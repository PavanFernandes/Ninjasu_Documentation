---
id: ""
title: "Rider App — Implementation Roadmap"
summary: "Phased DECIDE-vs-BUILD roadmap (Phase 0-7) for the rider app: device-verifying the dispatch loop, surfacing silent failures, push reliability, live tracking, and background location."
type: how-to
status: active
apps: [rider, customer, web]
module: "rider"
anchors:
  - { repo: "Ninjasu_Rider_App", path: "app" }
  - { repo: "ninja delivery service java", path: "src/main/java/com/example/ninja/service/impl/DeliveryServiceImpl.java" }
verified_against: "cc1ce62"
updated: 2026-08-06
---

# Rider App — Implementation Roadmap

Companion to [handover.md](./handover.md) (read that first — it has a 2026-08-06 device-verification
update). Technical detail and review findings: [rider-dispatch-phase3-plan.md](./rider-dispatch-phase3-plan.md).

> ✅ **Phase 1 partially complete, 2026-08-06.** The assign/revoke half of the loop (steps 1-2 of §2
> in handover.md, roughly) is now device-verified — including the order-decline cascade, which
> surfaced and got 2 real bugs fixed same-day (notification channel registration, a refund-callback
> 500). **The broadcast/first-accept-wins half (steps 3 onward — the actual "phone rings when an
> order goes Ready" loop) is still completely unverified** — the test shop used had no zone/online
> platform rider to exercise it. Treat that specific loop as still pre-launch-blocking; the
> assign/revoke half as debugging-a-live-feature, not qualifying one for launch.

## How this roadmap is meant to be used

Every phase is split into two columns:

| 🧠 DECIDE (Samivan) | 🔨 BUILD (implementer) |
|---|---|
| Costs money, picks a vendor, changes architecture, or trades off business risk. Must be answered **before** the build column starts. | Fully specified. No architectural or spending choice left in it. |

**Rules of engagement**
- A phase's BUILD column does not start until its DECIDE column is answered. If a decision is
  outstanding, work a different phase — do not guess.
- If a BUILD task turns out to need a decision, that is a **mis-scoped task**. Stop, escalate, move
  on. Do not decide it locally.
- Phases 0-2 have almost no decisions in them on purpose, so implementation can start immediately
  while the expensive decisions are still being thought about.
- **Do not reopen anything in handover.md §5** (locked decisions).

**Definition of done for every BUILD task:** backend `./mvnw compile` clean · apps `npx tsc --noEmit`
**and** `eslint` clean (type-checking alone has silently missed real violations before) · verified on
a real device where the task touches the app · `code_map.md` updated if a new file was created.

---

## Phase 0 — Save the work ✅ DONE (stale section, kept for history)

Was: the rider app was entirely untracked in git, one cleanup command from total loss. As of
2026-08-06 the repo has real committed history on `main` — this no longer blocks anything.
Not independently re-verified whether `.env`/secrets are correctly gitignored.

---

## Phase 1 — Find out what actually works 🔴

Everything in the loop is written but has never run on a phone. This phase produces *information*,
not features. Do not fix anything beyond making the journey complete; log what breaks and triage
after.

| 🧠 DECIDE | 🔨 BUILD |
|---|---|
| Nothing. | Run the complete §2 journey from handover.md on a real Android phone, end to end, and write down every failure. |

**Setup needed:** a test shop set to PLATFORM mode, placed in a delivery zone, with a test rider in
that same zone. A standing dev account exists (see memory `project_dev_test_account`); dev login code
is always `1234`.

**The pass condition — every step, in order:**
1. Rider signs up → gets code → enters vehicle details → reaches home
2. Rider goes online
3. Test customer places an order at the test shop
4. Shop marks it Accepted → Preparing → Ready
5. **Rider's phone rings** ← the most likely thing to fail
6. Rider taps Accept and reaches the delivery screen
7. A *second* rider taps Accept and correctly sees "Already taken"
8. Rider taps Picked Up → **the customer's app shows the 4-digit code**
9. Rider taps Out for Delivery
10. Rider enters the code + cash amount → delivery completes
11. Customer's order shows Delivered

**Expected trouble spots, so they aren't a surprise:** the ring in step 5 (Android policy + power
saving); the notification not opening the right screen when the app is fully closed; the code in
step 8 not appearing if statuses don't sync.

**Output:** a written list of what broke. That list re-prioritises everything below.

**Also now in scope (2026-08-06, shipped after this phase was written):** a `MANUAL`-dispatch shop
assigning a rider by hand should make that rider's phone show a quiet notification
(`DELIVERY_ASSIGNED`) and open the delivery screen; reassigning or cancelling should notify the
rider who lost it (`DELIVERY_REVOKED`) on a separate, non-alarm channel from the broadcast ring in
step 5. Neither has been observed on a real device. See [ADR-0019](../01-Architecture/decisions/ADR-0019-dispatch-mode-vs-delivery-mode.md).

---

## Phase 2 — Turn silent failures into visible ones 🟠

Highest value per line of code in the whole roadmap. These are the bugs that make a working system
*look* broken and burn a demo. All small, all independent, no decisions needed.

| 🧠 DECIDE | 🔨 BUILD |
|---|---|
| Nothing — all three are pure "surface the problem" work. | **2a.** Admin warning when a shop is PLATFORM mode but in no zone. Show it on the shop page and the zones page. Today this configuration is a completely silent no-op.<br><br>**2b.** Alert staff when an order has been Ready with no rider for more than N minutes (start with 10). Surface on the shop order board. This is the only cure for "every rider ignored it," since dismissing an offer writes nothing.<br><br>**2c.** Stop re-broadcasting an order that already has a rider. If an order re-enters Ready, every phone rings again and everyone gets "already taken." Add an early exit mirroring the check the accept endpoint already does. |

---

## Phase 3 — Make the ring trustworthy 🟠

The notification *is* the product. If it doesn't ring, nothing else matters.

| 🧠 DECIDE | 🔨 BUILD |
|---|---|
| **Accept that the full-screen ring is best-effort?** Android restricts full-screen alerts to phone/messaging/alarm apps since Jan 2025 and downgrades silently. There is no compliant workaround for a delivery app. *(Recommendation: accept it. Make a loud, repeating, hard-to-miss ordinary notification the guaranteed floor, and treat the full-screen takeover as a bonus.)* | **3a.** Send the notification so the phone shows it **even if the app cannot run** — currently it relies on app code executing, which power-saving can delay. Then make sure the rider does not get *two* alerts.<br><br>**3b.** Label device notification tokens by which app registered them. Right now a rider who is also a customer gets delivery offers on their customer app. **Critical migration note:** existing tokens have no label, so filtering strictly on it would stop offers for every already-registered rider. Treat unlabelled as "matches anything"; tokens re-register on each app launch, so unlabelled ones disappear on their own. Only tighten afterwards.<br><br>**3c.** Verify under real power-saving conditions (`adb shell dumpsys deviceidle force-idle`), not on an emulator. |

---

## Phase 4 — Live tracking 🟡

The customer-facing feature you actually want, and the one with a real cost dimension.

**D1 answered 2026-07-31 — backend is single-instance.** 4a/4b below are unblocked and **built**.
4c (the actual map) is still gated on D2 and D3.

| 🧠 DECIDE | 🔨 BUILD |
|---|---|
| ~~D1. Single instance?~~ **✅ Confirmed single-instance.** Re-check this before ever scaling out — the cache is per-JVM and breaks silently, not loudly, across instances. | **4a. ✅ BUILT 2026-07-31** — `cache/RiderLocationCache.java` (Caffeine, 10-min TTL to bound memory, NOT a staleness signal). Every ping updates the cache; only some pings also reach Postgres — the cache decides which, based on how long since this rider was last flushed (45s), so an 8s ping cadence does not become an 8s write cadence to Neon. Wired into `postLocation` (write) and `getDeliveryLocation` (cache-first read, DB fallback for cold-start/eviction). |
| | **4b. ✅ BUILT 2026-07-31** — `RiderLocationFillFactorRunner` sets `fillfactor=80` on `rider_live_locations` at boot (raw DDL — Hibernate has no annotation for storage parameters). **Never add an index on lat/lng/recorded_at** — the table already has none, which is what keeps the per-rider upsert a HOT update; an index there would silently defeat this. |
| ~~D2. How fresh must the map be?~~ **✅ Decided 2026-07-31: 15s.** Correction to the earlier framing: refresh interval is **not** a real cost lever for either map provider — neither bills per marker update, only Google Maps SDK (per map *load*, i.e. per screen open) does; the backend cost is already near-zero thanks to the cache (4a). 15s was chosen purely on feel, not cost. **D3. Map provider — the real remaining cost decision.** Google Maps bills **per map load** (10,000 free/month, then $2–$7/1,000) — cost scales with how many *times* tracking is opened. Mapbox bills **per monthly active user** (25,000 free MAUs/month) — cost scales with how many *distinct customers* open tracking at all that month, regardless of repeat opens. Consequence: if customers reorder often, Mapbox can work out cheaper (10 opens by 1 repeat customer = 10 Google loads but still 1 Mapbox MAU); if most customers are one-time, Google's free tier likely wins. Needs your repeat-order rate to model properly. | **4c-prep. ✅ BUILT 2026-07-31** — the customer-side discoverability gap (tracking screen only knows its own orderId, same class of gap Phase 4b fixed on the staff side) is closed: `GET /api/deliveries/for-order/{orderId}` (`DeliveryTrackingController.deliveryIdForOrder`) plus ready-to-call frontend functions `getDeliveryIdForOrder`/`getDeliveryLocation` in `orders.service.ts`. **No screen uses them yet.**<br><br>**4c. Not started — blocked on D3 only.** Show the rider on a map in the customer's order screen while out for delivery at a 15s poll, smoothing movement between updates, with a clear "location unavailable" state when data is stale (over 120 seconds, per ADR-0013). The fetch plumbing is ready; only the SDK choice and the screen itself remain. |

**Why polling is fine here:** the objection to polling was database load, and the cache removes it
entirely — customer requests never reach Postgres. ADR-0013's decision stands.

**Not device-verified yet.** Compiles clean; the cache logic has not been exercised against a real
rider phone posting pings over an actual delivery.

---

## Phase 4b — Delivery audit timeline ✅ BUILT 2026-07-30

Added ahead of the roadmap because history cannot be backfilled — every delivery before it shipped
has its story permanently lost. Backend complete and compiling; **not yet device-verified**.

- `delivery_events` — append-only log of what happened to each delivery and who caused it.
  **Status events only** (decision: location breadcrumbs deferred until Phase 6, because
  foreground-only GPS would persist a route with invisible gaps — worse than no route in a
  dispute; the table already carries nullable lat/lng so adding them later needs no migration).
- Records: creation (staff-assign vs rider self-accept), every status transition, cash collected
  with short-pay reason, staff OTP override, reassignment.
- **Structural change worth knowing:** delivery status was written at 7 separate call sites. All
  now go through a single `transitionTo()` that writes the status and its audit event together —
  so the log cannot be forgotten by a future 8th transition.
- Read: `GET /api/shops/{shopId}/deliveries/{id}/timeline` (SHOP-gated, membership + shop-ownership
  verified).

**UI built 2026-07-30 (Ninjasu_Web only):** a "View delivery" button on the shop order board
(shown for READY/OUT_FOR_DELIVERY/DELIVERED/CANCELLED orders — earlier statuses can never have a
delivery yet) opens a dialog rendering the timeline. Also added the missing link between the two:
`GET /api/shops/{shopId}/orders/{orderId}/delivery` — an order card only knows its own orderId,
not any deliveryId, so this new lookup is how the button finds one to open. Returns `null` (not a
404) when no delivery exists yet, which is a normal pre-READY state, not an error.

**Remaining:** the mobile seller panel (`Food-Ninja-Frontend`) has no equivalent button yet —
`ShopOrdersScreen.tsx` would need the same wiring. Not done, not blocking.

---

## Phase 5 — Small, independent wins 🟢

No dependencies. Good tasks for a gap or a second person.

| 🧠 DECIDE | 🔨 BUILD |
|---|---|
| **Rider ID format** — `NJ-R-00042` (recommended) or 8-character code? *(Note: a 6-character random code was rejected — it collides about half the time by 5,000 riders.)* | **5a.** Add a readable rider ID using a plain database sequence, shown in the rider's profile and admin search, with a backfill for existing riders.<br><br>**5b.** Let admins assign zones from a shop's own page. Same data, missing direction — a read endpoint plus a multi-select. Keep the existing zone-side direction too.<br><br>**5c.** "Missions" wording. **One file** mapping display text in the rider app only. Never rename anything in the API, database, or code — a cosmetic rename leaking into the contract is a permanent tax across four repos. Customer and admin wording stays "delivery".<br><br>**5d.** Record when each rider was last seen, updated on any authenticated request. Makes "online" falsifiable and is a prerequisite for ever ranking riders by distance. |

---

## Phase 6 — Background location 🟡

The largest single piece of work, and what stands between a demo and something usable. Riders pocket
their phones; today that stops location entirely.

| 🧠 DECIDE | 🔨 BUILD |
|---|---|
| **Confirm the switch to a custom build.** This needs a native background service, which cannot run in the standard Expo Go testing app. It changes how the app is built and tested from here on, and adds build time and cost. Also decide the battery-versus-accuracy trade — riders will complain about battery drain, and it is a real retention issue. | **6a.** A foreground service that keeps sending location while a delivery is active, with a persistent notification (Android requires one).<br><br>**6b.** Queue locations while offline and send them when signal returns — patchy coverage is normal.<br><br>**6c.** Handle the rider revoking location permission mid-delivery without crashing. |

---

## Phase 7 — Deliberately deferred

Do not start these without an explicit go-ahead. Each has a stated trigger.

| Item | Why deferred | Revisit when |
|---|---|---|
| **Rider earnings screen** | No payout formula has been decided, so there is nothing to display. Delivered records intentionally have no payout amount and will need backfilling once a formula exists. | Payout formula decided |
| **Nearest-rider assignment** | First-to-accept rewards the fastest phone, not the closest rider. Fine with a handful; genuinely wrong at scale. | **Any zone exceeds ~5 online riders** (numeric on purpose — waiting for complaints means months of slower deliveries first) |
| **Geographic zones** | Zones group shops, so nothing bounds drop distance. If needed, a postcode list is the cheapest option for India — not full map polygons. | Delivery distances become a complaint |
| **Masked phone numbers** | Riders currently get the customer's real number permanently. Competitors mask it; this is the most reputationally damaging failure mode in Indian delivery. Needs a paid telephony vendor. | Before any marketing push that grows volume |
| **Cash exposure cap** | See the decision below — may be promoted to launch-blocking. | Samivan's call |
| **White-label / selling the app to others** | A product pivot, not a feature. Two cheap habits keep the option open: keep branding in the constants file, and keep delivery logic free of food-specific concepts. | A third party offers to pay |
| Proof-of-delivery photo, in-app navigation handoff, SOS beyond a phone link, shift booking | Standard in the category, none launch-blocking | After launch |

---

## Decisions queue (Samivan's list, in the order they block work)

| # | Decision | Blocks | Cost dimension |
|---|---|---|---|
| 1 | Commit `google-services.json`? | Phase 0 | none |
| ~~2~~ | ~~Backend: one instance or several?~~ **✅ Answered 2026-07-31: single-instance.** | ~~all of Phase 4~~ 4a/4b done | none — no Redis needed |
| ~~3~~ | ~~Map refresh interval~~ **✅ Answered 2026-07-31: 15s.** | Phase 4c | negligible — not the cost lever it was framed as |
| 4 | Google Maps (per-load) vs Mapbox (per-MAU) | Phase 4c | needs your repeat-order rate to model properly |
| 5 | Accept that the full-screen ring is best-effort | Phase 3 | none |
| 6 | Rider ID format | Phase 5 | none |
| 7 | Move to a custom build + battery/accuracy trade | Phase 6 | build time and cost |
| 8 | **Cash exposure cap — launch blocker or accepted risk?** | Phase 7 | direct money-loss risk |
| 9 | Max deliveries a rider can hold at once | Phase 7 | none |
| 10 | Drop-distance limit | Phase 7 | none |

**Suggested order:** answer 1 and 5 immediately (both free, both unblock work today). Answer 2 next —
it is the largest architectural fork in the roadmap. Take time over 4, 7, and 8, which are the ones
that actually cost money.
