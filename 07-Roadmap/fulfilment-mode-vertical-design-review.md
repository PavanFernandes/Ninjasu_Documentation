---
title: "Fulfilment mode × vertical × menu-over-time — design review"
summary: "geld existing + devil's advocate + blind Codex pass (2026-11-15) on whether the Eat Now / Schedule model scales to groceries and to rotating menus. Status PROPOSED: awaiting decisions D1-D4."
type: design-review
status: FINAL — D1, D2 approved 2026-11-15; D4 owned by Samivan; D3 pending
module: schedule
apps: [backend, web, customer]
verified_against: "backend origin/feature/schedule b7ca8dc, origin/main (2026-11-15); web fix/delivery-cash-due-field; app feature/schedule-my-orders-groups"
updated: 2026-11-15
---

# Fulfilment mode × vertical × menu-over-time — design review

Question (Samivan, 2026-11-15): does "Eat Now" fit when groceries come; must restaurants keep re-adding dishes to the
Schedule menu; can a grocery item be delivered now or scheduled; is what is built scalable; static vs rotating menus.

Ran: geld (existing mode, lenses 0-3, 7 MODEL/INV/MONEY/EVOL/API), devil's advocate, 4 code investigators, a blind
read-only Codex pass, 22 adversarial verifiers (every finding below survived; corrections folded in). No database was
connected. No design-view artifact (skipped on purpose: artifact watches cost tokens).

## Summary (read this first)

Three questions are independent and the code should keep them independent:

| Axis | Question it answers | Values | Where it lives today |
|---|---|---|---|
| **Vertical** | what is sold | FOOD, GROCERY, PRODUCT | `CartType` (plus SCHEDULE, see MODEL-1), `orders.cart_type` |
| **Fulfilment mode** | when it is delivered | EAT_NOW (now), SCHEDULE (slot) | `FulfilmentType` (commission cards, fees, quotes); `CartType.SCHEDULE` (carts); `orders.group_id IS NOT NULL` (orders) |
| **Availability over time** | which days an item is offered | standing; "Today only" | `schedule_item_settings` (Schedule only); live toggles + daily stock (Eat Now) |

Answers:
1. **Mode name.** "Eat Now" is a food word; groceries need a neutral customer label. The stored code `EAT_NOW` is live in
   production (`commission_rate_card_assignment.fulfilment_type`, append-only with a CHECK, on main) and in append-only
   audit rows. Recommendation: keep the code, treat it as "deliver now, any vertical", change only labels (D2).
   "Instant" breaks the plan's messaging rule (no speed promises, schedule-plan §1).
2. **Re-adding dishes: no.** The Schedule menu is not a copy. `schedule_item_settings` is one row per existing item on the
   same `items` table; a dish switched on for every day stays on. Only "Today only" dishes lapse, and they come back
   with one tap, not a re-add.
3. **Grocery now-or-scheduled.** The overlay tables are vertical-agnostic (keyed by `item_id`), but the cart is not:
   `CartType.SCHEDULE` means "Schedule AND food". A scheduled grocery cart cannot be expressed without a
   `GROCERY_SCHEDULE` value (vertical × mode explosion). This was a recorded trade-off (2b.5 EVOL-1: "revisit if a
   second vertical gets Schedule"). The revisit is due now because the **app is about to put `type=SCHEDULE` on the
   wire** (Phase 4), and shipped app versions freeze it (D1).
4. **Scalable?** For the food pilot, yes. For grocery, four later additions are needed (area modes per vertical, slots
   per vertical, one stock pool for shelf goods, cutoff the evening before); all are additive, none blocked by today's
   schema. Two cheap fixes are due before any grocery shop goes live (MONEY-1, D4).
5. **Rotating menus.** Schedule covers "a kitchen that re-picks each day" (manually, the night before as every-day
   switches or the same day as Today only). It does not cover weekly rotation or menus planned for future dates; both
   can be added without changing existing tables. Eat Now has no rotation at all; a shared (item, mode) rule can be
   added beside it later. Nothing to build now.
6. **Found on the way:** `service_area.eat_now_enabled` is enforced nowhere. HSR "Schedule only" is not real: HSR
   restaurants will show in Eat Now home (radius discovery) and accept instant orders (D3).

## Must change (before the affected deploy)

| Id | Failure | Proposed change | Cost now |
|---|---|---|---|
| MODEL-1 (D1) | App Phase 4 sends `/api/cart?type=SCHEDULE` and `cartType: SCHEDULE` at checkout. When grocery is scheduled, the enum needs `GROCERY_SCHEDULE`; `chk_cart_type`, `chk_cart_sessions_shape`, the one-active-cart index, `FulfilmentPolicies.forCartType`, `vertical()` and ~15 `== CartType.SCHEDULE` checks branch on the combined value; old apps keep sending the old shape forever | Split the axes: `cart_sessions.fulfilment_type` (EAT_NOW / SCHEDULE, NOT NULL DEFAULT 'EAT_NOW'); `cart_type` = vertical only; unique active cart on (user, cart_type, fulfilment_type); shape CHECK keys on `fulfilment_type`; API takes `fulfilment` beside `type`; policy picked by `FulfilmentType`; drop `CartType.SCHEDULE` by expand-contract (Schedule carts are short-lived: abandon them in the migration) | Cheap→migration: `CartType.SCHEDULE` is only on `feature/schedule` (main has FOOD/GROCERY/PRODUCT); 10 main + 11 test files; app has no SCHEDULE yet. Rises with every Phase 4 slice |
| ACCESS-1 (D3) | Admin sets HSR to Schedule only; customers in HSR still see HSR restaurants in Eat Now home (radius discovery, `HomeServiceImpl` ignores the flag) and can order instantly; the app never reads `eatNowEnabled` | Enforce the mode server-side: Eat Now home/search, cart add and checkout resolve the delivery point's area and refuse when `eat_now_enabled` is false; a point outside every area keeps today's behaviour | Cheap: guards, no schema. Needed before the HSR pilot |
| MONEY-1 (D4) | A GROCERY/PRODUCT cart is quoted with **zero GST** (`OnlineOrderQuote` non-FOOD branch). Admin can already create a GROCERY shop (web `SHOP_TYPES`); its items are saved as FOOD shape and it never appears in discovery | Fail closed on any non-FOOD vertical (throw unsupported vertical) and update `groceryAndProductKeepCurrentTotals`; hide GROCERY/PRODUCT from shop creation until grocery is scoped | Cheap: one method + one test + one web constant; can go to main on its own |

## Trade-off (owner decides)

- **NAME-1 (D2): the mode code.** Options: keep `EAT_NOW` as the code (labels only); rename to `NOW` by expand-contract
  (accept both, disable the append-only trigger on purpose to rewrite rows, swap the CHECK; audit rows keep `EAT_NOW`
  forever, so readers accept both permanently); or two names (enum `NOW` serialised as `"EAT_NOW"`), which is one word
  for two things. Recommended: keep the code, document it as "deliver now, any vertical", labels per screen
  ("Deliver now" / "Schedule"; food copy may keep "Eat Now").

## Revisit (trigger named)

| Id | When | What |
|---|---|---|
| EVOL-2 | grocery scoped | `service_area_mode(service_area_id, vertical, fulfilment_type, enabled, fee, packaging, caps)` replacing the per-mode booleans and `schedule_*` columns; decide whether Eat Now moves onto service areas (today Eat Now = shop radius, Schedule = `shops.service_area_id`: two geographies) |
| EVOL-3 | first non-food slot | `service_area_slot.vertical` (or slot kind) and add it to `ux_service_area_slot_area_start`, else a 07:00 grocery slot is offered to lunch dishes |
| INV-1 | grocery Schedule | one stock pool for shelf goods: scheduled grocery reserves against `item_stock_ledger`; keep the separate Schedule pool for cooked food (D-11, correct for food). Same physical last unit sold twice otherwise |
| TIME-1 | ordering ahead (advance_days > 0) or a morning slot | cutoff the day before: `order_until_day_offset` or minutes-before-slot; today `order_until` can only fall on the delivery date |
| SIZE-1 | first catalogue > ~200 items | shop/category default "all active items schedulable, live stock as cap" in `schedule_shop_settings`, rows only for exceptions (3,000 SKUs = 3,000 single adds today; bulk only toggles existing rows) |
| MODEL-2 | first grouped non-Schedule mode | `orders.fulfilment_type` / `order_groups.fulfilment_type`; today `group_id IS NOT NULL` = Schedule and the DB enforces it (2b.4 SIMPLE-1) |
| EVOL-4 | pilot shows daily toggling hurts | weekday mask on `schedule_item_settings`, then a dated `(item_id, service_date)` override table; Eat Now rotation as a sibling `(item_id, fulfilment_type)` rule with its own pure resolver. Not the Schedule resolver (it carries area, slot, cutoff, stock rules) |
| INV-2 | any new availability reader | every Schedule reader goes through `ScheduleAvailabilityResolver`; never copy the live `is_available` checks (`CartServiceImpl:126`, `PosOrderServiceImpl:437`). Existing test: `ScheduleCartWriterTest:368` |
| LIVE-1 | live-menu track (not Schedule) | Eat Now ignores category `is_available` and shop opening hours for delivery; check cart guard + checkout re-validation |

## Keep

- **KEEP-1** Schedule as a per-item overlay on the same items (no menu copy, no daily re-add); standing settings
  replaced per-date menus on 2026-10-22 for reasons that still hold (comparables use reusable menus with a switch).
- **KEEP-2** Separate Schedule stock pool for food (D-11) and a separate Schedule add-on switch (D-5): deliberate.
- **KEEP-3** `FulfilmentPolicy` seam and `FulfilmentType` on commission cards: the right axis, already live.
- **KEEP-4** `orders.cart_type` stays pure vertical (Schedule orders store FOOD).

## Built state (cost evidence)

| Item | Code | On main / prod | Data |
|---|---|---|---|
| `FulfilmentType` EAT_NOW/SCHEDULE | yes | main (16 files), prod | commission assignment rows (append-only) + audit metadata |
| `CartType.SCHEDULE` | `feature/schedule` only | no | `cart_sessions` rows if the 2b.5 SQL ran (dev account only, MIG-3) |
| `service_area.eat_now_enabled` | yes | main | unknown |
| `schedule_item_settings` etc. | `feature/schedule` | no | schedule-menu SQL ran on Neon (2b.2) |
| app cart type | `'FOOD'\|'GROCERY'\|'PRODUCT'` | — | no SCHEDULE sent yet |

## Devil's advocate trace

| Proposal | Verdict |
|---|---|
| Rename EAT_NOW now because nothing is deployed | rejected: it is deployed (commission cards on main) |
| Generalise `schedule_item_settings` into an (item, mode) table now | rejected: no second mode needs it yet; additive later (EVOL-4) |
| Add `orders.fulfilment_type` now | rejected for now: 2b.4 SIMPLE-1 still holds; MODEL-2 trigger named |
| Split the cart axes (MODEL-1) | proceed with conditions: before app Phase 4 cart slices; reopens locked 2b.5 decision 2, needs Samivan |

## Doc drift

`schedule-plan.md` §7 2b still lists `orders.fulfilment_type NOT NULL default EAT_NOW` and §3.6 #43 says
`order_groups` carry `fulfilment_type`; 2b.4 removed both (SIMPLE-1). Fixed 2026-11-15 (struck through with the reason).

## Decisions

| # | Decision | Answer |
|---|---|---|
| D1 | MODEL-1 split cart vertical / fulfilment before app Phase 4 cart work | **Approved 2026-11-15 (Samivan: "recheck, take a 2nd opinion and Raphael's, and proceed").** Recheck (Claude), blind Codex and Raphael all chose option (c), full split; revises 2b.5 decision 2 / EVOL-1 on purpose. Condition from Codex: every cart lookup keyed by (user, cart_type) also keys on fulfilment, incl. Eat Now payment confirm and reopen; tests prove FOOD/EAT_NOW and FOOD/SCHEDULE carts coexist and never cross. Orders and groups get no fulfilment column (2b.4 SIMPLE-1 stands) |
| D2 | NAME-1 keep `EAT_NOW` code, labels only | **Approved 2026-11-15:** keep `EAT_NOW` everywhere it is stored or sent; Codex agrees (no code parses audit `channel` back into the enum). Customer label per screen ("Deliver now"; food copy may say "Eat Now"); never "Instant". D1 adds one more stored copy (`cart_sessions.fulfilment_type`) with the same value |
| D3 | ACCESS-1 enforce `eat_now_enabled` server-side before HSR pilot | pending |
| D4 | MONEY-1 fail closed on non-FOOD tax + hide GROCERY shop type | Samivan 2026-11-15: skipped here, he handles it himself (he owns shop creation) |

## D1 build record (2026-11-15)

Backend branch `refactor/cart-fulfilment-split` (from `origin/feature/schedule`, merges into it). Not committed.

- **Shape:** `cart_sessions.fulfilment_type` (EAT_NOW / SCHEDULE); `CartType` = FOOD, GROCERY, PRODUCT (`vertical()` gone);
  a Schedule cart is `FOOD` + `SCHEDULE` (`CartSession.SCHEDULE_VERTICAL`, the one place "Schedule sells food" lives).
- **Lookups:** the two-key repository methods are deleted, so the compiler found every caller; single-cart reads go through
  `findEatNowCart`, `findScheduleCart`, `findScheduleCartForUpdate`. Policy by `FulfilmentPolicies.forFulfilment`.
- **API:** `GET/DELETE /api/cart` and `PUT /api/cart/accept-changes` take `fulfilment` (default `EAT_NOW`, so live clients
  are unchanged); `CartResponse` / `CartSummaryResponse` carry `fulfilmentType`; a checkout body with `cartType: "SCHEDULE"`
  is a 400. Query param named `fulfilment`, not `channel` (that word already means SalesChannel and commission channel).
- **SQL:** `db_manual/cart-fulfilment-split-migration.sql`, RUN by Samivan 2026-11-15 and verified (checks validated, new index valid, old index gone, 0 Schedule carts existed). Codex review fixes folded in: LOCKED Schedule carts
  are moved, never abandoned (a payment in flight keeps its cart); the new index must be `indisvalid` before the old one
  drops, and the boot guard's index check now requires a valid index for every guarded index.
- **Tests:** real-DB `repository/CartSessionFulfilmentTest` (coexistence, one open cart per key, shape check, SCHEDULE
  rejected, and an upgrade test that rebuilds the old schema and legacy rows and runs the file; a mutant abandoning LOCKED
  carts was killed); updated unit tests across cart, checkout, settlement and guard.
- **Accepted risks:** live main reads carts by user + cart_type and can see a Schedule cart as an Eat Now cart, so only
  the dev account creates Schedule carts until this is on main (2b.5 MIG-3 already says so); add responses cached for
  idempotency before deploy replay as a miss (Schedule, dev only) or with `fulfilmentType` null (Eat Now, field unused).
