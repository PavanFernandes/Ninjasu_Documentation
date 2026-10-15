---
id: ""
title: "Schedule — Final implementation order (phase by phase)"
summary: "Final, ordered task list for every Schedule phase and slice: tables, classes, endpoints, tests, hand-run SQL, rollback and exit checks, parallelism and repo. Built from schedule-plan.md after design reviews 1-3 and two Codex reviews against the backend; contradictions resolved."
type: how-to
status: final-for-review
apps: [backend, web, customer, rider]
module: "schedule"
anchors: []
verified_against: "backend main @ 7434fd8 (2026-10-15)"
updated: 2026-10-15
review: schedule-design-review.md
---

# Schedule — Final implementation order

**Read with:** [schedule-plan.md](schedule-plan.md) (the decisions; numbers `#n` below point to its §3 items) and
[schedule-design-review.md](schedule-design-review.md) (the reasoning, P1–P17).
**Legend:** **[B]** backend · **[W]** Ninjasu_Web · **[C]** Food-Ninja-Frontend (customer app) · **[R]** Ninjasu_Rider_App · **[Biz]** non-code.
**Rules for every slice:** branch from `origin/main`, no worktrees; `/gcp` brief before coding, quick judge before each push; every SQL object is **hand-run** with a boot guard that fails fast if it is missing; tests before the change that needs them; Codex output is re-verified before commit.
**Tracking:** each task has an id (e.g. `2b.3`). Mark progress in the "Status" column of §1, not in prose.

## 1. Tracker

| Slice | What it delivers | Depends on | Status |
|---|---|---|---|
| 0 | Runway: payment re-review, device tests, staff ADR, pilot setup | — | not started |
| 2a | Areas, slots, dates, commission rates, audit plumbing | 0.5 (ADR) for 2a.5 only | not started |
| 2b | Pricing + checkout contract, carts, order groups, group payment core, reservations, cancellation, release job | 2a, 0.2 | not started |
| 2c | Settlement inputs and export-grade snapshots | 2b | not started |
| 2d | Tickets, customer notifications, ops API, address fix, frozen contracts | 2b | not started |
| 3 | Ops board, group batching, settlement export | 2c, 2d | not started |
| 4 | Customer app | 2d contracts frozen | not started |
| 5 | Restaurant side | 2d | not started |
| 6 | Rider batching + prepaid completion | 3 | not started |
| 7 | HSR pilot | all above + Phase 0 business items | not started |
| 8 | Numbers + iterate | 7 | not started |

## 2. Code facts this plan is built on (verified 2026-10-15)

- `SHOP_BOARD_ACTIVE_STATUSES` is derived from all statuses minus terminal/ghost (`OrderServiceImpl.java:55`): a new status leaks onto the live board unless classified explicitly.
- `orders.razorpay_order_id` is UNIQUE (`Order.java:153`) and the webhook resolves only `findByRazorpayOrderId` (`PaymentServiceImpl.java:447`): one payment = one order today.
- Checkout, confirm and refund use `order.getGrandTotal()` (`PaymentServiceImpl.java:170, 227, 641`); refunds are whole-order.
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
| 0.2 | Adversarial re-review of online payment (checkout, verify, webhook-first, verify-first, stock failure, cancel, decline, refund retry) and fix the missing immediate refund after a confirm-time stock failure | B | do it with 2b.4 in mind: the group payment core reuses this code |
| 0.3 | Device-test the delivery loop; confirm prod `deliveries.created_by_staff_id` is nullable | R+B | |
| 0.4 | Pilot setup: boundary, office cluster, riders, a named manual-payout operator; pilot shops are `SINGLE_MERCHANT` | Biz | Route split cannot carry commission |
| 0.5 | Staff ADR: `admin-access-redesign.md` supersedes its proposal but still describes `platform_staff` for area roles. Decide `service_area_staff(user_id, service_area_id, role)` vs `platform_staff` | B | needed before 2a.5 and 2d.4 |
| 0.6 | Verify customer push delivery works on the app (prerequisite for 2d.2 notifications) | C+B | |

Parallel: all. Rollback: online payment stays off, no Schedule menu listed. **Exit:** a prepaid single-restaurant delivery order works end to end on phones.

## Phase 2a — Areas, dates, slots, rates (additive; a shop with no area behaves as today)

| # | Task | Tests |
|---|---|---|
| 2a.1 | `service_area(id, name, center_lat, center_lng, radius_m, timezone, eat_now_enabled, schedule_enabled CHECK at least one, paused_on, advance_days CHECK 0..1, window_open_day_offset, window_open_time, last_call_minutes, pickup_lead_minutes, schedule_delivery_fee ≤ 10, schedule_packaging_fee, commission_notice_days, ...)`; `service_area_slot(id, service_area_id, start_local_time, capacity, active)` unique `(service_area_id, start_local_time)`. Classes `FulfilmentType {EAT_NOW, SCHEDULE}`, `ServiceArea`, `ServiceAreaSlot`, `ServiceDateResolver` (the only code that computes dates and "orderable now"), `ServiceAreaResolver`, `ScheduleEligibilityService` + one SQL fragment | today/tomorrow with `advance_days=1`, timezone, pause, overlap, one validator (no mode, duplicate slot, window after first last call, capacity < 1, fee > 10) |
| 2a.2 | `shops.service_area_id UUID NULL` (no FK); `PUT /api/admin/shops/{shopId}/schedule-assignment`, admin only; owner DTOs cannot write it | ADMIN allowed, SHOP forbidden, NULL = legacy |
| 2a.3 | `POST/GET/PUT /api/admin/service-areas`, `POST/PUT/DELETE .../{areaId}/slots`; public `GET /api/schedule/context?lat=&lng=&serviceDate=` (modes, slots, last calls, open restaurants) | contract tests |
| 2a.4 | `commission_rate(id, scope_type, shop_id NULL, service_area_id NULL, fulfilment_type, rate_percent, effective_from TIMESTAMPTZ, consent_ref, created_by, created_at)`; exactly one scope; shop rate overrides area rate; insert rejected unless `effective_from ≥ now + commission_notice_days`; `CommissionRateResolver.rateAt(shop, instant)` picks the latest row with `effective_from ≤ instant`. **The rate is resolved at checkout time** (#33). `POST/GET /api/admin/commission-rates` | precedence; notice rule; a tomorrow order placed today keeps today's rate; later rate rows never change existing orders |
| 2a.5 | `platform_audit_events` + `PlatformAuditRecorder` (append-only trigger) if missing; every 2a mutation audited; add Schedule values to shop `AuditAction` for restaurant edits (used in 2b.7) | mutation writes a row; unaudited-mutator declaration test; boot guard |
| 2a.6 | Boot guards for all hand-run objects | boot fails with a clear message per missing object |

Parallel: 2a.2 and 2a.4 after 2a.1; 2a.5 after 0.5. Rollback: `schedule_enabled=false`. **Exit:** tomorrow-path tests pass; a shop with no area is unchanged.

## Phase 2b — Pricing, carts, order groups, group payment, reservations

Order inside 2b is strict: pricing and the checkout contract exist before any Razorpay order is created for Schedule.

| # | Task | Tests |
|---|---|---|
| 2b.1 | **Order status classification.** `OrderStatus.SCHEDULED`; explicit sets LIVE / SCHEDULED_ONLY / GHOST / TERMINAL replace the derived board list; exclude `SCHEDULED` from shop board, shop detail, `getActiveOrder`, KDS, dispatch, shop push; `assignDelivery` rejects it; delete or fix dead `findActiveByShopId`; fix the "COD" push text | every enum value in exactly one set; each excluded read verified |
| 2b.2 | **Schedule menu (Zepto-style).** `scheduled_menu_item(id, shop_id, service_date, item_id, stock_qty, reserved_qty, order_until TIME, split_price, active, copied_from_id, ...)` unique `(shop_id, service_date, item_id)`, CHECK `0 ≤ reserved_qty ≤ stock_qty`; `service_area_slot_day(id, service_area_slot_id, service_date, capacity, reserved_groups)` unique `(slot, date)`. One availability resolver: item active AND row for date AND stock > reserved AND now < min(order_until, slot last call) AND shop assigned AND area enabled and not paused AND date within window/advance days AND slot valid. **v1: Schedule dishes carry no paid add-ons** (pending Samivan's OK) | each availability condition has its own failing test; restock and extended order-until reopen a dish; stock below reserved rejected |
| 2b.3 | **Pricing.** `MenuPriceResolver` (menu price = split + round-to-nearest-rupee of rate × split), `FeeResolver` (Schedule flat area fee and packaging; runs before and instead of `computeDeliveryFee` for Schedule), `RoundingPolicy` (one function: whole-rupee bill with a round-off line) | Schedule fee ignores `DeliveryConfig`; Eat Now unchanged; totals = lines + charges |
| 2b.4 | **Carts.** Schedule cart that holds several shops with one area, date, slot, address and mode; Eat Now `cart_sessions.shop_id` behaviour unchanged (e.g. Schedule cart sessions keyed per user+date+slot with shop on each line, or nullable `shop_id` only for `fulfilment_type=SCHEDULE` with a CHECK). `CartShopPolicy` + fulfilment-aware location policy (Schedule resolves the area; the shop radius is ignored) | Eat Now one-shop conflict still raised; Schedule cart cannot mix date/slot/area; mixed shops allowed |
| 2b.5 | **Order groups + checkout contract.** `order_groups(id, group_code, customer_id, service_area_id, service_date, slot_id, address snapshot, razorpay_order_id UNIQUE, razorpay_payment_id, payment_status, captured_amount, refunded_amount, delivery_fee, packaging snapshot, earliest_locked_cutoff_at NULL, created_at)` unique `(service_area_id, service_date, group_code)`; `orders.group_id`, `orders.order_code` unique `(service_area_id, service_date, order_code)`, suffix A/B/C by shop order. Schedule checkout: re-price from the server (rate at checkout); if the price differs from the cart, return a typed `PRICE_CHANGED` with the new per-order and group totals and require reconfirmation; then create the group + one order per shop (per-line split, menu price, commission snapshots; order payout + commission amount) and the Razorpay order for the group total, idempotently. Response: `groupId`, group code, member order codes, Razorpay order id, amount | two shops → one group, `XXXX-A`/`XXXX-B`; retry idempotent; price change forces reconfirm; Eat Now checkout response unchanged |
| 2b.6 | **Group payment core.** Extract one shared core (signature check, payment-status CAS, Razorpay calls). Verify, webhook, reconciliation, cancel-before-capture and stale-checkout handling first resolve the **payment owner** (legacy order or order group), then run idempotently. Webhook audit rows record the group and member orders. Reconciliation queries pending groups by the group Razorpay id; legacy per-order path kept. On capture: each member order reserves its dishes (2b.7); successful members → `SCHEDULED` with their locked cutoff; failed members create a partial-refund obligation (2b.8); group `earliest_locked_cutoff_at` set; **no live stock ledger write and no `OrderPlacedEvent` on any confirm route** | webhook-first, verify-first, duplicate, reconciliation, partial failure, all-failed; legacy suite still green |
| 2b.7 | **Reservations.** `schedule_reservations(order_id PK, slot_day_id, status, reserved_at, voided_at, void_reason)` + lines; slot capacity reserved **once per group**, dish stock per member order, conditional UPDATEs, compensation only of own writes. `ScheduleReservationService.reserveAtConfirm`, `voidReservation(orderId, reason)` (frees capacity when the last group member is voided). Restaurant edits to stock / order-until / split price via `PUT /api/shops/{shopId}/schedule-menu/{serviceDate}/items/{itemId}` audited in shop `audit_events` with before/after | final-unit and final-capacity races; duplicate confirm; edit never moves an existing order's locked cutoff |
| 2b.8 | **Refunds and cancellation.** `group_refunds(id, group_id, order_id NULL, component, amount, reason, status, gateway_idempotency_key)`; every refund takes a lock on the group row and checks `refunded_amount + amount ≤ captured_amount`; delivery fee refunded once, only when the last member order is cancelled. Customer cancel = whole group before `earliest_locked_cutoff_at` (`POST /api/schedule/groups/{groupId}/cancel`): void all reservations, one refund. Restaurant decline / ops cancel stays per order → partial refund. Immediate refund attempt after commit; hourly retry kept; re-verify jobs against a ~24 h `SCHEDULED` lifetime | concurrent decline + cancel cannot over-refund; fee refunded once; cancel after cutoff rejected |
| 2b.9 | **Release job.** `ScheduleReleaseJob` + `releaseForFulfilment` CAS `SCHEDULED → PLACED` where `release_at ≤ now`; keeps the reservation; restart catch-up; publishes ticket-level events only (2d.1). Off until 2d | two instances, repeat run, restart, voided order ignored |

Parallel: 2b.1 and 2b.2 first; 2b.3 → 2b.4 → 2b.5 → 2b.6 → 2b.7 → 2b.8 serial; 2b.9 after 2b.1. Rollback: Schedule checkout off; an operator script voids and refunds every `SCHEDULED` group before access is removed; populated tables are never dropped. **Exit:** races, cutoff, duplicate payment, partial failure, over-refund, cancel, and idempotent release tests pass; legacy payment tests green.

## Phase 2c — Settlement inputs

| # | Task | Tests |
|---|---|---|
| 2c.1 | `SettleableOrderPredicate` (DELIVERED, not refunded/refund-pending), shared by the export and Numbers | status × refund matrix |
| 2c.2 | Export-grade fields: group captured/refunded, group delivery and packaging (Ninjasu revenue, never a restaurant's), per-order split, commission, payout; documented allocation rules | one group with a partial refund reconciles to Razorpay |
| 2c.3 | Reject Schedule for `ROUTE_SPLIT` shops | rejection test |

**Exit:** a two-restaurant group with one partial refund reconciles: Razorpay captured − refunds = payouts + commission + group charges.

## Phase 2d — Tickets, notifications, ops API, frozen contracts

| # | Task | Tests |
|---|---|---|
| 2d.1 | `schedule_ticket_publications(shop_id, service_date, slot_id, version, payload_json incl. order codes + group codes + pickup-by, published_at)` + `schedule_ticket_amendments` (append-only); one `ScheduleTicketReleased` event per shop/date/slot; late orders append additions; ticket status derived from member orders; per-order shop alarms and cancel pushes suppressed for Schedule | 14 orders → one event, zero early alarms; late order → amendment |
| 2d.2 | Customer notifications **per group**: paid, reminder before cutoff, being prepared, picked up, delivered, refunded (full/partial with reason); member-order events aggregated, idempotent | two-restaurant group gets one push per stage |
| 2d.3 | Live counts endpoint for restaurants from an **in-process cache** (refresh ≤ 30 s; updated on reserve/void); no Postgres query per poll | load test: polls never hit the DB |
| 2d.4 | Staff per ADR (0.5), `AreaAccessService`, `/api/ops/**` matcher; handlers load the resource and read its area; ADMIN bypass audited | cross-area denial; forged area id ignored |
| 2d.5 | Ops address correction for a group, before batching only (rejected once batched unless the group is removed first), audited | guard + audit tests |
| 2d.6 | Freeze contracts: board, tickets (accept/ready/handover fan-out through the existing transition validator; "can't make" as a pending request (a `ticket_issue` row: ticket, orders, dish, qty, status PENDING/APPROVED/REJECTED, decided_by) that only ops approval turns into per-order cancellation + partial refund + ticket amendment (plan item 41)), ops cancel, labels data (`4821-A · Asha · 3 items`) | contract + authorization + audit tests |

**Exit (Phase 2):** contracts versioned, authorized, audited; fixtures published for web, customer and rider apps.

## Phase 3 — Ops board [B+W]

| # | Task |
|---|---|
| 3.1 | [W] Admin screens: service areas (window, last call, pickup lead, slots, fees, packaging, advance days), shop assignment, commission rates with consent reference and the notice check, audit view, Orders filters (mode, slot); a list showing each dish's split price next to its dine-in price for the team's review |
| 3.2 | [B] Batches by **group**: `schedule_batches`, `schedule_batch_groups(group_id UNIQUE)`, append-only `batch_events` (per-shop pickup/handover, group drop), `drop_points`; endpoints add/remove **groups** only, assign rider |
| 3.3 | [B] `deliveries.batch_id` + `BatchDeliveryService.assignBatch` (one delivery per member order, all on the batch; atomic) moved here from Phase 6 so the board can assign riders end to end |
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
| 5.1 | Daily lunch list: stock + order-until per dish, "set time for all dishes", restock, reopen, "same as yesterday", split price with menu-price preview matching the backend |
| 5.2 | Upcoming Scheduled view with live counts per slot and dish (2d.3) |
| 5.3 | Ticket view: one accept / ready / handover, pickup-by time, order codes, "can't make" request (pending until ops approves), amendments |

**Exit:** a restaurant publishes its list, watches demand, preps from one ticket.

## Phase 6 — Rider [B+R]

| # | Task |
|---|---|
| 6.1 | [B] Prepaid: `codAmount = 0` for online-paid orders; completion skips cash when expected is zero; proof/OTP kept |
| 6.2 | [B] Rider batch APIs: `GET /api/rider/batches/active`, pickup per shop, **group drop completion** that completes every member delivery together; a member order is never assigned or completed alone |
| 6.3 | [R] Batch card: ordered pickups, grouped drops with labels, notes, proof per D5, prepaid display |

**Exit:** a rider completes a multi-shop, multi-drop batch with no cash step.

## Phase 7 — HSR pilot [Biz + all]
One Schedule-only area, few restaurants, two lunch riders, one office cluster, behind flags. Daily ops on the board; weekly reconciliation (Razorpay vs charges vs payouts vs export); kill criterion revisited before start and tracked weekly; every manual workaround logged. Rollback: `schedule_enabled=false`, finish or refund open groups, keep evidence.

## Phase 8 — Numbers and iteration
Numbers from immutable orders, groups, charges, reservations, batches; then `settled_at` + `settlement_ref`, customer-chosen drop points and auto-grouping, tomorrow switch-on, Eat Now in HSR, in-app commission acceptance, Razorpay Route platform share, paid add-ons on Schedule dishes. Each behind its own flag and ADR.

## 3. Open items (do not block Phase 2a)
- Paid add-ons on Schedule dishes in v1: proposed **no** (2b.2), awaiting Samivan.
- Staff ADR (0.5): blocks 2a.5 and 2d.4 only.
- CA questions (deferred): marketplace/ECO model, GST on commission/fees, menu price built as split + commission, FSSAI position.
- D5 handover proof, D7 accept check (later phases).
