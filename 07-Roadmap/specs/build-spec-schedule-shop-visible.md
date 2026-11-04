# Build spec: Schedule shop-visible orders (backend, one PR)

You are implementing, in the backend repo `ninja delivery service java` on branch `feature/schedule-shop-visible`. Edit files only; do not run git commands that change state, do not run Maven (it cannot run for you), do not touch any database. Read first: `../Ninjasu_Documentation/07-Roadmap/schedule-shop-visible-slice-plan.md` (v2) and the sections "Decision 2026-10-30", "Review 2026-10-30" and "Second pass" at the end of `schedule-2b8-2b10-plan.md`. This spec lists what to build; the plan has the why.

## Ground rules
- A "Schedule member" order is `order.getGroupId() != null`. Create ONE method for it (suggested `ScheduleMember.is(Order)` in `service/schedule/shop/`) and call it from every gate. Do not use `cartType` for this.
- `DeliveryServiceImpl.java` (968 lines) and `OrderServiceImpl.java` (417 lines) are over the size limit: do NOT add logic to them. Edit only to call into new small classes. New classes go in `service/schedule/shop/`, DTOs in `dto/schedule/shop/`, controller in `controller/`.
- Eat Now behaviour must not change. Reuse: `OrderRepository.transitionScheduleMember` (expected-status compare-and-set), `ScheduleGroupAccess` (group lock then member locks), `permissionService.requirePermission(shopId, userId, Permission.ONLINE_ORDERS_MANAGE)`, `BusinessRuleViolationException`, `ApiResponse<T>` envelope, SLF4J logging (INFO on entry, WARN on refusal).
- No SQL, no new table or column. No entity returned from a controller. Match surrounding code style and comment density; comments state the rule only, no history.
- Flow for a member: `SCHEDULED -> ACCEPTED -> READY`. `PREPARING` is skipped. `OUT_FOR_DELIVERY` and `DELIVERED` are NOT reachable in this cut (deferred): the member transition table must not allow them yet.

## Part 1: Isolation (must be complete before Part 2 matters)
1. **Dispatch gate.** One method (e.g. `ScheduleMember.refuseDispatch(Order)`) throwing `BusinessRuleViolationException("A scheduled order is not dispatched per order")`. Call it at EVERY dispatch entry in `DeliveryServiceImpl`: manual assignment (around line 267; today it refuses only `Group.SCHEDULED_ONLY` status), reassignment (`reassignDelivery`, around line 686, which builds a fresh assignment), rider acceptance (around line 164) placed BEFORE the idempotent "return the delivery they already own" branch, and any other method that creates or hands out a delivery for an order id (grep `new Delivery()` and `deliveryRepository.save`). Also in `listener/DeliveryDispatchListener.java`: ignore the event when the order is a Schedule member (load the order if the event does not carry group info), and in any broadcast or scheduled sweep that scans READY orders (grep `OrderStatus.READY` under `service` and `scheduler`).
2. **Eat Now board.** The shop delivery board query in `OrderServiceImpl` (around line 267, live statuses) must exclude Schedule members (`group_id IS NULL` in the query or repository method, not a Java filter after paging). Also exclude them from any other shop or rider list that includes ACCEPTED or READY by status.
3. **Old shop detail route.** `OrderServiceImpl.getOrderForShop` (around line 244) must refuse a Schedule member with the same not-found behaviour used for hidden orders.
4. **Notification listener.** `notification/OrderNotificationListener.java` must send no shop push, no alarm and never publish `OrderPlacedEvent` for a Schedule member on any status event (including READY and the customer-cancel branch). Customer-facing pushes are unchanged.
5. **KDS and POS.** Do not change them; add a test that proves no KDS or POS read returns a member (they are limited to dine-in, takeaway and staff sources: assert it).
6. **Audit queries.** Add a vault doc `Ninjasu_Documentation/07-Roadmap/schedule-member-audit.md` with two read-only SQL queries labelled "read-only, run on a branch or by Samivan": grouped orders whose `cart_type` is not SCHEDULE, and SCHEDULE orders with no `group_id`. No code.

## Part 2: Transitions
7. **Transition table.** Replace the inline switch in `OrderServiceImpl.validateSellerStatusTransition` (around line 399) by a call to a new class (e.g. `ScheduleMemberTransitions`) keyed by (member or not, current status). Eat Now rows exactly as today. Member rows: `SCHEDULED -> ACCEPTED, DECLINED, CANCELLED`; `ACCEPTED -> READY, CANCELLED`; everything else refused.
8. **Shop accept and decline of SCHEDULED.** In `ScheduleCancelServiceImpl`: `acceptMember` (requires PLACED today) must accept `SCHEDULED` for the shop; `declineMember` (shop path allowed only PLACED or ACCEPTED, admin-only for SCHEDULED) must let the shop decline `SCHEDULED` (keep `ONLINE_ORDERS_MANAGE`, the reason, the refund and restock, the audit row). Keep the existing admin path. Do not change whole-group cancel (`cancelGroup`): its rule stays as is.
9. **READY.** In the group-member branch of `OrderServiceImpl.updateOrderStatus` (around line 331) route `READY` for a member to a new method (e.g. `ScheduleCancelService.markMemberReady` or a method in a new `service/schedule/shop` class) that: locks the group then the members (`ScheduleGroupAccess`), checks shop permission, requires the group be paid, uses `transitionScheduleMember` with expected status `ACCEPTED` and next `READY` (zero rows updated means refuse with a state-changed error, never an unconditional write), audits like accept, and publishes the normal `OrderStatusChangedEvent`. Every other member target (including `PREPARING`, `OUT_FOR_DELIVERY`, `DELIVERED`) is refused.
10. All member transitions use group-lock-then-member-lock order and the expected-status compare-and-set.

## Part 3: Shop Schedule reads
11. New controller (shop audience, same prefix and security pattern as `ShopOrderController`) with three GETs: list, count, detail. Permission `ONLINE_ORDERS_MANAGE` for the path shop id.
    - **List:** the shop's Schedule members (`group_id IS NOT NULL`, status in SCHEDULED, ACCEPTED, READY) joined to `order_groups`, grouped by `service_date` and `slot_id` (include slot start/end and name if the slot entity exposes them), ordered by date then slot start then placed time. Each row: order id, order code (group code + suffix), status, customer display name and delivery address fields the order already carries, line items, totals, `release_at`, group id. Default date is today in the area's zone; accept an optional `serviceDate` query param. Paged.
    - **Count:** number of SCHEDULED (awaiting accept) members for the shop for the date, plus per-status counts. Cheap single aggregate query.
    - **Detail:** one member by id, only if it belongs to the path shop and is a Schedule member; anything else is not found.
12. DTOs and mapping in the service layer; repository queries in `OrderRepository` or a new `ScheduleShopOrderRepository` (prefer a new one to keep `OrderRepository` small). Image URLs follow the S3 rule in the backend CLAUDE.md if any are returned.

## Tests (write them; I will run them)
- Table-driven transition test: every (member or not, status) pair for both kinds.
- Dispatch gate: each entry refuses a member in ACCEPTED and READY, and a member that already has a delivery (reassign, rider-accept replay); Eat Now READY still dispatches (listener test).
- Shop accept and decline of SCHEDULED succeed with permission, refuse without, refuse a wrong shop; decline refunds and restocks (existing mocks).
- READY: ACCEPTED to READY works once; a second call or a concurrent cancel yields a refusal, not an overwrite; PREPARING and later targets refused.
- Board and old detail route exclude and refuse members; guessed id refused.
- Notification listener: no shop push, no alarm, no `OrderPlacedEvent` for a member.
- Shop Schedule list groups by date and slot, count equals list, another shop's members hidden, detail of another shop's id is not found.
- Put tests beside the existing test of the class they cover under `src/test/java/...`; keep files under 400 lines; each test owns its data.

When done, reply with the list of files changed or added, each guard you added with its test name, and anything in this spec you could not do or that conflicted with the code. Do not claim a guard exists without naming the test that proves it.
