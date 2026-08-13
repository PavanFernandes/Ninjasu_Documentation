---
id: ""
type: how-to
status: active
apps: [rider, customer, web]
module: "rider"
anchors:
  - { repo: "ninja delivery service java", path: "src/main/java/com/example/ninja/listener/DeliveryDispatchListener.java" }
  - { repo: "ninja delivery service java", path: "src/main/java/com/example/ninja/config/DeliveryOrderUniqueIndexRunner.java" }
  - { repo: "ninja delivery service java", path: "src/main/java/com/example/ninja/service/impl/RiderServiceImpl.java" }
  - { repo: "Ninjasu_Rider_App", path: "src/features/notifications/lib" }
verified_against: "1d85a2b"
updated: 2026-07-30
---

# Rider App — Phase 3 Plan (Rider ID, Zones, Missions, Live Tracking, Standalone)

**Date:** 2026-07-30 · **Status:** reviewed — devil's-advocate + market passes folded in (§9)
**Supersedes status claims in:** `project_rider_dispatch_plan` memory, `rider-dispatch-plan.md` §Status (both stale)
**Handover entry points:** [handover.md](./handover.md) · [implementation-roadmap.md](./implementation-roadmap.md)

> This is the **technical** layer — findings, risks, and reasoning. For the non-technical overview
> read `handover.md`; for sequenced work read `implementation-roadmap.md`.

---

## 0. Audit correction — most of this is ALREADY BUILT

The memory and the old plan doc both said "NOT built" / "uncommitted". Both are wrong as of today.
Verified against code + git this session:

| User's ask | Actual state | Evidence |
|---|---|---|
| Rider login/signup | **BUILT** | `Ninjasu_Rider_App/app/(auth)/{login,signup,verify}.tsx`; backend `POST /riders/signup` upsert-by-phone |
| Zones built properly? | **BUILT + committed** | `DeliveryZone/DeliveryZoneShop/DeliveryZoneRider` entities; backend commit `a4723d7` |
| Admin zone screens | **BUILT + committed** | `Ninjasu_Web/src/app/(admin)/admin/delivery-zones/{,new,[id]/edit}`, `admin/riders` |
| Order → rider notified | **BUILT** | `DeliveryDispatchListener` (AFTER_COMMIT + REQUIRES_NEW + try/catch, READY + DELIVERY + PLATFORM-gated) |
| Prevent double-pick | **BUILT, and done well** | `DeliveryOrderUniqueIndexRunner` — *partial* unique index `WHERE status NOT IN (DELIVERED,CANCELLED,FAILED)`, deliberately partial so `reassignDelivery()` still works |
| Rider accept UI | **BUILT** | `app/(rider)/offer/[orderId].tsx` — 409 → "Already taken" |
| Push/ring infra | **BUILT** | `messageHandlers.ts`, `pushSetup.ts`, data-only FCM → notifee alarm; `google-services.json` present |
| Rider posts location | **BUILT** | `POST /api/rider/location`, 8s foreground ping (`PING_MS = 8000`) |
| Customer tracks rider | **NOT BUILT** ← real gap | `DeliveryTrackingController` exists; **nothing in the customer app calls it** |
| Rider ID | **NOT BUILT** (UUID only) | `Rider.id` UUID, `Rider.userId` unique |
| Per-shop zone assign | **PARTIAL** — API is zone-centric only | no shop→zones read endpoint |
| "Missions" wording | **NOT BUILT** | zero occurrences in rider app |
| Standalone/multi-tenant | **NOT BUILT** | single-tenant throughout |
| Earnings view | **DEFERRED** by decision | payout formula undefined; `rider_payout_amount` left NULL |

### 0.1 PRIORITY ZERO — the rider app is entirely untracked in git

`git status` in `Ninjasu_Rider_App` shows **every** file as `??` (untracked): `app/`, `src/`,
`constants/`, `package.json`, `google-services.json`, `.env`. The repo has exactly one commit
(a docs-routing commit). A single `git clean -fd` destroys the whole app.

**Action before any new code:** commit the rider app. Confirm `.gitignore` covers `.env*` and
decide explicitly on `google-services.json` (it is not a secret — it's a client config — but it
identifies the Firebase project, so it's normally committed for RN apps; `.env` must NOT be).

Also verified closed: the "customer app doesn't show `delivery_otp`" blocker from memory is
**fixed** — `OrderTrackingScreen.tsx:152` renders it.

---

## 1. Rider ID — recommendation: YES, but not for the reason given

**The stated reason is false.** Zone assignment does not need a new ID — `delivery_zone_rider`
already joins on `riders.id` (UUID) and works today. Adding a rider code will not enable
anything that is currently blocked.

**The real reasons it's still worth adding** (industry-verified): Zomato surfaces an "FE ID"
(Fleet Executive ID) to its partners in the app under Profile, used for support calls, cash
reconciliation, payout statements and ID cards. A UUID cannot be read aloud over a phone call.
This is an **operations** feature, not a routing one.

### Two options

| | A. UUID-derived code | B. Sequence-backed serial (**recommended**) |
|---|---|---|
| Format | `RID-A3F2C9` | `NJ-R-00042` |
| Infra | Reuse `util/Ref.java` | Plain Postgres `SEQUENCE` |
| Collision risk | **~53% at 5,000 riders** (see below) | None (DB-guaranteed) |
| Contention | None | None (a sequence is not a row lock) |
| Ops feel | Opaque, 6 hex chars to read aloud | "Rider 42" reads nicely |

**Recommendation: B — reversed by the devil's-advocate pass.** Option A was the initial
recommendation and is wrong at scale: 6 hex chars is a 16.7M space, and the birthday bound
`1 - e^(-n²/2N)` gives a **~53% collision probability at 5,000 riders**. With the `UNIQUE`
constraint this design requires, rider signup would start failing intermittently in the low
thousands. Widening to 8 hex chars drops it to ~0.29% but makes the code harder to read aloud —
which was the entire point of having one.

Gaplessness is a *financial-document* requirement (GST bill numbers), so a plain `SEQUENCE`
suffices — no row-locked `ShopCounter` needed, gaps are fine, and there's no contention.

Schema: `riders.rider_code VARCHAR(16)` + `UNIQUE`, populated at profile creation, plus a
backfill runner for existing rows (same pattern as `RiderTypeBackfillRunner`). Surface it in
`RiderProfileDto`, the rider app profile header, and `RiderAdminDto` for admin search.

---

## 2. Zones — verified working, with one real design gap

**Verified:**
- `rider_type` CHECK constraint present — `Rider.java:22`, `@org.hibernate.annotations.Check`
- Index `idx_riders_shop_online` present (F4' satisfied) — `Rider.java:27`
- `resolveEligibleRiders(shopId)` defined **once** in `RiderServiceImpl:161`, unions restaurant
  riders + platform-riders-in-covering-zones, dedups via `LinkedHashMap`. Reused by both the
  dispatch listener and the see-and-call screen. Correct.

**Gap 2a — the CHECK has a NULL escape hatch.** The constraint ends `OR rider_type IS NULL`,
which permits a row with NULL type and any `shop_id`. Almost certainly there to let
`ddl-auto=update` add the constraint before the backfill runs. After backfill it should be
tightened to `NOT NULL` + drop the NULL branch.

**Gap 2b — a zone has no geography at all.** A zone is a hand-picked list of shops. It routes
by **shop**, never by **drop address**. Consequence: a platform rider in "HSR Zone" can be
broadcast an order whose delivery address is 20 km outside HSR, and nothing rejects it. The zone
constrains where the rider *picks up*, not where they must *go*.

Industry practice (delivery.com's API exposes `polygon`, `zipCode`, and `radius` zone types;
polygon is standard for last-mile) suggests real geometry eventually. But polygons need a
drawing tool in admin, which is a real build.

**Recommendation:** keep the manual shop-list (it works, and it's honest about being an
operational grouping). Add a cheap **drop-distance guard** at dispatch: skip the broadcast, or
flag it, when the delivery address exceeds a per-zone `max_drop_km`. Defer polygons. If geometry
is ever needed, **pincode list is the cheapest India-appropriate upgrade** (pincode boundary data
is published on AIKosh) — not PostGIS polygons.

---

## 3. Per-shop zone assignment in admin (the explicit ask)

Today the API and UI are **zone-centric**: open a zone, add shops to it. The ask is
**shop-centric**: open a shop, assign its zone(s).

Same M:N table, no schema change. Needed:
- Backend: `GET /api/admin/shops/{shopId}/delivery-zones` (which zones cover this shop). Reuse
  the existing add/remove endpoints for writes.
- Web: a "Delivery zones" multi-select on the shop edit page, reusing
  `delivery-zone.service.ts`.

Keep both directions — zone-centric is better for bulk setup, shop-centric for onboarding one shop.

---

## 4. Dispatch loop — built, but four risks worth fixing

**4a. Google Play revoked full-screen-intent for our category (severity: high).**
Play policy effective **22 Jan 2025** revokes `USE_FULL_SCREEN_INTENT` from any app that is not a
dialer, messenger, or alarm clock — and the system **silently downgrades** FSI to a heads-up
banner rather than erroring. A delivery app does not qualify. This affects the rider offer ring
**and the already-shipped shop order-alarm** (`Food-Ninja-Frontend/app/order-alarm.tsx`).
→ Do not depend on FSI. Ring via a high-priority notification + looping custom sound + vibration
+ ongoing notification. Treat the full-screen takeover as a bonus that may not fire.

**4b. Data-only FCM can be withheld during Doze (severity: medium-high).**
The current design is data-only FCM → app builds a local notifee alarm. Multiple reported cases
show the background handler not being invoked until the device exits Doze, even at high priority.
A rider's phone idle in a pocket is exactly Doze.
→ Send a **hybrid** message: a real `notification` block (so the system displays it with no app
code) **plus** the data payload (for the alarm upgrade when the app can run). Never rely solely
on app-side rendering for the one notification the business depends on.

**4c. Device tokens are not scoped per client app (severity: medium).**
`DeliveryDispatchListener:73` does `deviceTokenRepository.findByUserIdIn(riderUserIds)` — every
token for that user, regardless of which app registered it. A rider who is also a customer gets
the rider offer pushed to their customer-app install. Also ignores ADR-0015's `activeDeviceId`,
so an off-duty second phone rings.
→ Add an app/client discriminator to `DeviceToken` (e.g. `client=RIDER|CUSTOMER|SHOP|WEB`) and
filter on it. This is a shared multi-client-backend concern, not rider-only.

**4d. Riders already on a delivery still get broadcast.** `resolveEligibleRiders` filters
`is_online` but not "already has an active delivery." Batching was allowed day one, so this may
be intentional — but it should be a *decision*, and probably a cap (e.g. max 2 concurrent).

---

## 5. "Missions" — cosmetic UI rename

Ninja-theme framing: a delivery is a **Mission**. **UI strings only.**

Hard rule: do **not** rename `Delivery`/`deliveries`, `DeliveryStatus`, any endpoint, DTO field,
or DB column. A cosmetic rename that leaks into the contract creates a permanent
vocabulary-mismatch tax across four repos.

Implementation: a single `constants/copy.ts` in the rider app mapping domain → mission language
(`Accept delivery` → `Accept mission`, `Deliveries` → `Missions`, `Delivered` → `Mission
complete`). One file to review, one file to revert. Customer-facing and admin copy stay literal
("delivery") — the ninja framing is for riders only.

---

## 6. Live tracking, Neon-optimized (the main new build)

### 6.1 The Neon constraints that shape this

- **LISTEN/NOTIFY is unusable.** Neon scales to zero after ~5 min idle and *ends sessions*;
  listeners and notifications live only for the session. Ruled out as a realtime bus.
- **Compute is billed on active time.** A steady write trickle keeps compute awake — that's
  fine during trading hours (it would be awake anyway) but means overnight pings are pure cost.
- **HOT updates already work here, keep it that way.** `rider_live_locations` is PK=`rider_id`
  with **no index on `lat`/`lng`/`recorded_at`**, so the UPSERT is heap-only. Adding an index on
  `recorded_at` would silently destroy this. Set `fillfactor = 80` on the table to leave in-page
  room for HOT.

### 6.2 The pipeline

**Rule: customer polling must never reach Postgres.**

```
rider app ──8s──> POST /api/rider/location
                      │
                      ├─> in-process cache (authoritative for reads)   ← every read served here
                      └─> write-behind to Neon every ~30-60s           ← crash-recovery fallback only

customer app ──5s──> GET /api/deliveries/{id}/location  ──> cache only
```

Effect: rider writes to Neon drop from 7.5/min to ~1-2/min per active delivery, and customer
reads hit Neon **zero** times. Staleness rule (>120s ⇒ unavailable, per ADR-0013) is preserved
because the cache holds `recordedAt`.

**Blocking caveat — this breaks on more than one backend instance.** An in-process cache is
per-JVM: rider writes land on instance A, the customer polls instance B, sees nothing. Before
building, confirm the deployment is single-instance. If it ever scales out, this needs Redis.
That is a real fork in the road, not a detail.

**Keep polling, don't switch to WebSocket.** ADR-0013 already chose REST + poll + client-side
interpolation, and the user's objection ("nothing constantly polling") is really about *Neon
load* — which the cache removes entirely. Client-side polling of a memory cache is cheap,
survives flaky mobile networks better than a socket, and needs no new infra. ADR-0013 stands.

### 6.3 Customer-side build (genuinely missing)

Nothing in the customer app calls the tracking endpoint. Build: a map on
`OrderTrackingScreen` showing the rider marker, shown only while `OUT_FOR_DELIVERY`, with
interpolation between polls and a graceful "location unavailable" state when stale.

### 6.4 Background GPS is still the unsolved hard part

Pings currently fire only while the delivery screen is open **and** the app is foregrounded. A
rider who pockets their phone stops transmitting — which is the normal case. A real foreground
service is required, and that needs an EAS dev build (it cannot work in Expo Go). This is the
single biggest gap between "demoable" and "usable."

---

## 7. Standalone / white-label logistics product

Market reality: Onfleet is ~$0.25/task with tiered plans; Tookan starts ~$58-99/mo for a small
agent count with per-task overage and offers white-label branded tracking pages. The expected
minimum feature set is driver app + dispatcher dashboard + customer tracking link +
proof-of-delivery + API/webhooks.

**Recommendation: do not build multi-tenancy now.** It is a product pivot, not a feature — it
implies tenant isolation, per-tenant branding, self-serve onboarding, billing, and an API
surface for third parties. Building it speculatively while the first-party loop still can't
survive a pocketed phone would be backwards.

**But make two cheap decisions now that avoid a rewrite later:**
1. **Don't hard-code Ninjasu branding into rider-app components.** Keep colors/labels/logo in
   `constants/` (already true for colors) so a theme swap is config, not a refactor.
2. **Keep the delivery domain free of food-specific coupling.** `Delivery` already references
   `orderId` nullably with no FK — preserve that. The moment delivery logic reads menu/cart
   concepts, the standalone story dies.

Revisit only when a third party has actually asked to pay.

---

## 8. Phasing

| Phase | Content | Why this order |
|---|---|---|
| **0** | **Commit the rider app.** Verify `.gitignore` covers `.env*`. | Everything else risks total loss until done |
| **1** | Device-verify the existing loop end-to-end on a real phone (signup → online → order READY → ring → accept → pickup → OTP+cash complete) | It's all built and never run on a device. Find out what's actually broken before adding to it |
| **2** | **Visibility fixes (cheap, prevent "it's broken" reports):** admin warning for PLATFORM-mode-shop-with-no-zone (M-RF1) · staff alert for READY-with-no-delivery (M-S2) · broadcast idempotency guard (D5) | Every one of these turns a silent failure into a visible one. Highest value per line of code in the whole plan |
| **3** | Push hardening: hybrid notification+data with dedup (D6/§4b), drop FSI dependence (§4a), `DeviceToken.client` scoping with NULL-transition (D3/§4c) | The dispatch loop's reliability *is* the product |
| **4** | Live tracking: cache layer + write-behind + customer map + `fillfactor=80` | The explicit ask; **blocked on the single-instance answer** |
| **5** | Rider code (`NJ-R-` sequence), per-shop zone assign, "Missions" copy layer, `last_seen_at` (M-S3) | Independent, low-risk, ship anytime |
| **6** | Background foreground-service GPS (needs EAS dev build) | Biggest effort; gates real-world usability *and* any tracking demo |
| **Deferred** | Earnings view (payout formula), polygons/pincode zones, multi-tenancy, masked calling (M-S4), sequential/ranked dispatch | Explicitly parked — see triggers below |

**Revisit triggers for deferred items** (numeric, not subjective):
- **Sequential/ranked dispatch:** when any zone exceeds **~5 online riders**. Not "when riders
  complain about noise" — by then customers have been getting slower deliveries for months (M-S1).
- **Masked calling:** before any marketing push that materially grows order volume.
- **Multi-tenancy:** only when a third party has actually offered to pay.

---

## 9. Findings folded in from the two review passes

Devil's advocate (`D*`) and market scout (`M-*`, full detail in
`Ninjasu_Rider_App/agents/market/rider-dispatch-scout.md`):

| # | Finding | Where it landed |
|---|---|---|
| D1 | 6-hex rider code collides ~53% at 5k riders | §1 recommendation reversed to a sequence |
| D2 | Cache-vs-table two-sources-of-truth; unbounded cache growth | §6.2 conditions: persist true `recorded_at`, column comment, TTL eviction |
| D3 | `DeviceToken.client` filter would silently kill dispatch for all existing tokens (NULL semantics) | Phase 3: NULL = match-any transition window |
| D4 | Per-zone `max_drop_km` duplicated across zones; silent skip | Platform default + optional override; must log **and** surface to staff |
| D5 | Broadcast not idempotent — re-READY re-rings everyone | Phase 2 guard |
| D6 | Hybrid push can double-notify or silently degrade the ring | Phase 3: explicit dedup + verify under real Doze |
| M-S1 | Broadcast optimises for fastest tapper, not nearest rider | Numeric revisit trigger (>5 riders/zone) |
| M-S2 | **Riders-online-but-all-ignored is indistinguishable from nobody-online**; order sits at READY with no alert | Phase 2 — highest-severity operational gap |
| M-S3 | "Online" is unverified self-declaration; no idle location, no heartbeat, no acceptance rate | Phase 5 `last_seen_at`; also blocks any future ranking |
| M-S5 | **Unbounded COD cash exposure per rider** — reconciliation is after-the-fact, no preventive cap | Launch-blocker candidate — see decision 5 |
| M-RF1 | PLATFORM shop in no zone = totally silent no-op that looks like a broken feature | Phase 2 admin warning |

---

## 10. Open decisions for the user

1. **Is the backend single-instance?** Gates the entire §6.2 cache design. If it ever scales out,
   an in-process cache silently breaks (rider writes to instance A, customer polls instance B) and
   the design needs Redis instead.
2. **Rider code format** — `NJ-R-00042` sequence (now recommended) or 8-char `RID-A3F2C901`?
3. **Concurrent-delivery cap per rider** — unlimited (current behaviour), or max N?
4. **Drop-distance guard** — add it with a platform-level default, or accept unbounded drops for now?
5. **COD exposure cap (M-S5)** — is a max-outstanding-cash limit per rider a launch blocker, or an
   accepted risk for the initial small trusted fleet? This is a money-loss question, not a
   technical one, so it needs an explicit call.
