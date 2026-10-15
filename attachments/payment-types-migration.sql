-- Per-shop payment types + split payment — schema/data migration.
-- Mirrors PaymentTypesMigrationRunner (which becomes a no-op once this has run).
-- Idempotent and backward compatible: safe to run BEFORE deploying the new backend, and to re-run.
-- Run the whole file in one go (psql / Neon SQL editor). Runs in one transaction; any error rolls it all back.

-- 0. PRE-CHECK (run separately first). All three must be non-null; if bill_payments is NULL the
--    bills feature isn't in this database yet — deploy the backend instead and let the runner do it.
--   SELECT to_regclass('public.shops'), to_regclass('public.table_checks'), to_regclass('public.bill_payments');
--   -- Constraints this will drop (expected: chk_table_checks_paymode, maybe bill_payments_method_check):
--   SELECT conrelid::regclass AS tbl, conname, pg_get_constraintdef(oid)
--   FROM pg_constraint
--   WHERE contype = 'c' AND (
--        (conrelid = 'public.table_checks'::regclass  AND pg_get_constraintdef(oid) ILIKE '%payment_mode%')
--     OR (conrelid = 'public.bill_payments'::regclass AND pg_get_constraintdef(oid) ILIKE '%method%'));

-- pgAdmin's server "Role" setting (Properties > Advanced) runs SET ROLE on connect; under a role such as
-- `authenticated` every CREATE below fails with "permission denied for schema public". Drop it first.
RESET ROLE;

BEGIN;
SET LOCAL lock_timeout = '5s';

DO $$
BEGIN
  IF current_user <> session_user THEN
    RAISE EXCEPTION 'Running as % but logged in as % - run RESET ROLE (and clear the pgAdmin server Role setting)',
      current_user, session_user;
  END IF;
END $$;

-- 1. Per-shop payment types (shop_id has no FK on purpose: cross-domain FK-free rule).
CREATE TABLE IF NOT EXISTS public.shop_payment_types (
  id           uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id      uuid         NOT NULL,
  name         varchar(40)  NOT NULL,
  system_code  varchar(10),
  active       boolean      NOT NULL DEFAULT true,
  sort_order   integer      NOT NULL DEFAULT 0,
  created_at   bigint       NOT NULL,
  updated_at   bigint       NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_spt_shop_name   ON public.shop_payment_types (shop_id, lower(name));
CREATE UNIQUE INDEX IF NOT EXISTS uq_spt_shop_system ON public.shop_payment_types (shop_id, system_code) WHERE system_code IS NOT NULL;
CREATE INDEX        IF NOT EXISTS idx_spt_shop_order ON public.shop_payment_types (shop_id, sort_order);
ALTER TABLE public.shop_payment_types DROP CONSTRAINT IF EXISTS chk_spt_system_code;
ALTER TABLE public.shop_payment_types ADD CONSTRAINT chk_spt_system_code
  CHECK (system_code IS NULL OR system_code IN ('CASH','UPI','CARD'));

-- 2. Link each bill payment to its payment type.
ALTER TABLE public.bill_payments ADD COLUMN IF NOT EXISTS payment_type_id uuid;

-- 3. payment_mode / method now hold payment-type NAMES, so drop every CHECK that restricts them to
--    CASH/UPI/CARD (the hand-named one and any Hibernate-generated "<table>_<column>_check").
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT conrelid::regclass AS tbl, conname FROM pg_constraint
           WHERE contype = 'c' AND (
                (conrelid = 'public.table_checks'::regclass  AND pg_get_constraintdef(oid) ILIKE '%payment_mode%')
             OR (conrelid = 'public.bill_payments'::regclass AND pg_get_constraintdef(oid) ILIKE '%method%'))
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', r.tbl, r.conname);
  END LOOP;
END $$;

-- 4. Widen (no-op if already this size).
ALTER TABLE public.table_checks  ALTER COLUMN payment_mode TYPE varchar(500);
ALTER TABLE public.bill_payments ALTER COLUMN method       TYPE varchar(40);

-- 5. Cash / UPI / Card for every existing shop (new shops are seeded on first use by the backend).
INSERT INTO public.shop_payment_types (id, shop_id, name, system_code, active, sort_order, created_at, updated_at)
SELECT gen_random_uuid(), s.id, d.name, d.code, true, d.ord,
       (extract(epoch from now()) * 1000)::bigint, (extract(epoch from now()) * 1000)::bigint
FROM public.shops s
CROSS JOIN (VALUES ('Cash', 'CASH', 0), ('UPI', 'UPI', 1), ('Card', 'CARD', 2)) AS d(name, code, ord)
WHERE NOT EXISTS (SELECT 1 FROM public.shop_payment_types t WHERE t.shop_id = s.id AND t.system_code = d.code)
ON CONFLICT DO NOTHING;

-- 6. Link existing bill payments (they hold CASH/UPI/CARD in method) to their shop's seeded type.
UPDATE public.bill_payments bp
SET payment_type_id = t.id
FROM public.bills b, public.shop_payment_types t
WHERE bp.bill_id = b.id AND bp.payment_type_id IS NULL
  AND t.shop_id = b.shop_id AND t.system_code = bp.method;

-- 7. FK (same domain).
ALTER TABLE public.bill_payments DROP CONSTRAINT IF EXISTS fk_bill_payments_type;
ALTER TABLE public.bill_payments ADD CONSTRAINT fk_bill_payments_type
  FOREIGN KEY (payment_type_id) REFERENCES public.shop_payment_types (id);

COMMIT;

-- 8. VERIFY (run after COMMIT).
--   -- both columns widened: expect 500 and 40
--   SELECT table_name, column_name, character_maximum_length FROM information_schema.columns
--   WHERE table_schema = 'public' AND ((table_name = 'table_checks' AND column_name = 'payment_mode')
--      OR (table_name = 'bill_payments' AND column_name = 'method'));
--   -- no CHECK left on those columns: expect 0 rows
--   SELECT conrelid::regclass, conname FROM pg_constraint WHERE contype = 'c' AND (
--        (conrelid = 'public.table_checks'::regclass  AND pg_get_constraintdef(oid) ILIKE '%payment_mode%')
--     OR (conrelid = 'public.bill_payments'::regclass AND pg_get_constraintdef(oid) ILIKE '%method%'));
--   -- every shop has exactly 3 seeded types: expect 0 rows
--   SELECT s.id FROM public.shops s
--   WHERE (SELECT count(*) FROM public.shop_payment_types t WHERE t.shop_id = s.id AND t.system_code IS NOT NULL) <> 3;
--   -- every legacy bill payment linked: expect 0
--   SELECT count(*) FROM public.bill_payments WHERE payment_type_id IS NULL;
