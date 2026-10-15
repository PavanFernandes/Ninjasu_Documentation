---
id: ""
title: "Schedule (planned lunch delivery) — Direction & Phase Plan"
summary: "Eat Now vs Schedule as per-area modes; Schedule launches in Bengaluru HSR (3 km) as manually-batched lunch delivery in fixed slots. Records the decisions, the money model, vocabulary, open decisions, blockers and the phase-by-phase build order across backend, web admin, customer app and rider app."
type: how-to
status: final-for-review
apps: [backend, web, customer, rider]
module: "schedule"
anchors: []
verified_against: "backend main @ 7434fd8 (2026-10-14); design review 1 + 2"
updated: 2026-10-15
review: schedule-design-review.md
---

# Schedule — Direction & Phase Plan

Each phase gets its own detailed design when it is picked up. This doc fixes the **direction**,
the **order**, and what each phase must deliver. It is the one source of truth for Schedule
decisions. Update it when a decision changes; don't fork it. The reasoning behind each decision
(failure scenarios, mitigations) is in [schedule-design-review.md](schedule-design-review.md): P-numbers below point there.

## 1. Direction

Ninjasu runs two fulfilment **modes**, chosen per **service area**:

| Mode | Customer intent | Where first |
|---|---|---|
| **Eat Now** | "I'm hungry now. Show me good food nearby." | The original town (not crowded; single-order delivery is affordable) |
| **Schedule** | "I'll eat lunch at a known time. Plan it." | **Bengaluru HSR, 3 km radius**, lunch slots |

Schedule is not a convenience feature. It is how delivery margin works in a dense city: known demand
→ batched rider runs → lower rider cost per order (dossier assumption A8). In HSR, Eat Now is
switched off until demand shows up through the **"Notify me when instant delivery starts here"**
button.

**Business model: marketplace (ECO).** The restaurant sets its price and is the seller; Ninjasu
facilitates, earns a commission plus fees, and pays GST under section 9(5). Ninjasu never buys and
resells food (CA to confirm; see §5).

**Messaging rule:** describe how it works. No promises ("on time"), no price comparison
("restaurant prices", "no markup"), because Ninjasu takes a commission.

## 2. Vocabulary (one word, one meaning)

| Term | Meaning | Not to be confused with |
|---|---|---|
| **Scheduled order** | An order for a future slot. UI word: **Schedule** | Never "pre-order" or "booking" |
| **Service area** | Where Ninjasu operates as the service provider: boundary, modes on, slots, staff | `delivery_zones` = rider notification routing (relabel "Rider groups" in admin UI) |
| **Service date** | The calendar date (in the area's timezone) an order is for. Today at launch, tomorrow later | "placed on" date |
| **Slot** | A delivery window, e.g. 12:30 | — |
| **Order-until** | The clock time after which a dish can no longer be ordered for a service date, set and editable by the restaurant. The customer's effective cutoff for a slot = the earlier of the dish's order-until and the area's last call for that slot | — |
| **Slot capacity** | Max orders per slot (rider-bound), set by Ninjasu | Scheduled stock |
| **Scheduled stock** | How many of a dish the restaurant offers for Schedule on a service date; editable at any time (restock up, or down to what is already reserved) | Raw-material inventory; live item stock |
| **Prep ticket** | One derived card per shop per slot per service date: the restaurant's view of N customer orders | A purchase order (Ninjasu never orders food from a restaurant) |
| **Batch** | Orders a manager groups into one rider run | Prep ticket |
| **Drop point** | Saved place (~50 m radius) where orders cluster, with gate/reception notes | Delivery address |
| **Split price** | What the restaurant receives per unit (never above its dine-in price; the team enforces) | Menu price |
| **Menu price** | What the customer sees for Schedule: split price + commission (commission rounded to the nearest rupee) | Split price |
| **Commission** | Ninjasu's share, set per restaurant under the signed agreement; built into the menu price | Delivery fee, packaging fee |
| **Payout (split)** | What Ninjasu owes the restaurant for an order | — |
| **Order charge** | One recorded checkout fee line on an order group or order (type, amount); always paid by the customer | — |
| **Settleable order** | An order whose status is DELIVERED/COMPLETED, defined by ONE shared predicate | — |
| **Problem queue** | Live list of what's going wrong on the board now | Audit log = history of what people did |

## 3. Decisions

### 3.1 Product and operations
1. Modes are per service area: Eat Now / Schedule / both, set by the platform admin. HSR = Schedule only; town = Eat Now.
2. **Ordering window and cutoffs, kept to two numbers (decided 2026-10-15).** The area sets when ordering opens (e.g. 8:00) and one **last call** = N minutes before each slot (riders and batching need orders by then; nothing can go past it). Each dish on the day's lunch list has just **stock** and an **order-until clock time**, both editable by the restaurant at any time. Effective cutoff for a dish in a slot = earlier of the dish's order-until and the slot's last call. There is no restaurant-level cutoff rule; the restaurant UI has a "set order-until for all dishes" shortcut instead.
3. Slots e.g. 12:30 / 1:00 / 1:30. The customer picks a slot; restaurants grey out per slot, so the app picks the slot first.
4. **Manual batching first.** A manager builds batches and assigns riders. No routing engine; dispatch uses MANUAL mode + existing staff assign.
5. **The board records everything from day one**: batch membership, rider, per-restaurant handover time, delivered time, slot vs actual. Records can't be backfilled.
6. Area-scoped staff roles and the `/api/ops/**` audience, authorized against the area resolved server-side from the resource, never a client-sent area id (review P2; superseded in detail by `platform_staff` in [admin-access-redesign.md](admin-access-redesign.md)).
7. Drop points: table exists from v1, created from real batches.
8. Curated: Ninjasu onboards only good restaurants; may run its own kitchen to fill menu gaps (no placement advantage, no use of partner data, disclosed).
9. Admin surfaces: Service areas, Schedule board, Schedule fields on the Shop page, Orders filters, later a Numbers view.

### 3.2 Dates and configuration (decided 2026-10-14; review P9, P10)
10. **Today only at launch, built for "tomorrow" later.** Every Schedule row carries `service_date` (area timezone). The area has `advance_days` (0 now, CHECK 0..1); the customer API takes an optional `service_date` validated against it. Tomorrow is a setting change. Only tomorrow, never further. The tomorrow path is built and tested from slice one.
11. One `ServiceDateResolver` computes every date and "is this orderable now"; nothing else does.
12. Window open time, `last_call_minutes`, slots (rows: time, capacity) and `advance_days` are set by the platform admin on the Service areas page, validated by one server-side validator, audited. Slot day rows snapshot capacity when created; capacity can't drop below reserved.

### 3.3 Orders, stock, cancellation (decided 2026-10-14; review P3, P4, P5, P12)
13. **One restaurant per order, but a Schedule cart may hold several restaurants (D1 revised 2026-10-14).** Eat Now carts stay single-restaurant. A Schedule cart (one service date, one slot, one delivery address) may span restaurants; checkout creates one **order group** (one payment, one customer, one drop, one delivery fee) and **one order per restaurant** inside it. Each order is still single-restaurant, so tickets, commission, payout, GST invoice and refunds stay per order. See §3.5. `CartShopPolicy` replaces the hard-coded check in `CartServiceImpl.addToCart`.
14. **Cancellation (D2):** free before cutoff (full refund, capacity + stock released); no customer cancel after; a restaurant decline or ops cancel always refunds. The server checks the cutoff.
15. **Separate curated Schedule menu (D3), Zepto-style stock (decided 2026-10-15):** one `scheduled_menu_item` row per dish per service date with `stock_qty`, `reserved_qty`, `order_until` (clock time) and `split_price`, never touching the live stock counter. The restaurant can raise stock (restock) or lower it to no less than reserved, and move order-until earlier or later at any time, including reopening a dish after its time passed. Examples: bulk biryani 50 until 11:30; fried rice until 12:50 (the slot last call still blocks the 12:30 slot); extra 15 biryani = raise stock to 65 and move order-until to 13:00. The customer sees "order by 11:30", "sold out", or "ordering closed for this slot" (greyed, not hidden); a restock shows up on the next refresh. One availability resolver: item active AND row for the date AND stock > reserved AND now < effective cutoff AND shop assigned AND area not paused. "Same as yesterday" copies stock and order-until. The customer-facing menu price is derived from the split price and the rate in force, never stored.
16. **Restaurant cutoff (D4, superseded 2026-10-15):** no `schedule_lead_minutes` column; per-dish order-until replaces it (item 15).
17. **Shop ↔ area (D6):** assigned by admin only, `shops.service_area_id UUID NULL`, no foreign key, one area per shop; the shop's own delivery radius is ignored for Schedule. Orders store their own `service_area_id`. One SQL fragment + one eligibility function answer "is this shop in the area".
18. New order status `SCHEDULED` (paid, unreleased). **An order's cutoff is locked when it is paid** = the earliest effective cutoff among its lines at that moment; later edits to stock or order-until never change existing orders. At that cutoff an idempotent job releases it to `PLACED` (an order placed after the restaurant's bulk release joins the ticket as an addition). Reservation at payment confirm (soft check at checkout); `releaseForFulfilment` and `voidReservation` are separate operations; prepaid only; exhaustive `OrderStatus` classification test.
19. **Prep ticket (D9, confirmed 2026-10-14):** derived from the member orders, one `ScheduleTicketReleased` event, per-order shop alarms and pushes suppressed for SCHEDULED orders. Status is derived, never stored; the first fired version is immutable and later changes append amendments.

### 3.4 Money (decided 2026-10-14; review P11; supersedes the earlier ledger design)
20. **Handled outside the code by the Ninjasu team:** COD cash (the rider remits it to Ninjasu, who settles the restaurant net; decided 2026-10-14, no code), the restaurant agreement, the notice period for commission changes, the rule that a restaurant's payout is never more than its dine-in price, price review, and the actual payouts (manual until Razorpay Route split exists).
21. **Menu price = split price + commission (decided 2026-10-14, closes D14).** The restaurant's **split price** (the team ensures it never exceeds the dine-in price) is what the restaurant receives per unit. Commission is built into the price the customer sees: commission per unit = rate × split, rounded to the nearest rupee; menu price = split + commission (whole rupees). Other charges (delivery, packaging, any future fee) appear at checkout. The restaurant's payout is therefore unaffected by a commission change; a rate increase raises the menu price the customer sees.
    **The code records, per order at placement:** per line the split price and the menu price (both snapshotted), and on the order the restaurant payout and the commission amount (denormalized for audit and export), plus an `order_charges` child table (type, amount) for the checkout charges. A new fee type is a new row, not a migration. The existing `delivery_fee` column stays. Every checkout charge is paid by the customer, so no "bearer" column is needed.
22. **Rates:** a small `commission_rate` table: scope (a shop, or an area + mode), rate, `effective_from`, `consent_ref` (free text: addendum or email id), created by. The rate for an order is the latest row effective at placement; the order keeps it. A new row is rejected unless `effective_from` is at least the notice period away (admin-set days). Every change is audited in `platform_audit_events`. Consent is recorded outside the app in the pilot; an in-app "owner accepts" button is a later add-on to the same table. Increases need the restaurant's explicit acceptance, decreases need notice only (the agreement decides; lawyer to confirm).
23. **Commission base:** the rate applies to the split price (item lines only), never to taxes, delivery fee or packaging. A restaurant-funded discount lowers the split it receives; a Ninjasu-funded discount lowers the customer's price, never the split. Commission accrues on delivered/completed orders only; the order's recorded amount is "if delivered". The shown percentage varies slightly because commission rounds per unit to the nearest rupee; the recorded rupee amounts are the truth.
24. **Settlement** is an export of settleable orders per restaurant per period, using ONE shared "settleable order" predicate (the `SALE_BILL` pattern in reports). Optional later: `settled_at` + `settlement_ref` on the order to prevent double payouts. After-delivery partial refunds are adjusted by hand in the pilot.
25. **Delivery fee:** Schedule defaults to ₹0, admin-configurable per area + mode up to a ₹10 ceiling; one `FeeResolver`: a SCHEDULED order reads the area's value and ignores the shop's `DeliveryConfig` (including free-delivery-above). Eat Now and legacy orders keep today's path.
26. **Packaging:** a separate visible line, admin-configurable per area + mode (default 0), recorded as an order charge; excluded from the commission base; Ninjasu revenue only where Ninjasu supplies the packaging.
27. **Rounding:** prices and payable amounts are whole rupees. A listed price is a whole rupee; GST lines are computed exactly and one round-off line brings the bill to a whole rupee; commission rounds to the nearest rupee through one shared function. Amounts stay DECIMAL(10,2) like the existing columns.
28. **Tax facts (secondary sources, CA to confirm):** under section 9(5) Ninjasu pays 5% GST on the restaurant's food (no ITC; the restaurant does not charge GST on those orders); from 22 Sep 2025, 18% GST on local delivery through an ECO when the rider is unregistered, so a free delivery fee does not remove that cost. GST on platform/customer fees and on commission is unconfirmed. GST is a pass-through liability, never Ninjasu revenue.
29. **Razorpay keeps its fee on refunds** (about 2.36% of the order at standard pricing, per Razorpay's terms), so each free cancel costs real money. Track cancelled-order fee loss in the pilot numbers.

### 3.5 Multi-restaurant Schedule checkout (decided 2026-10-14)
30. **Order group.** New `order_groups` row per checkout: customer, service area, service date, slot, address, a short human **group code** (unique per area per service date), the Razorpay order (today `orders.razorpay_order_id` is UNIQUE, so one payment = one order; the group takes over that role for Schedule), payment status, delivery fee. Orders carry `group_id` and an **order code** = group code + restaurant suffix (e.g. `4821-A`, `4821-B`).
31. **Codes are the handover key (decided 2026-10-15).** The order code (unique per area per service date) is the key for the restaurant, the bag and the rider; never a user id (one customer can have several orders a day, reception sorts by name, and a permanent id printed daily is a privacy leak). Bag label: **`4821-A · Asha · 3 items`**. The restaurant ticket lists order codes; the rider collects every part of a group before the drop. **The batching unit is the group**, so all its orders go in one batch.
32. **Slot capacity counts groups (drops), not orders**, because rider effort is per drop.
33. **Commission rate is locked when the customer checks out** (the price they saw), never recomputed; a tomorrow order placed today uses today's rate. No service-date rate logic.
34. **Payment confirm fans out** to every order in the group in one flow: each order reserves its own dishes; a restaurant that can't be reserved is refunded as a partial refund on the group payment (recommended), the rest proceeds. If nothing is left, the delivery fee is refunded too.
35. **Cancellation (D2) for a group:** the customer cancels the whole group before its **earliest locked cutoff** (one refund, simple). Restaurant decline / ops cancel stays per order, refunded as a partial refund.
36. Each order keeps its own GST treatment (the restaurant is the supplier); the delivery fee belongs to the group.

### 3.6 Operational details found in the role-play (2026-10-15)
37. **Pickup-by time.** Each ticket shows "ready by HH:MM" = slot start − the area's `pickup_lead_minutes`; the restaurant preps against that, not the slot time.
38. **Ops can correct a delivery address** before the group is batched (audited); after batching, only by moving it out of the batch first.
39. **Customer notifications:** paid ("Scheduled for 12:30"), reminder before cutoff (if nothing ordered yet), being prepared (at release), picked up, delivered, refunded (with the reason). Verify customer push state before Phase 4.
40. **A group always travels in one batch**, even when its restaurants are far apart; the manager picks the pickup order. Revisit only if pilot data shows it hurts.
41. **"Can't make" needs ops approval (decided 2026-10-15).** A restaurant that cannot make a dish flags it on the ticket ("can't make 2 thali", optionally naming the orders). Nothing is refunded yet: the request lands in the ops **problem queue** as pending, with the affected order codes, customers and minutes to the slot. The ops manager approves (choosing which orders to drop if the restaurant did not say), or rejects, or asks the restaurant to substitute. Only approval cancels those lines, refunds the customers (partial refund) and appends a ticket amendment. No automatic approval.

## 4. Kill criterion (deferred 2026-10-14: revisit before the Phase 7 pilot; the board still records the data)

- The earlier break-even (≈ 5–7 orders per rider stop per run) assumed a ₹10 delivery fee. With a free Schedule delivery fee the break-even is higher (about 6–11 orders per run by the same arithmetic; recompute with real commission).
- If the average stays below break-even after an agreed number of pilot weeks, delivery is being funded by Ninjasu, not by efficiency. Revisit fee, slots, area, or commission.
- Watch also: slot fill, delivered-vs-slot time, repeat customers/week, refund-fee loss.

## 5. Open decisions

| # | Decision | Needed by | State |
|---|---|---|---|
| D5 | Handover proof at office drops: OTP / reception photo / OTP door-to-door | Phase 6 | Recommend reception photo at drop points |
| D7 | "Near the shop" rider accept check: UX only or server-recorded | Later | UX only for now |
| D9 | Prep ticket (proposed) vs a real bulk order from Ninjasu | Phase 2d | Recommend the ticket; a real purchase order makes Ninjasu the buyer-reseller |
| D11 | Restaurant partner agreement: commission rate + basis, notice period and consent, payout schedule, who sets prices, payout ≤ dine-in price, discount funding, cancellation liability, FSSAI + GST/ECO duties, content licence, termination | Phase 0 | Team + lawyer; not legal advice |
| CA | Confirm: marketplace/ECO model; whether an ECO must register for GST (assumed yes); GST on commission, platform fee and packaging; whether a menu price built as split + commission (set by Ninjasu from the restaurant's split) keeps the restaurant the supplier; FSSAI position (marketplace, own kitchen) | Before pilot | Deferred by Samivan 2026-10-14; ask before the pilot |

## 6. Blockers outside the Schedule build (Phase 0)

| Blocker | Why | State |
|---|---|---|
| Rider delivery loop verified on a real phone | Schedule is its first real use | PR #37/#3 merged; device test pending |
| `deliveries.created_by_staff_id` nullable in prod | Accepts fail otherwise | Verify after deploy |
| **Online payment live** | Scheduled orders must be **prepaid** (no-show = wasted food) | Razorpay built, flag off, needs adversarial re-review |
| GSTIN | Ninjasu as ECO under 9(5) | Registration planned Oct 2026 |
| Signed restaurant partner agreement (D11) | Commission, payout, price and liability terms before a menu is listed | Not started |
| HSR restaurants onboarded | No supply, no menu | Not started |
| Lunch-shift riders in HSR | 2–3 h afternoon shift, pay per shift | Not started |
| `platform_audit_events` exists | Every admin change in Phase 2 writes to it (D8) | Verify at the start of Phase 2a; build first if missing |
| Clean working trees | Unpushed/uncommitted work across repos | Check before branching |

## 7. Phases
**Task-level order, tests, SQL and the progress tracker live in [schedule-implementation-order.md](schedule-implementation-order.md); where the two differ on tasks, that file wins.** The phase summaries below describe intent only.

Phases 3–6 can run in parallel once Phase 2's API contracts are frozen. Phase 0 runs alongside
Phases 1–2 but must be closed before Phase 7. Run `/gcp` before each Phase 2 slice and a quick judge before each push.

### Phase 0 — Clear the runway (no Schedule code)
Close the §6 blockers: device-verify the rider loop, confirm the prod column, re-review and switch
on online payment, push or merge stray branches. Business track: sign the first HSR restaurants
(with the D11 agreement), line up lunch-shift riders, pick the pilot office cluster, ask the CA the §5 questions.
**Exit:** prepaid delivery order works end to end on real phones.

### Phase 1 — Design gate (done)
Review 1 (P1–P8, 2026-10-08) and review 2 (P9–P13, 2026-10-14) are written; D1–D4, D6, D8, D10–D13 decided.
**Remaining:** ADR superseding the audit plan's scope line; frozen contracts come out of Phase 2.

### Phase 2 — Backend foundation (build in small, tested slices)

**2a — Areas, slots, dates, rates (additive; no row = today's behaviour)**
- `service_area` (centre, radius, `eat_now_enabled` / `schedule_enabled` with CHECK at least one, IANA timezone, `paused_on`, `advance_days`, window offset + time, per-mode fee and packaging defaults) and `service_area_slot` rows with one validator.
- `shops.service_area_id`; admin-only write endpoint.
- `ServiceDateResolver`; one eligibility function + SQL fragment; guard test that fails if a discovery query skips them.
- `commission_rate` table + resolver (D13 #22); audit actions to `platform_audit_events`.
- Customer read: resolve area by location → modes, slots, cutoffs.
- Hand-run SQL migration + boot guard. **Exit:** the tomorrow path is covered by tests with `advance_days = 1`.

**2b — Orders and stock**
- `orders`: `fulfilment_type` NOT NULL default EAT_NOW, `service_area_id`, `service_date`, slot, `release_at` (epoch ms), status `SCHEDULED`; exhaustive classification test; the live-order read audit (shop board, KDS, getActiveOrder, assign, cancel push, history).
- `scheduled_menu_item` + availability resolver; `schedule_reservations` (PK `order_id`) + the single `release(orderId)`; reservation at payment confirm; prepaid-only (`placeOrder` rejects scheduled).
- Release job (catches up after restart), reminder before cutoff; re-verify the refund sweep and reconciliation job against a ~24 h `SCHEDULED` lifetime; fix the payment-confirm refund wait.
- `CartShopPolicy`. **Exit:** tests for capacity races, cutoff, idempotent release.

**2c — Money snapshot**
- One `MenuPriceResolver` (menu price = split + round-to-nearest-rupee of rate in force × split); per-line split + menu price snapshots; order payout + commission amount; `order_charges` for checkout charges; `FeeResolver` (scheduled flat fee branch); packaging line; the rounding function; the shared settleable-order predicate.
- **Exit:** one scheduled and one Eat Now order each show correct charges, payout and totals; no existing order changes.

**2d — Prep ticket and ops API**
- Derived prep ticket + `ScheduleTicketReleased` event, alarm/push suppression; `/api/ops/**` with area authorization; audit actions for every mutating endpoint.
**Exit (Phase 2):** contracts frozen.

### Phase 3 — Ops board (backend + Ninjasu_Web)
- Admin: Service areas page (modes, window, slots, fees, packaging, advance days), Schedule fields on the Shop page (area, commission rate + consent reference with the notice check), ops members, Orders filters (mode, slot). Relabel Delivery zones → Rider groups. A review list showing each item's dine-in price next to its Schedule price (the team checks the payout rule).
- **Schedule board:** slot columns (cutoff countdown, orders/capacity, restaurant prep status), map of drop addresses → create batch → assign rider, batch progress with timestamps, problem queue (late restaurant, unbatched after cutoff, no pickup, sold out after order, running late, customer unreachable) with one-click actions, shareable batch sheet.
- Batches (append-only `batch_events`, no stored batch status) + drop points; "save as drop point".
- **Settlement export** per restaurant per period (XLSX via the reports infrastructure).
- Audit log filters + "worth reviewing" view.
**Exit:** a manager can run one lunch end to end on the board and settle it by hand.

### Phase 4 — Customer app (Food-Ninja-Frontend)
- Home driven by the area's modes. Schedule home: slot picker first, then restaurants greyed per slot (not hidden), cutoff countdown, sold-out states, notify-me buttons. A day picker appears only when `advance_days > 0`.
- Checkout with slot + prepaid; separate visible fee lines (delivery, packaging, any customer-borne fee); "Scheduled for 12:30" tracking; reminder push before cutoff (verify customer push first); first-open screen for HSR.
**Exit:** a customer can schedule, pay, and track a lunch order.

### Phase 5 — Restaurant side (Ninjasu_Web shop + RN where needed)
- Prep ticket per slot ("12:30: 14 biryani, 6 thali"): one accept, one ready, one handover; partial "can't make" uses the existing decline path.
- "Upcoming scheduled" separate from live orders, with a **live count per slot and per dish** (paid orders so far, reserved vs stock) that the restaurant can watch before the cutoff; no alarm or push until release; the view polls a light read of the reservation counters, never aggregating orders on every poll; morning entry of the lunch list for a date ("same as yesterday"); restaurant cutoff setting; Schedule price entry.
**Exit:** a restaurant preps from the ticket without calling anyone.

### Phase 6 — Rider app (Ninjasu_Rider_App)
- Prepaid completion: skip the cash step for prepaid orders (app is COD-only today; verify a prepaid delivery snapshots `codAmount = 0`).
- Batch card: slot, drop point, pickup order, drop list; one-tap "picked up from X (n orders)" writes the handover event; drop point notes; handover proof per D5.
**Exit:** a rider runs a batch without per-order tapping.

### Phase 7 — HSR pilot (manual ops)
One office cluster, a few restaurants, two lunch-shift riders. Run several weeks. Revisit the kill criterion before starting; track it weekly. Log every manual workaround: those are the next build items.

### Phase 8 — Numbers + iterate
Numbers view from batch records and order charges (orders per run, rider cost per order, commission earned, slot fill, delivered vs slot, handover lateness, turned-away + notify-me, repeat customers, refund-fee loss). Then, driven by pilot data: in-app commission acceptance, `settled_at` marks, auto-grouping by drop point, customer picks drop point, "tomorrow" switch-on, Eat Now rule for HSR, a Razorpay Route split.

## 8. Where to start

1. Phase 0 runway items and the §5 questions (CA, agreement) don't block code and can start now.
2. First code: Phase 2a on a fresh `feature/schedule-service-areas` branch off `origin/main` in the backend, after confirming `platform_audit_events` exists.
3. Don't start Phase 4 UI before Phase 2 contracts are frozen (type-drift principle).
4. Findings outside Schedule that were logged, not folded in: item stock-ledger credit leaks, dead `findActiveByShopId`, the shop push saying "COD" for every delivery order, delivery orders ignoring shop opening hours.

Implementation order: [schedule-implementation-order.md](schedule-implementation-order.md).
Related: Raphael dossier `brain/dossiers/ninjasu-pos.md` (assumption A8),
[audit-log-plan.md](audit-log-plan.md), [admin-access-redesign.md](admin-access-redesign.md),
[stock-ledger-design.md](stock-ledger-design.md), `06-Rider-App/` (dispatch, manual assign).
