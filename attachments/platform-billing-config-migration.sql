-- ============================================================
-- Platform Billing Config — migration  (PostgreSQL / Neon)
-- Run ONCE. Re-runnable (IF NOT EXISTS + ON CONFLICT DO NOTHING).
--
-- Stores Ninjasu's OWN legal/tax identity — the "supplier" side of an online
-- delivery bill under Section 9(5) CGST (Ninjasu is the deemed supplier, not
-- the restaurant — see Ninjasu_Documentation/02-Domain, bill-FINAL.md §6.1).
--
-- Singleton table (id is hardcoded to 1) — there is exactly one Ninjasu.
-- gstin is deliberately NULLABLE and starts NULL: Ninjasu has no GSTIN yet and
-- is launching KOT/dine-in only. document_type resolution must derive
-- TAX_INVOICE vs PLAIN_BILL from whether gstin is set here, never assume
-- TAX_INVOICE just because supplier_type=PLATFORM (bill-FINAL.md §6.1, §8 Phase 1).
--
-- This table is NOT consumed by any code yet — online billing (Phase 1) is
-- deferred until Ninjasu has a GSTIN and delivery actually launches. Creating
-- it now only gives the row somewhere to live once that happens.
-- ============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.platform_billing_config (
  id                 smallint      PRIMARY KEY DEFAULT 1,
  legal_name         varchar(200)  NOT NULL,
  gstin              varchar(20),                 -- NULL until Ninjasu registers
  registered_address text          NOT NULL,
  invoice_prefix     varchar(10)   NOT NULL DEFAULT 'NJ',
  updated_at         bigint        NOT NULL DEFAULT (extract(epoch from now())*1000)::bigint,
  CONSTRAINT chk_platform_billing_config_singleton CHECK (id = 1)
);

-- Seed the single row as an explicit placeholder — the real legal name/address
-- are facts only Samivan can supply, not something to guess. Update in place
-- via SQL for now (same DB-grant-only pattern as ADMIN — see
-- project_shop_admin_auth_gap) until an admin UI is decided.
INSERT INTO public.platform_billing_config (id, legal_name, gstin, registered_address, invoice_prefix)
VALUES (1, 'TBD — set actual registered legal name', NULL, 'TBD — set actual registered address', 'NJ')
ON CONFLICT (id) DO NOTHING;

COMMIT;
