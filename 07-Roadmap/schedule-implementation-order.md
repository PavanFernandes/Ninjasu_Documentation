---
id: ""
title: "Schedule — Final implementation order (phase by phase)"
summary: "Final, ordered task list for every Schedule phase and slice: tables, classes, endpoints, tests, hand-run SQL, rollback and exit checks, parallelism and repo. Built from schedule-plan.md after design reviews 1-3 and two Codex reviews against the backend; contradictions resolved."
type: how-to
status: final-reviewed-2026-10-15
apps: [backend, web, customer, rider]
module: "schedule"
anchors: []
verified_against: "backend main @ 7434fd8 (2026-10-15); code facts re-verified in the final review"
updated: 2026-10-15
review: schedule-design-review.md
---

# Schedule — Final implementation order

**Final review (2026-10-15):** Claude (devil's advocate, Raphael, marketer lenses) and Codex reviewed this plan. Changes folded in: the order/group schema and idempotency keys (2b.4), a resequenced 2b (reservation and refund cores before the payment core), a group refund core with a lease and gateway-receipt dedupe (2b.7), capture-amount validation (2b.9), legacy-endpoint guards, the prepaid `codAmount` fix moved before rider assignment (2d.7), a backend price-preview endpoint instead of web-side pricing (2b.3, 5.1), a CA gate before pricing (0.7), a fulfilment-policy design (plan decision 43), and the ticket-fire rule (plan decision 42). Task ids 2b.4-2b.11 were renumbered.

**Read with:** [schedule-plan.md](schedule-plan.md) (the decisions; numbers `#n` below point to its §3 items) and
[schedule-design-review.md](schedule-design-review.md) (the reasoning, P1–P17).
**Legend:** **[B]** backend · **[W]** Ninjasu_Web · **[C]** Food-Ninja-Frontend (customer app) · **[R]** Ninjasu_Rider_App · **[Biz]** non-code.
**Rules for every slice:** branch from `origin/main`, no worktrees; `/gcp` brief before coding, quick judge before each push; every SQL object is **hand-run** with a boot guard that fails fast if it is missing; tests before the change that needs them; Codex output is re-verified before commit.
**Tests:** the case list is in [schedule-acceptance-tests.md](schedule-acceptance-tests.md); write a slice's cases as failing tests before its code.
**Tracking:** each task has an id (e.g. `2b.3`). Mark progress in the "Status" column of §1, not in prose.

## 1. Tracker

| Slice | What it delivers | Depends on | Status |
|---|---|---|---|
| 0 | Runway: payment re-review, device tests, staff ADR, pilot setup | — | not started |
| 2a | Areas, slots, dates, commission rates, audit plumbing | 0.5 (ADR) for 2a.5 only | not started |
| 2b | Pricing, order/group schema, carts, reservations, group refund core, checkout contract, group payment core, cancellation, release job | 2a, 0.2, 0.7 (for 2b.3) | not started |
| 2c | Settlement inputs and export-grade snapshots | 2b | not started |
| 2d | Tickets, customer notifications, ops API, address fix, prepaid delivery fix, frozen contracts | 2b | not started |
| 3 | Ops board, group batching, settlement export | 2c, 2d (incl. 2d.7) | not started |
| 4 | Customer app | 2d contracts frozen | not started |
| 5 | Restaurant side | 2d | not started |
| 6 | Rider batching + rider-app prepaid completion | 3 | not started |
| 7 | HSR pilot | all above + Phase 0 business items | not started |
| 8 | Numbers + iterate | 7 | not started |

## 2. Code facts this plan is built on (verified 2026-10-15)

- `SHOP_BOARD_ACTIVE_STATUSES` is derived from all statuses minus terminal/ghost (`OrderServiceImpl.java:55`): a new status leaks onto the live board unless classified explicitly.
- `orders.razorpay_order_id` is UNIQUE (`Order.java:153`); `payment.captured` / `order.paid` resolve it with `findByRazorpayOrderId` (`PaymentServiceImpl.java:447`), while `refund.processed` resolves by `findByRazorpayPaymentId` (`:502`) and only acts on `REFUND_PENDING` orders (`:507`): one payment = one order today.
- `orders.idempotency_key` is NOT NULL and globally UNIQUE (`Order.java:88`): a multi-order checkout needs one derived key per member order.
- Checkout and refund use `order.getGrandTotal()` (`PaymentServiceImpl.java:170, 641`); refunds are whole-order, with receipt `refund-<orderId>` as the gateway dedupe key (`:649`). Confirm (`doConfirmPayment`, `:265-342`) neither validates nor stores the gateway's captured amount. `attemptGatewayRefund(orderId, shopId)` loads a shop and its settlement strategy (`:623-638`); the hourly sweep scans only `Order.paymentStatus = REFUND_PENDING` (`:680`); confirm completes the cart by user + cart type (`:309-310`).
- `getOrderHistory` returns every non-ghost order (`OrderServiceImpl.java:173`). The seller-transition switch has `default -> false` (`:375-383`), so a new enum value compiles; the leak is the derived board list (`:55-58`).
- Confirm decrements the live stock ledger and publishes `OrderPlacedEvent`.
- `cart_sessions.shop_id` is NOT NULL (`CartSession.java:24`); `addToCart` rejects a second shop.
- `OrderAssembler` is single-shop: one radius check (`:108-116`), one `computeDeliveryFee` from shop `DeliveryConfig` (`:304`).
- `assignDelivery` snapshots `codAmount = order.getGrandTotal()` for every order (`DeliveryServiceImpl.java:285`); a delivery has one `shop_id` and one `order_id`.
- Route split transfers the full grand total to the shop (`RouteSplitSettlement.java:39`); no commission exists in code.
- Existing jobs: `PaymentReconciliationJob` (hourly), `ItemStockResetJob` (03:00 IST).
- Shop audit: `AuditAction` enum + `AuditRecorder` (transaction-mandatory); no Schedule actions yet.

## Phase 0 — Runway

| # | Task | Repo | Notes |
|---|---|---|---|
| 0.1 | Restaurant agreement (D11) signed with the first HSR restaurants; split price ≤ dine-in; commission notice + consent | Biz | lawyer review; CA questions deferred, ask before Phase 7 |
| 0.2 | Adversarial re-review of online payment (checkout, verify, webhook-first, verify-first, stock failure, cancel, decline, refund retry) and fix the missing immediate refund after a confirm-time stock failure (`PaymentServiceImpl.java:323-328` sets `REFUND_PENDING` but schedules no attempt); the fast-path test (T0-05) must pass before 2b.9 starts | B | do it with 2b.9 in mind: the group payment core reuses this code |
| 0.3 | Device-test the delivery loop; confirm prod `deliveries.created_by_staff_id` is nullable | R+B | |
| 0.4 | Pilot setup: boundary, office cluster, riders, a named manual-payout operator; pilot shops are `SINGLE_MERCHANT` | Biz | Route split cannot carry commission |
| 0.5 | Staff ADR: `admin-access-redesign.md` supersedes its proposal but still describes `platform_staff` for area roles. Decide `service_area_staff(user_id, service_area_id, role)` vs `platform_staff` | B | needed before 2a.5 and 2d.4 |
| 0.6 | Verify customer push delivery works on the app (prerequisite for 2d.2 notifications) | C+B | |
| 0.7 | **CA gate for pricing (before 2b.3).** Ask the CA: does a menu price built as split + commission, set by Ninjasu, keep the restaurant the supplier under section 9(5)? GST on commission, delivery and packaging; the FSSAI position. 2b.3 writes this model into the schema, so the answer is cheaper before than after | Biz | the remaining CA questions can wait until Phase 7 |

Parallel: all. Rollback: online payment stays off, no Schedule menu listed. **Exit:** a prepaid single-restaurant delivery order works end to end on phones.

## Phase 2a — Areas, dates, slots, rates (additive; a shop with no area behaves as today)

| # | Task | Tests |
|---|---|---|
| 2a.1 | `service_area(id, name, center_lat, center_lng, radius_m, timezone, eat_now_enabled, schedule_enabled CHECK at least one, paused_on, advance_days CHECK 0..1, window_open_day_offset, window_open_time, last_call_minutes, pickup_lead_minutes, schedule_delivery_fee ≤ 10, schedule_packaging_fee, `schedule_max_shops_per_cart INT NOT NULL DEFAULT 3 CHECK ≥ 1` (a group travels in one batch, so the cap bounds pickup stops), commission_notice_days, ...)`; `service_area_slot(id, service_area_id, start_local_time, capacity, active)` unique `(service_area_id, start_local_time)`. Classes `FulfilmentType {EAT_NOW, SCHEDULE}`, `ServiceArea`, `ServiceAreaSlot`, `ServiceDateResolver` (the only code that computes dates and "orderable now"), `ServiceAreaResolver`, `ScheduleEligibilityService` + one SQL fragment | today/tomorrow with `advance_days=1`, timezone, pause, overlap, one validator (no mode, duplicate slot, window after first last call, capacity < 1, fee > 10) |
| 2a.2 | `shops.service_area_id UUID NULL` (no FK); `PUT /api/admin/shops/{shopId}/schedule-assignment`, admin only; owner DTOs cannot write it | ADMIN allowed, SHOP forbidden, NULL = legacy |
| 2a.3 | `POST/GET/PUT /api/admin/service-areas`, `POST/PUT/DELETE .../{areaId}/slots`; public `GET /api/schedule/context?lat=&lng=&serviceDate=` (modes, slots, last calls, open restaurants) | contract tests |
| 2a.4 | `commission_rate(id, scope_type, shop_id NULL, service_area_id NULL, fulfilment_type, rate_percent, effective_from TIMESTAMPTZ, consent_ref, created_by, created_at)`; exactly one scope; shop rate overrides area rate; insert rejected unless `effective_from ≥ now + commission_notice_days`; `CommissionRateResolver.rateAt(shop, instant)` picks the latest row with `effective_from ≤ instant`. **The rate is resolved at checkout time** (#33). `POST/GET /api/admin/commission-rates` | precedence; notice rule; a tomorrow order placed today keeps today's rate; later rate rows never change existing orders |
| 2a.5 | `platform_audit_events` + `PlatformAuditRecorder` (append-only trigger) if missing; every 2a mutation audited; add Schedule values to shop `AuditAction` for restaurant edits (used in 2b.6) | mutation writes a row; unaudited-mutator declaration test; boot guard |
| 2a.6 | Boot guards for all hand-run objects | boot fails with a clear message per missing object |

Parallel: 2a.2 and 2a.4 after 2a.1; 2a.5 after 0.5. Rollback: `schedule_enabled=false`. **Exit:** tomorrow-path tests pass; a shop with no area is unchanged.

## Phase 2b — Pricing, carts, order groups, group payment, reservations

Order inside 2b is strict: pricing and the checkout contract exist before any Razorpay order is created for Schedule.

**Flexibility rule (plan decision 43).** Nothing in 2b hard-codes "Schedule" or "one shop". A `FulfilmentPolicy` per fulfilment type owns the differences (max shops per cart, payment owner kind, location policy, cancellation rule, reservation and release rules); the order group, payment owner, refund core and cart keying are generic over `fulfilment_type`. Multi-restaurant is on only for Schedule today; turning it on for another type later is a new policy plus UI, not a schema or payment-core change.

| # | Task | Tests |
|---|---|---|
| 2b.1 | **Order status classification.** `OrderStatus.SCHEDULED`; explicit sets LIVE / SCHEDULED_ONLY / GHOST / TERMINAL replace the derived board list; exclude `SCHEDULED` from shop board, shop detail, `getActiveOrder`, KDS, dispatch, shop push; `assignDelivery` rejects it; delete or fix dead `findActiveByShopId`; fix the "COD" push text | every enum value in exactly one set; each excluded read verified |
| 2b.2 | **Schedule menu (Zepto-style).** `scheduled_menu_item(id, shop_id, service_date, item_id, stock_qty, reserved_qty, order_until TIME, split_price, active, copied_from_id, ...)` unique `(shop_id, service_date, item_id)`, CHECK `0 ≤ reserved_qty ≤ stock_qty`; `service_area_slot_day(id, service_area_slot_id, service_date, capacity, reserved_groups)` unique `(slot, date)`. One availability resolver: item active AND row for date AND stock > reserved AND now < min(order_until, slot last call) AND shop assigned AND area enabled and not paused AND date within window/advance days AND slot valid. **v1: Schedule dishes carry no paid add-ons** (pending Samivan's OK) | each availability condition has its own failing test; restock and extended order-until reopen a dish; stock below reserved rejected |
| 2b.3 | **Pricing.** `MenuPriceResolver` (menu price = split + round-to-nearest-rupee of rate × split), `FeeResolver` (Schedule flat area fee and packaging; runs before and instead of `computeDeliveryFee` for Schedule), `RoundingPolicy` (one function: whole-rupee bill with a round-off line) Also `GET /api/shops/{shopId}/schedule-menu/price-preview?splitPrice=` returns the menu price from `MenuPriceResolver`, so the web app never re-implements the rule (5.1). | Schedule fee ignores `DeliveryConfig`; Eat Now unchanged; totals = lines + charges; the preview endpoint equals the checkout price for the same rate |
| 2b.4 | **Order and group schema (hand-run SQL + boot guards).** `orders`: `fulfilment_type` NOT NULL DEFAULT `EAT_NOW`, `service_area_id`, `service_date`, `slot_id`, `group_id`, `order_code`, `release_at` (epoch ms = the order's locked cutoff, NULL = not scheduled), `payout_amount`, `commission_amount`, `original_payout_amount`, `refunded_amount` DEFAULT 0, `refund_state` (NONE/PARTIAL/FULL); unique `(service_area_id, service_date, order_code) WHERE order_code IS NOT NULL`; partial index `(release_at) WHERE status = 'SCHEDULED'`. `order_lines`: `split_price`, `menu_price`, `commission_amount` snapshots. `order_charges(id, order_id NULL, group_id NULL, type, amount)` CHECK exactly one owner (delivery and packaging belong to the group, never to a restaurant's order). `order_groups(id, fulfilment_type, group_code, checkout_idempotency_key UNIQUE NOT NULL, customer_id, service_area_id, service_date, slot_id, address snapshot, razorpay_order_id UNIQUE, razorpay_payment_id UNIQUE NULL, payment_status, captured_amount, refunded_amount, delivery_fee, packaging_fee, earliest_locked_cutoff_at NULL = no member reserved yet, created_at)` unique `(service_area_id, service_date, group_code)`. **Idempotency:** `orders.idempotency_key` is NOT NULL and globally UNIQUE (`Order.java:88`), so the group carries the client's key and each member order gets the deterministic key `sha256hex(groupKey + ':' + shopId)` (64 chars); a retry recomputes the same keys. **Legacy guards:** `getOrderHistory` (`OrderServiceImpl.java:173`) filters `group_id IS NULL` until 4.4 ships the group read; legacy `cancelOrder` (`:184`), seller decline / status endpoints and the payment-cancel endpoint reject any order with a `group_id` (typed error; the group entry points arrive in 2b.10) | Eat Now rows unchanged (new columns NULL/default); a retry yields the same keys and no second row; a member order cannot be cancelled or declined through a legacy endpoint; history excludes members; boot guard names each missing object |
| 2b.5 | **Carts.** A Schedule cart has its own cart type and is keyed by user + SCHEDULE + service date + slot: confirm completes the cart by user + cart type (`PaymentServiceImpl.java:309-310`), so a shared type would complete or collide with an Eat Now cart. `cart_sessions.shop_id` becomes nullable with `CHECK (fulfilment_type = 'SCHEDULE' OR shop_id IS NOT NULL)`; each Schedule cart line carries its own `shop_id` (verify the line entity and the cart-type enum in the /gcp brief). Eat Now keeps its one-shop rule (`CartSession.java:24`, `addToCart`). A `FulfilmentPolicy` per fulfilment type (shop limit per cart, payment owner kind, location policy, cancellation rule, reservation and release rules; Eat Now = 1 shop and order-level payment, Schedule = the area's `schedule_max_shops_per_cart` and group payment) replaces the hard-coded checks: `CartShopPolicy` + a fulfilment-aware location policy (Schedule resolves the area and skips the shop radius check at `OrderAssembler.java:108-116`) | Eat Now one-shop conflict still raised; Schedule cart cannot mix date/slot/area; mixed shops allowed; confirming a Schedule group never completes or collides with an Eat Now cart; the shop limit comes from the policy (Eat Now 1, Schedule = the area setting, a shop over the limit is rejected) |
| 2b.6 | **Reservations.** `schedule_reservations(order_id PK, slot_day_id, status, reserved_at, voided_at, void_reason)` + lines; slot capacity reserved **once per group**, dish stock per member order, conditional UPDATEs, compensation only of own writes. `ScheduleReservationService.reserveAtConfirm`, `voidReservation(orderId, reason)` (frees capacity when the last group member is voided). Restaurant edits to stock / order-until / split price via `PUT /api/shops/{shopId}/schedule-menu/{serviceDate}/items/{itemId}` audited in shop `audit_events` with before/after | final-unit and final-capacity races; duplicate confirm; edit never moves an existing order's locked cutoff |
| 2b.7 | **Group refund core (built before the payment core that calls it).** `group_refunds(id, group_id, amount, reason, state, claimed_by, lease_until, gateway_receipt UNIQUE, gateway_refund_id UNIQUE NULL, created_at)` plus `group_refund_allocations(id, refund_id, order_id NULL, component, amount)`, so one gateway refund can span several member orders and group charges; states `PENDING → SUBMITTING (lease) → ISSUED → PROCESSED / FAILED`. `GroupRefundService.request(...)` locks the group row and checks `refunded_amount + open requests + amount ≤ captured_amount` (open requests = PENDING, SUBMITTING and ISSUED amounts, counted until PROCESSED or FAILED) and, per order, `refunded_amount + amount ≤ order grand total`, then inserts the request and its allocations and updates each member's `refunded_amount` / `refund_state` in the same transaction (reverted if the request FAILS). A worker claims a row atomically (CAS to SUBMITTING with a lease), calls Razorpay with `receipt = 'gr-' + id` (the gateway dedupes on receipt, as legacy does with `refund-<orderId>`, `PaymentServiceImpl.java:649`) and stores `gateway_refund_id`. An expired lease is reconciled first (fetch the payment's refunds, match the receipt) and re-sent only if absent. Group refunds use the platform Razorpay account and load no shop (legacy `attemptGatewayRefund(orderId, shopId)` needs one, `:623-638`). The hourly sweep gets a second query over `group_refunds` (legacy scans only `Order.paymentStatus = REFUND_PENDING`, `:680`); `refund.processed` resolves `gateway_refund_id` first, then the receipt (it can arrive before the id is saved; the handler is idempotent), then falls back to the legacy payment-id path (`:502`). **Allocation invariant:** a member order's refundable amount is its grand total (items + tax + its own round-off, whole rupees, fixed at checkout); group charges are refundable at group level only, the delivery fee only when the last member is cancelled. A partial line refund = old order grand total − recomputed grand total (one function); the order's `payout_amount` and `commission_amount` are recomputed from the remaining lines (originals kept) and `refunded_amount` / `refund_state` update in the same transaction | two workers claim one row: one gateway call; Razorpay accepts then the local save fails: reconcile finds the receipt, no second refund; concurrent decline + cancel cannot exceed captured or an order's total; delivery fee refunded once; `refund.processed` flips the right row, including when it arrives before the gateway id is saved; one refund spanning two member orders updates both; legacy refund tests green |
| 2b.8 | **Checkout contract.** Reject a group containing any shop whose settlement is not `SINGLE_MERCHANT` (Route split cannot carry commission; the group is paid to the platform account). Re-price from the server (rate at checkout); if the price differs from the cart return a typed `PRICE_CHANGED` with the new per-order and group totals and require reconfirmation. Then, idempotently on the 2b.4 keys: create the group and one order per shop (per-line split and menu price, commission, order payout, `order_charges`, suffix A/B/C by shop order; `release_at` is set at confirm), then the Razorpay order for the group total on the platform account through a group settlement path with no shop. Same shape as legacy: persist in a transaction, call Razorpay outside any DB transaction, store the gateway id in a second transaction (`PaymentServiceImpl.java:160-199`). Response: `groupId`, group code, member order codes, Razorpay order id, amount | two shops → one group, `XXXX-A`/`XXXX-B`; retry idempotent; price change forces reconfirm; a `ROUTE_SPLIT` shop is rejected; Eat Now checkout response unchanged |
| 2b.9 | **Group payment core.** Extract one shared core (signature check, payment-status CAS, Razorpay calls) that depends on a `PaymentOwner` abstraction (`LegacyOrderOwner`, `OrderGroupOwner`) and not on Schedule, so another fulfilment type can use group payment later with no core change. Verify, webhook, reconciliation, cancel-before-capture and stale-checkout handling first resolve the **payment owner** (the gateway order id is looked up in `orders`, `:447`, then in `order_groups`), then run idempotently. **Capture validation:** legacy confirm neither reads nor stores the gateway's captured amount (`doConfirmPayment`, `:265-301`); the group path reads the payment entity, requires status = captured, `order_id` = the group's Razorpay order id, amount (paise) = group total and currency = INR before the CAS, and stores `captured_amount` and `razorpay_payment_id`; on any mismatch it first persists the actual payment id and captured amount durably (group marked `CAPTURE_MISMATCH`), raises an alert, then refunds the whole capture through 2b.7. CAS group `CREATED → PAID` once. Then each member order in turn reserves its dishes (2b.6): successes → `SCHEDULED` with `release_at` = locked cutoff; failures → partial-refund requests (2b.7); `earliest_locked_cutoff_at` = min over successes; if none succeed, a full refund including group charges. Complete the Schedule cart. **No live stock ledger write and no `OrderPlacedEvent` on any confirm route.** Webhook audit rows record the group and member orders. Reconciliation queries pending groups by the group Razorpay id; the legacy per-order path is kept | webhook-first, verify-first, duplicate, concurrent, reconciliation, partial failure, all-failed, capture amount mismatch; legacy suite still green |
| 2b.10 | **Cancellation and decline flows.** Customer cancel = the whole group before `earliest_locked_cutoff_at` (`POST /api/schedule/groups/{groupId}/cancel`): void all reservations, one refund request (2b.7). Restaurant decline and ops cancel stay per order → partial refund request. Immediate refund attempt after commit; hourly retry kept; reconciliation and the orphan sweep skip a paid `SCHEDULED` order hours from release | concurrent decline + cancel cannot over-refund; fee refunded once; cancel after cutoff rejected; jobs ignore a SCHEDULED order |
| 2b.11 | **Release job.** `ScheduleReleaseJob` + `releaseForFulfilment` CAS `SCHEDULED → PLACED` where `release_at ≤ now`; keeps the reservation; restart catch-up; publishes ticket-level events only (2d.1). Off until 2d; the ticket fires at the slot's last call (plan decision 42) | two instances, repeat run, restart, voided order ignored |

Order: 2b.1 and 2b.2 first (parallel); 2b.3 → 2b.4; then 2b.5, 2b.6 and 2b.7 in parallel (all need 2b.4); 2b.8 (needs 2b.3, 2b.4, 2b.5); 2b.9 (needs 2b.6, 2b.7, 2b.8); 2b.10; 2b.11 after 2b.1, 2b.4, 2b.6 and 2b.9. Rollback: Schedule checkout off; an operator script voids and refunds every `SCHEDULED` group before access is removed; populated tables are never dropped. **Exit:** races, cutoff, duplicate payment, capture mismatch, partial failure, over-refund, gateway-ambiguity refund, cancel, and idempotent release tests pass; legacy payment tests green.

## Phase 2c — Settlement inputs

| # | Task | Tests |
|---|---|---|
| 2c.1 | `SettleableOrderPredicate` (DELIVERED, not refunded/refund-pending), shared by the export and Numbers | status × refund matrix |
| 2c.2 | Export-grade fields: group captured/refunded, group delivery and packaging (Ninjasu revenue, never a restaurant's), per-order split, commission, payout; documented allocation rules | one group with a partial refund reconciles to Razorpay |
| 2c.3 | Rejection of `ROUTE_SPLIT` shops is enforced at checkout (2b.8); here only the settlement export asserts no Route-split group exists | export guard test |

**Exit:** a two-restaurant group with one partial refund reconciles: Razorpay captured − refunds = payouts + commission + group charges.

## Phase 2d — Tickets, notifications, ops API, frozen contracts

| # | Task | Tests |
|---|---|---|
| 2d.1 | `schedule_ticket_publications(shop_id, service_date, slot_id, version, payload_json incl. order codes + group codes + pickup-by, published_at)` + `schedule_ticket_amendments` (append-only); a **draft ticket** that updates live from the first paid order (same in-process cache as 2d.3, read-only, no alarm), frozen as publication v1 at the slot's last call (plan decision 42), one `ScheduleTicketReleased` event per shop/date/slot; changes after v1 append amendments; ticket status derived from member orders; per-order shop alarms and cancel pushes suppressed for Schedule | 14 orders → one event, zero early alarms; late order → amendment |
| 2d.2 | Customer notifications **per group**: paid, reminder before cutoff, being prepared, picked up, delivered, refunded (full/partial with reason); member-order events aggregated, idempotent | two-restaurant group gets one push per stage |
| 2d.3 | Live counts endpoint for restaurants from an **in-process cache** (refresh ≤ 30 s; updated on reserve/void); no Postgres query per poll | load test: polls never hit the DB |
| 2d.4 | Staff per ADR (0.5), `AreaAccessService`, `/api/ops/**` matcher; handlers load the resource and read its area; ADMIN bypass audited | cross-area denial; forged area id ignored |
| 2d.5 | Ops address correction for a group, before batching only (rejected once batched unless the group is removed first), audited | guard + audit tests |
| 2d.7 | **Prepaid delivery fix [B].** `assignDelivery` snapshots `codAmount = order.getGrandTotal()` for every order (`DeliveryServiceImpl.java:285`) and the dispatch notification sends it (`DeliveryDispatchListener.java:138`): set `codAmount = 0` for online-paid orders, make rider completion skip the cash step when expected is zero, keep proof/OTP. Must land before 3.3 (batch assignment) | COD delivery still collects cash; prepaid delivery has `codAmount` 0 in the delivery and in the notification |
| 2d.6 | Freeze contracts: board, tickets (accept/ready/handover fan-out through the existing transition validator; "can't make" as a pending request (a `ticket_issue` row: ticket, orders, dish, qty, status PENDING/APPROVED/REJECTED, decided_by) that only ops approval turns into per-order cancellation + partial refund + ticket amendment (plan item 41)), ops cancel, labels data (`4821-A · Asha · 3 items`) | contract + authorization + audit tests |

**Exit (Phase 2):** contracts versioned, authorized, audited; fixtures published for web, customer and rider apps.

## Phase 3 — Ops board [B+W]

| # | Task |
|---|---|
| 3.1 | [W] Admin screens: service areas (window, last call, pickup lead, slots, fees, packaging, advance days), shop assignment, commission rates with consent reference and the notice check, audit view, Orders filters (mode, slot); a list showing each dish's split price next to its dine-in price for the team's review |
| 3.2 | [B] Batches by **group**: `schedule_batches`, `schedule_batch_groups(group_id UNIQUE)`, append-only `batch_events` (per-shop pickup/handover, group drop), `drop_points`; endpoints add/remove **groups** only, assign rider |
| 3.3 | [B] (needs 2d.7) `deliveries.batch_id` + `BatchDeliveryService.assignBatch` (one delivery per member order, all on the batch; atomic) moved here from Phase 6 so the board can assign riders end to end |
| 3.4 | [W] Board: slot columns, capacity/cutoff, ticket state, map of group drops, unbatched and late-order warnings, problem queue with pending "can't make" approvals (approve, reject, choose which orders), batch sheet with labels |
| 3.5 | [B+W] Settlement export (XLSX via reports infrastructure): per restaurant rows + group section, group/order codes, refunds |

**Exit:** a manager runs a simulated lunch: batch groups, assign a rider, export settlement.

## Phase 4 — Customer app [C]

| # | Task |
|---|---|
| 4.1 | Area bootstrap from `/api/schedule/context`; first-open HSR screen; never infer availability client-side |
| 4.2 | Slot first, then restaurants and dishes greyed per slot ("order by 11:30", "sold out", "closed for this slot"); day picker only when `advance_days > 0`; restock appears on refresh |
| 4.3 | Multi-restaurant Schedule cart; checkout with itemized fee lines; handle `PRICE_CHANGED` reconfirmation; prepaid Razorpay only; cutoff crossed while the sheet is open |
| 4.4 | One group card for upcoming/tracking with member order codes; whole-group cancel before the cutoff; all group notifications from 2d.2 |

**Exit:** a customer schedules from two restaurants, pays once, sees fees, cancels before cutoff, tracks.

## Phase 5 — Restaurant side [W]

| # | Task |
|---|---|
| 5.1 | Daily lunch list: stock + order-until per dish, "set time for all dishes", restock, reopen, "same as yesterday", split price with the menu price fetched from the backend preview endpoint (2b.3); the web app never computes it |
| 5.2 | Upcoming Scheduled view with live counts per slot and dish (2d.3) |
| 5.3 | Ticket view: one accept / ready / handover, pickup-by time, order codes, "can't make" request (pending until ops approves), amendments |

**Exit:** a restaurant publishes its list, watches demand, preps from one ticket.

## Phase 6 — Rider [B+R]

| # | Task |
|---|---|
| 6.1 | [R] Rider app: no cash step when the delivery's expected cash is zero; prepaid shown on the card (the backend part is 2d.7) |
| 6.2 | [B] Rider batch APIs: `GET /api/rider/batches/active`, pickup per shop, **group drop completion** that completes every member delivery together; a member order is never assigned or completed alone |
| 6.3 | [R] Batch card: ordered pickups, grouped drops with labels, notes, proof per D5, prepaid display |

**Exit:** a rider completes a multi-shop, multi-drop batch with no cash step.

## Phase 7 — HSR pilot [Biz + all]
One Schedule-only area, few restaurants, two lunch riders, one office cluster, behind flags. Daily ops on the board; weekly reconciliation (Razorpay vs charges vs payouts vs export); kill criterion revisited before start and tracked weekly; every manual workaround logged. Rollback: `schedule_enabled=false`, finish or refund open groups, keep evidence.

## Phase 8 — Numbers and iteration
Numbers from immutable orders, groups, charges, reservations, batches; then `settled_at` + `settlement_ref`, customer-chosen drop points and auto-grouping, tomorrow switch-on, Eat Now in HSR, in-app commission acceptance, Razorpay Route platform share, paid add-ons on Schedule dishes. Each behind its own flag and ADR.

## 3. Open items (do not block Phase 2a)
- **Decided 2026-10-15 (Samivan):** ticket fires at the slot's last call and is visible live as a draft before then (plan decision 42); multi-restaurant is Schedule-only today, built policy-driven so other fulfilment types can adopt it later (plan decision 43).
- **O-2 (closed):** see the decided line above; groups of one are not a separate first build.
- **O-3 (agreed, do in the /gcp brief before 2b.5):** read the cart line entity and the cart-type enum; confirm no other code path reads `orders` assuming one shop per payment.
- Paid add-ons on Schedule dishes in v1: proposed **no** (2b.2), awaiting Samivan.
- Staff ADR (0.5): blocks 2a.5 and 2d.4 only.
- CA questions (deferred): marketplace/ECO model, GST on commission/fees, menu price built as split + commission, FSSAI position.
- D5 handover proof, D7 accept check (later phases).
