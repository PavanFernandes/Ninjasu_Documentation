-- ============================================================
-- Floor Map (spatial table view) — migration  (PostgreSQL / Neon)
-- Run ONCE. Column adds are IF-NOT-EXISTS (re-runnable); the CHECK constraints are one-shot,
-- guarded with DROP-IF-EXISTS so a re-run doesn't error.
--
-- Same rationale as captain-ordering-migration.sql / guest-qr-ordering-migration.sql:
-- ddl-auto=update only ADDS columns, it never creates CHECK constraints. This migration is
-- required regardless of boot order — the app tolerates its absence (every new column is
-- nullable, and toDto/updateTable null-guard everything), but the invariants below are not
-- enforced until this runs.
--
-- Full design: Food-Ninja-Frontend/skills/agents/arch-notes/floor-map-FINAL.md
-- The why: Ninjasu_Documentation/07-Roadmap/vision-spatial-table-view.md
-- ============================================================

BEGIN;

-- 1. shop_tables: layout position + shape ---------------------------------------
-- pos_x/pos_y are PERCENTAGES (0-100) of the canvas, not pixels — so an owner's arrangement
-- holds identically across a 1920px desktop and a 1280px laptop/tablet. NULL = never placed
-- (renders in the "unplaced" tray, not on the map). shape NULL defaults to SQUARE in
-- ShopTableServiceImpl#toDto, not backfilled here — no existing row needs a write.
ALTER TABLE public.shop_tables
  ADD COLUMN IF NOT EXISTS pos_x  numeric(5,2),
  ADD COLUMN IF NOT EXISTS pos_y  numeric(5,2),
  ADD COLUMN IF NOT EXISTS shape  varchar(10);

ALTER TABLE public.shop_tables DROP CONSTRAINT IF EXISTS chk_shop_tables_shape;
ALTER TABLE public.shop_tables
  ADD CONSTRAINT chk_shop_tables_shape CHECK (shape IS NULL OR shape IN ('ROUND','SQUARE','RECT'));

-- Paired-null: a table is either fully placed or fully unplaced, never half — this is what
-- makes isPlaced() safe to implement as a single null-check on either column.
ALTER TABLE public.shop_tables DROP CONSTRAINT IF EXISTS chk_shop_tables_pos;
ALTER TABLE public.shop_tables
  ADD CONSTRAINT chk_shop_tables_pos CHECK (
    (pos_x IS NULL AND pos_y IS NULL) OR
    (pos_x IS NOT NULL AND pos_y IS NOT NULL AND pos_x BETWEEN 0 AND 100 AND pos_y BETWEEN 0 AND 100)
  );

COMMIT;

-- 2. table_checks: waiter-call attention flag (Phase 5) --------------------------
-- Added now that Phase 5's code (TableCheckServiceImpl#ackAttention, GuestOrderServiceImpl#callStaff)
-- actually reads/writes it. NULL = no outstanding call. Lives on the CHECK, not shop_tables — see
-- TableCheck.java's javadoc on why (the flag's lifetime is then the dining session's, not sticky).
BEGIN;

ALTER TABLE public.table_checks
  ADD COLUMN IF NOT EXISTS attention_requested_at bigint;

COMMIT;
