---
id: ""
title: "Schedule (planned lunch delivery) — Direction & Phase Plan"
summary: "Eat Now vs Schedule as per-area modes; Schedule launches in Bengaluru HSR (3 km) as manually-batched lunch delivery in fixed slots. Records the decisions, the money model, vocabulary, open decisions, blockers and the phase-by-phase build order across backend, web admin, customer app and rider app."
type: how-to
status: final-reviewed-2026-10-15
apps: [backend, web, customer, rider]
module: "schedule"
anchors: []
verified_against: "backend main @ 7434fd8 (2026-10-14); design review 1 + 2"
updated: 2026-10-18
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
| **Split price** | Retired 2026-10-18 (#44, #45): was a per-dish per-day price the restaurant receives. No longer stored or shown | App price |
| **Menu price** | Retired 2026-10-18 (#44): was split price + commission. Use **app price** | App price |
| **Dine-in price** | Per add-on option: what Ninjasu POS, counter sale and the dine-in guest QR menu charge. Editable only by the Ninjasu admin (#48) | App price |
| **App price** | Per add-on option: what the customer app (Eat Now and Schedule) charges, set by the restaurant, at most dine-in + the global cap (#47). An item's app price = the sum of its selected options | Dine-in price |
| **Commission** | Ninjasu's share of an order: a flat-rupee slab per item unit from the restaurant's commission plan, computed on the order, never built into or shown as part of a menu price (#45) | Delivery fee, packaging fee |
| **Commission plan** | A named, versioned slab table created by the platform admin; each restaurant is assigned one (#46) | Agreement |
| **Payout** | What Ninjasu owes the restaurant for an order: item total at app prices − commission (#45) | — |
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
13. **One restaurant per order, but a Schedule cart may hold several restaurants (D1 revised 2026-10-14).** Eat Now carts stay single-restaurant. A Schedule cart (one service date, one slot, one delivery address) may span restaurants; checkout creates one **order group** (one payment, one customer, one drop, one delivery fee) and **one order per restaurant** inside it. Each order is still single-restaurant, so tickets, commission, payout, GST invoice and refunds stay per order. See §3.5. `CartShopPolicy` replaces the hard-coded check in `CartServiceImpl.addToCart`. The shop limit comes from a per-fulfilment `FulfilmentPolicy` (decision 43).
14. **Cancellation (D2):** free before cutoff (full refund, capacity + stock released); no customer cancel after; a restaurant decline or ops cancel always refunds. The server checks the cutoff.
15. **Separate curated Schedule menu (D3), Zepto-style stock (decided 2026-10-15):** one `scheduled_menu_item` row per dish per service date with `stock_qty`, `reserved_qty`, `order_until` (clock time) and `active` (plus copy fields such as `copied_from_id`), with no price column (`split_price` dropped 2026-10-18: the menu has no price on an item, only on add-on options, so one per-day price cannot express sizes or paid add-ons; see #44), never touching the live stock counter. The restaurant can raise stock (restock) or lower it to no less than reserved, and move order-until earlier or later at any time, including reopening a dish after its time passed. Examples: bulk biryani 50 until 11:30; fried rice until 12:50 (the slot last call still blocks the 12:30 slot); extra 15 biryani = raise stock to 65 and move order-until to 13:00. The customer sees "order by 11:30", "sold out", or "ordering closed for this slot" (greyed, not hidden); a restock shows up on the next refresh. One availability resolver: item active AND row for the date AND stock > reserved AND now < effective cutoff AND shop assigned AND area enabled and not paused AND date within window/advance days AND slot valid AND item not flagged over the app-price cap (#47; updated 2026-10-18). "Same as yesterday" copies stock and order-until. The customer sees the dish's app price from its live add-on options (#44); the per-day row holds no price.
16. **Restaurant cutoff (D4, superseded 2026-10-15):** no `schedule_lead_minutes` column; per-dish order-until replaces it (item 15).
17. **Shop ↔ area (D6):** assigned by admin only, `shops.service_area_id UUID NULL`, no foreign key, one area per shop; the shop's own delivery radius is ignored for Schedule. Orders store their own `service_area_id`. One SQL fragment + one eligibility function answer "is this shop in the area".
18. New order status `SCHEDULED` (paid, unreleased). **An order's cutoff is locked when it is paid** = the earliest effective cutoff among its lines at that moment; later edits to stock or order-until never change existing orders. At that cutoff an idempotent job releases it to `PLACED` (an order placed after the restaurant's bulk release joins the ticket as an addition). Reservation at payment confirm (soft check at checkout); `releaseForFulfilment` and `voidReservation` are separate operations; prepaid only; exhaustive `OrderStatus` classification test.
19. **Prep ticket (D9, confirmed 2026-10-14):** derived from the member orders, one `ScheduleTicketReleased` event, per-order shop alarms and pushes suppressed for SCHEDULED orders. Status is derived, never stored; the first fired version is immutable and later changes append amendments.

### 3.4 Money (decided 2026-10-14; review P11; supersedes the earlier ledger design)
20. **Handled outside the code by the Ninjasu team:** COD cash (the rider remits it to Ninjasu, who settles the restaurant net; decided 2026-10-14, no code), the restaurant agreement, and the actual payouts (manual until Razorpay Route split exists).
    **Updated 2026-10-18:** the agreement stays outside the code, but it states the restaurant's plan name and version with the slab table attached, the notice period for changes, the app-price cap, refund handling, payout schedule and GST on commission; its reference is stored as `consent_ref` on the plan assignment (#46); the text needs legal/CA review. The notice period is enforced in code on plan changes (#46). The old "payout never above dine-in price" rule is replaced by payout = item total at app prices − commission (#45), and manual price review by the app-price cap (#47) and dine-in price edit gating (#48).
21. **Superseded 2026-10-18 by #44 and #45** (two prices per option; order-level slab commission). Kept for history:
    **Menu price = split price + commission (decided 2026-10-14, closes D14).** The restaurant's **split price** (the team ensures it never exceeds the dine-in price) is what the restaurant receives per unit. Commission is built into the price the customer sees: commission per unit = rate × split, rounded to the nearest rupee; menu price = split + commission (whole rupees). Other charges (delivery, packaging, any future fee) appear at checkout. The restaurant's payout is therefore unaffected by a commission change; a rate increase raises the menu price the customer sees.
    **The code records, per order at placement:** per line the split price and the menu price (both snapshotted), and on the order the restaurant payout and the commission amount (denormalized for audit and export), plus an `order_charges` child table (type, amount) for the checkout charges. A new fee type is a new row, not a migration. The existing `delivery_fee` column stays. Every checkout charge is paid by the customer, so no "bearer" column is needed.
22. **Superseded 2026-10-18 by #46** (named slab plans replace the percentage rate; the assignment keeps scope, `effective_from`, notice and `consent_ref`). Kept for history:
    **Rates:** a small `commission_rate` table: scope (a shop, or an area + mode), rate, `effective_from`, `consent_ref` (free text: addendum or email id), created by. The rate for an order is the latest row effective at placement; the order keeps it. A new row is rejected unless `effective_from` is at least the notice period away (admin-set days). Every change is audited in `platform_audit_events`. Consent is recorded outside the app in the pilot; an in-app "owner accepts" button is a later add-on to the same table. Increases need the restaurant's explicit acceptance, decreases need notice only (the agreement decides; lawyer to confirm).
23. **Commission base (updated 2026-10-18):** the slab applies to each item unit's app price including the add-ons chosen for that unit (item lines only), never to taxes, delivery fee or packaging (#45). Whether the slab uses the price after a restaurant-funded discount is open (D17; suggested yes); a Ninjasu-funded discount or coupon never changes commission. Commission accrues on delivered/completed orders only; the order's recorded amount is "if delivered". The recorded rupee amounts are the truth.
    Earlier text (2026-10-14, replaced): the rate applied to the split price; a restaurant-funded discount lowered the split; the shown percentage varied because commission rounded per unit.
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
33. **Commission rate is locked when the customer checks out** (the price they saw), never recomputed; a tomorrow order placed today uses today's rate. No service-date rate logic. (2026-10-18: what is locked is the plan id + version and the per-line commission, #46.)
34. **Payment confirm fans out** to every order in the group in one flow: each order reserves its own dishes; a restaurant that can't be reserved is refunded as a partial refund on the group payment (recommended), the rest proceeds. If nothing is left, the delivery fee is refunded too.
35. **Cancellation (D2) for a group:** the customer cancels the whole group before its **earliest locked cutoff** (one refund, simple). Restaurant decline / ops cancel stays per order, refunded as a partial refund.
36. Each order keeps its own GST treatment (the restaurant is the supplier); the delivery fee belongs to the group.
37a. **Idempotency and payment account (final review 2026-10-15).** The group carries the client's checkout key; each member order's `idempotency_key` is derived from it (`orders.idempotency_key` is NOT NULL and globally unique). A group is paid to and refunded from the platform Razorpay account with no shop in the path; a group containing a shop that is not `SINGLE_MERCHANT` is rejected at checkout. Group refunds are rows with a lease and a gateway receipt used as the dedupe key. A member order's refundable amount is its immutable grand total; group charges are refundable at group level only. The group payment path validates the gateway's captured amount and currency before confirming. Details: implementation order 2b.4, 2b.7, 2b.9.

### 3.6 Operational details found in the role-play (2026-10-15)
37. **Pickup-by time.** Each ticket shows "ready by HH:MM" = slot start − the area's `pickup_lead_minutes`; the restaurant preps against that, not the slot time.
38. **Ops can correct a delivery address** before the group is batched (audited); after batching, only by moving it out of the batch first.
39. **Customer notifications:** paid ("Scheduled for 12:30"), reminder before cutoff (if nothing ordered yet), being prepared (at release), picked up, delivered, refunded (with the reason). Verify customer push state before Phase 4.
40. **A group always travels in one batch**, even when its restaurants are far apart; the manager picks the pickup order. Revisit only if pilot data shows it hurts.
41. **"Can't make" needs ops approval (decided 2026-10-15).** A restaurant that cannot make a dish flags it on the ticket ("can't make 2 thali", optionally naming the orders). Nothing is refunded yet: the request lands in the ops **problem queue** as pending, with the affected order codes, customers and minutes to the slot. The ops manager approves (choosing which orders to drop if the restaurant did not say), or rejects, or asks the restaurant to substitute. Only approval cancels those lines, refunds the customers (partial refund) and appends a ticket amendment. No automatic approval.
42. **Ticket timing (decided 2026-10-15).** The restaurant sees a **draft ticket** that updates live from the first paid order (read-only, no alarm, served from the live-counts cache). It freezes into publication v1 at the slot's **last call**, the same moment batching starts; one `ScheduleTicketReleased` event per shop, date and slot. Changes after v1 (cancellations, approved "can't make") append amendments. A dish's order-until only closes ordering for that dish.
43. **Flexible by design (decided 2026-10-15).** Multi-restaurant carts are on only for Schedule today. A `FulfilmentPolicy` per fulfilment type owns the differences (max shops per cart, payment owner kind, location policy, cancellation, reservation and release rules); `order_groups` carry `fulfilment_type`, and the payment core runs on a `PaymentOwner` abstraction. The Schedule cart limit is the area setting `schedule_max_shops_per_cart` (default 3). Enabling multi-restaurant for another fulfilment type later = a new policy + UI, with no schema or payment-core change.

### 3.7 Pricing, commission and menu permissions (decided 2026-10-17 / 2026-10-18)
Root cause: the menu has no price on an item; an item's price is the sum of its selected add-on options, and one required ITEM group gives the base price ([02-Domain/menu.md](../02-Domain/menu.md)). A per-dish price cannot express sizes or paid add-ons, so the split-price model (#21) is replaced.

44. **Two prices per add-on option (decided 2026-10-18).** Each option has a **dine-in price** and an **app price**. Ninjasu POS, counter sale and the dine-in guest QR menu show the dine-in price; the customer app (Eat Now and Schedule) shows the app price. The restaurant sets the app price. Today the app and POS both read the same `Addon.price`, so the app currently shows the dine-in price with no commission. Empty app price behaviour is open (D16).
45. **Commission is an order-level flat-rupee slab (decided 2026-10-18).** Commission is computed on the order, never shown in or built into a menu price; the app never displays "restaurant price + 10%". Per item unit, the slab is looked up on that unit's app price including the add-ons chosen for it, then multiplied by quantity; order commission = sum of its lines; restaurant payout = item total at app prices − commission. Delivery and packaging fees are excluded; GST on commission is charged extra. If Ninjasu changes its commission, app prices are updated by hand; nothing is recomputed automatically.
    **Standard slab:** ₹0–99 → ₹5; ₹100–149 → ₹10; ₹150–199 → ₹15; ₹200–249 → ₹20; ₹250–299 → ₹25; ₹300 and above → ₹25 + 10% of the amount above ₹300 (no jump at 300; ₹400 → ₹35, ₹500 → ₹45). Example: thali Large 200 + Egg 20 + Papad 10 = ₹230 app price → ₹20 per thali.
    The split-price preview endpoint is dropped. The restaurant menu editor shows a read-only line next to each app price: "Ninjasu keeps ₹X, you get ₹Y", computed from the restaurant's plan. Because the slab applies to a unit including its add-ons, which options show this line (and on what amount) is deferred to the onboarding revisit after Schedule (D25).
    **Rounding (confirmed by Samivan 2026-10-18):** the per-unit commission is rounded to a whole rupee by the #27 function (nearest rupee, .5 up) before × quantity (₹305 → ₹25.50 → ₹26; qty 3 → ₹78). Whether the band is chosen on the unit app price after a restaurant-funded discount is D17 (open).
46. **Named commission plans (decided 2026-10-18; supersedes #22 and the 2a.4 percentage `commission_rate` model, which has no production caller).** The platform admin creates and names slab plans (e.g. Standard; a low-price plan for snacks/bakeries or a partner/launch plan only when needed; a custom plan for one restaurant is allowed and is still a recorded named plan). Each restaurant is assigned one plan. Plans are versioned and append-only; a change needs the existing notice period. The assignment keeps scope, `effective_from`, notice and `consent_ref` (the signed agreement's reference, #20). Each order snapshots the plan id + version and the per-line commission, so later plan changes never alter past orders and a partial refund returns exactly that line's commission. Which plans exist at launch is open (D21).
47. **One global app-price cap (decided 2026-10-18).** A single platform setting "max app price over dine-in price"; no per-restaurant setting, and it is not part of the commission math. A save that puts an option's app price above dine-in + cap% is refused with a clear message. If Ninjasu tightens the setting later, or the Ninjasu admin lowers a dine-in price, options now above it are flagged and hidden from Schedule until fixed. The percentage is open (D15).
48. **Only the Ninjasu admin edits the dine-in price (decided 2026-10-18, revised the same day; closes D23).** For every shop, with or without Ninjasu POS, the restaurant cannot edit the dine-in price; only the Ninjasu admin can, set at onboarding from the printed menu and changed on the restaurant's request. The restaurant keeps editing the app price, within the cap (#47). Every price change is audited. This closes the gaming risk of inflating the dine-in price to lift the cap, including the toggle bypass (`shops.pos_enabled` is an owner toggle, so a POS-based gate could be switched on for one edit). The first draft gated edits on "POS enabled"; that is withdrawn. Consequence: a POS restaurant that changes its dine-in prices asks Ninjasu, where today the owner edits option prices directly in the menu editor.
49. **Paid add-ons are allowed on Schedule dishes (decided 2026-10-18).** E.g. thali + egg / kebab / papad, choice of dal or sambar. Replaces the earlier v1 "Schedule dishes carry no paid add-ons (pending Samivan's OK)". Add-on running out before the dish is open (D20).
50. **Schedule-menu permissions, POS style (decided 2026-10-18).** `schedule_menu.view`; `schedule_menu.manage` (dishes, order-until, copy day); `schedule_menu.stock` (restock, mark sold out, move order-until only). Owner/admin has all; Manager gets all; Chef gets view + stock. New permissions go into the DEFAULT templates only, never the LEGACY sets (`legacyMyRole` uses `containsAll` on LEGACY).

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
| D11 | Restaurant partner agreement: commission plan name + version with the slab table attached, notice period and consent, app-price cap, refund handling, payout schedule, GST on commission, who sets prices (the restaurant sets the app price; dine-in price per #48), discount funding, cancellation liability, FSSAI + GST/ECO duties, content licence, termination (updated 2026-10-18) | Phase 0 | Team + lawyer + CA review of the text; not legal advice |
| CA | **Pricing questions needed before 2b.3** (task 0.7). Aggregator-style model (updated 2026-10-18): the restaurant sets the customer (app) price and Ninjasu deducts a slab commission from the restaurant's item total (#44–#46). Confirm: the restaurant stays the supplier under 9(5) in this model; GST on commission (assumed charged extra); whether an ECO must register for GST (assumed yes); GST on platform fee and packaging; FSSAI position (marketplace, own kitchen). The 2026-10-14 question about a menu price built as split + commission set by Ninjasu is withdrawn with #21 | Before 2b.3 (pricing); rest before pilot | Open |
| D15 | App-price cap percentage (#47) | 2b.3 | Open; suggestion: 10%, roughly the median premium restaurants add on Swiggy/Zomato today |
| D16 | Empty app price: fall back to the dine-in price, or require an app price before a dish is sold online | 2b.3 | Open; suggestion: fall back, so Eat Now looks unchanged until a restaurant sets app prices |
| D17 | Do item/add-on discount percentages apply to both prices; does the slab use the price after a restaurant-funded discount | 2b.3 | Open; suggestion: yes to both. A Ninjasu-funded coupon never changes commission |
| D18 | Same commission plan for Schedule and Eat Now, or separate plans per fulfilment type | 2b.3 | Open |
| D19 | Eat Now orders also record commission and payout snapshots at order time | 2b.3 | Open; suggestion: yes, with prices unchanged |
| D20 | Add-on running out before the dish: reuse the live option's `isAvailable` flag (shared kitchen) or a per-day Schedule flag | 2b.2 | Open; suggestion: reuse `isAvailable` for v1 |
| D21 | Which commission plans exist at launch | Phase 0 (agreement) | Open; suggestion: Standard only, add others when a real restaurant needs one |
| D22 | Ninjasu revenue per order (about 5–10% effective) vs rider cost per order | Before pilot | Open; check with pilot numbers (§4) |
| D23 | What counts as "POS enabled" for dine-in price edits (#48): the owner toggle `pos_enabled` alone is bypassable (turn on, edit, turn off) | 2b.12 | **Decided 2026-10-18:** no POS gate at all; only the Ninjasu admin edits dine-in prices, for every shop (#48) |
| D24 | Restaurant with no plan assigned: reject its dishes from the app / reject checkout (never a silent 0 or Standard fallback, review P21(c)); and whether the first assignment at onboarding is exempt from the notice period (notice applies to changes only) | 2b.13 | Open; suggestion: no plan = not sellable online; first assignment effective immediately with `consent_ref` |
| D25 | Which options show the "Ninjasu keeps ₹X, you get ₹Y" line (#45): the slab is per unit including add-ons, so on an add-on option (Egg ₹20) the line would mislead | After Schedule ships (onboarding revisit) | **Deferred 2026-10-18** by Samivan: decided with the restaurant onboarding revisit, after Schedule is done; not needed for 2b.13. Suggestion kept for then: show it next to each required base option (the ITEM group that sets the base price), computed on that option alone; no line on add-on options; plus one backend-computed "with add-ons" example (Large + Egg + Papad = ₹230 → keeps ₹20, you get ₹210) |
| D26 | A unit cheaper than its slab amount (Codex review 2026-10-18): option prices only need to be above ₹0, so a ₹1-4 unit would pay ₹5 and give a negative payout; a ₹10 tea pays 50% | 2b.13 | Open; suggestion: commission never exceeds half the unit app price (a ₹6 unit pays ₹3), plus a low-price plan for snack and tea shops (D21) |
| D27 | Who sets the dine-in price of an option the restaurant creates itself (a new dish or add-on), now that only the Ninjasu admin edits dine-in prices (#48) | 2b.12 | Open; suggestion: the restaurant enters it once at creation, the option is "dine-in price unverified" and hidden from Schedule until the Ninjasu admin confirms it; later changes are admin-only |

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
- `commission_rate` table + resolver (D13 #22); audit actions to `platform_audit_events`. (Superseded 2026-10-18 by named slab plans, #46; the percentage model has no production caller.)
- Customer read: resolve area by location → modes, slots, cutoffs.
- Hand-run SQL migration + boot guard. **Exit:** the tomorrow path is covered by tests with `advance_days = 1`.

**2b — Orders and stock**
- `orders`: `fulfilment_type` NOT NULL default EAT_NOW, `service_area_id`, `service_date`, slot, `release_at` (epoch ms), status `SCHEDULED`; exhaustive classification test; the live-order read audit (shop board, KDS, getActiveOrder, assign, cancel push, history). **Status groups + read audit done in 2b.1** (backend PR #53, merged 2026-10-17, merge b1a9080): groups LIVE / SCHEDULED_ONLY / GHOST / TERMINAL (SERVED and COLLECTED are TERMINAL); shop board, shop detail, customer active order and KDS exclude SCHEDULED; customer history keeps it; staff `assignDelivery` refuses it (a new guard).
- 2b.2 ships as three PRs: (a) tables + entities + repositories + the one availability resolver + boot guard, consistency test and SQL; (b) shop-side API under `/api/shops/{shopId}/schedule-menu` (list a date, upsert a dish, set order-until for all, copy from another date) with the #50 permissions; (c) `GET /api/schedule/context` gains restaurants and dishes with their availability reason. Readers of area/slot data use `ServiceAreaCatalog`.
- `scheduled_menu_item` + availability resolver; `schedule_reservations` (PK `order_id`) + the single `release(orderId)`; reservation at payment confirm; prepaid-only (`placeOrder` rejects scheduled).
- Release job (catches up after restart), reminder before cutoff; re-verify the refund sweep and reconciliation job against a ~24 h `SCHEDULED` lifetime; fix the payment-confirm refund wait.
- (Added 2026-10-18, #44–#48) 2b.12: dine-in + app price per add-on option with the global cap check and dine-in edit gating; 2b.13: named commission plans + plan assignment + the one slab commission calculator. Both land before pricing (2b.3) and carts (2b.5).
- `CartShopPolicy`. **Exit:** tests for capacity races, cutoff, idempotent release.

**2c — Money snapshot**
- (Updated 2026-10-18, #44–#47; option prices, cap check and the slab calculator moved to 2b.12/2b.13) consumes the 2b snapshots: per-line app price + commission snapshots, plan id + version on the order; order payout + commission amount; `order_charges` for checkout charges; `FeeResolver` (scheduled flat fee branch); packaging line; the rounding function; the shared settleable-order predicate.
- **Exit:** one scheduled and one Eat Now order each show correct charges, payout and totals (the Eat Now payout only if D19 is decided yes); no existing order changes.

**2d — Prep ticket and ops API**
- Derived prep ticket + `ScheduleTicketReleased` event, alarm/push suppression; `/api/ops/**` with area authorization; audit actions for every mutating endpoint.
**Exit (Phase 2):** contracts frozen.

### Phase 3 — Ops board (backend + Ninjasu_Web)
- Admin: Service areas page (modes, window, slots, fees, packaging, advance days), Schedule fields on the Shop page (area, commission plan assignment + consent reference with the notice check; updated 2026-10-18, #46), ops members, Orders filters (mode, slot). Relabel Delivery zones → Rider groups. Commission plans page (create, name, version slab plans, #46); global app-price cap setting with the list of items above it (#47); dine-in price editing for every shop, admin only (#48).
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
- "Upcoming scheduled" separate from live orders, with a **live count per slot and per dish** (paid orders so far, reserved vs stock) that the restaurant can watch before the cutoff; no alarm or push until release; the view polls a light read of the reservation counters, never aggregating orders on every poll; morning entry of the lunch list for a date ("same as yesterday"); restaurant cutoff setting; app price entry per option in the menu editor with the read-only "Ninjasu keeps ₹X, you get ₹Y" line (#44, #45; dine-in price read-only for the restaurant, edited by the Ninjasu admin, #48); screens gated by the `schedule_menu.*` permissions (#50).
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
4. Findings outside Schedule that were logged, not folded in: item stock-ledger credit leaks, dead `findActiveByShopId`, the shop push saying "COD" for every delivery order, delivery orders ignoring shop opening hours. (2b.1, PR #53: the new-order push now says COD only for cash on delivery; `findActiveByShopId` did not exist, so `assignDelivery` got its own guard.)

Final-review decisions are 42-43 above; pricing, commission and menu-permission decisions are 44-50 (2026-10-18); the remaining check (O-3, cart entity) is in the implementation order, section 3.
Implementation order: [schedule-implementation-order.md](schedule-implementation-order.md).
Related: Raphael dossier `brain/dossiers/ninjasu-pos.md` (assumption A8),
[audit-log-plan.md](audit-log-plan.md), [admin-access-redesign.md](admin-access-redesign.md),
[stock-ledger-design.md](stock-ledger-design.md), `06-Rider-App/` (dispatch, manual assign).
