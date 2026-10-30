# Build spec: group payment (2b.9)

Working spec for an implementer (Codex). Design is FINAL in [schedule-2b8-2b10-plan.md](../schedule-2b8-2b10-plan.md) (locked P-1 to P-9; Q1: side by side, do NOT refactor `PaymentServiceImpl`). Repo: `ninja delivery service java` (Spring Boot 4, Java 21, PostgreSQL). You cannot run Maven or a database: read the code carefully instead.

## Read first
- `schedule-2b8-2b10-plan.md`; `schedule-implementation-order.md` row 2b.9 (long line; the 2026-10-28 override in `schedule-2b6-holds-plan.md` wins: a late capture on a lapsed hold is ALL OR NOTHING, a full refund); `schedule-2b6-holds-plan.md` (H-3, H-4, H-5, H-14, H-15, the late-capture path); `schedule-2b4-order-group-plan.md` (L-9, L-13, invariants 10 to 12).

## Reuse
- `service/ScheduleReservationService.confirm(groupId)` (ConfirmOutcome CONFIRMED, VOIDED, NOT_OPEN). Read `ScheduleReservationSettler`: confirm already marks the group PAID or FAILED itself via `markPaid` and `markFailed`. Work out what that means for the capture writers and adapt carefully so the group ends with razorpay_payment_id and captured_amount written exactly once.
- `OrderGroupRepository`: `findByIdForUpdate`, `findByRazorpayOrderId`, `markPaidWithCapture`, `markCancelled`, `markCaptureMismatch`, `recordOrphanCapture`, `markFailed`. You may add queries (for example the stale group query).
- `OrderRepository.findByGroupIdForUpdateOrderById` (members locked by id AFTER the group row).
- `service/schedule/payment/GroupCaptureValidator`, `GroupPaymentGateway` (fetchPayment, paymentsForOrder, signatureValid), `service/schedule/cancel/CancelWindowResolver`.
- `service/refund/group/GroupRefundService.raise` (accepts PAID, FAILED, CANCELLED, CAPTURE_MISMATCH groups with a stored payment id and captured amount), `RaiseGroupRefundCommand`, `RefundEvent`, `RefundCustomerReason`, `RefundTechnicalCause`, `service/refund/RefundRows`, `RefundState`, `RefundApproval`, `PaymentRefundRepository`.
- `service/impl/PaymentServiceImpl`: read `processWebhook` (about line 426 to 473) and the legacy confirm, verify and reconcile for the PATTERN only.
- `service/schedule/ServiceDateResolver`, the ServiceArea cancel settings (`cancel_freeze_minutes`, `late_cancel_grace_minutes`) and slot facts for release_at.

## Contract already written (do not change signatures)
`service/schedule/payment/GroupPaymentService` (owns, verify, onCaptured, cancelCheckout, sweepStale), `dto/schedule/ScheduleGroupView`, `dto/schedule/VerifyGroupPaymentRequest`, `service/refund/group/ExtraCaptureRefundService`.

## Build
1. `service/schedule/payment/GroupPaymentServiceImpl` plus small helpers (each under 250 lines).
   - `owns(razorpayOrderId)`: a group has it.
   - `verify(userId, req)`: the group must belong to the user (else a not found style exception); the signature is checked against the group STORED razorpay_order_id, never the client copy; then confirm.
   - `onCaptured(razorpayOrderId, paymentId)`: the system path (webhook or sweep).
   - **Confirm (shared).** Fetch the payment from Razorpay OUTSIDE any DB transaction (`GroupPaymentGateway.fetchPayment`), run `GroupCaptureValidator` against `GroupExpectation(group razorpay order id, payable_total, currency)`. Then ONE transaction: lock the group, then members by id. Cases:
     - Group CREATED and check OK: write the capture and CREATED to PAID exactly once (`markPaidWithCapture`), call `ScheduleReservationService.confirm`. CONFIRMED: members move from the pre-payment status to SCHEDULED with release_at (if the plan is ambiguous, use the slot last-call instant for the group area, date and slot, and state the assumption), set cancel_until_at and late_cancel_from_at on the group with `CancelWindowResolver` (earliest member release_at, area cancel settings, slot start), complete the Schedule cart (`CartSessionService.markCompleted`); NO OrderPlacedEvent and NO live stock write.
     - VOIDED (lapsed hold re-check failed; the settler already failed the group): record the orphan capture and raise a FULL group refund (event VOID or PAYMENT_AFTER_FAILURE, customer reason ITEM_UNAVAILABLE, technical cause HOLD_LAPSED_SOLD_OUT or HOLD_LAPSED_SLOT_FULL from the RefundReason in ConfirmOutcome).
     - Group FAILED or CANCELLED when a valid capture arrives: `recordOrphanCapture` then a full refund (PAYMENT_AFTER_FAILURE, ORPHAN_CAPTURE).
     - Check not OK on a CREATED group: `markCaptureMismatch` (stores the actual payment id and amount durably), log an ERROR for alerting, full refund (CAPTURE_MISMATCH).
     - Group already PAID with the SAME payment id: idempotent no-op.
     - Group already holding a DIFFERENT payment id (second capture): call `ExtraCaptureRefundService.raise(groupId, paymentId, thatPaymentAmount)` and do not touch the group.
     - Full refund means `GroupRefundService.raise` with every member order (null amount means remaining) and includeFees true.
   - `cancelCheckout(userId, groupId)`: owner only; CREATED only; `ScheduleReservationService.voidGroup` then `markCancelled` in one transaction, cart back to ACTIVE. If the group is already PAID return the view unchanged (the customer must use the cancel flow).
   - `sweepStale()`: CREATED groups whose hold_expires_at plus a grace (a constant, 2 minutes) has passed: ask Razorpay (`paymentsForOrder`); a captured payment goes through the same confirm path; none means void the holds and `markFailed`.
2. `service/refund/group/ExtraCaptureRefundServiceImpl`: ONE PaymentRefund row per (group, payment id), idempotent via an obligation key from the payment id, subject = the group, razorpay_payment_id = that payment id, amount = that payment amount, event ORPHAN_CAPTURE, no allocation slices. Adjust `RefundState.capGroup` and the `PaymentRefundRepository.sumOpenAmountForGroup` query (add a payment-id parameter or a new query) so refunds of a DIFFERENT payment id are NOT counted against the group captured amount and an extra-capture refund is capped by its own amount. `RefundApproval` must approve such a refund (it has no slices). Keep every existing refund test green (read them first).
3. `service/schedule/payment/GroupPaymentSweepJob`: `@Scheduled` hourly calling `sweepStale`, following the pattern and flags of `service/impl/PaymentReconciliationJob`. `controller/SchedulePaymentController`: `POST /api/schedule/payments/verify` and `POST /api/schedule/payments/cancel` (body groupId), user from the principal like `PaymentController`, `ApiResponse<ScheduleGroupView>`.
4. WEBHOOK DISPATCH: a minimal edit to `service/impl/PaymentServiceImpl.processWebhook`, the ONLY change to that file. For payment.captured and order.paid, if `GroupPaymentService.owns(razorpayOrderId)` call `onCaptured(razorpayOrderId, razorpayPaymentId)` and return; otherwise unchanged. Add the dependency without creating a Spring cycle (for example ObjectProvider). Legacy behaviour must stay identical for Eat Now; existing `PaymentServiceImpl` tests must stay green (read them; update only constructor wiring if needed).
5. Tests (JUnit 5 plus Mockito, no database), one file per class: every confirm case above (OK, mismatch, after FAILED, after CANCELLED, lapsed hold, duplicate same id, second payment id), ownership not found for another customer, signature against the stored order id, lock order group then members, sweep outcomes, cancelCheckout rules, extra-capture cap and idempotency, webhook dispatch (group versus legacy order).

## Rules
Files under 250 lines, methods under 60 lines, comments state a rule in one sentence (no history), no entities from controllers. Do NOT edit `DeliveryServiceImpl`, `DeliveryOrderSyncListener`, `OrderServiceImpl`, `OrderRepository`, the checkout files (`service/schedule/checkout/*`, `ScheduleCheckoutController`).

## Reply with
Every file created or edited, every assumption (release_at, statuses, settler interplay), and what you could not verify. Do not claim anything compiles or passes.
