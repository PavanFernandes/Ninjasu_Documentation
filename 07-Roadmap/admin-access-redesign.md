---
id: ""
title: "Platform staff access redesign (admin + area ops) — devil's advocate"
summary: "Moves platform ADMIN out of users.roles into a platform_staff table that also holds Schedule area roles, gives staff their own login, token and website, and names the shared non-shop audit table. Includes the current-state risks, verdicts, effort and build order."
type: how-to
status: proposed
apps: [backend, web]
module: "auth"
anchors: []
verified_against: "backend main @ b428324; Ninjasu_Web main @ 21c8a95 (2026-10-08)"
updated: 2026-10-08
---

# Platform staff access redesign

> **Decision 2026-10-08 (supersedes Proposal 1 below):** admin is one person (Samivan, developer superuser). Admin access comes from a `PLATFORM_ADMIN_USER_IDS` server setting, validated at boot (malformed = refuse to start, empty = no admin); `users.roles` is no longer read for ADMIN and stale entries are stripped after cutover. No `platform_staff` table. Schedule area roles are a separate audience designed in Schedule Phase 3. Topics 2–4 (admin login/token, subdomain, `platform_audit_events`) are being decided one at a time.

Raised by Samivan 2026-10-08: stop deriving admin from the `users.roles` array; a separate table decides
access while `users` alone keeps owning the OTP login; admin gets its own URL, login and JWT secret instead
of the in-app role switch.

## Current state (verified in code)

- **ADMIN lives in `users.roles` (text[])**, next to USER, SHOP, RIDER. Checked by URL matchers
  (`hasRole("ADMIN")`, ~40 in `SecurityConfig`) and by five hand-written `getRoles().contains("ADMIN")` checks
  (`PermissionServiceImpl:31`, `AuditRecorderImpl:62`, `ShopTableServiceImpl:192`, `UploadController:63`,
  `UserServiceImpl:178`).
- **Nine code paths write `users.roles`**: user create, rider signup (`UserServiceImpl:58,76-86`), admin
  create/update user (`:143-191`), shop owner upsert (`ShopServiceImpl:126-136`), invite consumption
  (`AuthServiceImpl:490`), role admin (`RoleAdminServiceImpl:192,243`), membership backfill. "ADMIN is
  DB-grant-only" is enforced only by filter code in two of them. Each future writer is a new escalation risk;
  the rider-OTP takeover (PR #37) is the same family.
- **Authorities are rebuilt from the DB on every request** (`JwtAuthFilter:50-56`). Good: revocation is immediate
  and a forged `roles` claim is ignored.
- **One JWT for everyone**: one secret, 7-day expiry (`app.jwt.expiration-ms=604800000`), subject = user id.
- **The JWT secret has a known default** (`app.jwt.secret=${APP_JWT_SECRET:ZGVm...}`). If production does not
  set `APP_JWT_SECRET`, anyone can sign a token with any user id as subject, including an admin's.
- **Admin login is the ordinary OTP login**, so it inherits whatever `OTP_PHONE_PROVIDER` is set to. With `dev`,
  every account (admin included) accepts the fixed code 1234.
- **Web**: one site; `RoleSwitcher` toggles admin and shop views in the same session; `proxy.ts` checks the
  `roles` claim for routing (UX only; the backend enforces).

## Verdicts

> **Proposal 0 — check the two production settings now**
> **Failure scenario:** production runs on the default JWT secret (anyone mints an admin token) or on the `dev`
> OTP provider (anyone logs in as admin with 1234).
> **Mitigation:** confirm in the EC2/Docker env that `APP_JWT_SECRET` is set to a private value and
> `OTP_PHONE_PROVIDER=messagecentral`. Then remove the default secret so boot fails if it is unset (same
> fail-closed pattern as the OTP provider check).
> **Verdict:** `proceed` immediately. Effort: minutes to check, XS to remove the default.

> **Proposal 1 — a separate access table instead of `users.roles` for admin**
> **Failure scenarios if skipped:** any of the nine role writers, or a new one, can put ADMIN in the array
> through a missed filter. **Failure scenarios of the change:** existing admins locked out on deploy if not
> migrated; the five hand-written checks and ~40 matchers drift if some keep reading the array.
> **Mitigation:**
> - **One table for all platform staff, not admin only:** `platform_staff (user_id, role, service_area_id)`
>   with roles `ADMIN`, `AREA_MANAGER`, `AREA_OPS`. CHECK: ADMIN has no area; area roles must have one. This
>   also replaces the planned `service_area_members` (Schedule P2): one access model, not two.
> - No API writes this table in v1: grants are SQL, as ADMIN is today, but now structurally rather than by
>   filter code. Revoke = delete the row (no `revoked_at`, which would be an implicit filter every reader must
>   remember); the grant/revoke is recorded in the platform audit table.
> - One `PlatformStaffService` answers every "is admin / may act on area X" question; the five hand-written
>   checks call it. The filter maps a staff token (Proposal 2) to `ROLE_ADMIN` / `ROLE_OPS` authorities from this
>   table, so the existing matchers keep working.
> - Migration: insert a row for every user whose array holds ADMIN, deploy, verify login, then strip ADMIN from
>   the arrays and remove the five array checks. A test fails if any code reads `"ADMIN"` from `users.roles`.
> - `users` remains the only identity and OTP table, as requested.
> **Verdict:** `proceed with conditions`. Effort: **S-M, about 1-2 days** backend.

> **Proposal 2 — separate staff login and token**
> **Failure scenarios if skipped:** a customer or shop token is accepted on admin endpoints whenever a matcher
> or check is wrong; admin sessions last 7 days; admin login is weakened by any OTP dev setting.
> **Failure scenarios of the change:** the ~20 "SHOP or ADMIN" endpoints (menu, stock, purchases, uploads, audit
> reads, pos-settings) must accept two token kinds; a bug in choosing the key per token could accept a token
> signed by the wrong secret.
> **Mitigation:**
> - Login endpoint `/api/staff-auth/*`: the same `users` OTP, but **always the real SMS provider** (the dev
>   provider is refused here, fail closed), then a `platform_staff` check, then a staff token.
> - Staff token: **own secret**, `aud=staff`, **short expiry (about 12 h)**, no refresh in v1. The filter picks
>   the verification key by audience; an unknown audience is rejected. Customer and shop tokens are refused on
>   `/api/admin/**` and `/api/ops/**`; staff tokens are refused on customer endpoints. On the mixed shop
>   endpoints both are accepted, a staff token carrying only staff authorities (never SHOP).
> - Own secret lets you rotate staff sessions (a lost laptop) without logging out every customer and shop.
> **Verdict:** `proceed with conditions`. Effort: **M, about 2-3 days** backend including tests.

> **Proposal 3 — separate staff website**
> **Failure scenarios if skipped:** admin and shop UI share one origin and storage, so any script injection on a
> shop page (menu names and other shop-entered text) can reach an admin session; admin code ships to every shop
> user; the role switch keeps both powers in one browser session.
> **Mitigation:**
> - **Same Next.js codebase, separate host** (e.g. `console.ninjasu.com`): `proxy.ts` routes by host; the staff
>   token cookie is scoped to that host only; staff login page there; the RoleSwitcher's admin option is removed.
>   A person who is both admin and shop owner signs in to each site separately.
> - Later, cheaply: stricter CSP, no indexing, optional IP allow-list on the console host.
> - A separate repo/app is unnecessary now; split only if the console grows its own release cadence.
> - Infra: DNS record + nginx server block + certificate (watch the 20 GB EC2 disk and cert-renewal history).
> - The Schedule ops board (Phase 3) lives on this console; area roles see only their areas.
> **Verdict:** `proceed with conditions`. Effort: **M, about 2-4 days** web + infra.

> **Proposal 4 — audit table name**
> **Decision:** **`platform_audit_events`**, the name the audit-log plan already reserved for non-shop actions.
> Scope column `PLATFORM | SERVICE_AREA` plus nullable `service_area_id` with a CHECK tying them together, and an
> optional `shop_id` when the action concerns a shop's order. It records admin actions (shops, users, zones,
> staff grants) and area ops actions (slots, batches, refunds) in one place. `audit_events` stays shop-only.
> **Verdict:** `proceed`. Supersedes "area_audit_events" in schedule-design-review.md (D8).

> **Proposal 5 — "nothing hardcoded, editable by super admin" for notification text**
> **Failure scenario of over-applying it:** an admin-editable template table with placeholders: a typo or a
> removed placeholder breaks every shop alarm at once, and the copy needs validation, preview and language
> handling.
> **Mitigation:** split by kind.
> - **Business settings** (fees, slots, capacity, cutoffs, modes per area, commission) are admin-editable data.
>   They already are in the Schedule plan.
> - **Message wording** stays in code, in one place per message, and is **built from the order's data**: the shop
>   alert shows the order's actual payment method instead of a fixed "COD".
> - Editable templates only if a real need appears (M effort then).
> **Verdict:** `proceed with conditions` (data-driven copy now, templates deferred).

## Build order and total effort

| Step | What | Effort |
|---|---|---|
| 0 | Check prod `APP_JWT_SECRET` and `OTP_PHONE_PROVIDER`; remove default secret | minutes + XS |
| 1 | `platform_staff` + `PlatformStaffService`, migrate admins | 1-2 days |
| 2 | Staff login + staff token (own secret, short expiry, real OTP only) | 2-3 days |
| 3 | Console host in Ninjasu_Web, staff login page, drop admin from RoleSwitcher | 2-4 days + DNS/cert |
| 4 | `platform_audit_events` (with Schedule Phase 2) | part of Phase 2 |

Total about **1-1.5 weeks**. Steps 1-3 should land **before Schedule Phase 2**, because `/api/ops`, the area
roles and the ops board are built on them.

## Related fixes queued (not access-related)

- **Stock ledger credit leak** (verified): an order takes stock from whichever ledger row is open, but a cancel
  gives it back to the row whose date matches the order's calendar date. Between midnight and 3 AM IST the open
  row is still yesterday's, and a one-time batch's row is dated the day it was opened, so in both cases the
  cancel finds no matching row and the stock is lost. Fix: record the ledger row id on the order line when stock
  is taken (`UPDATE ... RETURNING id`) and credit that exact row; orders without the id keep today's behaviour.
  Effort XS-S.
- **Dead query** `OrderRepository.findActiveByShopId`: lists a shop's active orders but does not exclude unpaid
  checkouts. Nothing calls it today; delete it so nobody revives it.
- **Shop alert text** says "COD" for prepaid orders: build it from the order's payment method (Proposal 5).

## Revision 2 — devil's advocate on the decided shape (2026-10-08)

**Decided so far:** admin = Samivan via `PLATFORM_ADMIN_USER_IDS`; admin power only on tokens from the admin
login; admin login always uses the real SMS provider; one authentication filter (Samivan's "middleware")
handles both token kinds so the ~20 shared shop/admin endpoints stay unchanged.

### Improvement vs today

| Risk | Today | After |
|---|---|---|
| A bug in any of 9 `users.roles` writers makes someone admin | Possible (only 2 filter ADMIN) | Impossible: admin comes from the server setting + admin login only |
| Samivan's 7-day customer-app token is an admin token | Yes | No: customer/shop tokens carry no admin power |
| Admin session lifetime | 7 days | ~12 h |
| Admin login weakened by `OTP_PHONE_PROVIDER=dev` | Yes (code 1234) | No: admin login refuses the dev provider |
| Log out admin everywhere without logging out customers | No | Yes: rotate the admin secret |
| JWT secret has a known default | Yes | Both secrets fail boot if unset |

### Where it could regress, and the condition that prevents it

> **R1 — admin power leaks back through service-level checks.** Five places check `user.getRoles().contains("ADMIN")`
> (`PermissionServiceImpl:31`, `AuditRecorderImpl:62`, `ShopTableServiceImpl:192`, `UploadController:63`,
> `UserServiceImpl:178`). If they are rewritten as "is this user id in the admin setting", a customer token for
> Samivan's id regains admin power on those paths and the token separation is defeated.
> **Condition:** admin is a property of the **request**, not the user: the filter grants `ROLE_ADMIN` only for a
> verified admin token, and one helper `isAdminRequest()` reads that authority. All five call sites use it. A test
> fails if any code reads `"ADMIN"` from `users.roles`.

> **R2 — the filter picks the verification key from an unverified claim.**
> **Condition:** verify with the admin secret, else with the user secret; then require the token's audience to
> match the secret that verified it; reject unknown or missing audience. Unit tests for every combination (admin
> token / user token × admin endpoint / shared endpoint / customer endpoint × wrong audience × expired).

> **R3 — the admin login becomes an SMS-cost and enumeration target.** Anyone can call it with any phone.
> **Condition:** send an SMS only if the phone belongs to a listed admin; return the same response either way; the
> existing per-phone rate limit plus a tight per-IP limit on this endpoint.

> **R4 — lockout by misconfiguration.** A typo in `PLATFORM_ADMIN_USER_IDS` means no admin.
> **Condition:** boot fails on malformed ids; log the count of admin ids at boot; recovery is edit setting + restart.
> Accepted (fail-closed beats fail-open).

> **R5 — clients that route by the `roles` array.** The RN app's AuthGuard sends users with an admin role to the
> `(admin)` panel; Ninjasu_Web `proxy.ts` gates the admin area on the `roles` claim; `RoleSwitcher` toggles admin.
> Stripping ADMIN from `users.roles` changes all three.
> **Condition:** depends on the open question below. Web: admin area only on the admin subdomain, gated on an admin
> token. RN: hide/remove the admin screens, or give them the admin login. Strip ADMIN from `users.roles` only after
> the clients stop reading it.

> **R6 — audit actor misattributed.** `AuditRecorderImpl` labels `PLATFORM_ADMIN` from the roles array.
> **Condition:** label from `isAdminRequest()` (R1), so Samivan acting through a shop login is recorded as staff,
> and through the admin login as platform admin.

> **R7 — tokens issued before the cutover.** Existing 7-day tokens for Samivan lose admin power on deploy.
> **Accepted:** desired behaviour; sign in on the admin subdomain afterwards.

> **R8 — UX cost.** Re-login about twice a day for admin work.
> **Accepted:** the price of a 12 h admin session; revisit only if it hurts.

**Verdict:** `proceed with conditions` (R1-R6). This is an improvement on every security axis above; the only
regressions are UX (R7, R8), both accepted.

**Open question:** are the RN app's admin screens (`app/(admin)/` shop create/edit/view) still used, or is web admin
enough? Decides R5 and whether a powerful token ever lives on a phone.

### Revised effort (one-person admin)

| Step | What | Effort |
|---|---|---|
| 0 | Confirm prod `APP_JWT_SECRET` set and `OTP_PHONE_PROVIDER` not dev; check who has ADMIN in the DB today | minutes |
| 1 | `PLATFORM_ADMIN_USER_IDS` + `isAdminRequest()` + rewire the five checks + roles-read test | ~1 day |
| 2 | Admin login (real SMS only, admin-phone-only send, rate limit) + admin token + the one filter + tests | ~2 days |
| 3 | Web: admin area on a subdomain of the same app, admin-token cookie for that host only, RoleSwitcher loses admin | ~2-3 days + DNS/cert |
| 4 | RN admin screens per the open question; then strip ADMIN from `users.roles` | 0.5-1 day |

Total about one week. `platform_audit_events` (topic 4) lands with Schedule Phase 2.

## Revision 3 — decisions 2026-10-08 (final for now)

- **Admin token lifetime: 7 days** (Samivan's call), configurable via `ADMIN_TOKEN_TTL` so it can be shortened
  without code. Noted trade-off: a login-alert email does not detect use of a stolen token (no new login occurs);
  the mitigation is rotating the admin secret, which ends every admin session without affecting customers/shops.
  Supersedes the "~12 h" in Revision 2 and R8.
- **Admin login = password + SMS OTP** (two factors: know + have). Password **hashed with bcrypt** (the PIN login
  already uses it), never reversible encryption. Hash lives in the `PLATFORM_ADMIN_PASSWORD_HASH` server setting
  next to `PLATFORM_ADMIN_USER_IDS`; no table, no API writes it. Minimum 12 characters; lock the admin login after a
  few failed attempts. **No forgot-password flow**: recovery = generate a new hash, update the setting, restart.
  Effort +0.5-1 day.
- **Deferred:** email alert to admins on every admin login.
- Samivan: "this much secure is fine" — admin hardening scope is closed at this level.
- Still open: RN admin screens kept or web-only (R5); step 0 production checks.
- **R5 resolved (2026-10-08): admin is removed from the RN app.** Delete `app/(admin)/` (shops, shop-form,
  shop-view, cuisines, profile) and the `ADMIN` branches in `src/utils/roleHome.ts`, the root AuthGuard
  (`app/_layout.tsx` roleAreas) and the Profile role switcher / admin tab config. **Keep** shared code that
  `(shop)` uses: `src/features/admin/services/shop.service.ts` (`getMyShop`, used by `useShopId`) and whatever
  `app/(shop)/shop.tsx` and `orders.tsx` import from `src/features/admin`. Admin lives only on the web subdomain,
  so an admin token never sits on a phone. Effort ~0.5 day.

## Build spec (2026-10-08) — the contract all three changes code against

### Server settings (backend)
| Setting | Meaning | If missing/invalid |
|---|---|---|
| `PLATFORM_ADMIN_USER_IDS` | comma-separated user UUIDs who are platform admin | malformed → refuse to start; empty → no admin (log count at boot) |
| `PLATFORM_ADMIN_PASSWORD_HASH` | bcrypt hash of the admin password | missing/not bcrypt → admin login disabled (log loudly); app still starts |
| `ADMIN_JWT_SECRET` | signing secret for admin tokens, base64, ≥ 256 bits | missing → refuse to start |
| `ADMIN_TOKEN_TTL` | admin token lifetime, ms | default 604800000 (7 days) |
| `APP_JWT_SECRET` | existing user-token secret | **default fallback removed** → refuse to start if unset |

### Admin login API (public, rate-limited)
1. `POST /api/admin-auth/start` `{ phone, password }`
   - Proceeds only if `phone` belongs to a user whose id is in `PLATFORM_ADMIN_USER_IDS` **and** bcrypt matches.
     Only then sends an SMS OTP through the **real** provider (Message Central) — the `dev` provider is refused
     here even if configured globally (fail closed: 503 "admin login unavailable").
   - Same response body and status whether or not the phone/password matched (no enumeration). Password checked
     before any SMS, so wrong passwords never cost an SMS.
   - Lockout: 5 failed password attempts per phone (and per IP) → 15 min block; in-memory is fine (single host).
   - OTP state reuses the `users` row fields the normal SMS login already uses (one OTP table).
2. `POST /api/admin-auth/verify` `{ phone, otp }` → verifies via Message Central; re-checks the user is still in
   the admin list → returns `{ token, expiresAt }`.
   - Admin token: HMAC with `ADMIN_JWT_SECRET`, claims `sub=userId`, `aud="admin"`, `iat`, `exp=now+ADMIN_TOKEN_TTL`.
     No roles claim (power is decided server-side).

### The one authentication filter
- Verify the bearer token with `ADMIN_JWT_SECRET`; if that fails, with `APP_JWT_SECRET`. Never read claims to
  choose the key. Then:
  - Verified by admin secret: require `aud == "admin"` and `sub` currently in `PLATFORM_ADMIN_USER_IDS`, else 401.
    Authorities: **`ROLE_ADMIN` only**. Principal = that `User`.
  - Verified by user secret: require `aud` absent (existing tokens) or `"user"`. Authorities = `users.roles` with
    any `"ADMIN"` entry **dropped**. Principal = that `User`.
- New user tokens get `aud="user"`.
- `isAdminRequest()` helper (one place) = current authentication has `ROLE_ADMIN`. **Admin is a property of the
  request, never of the user record or the user id.**
- Rewire every `getRoles().contains("ADMIN")` to `isAdminRequest()`: `PermissionServiceImpl:31`,
  `AuditRecorderImpl:62` (actor PLATFORM_ADMIN only for admin requests), `ShopTableServiceImpl:192`,
  `UploadController:63`. `UserServiceImpl` create/update user: always strip `"ADMIN"` from requested roles and
  never re-add it (the "wasAdmin" preservation is removed — admin no longer lives in roles).
- Test: fails if any production code reads `"ADMIN"` out of `users.roles`; filter tests for every combination
  (admin/user token × admin endpoint / shared SHOP-or-ADMIN endpoint / customer endpoint × wrong aud × expired ×
  admin removed from the setting).
- Every new mutating endpoint: `@NotAudited("auth")` or `@AuditedEndpoint` so `AuditEndpointDeclarationTest` passes.

### Web (Ninjasu_Web)
- Admin area served only on the admin subdomain of the same app (e.g. `admin.<web host>`; locally
  `admin.localhost:<port>`). `proxy.ts` routes by host: admin host → only `/admin/**` + `/admin/login`, requires the
  admin session cookie; main host → `/admin/**` is not served (404 or redirect to the admin host).
- Admin session cookie: separate name (e.g. `ninjasu_admin_session`), host-only (no `Domain` attribute),
  `HttpOnly`, `Secure`, `SameSite=Strict`, holds the admin token; forwarded to Spring the same way the user session is.
- `/admin/login`: phone + password → OTP step → set cookie → `/admin`.
- `RoleSwitcher` drops the admin option; nothing on the main host links to admin.

### RN app (Food-Ninja-Frontend)
- Delete `app/(admin)/`; remove `ADMIN` from `roleHome.ts`, the root AuthGuard `roleAreas`, the Profile role
  switcher, and the admin tab config. Keep `src/features/admin/**` code that `(shop)` or POS uses.

### Release order
1. Confirm prod `APP_JWT_SECRET` is set (the default is removed — an unset value now stops boot) and list who
   has ADMIN in the DB.
2. Set `PLATFORM_ADMIN_USER_IDS`, `PLATFORM_ADMIN_PASSWORD_HASH`, `ADMIN_JWT_SECRET` on the backend host; DNS +
   nginx + certificate for the admin subdomain.
3. Merge backend + web together (the old web admin stops working the moment the backend deploys); RN any time.
4. After both clients are live: SQL strip `"ADMIN"` from `users.roles`.
