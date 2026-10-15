---
id: ""
title: "Audit Log — Phase 1 build notes & follow-ups"
summary: "What Phase 1 of the audit log actually shipped (branch feature/audit-log), where it deviates from the plan, what is unverified, the deploy-order requirement, and the endpoint backlog for later phases."
type: how-to
status: designing
apps: [backend]
module: "audit"
anchors: []
verified_against: "backend feature/audit-log @ 2026-09-27 (compile + 171 unit tests green; SQL never run on Postgres)"
updated: 2026-09-27
---

# Audit Log — Phase 1 build notes & follow-ups

Companion to [audit-log-plan.md](audit-log-plan.md) (the design). This file records what the build
actually did.

## Deploy order (blocking)

Run `db_manual/audit-events-migration.sql`, then `db_manual/audit-view-permission-backfill.sql`, **before**
deploying the backend. `audit_events` is excluded from `ddl-auto` (`AuditSchemaFilterProvider`) and recording is
fail-closed, so a missing table would make every audited action return 500. `AuditSchemaGuard` now fails boot with
a clear message if the table is absent (toggle: `audit.verify-on-boot`, default true).

## Deviations from the plan

1. `bill.refunded` is in the catalog but not emitted — `BillRefund` is schema-only (no refund writer/endpoint).
   Wire it in the change that introduces refunds.
2. Takeaway events use their own order as the root (`orders.check_id` is null for takeaway); dine-in KOT and all
   bill events use the CHECK.
3. `recordPayment` keeps its "all items must be served before settling" guard — a billing rule, do not remove.
   `bill.settled` carries `forceServedKotIds` (always empty today). Only `writeOffCheck` force-serves live KOTs; its
   `bill.written_off` event records their ids and never emits `kot.served` for them.
4. `audit.view` is granted by a separate idempotent backfill (`audit-view-permission-backfill.sql`); LEGACY seed
   grants are unchanged.
5. The entity maps only `id` as its `@Id`: Hibernate 7 rejects IDENTITY generation inside a composite id. The DB
   primary key stays `(id, occurred_at)`; the repository has no findById/save/update/delete.
6. List filters are plain repeated `module` / `action` params (Tomcat rejects unencoded `[]`); omitting a filter
   applies no restriction, so rows with a since-renamed module/action stay visible.
7. Guest events record `client=GUEST_WEB` but **no IP** — behind the proxy `getRemoteAddr()` is the proxy's address.
   Add IP once forwarded headers are configured.
8. The endpoint ratchet keeps all out-of-scope mutations on `src/test/resources/audit-endpoint-allowlist.txt`;
   only the two guest exclusions (`join`, `call-staff`) use `@NotAudited`.

## Known gaps / follow-ups

- Staff events carry no `client`, `ip` or `request_id` (needs plumbing from the controllers); Decision 1 wants
  `client`/`device_id` recorded so a shared-terminal switch can be interpreted later.
- `AuditRecorderImpl.record` re-reads user + membership + role names on every event (up to 3 queries per audited
  action on hot paths such as `fireOrder`); cache from `PermissionService` if it shows up in profiles.
- The cursor HMAC reuses `app.jwt.secret`; give it its own key if cursors ever outlive a JWT-secret rotation.
- Exhaustive one-test-per-action coverage is incomplete; add before merge if that is a hard gate.
- Unverified against a real Postgres: INET/JSONB binding, `GENERATED ALWAYS` identity insert, the append-only
  triggers, and the native `to_regclass` guard query. Run the migration + a test insert on a disposable DB first.
- Vault edits not yet made: Principle #21 in `principles-part3-hardening-stage-decisions.md` (wording is in the
  plan); an ADR once the design is locked.

## Endpoint backlog (on the allowlist — later phases)

**P3 Menu:** `AddonController` (add/update/availability/delete), `AddonGroupController` (create/update/delete),
`MenuCategoryController` (create/update/availability/delete), `MenuItemAddonGroupController` (link/unlink),
`MenuItemController` (create/update/availability/reassign/delete), `TaxClassController#assign`.

**P3 Stock & purchasing:** `StockController#patchStock`; `PurchasingController` (createPurchase, createMaterial,
updateMaterial, mergeMaterials, createUnit, createSupplier, deletePurchase).

**P3 Team, roles, settings:** `RoleController` (create/update/delete/duplicate/template/replace); `ShopController`
(createShop, addDeliveryConfig, addRestaurantDetails, activate/deactivate/update/delete, setBackgroundTemplate,
inviteMember, cancelInvite, removeMember, changeMemberRole); `PaymentTypeController` (create/update);
`PosSetupController#setPosEnabled`; `GuestBackgroundTemplateController` (create/update/delete).

**P3 Online orders & delivery staff ops:** `ShopOrderController#updateStatus`; `ShopDeliveryController`
(assign, reassign, cancel, forceComplete, reconcile) — via one `DeliveryAuditFacade`, since `transitionTo()` is not
the only delivery writer.

**Out of scope for the shop-scoped log (platform/global or non-decisions):** admin user/cuisine/zone/rider-affiliation
CRUD; auth/OTP/PIN/account; cart/wishlist/saved addresses; customer order/payment durability paths and the Razorpay
webhook; device/push; rider self-service and GPS.
