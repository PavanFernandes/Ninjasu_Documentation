-- ============================================================
-- Captain Ordering — Phase 0 migration  (PostgreSQL / Neon)
-- Run ONCE. Column/table/index adds are IF-NOT-EXISTS (re-runnable);
-- the CHECK constraints and DROP NOT NULLs are one-shot.
--
-- IMPORTANT (ddl-auto=update): the app uses Hibernate schema-update, which only
-- ADDS — it never drops NOT NULLs or creates partial indexes / CHECK constraints.
-- So this migration is REQUIRED regardless of boot order. All CHECK constraints are
-- separate ALTER ... ADD CONSTRAINT statements (not inline in CREATE TABLE) precisely
-- so they still apply even if Hibernate created the bare table on an earlier boot —
-- an inline CHECK would be silently skipped by CREATE TABLE IF NOT EXISTS. Prefer to
-- run this BEFORE restarting the app on the new entities; it is correct either way.
-- ============================================================

BEGIN;

-- 1. Shop setting: the feature gate --------------------------------
ALTER TABLE public.shops
  ADD COLUMN IF NOT EXISTS pos_enabled boolean NOT NULL DEFAULT false;

-- 2. shop_tables: the physical tables (powers the floor grid) -------
CREATE TABLE IF NOT EXISTS public.shop_tables (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id     uuid        NOT NULL,                       -- shared-id ref, no FK
  label       varchar(50) NOT NULL,
  area        varchar(100),
  sort_order  int         NOT NULL DEFAULT 0,
  is_active   boolean     NOT NULL DEFAULT true,
  created_on  bigint      NOT NULL DEFAULT (extract(epoch from now())*1000)::bigint,
  updated_on  bigint      NOT NULL DEFAULT (extract(epoch from now())*1000)::bigint
);
CREATE INDEX IF NOT EXISTS idx_shop_tables_shop ON public.shop_tables (shop_id);

-- Scoped to is_active: a deactivated table (floor rearrangement) must not
-- permanently squat its label — a new active table can reuse it. Same partial-index
-- pattern as uq_table_checks_open_per_table below.
CREATE UNIQUE INDEX IF NOT EXISTS uq_shop_tables_shop_label_active
  ON public.shop_tables (shop_id, label)
  WHERE is_active = true;

-- 3. table_checks: the running tab (a party's Check) ---------------
CREATE TABLE IF NOT EXISTS public.table_checks (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id            uuid          NOT NULL,               -- shared-id ref, no FK
  table_id           uuid,                                 -- shared-id ref to shop_tables
  table_label        varchar(50)   NOT NULL,               -- denormalized snapshot
  covers             int,                                  -- optional guest count
  customer_mobile    varchar(15),                          -- optional contact, NOT a user FK
  customer_name      varchar(255),
  opened_by_staff_id uuid          NOT NULL,
  opened_at          bigint        NOT NULL DEFAULT (extract(epoch from now())*1000)::bigint,
  status             varchar(20)   NOT NULL DEFAULT 'OPEN',
  billed_total       numeric(10,2),                        -- sum-of-KOTs snapshot at close
  payment_mode       varchar(20),                          -- CASH | UPI | CARD (payment source of truth)
  paid_at            bigint,
  closed_by_staff_id uuid,
  updated_at         bigint        NOT NULL DEFAULT (extract(epoch from now())*1000)::bigint
);
-- Separate ADD CONSTRAINT (not inline) so they apply even if Hibernate already
-- created this table on an earlier boot (see header note).
ALTER TABLE public.table_checks
  ADD CONSTRAINT chk_table_checks_status  CHECK (status IN ('OPEN','BILLED','CLOSED','VOIDED')),
  ADD CONSTRAINT chk_table_checks_paymode CHECK (payment_mode IS NULL OR payment_mode IN ('CASH','UPI','CARD'));
CREATE INDEX IF NOT EXISTS idx_table_checks_shop_status ON public.table_checks (shop_id, status);

-- Load-bearing invariant: at most ONE open party per table.
CREATE UNIQUE INDEX IF NOT EXISTS uq_table_checks_open_per_table
  ON public.table_checks (shop_id, table_label)
  WHERE status = 'OPEN';

-- 4. orders: extend for dine-in / takeaway -------------------------
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS order_type         varchar(20) NOT NULL DEFAULT 'DELIVERY',
  ADD COLUMN IF NOT EXISTS order_source       varchar(20) NOT NULL DEFAULT 'CUSTOMER',
  ADD COLUMN IF NOT EXISTS check_id           uuid,
  ADD COLUMN IF NOT EXISTS kot_number         int,
  ADD COLUMN IF NOT EXISTS placed_by_staff_id uuid;

-- Relax the delivery-only NOT NULLs (dine-in/takeaway have no address/customer).
ALTER TABLE public.orders ALTER COLUMN user_id                    DROP NOT NULL;
ALTER TABLE public.orders ALTER COLUMN delivery_lat               DROP NOT NULL;
ALTER TABLE public.orders ALTER COLUMN delivery_lng               DROP NOT NULL;
ALTER TABLE public.orders ALTER COLUMN delivery_formatted_address DROP NOT NULL;
ALTER TABLE public.orders ALTER COLUMN delivery_label             DROP NOT NULL;
ALTER TABLE public.orders ALTER COLUMN payment_method             DROP NOT NULL;

-- Enum + invariant guards.
ALTER TABLE public.orders
  ADD CONSTRAINT chk_orders_type   CHECK (order_type   IN ('DELIVERY','DINE_IN','TAKEAWAY')),
  ADD CONSTRAINT chk_orders_source CHECK (order_source IN ('CUSTOMER','STAFF')),
  -- check_id present  ⟺  dine-in  (a dine-in KOT must carry a check; others must not)
  ADD CONSTRAINT chk_orders_dinein_check CHECK ((order_type = 'DINE_IN') = (check_id IS NOT NULL));

-- KDS "last 6h" feed + delivery-list type filter (DA-3) + check grouping.
CREATE INDEX IF NOT EXISTS idx_orders_shop_type_status_placed
  ON public.orders (shop_id, order_type, status, placed_on);
CREATE INDEX IF NOT EXISTS idx_orders_check
  ON public.orders (check_id) WHERE check_id IS NOT NULL;

-- 5. shop_counters: gapless per-shop, per-period serials -----------
-- Drives the human-facing numbers (NOT the UUID PK):
--   counter_type='KOT'  period_key=YYYY-MM-DD  -> kitchen call-out number, resets daily
--   counter_type='BILL' period_key=FY '2026-27'  -> GST invoice serial, resets financial year
-- Increment under the row lock in the same txn:
--   INSERT INTO shop_counters(shop_id,counter_type,period_key,value) VALUES (?,?,?,1)
--   ON CONFLICT (shop_id,counter_type,period_key)
--   DO UPDATE SET value = shop_counters.value + 1 RETURNING value;
CREATE TABLE IF NOT EXISTS public.shop_counters (
  shop_id      uuid        NOT NULL,
  counter_type varchar(20) NOT NULL,   -- 'KOT' | 'BILL'
  period_key   varchar(10) NOT NULL,   -- '2026-07-10' (daily) | '2026-27' (FY)
  value        int         NOT NULL DEFAULT 0,
  PRIMARY KEY (shop_id, counter_type, period_key)
);
-- Separate ADD CONSTRAINT (not inline) — applies even if Hibernate created the bare table first.
ALTER TABLE public.shop_counters
  ADD CONSTRAINT chk_shop_counters_type CHECK (counter_type IN ('KOT', 'BILL'));

COMMIT;

-- Rollback note: once DINE_IN/TAKEAWAY rows exist you cannot re-add the dropped
-- NOT NULLs without cleaning those rows first (one-way, per DA-6).
