# Codex schema review: 2b.13 commission rate cards (2026-10-21)

Read-only Codex run (codex-cli 0.155.1) on the working tree of backend `feature/schedule-2b13` (head f65ecfd plus uncommitted geld changes) and the plan's Data model review. Not blind: it was given the owner decisions D1-D4 and the proposed renames. Claude verified each High claim (table at the end).

---

FILES I READ:
`Ninjasu_Documentation/07-Roadmap/commission-rate-cards-plan.md` (whole file, including Data model review); backend `AGENTS.md`; the five requested `db_manual/` SQL files; HEAD versions of the four changed SQL files; the requested entities, `OrderInvoiceSnapshot`, `OrderAssembler`, and `ScheduleSchemaGuard`; `OrderServiceImpl`, `PaymentServiceImpl`, `OrderInvoiceFactsRepository`, and `Delivery`. Git status and diffs were read. No files were changed and no database, network, or build command was run.

Paths below are relative to `ninja delivery service java/`, except `plan:`.

## Q1 — SQL correctness

- **High — `db_manual/commission-rate-card-migration.sql:53-59,165-188`:** The currency CHECK has an unterminated string and its following `IF` is missing; a second copy of the file starts after `COMMIT` with a stray `);`. The file cannot run. Restore the CHECK and one complete copy of the migration.
- **High — `db_manual/platform-seller-profile-migration.sql:51-58`:** `DO $ ... END $;` is invalid PostgreSQL dollar quoting. Use `DO $$ ... END $$;`.
- **Medium — `db_manual/commission-rate-card-migration.sql:17-28,132-162`:** Rerun logic adds `currency_code` to an older table, but `CREATE TABLE IF NOT EXISTS` and `ON CONFLICT (id) DO NOTHING` do not repair a missing seeded slab or verify that fixed IDs still hold the intended rows. Check the seeded version/slabs explicitly before treating reruns as safe.
- **Low — `db_manual/order-commission-snapshot-migration.sql:50-55`:** `VALIDATE` is rerunnable, but a failed validation leaves a `NOT VALID` constraint and the transaction containing the column additions already committed. Verify `convalidated` before deploy; retry validation after resolving its cause.
- **Low — `db_manual/commission-rate-card-assignment-migration.sql:2`, `db_manual/order-invoice-snapshot-migration.sql:4-6`, `db_manual/platform-seller-profile-migration.sql:2`:** Required order is rate card → assignment and commission snapshot (either order) → invoice side table → platform profile. The latter file needs the side table; no other forward reference appears once the two syntax defects are fixed.

## Q2 — Entity, SQL, and guard agreement

- **High — `db_manual/commission-rate-card-migration.sql:107-120`; `src/main/java/com/example/ninja/entity/CommissionRateCard.java:35-37`:** The entity treats currency as immutable, but the card trigger permits `currency_code` changes. That relabels every historical slab and pinned order. Add a null-safe currency equality check to the trigger.
- **Medium — `src/main/java/com/example/ninja/config/ScheduleSchemaGuard.java:65-110,138-145`:** The guard checks selected object *names and existence*, not every mapped column, type, nullability, constraint definition, or `NOT VALID` state. It also omits side-table columns and the currency column; a Hibernate-created or wrong-shaped table can pass. Add catalog checks for critical definitions and validation state.
- **Medium — `db_manual/order-commission-snapshot-migration.sql:13-35`; `src/main/java/com/example/ninja/entity/Order.java:112-116`; `src/main/java/com/example/ninja/entity/OrderLine.java:55-59`:** Mapped names, numeric precision, and nullable snapshots agree, but `updatable=false` is only ORM behavior; SQL has no immutability trigger for order or line commission. Enforce snapshot immutability in the database if direct writes are in scope.
- **Low — `db_manual/order-invoice-snapshot-migration.sql:17-57`; `src/main/java/com/example/ninja/entity/OrderInvoiceFacts.java:15-73`; `db_manual/platform-seller-profile-migration.sql:14-48`; `src/main/java/com/example/ninja/entity/PlatformSellerProfile.java:15-59`:** Apart from the broken platform `DO`, the mapped side-table and profile column names, lengths, nullability, FK targets, checks, and trigger names agree with their SQL. The side-table PK supplies one row per order.

## Q3 — Naming

- **Low — `src/main/java/com/example/ninja/entity/OrderInvoiceFacts.java:9-15`; `db_manual/order-invoice-snapshot-migration.sql:1-2`:** `order_seller_snapshot` is clearer than `order_invoice_facts`: it records seller and jurisdiction facts before an invoice exists. Rename its entity, repository, SQL filename, constraints, triggers, comments, and guard entries together.
- **Low — `db_manual/order-invoice-snapshot-migration.sql:28`; `src/main/java/com/example/ninja/entity/OrderInvoiceFacts.java:58-60`:** `platform_seller_profile_id` correctly names the referenced table. **Low — `db_manual/order-commission-snapshot-migration.sql:13,26-29`:** `commission_rate_card_version_id` likewise identifies the referenced entity; rename its FK and guard entry with it.
- **Low — `db_manual/commission-rate-card-assignment-migration.sql:18,41-44,60-64`:** `card_version_id` and `fk_commission_assignment_version` abbreviate the same rate-card concept differently from the proposed order rename. Prefer `commission_rate_card_version_id` and `fk_commission_rate_card_assignment_version`; expand the `chk_`, `ux_`, and `idx_commission_assignment_*` names to the full table stem for consistent catalog searches.
- **Low — `db_manual/order-invoice-snapshot-migration.sql:23-27`:** `restaurant_*` will misdescribe grocery or product shop facts, since checkout accepts all cart types (`src/main/java/com/example/ninja/service/impl/OrderAssembler.java:94,166-169`). If the side row covers every customer order as planned, use `shop_seller_*` for the seller fields before rollout.

## Q4 — Columns on `orders`

- **Medium — `src/main/java/com/example/ninja/entity/Order.java:117`; `plan:303-307`:** The former seller/GSTIN/address/profile columns are correctly removed from the entity and belong in the 2b.13 side table. If the earlier SQL ran, drop those physical `orders` columns in a later contract migration after confirming no reader uses them.
- **Medium — `src/main/java/com/example/ninja/entity/Order.java:155-179`:** `razorpay_order_id`, `razorpay_payment_id`, `refund_id`, `paid_on`, and `refunded_on` describe payment and refund transactions. Move them to payment/refund records when multiple attempts or partial refunds arrive in 2c; retain a compact order payment status for operational reads.
- **Low — `src/main/java/com/example/ninja/entity/Order.java:119-147`; `src/main/java/com/example/ninja/entity/Delivery.java:44-60`:** Destination coordinates/address/label and delivery OTP/attempts are delivery-specific. Move the destination snapshot and verification state to an order-delivery record at the next delivery-schema redesign; account for multiple delivery attempts. Core identity, status, totals, `shop_name`, commission pin/total, and POS/KOT identifiers still fit their order grain (`Order.java:44-115`).

## Q5 — Existing review

- **High — `plan:286-322`; `db_manual/commission-rate-card-migration.sql:53-59,165-188`; `db_manual/platform-seller-profile-migration.sql:51-58`:** It missed both current migration blockers. The reviewed design cannot be deployed until the working-tree SQL parses.
- **High — `plan:262-270,334`; `db_manual/commission-rate-card-migration.sql:117-120`:** Calling card/version snapshots immutable misses the mutable card currency. Fix the trigger before relying on historical monetary meaning.
- **Medium — `plan:318-321`; `db_manual/order-commission-snapshot-migration.sql:50-55`:** MIG-1’s lock fix is present, but the review did not require proof that the deferred constraints were validated. The guard’s existence check (`ScheduleSchemaGuard.java:138-145`) is insufficient evidence.
- **Low — `plan:303-312,367-369`; `db_manual/order-invoice-snapshot-migration.sql:17-33`:** PLACE-1 has been implemented, while PLACE-2’s state-based design was explicitly superseded by owner decision D2. Treat the second registration as the stated revisit trigger, not a current disagreement. D4’s environment items remain pre-launch work (`plan:288-302`).

## Q6 — Side-table write path

- **Medium — `src/main/java/com/example/ninja/service/impl/OrderAssembler.java:166-175`; `OrderServiceImpl.java:68-90`; `PaymentServiceImpl.java:145-161`:** Both current callers save the order and row in one transaction, so a thrown save rolls both back. The separate `saveInvoiceFacts` call is easy for a future Schedule caller to omit; make creation an order persistence invariant or require a shared checkout method that saves both.
- **Medium — `src/main/java/com/example/ninja/service/impl/OrderInvoiceSnapshot.java:57-60`; `src/main/java/com/example/ninja/repository/OrderInvoiceFactsRepository.java:8`; `db_manual/order-invoice-snapshot-migration.sql:18,52-57`:** Reusing the built entity and calling `save` again does not provide idempotent insertion: its assigned ID can lead JPA to merge an existing row, which the immutable trigger rejects. Use an insert-only operation with explicit duplicate handling.
- **Low — `src/main/java/com/example/ninja/service/impl/PaymentServiceImpl.java:145-161,168-187,204-220`:** A failed gateway creation leaves a `PAYMENT_FAILED` order and its frozen row. That is internally consistent, but invoice/export queries must select payable/placed orders rather than interpreting every side-table row as a completed sale.
- **Medium — `src/main/java/com/example/ninja/service/impl/OrderAssembler.java:160-169`; `src/main/java/com/example/ninja/service/impl/OrderInvoiceSnapshot.java:40-53`:** Every cart type gets seller facts, while commission is FOOD-only; the current `restaurant_*` fields can therefore describe a grocery or product seller. Scope the fields by seller type or rename them before those rows feed invoices.

VERDICT: **Reject the working-tree SQL for execution** until both syntax blockers are repaired; then verify reruns, constraint validation, currency immutability, and the side-table write contract before deployment.
---

## Claude verification and disposition (2026-10-21)

| Codex finding | verified? | disposition |
|---|---|---|
| Q1 rate-card SQL truncated + duplicated | yes (known; JS `.replace` expanded `$'`) | FIX now |
| Q1 `platform-seller-profile-migration.sql:51-58` `DO $` / `END $;` | yes; HEAD has `$$`, same `.replace` bug (`$$` → `$`) | FIX now: restore `$$` |
| Q2/Q5 card currency mutable: guard trigger checks id, default, created_at, created_by, not currency | yes (`commission-rate-card-migration.sql` guard function) | FIX now: add `NEW.currency_code IS DISTINCT FROM OLD.currency_code` |
| Q3/Q6 `restaurant_*` columns filled for every cart type (`OrderAssembler` step 8 is unconditional) | yes | FIX now: rename to `seller_*` (matches table `order_seller_snapshot`). Whether 9(5) platform facts apply to grocery/product goes to CA task 0.7 |
| Q6 `save()` on an assigned-id entity merges (SELECT then INSERT); a second save hits the immutable trigger | plausible (Spring Data `isNew` is false for a non-null id without `@Version`) | FIX now, cheap: implement `Persistable` with `isNew = true` so it is a plain insert |
| Q6 a future checkout can forget `saveInvoiceFacts` | already guarded by `OrderSnapshotCallersTest.everyCheckoutThatAssemblesAnOrderAlsoSavesItsInvoiceFacts` | keep |
| Q5/Q1 no proof that the NOT VALID constraints were validated | yes | manual test list: `SELECT conname, convalidated FROM pg_constraint WHERE conname IN (...)` after file 3 |
| Q1 seed rerun does not repair a missing default slab | yes | manual test list: check the default card has version 1 with its slab |
| Q2 guard checks names/existence, not definitions | yes | REVISIT with Flyway (pre-launch, ENV deferred) |
| Q2 order/line commission immutable only in ORM | yes | REVISIT (accepted: single writer, hot tables, no trigger on `orders`) |
| Q3 `commission_rate_card_assignment.card_version_id` / `idx_commission_assignment_*` abbreviated | yes | SKIP: inside its own table the prefix is redundant; file 2 may already be applied |
| Q4 Razorpay ×5-6 and delivery destination + OTP columns on `orders` | yes | PLACE-3 revisit (trigger: second gateway, partial refunds, 2c, or delivery redesign) |
| Q6 PAYMENT_FAILED orders keep a snapshot row | yes | keep; invoice/export queries select by order status |
