---
id: ADR-0019
title: "ADR-0019: `dispatchMode` split from `deliveryMode`"
summary: "Split Shop.dispatchMode (MANUAL/BROADCAST) from deliveryMode (who is eligible) so a SELF-fleet shop can enable automatic rider broadcast without being forced into the shared platform-wide rider pool."
type: decision
status: accepted
apps: [backend, rider, web]
module: rider-app
anchors:
  - { repo: "ninja delivery service java", path: "src/main/java/com/example/ninja/entity/Shop.java" }
  - { repo: "ninja delivery service java", path: "src/main/java/com/example/ninja/service/impl/ShopServiceImpl.java" }
  - { repo: "ninja delivery service java", path: "src/main/java/com/example/ninja/service/impl/RiderServiceImpl.java" }
  - { repo: "ninja delivery service java", path: "src/main/java/com/example/ninja/listener/DeliveryDispatchListener.java" }
  - { repo: "ninja delivery service java", path: "src/main/java/com/example/ninja/listener/DeliveryRiderNotificationListener.java" }
verified_against: "7d9bcb4"
updated: 2026-08-06
---

# ADR-0019: `dispatchMode` split from `deliveryMode`

## Context

`Shop.deliveryMode` (PLATFORM | SELF | NONE) answered one question — which rider pool a shop draws
from — but it was also, silently, the only switch controlling whether that shop's riders got
notified of anything at all. `DeliveryDispatchListener` and `acceptDelivery` both gated on
`deliveryMode == PLATFORM`; a `SELF` shop got zero notification behaviour of any kind, for its own
dedicated fleet or otherwise.

This meant a shop with its own riders, wanting nothing more than "ring my rider's phone when staff
assigns them a delivery," had exactly one way to get it: set `deliveryMode = PLATFORM`. That flag
has real side effects beyond notification — it opens the shop's orders to the shared platform-wide
rider pool (via zone membership) and enables rider self-accept on a first-tap-wins race. A shop
that just wanted its own rider notified would, as a side effect, also start sharing orders with
riders who don't work for it.

The two concerns — **who the eligible riders are** (deliveryMode) and **whether/how they get
notified** (a separate axis) — were conflated into one field with no way to want one without the
other.

## Decision

**Add `Shop.dispatchMode` (MANUAL | BROADCAST) as an independent field.**

- `deliveryMode` keeps deciding *who* is eligible: `SELF` → the shop's own fleet only, `PLATFORM` →
  own fleet ∪ zoned platform riders, `NONE` → nobody.
- `dispatchMode` decides *how dispatch fires*: `MANUAL` → staff pick a rider by hand (existing
  flow, unchanged), `BROADCAST` → the automatic first-accept-wins push to every eligible online
  rider at once (`DeliveryDispatchListener`, on the order reaching READY).
- Both gates in the broadcast/accept path moved from checking `deliveryMode == PLATFORM` to
  checking `dispatchMode == BROADCAST`. A **narrow** `resolveDispatchRiders(shopId)` method was
  added specifically for this path — it still branches internally on `deliveryMode` to decide *who*
  (SELF → own fleet, PLATFORM → union, NONE → empty), so a `SELF + BROADCAST` shop broadcasts to
  its own fleet only, never to the shared pool.
- The existing **wide** `resolveEligibleRiders` (backing the staff "see & call" contact list) was
  deliberately left untouched — that list is meant to show every online rider regardless of
  BROADCAST/MANUAL, so staff always have a manual fallback.
- Backfill is **derived per-shop**, never a blanket default: existing `PLATFORM` shops get
  `dispatchMode = BROADCAST` (preserves their exact current behaviour), everything else gets
  `MANUAL`. A constant default in either direction would have silently changed live shops' behaviour
  on deploy.
- `dispatchMode` is normalized to `MANUAL` whenever `deliveryMode` resolves to `NONE` — a
  `NONE + BROADCAST` combination is never a reachable stored state (same reasoning as the `Rider`
  entity's own `@Check` pairing `riderType` with `shopId`).
- A separate, parallel gap was closed in the same change: staff assignment (`assignDelivery`/
  `reassignDelivery`) previously validated a rider was active and online but never that the rider
  actually belonged to (or was zoned to cover) the target shop — a shop's staff could assign
  another shop's dedicated rider. Not directly part of this ADR's question, but surfaced by the
  same audit and fixed alongside it (`requireRiderCoversShop`).

## Consequences

- A `SELF` shop can now get its own fleet's phones ringing on broadcast without misrepresenting
  itself as `PLATFORM` — no forced trade-off between "get notified" and "share orders with the
  shared pool."
- Two independent booleans (well, one 3-value + one 2-value field) instead of one field doing two
  jobs — slightly more surface area, but each value is now honest about what it controls.
- New rider-facing notification types, `DELIVERY_ASSIGNED`/`DELIVERY_REVOKED`
  (`DeliveryRiderNotificationListener`), were added at the same time and are **not** gated on
  `dispatchMode` at all — a staff-assigned rider (any mode) gets notified on assignment, and a
  rider who loses a delivery (reassignment, cancellation, or the order itself being cancelled by
  the customer) gets notified too. These fill the gap the `dispatchMode` split exposed: MANUAL
  dispatch previously had zero notification of any kind.
- `deliveryMode`'s only two remaining reads become genuinely just "who is eligible" questions —
  `dispatchMode` is the honest single source of truth for "does the broadcast fire."

## Enforced in

`Shop.dispatchMode` + `DispatchModeBackfillRunner` (backend, derived backfill) +
`ShopServiceImpl.normalizeDispatchMode` (forces MANUAL on NONE, both create and update paths) +
`RiderServiceImpl.resolveDispatchRiders` (narrow, mode-aware) + both gates in
`DeliveryDispatchListener`/`DeliveryServiceImpl.acceptDelivery` + `DeliveryServiceImpl
.requireRiderCoversShop` (ownership validation) + `DeliveryRiderNotificationListener`
(DELIVERY_ASSIGNED/REVOKED push, mode-independent). Admin UI in both `Ninjasu_Web` (ShopForm,
ShopDetail, ShopSettings) and `Food-Ninja-Frontend` (shop-form) exposes the field. Rider app
(`messageHandlers.ts`/`pushSetup.ts`) handles the two new push types on a new `"delivery-updates"`
channel, separate from the existing `"delivery-offers-urgent"` full-screen broadcast alarm.

Related: [ADR-0013](ADR-0013-rider-live-tracking-poll-not-websocket.md),
[ADR-0015](ADR-0015-rider-single-active-on-duty-device.md). Full build/review trail: memory
`project_rider_assign_notification_plan`.

**Status note (2026-08-06):** merged to `main` and deployed to production in all 4 repos on
explicit request, without the device verification called for in `handover.md` §4/roadmap Phase 1
ever having happened. This decision is accepted on its merits; the *rollout* carried a known,
accepted risk — see handover.md for the live status.

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
