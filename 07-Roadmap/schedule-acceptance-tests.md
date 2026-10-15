---
id: ""
title: "Schedule — Acceptance test cases"
summary: "Test-case spec for the Schedule module: every decision and review finding turned into a checkable case, grouped by implementation slice, with level and traceability. Write the executable tests for a slice first, before its code."
type: how-to
status: ready
apps: [backend, web, customer, rider]
module: "schedule"
anchors: []
verified_against: "schedule-plan.md items #1-#41, design review P1-P17 (2026-10-15)"
updated: 2026-10-15
review: schedule-design-review.md
---

# Schedule — Acceptance test cases

Companion to [schedule-implementation-order.md](schedule-implementation-order.md) (tasks) and [schedule-plan.md](schedule-plan.md) (decisions, `#n`).
**Level:** U = unit, I = integration (Spring + a real scratch Postgres), C = API contract, E = end-to-end on a device or browser, M = manual/device checklist.

## Rules for every slice
1. **Tests first.** At the start of a slice, turn its cases below into failing tests, then write the code. Cases marked **(invariant)** must stay in the suite forever.
2. **Characterize before refactoring.** Before changing the payment core (Phase 0.2 / 2b.9), pin today's Eat Now behaviour with tests (T0-xx). They must pass before and after.
3. **Fixed clock.** Every time-dependent test injects a `Clock`; nothing reads `now()` directly. Use areas in `Asia/Kolkata` while the server runs in UTC.
4. **Real database for concurrency.** Race tests run against a scratch Postgres (Neon branch or local), never production; never run `contextLoads` against production.
5. **Legacy untouched.** Every slice ends with the Eat Now suites green and a shop with no service area behaving exactly as before.
6. Each test names its case id (`T2b-12`) so the tracker and this file stay in sync. Mark done in the Status column.

## Phase 0 — Characterization of today's payment and delivery
| ID | Case | Lvl | Traces |
|---|---|---|---|
| T0-01 | Eat Now COD order: totals, status, events, delivery fee unchanged | I | legacy |
| T0-02 | Online checkout then verify: confirmed once; a second verify does not decrement stock again | I | legacy |
| T0-03 | Webhook arrives before verify: same final state as verify-first | I | legacy |
| T0-04 | Verify arrives before webhook: webhook is a no-op | I | legacy |
| T0-05 | Confirm with live-stock failure: order CANCELLED + REFUND_PENDING and a refund is **attempted immediately** (new behaviour) | I | C13, 0.2 |
| T0-06 | Refund retry job: picks REFUND_PENDING; the idempotency key prevents a double refund | I | legacy |
| T0-07 | Cancel / decline of a paid order refunds the full total once | I | legacy |
| T0-08 | Reconciliation: PENDING_PAYMENT with a captured gateway payment becomes confirmed | I | legacy |
| T0-09 | Delivery assignment snapshots COD amount for a COD order and zero is not yet supported (pin current behaviour; changes deliberately in 2d.7) | I | legacy, 2d.7 |

## Phase 2a — Areas, dates, slots, rates
| ID | Case | Lvl | Traces |
|---|---|---|---|
| T2a-01 | **(invariant)** Service date uses the area timezone: server 18:40 UTC = 00:10 IST next day gives the next service date | U | #10, P9 |
| T2a-02 | `advance_days=0` rejects tomorrow; `=1` accepts tomorrow and rejects the day after | U | #10 |
| T2a-03 | Window: 07:59 not orderable, 08:00 orderable | U | #2 |
| T2a-04 | Last call: slot 12:30, last call 30 min: 12:00 boundary behaviour defined and tested both sides | U | #2 |
| T2a-05 | `paused_on` equals the service date: not orderable; the next day orderable with no reset job | U | P1 |
| T2a-06 | Validator rejects: no mode on, duplicate slot start, window after first last call, capacity < 1, delivery fee > 10, `advance_days` 2 | U | P10 |
| T2a-07 | **(invariant)** A shop with `service_area_id` NULL: discovery and checkout unchanged | I | P1 |
| T2a-08 | ADMIN sets a shop's area; a SHOP-role user gets 403; the owner edit DTO cannot carry the field | I | #17 |
| T2a-09 | Overlapping areas resolve to the nearest centre deterministically | I | P1 |
| T2a-10 | Commission resolver: shop rate beats area rate; latest `effective_from` at or before the instant wins; a future row is not applied early | U | #22 |
| T2a-11 | A rate row with `effective_from` earlier than now + notice days is rejected; exactly at the notice boundary is accepted | I | #22 |
| T2a-12 | A rate change never alters the rate stored on an existing order | I | #33 |
| T2a-13 | A tomorrow order placed today uses today's rate | U | #33 |
| T2a-14 | Every admin mutation writes a `platform_audit_events` row; an unaudited mutator fails the build | I | D8 |
| T2a-15 | Boot guard: missing table or column fails startup with a message naming it | I | rules |

## Phase 2b — Orders, groups, payment, reservations
| ID | Case | Lvl | Traces |
|---|---|---|---|
| T2b-01 | **(invariant)** Every `OrderStatus` value belongs to exactly one of LIVE / SCHEDULED_ONLY / GHOST / TERMINAL | U | P4, C1 |
| T2b-02 | A SCHEDULED order is absent from shop board, shop detail, `getActiveOrder`, KDS, dispatch, shop push; present in the customer's upcoming list | I | P4 |
| T2b-03 | `assignDelivery` rejects a SCHEDULED order | I | C1 |
| T2b-04 | Availability fails independently for each of: inactive item, no row for the date, stock exhausted, past order-until, past slot last call, shop not assigned, area paused, outside window/advance days, invalid slot | I | #15 |
| T2b-05 | Restock reopens a sold-out dish; extending order-until reopens it; lowering stock below reserved is rejected | I | #15 |
| T2b-06 | **(invariant)** An edit to stock or order-until never changes an existing order's locked cutoff | I | #18 |
| T2b-07 | Two customers pay for the last unit at once: exactly one succeeds, the other is refunded | I | P3 |
| T2b-08 | Two groups pay for the last slot capacity at once: exactly one succeeds | I | P3, #32 |
| T2b-09 | Pricing: split 140 at 10% gives 154; split 143 gives 157 (14.3 rounds to 14); split 145 gives 160 (14.5 rounds half up to 15); delivery flat ignores shop `DeliveryConfig`; packaging added; Eat Now unchanged | U | #21, #27 |
| T2b-10 | Cart: Eat Now second shop still rejected; Schedule cart accepts two shops; mixing date, slot or area is rejected; COD `placeOrder` rejects Schedule | I | #13, P8 |
| T2b-11 | Checkout re-prices from the server; if split or rate changed since the cart, `PRICE_CHANGED` is returned with new totals and the payment is not created until the customer reconfirms; the order snapshots the confirmed price | I | C18 |
| T2b-12 | Two-restaurant checkout creates one group and two orders coded `XXXX-A`, `XXXX-B`; codes unique per area and date; a retried checkout creates no second group | I | #30, #31 |
| T2b-13 | **(invariant)** Group payment: verify-first, webhook-first, duplicate and concurrent confirms produce one confirmation; each member reserved once; **no live stock ledger write and no `OrderPlacedEvent`** | I | P14, C15 |
| T2b-14 | Capture after cutoff: full refund. One dish sold out between checkout and payment: partial refund, the rest proceeds. Every dish fails: full refund including the delivery fee | I | #34 |
| T2b-15 | Reconciliation: a pending group with a captured payment is confirmed; with a failed payment is cancelled | I | C15 |
| T2b-16 | Customer cancels the group before the earliest locked cutoff: one full refund, reservations voided, capacity and stock restored; after the cutoff the cancel is rejected | I | #35, D2 |
| T2b-17 | **(invariant)** A restaurant decline and an ops cancel at the same time never refund more than captured; the delivery fee is refunded once | I | P14 |
| T2b-18 | Release job: orders with `release_at` at or before now become PLACED once; two job instances race safely; catches up after a restart; a voided order is ignored; the reservation is kept | I | 2b.11, C2 |
| T2b-19 | The hourly reconciliation and refund jobs do not touch a paid SCHEDULED order that is hours from its release | I | C13 |
| T2b-20 | `voidReservation` is idempotent: called twice, capacity and stock return once | I | C2 |
| T2b-21 | **(invariant)** Checkout retry with the same group key recomputes the same member keys and creates no second group or order; `orders.idempotency_key` uniqueness holds across members | I | 2b.4 |
| T2b-22 | Capture amount, currency, status or gateway order id differs from the group: no member is confirmed, the actual payment id and amount are stored first, an alert is raised, the whole capture is refunded | I | 2b.9 |
| T2b-23 | **(invariant)** Razorpay accepts a group refund but the local save fails: the next worker finds the receipt at the gateway and does not refund again; two workers claim one `group_refunds` row: one gateway call | I | 2b.7 |
| T2b-24 | A member order cannot be cancelled, declined or advanced through a legacy endpoint; legacy order history excludes members | I | 2b.4 |
| T2b-25 | Confirming a Schedule group completes only the Schedule cart; an active Eat Now cart is untouched | I | 2b.5 |
| T2b-26 | Partial line refund: order grand total, payout and commission are recomputed from the remaining lines; `refunded_amount` and `refund_state` update with the refund row; the delivery fee is refunded only with the last member | I | 2b.7 |
| T2b-27 | A group refund resolves through `refund.processed` by gateway refund id; a legacy order refund still resolves by payment id | I | 2b.7 |

## Phase 2c — Settlement inputs
| ID | Case | Lvl | Traces |
|---|---|---|---|
| T2c-01 | **(invariant)** Settleable predicate: DELIVERED yes; refunded, refund-pending, cancelled, declined no | I | #24 |
| T2c-02 | A two-restaurant group with one partial refund reconciles: captured minus refunds equals payouts plus commission plus group charges | I | 2c exit |
| T2c-03 | A Schedule checkout containing a `ROUTE_SPLIT` shop is rejected (enforced in 2b.8) | I | C10, 2b.8 |
| T2c-04 | Rounding: GST lines exact, one round-off line brings the bill to a whole rupee, commission rounds to the nearest rupee | U | #27 |

## Phase 2d — Tickets, notifications, ops
| ID | Case | Lvl | Traces |
|---|---|---|---|
| T2d-01 | 14 orders at the cutoff produce one `ScheduleTicketReleased` event and no alarm before it; the payload has dish totals, order codes and ready-by time | I | #19 |
| T2d-02 | A late order after release appends an amendment; the first publication is never changed (update and delete are blocked) | I | #19 |
| T2d-03 | Accept and Ready fan out through the existing transition validator; ticket status is derived from the orders | I | #19 |
| T2d-04 | "Can't make": creates a pending request and refunds nothing; ops approval with chosen orders cancels those lines, partially refunds and amends the ticket; rejection changes nothing | I | #41 |
| T2d-05 | A two-restaurant group gets one push per stage (paid, preparing, picked up, delivered, refunded); a retry does not duplicate | I | #39 |
| T2d-06 | Live counts are served from the cache: polling does not query the database; a reservation shows within 30 seconds | I | P16 |
| T2d-07 | **(invariant)** An ops user for area A cannot act on area B's order; a forged area id is ignored; ADMIN bypass is audited | I | P2 |
| T2d-08 | Address correction is allowed before batching and rejected after unless the group is removed from the batch; both audited | I | #38 |
| T2d-09 | Frozen contracts: fixtures validate against the responses | C | 2d.6 |
| T2d-10 | A prepaid delivery has `codAmount` 0 in the delivery and in the dispatch notification; a COD delivery is unchanged | I | 2d.7 |

## Phase 3 — Ops board
| ID | Case | Lvl | Traces |
|---|---|---|---|
| T3-01 | **(invariant)** A group is in exactly one batch; adding or removing a single member order is rejected | I | #40 |
| T3-02 | Moving a group between batches records an event; batch events are append-only | I | P6 |
| T3-03 | Assigning a rider creates one delivery per member order, atomically; a partial failure rolls back; no member delivery carries a cash amount | I | 3.3, 2d.7 |
| T3-04 | A late order after the first batch appears in the problem queue as unbatched | E | #37 |
| T3-05 | Settlement export (golden file): per-restaurant rows plus a group section with codes, charges and refunds | I | 3.5 |
| T3-06 | Admin forms show each dish's split price next to its dine-in price | E | #20 |

## Phase 4 — Customer app
| ID | Case | Lvl | Traces |
|---|---|---|---|
| T4-01 | HSR (Schedule-only) shows no mode toggle; the town shows Eat Now only | E | #1 |
| T4-02 | Slot first, then restaurants: a restaurant past its cutoff for that slot is greyed with the reason, not hidden | E | #3 |
| T4-03 | A dish reappears after a restock on the next refresh; a sold-out dish is greyed | E | #15 |
| T4-04 | Two-restaurant cart, one payment, itemized lines; `PRICE_CHANGED` shows a confirmation dialog | E | #30 |
| T4-05 | Cutoff passes while the payment sheet is open: the customer is told and refunded | E | #34 |
| T4-06 | Upcoming card shows both order codes; whole-group cancel works before the cutoff and is hidden after | E | #35 |
| T4-07 | A scheduled order never replaces the active Eat Now order | E | P4 |

## Phase 5 — Restaurant side
| ID | Case | Lvl | Traces |
|---|---|---|---|
| T5-01 | Lunch list: stock and order-until editable any time; "same as yesterday"; the menu-price preview comes from the backend preview endpoint | E | #15 |
| T5-02 | Live counts update without an alarm; no sound before release | E | #19 |
| T5-03 | One accept, one ready; order codes and ready-by time visible; late additions shown | E | #19 |
| T5-04 | "Can't make" shows as pending until ops decides | E | #41 |

## Phase 6 — Rider
| ID | Case | Lvl | Traces |
|---|---|---|---|
| T6-01 | Rider app: completion skips the cash step when expected cash is zero; a COD delivery still collects cash (backend side is T2d-10) | E | C9, 6.1 |
| T6-02 | Group drop completion completes every member delivery; one member order can never be completed alone | I | #40 |
| T6-03 | Pickup per restaurant writes a batch event with the order count | I | P6 |
| T6-04 | Rider batch card: pickup order, grouped drops, labels, notes (device run) | M | D5 |

## Phase 7 — Pilot checks (manual, weekly)
| ID | Case | Lvl | Traces |
|---|---|---|---|
| T7-01 | Razorpay captured minus refunds equals restaurant payouts plus commission plus Ninjasu charges, for every group of the week | M | #24 |
| T7-02 | Refund-fee loss on cancelled orders is recorded in the numbers | M | #29 |
| T7-03 | Every manual workaround logged with order or batch ids | M | §7 |
