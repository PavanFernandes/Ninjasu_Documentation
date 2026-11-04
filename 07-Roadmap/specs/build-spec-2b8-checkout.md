# Build spec: Schedule checkout (2b.8)

Working spec for an implementer (Codex). Design is FINAL in [schedule-2b8-2b10-plan.md](../schedule-2b8-2b10-plan.md); this file says exactly what to build. Repo: `ninja delivery service java` (Spring Boot 4, Java 21, PostgreSQL). You cannot run Maven or a database: read the code carefully instead.

## Read first
- `Ninjasu_Documentation/07-Roadmap/schedule-2b8-2b10-plan.md` (locked P-1 to P-9; P-7 line tax, P-8 area flag).
- `schedule-implementation-order.md` row 2b.8 (a long line), `schedule-2b4-order-group-plan.md` (group and order columns, invariants, L-1 to L-12, L-18), `schedule-2b6-holds-plan.md` (checkout transaction, H-1 to H-20, typed 409 per line SOLD_OUT versus HELD), `schedule-2b5-cart-plan.md`.

## Reuse (do not copy)
- `service/ScheduleReservationService`: `acquire(HoldRequest)` MUST run inside your transaction; `holdDeadlineMs()`. `ScheduleHoldRejectedException`, `Rejection`.
- `service/schedule/FeeResolver`, `service/tax/BillTotalsCalculator.forScheduleLines`, `service/schedule/CommissionSlabCalculator`, the order commission snapshot code used by `service/impl/OrderAssembler`.
- `service/impl/OrderAssembler`: read how `assemble()` builds lines, snapshots and the seller snapshot for Eat Now. `assemble()` REFUSES Schedule carts: do not change that. You may add a NEW public method or extract small helpers without changing Eat Now behaviour.
- `service/refund/group/LineTaxApportioner` (freeze `order_lines.tax_amount`), `service/schedule/checkout/GroupKeys` (memberKey, suffix, orderCode, requestHash), `service/schedule/payment/GroupPaymentGateway` (createOrder, keyId).
- `service/CartSessionService` (Schedule cart, markLocked), `OrderGroupRepository` (you may add lookup methods: by customer id plus checkout idempotency key; an open CREATED group for customer plus service date; group code uniqueness per area plus date), entities `OrderGroup`, `Order`, `OrderLine`, `OrderStatus`, `SettlementStrategyResolver` (reject ROUTE_SPLIT shops).

## Contract already written (do not change signatures)
`dto/schedule/checkout/ScheduleCheckoutRequest`, `ScheduleCheckoutResponse`, `service/schedule/checkout/ScheduleCheckoutService`, `ScheduleCheckoutError`, `ScheduleCheckoutException`.

## Build
1. `service/schedule/checkout/ScheduleCheckoutServiceImpl` plus helpers (each under 250 lines; pure rules in their own classes): `checkout(userId, request, idempotencyKey)`.
   - **Area gate.** The cart service area must have `schedule_enabled`, else `ScheduleCheckoutException` AREA_CLOSED. Every shop must be SINGLE_MERCHANT, else ROUTE_SPLIT_SHOP.
   - **Idempotency.** A group already stored for (customer, key): same request hash returns the stored result (same group, same holdExpiresAt; if razorpay_order_id is still null, create the gateway order now and store it). A different hash is a BusinessRuleViolationException. Another unresolved CREATED group for the customer on the same date with a different key is UNRESOLVED_GROUP.
   - **Transaction 1.** Lock the cart session row. Take only the ticked lines (empty is CART_EMPTY). Re-price server side from current Schedule online prices; never trust client prices. Per member order compute lines and commission snapshots (commission channel SCHEDULE, 2b.4 L-8). Delivery and packaging fees come from FeeResolver at GROUP level, not per restaurant. Tax comes from `BillTotalsCalculator.forScheduleLines`.
   - **Rounding.** Member orders carry round_off 0. The whole-rupee round-off is ONE signed line on the GROUP: `group.payable_total = RoundingPolicy.wholeRupee(sum of member grand totals + delivery + packaging)`, `group.round_off` is the difference. Check how `forScheduleLines` rounds today (it passes roundToWholeRupee true) and add an UNROUNDED variant if needed without changing Eat Now.
   - If the server payable total differs from `request.expectedPayableTotal`, throw PRICE_CHANGED with the new per-order totals and the group total in details, writing nothing.
   - Create the group: CREATED, unique group_code of 4 to 6 digits per area plus date with bounded retry, checkout_idempotency_key, checkout_request_hash from `GroupKeys.requestHash`, address snapshot, fees, payable_total, round_off, `hold_expires_at = ScheduleReservationService.holdDeadlineMs()`.
   - Create one Order per shop in stable order (shop id ascending): group_id, group_suffix via `GroupKeys.suffix`, idempotency_key = `GroupKeys.memberKey(groupKey, shopId)`, the pre-payment Schedule status from `OrderStatus` (read the enum and the 2b.4 plan; members become SCHEDULED at payment), delivery_* copied, lines with frozen tax: `LineTaxApportioner.split(order.taxTotal, taxable value per line)` written to `order_lines.tax_amount`, asserting the shares sum to the order tax_total; seller snapshot as Eat Now does.
   - `ScheduleReservationService.acquire(HoldRequest)` in the same transaction. `ScheduleHoldRejectedException` becomes `ScheduleCheckoutException` LINE_UNAVAILABLE with per-line reasons in details (SOLD_OUT versus HELD versus the existing rejection reasons); the whole transaction rolls back.
   - Lock the cart (`markLocked`) and commit.
   - OUTSIDE any DB transaction: `GroupPaymentGateway.createOrder(amountPaise, currency, receipt = group code or id)`. Transaction 2 stores razorpay_order_id on the group only if still null. On gateway failure compensate: `ScheduleReservationService.voidGroup(groupId, reason)`, group markFailed, cart back to ACTIVE, and rethrow a clean error.
   - Build the response from stored values (holdExpiresAtMs from the group, serverNowMs from the same database clock source the hold used, amount in paise).
2. `controller/ScheduleCheckoutController`: `POST /api/schedule/checkout` with required header `Idempotency-Key`, `@Valid` body, user id from the authenticated principal exactly as `PaymentController` does, returns `ApiResponse<ScheduleCheckoutResponse>`. Follow how `/api/payments/checkout` is secured in `config/SecurityConfig`.
3. A handler for `ScheduleCheckoutException` in `exception/GlobalExceptionHandler`: HTTP 409 (400 for CART_EMPTY), ApiResponse status ERROR, message, data = `{error: <enum name>, details...}`.
4. Unit tests (JUnit 5 plus Mockito, no database) beside each class: PRICE_CHANGED writes nothing; idempotent replay returns the same group; gateway failure compensates; LINE_UNAVAILABLE maps reasons; area flag off; ROUTE_SPLIT shop refused; only ticked lines ordered; tax shares sum to tax_total; round-off on the group only; member keys deterministic; two shops get suffixes A and B.

## Rules
Files under 250 lines, methods under 60 lines, comments state a rule in one sentence (no history), no entity returned from a controller, no change to Eat Now behaviour. You MAY add small additive methods to `OrderGroupRepository`, `BillTotalsCalculator`, `OrderAssembler` (helpers only) and `exception/GlobalExceptionHandler`. Do NOT edit `DeliveryServiceImpl`, `DeliveryOrderSyncListener`, `OrderServiceImpl`, `OrderRepository`, `PaymentServiceImpl`, any refund code, or the group payment files (`service/schedule/payment/*`, `SchedulePaymentController`).

## Reply with
Every file created or edited, every assumption (especially the member pre-payment status, release_at, rounding), and what you could not verify. Do not claim anything compiles or passes.
