---
id: ADR-0017
type: decision
status: accepted
apps: [web, backend]
module: web-app
anchors: []
verified_against: ""
updated: 2026-07-17
---

# ADR-0017: Ninjasu_Web stack (Next.js) + BFF cookie auth

## Context

`Ninjasu_Web` is the platform's greenfield web client — one repo, four route-grouped audiences:
Ninjasu-team admin + shop/restaurant dashboard (built first), a public marketing site, and guest
QR-ordering (backlog). It is the desktop counterpart to the mobile `Food-Ninja-Frontend`, on the
same shared backend (see [[ADR-0016-multi-client-backend-boundary]]).

Two things forced explicit decisions:
- **Framework:** reusing the Expo app via react-native-web was rejected (principle 8: zero shared
  business logic; RNW is weak exactly where a dense desktop admin needs strength — data grids,
  multi-pane layouts). The real choice was Next.js vs a Vite SPA.
- **Auth is not mobile auth.** The mobile app carries the JWT as a Bearer header in AsyncStorage. On
  web that is an XSS liability for an *admin* surface, and a browser on Vercel talking to Spring on
  another origin raises CORS + cookie-SameSite complications the mobile app never had.

## Decision

**Stack: Next.js (App Router) + Tailwind + shadcn/ui.** Next over Vite because the marketing page and
guest-QR page genuinely benefit from server/static rendering, while admin/shop run as authenticated
SPAs within the same app. Audience isolation = route groups `(admin)` / `(shop)` / `(marketing)` /
`(guest)` + a `features/` split where only `shared/` is importable by all, enforced by an ESLint
import-boundary rule.

**Auth: BFF (backend-for-frontend) proxy.** All browser API calls go to Next.js Route Handlers
(`/app/api/...`) which read the JWT from an **httpOnly, Secure, SameSite=Lax cookie** and forward it
as a Bearer header to Spring. This single choice collapses three problems:
- **Token security** — the JWT is never readable by browser JS, so XSS cannot steal an admin session.
- **CORS** — the browser only ever calls its own origin; the Next↔Spring call is server-to-server, so
  no CORS config and no cross-site cookie issues.
- **Hosting** — web on Vercel and Spring anywhere else "just works."

Supporting decisions:
- **Refresh:** confirm the backend JWT lifetime; if no refresh-token flow exists, interim is a
  longer-lived access token (8–12h) so long data-entry sessions don't get bounced. Proper
  refresh-token rotation is a backend follow-up.
- **CSRF:** cookie-based auth reintroduces CSRF risk — SameSite=Lax + a double-submit CSRF token on
  mutating routes.
- **Role gating:** reuse the existing OWNER/MANAGER/STAFF/CHEF model via a `usePermissions()` helper
  in `shared/`; no new role model.
- **Menu images:** presigned-URL direct-to-S3 (`POST /api/.../uploads/presign` → key), matching the
  backend S3 key/URL rule — image bytes never stream through Next or Spring.
- **Guest QR (backlog):** an HMAC-signed table token in the QR URL
  (`/(guest)/t/{shopId}/{tableId}?sig=`) → a short-lived guest-session cookie scoped to that table's
  check → orders posted as `pending-approval`, released to the KOT only after staff approval.

## Consequences

- The BFF proxy is thin but real code: each Spring endpoint the browser needs is fronted by a Next
  route handler. Accepted — it is mechanical and buys token security + zero CORS.
- Web auth is deliberately different from the mobile Bearer/AsyncStorage model; the two are not
  shared code. The single session-end owner rule still applies conceptually (see memory
  `feedback_auth_single_persistence_owner`) but its web implementation is cookie-clearing in a Next
  route, not `clearUserData()`.
- Backend prerequisites this creates: JwtAuthFilter cookie support (or accept BFF-forwarded Bearer),
  token lifetime/refresh decision, presign endpoint, and (for guest, later) table-token signing +
  guest-scoped order endpoint. Ownership enforcement (ADR-0016 guardrail #4) gates the first
  admin/shop endpoint.

## Enforced in

Backend boundary this sits on: [[ADR-0016-multi-client-backend-boundary]]. Principle 8 (web primary,
mobile minimal; admin role/ownership). App map: [[Web-App-MOC]]. Existing auth context:
[[ADR-0009-pluggable-otp-auth]], [[ADR-0010-guest-browsing-gate-at-add-to-cart]]. Full phased build
plan + gap solutions: memory `project_ninjasu_web_plan`.

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
