# Roles & Permissions (shop-scoped RBAC)

**Status:** SPEC v2 — reviewed by Codex 2026-09-25 (10 must-fix findings folded in). Not built.
Supersedes the hardcoded `ShopRoles.java` sets. DA conditions: memory `followup_roles_permissions_da`.

## Why
Clients need to restrict what staff can do: waiters must not void a fired KOT or write off bills, reports must be hideable, a chef sees only the kitchen, a CA only reports, a marketing person only marketing. Permissions differ per restaurant, so they cannot be hardcoded in Java.

## Model (decided)
- **Permission** = a named ACTION key from a **code-defined catalog** (Java enum). Never an owner-editable table; never generic CRUD verbs.
- **Role** = a per-shop named set of permissions. Seeded per shop from templates; the owner edits their own copy and can create / duplicate / delete roles.
- **A member holds ≥1 roles; effective permissions = UNION.** No deny rules, no per-user grants, no policy language.
- **Owner** = exactly one per shop, `user_shops.is_owner`, implicitly holds every permission, immutable (no role change/removal). **Admin** is a normal seeded role (partners/co-owners): everything except owner-only actions.
- **Global JWT roles are unchanged and separate:** `SHOP`, platform `ADMIN`, `RIDER` (SecurityConfig). The per-shop "Admin" role is NOT `ROLE_ADMIN`. Platform ADMIN keeps the bypasses it has today (see "Platform ADMIN bypass").
- **Out of scope:** manager-PIN / WhatsApp approval (later), per-user grants, deny rules, station scoping (scope ≠ permission).

## Tables
```
shop_roles            (id uuid pk, shop_id uuid NOT NULL, name varchar(40) NOT NULL,
                       template_key varchar(20) NULL, created_at)
                      CREATE UNIQUE INDEX ux_shop_roles_name ON shop_roles (shop_id, lower(name));
                      CREATE INDEX ix_shop_roles_shop ON shop_roles (shop_id);
shop_role_permissions (role_id uuid FK→shop_roles ON DELETE CASCADE, permission_key varchar(60))
                      PK (role_id, permission_key)
user_shop_roles       (user_shop_id uuid FK→user_shops ON DELETE CASCADE,
                       role_id uuid FK→shop_roles ON DELETE RESTRICT)      -- RESTRICT ⇒ role with members can't be deleted
                      PK (user_shop_id, role_id);  CREATE INDEX ix_usr_role ON user_shop_roles (role_id);
shop_invite_roles     (invite_id uuid FK→shop_invites ON DELETE CASCADE,
                       role_id uuid FK→shop_roles ON DELETE CASCADE)       -- deleted role drops from pending invites
                      PK (invite_id, role_id)
user_shops            + is_owner boolean NOT NULL DEFAULT false
                      CREATE UNIQUE INDEX ux_user_shops_owner ON user_shops (shop_id) WHERE is_owner;
                      legacy `role` column: DROP NOT NULL in the cutover SQL; unread + unwritten by new code; dropped in a later migration
shop_invites          legacy `role` column: DROP NOT NULL, same treatment
```
`shop_id` is a plain UUID (no FK to shops — cross-domain decoupling principle). FKs are only inside the RBAC domain.
`template_key` non-null ⇒ seeded from that template (drives new-permission backfill); duplicated/custom roles are `null`. Editing a seeded role keeps its `template_key` (so it still receives newly shipped permissions). Role names: trimmed, 1–40 chars, case-insensitive unique per shop.

## Permission catalog v1
Only actions with a real endpoint today. `X.manage` implies `X.view` where both exist (`menu.manage`⇒`menu.view`, `inventory.purchases.manage`⇒`inventory.purchases.view`, `tables.manage`⇒`floor.view`) — **normalized at save time** (server adds the view key when manage is present), not in the resolver.

| Module | Key | Gates |
|---|---|---|
| Online orders | `online_orders.manage` | delivery/online order list/detail/history/status; delivery ops (assign, reassign, cancel, force-complete, timeline, lookup, discrepancies); online rider list |
| Floor | `floor.view` | read floor: tables, checks, bill (any-of with `kds.view`) |
| | `floor.open_table` | open check; enable guest join; list/decide guest table approvals |
| | `floor.fire_kot` | fire a KOT |
| | `floor.serve` | serve/collect transitions; acknowledge waiter attention |
| | `floor.void_kot` | void a whole KOT / takeaway order (voidKot, voidTakeaway) |
| | `floor.settle_bill` | record payment |
| | `floor.void_bill` | write off a check; settle a written-off bill (same authority) |
| Takeaway | `takeaway.manage` | fire takeaway |
| Kitchen | `kds.view` | KDS feed; also satisfies floor reads (any-of) |
| | `kds.update_status` | →PREPARING / →READY transitions |
| | `kds.receive_alarm` | receives new-KOT alarm push |
| Reports | `reports.history.view` | completed dine-in check history |
| | `audit.view` | audit log: the shop activity list, a check's activity timeline, and the filter catalog. Admin-only: the owner (implicit) and the DEFAULT Admin template; no other seeded template holds it (LEGACY sets unchanged; existing Admin-template roles get it from `db_manual/audit-view-permission-backfill.sql`). An owner can still grant it to a custom role deliberately. See `07-Roadmap/audit-log-plan.md` |
| Inventory | `inventory.purchases.view` / `.manage` | purchase ledger read / write |
| | `inventory.stock.manage` | item stock quantities |
| Menu | `menu.view` / `menu.manage` | categories, items, addon groups; menu image upload |
| Setup | `tables.manage` | create/update/deactivate tables, regenerate QR |
| Team | `team.manage` | list members/invites, invite, cancel invite, remove member, assign member roles |
| | `roles.manage` | create/edit/duplicate/delete roles |

Not permissions (owner-only): enabling POS / guest-ordering (`setPosEnabled` — owner OR platform ADMIN), ownership transfer, delete shop. `settings.manage` is deliberately absent until a settings endpoint is gated by it.

## Endpoint → permission mapping (Phase 1, exhaustive; paths under `com.example.ninja`)
| Site | Today | New |
|---|---|---|
| `TableCheckServiceImpl.openCheck` | POS_FLOOR_ACTORS | `floor.open_table` |
| `.getCheck` | POS_VIEWERS | any-of(`floor.view`,`kds.view`,`reports.history.view`); a caller holding neither floor.view nor kds.view (history-only, e.g. Accountant) may open CLOSED checks only |
| `.listChecks` | POS_VIEWERS | any-of(`floor.view`,`kds.view`) |
| `.getCheckHistory` | POS_VIEWERS | `reports.history.view` |
| `.fireKot` | POS_FLOOR_ACTORS | `floor.fire_kot` |
| `.recordPayment` | POS_FLOOR_ACTORS | `floor.settle_bill` |
| `.writeOffCheck` | MANAGERS_AND_ABOVE | `floor.void_bill` |
| `.settleWrittenOffBill` | MANAGERS_AND_ABOVE | `floor.void_bill` |
| `.enableGuestJoin` | POS_FLOOR_ACTORS | `floor.open_table` |
| `.ackAttention` | POS_FLOOR_ACTORS | `floor.serve` |
| `BillServiceImpl.getForCheck` | POS_VIEWERS | any-of(`floor.view`,`kds.view`,`reports.history.view`); same history-only CLOSED-checks rule as getCheck |
| `GuestOrderServiceImpl.listPendingTables`, `.decideTable` | POS_FLOOR_ACTORS | `floor.open_table` |
| `PosOrderController.voidKot`, `.voidTakeaway` | POS_FLOOR_ACTORS | `floor.void_kot` |
| `PosOrderController.fireTakeaway` | POS_FLOOR_ACTORS | `takeaway.manage` |
| `PosOrderController.updateKotStatus`, `.updateTakeawayStatus` (`verifyKotTransitionRole`) | per-TARGET: cook→KITCHEN, serve/collect→FLOOR | →PREPARING/READY: `kds.update_status`; →SERVED: `floor.serve`; →COLLECTED (takeaway handover, counts as revenue): `floor.settle_bill` |
| `PosOrderController.getKdsFeed` | POS_VIEWERS | `kds.view` |
| `PosOrderController.getTakeawayOrders` (`GET /takeaway-orders`, new) | n/a | `takeaway.manage` — returns TAKEAWAY orders only; the Takeaway tab reads this, not /kds |
| `ShopTableServiceImpl.listTables` | POS_VIEWERS | any-of(`floor.view`,`kds.view`) |
| `.createTable/.regenerateQrToken/.updateTable/.deactivateTable` | MANAGERS_AND_ABOVE | `tables.manage` |
| `.setPosEnabled` | OWNER_ONLY (+platform ADMIN) | unchanged: `is_owner` OR platform ADMIN |
| `StockServiceImpl` (gate L51-53) | MANAGERS_AND_ABOVE (+platform ADMIN) | `inventory.stock.manage` (+platform ADMIN) |
| `PurchasingServiceImpl` private gate (L55-63) | MANAGERS_AND_ABOVE (+platform ADMIN) | reads → `inventory.purchases.view`; writes → `.manage` (per public method) (+platform ADMIN) |
| `MenuCategory/MenuItem/AddonGroup` `verifyAccess` | ANY_MEMBER (reads) / MANAGERS_AND_ABOVE (writes) (+platform ADMIN) | `menu.view` / `menu.manage` (+platform ADMIN) |
| `UploadController` L99 | MANAGERS_AND_ABOVE (+existing platform rules) | `menu.manage` (+existing platform rules) |
| `OrderServiceImpl` L228/243/285, `DeliveryServiceImpl` L98/543/596/635/687/707/732/753, `RiderServiceImpl` L97 | ANY_MEMBER | `online_orders.manage` |
| `ShopServiceImpl` invite/list members/pending invites/cancel invite/remove member/change role (all `requireOwner`) | OWNER | `team.manage` (owner implicit); role-content changes → `roles.manage` |
| `OrderNotificationListener` alarm (`kitchenAlarmTokens`) | CHEF, fallback OWNER/MANAGER | holders of `kds.receive_alarm`; if none: owner + holders of `kds.update_status` |
| `OrderNotificationListener` guest-approval push (`floorActorTokens`) | POS_FLOOR_ACTORS | holders of `floor.open_table` |
| `OrderNotificationListener` delivery new/cancel (`tokensForShop`) | every member | **unchanged: every member** (do not filter) |
| `AuthServiceImpl` invite accept (L423-440) | copies `invite.role` | copies `shop_invite_roles` → `user_shop_roles`; if none of the invite's roles still exist ⇒ invite is void (reject as expired). Existing member re-invited: membership left unchanged (as today) |
| `ShopServiceImpl.createShop` (L139) / `MembershipBackfillRunner` | sets role "OWNER" | set `is_owner=true` (no role row); createShop also seeds the 6 DEFAULT templates (Admin, Manager, Staff, Chef, Accountant, Cashier) |
| `getMyShop/getMyShops` `myRole` | membership.role | see "Legacy myRole" |

Implementation done-condition: `grep -rn "getRole()\|ShopRoles\.\|\"OWNER\"" src/main` returns nothing outside the deleted/legacy shim. Every POS action endpoint MUST use a specific key (never a broad one).

## Platform ADMIN bypass
`caller.getRoles().contains("ADMIN")` (global) is retained ONLY where it exists today: menu/category/addon (`verifyAccess`), stock, purchasing, `setPosEnabled`, uploads. Implemented as an explicit `requirePermissionOrPlatformAdmin(...)` used at exactly those sites; plain `requirePermission` has no bypass.

## Templates
Owner is implicit, not a role. **Two seed sets:**

**A. `LEGACY` set — used ONLY by the migration for EXISTING shops (behaviour-preserving; exactly reproduces today's access):**
- **Manager**: online_orders.manage, floor.view, floor.open_table, floor.fire_kot, floor.serve, floor.void_kot, floor.settle_bill, floor.void_bill, takeaway.manage, kds.view, kds.update_status, reports.history.view, inventory.purchases.view/manage, inventory.stock.manage, menu.view/manage, tables.manage
- **Staff**: online_orders.manage, floor.view, floor.open_table, floor.fire_kot, floor.serve, floor.void_kot, floor.settle_bill, takeaway.manage, kds.view, reports.history.view, menu.view
- **Chef**: kds.view, kds.update_status, kds.receive_alarm, reports.history.view
- (+ **Admin** and **Accountant** seeded for existing shops too, unassigned)

**B. `DEFAULT` set — seeded for NEW shops (least-privilege; owner edits):**
| | Admin | Manager | Staff | Chef | Accountant | Cashier |
|---|---|---|---|---|---|---|
| online_orders.manage | ✅ | ✅ | | | | |
| floor.view / serve | ✅ | ✅ | ✅ | | | ✅ |
| floor.open_table / fire_kot | ✅ | ✅ | ✅ | | | |
| floor.settle_bill | ✅ | ✅ | | | | ✅ |
| floor.void_kot / void_bill | ✅ | ✅ | | | | |
| takeaway.manage | ✅ | ✅ | ✅ | | | ✅ |
| kds.view / update_status | ✅ | ✅ | | ✅ | | |
| kds.receive_alarm | | | | ✅ | | |
| reports.history.view | ✅ | ✅ | | | ✅ | |
| inventory.purchases.view / manage | ✅ | ✅ | | | view only | |
| inventory.stock.manage | ✅ | ✅ | | | | |
| menu.view | ✅ | ✅ | ✅ | | | |
| menu.manage / tables.manage | ✅ | ✅ | | | | |
| team.manage / roles.manage | ✅ | | | | | |

**Staff (waiter/captain) does not settle bills or hand over takeaway (COLLECTED).** Settling belongs to Cashier, Manager, Admin and the owner. A Cashier cannot move a takeaway to READY (`kds.update_status`); the kitchen or a manager does. Takeaway has no tender/payment record — COLLECTED is the sale. Existing shops keep their LEGACY seeds; `db_manual/remove-staff-settle-bill.sql` (owner-run, after creating a Cashier from the template menu) removes `floor.settle_bill` from their Staff roles.

Owners of existing shops tighten their roles themselves; nothing narrows silently. The Admin template holds every catalog key EXCEPT `kds.receive_alarm` (a holder counts as a chef for alarm routing, so an Admin holding it would receive every kitchen alarm and defeat the no-chef fallback). Owner-only actions are not permissions, so Admin cannot perform them.

## Resolution & enforcement
- `PermissionService.effective(shopId, userId)`: owner ⇒ all keys; else one join `user_shops ⨝ user_shop_roles ⨝ shop_role_permissions`. Per request; no cache; no JWT claim ⇒ revocation immediate.
- `requirePermission(P)`, `requireAny(P…)`, `requirePermissionOrPlatformAdmin(P)`. Backend 403 is the real gate; UI only hides.
- Unknown `permission_key` in DB: ignored, WARN at startup.
- KOT status gating stays PER-TRANSITION (mapping table).

## Guards (privilege escalation) — all inside ONE transaction that first takes `PESSIMISTIC_WRITE` on the shop row
1. Cannot grant/assign a permission you do not hold (role edit, role assignment, invite).
2. Cannot change your own role assignments. **Non-owner callers cannot edit a role they themselves hold** (owner-only for such edits).
3. Only the owner may assign/edit a role containing `roles.manage` or `team.manage`.
4. Owner membership immutable; `ux_user_shops_owner` backs uniqueness.
5. Role deletion blocked while it has members OR pending invites (FK RESTRICT on members + friendly pre-checks; pending-invite links would otherwise silently cascade away and leave an invite that can never be accepted).
6. Non-owner members always keep ≥1 role (checked after the locked replace).
7. `kds.receive_alarm` is a notification-routing flag, not a privilege: rule 1 and the target-containment check ignore it, so a non-owner Admin (whose template lacks it) can still assign/edit the Chef role and manage Chefs.
The per-shop row lock serializes ALL RBAC mutations for that shop (rare, cheap) — eliminates the concurrent role-edit / assign / delete / last-role races.

## New permission rule
Shipping a feature adds enum key(s) + a migration adding ONLY those keys to roles whose `template_key` matches the DEFAULT template. Never re-sync existing keys. `template_key = null` roles get new keys OFF. Never rename keys — deprecate.

## Legacy `myRole` (shipped RN builds read it)
`GET /shops/my` keeps `myRole`, derived ONLY when the effective set ⊇ the full LEGACY bundle: `OWNER` if `is_owner`; else `MANAGER` if ⊇ LEGACY Manager; else `STAFF` if ⊇ LEGACY Staff; else `CHEF` if ⊇ LEGACY Chef; else `null` (old apps go view-only; new clients use `myPermissions`). Also returns `myPermissions: string[]`, `myRoleNames: string[]`.

## API
- `GET /api/shops/{shopId}/permissions/catalog`
- `GET/POST /api/shops/{shopId}/roles`, `PUT/DELETE .../roles/{roleId}`, `POST .../roles/{roleId}/duplicate`, `POST .../roles/from-template/{templateKey}`
- `PUT /api/shops/{shopId}/members/{userId}/roles` `{roleIds}` (replaces `PATCH .../role`); invite request takes `roleIds`
- Member listing returns roles + effective permissions with the granting role name.

## Cutover mechanism (matches this repo: `ddl-auto=update` + boot runners + hand-run SQL; no Flyway)
1. **Pre-deploy SQL** `Ninjasu_Documentation/attachments/roles-permissions-migration.sql`, idempotent, run by Samivan against Neon (after a backup; never from a dev machine by an agent):
   a. Preflight: for every shop, `shops.owner_id` is the owner source of truth. Abort (`RAISE EXCEPTION`) if a shop has no resolvable owner user. Mark that user's `user_shops` row `is_owner=true` (create it if missing). Any OTHER row with legacy role `OWNER` is remapped to the Admin role.
   b. Create tables/indexes; `ALTER ... DROP NOT NULL` on both legacy `role` columns.
   c. Seed LEGACY-set roles (+Admin, Accountant) ONLY for shops that have no roles yet (so a re-run never recreates roles an owner deleted/renamed; ids are supplied explicitly so it also works if Hibernate created the table first); map `MANAGER/STAFF/CHEF` memberships and pending invites to the matching role.
   d. Verification queries (must all return 0 rows): shops without exactly one owner; non-owner memberships without a role; pending invites without a valid role; role joins crossing shops; unknown permission keys.
2. **Fail-closed boot guard** (`RbacSchemaGuard`, refuses to start if a check fails; property `rbac.verify-on-boot`, default true): every shop has exactly one owner, every non-owner member has ≥1 role. NOT the non-fatal log-and-continue style of `MembershipBackfillRunner`.
3. Deploy backend with ALL gates converted in one release. Legacy `role` columns dropped in a later migration.

## Frontend
- **Ninjasu_Web:** Settings → "Staff & Roles": roles list, permission matrix grouped by module ("select all" per module), member multi-role picker, "Add role from template", "Duplicate role", effective-permissions view. Sidebar: ORDERS (Online Orders, Dine-In[Floor|Takeaway], Kitchen) / REPORTS (History) / INVENTORY (Purchases) / MANAGE (Menu, Tables, Staff & Roles, Settings). Hide, never grey; empty section header disappears; land on first permitted route; single permitted tab ⇒ no tab bar. `usePermissions()` replaces `useShopRole`.
- **RN app:** read `myPermissions`; chef lands on Kitchen.

## Build phases
1. **Backend foundation** — entities, migration SQL, `PermissionService`, all gates per the mapping, notification listener, invite accept, shop-create seeding, `myPermissions`, boot guard. **Behaviour-preserving; must be verified equivalent before Phase 2.**
2. **Roles admin API** + guards + team endpoints.
3. **Web** Staff & Roles UI + sidebar/gating.
4. **RN** gating.
