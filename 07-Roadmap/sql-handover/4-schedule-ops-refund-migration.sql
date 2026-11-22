-- Plan: Ninjasu_Documentation/07-Roadmap/schedule-ops-5-ops-refund-plan.md
-- NOT RUN YET: confirm the target database (ENV-4) before running; run it again right after the backend is live.
-- Refund funding and decision attribution. Hand-run; idempotent.
-- Rerun immediately after the new backend goes live and before serving settlement.
-- Partial approvals between the first run and deployment are stored as RESTAURANT by the old backend.
-- The rerun corrects their funding and backfills the decider on rows written by the old backend.
BEGIN;
SET lock_timeout = '3s';
ALTER TABLE public.payment_refunds ADD COLUMN IF NOT EXISTS funded_by text NOT NULL DEFAULT 'RESTAURANT';
COMMIT;

BEGIN;
SET lock_timeout = '3s';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_payment_refunds_funded_by'
                 AND conrelid = 'public.payment_refunds'::regclass) THEN
    ALTER TABLE public.payment_refunds ADD CONSTRAINT chk_payment_refunds_funded_by
      CHECK (funded_by IN ('RESTAURANT', 'PLATFORM')) NOT VALID;
  END IF;
END $$;
COMMIT;

BEGIN;
SET lock_timeout = '3s';
ALTER TABLE public.payment_refunds VALIDATE CONSTRAINT chk_payment_refunds_funded_by;
COMMIT;

BEGIN;
SET lock_timeout = '3s';
ALTER TABLE public.payment_refunds ADD COLUMN IF NOT EXISTS decided_by_user_id uuid;
COMMIT;

BEGIN;
SET lock_timeout = '3s';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_payment_refunds_reasons'
                 AND conrelid = 'public.payment_refunds'::regclass
                 AND strpos(pg_get_constraintdef(oid), '''MANUAL''') > 0) THEN
    ALTER TABLE public.payment_refunds DROP CONSTRAINT IF EXISTS chk_payment_refunds_reasons;
    SET lock_timeout = '3s';
    ALTER TABLE public.payment_refunds ADD CONSTRAINT chk_payment_refunds_reasons
      CHECK (raised_by IN ('SYSTEM', 'EXTERNAL', 'MANUAL')
        AND customer_reason IN ('CUSTOMER_CANCELLED', 'RESTAURANT_DECLINED', 'ITEM_UNAVAILABLE',
                                'PAYMENT_AFTER_CANCEL', 'PAYMENT_PROBLEM', 'OTHER', 'ITEM_MISSING',
                                'QUALITY_ISSUE', 'RIDER_ISSUE', 'LATE_DELIVERY', 'GOODWILL')
        AND technical_cause IN ('HOLD_LAPSED_SOLD_OUT', 'HOLD_LAPSED_SLOT_FULL', 'CAPTURE_MISMATCH',
                                'ORPHAN_CAPTURE', 'CONFIRM_STOCK_FAIL', 'NONE',
                                'ITEM_UNAVAILABLE_AFTER_ORDER')) NOT VALID;
  END IF;
END $$;
COMMIT;

BEGIN;
SET lock_timeout = '3s';
ALTER TABLE public.payment_refunds VALIDATE CONSTRAINT chk_payment_refunds_reasons;
COMMIT;

BEGIN;
SET lock_timeout = '3s';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_payment_refunds_decision'
                 AND conrelid = 'public.payment_refunds'::regclass
                 AND strpos(pg_get_constraintdef(oid), 'decided_by_user_id') > 0) THEN
    ALTER TABLE public.payment_refunds DROP CONSTRAINT IF EXISTS chk_payment_refunds_decision;
    SET lock_timeout = '3s';
    ALTER TABLE public.payment_refunds ADD CONSTRAINT chk_payment_refunds_decision
      CHECK ((raised_by NOT IN ('SYSTEM', 'MANUAL') OR status = 'REQUESTED' OR
              (COALESCE(decided_by_user_id, decided_by_admin_id) IS NOT NULL AND decided_at IS NOT NULL))
        AND (status <> 'REJECTED' AND (approved_amount IS NULL OR approved_amount = requested_amount)
             OR decision_note IS NOT NULL)
        AND (status NOT IN ('SUBMITTING', 'ISSUED', 'PROCESSED') OR approved_amount IS NOT NULL)
        AND (raised_by <> 'MANUAL' OR decision_note IS NOT NULL)) NOT VALID;
  END IF;
END $$;
COMMIT;

BEGIN;
SET lock_timeout = '3s';
ALTER TABLE public.payment_refunds VALIDATE CONSTRAINT chk_payment_refunds_decision;
COMMIT;

-- SELECT count(*) FROM public.payment_refunds WHERE approved_amount IS NOT NULL
--   AND approved_amount < requested_amount AND funded_by = 'RESTAURANT';
BEGIN;
-- Approval code also assigns PLATFORM to partial approvals, so this backfill is safe to rerun.
UPDATE public.payment_refunds SET funded_by = 'PLATFORM'
WHERE approved_amount IS NOT NULL AND approved_amount < requested_amount AND funded_by = 'RESTAURANT';
COMMIT;

BEGIN;
UPDATE public.payment_refunds SET decided_by_user_id = decided_by_admin_id
WHERE decided_by_user_id IS NULL AND decided_by_admin_id IS NOT NULL;
COMMIT;

BEGIN;
SET LOCAL lock_timeout = '3s';
ALTER TABLE public.service_area_staff ADD COLUMN IF NOT EXISTS can_issue_refunds boolean;
ALTER TABLE public.service_area_staff ALTER COLUMN can_issue_refunds SET DEFAULT false;
UPDATE public.service_area_staff SET can_issue_refunds = false WHERE can_issue_refunds IS NULL;
ALTER TABLE public.service_area_staff ALTER COLUMN can_issue_refunds SET NOT NULL;
COMMIT;

BEGIN;
SET LOCAL lock_timeout = '3s';
ALTER TABLE public.platform_schedule_config ADD COLUMN IF NOT EXISTS refund_window_hours integer;
ALTER TABLE public.platform_schedule_config ALTER COLUMN refund_window_hours SET DEFAULT 24;
UPDATE public.platform_schedule_config SET refund_window_hours = 24 WHERE refund_window_hours IS NULL;
ALTER TABLE public.platform_schedule_config ALTER COLUMN refund_window_hours SET NOT NULL;
COMMIT;

BEGIN;
SET LOCAL lock_timeout = '3s';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_platform_schedule_refund_window'
                 AND conrelid = 'public.platform_schedule_config'::regclass) THEN
    ALTER TABLE public.platform_schedule_config ADD CONSTRAINT chk_platform_schedule_refund_window
      CHECK (refund_window_hours BETWEEN 1 AND 720) NOT VALID;
  END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL lock_timeout = '3s';
ALTER TABLE public.platform_schedule_config VALIDATE CONSTRAINT chk_platform_schedule_refund_window;
COMMIT;

-- The manual refund replay reads every attempt of one obligation key, newest first. ux_payment_refunds_obligation is
-- partial (status <> 'FAILED'), so it cannot serve a read that includes FAILED rows.
-- gcp-ignore SQL-SCHEMA-05: a plain build holds a short write lock on payment_refunds, which is small and has no
-- long-running writers; the file runs as one script in the schema test, which a CONCURRENTLY build cannot.
BEGIN;
SET LOCAL lock_timeout = '3s';
CREATE INDEX IF NOT EXISTS idx_payment_refunds_obligation_lookup
  ON public.payment_refunds (obligation_key, requested_at DESC, id DESC);
COMMIT;

-- SELECT column_name, is_nullable, column_default FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'payment_refunds'
--   AND column_name IN ('funded_by', 'decided_by_user_id');
-- SELECT conname, convalidated, pg_get_constraintdef(oid) FROM pg_constraint
-- WHERE conrelid = 'public.payment_refunds'::regclass
--   AND conname IN ('chk_payment_refunds_funded_by', 'chk_payment_refunds_reasons', 'chk_payment_refunds_decision');
-- SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
-- WHERE c.relname = 'idx_payment_refunds_obligation_lookup'; -- expect t
-- SELECT count(*) FROM public.payment_refunds
-- WHERE (approved_amount < requested_amount AND funded_by = 'RESTAURANT')
--   OR (decided_by_admin_id IS NOT NULL AND decided_by_user_id IS NULL);
