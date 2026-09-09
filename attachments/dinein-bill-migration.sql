-- ============================================================
-- Dine-in Bill — migration  (PostgreSQL / Neon)
-- Run ONCE. Re-runnable (IF NOT EXISTS guards); the CHECK-constraint widen on
-- shop_counters is one-shot (DROP + re-ADD).
--
-- Scope: DINE_IN ONLY. Ninjasu has no GSTIN yet and is launching KOT/dine-in
-- only — online/takeaway bill generation, platform_billing_config, and the
-- PLATFORM invoice-counter scope are all deferred (see bill-FINAL.md §8).
-- The `source`/`series`/`supplier_type` columns below are still the full
-- 4-way shape so no second migration is needed when online ships later —
-- only DINE_IN/SHOP rows are ever written today.
--
-- No FKs anywhere below — matches this schema's existing convention
-- (table_checks/orders carry no REFERENCES either; see captain-ordering-migration.sql).
-- ============================================================

BEGIN;

-- 1. Shop: declared GST regime + business-day boundary ----------------------
-- gst_regime is DECLARED, never inferred from whether a gstin happens to be
-- present (bill-FINAL.md §6.3 — a COMPOSITION dealer HAS a GSTIN and must
-- still not charge tax, so GSTIN-presence and tax-collection are independent
-- facts). Existing shops backfill to UNREGISTERED — the safe, no-tax default;
-- an owner explicitly upgrades to COMPOSITION/REGULAR later, which is what
-- triggers the "GSTIN required" validation at bill-generation time, not here.
ALTER TABLE public.shops
  ADD COLUMN IF NOT EXISTS gst_regime varchar(20) NOT NULL DEFAULT 'UNREGISTERED',
  ADD COLUMN IF NOT EXISTS business_day_start_hour smallint NOT NULL DEFAULT 5;

ALTER TABLE public.shops
  DROP CONSTRAINT IF EXISTS chk_shops_gst_regime;
ALTER TABLE public.shops
  ADD CONSTRAINT chk_shops_gst_regime CHECK (gst_regime IN ('UNREGISTERED', 'COMPOSITION', 'REGULAR'));

ALTER TABLE public.shops
  DROP CONSTRAINT IF EXISTS chk_shops_business_day_start_hour;
ALTER TABLE public.shops
  ADD CONSTRAINT chk_shops_business_day_start_hour CHECK (business_day_start_hour BETWEEN 0 AND 23);

-- 2. shop_counters: widen for the daily OPERATIONAL bill number -------------
-- shop_counters already exists (captain-ordering-migration.sql) with
-- counter_type IN ('KOT','BILL') — 'BILL' was already earmarked there for the
-- FY-based STATUTORY invoice serial ("GST invoice serial, resets financial
-- year"), which is exactly what bill-FINAL.md's `invoice_number` needs — no
-- new table required, reused as originally scaffolded.
--
-- The DAILY-reset operational `bill_number` (bill-FINAL.md §3) is a genuinely
-- different counter — it must NOT share a row with the FY-scoped 'BILL'
-- counter — so it gets its own counter_type: 'BILL_OP_D' (dine-in). Per-channel
-- variants ('BILL_OP_O', 'BILL_OP_T') can be added later by relaxing this same
-- CHECK — no schema change, just a wider allow-list.
ALTER TABLE public.shop_counters
  DROP CONSTRAINT IF EXISTS chk_shop_counters_type;
ALTER TABLE public.shop_counters
  ADD CONSTRAINT chk_shop_counters_type CHECK (counter_type IN ('KOT', 'BILL', 'BILL_OP_D'));

-- 3. bills -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.bills (
  id                     uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id                uuid          NOT NULL,

  -- COMMERCIAL CHANNEL (observed), not a legal conclusion (bill-FINAL.md §6.3a).
  -- Only 'DINE_IN' is ever written today.
  source                 varchar(20)   NOT NULL,
  series                 varchar(4)    NOT NULL,   -- D | O | T — only 'D' today
  bill_number            int           NOT NULL,   -- resets daily, per shop+series (business_date)
  business_date          date          NOT NULL,   -- derived via shop.business_day_start_hour
  created_at             bigint        NOT NULL,   -- real epoch ms — FY derives from this if needed
  status                 varchar(20)   NOT NULL DEFAULT 'GENERATED',
                                                    -- GENERATED|PARTIALLY_PAID|PAID|WRITTEN_OFF|VOIDED

  check_id               uuid,                     -- dine-in source (set today)
  order_id               uuid,                     -- online/takeaway source (unused today)

  -- TAX identity: who is the supplier of record (bill-FINAL.md §6). Only
  -- supplier_type='SHOP' is produced today — 'PLATFORM' waits on Ninjasu's own
  -- GSTIN (see platform-billing-config-migration.sql, deferred).
  document_type          varchar(20)   NOT NULL,   -- PLAIN_BILL | BILL_OF_SUPPLY | TAX_INVOICE
  supplier_type          varchar(10)   NOT NULL,   -- SHOP | PLATFORM
  supplier_name          varchar(200)  NOT NULL,
  supplier_gstin         varchar(20),
  supplier_address       text          NOT NULL,
  invoice_number         varchar(40),              -- null unless document_type=TAX_INVOICE

  -- OUTLET identity: who cooked it — always the shop, even for a future
  -- PLATFORM-supplier online bill.
  outlet_name            varchar(200)  NOT NULL,
  outlet_address         text          NOT NULL,
  outlet_phone           varchar(15),
  outlet_fssai           varchar(20),

  -- money — all frozen at generation, never recomputed from live prices
  subtotal               numeric(10,2) NOT NULL,
  discount_total         numeric(10,2) NOT NULL DEFAULT 0,
  taxable_total          numeric(10,2) NOT NULL,
  cgst_amount            numeric(10,2) NOT NULL DEFAULT 0,
  cgst_rate              numeric(5,2)  NOT NULL DEFAULT 0,
  sgst_amount            numeric(10,2) NOT NULL DEFAULT 0,
  sgst_rate              numeric(5,2)  NOT NULL DEFAULT 0,
  igst_amount            numeric(10,2) NOT NULL DEFAULT 0,
  igst_rate              numeric(5,2)  NOT NULL DEFAULT 0,
  cess_amount            numeric(10,2) NOT NULL DEFAULT 0,
  delivery_fee           numeric(10,2) NOT NULL DEFAULT 0,
  platform_fee           numeric(10,2) NOT NULL DEFAULT 0,
  rounding               numeric(10,2) NOT NULL DEFAULT 0,
  grand_total            numeric(10,2) NOT NULL,

  -- settlement
  paid_at                bigint,
  settled_by_staff_id    uuid,
  writeoff_reason        varchar(40),
  writeoff_by_staff_id   uuid,
  superseded_by_bill_id  uuid          -- void-and-reissue chain (Phase 3, unused today)
);

ALTER TABLE public.bills
  DROP CONSTRAINT IF EXISTS chk_bills_status;
ALTER TABLE public.bills
  ADD CONSTRAINT chk_bills_status CHECK (status IN ('GENERATED','PARTIALLY_PAID','PAID','WRITTEN_OFF','VOIDED'));

ALTER TABLE public.bills
  DROP CONSTRAINT IF EXISTS chk_bills_document_type;
ALTER TABLE public.bills
  ADD CONSTRAINT chk_bills_document_type CHECK (document_type IN ('PLAIN_BILL','BILL_OF_SUPPLY','TAX_INVOICE'));

ALTER TABLE public.bills
  DROP CONSTRAINT IF EXISTS chk_bills_supplier_type;
ALTER TABLE public.bills
  ADD CONSTRAINT chk_bills_supplier_type CHECK (supplier_type IN ('SHOP','PLATFORM'));

ALTER TABLE public.bills
  DROP CONSTRAINT IF EXISTS chk_bills_writeoff_reason;
ALTER TABLE public.bills
  ADD CONSTRAINT chk_bills_writeoff_reason
    CHECK (writeoff_reason IS NULL OR writeoff_reason IN ('CUSTOMER_COMP','WALKOUT','DISPUTE','OTHER'));

-- One bill number per shop+business_day+series — the load-bearing invariant.
CREATE UNIQUE INDEX IF NOT EXISTS uq_bills_number
  ON public.bills (shop_id, business_date, series, bill_number);

-- List/report queries. Tiebreak paging on (created_at desc, id desc) in code —
-- created_at millis alone is non-unique (see table_checks history precedent).
CREATE INDEX IF NOT EXISTS idx_bills_shop_status_created
  ON public.bills (shop_id, status, created_at);
CREATE INDEX IF NOT EXISTS idx_bills_shop_business_date
  ON public.bills (shop_id, business_date);
CREATE INDEX IF NOT EXISTS idx_bills_check_id
  ON public.bills (check_id) WHERE check_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bills_order_id
  ON public.bills (order_id) WHERE order_id IS NOT NULL;

-- 4. bill_lines ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.bill_lines (
  id             uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  bill_id        uuid          NOT NULL,
  item_name      varchar(200)  NOT NULL,
  quantity       int           NOT NULL,
  unit_price     numeric(10,2) NOT NULL,   -- derived from OrderLineAddon snapshots at generation
  line_discount  numeric(10,2) NOT NULL DEFAULT 0,
  addon_summary  text,                     -- denormalized display string, e.g. "+ Extra Cheese"
  line_total     numeric(10,2) NOT NULL,
  hsn_sac        varchar(10),
  tax_rate       numeric(5,2)
);
CREATE INDEX IF NOT EXISTS idx_bill_lines_bill_id ON public.bill_lines (bill_id);

-- 5. bill_payments — split payment support (Rev 2) ---------------------------
CREATE TABLE IF NOT EXISTS public.bill_payments (
  id                    uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  bill_id               uuid          NOT NULL,
  method                varchar(20)   NOT NULL,   -- CASH | UPI | CARD (CheckPaymentMode today)
  amount                numeric(10,2) NOT NULL,
  reference              varchar(100),
  paid_at               bigint        NOT NULL,
  recorded_by_staff_id  uuid          NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_bill_payments_bill_id ON public.bill_payments (bill_id);

-- 6. bill_refunds — corrections are events, never edits (Phase 3, schema only today)
CREATE TABLE IF NOT EXISTS public.bill_refunds (
  id                    uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  bill_id               uuid          NOT NULL,
  payment_id            uuid,
  amount                numeric(10,2) NOT NULL,
  reason                text          NOT NULL,
  credit_note_number    varchar(40),
  created_at            bigint        NOT NULL,
  created_by_staff_id   uuid          NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_bill_refunds_bill_id ON public.bill_refunds (bill_id);

COMMIT;
