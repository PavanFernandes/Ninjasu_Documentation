-- Schedule 3.4f-2a: the manager's pickup order (shops) and drop order (groups) inside a batch.
-- Hand-run; idempotent. DO NOT RUN until ENV-4 is answered (Postgres major version, backup / point-in-time restore,
-- rehearsal copy). Confirm the target database host and run one block at a time.
-- Preconditions: db_manual/schedule-batch-migration.sql has run.
-- Run this file BEFORE the backend that uses it boots: ScheduleSchemaGuard refuses to boot without these objects.
-- Plan: Ninjasu_Documentation/07-Roadmap/schedule-3-4-ops-board-plan.md ("3.4f-2 data model review", L3 to L6).
-- Rollback: roll back the backend first; keep the column and the table (old code ignores them).

SET lock_timeout = '3s';

-- Block 1: the batch event types gain PICKUP_ORDER_SET and DROP_ORDER_SET (a table that already has the older list is upgraded).
ALTER TABLE public.schedule_batch_events DROP CONSTRAINT IF EXISTS chk_batch_events_type;
ALTER TABLE public.schedule_batch_events ADD CONSTRAINT chk_batch_events_type CHECK (event_type IN
  ('BATCH_CREATED','GROUP_ADDED','GROUP_REMOVED','RIDER_ASSIGNED','RIDER_CHANGED','SHOP_HANDOVER','GROUP_DROPPED','GROUP_DROP_FAILED','BATCH_CANCELLED','PICKUP_ORDER_SET','DROP_ORDER_SET'));

-- Block 2: schedule_batch_groups.drop_no (NULL = not placed by the manager yet, or a cancelled member).
-- The unique rule is DEFERRABLE INITIALLY DEFERRED so one transaction can swap two stops.
ALTER TABLE public.schedule_batch_groups ADD COLUMN IF NOT EXISTS drop_no INTEGER;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_schedule_batch_groups_drop_no' AND conrelid = 'public.schedule_batch_groups'::regclass) THEN
    ALTER TABLE public.schedule_batch_groups ADD CONSTRAINT chk_schedule_batch_groups_drop_no CHECK (drop_no IS NULL OR drop_no BETWEEN 1 AND 99);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_schedule_batch_groups_drop_no' AND conrelid = 'public.schedule_batch_groups'::regclass) THEN
    ALTER TABLE public.schedule_batch_groups ADD CONSTRAINT uq_schedule_batch_groups_drop_no UNIQUE (batch_id, drop_no) DEFERRABLE INITIALLY DEFERRED;
  END IF;
END $$;

-- Block 3: schedule_batch_pickups (one shop's place in one batch's pickup order; shop_id is a soft reference: no foreign key).
CREATE TABLE IF NOT EXISTS public.schedule_batch_pickups (
  batch_id   UUID    NOT NULL,
  shop_id    UUID    NOT NULL,
  pickup_no  INTEGER NOT NULL,
  set_by     UUID    NOT NULL,
  set_at     BIGINT  NOT NULL
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pk_schedule_batch_pickups' AND conrelid = 'public.schedule_batch_pickups'::regclass) THEN
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE contype = 'p' AND conrelid = 'public.schedule_batch_pickups'::regclass) THEN
      EXECUTE format('ALTER TABLE public.schedule_batch_pickups RENAME CONSTRAINT %I TO pk_schedule_batch_pickups', (SELECT conname FROM pg_constraint WHERE contype = 'p' AND conrelid = 'public.schedule_batch_pickups'::regclass));
    ELSE
      ALTER TABLE public.schedule_batch_pickups ADD CONSTRAINT pk_schedule_batch_pickups PRIMARY KEY (batch_id, shop_id);
    END IF;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_schedule_batch_pickups_batch' AND conrelid = 'public.schedule_batch_pickups'::regclass) THEN
    ALTER TABLE public.schedule_batch_pickups ADD CONSTRAINT fk_schedule_batch_pickups_batch FOREIGN KEY (batch_id) REFERENCES public.schedule_batches (id) ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_schedule_batch_pickups_set_by' AND conrelid = 'public.schedule_batch_pickups'::regclass) THEN
    ALTER TABLE public.schedule_batch_pickups ADD CONSTRAINT fk_schedule_batch_pickups_set_by FOREIGN KEY (set_by) REFERENCES public.users (id) ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_schedule_batch_pickups_no' AND conrelid = 'public.schedule_batch_pickups'::regclass) THEN
    ALTER TABLE public.schedule_batch_pickups ADD CONSTRAINT chk_schedule_batch_pickups_no CHECK (pickup_no BETWEEN 1 AND 99);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_schedule_batch_pickups_no' AND conrelid = 'public.schedule_batch_pickups'::regclass) THEN
    ALTER TABLE public.schedule_batch_pickups ADD CONSTRAINT uq_schedule_batch_pickups_no UNIQUE (batch_id, pickup_no) DEFERRABLE INITIALLY DEFERRED;
  END IF;
END $$;

-- Verify (read-only; expect the event check to name PICKUP_ORDER_SET and DROP_ORDER_SET, the drop_no column, 2 constraints on it, the pickups table and 5 constraints on it):
-- SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'chk_batch_events_type';
-- SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'schedule_batch_groups' AND column_name = 'drop_no';
-- SELECT conrelid::regclass AS tbl, conname, condeferrable FROM pg_constraint WHERE conname LIKE '%drop_no' OR conrelid = 'public.schedule_batch_pickups'::regclass ORDER BY 1, 2;
