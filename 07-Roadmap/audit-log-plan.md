---
id: ""
title: "Audit Log (Activity Trail) — Plan"
summary: "Cross-module, append-only audit log for Ninjasu POS: who did what, to which table/bill/item, when — filterable by module, event, staff and date; built as a platform primitive every future module inherits, with competitor case studies, DA conditions, security review and phases."
type: how-to
status: designing
apps: [backend, web, admin]
module: "audit"
anchors: []
verified_against: "backend main @ 2026-09-27 (pre-RBAC-merge)"
updated: 2026-09-27
---

# Audit Log (Activity Trail) — Plan

## Problem

Client requirement (2026-09-27): a restaurant owner must be able to answer —

1. **Who handled which table?** With 5 staff on the floor: who opened table 5, who added items, who served, who settled.
2. **Who settled or cancelled a bill / voided a KOT?**
3. **What did each person do today?** An activity log across the whole product — POS, kitchen, inventory/purchasing, menu, staff — filterable by **module**, **event**, **staff** and **date**.

And a system requirement from Samivan: this must be a **platform primitive**, not a POS feature — every
module built from now on records its actions without anyone remembering to design it again.

## What exists today (verified in code 2026-09-27)

There is **no audit log**. There are "who" columns on some rows, each holding only the *latest* actor,
never shown in any UI (web types `openedByStaffId`/`closedByStaffId` as raw UUIDs, never renders them).

| Recorded | Column |
|---|---|
| Opened table | `table_checks.opened_by_staff_id` |
| Fired KOT | `orders.placed_by_staff_id` |
| Approved guest table | `table_checks.guest_approved_by_staff_id` |
| Closed check | `table_checks.closed_by_staff_id` |
| Settled bill / each tender | `bills.settled_by_staff_id`, `bill_payments.recorded_by_staff_id` |
| Wrote off bill | `bills.writeoff_by_staff_id` (+ reason) |
| Refund | `bill_refunds.created_by_staff_id` |
| Guest order decision | `guest_order_requests.decided_by_staff_id` |
| Purchase created | `purchases.created_by` |

The only real event log is `delivery_events` (actor type + id + note + time) — the shape this plan generalizes.

**Not recorded at all:** KOT status changes (`PosOrderServiceImpl.updateStatus` takes no actor — *who served*
is lost), KOT voids (`voidOrder` stores the reason, not the actor), every status history (each change
overwrites the last), waiter-call ack and guest-join (log lines only), menu/price/stock/settings/team/role
changes, purchase deletes (hard delete, no trace).

## Case studies (research, not templates)

| Product | What they do | What we take |
|---|---|---|
| **Petpooja** ([captain ordering](https://blog.petpooja.com/industry-business-guides/petpooja-captain-ordering-reduces-order-errors/), [KOT cancellation](https://blog.petpooja.com/glossary/kot-cancellation/)) | Every ticket modification logged with staff name + time; KOT cancel always carries a reason + approving staff. A **"leakage panel"** surfaces signals: KOTs cancelled after reaching the kitchen, KOTs modified after generation, KOTs never billed, bills modified or **reprinted after first print**. | Owners don't read raw logs — they read **exception views derived from the log**. Void-after-cooking and reprint-after-print are the two signals to design for. |
| **Toast** ([loss reports](https://support.toasttab.com/en/article/Exceptions-Report-Overview), [voided items](https://support.toasttab.com/en/article/Managing-Voided-Items-and)) | Per-topic loss reports (voids, removed-before-fire items, discounts, no-sale drawer opens, refunds, voided payments), each filterable by employee, most showing **actor and approving manager**. Per a [Toast community answer](https://community.toasttab.com/t5/back-office-team/login-report/m-p/13464) there is **no single report of everything one employee did**. | (a) A unified per-staff feed is a genuine differentiator. (b) "Removed before firing" ≠ "voided after firing". (c) Actor vs approver is a real distinction — reserve for later (manager-override is out of scope per RBAC). |
| **Square** ([manage checks](https://squareup.com/help/us/en/article/8166-comp-void-and-reassign-checks-with-square-for-restaurants), [community](https://community.squareup.com/t5/Square-for-Retail/audit-trail-for-any-changes-made-by-internal-users/m-p/662004)) | Dashboard "Activity Log" of sensitive actions: refunds, inventory updates, comps/voids, tip-setting and discount changes. Merchants still ask for a **check-level** trail. | Settings and inventory changes belong in the same log. The per-check timeline is the most-asked view. |
| **WorkOS / GitHub audit logs** ([WorkOS docs](https://workos.com/docs/audit-logs)) | Event = `actor{type,id,name}` + `action` (dot-notation `resource.verb`) + targets + context (IP, user agent) + time + typed metadata; actions **declared up front** in a schema. | Code-declared action catalog, dot-notation names, snapshot actor name, context columns. |
| **India — MCA audit-trail rule** *(background only — Decision 3: not a product goal)* ([ICAI journal](https://cajournal.icai.org/article-details/audit-trail-requirements-responsibilities), [explainer](https://www.india-briefing.com/news/india-mandates-audit-trail-compliance-for-all-companies-explainer-key-obligations-34837.html/)) | Rule 3(1), Companies (Accounts) Rules 2014 (from 1 Apr 2023): accounting software used for books of account must keep an **edit log of every change**, that **cannot be disabled**, retained **8 years**. | Log is always-on (no feature flag), never deleted in v1. **Whether a POS counts as "accounting software" is a CA question — do not market "MCA-compliant" until confirmed** (Open Q5). |

## Gaps beyond the three questions (things the requirement didn't name)

1. **Shared devices make the log confidently wrong.** If waiters share one tablet logged in as the captain, every serve/void is attributed to the captain. The log is only as true as the identity on the device. (PIN login already exists — a PIN quick-switch on the POS is the real fix; Open Q1.)
2. **Void after cooking vs before** — `voidOrder` allows voiding a `READY` KOT. Food cooked then voided is the #1 leakage signal; the event must carry `fromStatus`.
3. **Settlement force-serves KOTs on write-off only.** `writeOffCheck` force-marks live KOTs `SERVED`; `recordPayment` has a guard ("All items must be served before settling the bill") so its force-serve block is unreachable today (found during the Phase 1 build — do NOT remove that guard; it is a billing rule). Force-served KOTs must never be logged as "served by the cashier", or the per-waiter serve report lies.
   *Build note:* `bill.refunded` is in the catalog but not emitted — `BillRefund` is schema-only (no refund writer/endpoint exists). Wire it in the change that introduces the real refund flow.
4. **Bill print / reprint is invisible** — printing is `window.print()` in `Ninjasu_Web/.../receiptPrint.ts`; the backend never learns a bill was printed, let alone reprinted after payment.
5. **Hard deletes erase evidence** — `PurchasingServiceImpl.deletePurchase` deletes the purchase + lines; material merge hard-deletes the loser. The audit row must snapshot what was deleted.
6. **Price/discount/availability edits** — KOTs snapshot price so bills stay correct, but "manager dropped the price for one order and restored it" is invisible.
7. **Privilege changes** — invites, removals, role assignment, role-permission edits (RBAC). "Who gave Ravi settle-bill permission?" is the first question any auditor asks.
8. **Removed staff lose their name** — revocation deletes the `user_shops` row (ADR-0005); a join-based log shows "Unknown" on the void that got them fired.
9. **Platform-admin actions on a shop** (RBAC keeps a platform-ADMIN bypass on menu/stock/purchasing) — the owner should see "Ninjasu Support changed your menu". Trust feature.
10. **Guest and system actors** — guest QR sessions and schedulers (e.g. `TableCheckGhostReleaser`) change state too.
11. **Shop settings** — POS/guest-ordering toggles, payment types, tax classes, GSTIN/FSSAI, tables/QR regeneration, dispatch mode.
12. **Customer PII in the log** — `table_checks.customer_mobile`, supplier phones. An append-only log that holds PII collides with erasure requests (DPDP Act); keep PII out entirely.

## Design

### Two layers — keep both

- **State columns** (`opened_by_staff_id` etc.) stay. They answer "who closed this check" without a join and are already written.
- **Audit events** (new) are the history: one append-only row per action. Never used to derive current state (DA check #1).

### Scope — SHOP-scoped log only (v1)

Every event belongs to exactly one shop (`shop_id NOT NULL`). This covers everything a shop's members,
guests and riders do **to that shop**, plus platform-admin actions **on that shop** (rendered "Ninjasu Support").
**Out of scope for v1:** platform-global mutations with no shop — cuisines, delivery-zone CRUD, platform user
admin (create/update/unlock/delete), guest-background-template CRUD, rider registration/affiliation. They get a
separate `platform_audit_events` table if/when needed (never a sentinel shop UUID in this one). Customer-personal
mutations (cart, wishlist, saved addresses, device tokens) are not shop decisions and are excluded on purpose.

### Table `audit_events`

```sql
CREATE TABLE public.audit_events (
  id            BIGINT GENERATED ALWAYS AS IDENTITY,
  occurred_at   BIGINT       NOT NULL,  -- epoch millis UTC, APPLICATION clock (matches orders/table_checks). Not causal across JVMs: read order is (occurred_at, id), never "insertion order"
  shop_id       UUID         NOT NULL,  -- tenant scope; no FK by design (FK-free convention); every read filters on it
  module        VARCHAR(30)  NOT NULL,  -- from the catalog, never free text
  action        VARCHAR(60)  NOT NULL,  -- dot-notation key from AuditAction, e.g. 'kot.voided'
  actor_type    VARCHAR(20)  NOT NULL,  -- STAFF | GUEST | CUSTOMER | RIDER | PLATFORM_ADMIN | SYSTEM
  actor_id      UUID,                   -- NULL iff actor_type = SYSTEM
  actor_name    VARCHAR(120),           -- SNAPSHOT at time of action (survives removal/rename)
  actor_roles   TEXT,                   -- SNAPSHOT of THIS SHOP's role names held by the actor at that moment (display only; NOT the global users.roles array)
  entity_type   VARCHAR(30)  NOT NULL,  -- KOT | CHECK | BILL | PURCHASE | ITEM | ROLE | MEMBER | TABLE | SHOP ...
  entity_id     UUID         NOT NULL,
  entity_label  VARCHAR(120),           -- SNAPSHOT: "KOT #42", "Table 5", "Paneer Tikka"
  root_type     VARCHAR(30)  NOT NULL,  -- aggregate root; = entity_* when the entity is its own root
  root_id       UUID         NOT NULL,  -- CHECK id for every KOT/bill/payment event → one-query table story
  reason        VARCHAR(255),           -- NULL = action type carries no reason
  amount        NUMERIC(12,2),          -- money involved (void value, bill total); NULL = not a money action
  changes       JSONB,                  -- {field:{from,to}} for updates; key-field snapshot for deletes. Allowlisted fields only
  metadata      JSONB,                  -- action-specific detail (fromStatus/toStatus, tenders, kotNumber)
  client        VARCHAR(20),            -- WEB | POS_APP | CUSTOMER_APP | GUEST_WEB | RIDER_APP | SYSTEM
  device_id     VARCHAR(64),            -- NULL until clients send X-Device-Id (Phase 4)
  ip            INET,
  request_id    VARCHAR(64),
  PRIMARY KEY (id, occurred_at),        -- Postgres requires the partition key in every unique key, so this keeps range partitioning possible later
  CONSTRAINT chk_audit_actor CHECK ((actor_type = 'SYSTEM') = (actor_id IS NULL))
);
CREATE INDEX idx_audit_shop_time   ON audit_events (shop_id, occurred_at DESC, id DESC);
CREATE INDEX idx_audit_shop_root   ON audit_events (shop_id, root_id, occurred_at);
CREATE INDEX idx_audit_shop_actor  ON audit_events (shop_id, actor_id, occurred_at DESC);
CREATE INDEX idx_audit_shop_module ON audit_events (shop_id, module, occurred_at DESC);
-- Append-only guard: blocks app bugs and casual edits (not a DBA — that's Open Q2, hash chain).
CREATE FUNCTION audit_events_immutable() RETURNS trigger LANGUAGE plpgsql AS
  $$ BEGIN RAISE EXCEPTION 'audit_events is append-only'; END $$;
CREATE TRIGGER trg_audit_immutable BEFORE UPDATE OR DELETE ON audit_events
  FOR EACH ROW EXECUTE FUNCTION audit_events_immutable();
CREATE TRIGGER trg_audit_no_truncate BEFORE TRUNCATE ON audit_events
  FOR EACH STATEMENT EXECUTE FUNCTION audit_events_immutable();
```

Hand-run SQL first (repo has no Flyway; `ddl-auto=update` must not create this table). `root_*` is always set,
so there is no NULL-means-self rule for readers to remember.

**JPA mapping (spec it, then prove it in a test — never a Spring context / DB):** the entity models the *real*
key with an `@IdClass(id, occurredAt)`; `id` is `@GeneratedValue(strategy = IDENTITY)`; `changes`/`metadata` use
Hibernate's JSON JDBC type (`@JdbcTypeCode(SqlTypes.JSON)`); `ip` is stored via an explicit `INET` mapping/converter
(a plain `String` binds as varchar and fails). Verified with the offline bare-Hibernate bootstrap pattern already used
by `RbacJpqlOfflineValidationTest`. The repository exposes **no update or delete method**.

**Partitioning (honest version):** the table is created unpartitioned. Later conversion = create a partitioned
parent, `ATTACH` the existing table as *one* historical partition (`FOR VALUES FROM (min) TO (cutover)`), then new
monthly partitions go forward — no row copy, but the old data stays in one big partition. That is fine at the
projected scale; do it when the table nears ~50M rows. The immutability triggers are re-created on each partition.

**Deletion policy:** no FK to `shops`, so a ops-side hard delete of a shop leaves its audit rows orphaned but
intact (the trigger only blocks row-level UPDATE/DELETE/TRUNCATE on the audit table itself). Ops keeps a
support-only lookup by `shop_id`. If a future `ON DELETE CASCADE` FK is ever added, the trigger will (correctly)
block shop deletion — do not add one.

### Action catalog — code-defined, like the RBAC permission catalog

One Java enum `AuditAction` is the single source. Each constant declares: `key` (`kot.voided`),
`module`, `entityType`, `label` ("Voided KOT"), `reasonRequired`, `sensitive` (feeds the leakage view),
and the RBAC `permission` it is performed under. Naming: `<entity>.<past-tense verb>` (WorkOS/GitHub style).

| Module | v1 actions |
|---|---|
**No wildcards — the enum is exact.** Below is the v1 inventory, derived from every mutating endpoint found in
the code review; Phase 1 turns each row into one constant. A row not listed is either out of scope (see Scope) or a
gap to add — never silently absent.

| Module | Exact v1 actions |
|---|---|
| `FLOOR` | `check.opened`, `check.guest_join_enabled`, `check.guest_table_approved`, `check.guest_table_rejected`, `check.attention_acknowledged`, `kot.fired`, `kot.served`, `kot.voided` (metadata: `fromStatus`) |
| `TAKEAWAY` | `takeaway.fired`, `takeaway.collected`, `takeaway.voided` |
| `BILLING` | `bill.settled` (tenders + force-served KOT ids in metadata), `bill.written_off`, `bill.writeoff_settled`, `bill.refunded`, `bill.printed`, `bill.reprinted` (P4) |
| `MENU` | `item.created`, `item.updated`, `item.deleted`, `item.availability_changed`, `item.price_changed` (split from update — the leakage signal), `item.moved_category`, `item.tax_class_bulk_assigned` (aggregate: category + row count), `category.created/updated/deleted` (each an exact constant), `addon_group.created/updated/deleted`, `addon_group.linked`, `addon_group.unlinked`, `addon.created/updated/deleted` |
| `STOCK` | `stock.set`, `stock.restocked` (explicit before/after read under the same lock) |
| `PURCHASING` | `purchase.created`, `purchase.deleted` (full snapshot), `material.created`, `material.updated`, `material.merged` (aggregate: loser, winner, lines repointed), `supplier.created`, `unit.created` |
| `TEAM` | `member.invited`, `invite.cancelled`, `invite.accepted` (login path — creates the membership), `member.removed`, `member.roles_changed`, `role.created`, `role.updated` (permission diff), `role.deleted` |
| `SETTINGS` | `table.created`, `table.updated`, `table.deactivated`, `table.qr_regenerated`, `pos.toggled`, `guest_ordering.toggled`, `payment_type.created/updated/deactivated`, `shop.profile_updated` (GSTIN/FSSAI diffs), `shop.delivery_config_updated`, `shop.activated`, `shop.deactivated`, `shop.deleted` (soft), `shop.background_template_set` |
| `ONLINE_ORDERS` | `order.accepted`, `order.declined`, `delivery.assigned`, `delivery.reassigned`, `delivery.cancelled`, `delivery.force_completed`, `cash_discrepancy.reconciled` |

**Guests (Decision 8):** no dedicated guest actions. `check.opened` and `kot.fired` are the only events a guest can cause; they are recorded with `actor_type=GUEST` (session id, name "Guest") so the table's story never shows items with no source. Guest attention requests, session expiry and seating hand-shakes are not logged; staff *approving* a guest table (`check.guest_table_approved/rejected`) is.

**Deliberately not logged:** guest attention/session lifecycle, GPS pings, login/OTP success, kitchen bumps (Decision 4 — see the open
Codex finding), order-driven stock counters (`atomicDecrement`/`creditSoldQty`/scheduler `period_closed`), rider
online/offline, customer cart/wishlist/address/device changes, online-order customer placement/payment webhooks
(payment state already has its own durable records: `payment_webhook_events`, `bills`, `bill_refunds`).

**Delivery — not a single-writer.** `DeliveryServiceImpl.transitionTo()` (l.270) is the only place *status* changes,
but it is **not** the only delivery write: initial assignment, the *new* delivery in a reassignment, and cash
reconciliation (`DeliveryCashCollection`, no event today) bypass it. Fix in P3: one `DeliveryAuditFacade` called by
`transitionTo`, assignment, reassignment and reconciliation, so every staff delivery action emits both a
`delivery_events` row and an `audit_events` row. `delivery_events` stays as the rider/GPS timeline; no migration.

### Write path

- **`AuditRecorder`** (platform service, not a domain service): `record(AuditEvent)` where `AuditEvent` is a small value object — ids, labels, amount, reason and allowlisted maps. **Never a domain entity** (that would make the recorder import Order/Bill/Item/Delivery/Role… and break the coupling guard). Insert-only.
- **Recorded from the SERVICE layer (Decision 9).** Services call the recorder directly — no controller-built actor object. Every mutating service method already receives `callerId`/`staffId` and `shopId` (they need them for `verifyRole`), so the call is `auditRecorder.record(shopId, callerId, AuditAction.X, entity…)`; the recorder looks up the actor's display name and **this shop's** role names itself. Only `updateStatus` and `voidOrder` lack a caller param today — both gain one (the controller already has `user`). Two other entry points: `recordSystem(shopId, "<jobName>", …)` for scheduled jobs/listeners (named, never "unknown"), and `recordGuest(shopId, sessionId, …)` used solely by the guest `check.opened`/`kot.fired` paths. **The actor is never read from a request body and never from the ambient SecurityContext** (the executors in `AsyncConfig` don't propagate it, jobs have none, AFTER_COMMIT listeners open new transactions).
- **Roles come from the membership resolver, not the JWT.** `actor_roles` = the actor's role names *in that shop*, resolved via the same `(userId, shopId)` membership lookup `verifyRole` uses (RBAC: `user_shop_roles`). The global `users.roles` array (SHOP/ADMIN/…) is a different concept and must not be stored here (a Cashier in shop A / Manager in shop B, or a platform ADMIN vs the per-shop "Admin" role). A platform-ADMIN acting on a shop without membership is recorded as `PLATFORM_ADMIN` ("Ninjasu Support").
- **Transaction policy is per action class — not one universal rule.**
  - *Staff-initiated synchronous actions* (void, settle, write-off, refund, menu/price/stock/team/settings): **same transaction, fail-closed** — an unlogged void is exactly what a thief benefits from.
  - *Compare-and-set (CAS) writes that must survive failure* (payment refund scheduling in `PaymentServiceImpl` uses REQUIRES_NEW and swallows errors; the hourly sweep only finds `REFUND_PENDING`): audit **only when the CAS returns 1**, inside the same transaction as the CAS — never wrap a recovery-critical write in something that can roll it back for an audit failure. These are out of v1 scope anyway (payment webhooks/refund state have their own durable records).
  - *Counters that intentionally outlive a thrown exception* (OTP/PIN failure counts, `noRollbackFor`): not logged in v1; if denied-attempt logging is ever wanted it goes in its own `REQUIRES_NEW`.
  - *Async/listener paths* (delivery-cancel cascade, dispatch): audit with an explicit `SYSTEM(<listener>)` actor inside the listener's own transaction.
- **Before-state:** `changes` is only promised where the service already loads the entity. Bulk `@Modifying` operations get **aggregate events** (`item.tax_class_bulk_assigned` = category + new class + row count; `material.merged` = winner/loser/lines repointed), and `stock.restocked` does an explicit read under the lock. Audit fires only when the update actually changed rows.
- **Idempotent replays** (e.g. `fireKot` with an idempotency key) must short-circuit *before* `record()` so a retry doesn't log twice.
- **Diffs / free text:** `changes`, `metadata`, `reason` and `entity_label` all pass the per-action allowlist/redaction — no customer or supplier contact fields, no secrets, no S3 keys. `reason` is length-capped and the UI warns "don't enter customer phone numbers".
- **Personal data, acknowledged:** `actor_name`, `actor_id` and `ip` are staff personal data, retained indefinitely (Decision 7). Access is `audit.view` only; list DTOs omit `ip`/`request_id`/raw `metadata` (owner-only export). An anonymize-on-request path is a P5 item, not a v1 promise.

### How every future module inherits it (the "global" part)

The unit of enforcement is the **endpoint** (the human-decision surface), not a `@Transactional` bytecode pattern —
the code review showed the latter is both leaky (programmatic `TransactionTemplate` writes, listeners, jobs, and
mutating methods with no annotation are invisible to it) and noisy (default-write `@Transactional` on plain reads,
`MANDATORY` helpers double-counted).

1. **Endpoint declaration rule** (reflection/ArchUnit test — no Spring context, no DB): every controller method mapped `POST/PUT/PATCH/DELETE` must carry `@AuditedEndpoint(AuditAction.X, …)` **or** `@NotAudited("reason")` (customer cart, login, etc.). The annotation is a *declaration only* — the actual `record(...)` call lives in the service (Decision 9). A new mutating endpoint without either fails the build. This is the check that makes "every new module inherits it" real.
2. **Ratchet:** the rule starts with an allowlist of today's un-annotated endpoints; it can only shrink; a *new* endpoint not in the allowlist and not annotated fails. When empty (end of P3) the allowlist is deleted.
3. **Behaviour tests, not just structure:** for each `AuditAction` one Mockito-level test (recorder mocked, repositories mocked — no DB) asserts the service emits it with the right actor/entity/root. Plus a test that every `AuditAction` is referenced by ≥1 `@AuditedEndpoint` (no dead catalog entries).
4. **Catalog endpoint** (`GET .../audit-events/catalog`): web filter dropdowns come from the backend, never hardcoded (principle 14, type drift).
5. **RBAC linkage (explicit, not a lockstep test):** `audit.view` is added to the RBAC spec/seed by hand — LEGACY set unchanged, the DEFAULT Admin template gains it (Admin-only — Samivan 2026-09-29), and the RBAC backfill runner grants it to existing seeded roles of those templates. (RBAC backfills only matching seeded templates, never custom roles — owners of custom roles grant it themselves.) A "every write permission must have an audit action" test was rejected: broad keys (`menu.manage`) pass with one reference while other mutations go unaudited, and deliberately-unlogged permissions (`kds.update_status`) would fail it.
6. **Principle #21 (proposed)** in `principles-part3`: *"Every human decision that changes a shop's money, stock, access, menu/price or a customer-visible outcome is recorded as an audit event, with the actor supplied explicitly by the caller (never read from a request body). Synchronous staff actions record in the same transaction; recovery-critical and async writes follow the per-action-class policy in `audit-log-plan.md`. [BACKEND][SHARED]"*
7. **`workflow.md` pre-code checklist** (added in Phase 1, when the recorder exists): "New mutating endpoint? → `AuditAction` constant + `@AuditedEndpoint` + catalog row."

### Read path

- `GET /api/shops/{shopId}/audit-events?from&to&module&action&actorId&entityType&rootId&cursor&size` (`module`/`action` repeat for multi-select — plain names, because Tomcat rejects unencoded `[]` in query strings; omitting a filter means no restriction, so rows with a since-renamed module/action still appear)
  - `from`/`to` are **UTC instants**, required, span ≤ 92 days; `size` ≤ 100. Shops have **no timezone field today** (`BusinessDayResolver` falls back to a single zone, several flows hardcode Asia/Kolkata), so v1 is explicitly India-only: the web builds "Today/Yesterday" in `Asia/Kolkata` and the response echoes the zone used. Shop-local days wait for the shop-timezone work.
  - **Keyset pagination** on the exact lexicographic predicate `(occurred_at, id) < (:lastOccurredAt, :lastId)` — the next page starts after the last row seen rather than skipping N rows, so new events landing on top don't duplicate/skip. Order is `(occurred_at, id)`, not causal insertion order: with clock skew across JVMs a late event can land behind an already-consumed cursor (acceptable for a log; documented).
  - Response is a purpose-built DTO inside the standard `ApiResponse<T>` envelope (never an entity/pageable); list DTO omits `ip`, `request_id`, `device_id` and raw `metadata`.
- `GET .../checks/{checkId}/activity` = the same query with `rootId` — the table story.
- `GET .../audit-events/catalog` — modules, actions, labels.
- New RBAC permission **`audit.view`**: owner implicit; seeded into the Admin template ONLY (decision 2026-09-29: Admin-only — Manager and Accountant do not get it).

### UI (Ninjasu_Web; RN app unchanged — write side needs no RN change)

- **Reports → Activity** page: date presets (Today / Yesterday / 7 days / custom), Module multi-select, Event multi-select grouped by module, Staff select, search by table/bill/KOT number. Row = time · actor (+ role) · sentence ("Asha voided KOT #42 · Table 5 · ₹640 · reason: customer left") · link. Expand → field diff. Deleted entities render as text, not links.
- **Check detail → Activity tab** (the per-table story) and staff names instead of raw UUIDs on check detail + history.
- **Staff & Roles → member → "View activity"** (pre-filtered).
- **Leakage view** (P4): voids by staff (count + value), voids after cooking, write-offs, reprints after settlement, price changes, purchase deletes — aggregates over `audit_events`.

### Rejected alternatives

| Option | Why not |
|---|---|
| Hibernate Envers / entity listeners (automatic row-change capture) | Bulk `@Modifying` updates bypass them — `ItemStockLedgerRepository` alone has 6 (`atomicDecrement`, `restock`, `creditSoldQty`, `closeOpenPeriod`…). The log would look complete and silently miss stock changes. Also records *column changes*, not *intent* ("voided" vs "status=CANCELLED"). |
| AOP `@Audited` interceptor that records generically | Can't compute before/after, labels or `fromStatus`; Spring proxies skip self-invocation (internal calls unaudited); fires on method success even when nothing changed. |
| DB triggers | No business intent; actor needs `SET LOCAL` per transaction (fragile with pooling); logic hidden from Java devs. (The immutability trigger above is a guard, not capture.) |
| `@TransactionalEventListener(AFTER_COMMIT)` / async writer | A crash between commit and write loses the event — for voids that is the whole point of the log. |
| One table per module | Filter-by-module across modules becomes a UNION of N tables; every module reinvents the shape. |

## Devil's-advocate findings

| # | Proposal | Failure scenario | Mitigation | Verdict |
|---|---|---|---|---|
| 1 | One cross-module table | Generic columns tempt JSONB for everything → unfilterable | Every filtered dimension is a real column; JSONB only for detail never filtered | proceed with conditions |
| 2 | Automatic capture (Envers) | Bulk ledger updates silently missing | Explicit recorder (above) | rejected |
| 3 | Async/after-commit write | Crash → unlogged void | Same tx for staff actions; per-action-class policy for recovery-critical/async paths | proceed with conditions |
| 4 | Actor threaded as a param | Forgotten — exactly today's `updateStatus`/`voidOrder` gap | Services already take `callerId`/`shopId`; add the missing param to those two methods; `@AuditedEndpoint` + behaviour tests make forgetting a build failure. NOT ambient SecurityContext (async/scheduled/listener paths have none) | proceed with conditions |
| 5 | Actor name via join | Removed staff (row deleted, ADR-0005) show "Unknown" | Snapshot `actor_name` + `actor_roles` | proceed with conditions |
| 6 | Trust the logged-in identity | Shared terminal → one login credited with everything | Own-login is the norm (Decision 1); record `client`/`device_id`; optional "acting as" step built only on client request | proceed (decided) |
| 7 | `recordPayment` force-serve | Cashier credited with serving N KOTs | `kot.served` only from `updateStatus`; force-served ids go in `bill.settled` metadata | proceed with conditions |
| 8 | Hard deletes | Log links to a vanished row; nothing says what was deleted | Delete events snapshot key fields + amount; UI renders as text | proceed with conditions |
| 9 | Offset pagination | New events shift pages → dupes/skips (same trap as POS history) | Keyset on `(occurred_at, id)` | proceed with conditions |
| 10 | Scale at 10× | Est. busy shop 3–5k events/day ≈ 1–2M/yr (assumption, unmeasured); 100 shops ≈ 100–200M/yr | Max 4 indexes, none on JSONB; mandatory date bound; `occurred_at` in the PK so range partitioning stays possible (attach existing table as one historical partition, monthly ones going forward); partition when > ~50M rows | proceed with conditions |
| 11 | PII in diffs | Manager sees customer phones via the log; erasure vs append-only | Per-action field allowlist; never log customer/supplier contact fields | proceed with conditions |
| 12 | `module` stored + derivable from `action` (check #1) | Drift if written by hand | Both written from the same enum constant; no free-text path | proceed |
| 13 | Two logs for delivery (`delivery_events` + audit) | Divergence — and `transitionTo()` is NOT the only delivery writer (assignment, reassignment's new delivery, cash reconciliation bypass it) | One `DeliveryAuditFacade` called by all four paths | proceed with conditions |
| 14 | Build now on main | RBAC (`feature/rbac-phase1`) rewrites every gate line in the same service methods; other session's payment-types/tax work touches `TableCheckServiceImpl`/`BillServiceImpl` | Build on top of merged RBAC; `audit.view` goes into the RBAC catalog | proceed with conditions |
| 15 | Idempotent retry | `fireKot` replay logs twice | Short-circuit before `record()` | proceed with conditions |

## Independent review (Codex, read-only, 2026-09-27) — dispositions

Codex reviewed v1 of this plan against the code: **16 findings, verdict "redesign"**. I re-checked the load-bearing
ones against the code before accepting (`transitionTo` not sole writer; no security-context propagation in
`AsyncConfig`; role resolution is per-`(userId, shopId)`). All 16 are folded in above; nothing was rejected.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | HIGH | `shop_id NOT NULL` can't hold platform-global actions | Scope section: shop-scoped only; separate platform table later; no sentinel UUID |
| 2 | HIGH | Roles can't come from the JWT principal | `actor_roles` from the membership resolver by `(userId, shopId)`; column → TEXT |
| 3 | HIGH | Guest/async/scheduled/listener actors misattributed | Service-layer `record(shopId, callerId, …)` (Decision 9); `recordSystem(<jobName>)`; `recordGuest` only for the two guest events (Decision 8) |
| 4 | HIGH | ArchUnit ratchet leaky (TransactionTemplate, listeners, no-annotation methods) and noisy (default-write reads) | Enforcement moved to controller endpoints (`@AuditedEndpoint`/`@NotAudited`) + behaviour tests |
| 5 | HIGH | Catalog omitted many decisions; wildcards not real constants | Exact inventory table; out-of-scope list explicit |
| 6 | HIGH | Universal fail-closed unsafe for refund-pending/webhook/lockout paths | Per-action-class transaction policy; Principle #21 reworded |
| 7 | HIGH | `transitionTo()` is not the sole delivery writer | Claim corrected; `DeliveryAuditFacade` |
| 8 | HIGH | Skipping kitchen events leaves a chef's "what did I do today" empty | **OPEN — Samivan's call** (Decision 4 stands until he answers; see below) |
| 9 | MED | "Server clock"/ATTACH-in-place claims wrong | Application clock documented; honest partition-conversion paragraph |
| 10 | MED | Trigger vs shop hard-delete unresolved | No shop FK by design; support-only lookup; never add cascade FK |
| 11 | MED | JPA/INET/JSONB/composite-key mapping unspecified | Mapping spec + offline bootstrap test |
| 12 | MED | Bulk queries lack before-state | Aggregate events; fire only when rows changed |
| 13 | MED | RBAC lockstep test conflicts with RBAC spec | Dropped; `audit.view` added to RBAC seed explicitly |
| 14 | MED | "No PII" contradicts stored actor/ip/free text | PII acknowledged; free-text redaction; DTO omissions |
| 15 | MED | No shop timezone exists | v1 India-only, UTC instants in API |
| 16 | LOW | Recorder taking entities couples domains; DTO/envelope rules | Value-object signature; `ApiResponse` + purpose-built DTOs |

## Security review — `GET /api/shops/{shopId}/audit-events`

```
Auth required:       Pass (JWT)
Ownership verified:  Required — caller is a member of shopId holding audit.view (owner implicit); platform ADMIN only via the existing bypass, and that read is itself not exposed to other shops
Input validation:    Required — from/to present, span ≤ 92d, size ≤ 100, module/action validated against the catalog enum, cursor opaque + tamper-checked (shopId bound)
Rate limited:        List: no (bounded by date span + size). CSV export (P4): yes, per user
Response minimal:    No ip/user_agent/request_id in the list DTO (owner-only export); no customer PII anywhere (finding 11)
Specific risks:      Cross-shop cursor replay (cursor must embed + verify shopId); log visible to a Manager includes cash-handling of peers (intended — owner decides via role)
```

## Phases

| Phase | Scope | Answers |
|---|---|---|
| **P0 Decide** | Open questions below; ADR-0021 (audit architecture); principle #21; this doc → decided | — |
| **P1 Platform + POS** (backend) | SQL + entity + `AuditRecorder` + `ActorContext` + `AuditAction` catalog + ArchUnit ratchet + RBAC-lockstep test; instrument checks, KOTs (incl. actor on `updateStatus`/`voidOrder`), bills, payments, write-off, refund, guest approvals, attention ack, tables; list + timeline + catalog endpoints; `audit.view` | All 3 client questions, via API |
| **P2 Web** | Activity page, check Activity tab, staff names on check/history, member → activity link | Client can self-serve |
| **P3 All modules** | Menu (price/availability split out), stock, purchasing (delete snapshot, merge), team/roles, settings, delivery staff ops via `DeliveryAuditFacade`. Endpoint allowlist → empty → hard fail | "Audit log for everything" |
| **P4 Leakage + export** | Leakage view, CSV export, `bill.printed/reprinted` (web + RN call a print-event endpoint), `X-Device-Id` header | Petpooja-parity loss control |
| **P5 On demand** | "Acting as" attribution on shared terminals, hash-chain tamper evidence, denied-attempt logging (REQUIRES_NEW), monthly partitioning/archival, kitchen-transition logging | Only when a client asks |

Sequencing: P1 starts only after RBAC merges; migration SQL runs before the backend deploy (Samivan runs it, never an agent); never run `contextLoads`-style tests (hit prod Neon).

## Decisions (Samivan, 2026-09-27)

1. **Shared devices — every staff member has their own login.** A shared "cashier/admin" terminal is possible; if a client asks, we add an optional "acting as <name>" attribution step on that terminal. **Not built until a client asks.** Until then `client`/`device_id` are recorded so a later switch can be back-interpreted, and the doc states the limitation: the log is exactly as truthful as the login on the device.
2. **Logs cannot be edited or deleted** — app-level (no update/delete path) plus the DB immutability triggers. No hash chain in v1.
3. **No MCA/compliance positioning.** The MCA row in the case-study table is background only; nothing in the product or sales claims compliance.
4. **Kitchen transitions (`PREPARING`/`READY`) are NOT logged — FINAL (Samivan, 2026-09-27: "no need").** Codex flagged that a chef's per-staff feed is therefore empty; accepted. Revisit only if a client asks for ticket-time analytics or chef activity. Original reasoning follows. The signals that matter are preserved elsewhere: `kot.served` (who served), and `kot.voided` carries `fromStatus` in `metadata`, so "voided after the kitchen marked it ready" stays queryable. Codex finding #8: with this exclusion a chef's per-staff feed is empty for their whole shift, which contradicts client question 3. Volume argument is weaker than first assumed (2 rows per KOT ≈ 1k rows/day for a 500-KOT shop). Recommended alternative: log them (`kot.preparing`, `kot.ready`), hide by default in the Activity page behind a "Show kitchen activity" toggle.
5. **Record only where it makes sense** — the bar is: *a human decision that changes money, stock, access, menu/price, or a customer-visible outcome.* Not logged: reads, polling, GPS pings, cart edits before checkout, stock-ledger counters moved by orders (`atomicDecrement`/`creditSoldQty` — those are consequences of a logged order, not decisions), kitchen bumps, login/OTP.
6. **Who sees it** — `audit.view` for the Owner (implicit) and the Admin template ONLY (revised 2026-09-29 from Admin/Manager/Accountant). Platform ADMIN keeps its support-read bypass.
7. **Retention** — never deleted in v1.
8. **Guests are (almost) not logged** — only `check.opened` and `kot.fired`, with a GUEST actor, so a table's story has no unsourced items. No other guest events.
9. **Recording is called from the service layer** with the `callerId`/`shopId` services already hold; the recorder resolves name + shop roles. No controller-built actor object.

**Speed / indexing (Samivan asked about a year column):** no year column. The `(shop_id, occurred_at DESC, id DESC)` index already turns "shop X, date range" into one contiguous index range scan — a year column adds a write and a second index without narrowing anything the timestamp doesn't. The real scaling lever is **monthly range partitioning** on `occurred_at` (already reserved via the PK), which gives the same "skip old years entirely" effect. Add `shop_id` as the leading key on every index (done). Every read requires a date bound (done).

## Related

- `02-Domain/roles-permissions.md` — permission catalog this mirrors; `audit.view` lands there
- `02-Domain/captain-ordering.md` D3 ("audit trail = the list of KOTs" — superseded by this once built)
- `06-Rider-App/implementation-roadmap.md` Phase 4b — `delivery_events`, the precedent
- `07-Roadmap/vision-inventory-module.md` — purchasing/To-Buy actions join the catalog when built
- `01-Architecture/decisions/ADR-0005` — revocation = row delete (why names are snapshotted)
