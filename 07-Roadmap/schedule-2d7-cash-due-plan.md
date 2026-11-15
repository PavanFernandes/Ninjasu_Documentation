# 2d.7 Cash due at the door (prepaid delivery fix)

Status: DECISIONS LOCKED 2026-11-04 · verdict APPROVED WITH CHANGES · reviewed by devil's advocate, geld, a blind Codex pass and a Raphael clarity pass · next: `/gcp`, then build 2d.7a.
This page is the CURRENT design. Everything that was proposed and then changed is in "Decision history" at the end; do not build from that part.

## The model in one sentence

The payment METHOD decides who collects the money (the gateway, or the rider at the door). The payment STATUS only tracks the gateway. **Cash due follows the method, never the status.**

Consequence you will be tempted to get wrong: a pending or failed online payment is NOT a cash order. It is a dead order. Cash is only ever owed when the customer explicitly chose cash and the checkout allowed it.

## Words used in this plan (each means one thing)

| Word | Means | Where it lives |
|---|---|---|
| Payment method | what the customer chose: `CASH_ON_DELIVERY` or `ONLINE` | `orders.payment_method`, never changes after placement |
| Payment status | gateway progress: `NONE`, `CREATED`, `PAID`, `FAILED`, `REFUND_PENDING`, `REFUNDED`. `NONE` means "no gateway payment is involved", NOT "unpaid" | `orders.payment_status` |
| Order total | what the order costs | `orders.grand_total`, written only when the order is created |
| Cash due | the cash the rider must take at the door right now. Derived, never stored. Always `0` or the order total | computed by `CashDue` |
| Cash expected / collected | what was due and what the rider recorded, frozen at completion. A history record | `delivery_cash_collections.amount_expected / amount_collected` |
| COD policy | which methods a checkout may use | `PaymentPolicy` (2d.7b) |

"Prepaid" is a conversation word only. No code, field or message uses it.

## Truth table (the one rule everything implements)

| method | status | new delivery allowed | cash due |
|---|---|---|---|
| COD | NONE | yes | order total |
| COD | anything else | refused, log ERROR (no code path produces it) | n/a |
| ONLINE | PAID | yes | 0 |
| ONLINE | CREATED, FAILED | refused (payment not confirmed) | n/a |
| ONLINE | REFUND_PENDING, REFUNDED | refused for a new delivery. A live delivery may still complete while REFUND_PENDING (cash 0); REFUNDED means the order is cancelled and completion is already refused | 0 |
| NULL (old rows, D5) | NONE or NULL | yes, treated as COD, log WARN | order total |
| NULL (old rows) | anything else | refused, like COD | n/a |

A NULL payment status (orders placed before the payments column existed; it has no database default) reads as `NONE`.

A refund state never authorizes cash. Whether a live delivery should stop when a refund starts is a product decision (revisit EVOL-3), not decided here.

## What is wrong today (facts)

The amount the rider must collect is decided in five places that share no code, plus a stored copy nobody on the server trusts:

| # | Place | What it does | Source |
|---|---|---|---|
| 1 | Assign / accept | writes `deliveries.cod_amount = grandTotal` for every order | `DeliveryServiceImpl.java:289,300` |
| 2 | Reassign | builds the new row without `cod_amount` (NULL) | `DeliveryServiceImpl.java:723-733` |
| 3 | Dispatch push | sends `grandTotal` as `codAmount` | `DeliveryDispatchListener.java:144` |
| 4 | Rider completion | `expected = order.getGrandTotal()`; `amountCollected` is `@NotNull`; short-pay needs a reason and writes a discrepancy | `DeliveryServiceImpl.java:528-545`, `CompleteDeliveryRequest.java:22` |
| 5 | Staff force-complete | same | `DeliveryServiceImpl.java:796-810`, `ForceCompleteRequest.java:18` |
| 6 | Rider app | shows `codAmount`, prefills from it, `?? 0` when null | `Ninjasu_Rider_App/app/(rider)/delivery/[id].tsx:141-192` |

The old 2d.7 row ("set `codAmount = 0` in places 1 and 3") would not have worked: completion (4, 5) would still expect the full total, so every prepaid delivery would be recorded as a short-pay discrepancy needing a reason.

Nothing is broken in production: online payment is off (`app.payments.online-enabled=false`) and Schedule orders are refused at dispatch (`ScheduleMember.refuseDispatch`, `DeliveryServiceImpl.java:274`). No prepaid deliveries exist, so no backfill.

## Locked decisions (Samivan, 2026-11-04)

| # | Decision |
|---|---|
| D1 | Derive cash due from the order; drop `deliveries.cod_amount`. |
| D2 | COD orders stay `payment_status = NONE`. `PAID` keeps meaning "the gateway captured money" because it drives gateway compare-and-swap updates and refunds (`OrderRepository:174`, `PaymentRefundServiceImpl:97`, `RefundApproval:67`); a cash-`PAID` COD order would be sent to the gateway for a refund of money it never held. Cash custody lives in `delivery_cash_collections`. Revisit when rider cash remittance to the shop is designed. |
| D3 | `PaymentPolicy` class, rule "Schedule is online-only", and a per-shop `shops.cod_enabled boolean NOT NULL DEFAULT true`. A shop can turn COD on or off and nothing else: there is NO shop-level online switch and no `online_enabled` column. Online payment can only be off platform-wide, through `app.payments.online-enabled`, which is the operator's safety switch (launch gate today, kill switch if Razorpay misbehaves), never a shop setting. |
| D4 | The rider app is not installed anywhere, so no compatibility shim: the API/push field `codAmount` is renamed `cashDue` in one change across backend and rider app. No `prepaid` field. The app labels by meaning ("No cash to collect" when `cashDue` is 0), never by cause. |
| D5 | NULL `payment_method` on a DELIVERY order is treated as COD with a WARN. Close it structurally after the count query returns 0. |

## Invariants (each is enforced by code or a test, not by this page)

| # | Invariant | Enforced by |
|---|---|---|
| INV-1 | An ONLINE order gets a delivery only when `payment_status = PAID` (assign, accept, reassign, batch). At completion only PAID and REFUND_PENDING pass. The ownership check runs before the payment check so a payment message never reveals another shop's order. | service guard + tests T6, T13 |
| INV-2 | One function, `CashDue`, decides cash due; the five places call it. | `CashDueTest` (table-driven over the truth table) |
| INV-3 | Cash due 0: no `delivery_cash_collections` row, no discrepancy. A valid positive `amountCollected` is IGNORED, logged WARN and noted on the DELIVERED event, never rejected (ADR-0014: a rider is never stranded at the door). A malformed amount (negative, more than 2 decimals, above the maximum) is refused for every order, before the OTP is touched, because it is a client bug and failing loudly is safer than guessing. OTP and geofence stay. | completion service + T4, T5, T12 |
| INV-4 | Schedule orders are ONLINE only. | `PaymentPolicy` + `ScheduleCheckoutWriter:181` + T10 |
| INV-5 | Cash due never changes after the order is placed (method is immutable, COD status stays NONE, `grand_total` is written only at creation). This is the ONLY reason deriving is safe. The day a feature edits an order total after placement (item removed, ticket amendment on a COD order) it must snapshot cash due, and D1 is reopened. | source-scanning test: fails if `setGrandTotal` appears outside the creation sites `OrderAssembler:169`, `ScheduleCheckoutWriter:125`, `PosOrderServiceImpl:134,187` (TEST-INV-01) |
| INV-6 | The policy never crashes or creates a silent cash order when no method is allowed. Online is always on for a shop when the platform has it on, so the only empty state is "platform online off AND shop `cod_enabled = false`". BUILT NOW: in that state the policy answers a clear "not taking orders right now" and creates nothing; the policy never overrides the shop's choice. DEFERRED (Samivan, 2026-11-04, see EVOL-5): rejecting the save of `cod_enabled = false` while the platform has online off. | policy + T17 (T14 deferred) |
| INV-7 | `amountCollected` is `>= 0` and a valid amount (reuse `MoneyRules.isAmount`, `service/schedule/MoneyRules.java`: 2 decimals, max 1,000,000). | bean validation on both DTOs + T11 |

The 2-decimal rule is repo-wide today (`MoneyRules`, `PriceQuoteCalculator`); non-2-decimal currencies belong to the global-readiness review, not to this change.

## Design: what changes

| Area | Before | After |
|---|---|---|
| `deliveries.cod_amount` | stored copy, written at assign, missing at reassign | not written, not read; column dropped in 2d.7d |
| Rider/staff completion | expected = order total always; cash step always | expected = `CashDue`; cash step skipped when 0 |
| `DeliveryDto` | `codAmount` | `cashDue` (null only for a standalone delivery) |
| Dispatch push | `codAmount` = total | `cashDue` from `CashDue` |
| "May this checkout pay cash" | hard-coded COD in `OrderServiceImpl:105`, hard-coded ONLINE in the Schedule writer | `PaymentPolicy`, checked in `placeOrder` and again at submit; same answer returned to the app so it hides disallowed methods |

Policy inputs: order type (Schedule never cash), the platform online flag (decides whether ONLINE is offered at all), the shop's `cod_enabled` (decides whether COD is offered). The offered methods are the ones every input allows. A shop flag change applies to checkouts after the change; COD orders already placed are untouched.

## Phases

| # | Phase | Repo | Branch | Base | Notes |
|---|---|---|---|---|---|
| 2d.7a | `CashDue`, completion/DTO/push/force-complete use it, INV-1/3/5/7, tests | ninja delivery service java | - | feature/schedule | gates 3.3 |
| 2d.7b | `PaymentPolicy`, `shops.cod_enabled`, INV-4/6 | ninja delivery service java | - | feature/schedule | read `service/fulfilment/*Policy` first; extend it if it fits |
| 2d.7c | Rider app: `cashDue`, "No cash to collect", no cash step at 0 | Ninjasu_Rider_App | - | - | app is untracked in git: put it under git first; ships WITH 2d.7a |
| 2d.7d | Drop `deliveries.cod_amount`; D5 CHECK; optional D6 | ninja delivery service java | - | feature/schedule | hand-run SQL, after 2d.7a is deployed |

Done when: 2d.7a merged into `feature/schedule`, tests green, a read-only Codex diff review reconciled, the 2d.7 row in `schedule-implementation-order.md` and `payment.md` updated, a new ADR written ("cash due derives from method and status"; ADR-0014 stays immutable with a link forward).

```
-- DO NOT RUN NOW — sketch for review
-- 2d.7b: alter table shops add column cod_enabled boolean not null default true;
-- 2d.7d: alter table deliveries drop column cod_amount;
-- 2d.7d (after the D5 count is 0): alter table orders add constraint orders_delivery_needs_payment_method
--          check (order_type <> 'DELIVERY' OR payment_method is not null);
-- D5 count (read-only): select count(*) from orders where order_type = 'DELIVERY' and payment_method is null;
```

## Tests

| # | Case | Expect |
|---|---|---|
| T1 | COD delivery completed with full cash | `cashDue` = total, ledger expected = collected, no discrepancy |
| T2 | COD short-pay without reason / with reason | rejected / discrepancy row |
| T3 | ONLINE+PAID assign | `cashDue` 0 in DTO and push |
| T4 | ONLINE+PAID complete, no `amountCollected` | DELIVERED, no ledger row |
| T5 | ONLINE+PAID complete, old-style 0 | same as T4 |
| T6 | ONLINE with CREATED / FAILED / REFUND_PENDING: assign | refused |
| T7 | reassign a COD delivery | same amount shown (was NULL) |
| T8 | staff force-complete ONLINE+PAID | no ledger row, reason still required for the OTP bypass |
| T9 | NULL method | cash due = total, WARN logged |
| T10 | Schedule requests COD; COD flag off; shop `cod_enabled` false | rejected with a clear message |
| T11 | negative `amountCollected` (rider, staff); more than 2 decimals | 400, nothing written |
| T12 | ONLINE+PAID, rider sends a positive amount | completes, amount ignored, WARN logged |
| T13 | complete an ONLINE order that is CREATED/FAILED | refused |
| T14 | DEFERRED with EVOL-5: platform online off, save shop `cod_enabled = false` | write rejected with a clear message |
| T17 | shop already has `cod_enabled = false`, platform online then turned off | that shop answers "not taking orders right now"; a shop with COD on still offers COD; no order is created as cash |
| T15 | `setGrandTotal` appears outside the creation sites | source-scanning test fails |
| T16 | `CashDueTest` over every row of the truth table | matches |

## Revisit (not built, with trigger)

| id | What | Trigger |
|---|---|---|
| EVOL-1 | COD has no PAID-like state; "was this order settled" is read from the cash ledger | rider cash remittance, or a COD revenue report |
| EVOL-2 | over-collection on COD is not flagged | Samivan wants an over-collection rule |
| EVOL-3 | live delivery when a refund starts (`REFUND_PENDING`) | refund/cancel workflow review |
| EVOL-4 | split tender (online + cash on one order) | any wallet/coupon-as-cash/tip feature: needs an allocation ledger, `CashDue` is total-or-zero |
| EVOL-6 | KNOWN, PRE-EXISTING (code review + Codex, 2026-11-05): two simultaneous staff force-completions of the same delivery can both pass the status check (the delivery is read before the order lock, and there is no version column), so the second overwrites the cash row and emits a second completion. The rider path is protected because completion clears the order OTP under the lock. | any change to the delivery locking, or before staff force-complete is used at volume; fix = re-read the delivery status after the order lock |
| EVOL-5 | KNOWN GAP, accepted by Samivan 2026-11-04: nothing stops saving `cod_enabled = false` while the platform has online payment off, which leaves that shop unable to take orders. Unreachable today because 2d.7b adds only the column and the policy read, no toggle endpoint or screen, and a shop's flag can only change by SQL. The platform flag `app.payments.online-enabled` stays as it is. | the moment any endpoint, admin screen or web setting can change `cod_enabled`: add the save-time rejection (T14) in that same change; also before online payment is switched on or off in production |
| D6 | rename `PaymentStatus.NONE` to something that cannot be read as "unpaid" (e.g. `NOT_APPLICABLE`). Blast radius is small: one Java default (`Order.java:178`), two TypeScript unions (`Food-Ninja-Frontend/src/features/orders/types.ts:27`, `Ninjasu_Web/src/features/shop/services/order.service.ts:57`) and one data update. Recommended as its own PR after 2d.7a, not inside it, so the money fix stays reviewable. | Samivan to decide |

## Decision history (do not build from this section)

- Proposal "set `codAmount = 0` for online orders in assign + push" was rejected: completion would still expect the total (devil's advocate A).
- "Keep a stored snapshot with one writer" (D1b) lost: three writers (assign, reassign, batch assign 3.3), reassign already forgot it, and the server never read it.
- "Pending payment falls back to COD automatically" was rejected: it would turn a failed prepaid Schedule checkout into a cash order and break the ghost-status rule (payment.md condition 3).
- "Reject a positive amount on a prepaid order" was dropped in the Raphael pass: it strands a rider at the door, against ADR-0014.
- "Add a `prepaid` boolean and keep the `codAmount` key" was dropped by D4 (the rider app is not installed).
- "COD gets a PAID state when cash is handed over" lost (D2).
- Codex (blind, read-only) agreed on: derive, same five places, reassign NULL, ONLINE owes zero in every status, keep the ledger as audit, policy server-side and rechecked at submit, Schedule online-only, restrictions combined. Codex-only finding adopted: amount bounds (INV-7), and INV-1 at completion. Not adopted: reconciling old rows (nothing is rewritten, no prepaid deliveries exist). Its claim that cancel/decline revokes live delivery work was not checked by me.
- Lenses run: 0, 2, 3, 5, 7, 8. Skipped: 1, 4, 6 (no hot path, no as-of data, no heavy query). Reference designs skipped.
