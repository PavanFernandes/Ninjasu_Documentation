-- ============================================================
-- Raw-Material Purchasing — Phase 0 migration  (PostgreSQL / Neon)
-- Run ONCE. Table/column/index adds are IF-NOT-EXISTS (re-runnable);
-- the CHECK constraints and the FK are DROP-then-ADD (also re-runnable).
--
-- IMPORTANT (ddl-auto=update): the app uses Hibernate schema-update, which only
-- ADDS — it never creates CHECK constraints, expression indexes, partial indexes
-- or foreign keys. So this migration is REQUIRED regardless of boot order. Every
-- CHECK is a separate ALTER ... ADD CONSTRAINT (not inline in CREATE TABLE)
-- precisely so it still applies if Hibernate created the bare table on an earlier
-- boot — an inline CHECK would be silently skipped by CREATE TABLE IF NOT EXISTS.
-- Prefer to run this BEFORE restarting the app on the new entities; it is correct
-- either way.
--
-- config/PurchasingMigrationRunner.java applies the same constraints/indexes at
-- boot as a safety net. Running this file first makes that runner a no-op.
--
-- SCOPE: five new tables. Touches NO existing table. Deletes nothing.
-- Rollback is the DROP block at the foot of this file.
--
-- Design decisions enforced here are labelled D-n and documented in
--   ../07-Roadmap/vision-inventory-module.md
-- ============================================================

BEGIN;

-- 1. material_units — a unit of measure, per shop ------------------
-- A RECORD, not a free-text string per row (D3): a unit row can later gain a
-- conversion factor additively; a string scattered across thousands of lines
-- cannot. v1 does NO conversion — one material, one unit.
CREATE TABLE IF NOT EXISTS public.material_units (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id     uuid        NOT NULL,                       -- shared-id ref, no FK
  label       varchar(32) NOT NULL,
  created_on  bigint      NOT NULL DEFAULT (extract(epoch from now())*1000)::bigint,
  updated_on  bigint      NOT NULL DEFAULT (extract(epoch from now())*1000)::bigint
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_material_units_shop_label
  ON public.material_units (shop_id, lower(label));


-- 2. raw_materials — what the kitchen buys -------------------------
-- Created INLINE from a purchase bill line. There is deliberately no master-list
-- setup screen and no pre-seeded catalogue: the master builds itself from what the
-- shop actually buys.
--
-- NOTE (D2): there is deliberately NO is_deleted column. Duplicates ("onions" vs
-- "Onion") are resolved by MERGE — re-point every purchase line to the winner, then
-- HARD-delete the loser. A soft-delete flag would force `WHERE is_deleted = false`
-- on every future query, and the first reader to forget it resurfaces the duplicate
-- in a report months later.
CREATE TABLE IF NOT EXISTS public.raw_materials (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id                uuid         NOT NULL,           -- shared-id ref, no FK
  name                   varchar(120) NOT NULL,
  category               varchar(64),                     -- vegetables, dairy, spices, packaging, gas
  unit_id                uuid,                            -- -> material_units.id (no FK: nullable, shop-scoped)
  track_quantity         boolean      NOT NULL DEFAULT false,
  expected_frequency     varchar(16),                     -- cold-start seed only (D15)
  canonical_material_id  uuid,                            -- reserved for benchmarking (D10); nothing writes it in v1
  created_on             bigint       NOT NULL DEFAULT (extract(epoch from now())*1000)::bigint,
  updated_on             bigint       NOT NULL DEFAULT (extract(epoch from now())*1000)::bigint
);

-- D15: the declared frequency is a SEED, never an override — the derived cadence
-- (median days between purchases) wins once a material has >= 3 purchases.
ALTER TABLE public.raw_materials DROP CONSTRAINT IF EXISTS chk_raw_materials_frequency;
ALTER TABLE public.raw_materials ADD CONSTRAINT chk_raw_materials_frequency
  CHECK (expected_frequency IS NULL
         OR expected_frequency IN ('WEEKLY','FORTNIGHTLY','MONTHLY','QUARTERLY','YEARLY'));

-- D2: makes trivial case-insensitive duplicates impossible at the DB level.
-- Near-duplicates ("onions", "pyaz") are handled by fuzzy match on create plus the
-- explicit MERGE above — this index only closes the easy hole.
CREATE UNIQUE INDEX IF NOT EXISTS uq_raw_materials_shop_name
  ON public.raw_materials (shop_id, lower(name));

CREATE INDEX IF NOT EXISTS idx_raw_materials_shop_category
  ON public.raw_materials (shop_id, category);


-- 3. purchase_suppliers — vendors ---------------------------------
-- Named purchase_suppliers, NOT suppliers, on purpose: `bills` already uses
-- "supplier" to mean the SHOP as GST supplier-of-record for a customer bill.
-- Unrelated concept, same word — the prefix stops a future grep landing on the
-- wrong one (D12).
--
-- v1 holds NAME and PHONE only, both optional. GSTIN is deferred: it is on the
-- photographed bill if ever needed, and a supplier phone number is a third party's
-- personal data, so not holding it is the cheapest privacy decision available.
CREATE TABLE IF NOT EXISTS public.purchase_suppliers (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id     uuid         NOT NULL,                      -- shared-id ref, no FK
  name        varchar(120) NOT NULL,
  phone       varchar(20),
  created_on  bigint       NOT NULL DEFAULT (extract(epoch from now())*1000)::bigint,
  updated_on  bigint       NOT NULL DEFAULT (extract(epoch from now())*1000)::bigint
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_purchase_suppliers_shop_name
  ON public.purchase_suppliers (shop_id, lower(name));


-- 4. purchases — one supplier bill --------------------------------
-- IMMUTABLE once created (D6). Same container/fired-ticket pattern the POS already
-- uses for table_checks and KOTs: a To Buy list is the mutable container, and
-- RECEIVING it CREATES one of these. It never "becomes" one. Partial delivery is
-- normal (onions Monday, paneer Thursday), so ONE list can produce MANY purchases —
-- hence source_list_id is a plain nullable column, not a unique one.
--
-- `total` IS AUTHORITATIVE (D5) and is never derived from purchase_lines. Lines are
-- optional detail; where they don't sum to the total the gap is displayed as
-- "unitemised", never reconciled away.
CREATE TABLE IF NOT EXISTS public.purchases (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id         uuid          NOT NULL,                 -- shared-id ref, no FK
  supplier_id     uuid,                                   -- optional: a bill needs no supplier
  purchase_date   date          NOT NULL,                 -- the bill's own date, not entry time
  total           numeric(12,2) NOT NULL,
  photo_key       varchar(512),                           -- S3 KEY, never a full URL
  source_list_id  uuid,                                   -- reserved for Phase 1 (D6)
  created_by      uuid          NOT NULL,
  created_on      bigint        NOT NULL DEFAULT (extract(epoch from now())*1000)::bigint,
  updated_on      bigint        NOT NULL DEFAULT (extract(epoch from now())*1000)::bigint
);

ALTER TABLE public.purchases DROP CONSTRAINT IF EXISTS chk_purchases_total_non_negative;
ALTER TABLE public.purchases ADD CONSTRAINT chk_purchases_total_non_negative
  CHECK (total >= 0);

-- The workhorse: every spend/trend report is shop + date range.
CREATE INDEX IF NOT EXISTS idx_purchases_shop_date
  ON public.purchases (shop_id, purchase_date);

CREATE INDEX IF NOT EXISTS idx_purchases_supplier
  ON public.purchases (supplier_id) WHERE supplier_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_purchases_source_list
  ON public.purchases (source_list_id) WHERE source_list_id IS NOT NULL;


-- 5. purchase_lines — optional detail on a bill -------------------
-- A purchase is COMPLETE with zero lines. Money is the floor: every line has an
-- amount. quantity is nullable and carries EXACTLY ONE meaning (D4) — the material
-- was UNTRACKED at the time of entry. It never means zero, and the CHECK below makes
-- a stored zero impossible rather than leaving it to caller discipline.
--
-- unit_id is snapshotted ON THE LINE, not read from the material (D3): a supplier
-- switching from 25 kg to 20 kg sacks must not silently rewrite what every past
-- "sack" meant.
CREATE TABLE IF NOT EXISTS public.purchase_lines (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_id  uuid          NOT NULL,
  material_id  uuid          NOT NULL,
  shop_id      uuid          NOT NULL,                    -- denormalised for shop-scoped reads
  amount       numeric(12,2) NOT NULL,
  quantity     numeric(12,3),                             -- NULL <=> untracked at entry (D4)
  unit_id      uuid,                                      -- snapshot, see above (D3)
  created_on   bigint        NOT NULL DEFAULT (extract(epoch from now())*1000)::bigint
);

ALTER TABLE public.purchase_lines DROP CONSTRAINT IF EXISTS chk_purchase_lines_amount_non_negative;
ALTER TABLE public.purchase_lines ADD CONSTRAINT chk_purchase_lines_amount_non_negative
  CHECK (amount >= 0);

-- D4: a stored zero would destroy the "untracked" distinction, so zero is forbidden
-- outright. NULL stays legal and is the only way to say "no quantity recorded".
ALTER TABLE public.purchase_lines DROP CONSTRAINT IF EXISTS chk_purchase_lines_quantity_positive;
ALTER TABLE public.purchase_lines ADD CONSTRAINT chk_purchase_lines_quantity_positive
  CHECK (quantity IS NULL OR quantity > 0);

-- Same-domain FK (allowed — the no-FK rule is for CROSS-domain refs like shop_id).
-- Deleting a purchase must take its lines with it.
ALTER TABLE public.purchase_lines DROP CONSTRAINT IF EXISTS fk_purchase_lines_purchase;
ALTER TABLE public.purchase_lines ADD CONSTRAINT fk_purchase_lines_purchase
  FOREIGN KEY (purchase_id) REFERENCES public.purchases (id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_purchase_lines_purchase
  ON public.purchase_lines (purchase_id);

-- Backs price-per-material trends and the MERGE re-point in D2.
CREATE INDEX IF NOT EXISTS idx_purchase_lines_shop_material
  ON public.purchase_lines (shop_id, material_id);

COMMIT;


-- ============================================================
-- Verification — run after COMMIT. Expect 5 rows.
-- ============================================================
-- SELECT table_name FROM information_schema.tables
--  WHERE table_schema = 'public'
--    AND table_name IN ('material_units','raw_materials','purchase_suppliers',
--                       'purchases','purchase_lines')
--  ORDER BY table_name;
--
-- Expect 4 CHECK constraints:
-- SELECT conname FROM pg_constraint
--  WHERE conname LIKE 'chk_raw_materials%' OR conname LIKE 'chk_purchase%'
--  ORDER BY conname;
--
-- Expect 3 unique + 6 plain indexes:
-- SELECT indexname FROM pg_indexes
--  WHERE schemaname = 'public'
--    AND (indexname LIKE 'uq_raw_materials%' OR indexname LIKE 'uq_material_units%'
--      OR indexname LIKE 'uq_purchase_suppliers%' OR indexname LIKE 'idx_purchase%'
--      OR indexname LIKE 'idx_raw_materials%')
--  ORDER BY indexname;


-- ============================================================
-- ROLLBACK (only if you want these gone — destroys all purchasing data)
-- ============================================================
-- BEGIN;
-- DROP TABLE IF EXISTS public.purchase_lines;      -- FK child first
-- DROP TABLE IF EXISTS public.purchases;
-- DROP TABLE IF EXISTS public.raw_materials;
-- DROP TABLE IF EXISTS public.purchase_suppliers;
-- DROP TABLE IF EXISTS public.material_units;
-- COMMIT;
