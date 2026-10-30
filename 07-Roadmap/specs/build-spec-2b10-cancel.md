# Build spec: cancellation, decline and acceptance (2b.10)

Working spec for an implementer (Codex). Design is FINAL in [schedule-2b8-2b10-plan.md](../schedule-2b8-2b10-plan.md) (locked P-1 to P-9). Repo: `ninja delivery service java` (Spring Boot 4, Java 21, PostgreSQL). You cannot run Maven or a database: read the code carefully instead.

## Read first
- `schedule-2b8-2b10-plan.md` (INV-2, P-6, the late-cancel flag), `schedule-implementation-order.md` row 2b.10 (long line), `schedule-2b4-order-group-plan.md` (decisions 6, 9; invariants 10 to 12; L-12 to L-17), `schedule-2b6-holds-plan.md` (H-5, H-14: reservations settle with the group; group cancel releases holds in the same transition), `refund-approval-plan.md` (refund core), `02-Domain/restaurant-schedule-terms.md` (T1 to T5).

## Rules being built
- A customer may cancel the WHOLE group only before `order_groups.cancel_until_at` and only while EVERY member is SCHEDULED or PLACED. Once any member is ACCEPTED the customer cannot cancel and no refund is owed (T3).
- A restaurant (or a platform admin) may decline ONE member order; that raises a member refund (T2).
- Accepting is PLACED to ACCEPTED as a conditional update under the member lock; the accept is audited; a platform-admin accept is a distinct audited action.
- Late-delivery cancel of one member opens at `late_cancel_from_at`; it is behind the flag `schedule.late-cancel.enabled` (default false, set explicitly in `application.properties`). While the flag is off the endpoint refuses with a clear message and writes nothing.
- Every write takes the lock order: group row first, then member orders by id (`OrderGroupRepository.findByIdForUpdate`, `OrderRepository.findByGroupIdForUpdateOrderById`).

## Reuse
`service/schedule/cancel/CancelWindowResolver` (`customerMayCancel`, `lateCancelOpen`), `service/ScheduleReservationService` (`voidGroup`, `restock`), `service/schedule/payment/*` (do not edit), `service/refund/group/GroupRefundService.raise` and `RaiseGroupRefundCommand` (order amounts null means remaining; includeFees), `RefundEvent`, `RefundCustomerReason`, `RefundTechnicalCause`, `OrderStatus`, `service/impl/OrderServiceImpl` (read `updateOrderStatus`, `cancelOrder` and the Schedule guards added in the last step), `PlatformAuditRecorder` / `PlatformAuditAction` and the audit tests (`AuditEndpointDeclarationTest` and similar: read how a new audited route must be declared), `Delivery` / `DeliveryRepository` (to revoke a live delivery), `service/PermissionService` (seller permission as in the existing seller status route).

## Contract already written (do not change signatures)
`service/schedule/cancel/ScheduleCancelService` (getGroup, cancelGroup, declineMember, acceptMember, lateCancelMember), `dto/schedule/ScheduleGroupView`.

## Build
1. **Single-member void.** `ScheduleReservationService` has only `voidGroup`. ADD `voidMember(UUID orderId, String reasonCode)` to the interface, `ScheduleReservationServiceImpl` and `ScheduleReservationSettler` (read `voidGroup` and follow its locking and ledger rules): HELD becomes VOIDED with no counters; CONFIRMED becomes VOIDED and the dish sold_qty of that member lines is reduced, and the slot-day `reserved_groups` is reduced ONLY when the LAST confirmed member of the group is voided. It must be idempotent (voiding an already VOIDED reservation is a no-op). Do not change existing `voidGroup` behaviour; existing reservation tests stay green.
2. `service/schedule/cancel/ScheduleCancelServiceImpl` plus helpers (each under 250 lines):
   - `getGroup`: owner only (not found for another customer), builds `ScheduleGroupView` with member order codes (group code plus the suffix).
   - `cancelGroup`: owner only; group must be PAID; `CancelWindowResolver.customerMayCancel`; every member SCHEDULED or PLACED else a typed BusinessRuleViolationException saying the order is already accepted. One transaction: members to CANCELLED (conditional on the status read under the lock), reservations voided (`voidGroup`), ONE full group refund via `GroupRefundService.raise` (all members, includeFees true, event CANCEL, reason CUSTOMER_CANCELLED).
   - `declineMember`: actor needs the shop permission (same as the existing seller route) or be a platform admin; the order must be a group member in PLACED or ACCEPTED (SCHEDULED only by a platform admin); member to DECLINED conditionally; `voidMember`; member refund via `GroupRefundService.raise` (this member null amount; fees only if the math allows); audit.
   - `acceptMember`: PLACED to ACCEPTED conditional under the member lock, audited; `byPlatformAdmin` writes a distinct audit action and is only reachable from the admin endpoint.
   - `lateCancelMember`: flag off means refuse; flag on: owner only, `CancelWindowResolver.lateCancelOpen`, member not DELIVERED and not already CANCELLED or DECLINED; in ONE transaction under the locks: member CANCELLED, any live delivery for the order revoked (set to CANCELLED), the order delivery OTP cleared, member refund raised (customer reason CUSTOMER_CANCELLED, not restocked because the food was made), and a Spring event `ScheduleMemberLateCancelledEvent(orderId, deliveryId)` published for the rider notice (new event class; no listener needed now).
3. **Seller route.** In `OrderServiceImpl.updateOrderStatus` (and only there), a transition on a Schedule member (group_id not null) to ACCEPTED or DECLINED/CANCELLED now DELEGATES to `ScheduleCancelService.acceptMember` or `declineMember` (the earlier step made these paths refuse members; keep the refusal for every other transition). Avoid a Spring bean cycle (ObjectProvider if needed). Ungrouped Eat Now behaviour must stay byte-for-byte the same.
4. **Controllers.** `controller/ScheduleGroupController`: `GET /api/schedule/groups/{groupId}`, `POST /api/schedule/groups/{groupId}/cancel`, `POST /api/schedule/orders/{orderId}/late-cancel`; user from the principal like `PaymentController`; `ApiResponse<ScheduleGroupView>`. In `AdminOrderController` add `POST /api/admin/orders/{orderId}/accept` (platform admin only, audited, declared the way the audit tests require).
5. `application.properties`: `schedule.late-cancel.enabled=false`.
6. **Tests** (JUnit 5 plus Mockito, no database, one file per class): cancelGroup before and after the deadline, after one member ACCEPTED, another customer gets not found, refund raised once and holds voided; declineMember permissions and states, refund per member; acceptMember conditional race (second accept refused); late-cancel flag off refuses and writes nothing, flag on cancels, revokes the delivery, clears the OTP; `voidMember` HELD and CONFIRMED, last member reduces `reserved_groups`, idempotent; seller route delegation versus Eat Now unchanged; lock order group then members.

## Rules
Files under 250 lines, methods under 60 lines, comments state a rule in one sentence (no history), no entities from controllers. Do NOT edit the checkout files (`service/schedule/checkout/*`, `ScheduleCheckoutController`, `GlobalExceptionHandler`), the group payment files (`service/schedule/payment/*`, `SchedulePaymentController`, `ExtraCapture*`), `PaymentServiceImpl`, `DeliveryServiceImpl`, or refund code.

## Reply with
Every file created or edited, every assumption (audit action names, permission checks, statuses), and what you could not verify. Do not claim anything compiles or passes.
