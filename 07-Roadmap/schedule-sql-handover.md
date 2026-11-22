# Schedule SQL handover (2026-11-22)

Four hand-run SQL files wait for you: 3.2 batches, 3.3 batch assign, 3.4f-2a route order, OPS-5a refund funding. Nothing here has been run on Neon by Claude. Statuses below are what the repo and notes show; the preflight query in step 1 tells you the truth.

## Read first
- Neon is production: there is one database, no test copy. Run as `neondb_owner` (not `authenticated`). Confirm the host in the editor header before every block.
- Run one block at a time, read the result, then the next. Every file is idempotent (a second run is safe).
- Run the SQL before the backend that needs it boots: `ScheduleSchemaGuard` and `PaymentRefundSchemaGuard` refuse to start without the objects.
- Rehearse first on a Neon branch (Branches, Create branch, from the main branch: an instant copy). Run steps 2 to 6 there, check, then repeat on main.

## Step 0: the three ENV-4 answers (needed before the first run)
1. Postgres major version: `select version();`
2. Recovery: Neon console, project Settings, Storage or Restore window: note the point-in-time restore window. Before the first run write down `select now();` so you know the restore point.
3. Rehearsal copy: the Neon branch above.

## Step 1: preflight (read-only, safe). Paste once, send me the result
```sql
SELECT 'order_groups table' AS check_name, to_regclass('public.order_groups') IS NOT NULL AS present
UNION ALL SELECT 'service_area table', to_regclass('public.service_area') IS NOT NULL
UNION ALL SELECT 'service_area_staff table', to_regclass('public.service_area_staff') IS NOT NULL
UNION ALL SELECT 'deliveries table', to_regclass('public.deliveries') IS NOT NULL
UNION ALL SELECT 'orders.ready_at (ready-at file)', EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='orders' AND column_name='ready_at')
UNION ALL SELECT 'schedule_batches table (file 1)', to_regclass('public.schedule_batches') IS NOT NULL
UNION ALL SELECT 'schedule_batch_events table (file 1)', to_regclass('public.schedule_batch_events') IS NOT NULL
UNION ALL SELECT 'deliveries.batch_id (file 2)', EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='deliveries' AND column_name='batch_id')
UNION ALL SELECT 'schedule_batch_groups.drop_no (file 3)', EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='schedule_batch_groups' AND column_name='drop_no')
UNION ALL SELECT 'schedule_batch_pickups table (file 3)', to_regclass('public.schedule_batch_pickups') IS NOT NULL
UNION ALL SELECT 'payment_refunds table (refund base)', to_regclass('public.payment_refunds') IS NOT NULL
UNION ALL SELECT 'payment_refunds.order_group_id (refund group file)', EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='payment_refunds' AND column_name='order_group_id')
UNION ALL SELECT 'payment_refund_allocations.order_line_id (refund lines file)', EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='payment_refund_allocations' AND column_name='order_line_id')
UNION ALL SELECT 'payment_refunds.funded_by (file 4)', EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='payment_refunds' AND column_name='funded_by');
```
Expected today: the first four and `orders.ready_at` present; files 1 to 4 absent. The three refund base rows must be present before file 4. A table that exists only because Hibernate created it (no constraints) shows as present: the file's own verify block catches that.

## Step 2 to 6: the order
| # | file | where the file is | needs | status |
|---|---|---|---|---|
| 2 | `schedule-batch-migration.sql` | backend `feature/schedule` (merged, PR #97), `db_manual/` | `order-group-migration.sql`, `service-area-migration.sql` | NOT RUN |
| 3 | `schedule-batch-assign-migration.sql` | backend `feature/schedule` (merged, PR #98) | file 2 | NOT RUN. Its Block 2 is `CREATE INDEX CONCURRENTLY`: run that statement alone, outside any transaction |
| 4 | `schedule-ready-at-migration.sql` | backend branch `feature/schedule-ops-board-read` | none | ALREADY RUN 2026-11-20 (skip; preflight shows `orders.ready_at`) |
| 5 | `schedule-route-order-migration.sql` | backend branch `feature/schedule-route-order` (commit e0b54ee, not pushed) | files 2 and 3 | NOT RUN. Your 2026-11-21 attempt stopped at statement 2 because the batch tables did not exist; nothing was applied. Safe after file 2 |
| 6 | `schedule-ops-refund-migration.sql` | backend branch `feature/schedule-ops5a-refund-funding` (commit a0eba69, not pushed) | the three `payment-refunds-*` files (refund base, group, lines) | NOT RUN. Run it again right after the backend with OPS-5a is live and before settlement is served |

To read a file that is not on your current branch: `git show feature/schedule-route-order:db_manual/schedule-route-order-migration.sql` and `git show feature/schedule-ops5a-refund-funding:db_manual/schedule-ops-refund-migration.sql` (backend repo `ninja delivery service java`).

## Check after each file (read-only; send me the output)
- File 2: `SELECT to_regclass('public.schedule_batches'), to_regclass('public.schedule_batch_groups'), to_regclass('public.schedule_batch_events');` expect 3 names. `SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.schedule_batch_events'::regclass AND NOT tgisinternal;` expect at least one append-only trigger.
- File 3: `SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE c.relname = 'idx_deliveries_batch';` expect `t` (on `f`: the file says how to drop and rerun).
- File 5: `SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'chk_batch_events_type';` expect it to contain `PICKUP_ORDER_SET`. `SELECT to_regclass('public.schedule_batch_pickups');` expect a name. `SELECT column_name FROM information_schema.columns WHERE table_name = 'schedule_batch_groups' AND column_name = 'drop_no';` expect 1 row.
- File 6: before running, count the rows the backfill will reclassify: `SELECT count(*) FROM public.payment_refunds WHERE approved_amount IS NOT NULL AND approved_amount < requested_amount AND funded_by = 'RESTAURANT';` (after the first run `funded_by` exists; the file also prints this count in a comment). After: `SELECT funded_by, count(*) FROM public.payment_refunds GROUP BY 1;` and `SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname IN ('chk_payment_refunds_reasons','chk_payment_refunds_decision');` expect `MANUAL` in the first and `decided_by_user_id` in the second. The last block of each file has its own verify queries too.

## Deploy order and rollback
- SQL first, then the backend: file 2 and 3 before any backend with batches (feature/schedule); file 5 before the backend with route order; file 6 before the backend with OPS-5a, then file 6 again once that backend is live.
- Do not deploy a backend branch before its file ran: it will not boot.
- Rollback: roll the backend back first; keep the new tables, columns and constraints (old code ignores them). Point-in-time restore on Neon is the last resort and loses writes after the restore point.
- Nothing is on `main` for backend or web; `main` deploys to production: ask before any merge there.

## What I need back from you
The result of step 0 (version, restore window), the preflight table, then the output of each block as you run it.
