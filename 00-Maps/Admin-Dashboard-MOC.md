---
id: ""
type: reference
status: active
apps: [admin]
module: "meta"
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Admin Dashboard — Map of Content

**Ninjasu_Admin_Dashboard** — this app has **not been built yet**. There is no repo, no code,
and no admin-dashboard-specific knowledge to document. This stub exists so the vault's app
coverage is complete and so anyone starting the build has a landing page that already points at
everything it will need to share with the rest of the platform.

## What it will share with everything else

The admin dashboard is a new client on top of the **same shared backend** every other app
uses — it does not get its own domain rules or its own architecture. Read these first, before
designing anything admin-specific:

- [Shared backend](../03-Backend/) — API contracts, auth, data model. Same envelope, same JWT
  auth, same endpoints (extended with admin-scoped ones as needed) as the customer app and rider
  app use.
- [Shared domain rules](../02-Domain/) — menu, cart, wishlist, core, captain-ordering. These are
  true for every client; the admin dashboard renders and manages against them, it does not
  reinvent them.
- [Shared architecture principles](../01-Architecture/principles.md) — read the `[SHARED]` tagged
  principles, plus `[BACKEND]` ones for anything touching the boundary this app will sit on.

## Relevant decisions

Existing ADRs whose subject matter this app will sit directly on top of once built:

- [Order / OrderLine Snapshot-Pricing Schema (Risk 6)](../01-Architecture/decisions/ADR-0002-order-orderline-snapshot-pricing-schema.md) — order/sales data the dashboard will need to read and display correctly.
- [Restaurant vs Shop Entity Consolidation (Open Question, Risk 4)](../01-Architecture/decisions/ADR-0004-restaurant-vs-shop-entity-consolidation.md) — the Shop entity is what this app manages.
- [Shop Membership (user_shops) + Staff Invites (shop_invites)](../01-Architecture/decisions/ADR-0005-shop-membership-and-staff-invites.md) — the access/staffing model this app's own permissions will likely be built on.
- [SHOP Role App Area (Seller Home)](../01-Architecture/decisions/ADR-0006-shop-role-app-area.md) — the existing in-customer-app seller area; closest current analog to what this dashboard replaces or complements.
- [Per-Option Images for Shared Addons](../01-Architecture/decisions/ADR-0007-per-option-images-shared-addons.md) — menu/addon management is admin-facing work.
- [Captain Ordering (Dine-In POS + KDS) — Append-KOT-Under-Check Architecture](../01-Architecture/decisions/ADR-0012-captain-ordering-dine-in-pos-kds.md) — dine-in POS + KDS is shop-staff-facing; this dashboard is a natural home for its management/reporting surface.

## When this app is built

Once the `Ninjasu_Admin_Dashboard` repo exists and has real code, its own knowledge — screens,
flows, UX reviews, app-specific decisions — goes in [`../05-Admin-Dashboard/`](../05-Admin-Dashboard/).
This MOC should then be expanded the way [`Customer-App-MOC.md`](Customer-App-MOC.md) and
[`Rider-App-MOC.md`](Rider-App-MOC.md) are structured, with anchors pointing at real files in that
repo.
