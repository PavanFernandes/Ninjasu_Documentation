-- Widens chk_table_checks_guest_approval to allow a third legal state: a staff-opened
-- check (opened_by_guest_session_id IS NULL) that staff has since invited guests onto
-- via enableGuestJoin — guest_join_code + guest_approval_status get set, but there is
-- still no guest_session opener. The original guest-qr-ordering-migration.sql only
-- allowed guest-opened-with-status OR staff-opened-with-nothing.

ALTER TABLE public.table_checks
  DROP CONSTRAINT chk_table_checks_guest_approval;

ALTER TABLE public.table_checks
  ADD CONSTRAINT chk_table_checks_guest_approval CHECK (
    (opened_by_guest_session_id IS NOT NULL AND guest_approval_status IN ('PENDING','APPROVED','REJECTED')) OR
    (opened_by_guest_session_id IS NULL AND guest_join_code IS NOT NULL AND guest_approval_status IN ('PENDING','APPROVED','REJECTED')) OR
    (opened_by_guest_session_id IS NULL AND guest_join_code IS NULL AND guest_approval_status IS NULL)
  );
