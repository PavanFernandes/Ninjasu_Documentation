# Schedule 2d.6a: "can't make" (`ticket_issue`) and its approval

Status: **FINAL v1.1 (2026-11-22). LOCKED.**
Reviewed by: Sol 6.2 (`gpt-6.2-sol`) via Devil's Advocate and 《Geld》 database/system design review (v1.0); a second Devil's Advocate and geld pass by the Claude session against the code (v1.1).
Signed off by: Samivan (2026-11-22; the three v1.1 decisions A, B and C below were answered the same day).

**v1.1 changes to v1.0 (all marked `[v1.1]` where they apply):**
- **A. Late approval.** Raising stops at slot start (D1), but approval has no time limit: only the order-state check applies. After the refund window (slot start + `refund_window_hours`) approval is admin-only and platform-funded (the OPS-5 rule, carried by the shared `GroupRefundIssuer`). v1.0 refused approval after slot start, which left a late ops answer unable to refund anyone.
- **B. Fees on an emptied group.** When approval leaves a group with no live order, the group's delivery and packaging fees are refunded in the same transaction, by the same rule `declineMember` uses (`fees = every member declined or cancelled`). Fees stay when other orders in the group continue.
- **C. Empty order keeps the stock consumed.** An order that loses every unit is voided through a new void variant that does **not** credit `schedule_stock_ledger.sold_qty`; slot capacity is released as for any void; the ticket gets `ORDER_REMOVED`.
- **D. Readers slice.** The G1 readers are assigned to a new slice **S3c** (v1.0 listed the formula but no slice built it).
- **E. Bounds.** `RaiseTicketIssueRequest.orderIds` is capped (`@Size(max = 100)`, elements `@NotNull`); the approve `selections` array is capped at 100; the ops queue takes `limit` (default 50, maximum 100) with keyset paging on `(raised_at DESC, id DESC)` for every status.
- **F. Wording.** The D4 sentence "restaurant absorbs the difference" is removed (fees are refunded by rule B or by an admin; there is nothing to absorb).
- **G. Stock invariant written down.** `schedule_stock_ledger.sold_qty` equals the sum of the confirmed reservation lines plus the sum of approved reductions for confirmed orders; a later void of a reduced member credits only the remaining quantity.

Written for: the two builders (Gemini 3.8 Flash and Codex gpt-6.2-sol) who will implement it, and the verifier session that will review it afterwards. Builders start at section 7.

Branches: backend `feature/schedule-ticket-issue-2d6a` cut from `origin/feature/schedule-3.4`; target `feature/schedule-3.4`. Web (3.4g, the ops problem queue and the restaurant's "can't make" screen) is a separate slice after this one and is out of scope here.

## 1. Goal and scope

A restaurant that cannot make a dish tells us on its Schedule orders. Nothing is refunded yet: the request waits in an ops queue. An ops manager (or platform admin) approves it, choosing which orders lose which units, or rejects it. Only approval does three things in one transaction: reduces the units the restaurant must make, refunds the affected customers for exactly those units, and appends a ticket amendment. Source of the rule: `schedule-plan.md` item 41 ("no automatic approval").

**In scope (2d.6a, backend only):** the `ticket_issue` tables and SQL; the shop endpoint that raises and lists issues; the ops endpoints that list, approve and reject; the approval transaction; the ticket amendment for it; audit; boot guard; tests.

**Out of scope:** web screens (3.4g and the shop screen), the ticket accept/ready/handover fan-out, ops cancel, labels data and the contract-freeze fixtures (that is **2d.6b**), a true "substitute" workflow (D7), customer push for a reduction (D8), payout rules (3.5).

## 2. What already exists (reuse, do not rebuild)

| Need | Existing owner (backend, `src/main/java/com/example/ninja/...`) |
|---|---|
| Partial refund by order line and unit, caps, tax split, idempotent key | `service/refund/group/GroupRefundService.raise(RaiseGroupRefundCommand.forManual(...lineQuantities...))`, `GroupRefundMath.planItems` |
| Approve + submit a refund the same transaction (the sequence to extract) | `service/refund/manual/ManualRefundServiceImpl.refundGroup` (raise, `RefundState.markApproved`, `PaymentRefundSubmitter.submit` after commit, platform audit) |
| Who pays by reason (restaurant-fault reasons) | `service/refund/RefundFundingRule` (`ITEM_UNAVAILABLE` is RESTAURANT) |
| Whole-order restaurant decline + refund | `service/schedule/cancel/ScheduleCancelServiceImpl.declineMember` |
| Ticket amendment rows, `LINES_REDUCED` and `CANT_MAKE_APPROVED` constants | `entity/ScheduleTicketAmendment`, `service/schedule/ticket/record/TicketAmendmentRecorder` (today it handles only `ScheduleMemberChangedEvent` kinds CONFIRMED and VOIDED) |
| Live counts and the shop-day cache | `service/schedule/ticket/view/ScheduleShopDayCache`, `ShopDayCacheInvalidator` |
| Stock and capacity held per order | `service/ScheduleReservationService` (`voidMember`), `service/impl/ScheduleReservationSettler`, entities `ScheduleReservation`, `ScheduleReservationLine` |
| Area access (admin, manager, ops) | `service/schedule/access/AreaAccessService.requireForSlot / requireForArea / requireForGroup` |
| Shop-side permission | `Permission.ONLINE_ORDERS_MANAGE` through the shop permission service (as `ScheduleCancelServiceImpl.declineMember`) |
| Audit | platform: `@PlatformAuditedEndpoint` + `PlatformAuditAction` + `PlatformAuditRecorder.recordAreaAction`; shop: `shopAudit.record(shopId, actorUserId, AuditAction...)` |
| Error codes | `ScheduleMenuException(HttpStatus, "CODE", message)`, rendered as `data: {CODE: message}` |
| Boot guard for hand-run SQL | `config/ScheduleBatchRequiredObjects` pattern and its schema test |

Missing (to build): `ticket_issue` tables; a partial reduction of a member's reservation lines (only whole-member `voidMember` exists); an event and recorder branch for `LINES_REDUCED`; the raise, list, approve and reject services and endpoints.

## 3. Decisions Confirmed (Samivan 2026-11-22)

| # | Question | Decision | Implementation Rule |
|---|---|---|---|
| D1 | When may a restaurant raise "can't make"? | While every affected order is `PLACED`, `ACCEPTED` or `SCHEDULED`, and the slot has not started | Raise: verified at raise (slot not started, every named order in `PLACED`, `ACCEPTED` or `SCHEDULED`). **[v1.1] Approval: no time limit; the order-state check is re-run under the locks.** After the refund window the approval is admin-only and PLATFORM-funded. |
| D2 | Granularity | One dish (menu item) in one shop, slot and date, a quantity in units, optionally naming orders | If named orders given, selections are validated within that candidate set. Unnamed issue uses the eligible dish pool. Explicit selections required at approval. |
| D3 | Who decides | `AREA_MANAGER` with `can_issue_refunds` = TRUE, or `PLATFORM_ADMIN`; `AREA_OPS` reads only. Reject: `AREA_MANAGER` (regardless of refund bit) or admin | Area manager approval checks `ManualRefundAccess.requireIssuer` (needs `can_issue_refunds`). Reject needs area manager role only. |
| D4 | Who pays | The restaurant: refund reason `ITEM_UNAVAILABLE`, funded `RESTAURANT` | Pro-rata item price + tax funded by restaurant. **[v1.1]** Fees are handled only by rule D9 below. |
| D5 | Ops never answers | Stays `PENDING`; no auto-approve; queue shows age; no auto-timeout | Stays `PENDING` in DB; queue displays age and marks stale/expired after slot start. Ops can manually reject after cutoff. |
| D6 | Open issues per dish | At most one `PENDING` issue per (shop, slot, date, menu item) | Partial unique index `uq_ticket_issues_pending_dish` enforced in PostgreSQL. Replay handles same `request_id`. |
| D7 | "Ask the restaurant to substitute" | Recorded as `REJECTED` with code `SUBSTITUTE_ASKED` and note | Terminal rejection state. Original orders and stock unchanged. |
| D8 | Customer message | Refund view ("item unavailable") + effective fulfillment quantity in customer order response | No new push notifications in 2d.6a. Fulfillment quantities reflect reductions. |
| D9 | An order loses every unit | **[v1.1]** Item refund, plus the group fees when no live order is left in the group | Approval refunds the item lines + pro-rata tax. If an order becomes empty it is voided without crediting stock (see Stock) and the ticket gets `ORDER_REMOVED`. If the group then has no live order, the delivery and packaging fees (and round-off) are refunded in the same transaction by the `declineMember` rule; otherwise fees stay. |
| D10 | Approving fewer units than requested | Allowed: approved total is at most requested quantity | Selections array must be explicit, positive, non-empty, and sum $\le$ `requested_qty`. |
| Stock | Stock resale policy | **No automatic resale flow** | When an issue is approved, do **NOT** decrement `sold_qty` in `schedule_stock_ledger`. Capacity remains consumed so checkout cannot resell. Restaurant can increase stock by +1 or ops/platform admin can raise stock manually if desired. **[v1.1]** An emptied order is voided through a void variant that skips the `sold_qty` credit (slot capacity is released as for any void). Invariant: `sold_qty` = sum of confirmed reservation lines + sum of approved reductions for confirmed orders; a later void of a reduced member credits only its remaining quantity (test required). |
| PII | Queue visibility | **Delivery address visible to Ops** | Ops queue & detail endpoints include delivery address (to help plan batching and routing). Customer name and phone remain omitted. Free-text notes sanitized. |

## 4. Design Gate & Geld Findings

### Devil's Advocate & Geld Verdict: APPROVED WITH CHANGES (2026-11-22)

The blind Geld review and Devil's Advocate by Sol 6.2 (`gpt-6.2-sol`) established the following mandatory architectural rules:

- **G1 · Quantity Representation (Fulfillment Projection):**
  - `order_lines.quantity` retains the original purchased quantity and snapshot prices for receipts and audit.
  - The durable record of reductions is `schedule_ticket_issue_lines` keyed by `order_line_id`.
  - Readers (`TicketOrderPayloads`, `ShopDayViewLoader`, `ScheduleCustomerGroupMapper`, `OrderMapper`) compute:
    $$\text{effective fulfillment quantity} = \text{order\_lines.quantity} - \sum(\text{approved issue lines})$$
  - Reservation lines are reconciled to this aggregate.
- **G2 · Lock Ordering (Anti-Deadlock):**
  - Lock order is strictly:
    1. Lock `schedule_ticket_issues` row `FOR UPDATE`.
    2. Discover all affected group IDs via ID-only projection.
    3. Acquire **all group locks in ascending ID order** (`order_groups FOR UPDATE`).
    4. Acquire all affected order/member locks in ascending ID order.
    5. Acquire the `slot-day` lock (`ScheduleLockSequence`).
    6. Acquire affected `schedule_stock_ledger` rows in ascending `item_id` order.
  - Revalidate all conditions (status, cutoff, amounts, caps) *after* all locks are held.
- **G3 · Replay & Idempotency:**
  - Persist `request_hash bytea` (SHA-256 of raise payload) and `decision_hash bytea` (SHA-256 of decision payload).
  - A replay of the exact same approval returns the stored `IssueView` without invoking the refund issuer again.
  - Deterministic refund obligation key `<paymentId>:MANUAL:<requestId>` where `requestId = UUID.nameUUIDFromBytes(("schedule-ticket-issue:v1:" + issueId + ":" + groupId).getBytes(StandardCharsets.UTF_8))`.
- **G4 · Queue Visibility & PII:**
  - Ops queue includes: `issueId`, `shopName`, `menuItemId`, `itemName`, `requestedQty`, `minutesToSlotStart`, `orderCode`, `groupCode`, `deliveryAddress`, `status`.
  - Customer name and customer phone are strictly excluded.
- **G5 · Submission Failure & Cap Reservation:**
  - Refunds commit before external Razorpay submission.
  - If Razorpay returns `FAILED` or times out, the refund row remains linked in `schedule_ticket_issue_refunds` and counts against line/order caps so funds cannot be double-spent. Admin refund board handles retries. Issue status stays `APPROVED`.

### Data Model & DDL (`db_manual/schedule-ticket-issue-migration.sql`)

```sql
-- Idempotent migration for Schedule 2d.6a Ticket Issue ("can't make")
-- Target: neondb (PostgreSQL 17.x)

CREATE TABLE IF NOT EXISTS public.schedule_ticket_issues (
    id uuid NOT NULL,
    shop_id uuid NOT NULL,                    -- Soft reference (shops soft-delete)
    service_area_id uuid NOT NULL,
    slot_id uuid NOT NULL,
    service_date date NOT NULL,
    menu_item_id uuid NOT NULL,
    item_name text NOT NULL,
    requested_qty integer NOT NULL,
    request_id uuid NOT NULL,
    request_hash bytea NOT NULL,
    note text,
    status text NOT NULL DEFAULT 'PENDING',
    raised_by uuid NOT NULL,
    raised_at bigint NOT NULL,
    decided_by uuid,
    decided_at bigint,
    decision_code text,
    decision_note text,
    decision_hash bytea,
    CONSTRAINT pk_ticket_issues PRIMARY KEY (id),
    CONSTRAINT uq_ticket_issues_shop_request UNIQUE (shop_id, request_id),
    CONSTRAINT fk_ticket_issues_area FOREIGN KEY (service_area_id)
        REFERENCES public.service_area(id) ON DELETE RESTRICT,
    CONSTRAINT fk_ticket_issues_slot FOREIGN KEY (slot_id)
        REFERENCES public.service_area_slot(id) ON DELETE RESTRICT,
    CONSTRAINT fk_ticket_issues_item FOREIGN KEY (menu_item_id)
        REFERENCES public.items(id) ON DELETE RESTRICT,
    CONSTRAINT fk_ticket_issues_raiser FOREIGN KEY (raised_by)
        REFERENCES public.users(id) ON DELETE RESTRICT,
    CONSTRAINT fk_ticket_issues_decider FOREIGN KEY (decided_by)
        REFERENCES public.users(id) ON DELETE RESTRICT,
    CONSTRAINT chk_ticket_issues_request CHECK (
        requested_qty BETWEEN 1 AND 999
        AND char_length(btrim(item_name)) BETWEEN 1 AND 120
        AND octet_length(request_hash) = 32
        AND (note IS NULL OR char_length(note) <= 500)
    ),
    CONSTRAINT chk_ticket_issues_status CHECK (
        status IN ('PENDING', 'APPROVED', 'REJECTED')
    ),
    CONSTRAINT chk_ticket_issues_decision CHECK ((
        (status = 'PENDING'
         AND num_nonnulls(decided_by, decided_at, decision_code, decision_note, decision_hash) = 0)
        OR
        (status IN ('APPROVED', 'REJECTED')
         AND decided_by IS NOT NULL AND decided_at IS NOT NULL
         AND decided_at >= raised_at
         AND decision_hash IS NOT NULL AND octet_length(decision_hash) = 32
         AND (decision_note IS NULL OR char_length(decision_note) <= 255)
         AND (
             (status = 'APPROVED' AND decision_code = 'APPROVED')
             OR
             (status = 'REJECTED'
              AND decision_code IN ('SUBSTITUTE_ASKED', 'CAN_MAKE', 'OTHER')
              AND decision_note IS NOT NULL AND btrim(decision_note) <> '')
         ))
    ) IS TRUE)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_ticket_issues_pending_dish
    ON public.schedule_ticket_issues (shop_id, service_date, slot_id, menu_item_id)
    WHERE status = 'PENDING';

CREATE INDEX IF NOT EXISTS idx_ticket_issues_area_queue
    ON public.schedule_ticket_issues (service_area_id, status, raised_at, id);

CREATE INDEX IF NOT EXISTS idx_ticket_issues_shop_history
    ON public.schedule_ticket_issues (shop_id, service_date, slot_id, raised_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS public.schedule_ticket_issue_orders (
    issue_id uuid NOT NULL,
    order_id uuid NOT NULL,
    CONSTRAINT pk_ticket_issue_orders PRIMARY KEY (issue_id, order_id),
    CONSTRAINT fk_ticket_issue_orders_issue FOREIGN KEY (issue_id)
        REFERENCES public.schedule_ticket_issues(id) ON DELETE RESTRICT,
    CONSTRAINT fk_ticket_issue_orders_order FOREIGN KEY (order_id)
        REFERENCES public.orders(id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_ticket_issue_orders_order
    ON public.schedule_ticket_issue_orders (order_id);

CREATE TABLE IF NOT EXISTS public.schedule_ticket_issue_lines (
    issue_id uuid NOT NULL,
    order_line_id uuid NOT NULL,
    quantity integer NOT NULL,
    CONSTRAINT pk_ticket_issue_lines PRIMARY KEY (issue_id, order_line_id),
    CONSTRAINT fk_ticket_issue_lines_issue FOREIGN KEY (issue_id)
        REFERENCES public.schedule_ticket_issues(id) ON DELETE RESTRICT,
    CONSTRAINT fk_ticket_issue_lines_line FOREIGN KEY (order_line_id)
        REFERENCES public.order_lines(id) ON DELETE RESTRICT,
    CONSTRAINT chk_ticket_issue_lines_qty CHECK (quantity BETWEEN 1 AND 999)
);

CREATE INDEX IF NOT EXISTS idx_ticket_issue_lines_line
    ON public.schedule_ticket_issue_lines (order_line_id, issue_id)
    INCLUDE (quantity);

CREATE TABLE IF NOT EXISTS public.schedule_ticket_issue_refunds (
    issue_id uuid NOT NULL,
    group_id uuid NOT NULL,
    root_refund_id uuid NOT NULL,
    CONSTRAINT pk_ticket_issue_refunds PRIMARY KEY (issue_id, group_id),
    CONSTRAINT uq_ticket_issue_refunds_root UNIQUE (root_refund_id),
    CONSTRAINT fk_ticket_issue_refunds_issue FOREIGN KEY (issue_id)
        REFERENCES public.schedule_ticket_issues(id) ON DELETE RESTRICT,
    CONSTRAINT fk_ticket_issue_refunds_group FOREIGN KEY (group_id)
        REFERENCES public.order_groups(id) ON DELETE RESTRICT,
    CONSTRAINT fk_ticket_issue_refunds_root FOREIGN KEY (root_refund_id)
        REFERENCES public.payment_refunds(id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_ticket_issue_refunds_group
    ON public.schedule_ticket_issue_refunds (group_id, issue_id);

ALTER TABLE public.schedule_ticket_amendments
    ADD COLUMN IF NOT EXISTS ticket_issue_id uuid,
    ADD CONSTRAINT fk_ticket_amendments_issue FOREIGN KEY (ticket_issue_id)
        REFERENCES public.schedule_ticket_issues(id) ON DELETE RESTRICT,
    ADD CONSTRAINT chk_ticket_amendments_issue_cause CHECK (
        (ticket_issue_id IS NOT NULL) = (cause = 'CANT_MAKE_APPROVED')
        AND (ticket_issue_id IS NULL OR kind IN ('LINES_REDUCED', 'ORDER_REMOVED'))
    );

CREATE UNIQUE INDEX IF NOT EXISTS uq_ticket_amendments_issue_order
    ON public.schedule_ticket_amendments (ticket_issue_id, order_id)
    WHERE ticket_issue_id IS NOT NULL;
```

## 5. API Contract

### Shop Endpoints (`/api/shops/{shopId}/orders/schedule/cant-make`)
*Permission: `ONLINE_ORDERS_MANAGE` on shop*
- **`POST`** body:
  ```json
  {
    "requestId": "uuid",
    "slotId": "uuid",
    "serviceDate": "2026-11-22",
    "menuItemId": "uuid",
    "quantity": 2,
    "orderIds": ["uuid"],
    "note": "Ran out of ingredients"
  }
  ```
  **[v1.1]** `orderIds` at most 100, no null elements; `quantity` 1 to 999; `note` at most 500, with the form hint "no names or phone numbers".
  $\to$ Returns `ApiResponse<IssueView>`
- **`GET ?serviceDate=...&slotId=...`** $\to$ Returns `ApiResponse<List<IssueView>>` (newest first).

### Ops Endpoints (`/api/ops/ticket-issues`)
- **`GET ?areaId=...&status=PENDING`** (Access: `AREA_OPS` or `AREA_MANAGER` or admin). **[v1.1]** `limit` default 50, maximum 100; order `raised_at DESC, id DESC` with a keyset cursor, for every status.
  $\to$ Returns queue rows with delivery addresses, timing, order codes, group codes, quantities.
- **`GET /{id}`** $\to$ Detail view with candidate orders, lines, and delivery address.
- **`POST /{id}/approve`** (Access: `AREA_MANAGER` with `can_issue_refunds`, or `PLATFORM_ADMIN`)
  - Body:
    ```json
    {
      "selections": [
        { "orderId": "uuid", "orderLineId": "uuid", "quantity": 1 }
      ],
      "note": "Approved reduction"
    }
    ```
  - **[v1.1]** `selections` has 1 to 100 entries; `quantity` is at least 1.
  - Emits `@PlatformAuditedEndpoint(SCHEDULE_TICKET_ISSUE_APPROVED)`.
- **`POST /{id}/reject`** (Access: `AREA_MANAGER` or `PLATFORM_ADMIN`)
  - Body: `{"code": "SUBSTITUTE_ASKED" | "CAN_MAKE" | "OTHER", "note": "..."}`
  - Emits `@PlatformAuditedEndpoint(SCHEDULE_TICKET_ISSUE_REJECTED)`.

## 6. The Approval Algorithm (Single Transaction)

1. **Authorization & Issue Lock**:
   - Verify caller has `AREA_MANAGER` on issue's area AND `can_issue_refunds = true` (or `PLATFORM_ADMIN`).
   - `SELECT * FROM schedule_ticket_issues WHERE id = :id FOR UPDATE`.
   - Replay check: if already `APPROVED` with matching `decision_hash`, return stored `IssueView`. If already decided with different hash, return 409 `ISSUE_ALREADY_DECIDED`.
2. **Lock Acquisition (Anti-Deadlock)**:
   - Discover affected group IDs from selections.
   - Lock all groups in ID order (`SELECT * FROM order_groups WHERE id IN (:groupIds) ORDER BY id FOR UPDATE`).
   - Lock all member orders in ID order.
   - Acquire slot-day lock (`ScheduleLockSequence.acquireSlotDay`).
   - Lock affected item-day stock ledger rows.
3. **Validation**:
   - **[v1.1]** No slot-start check at approval. Re-check, under the locks, that every affected order is `PLACED`, `ACCEPTED` or `SCHEDULED` and its group is PAID. If the refund window (slot start + `refund_window_hours`) has closed, the caller must be a platform admin and the refunds are PLATFORM-funded (carried by the shared `GroupRefundIssuer`).
   - Check every selection belongs to the shop, dish, slot, date.
   - Verify line available units: $\text{selectedQty} \le \text{purchasedQty} - \text{priorRefundedUnits}$.
   - Sum of selections $\le \text{requested\_qty}$.
4. **Execution per Group**:
   - For each group:
     - Invoke shared `GroupRefundIssuer.refundGroup(RaiseGroupRefundCommand.forManual(...lineQuantities...))`.
     - Reason: `ITEM_UNAVAILABLE` (funded `RESTAURANT`).
     - Key: `schedule-ticket-issue:v1:<issueId>:<groupId>`.
     - Store row in `schedule_ticket_issue_refunds`.
5. **Reservation & Kitchen Reduction**:
   - Lower `ScheduleReservationLine.quantity` for the affected orders.
   - Do **NOT** decrement `sold_qty` in `schedule_stock_ledger` (keeps capacity consumed so item cannot be resold).
   - **[v1.1]** If an order loses all units: void it through the no-credit void variant (Stock rule), mark it `DECLINED`, and let the recorder append `ORDER_REMOVED`. If the group then has no live order, include the delivery and packaging fees and the round-off in that group's refund (the `declineMember` rule, D9).
6. **Ticket Amendment**:
   - Publish `ScheduleLinesReducedEvent`.
   - If slot is frozen: `TicketAmendmentRecorder` appends `LINES_REDUCED` (or `ORDER_REMOVED` if all units gone), cause `CANT_MAKE_APPROVED`, source key `REDUCE:<issueId>:<menuItemId>:<orderId>`, links `ticket_issue_id`.
   - `ShopDayCacheInvalidator` evicts cache after commit.
7. **Issue Finalization & Audit**:
   - Insert `schedule_ticket_issue_lines` rows.
   - Update issue to `APPROVED`, store `decided_by`, `decided_at`, `decision_code='APPROVED'`, `decision_hash`.
   - Record `PlatformAuditRecorder.recordAreaAction` with ID-only metadata.
8. **After Commit**:
   - Trigger asynchronous Razorpay submission via `PaymentRefundSubmitter`.
   - If submission fails, obligation remains tracked in `schedule_ticket_issue_refunds` and prevents double refunding.

## 7. Slices, Owners and Acceptance

| Slice | Content | Builder | Done When |
|---|---|---|---|
| **S0** | Plan sign-off, Geld & DA findings folded, locked v1.0 | Samivan + Codex Sol 6.2 | **DONE** (2026-11-22) |
| **S1** | Migration SQL `schedule-ticket-issue-migration.sql`, entities, repositories, boot-guard entries, schema tests | **Codex Sol 6.2** | `ScheduleTicketIssueSchemaTest` + boot guard green |
| **S2** | Shop raise & list: controller, service, validation, idempotency, audit, tests | **Gemini 3.8 Flash (one try)**, else Codex | Controller + service tests green |
| **S3a** | Extract shared `GroupRefundIssuer` from `ManualRefundServiceImpl` (no behavior change) | **Codex Sol 6.2** | All existing manual refund tests pass unchanged |
| **S3b** | Approval transaction: lock order, reservation reduction, `ScheduleLinesReducedEvent`, recorder branch, approve/reject endpoints, audit | **Codex Sol 6.2** | All approval and concurrency tests green |
| **S3c** **[v1.1]** | Effective-quantity readers: one helper `effective = order_lines.quantity - sum(approved issue lines)` backed by ONE batched query (`sum ... where order_line_id in (:ids) group by order_line_id`, never one query per line), used by `TicketOrderPayloads`, `ShopDayViewLoader`, `ScheduleCustomerGroupMapper` and `OrderMapper`, and applied to Schedule orders only (`OrderMapper` serves other order types); a source-scan test that no other Schedule reader calls `OrderLine.getQuantity()` directly; the no-credit void variant and the `sold_qty` invariant test | **Codex Sol 6.2** | Reader tests green; a Schedule order with a reduction shows the effective quantity in the shop, ticket and customer responses and the original quantity on receipts |
| **S4** | Ops queue reads (`GET` list & detail) with delivery address and access matrix | **Gemini 3.8 Flash (one try)**, else Codex | Read tests green |
| **S5** | Full backend test suite (`./mvnw -B test -Dtest='!NinjaDeliveryServiceApplicationTests'`), `/gcp judge full`, PRs | Samivan + verifier | Suite green, PRs raised to `feature/schedule-3.4` |

---

## 8. Rollout Plan

1. **SQL First**: Samivan runs `db_manual/schedule-ticket-issue-migration.sql` on Neon.
2. **Backend**: Boot guard checks the 6 new schema objects on startup.
3. **Web (3.4g)**: Problem queue on ops board connects to these endpoints.

## 9. Status after build and review (2026-11-23)

Built on branch `feature/schedule-ticket-issue-2d6a` and merged into `feature/schedule-3.4` (backend PR #105); the screens (3.4g) are web PR #52. Related tests only were run per slice (332 tests on the final tip); the full suite was last run green (3,277) on the first fix commit and is left to the push to main and CI.

Differences from v1.1 found while building (accepted unless Samivan objects):
- A decided issue reads from the stored `schedule_ticket_issue_lines`, frozen at `decided_at`: `candidateOrders` is empty for decided issues and `minutesToSlotStart` is frozen. The replay view carries no refund fields (the contract in section 6 step 7 and G3 promised refunds in the stored view); the refund link is in `schedule_ticket_issue_refunds`.
- An unnamed issue stores no orders; the eligible pool is evaluated at approval and shown in the detail view only.
- `ScheduleTicketIssueServiceImpl` is not `@Transactional` as a whole: the loser of a unique violation re-reads in a fresh transaction.

Open risks:
- **Close a failed refund:** a held FAILED ticket-issue refund keeps its cap until an admin retry replaces it. If an admin abandons it the cap is held forever. Needs a "close failed refund" rule (own small slice).
- **Browser check:** the ops Problems queue and the shop Can't make dialog were built from types, lint and pure specs only.
- **Not in 3.4:** 2d.6b (ticket fan-out, ops cancel, labels data, contract freeze fixtures).
