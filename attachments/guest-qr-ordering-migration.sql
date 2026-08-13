-- ============================================================
-- Guest QR Table Ordering — migration  (PostgreSQL / Neon)
-- Run ONCE. Column/table/index adds are IF-NOT-EXISTS (re-runnable);
-- the CHECK constraints and DROP NOT NULL are one-shot.
--
-- Same rationale as captain-ordering-migration.sql: ddl-auto=update only ADDS,
-- it never drops NOT NULLs or creates CHECK constraints / partial indexes. This
-- migration is required regardless of boot order.
--
-- qr_token itself is NOT backfilled here (no pgcrypto gen_random_bytes available
-- by default on Neon) — QrTokenBackfillRunner (Java, boot-time) generates and
-- persists a token for every shop_tables row where qr_token IS NULL.
--
-- Reflects the gate-redesign (project_guest_qr_gate_redesign, 2026-08-03): approval
-- lives on table_checks (§3b), not per-order — guest_sessions has no OTP columns.
-- Since this migration had never been run, the shape below was rewritten in place
-- rather than layered on top of the original design.
-- ============================================================

BEGIN;

-- 1. shop_tables: per-table QR token (D1 — stored random token, not HMAC) --------
ALTER TABLE public.shop_tables
  ADD COLUMN IF NOT EXISTS qr_token             varchar(64),
  ADD COLUMN IF NOT EXISTS qr_token_rotated_at  bigint;

CREATE UNIQUE INDEX IF NOT EXISTS uq_shop_tables_qr_token
  ON public.shop_tables (qr_token)
  WHERE qr_token IS NOT NULL;

-- 2. shops: the guest-ordering feature gate (separate from pos_enabled; guest
--    ordering requires BOTH) -----------------------------------------------------
ALTER TABLE public.shops
  ADD COLUMN IF NOT EXISTS guest_ordering_enabled boolean NOT NULL DEFAULT false;

-- 3. table_checks: allow a guest to be the opener ------------------------------
ALTER TABLE public.table_checks
  ADD COLUMN IF NOT EXISTS opened_by_guest_session_id uuid;

ALTER TABLE public.table_checks ALTER COLUMN opened_by_staff_id DROP NOT NULL;

-- Exactly one owner — makes the new NULL meaningful and enforced, not just permitted.
ALTER TABLE public.table_checks
  ADD CONSTRAINT chk_table_checks_opener CHECK (
    (opened_by_staff_id IS NOT NULL AND opened_by_guest_session_id IS NULL) OR
    (opened_by_staff_id IS NULL AND opened_by_guest_session_id IS NOT NULL)
  );

-- 3b. table_checks: the trust gate moves HERE (per-table-session), not per-order.
--     Staff approve once when a guest session opens; every order after that fires
--     straight through. NULL for every staff-opened check (the CHECK below makes that
--     the only legal state when there's no guest opener).
ALTER TABLE public.table_checks
  ADD COLUMN IF NOT EXISTS guest_approval_status     varchar(20),
  ADD COLUMN IF NOT EXISTS guest_approved_by_staff_id uuid,
  ADD COLUMN IF NOT EXISTS guest_approved_at          bigint,
  ADD COLUMN IF NOT EXISTS guest_decision_reason      varchar(255),
  ADD COLUMN IF NOT EXISTS guest_join_code            varchar(8);

ALTER TABLE public.table_checks
  ADD CONSTRAINT chk_table_checks_guest_approval CHECK (
    (opened_by_guest_session_id IS NOT NULL AND guest_approval_status IN ('PENDING','APPROVED','REJECTED')) OR
    (opened_by_guest_session_id IS NULL AND guest_approval_status IS NULL)
  );

-- 4. orders: widen order_source to include GUEST (D5) --------------------------
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS chk_orders_source;
ALTER TABLE public.orders
  ADD CONSTRAINT chk_orders_source CHECK (order_source IN ('CUSTOMER','STAFF','GUEST'));

-- 5. guest_sessions: a guest's table-scoped session (never a users row). No OTP —
--    the trust gate lives on table_checks.guest_approval_status instead (§3b); phone
--    is an optional contact field, never a verification gate.
CREATE TABLE IF NOT EXISTS public.guest_sessions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id          uuid          NOT NULL,               -- shared-id ref, no FK
  table_id         uuid          NOT NULL,               -- shared-id ref to shop_tables
  -- Nullable for one instant within startSession's transaction only (the check needs
  -- this session's id as ITS opener before this column can be set) — never observable
  -- outside that transaction. joinSession sets it immediately (the check already exists).
  check_id         uuid,
  phone            varchar(15),                          -- optional contact field, not a gate
  token_hash       varchar(128)  NOT NULL,                -- SHA-256 hex of the opaque session token, set at creation
  created_on       bigint        NOT NULL DEFAULT (extract(epoch from now())*1000)::bigint,
  expires_at       bigint        NOT NULL,
  revoked_at       bigint
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_guest_sessions_token_hash
  ON public.guest_sessions (token_hash)
  WHERE token_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_guest_sessions_shop_expiry ON public.guest_sessions (shop_id, expires_at);

-- 6. guest_order_requests: audit log of fired guest orders (D4 — NOT a new
--    OrderStatus). The approval gate moved to table_checks (§3b) — this table no
--    longer holds anything PENDING; a row is written already-APPROVED the instant an
--    order fires (decided_by_staff_id NULL = auto-fired post table-approval, not a
--    per-order staff decision). PENDING/EXPIRED remain legal enum values for schema
--    stability but are never written going forward.
CREATE TABLE IF NOT EXISTS public.guest_order_requests (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  guest_session_id    uuid          NOT NULL,
  shop_id             uuid          NOT NULL,
  check_id            uuid          NOT NULL,
  payload             text          NOT NULL,             -- JSON-serialized KotItemRequest[] — NOT priced (D5 note)
  status              varchar(20)   NOT NULL DEFAULT 'PENDING',
  fired_order_id      uuid,                                -- set on APPROVED
  decided_by_staff_id uuid,
  decision_reason     varchar(255),
  decided_at          bigint,
  created_on          bigint        NOT NULL DEFAULT (extract(epoch from now())*1000)::bigint
);
ALTER TABLE public.guest_order_requests
  ADD CONSTRAINT chk_guest_order_requests_status CHECK (status IN ('PENDING','APPROVED','REJECTED','EXPIRED'));
CREATE INDEX IF NOT EXISTS idx_guest_order_requests_shop_status
  ON public.guest_order_requests (shop_id, status, created_on);

COMMIT;

-- Rollback note: once GUEST-sourced orders exist, chk_orders_source cannot be
-- narrowed back to ('CUSTOMER','STAFF') without cleaning those rows first.
