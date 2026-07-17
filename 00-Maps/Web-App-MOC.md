---
id: ""
type: reference
status: active
apps: [web]
module: "meta"
anchors: []
verified_against: ""
updated: 2026-07-17
---

# Ninjasu Web — Map of Content

**Ninjasu_Web** — the platform's **web client**, the desktop counterpart to the mobile
`Food-Ninja-Frontend`. One repo, four route-grouped audiences: **Ninjasu-team admin** + **shop /
restaurant dashboard** (both being built now), a **public marketing site** (ninjasu.com landing),
and **guest QR-ordering** (backlog — table-QR → menu → order). **Not built yet** as of 2026-07-17 —
repo exists, no code. This stub exists so the vault's app coverage is complete and so anyone starting
the build lands on a page that already points at everything it shares with the rest of the platform.

## Scope being built (Phase 1 onward)

- **Admin (Ninjasu team):** shop/tenant onboarding + lifecycle, per-shop feature entitlements,
  taxonomy/cuisine management, platform user + internal-team roles, cross-shop order oversight,
  KPI home.
- **Shop (restaurant):** menu management, KDS ticket board + Floor board (web counterpart to mobile
  Captain Ordering — reuses the same endpoints/state, does not re-derive), staff management, order
  acceptance controls, payout/earnings, best-selling widget.
- **Marketing:** static landing (+ optional partner-signup feeding admin onboarding).
- **Guest QR-ordering:** backlog; needs a signed table-token + staff-approval gate before an
  unauthenticated order fires to the KOT.

Stack: Next.js (App Router) + Tailwind + shadcn/ui. Feature isolation by route group `(admin)` /
`(shop)` / `(marketing)` / `(guest)` + a `features/` split, only `shared/` importable by all.
Multi-client backend boundary (code-by-domain, API-by-audience-prefix) is the platform rule this
app sits on — see the `[BACKEND]` principles and the pending multi-client-backend ADR.

## What it will share with everything else

Ninjasu_Web is a new client on top of the **same shared backend** every other app
uses — it does not get its own domain rules or its own architecture. Read these first, before
designing anything web-specific:

- [Shared backend](../03-Backend/) — API contracts, auth, data model. Same envelope, same JWT
  auth, same endpoints (extended with `/api/admin/...` and `/api/pos/...`-scoped ones as needed) as
  the customer app and rider app use.
- [Shared domain rules](../02-Domain/) — menu, cart, wishlist, core, captain-ordering. These are
  true for every client; the web app renders and manages against them, it does not
  reinvent them.
- [Shared architecture principles](../01-Architecture/principles.md) — read the `[SHARED]` tagged
  principles, plus `[BACKEND]` ones for anything touching the boundary this app will sit on.

## Relevant decisions

This app's own foundational ADRs:

- [Multi-client backend — code by domain, API by audience](../01-Architecture/decisions/ADR-0016-multi-client-backend-boundary.md) — the backend boundary this and every other client sits on; carries 5 mandatory guardrails.
- [Ninjasu_Web stack (Next.js) + BFF cookie auth](../01-Architecture/decisions/ADR-0017-ninjasu-web-stack-and-auth.md) — framework, route-group isolation, httpOnly-cookie BFF auth, presigned image upload, guest table-token.

Existing ADRs whose subject matter this app sits directly on top of:

- [Order / OrderLine Snapshot-Pricing Schema (Risk 6)](../01-Architecture/decisions/ADR-0002-order-orderline-snapshot-pricing-schema.md) — order/sales data the dashboard will need to read and display correctly.
- [Restaurant vs Shop Entity Consolidation (Open Question, Risk 4)](../01-Architecture/decisions/ADR-0004-restaurant-vs-shop-entity-consolidation.md) — the Shop entity is what this app manages.
- [Shop Membership (user_shops) + Staff Invites (shop_invites)](../01-Architecture/decisions/ADR-0005-shop-membership-and-staff-invites.md) — the access/staffing model this app's own permissions will likely be built on.
- [SHOP Role App Area (Seller Home)](../01-Architecture/decisions/ADR-0006-shop-role-app-area.md) — the existing in-customer-app seller area; closest current analog to what this dashboard replaces or complements.
- [Per-Option Images for Shared Addons](../01-Architecture/decisions/ADR-0007-per-option-images-shared-addons.md) — menu/addon management is admin-facing work.
- [Captain Ordering (Dine-In POS + KDS) — Append-KOT-Under-Check Architecture](../01-Architecture/decisions/ADR-0012-captain-ordering-dine-in-pos-kds.md) — dine-in POS + KDS is shop-staff-facing; this dashboard is a natural home for its management/reporting surface.

## When this app is built

Once the `Ninjasu_Web` repo has real code, its own knowledge — screens,
flows, UX reviews, app-specific decisions — goes in [`../05-Web/`](../05-Web/).
This MOC should then be expanded the way [`Customer-App-MOC.md`](Customer-App-MOC.md) and
[`Rider-App-MOC.md`](Rider-App-MOC.md) are structured, with anchors pointing at real files in that
repo.
