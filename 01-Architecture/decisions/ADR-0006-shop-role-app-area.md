---
id: ADR-0006
title: "ADR-0006: SHOP Role App Area (Seller Home)"
summary: "Introduced a dedicated (shop) tab navigator (Orders/My Shop/Profile) for the SHOP role, replacing a fallback into the customer app and reusing the admin's shop-detail component for both surfaces."
type: decision
status: accepted
apps: ["backend", "customer"]
module: "shop-membership"
anchors:
  - { repo: customer, path: "app/(shop)/_layout.tsx" }
  - { repo: customer, path: "app/(shop)/orders.tsx" }
  - { repo: customer, path: "app/(shop)/shop.tsx" }
  - { repo: customer, path: "app/(shop)/profile.tsx" }
  - { repo: customer, path: "src/features/admin/components/ShopDetailView.tsx" }
  - { repo: customer, path: "src/utils/roleHome.ts" }
  - { repo: customer, path: "app/(admin)/_layout.tsx" }
  - { repo: customer, path: "app/(admin)/shop-view.tsx" }
  - { repo: customer, path: "app/_layout.tsx" }
  - { repo: customer, path: "app/(onboarding)/index.tsx" }
  - { repo: customer, path: "src/features/profile/ProfileScreen.tsx" }
verified_against: "49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-06-10
---

# ADR-0006: SHOP Role App Area (Seller Home)

## Context

Shop owners are onboarded with roles `["USER", "SHOP"]`. Switching to the SHOP role
previously fell through to the customer `(tabs)` app — a bug, not a designed behaviour.
There was no dedicated app area for a shop owner to operate their own shop from.

A shop owner needs to see their single shop's detail (the same UI the platform admin
already uses for `shop-view`) plus order management for that shop. Order management is
a shop-owner concern, not a platform-admin one, so it also needed to move out of the
admin app.

This decision was made jointly via the `ui_engineer` and `architect` passes.

## Decision

Introduce `(shop)` as a new bottom-tab navigator with three tabs: **Orders / My Shop /
Profile**.

- **Orders is first.** Partner apps in this space (e.g. Swiggy/Zomato for Restaurants)
  open straight to the order queue — it's the daily workhorse for a shop owner, and
  burying it behind other tabs adds friction (ui_engineer rationale).
- **My Shop** shows shop details/menu/addons — the *same* component the platform admin
  uses, scoped to the signed-in owner's shop.
- **Profile** carries the role switch plus sign-out. An owner is dual-role (USER + SHOP)
  and needs a visible surface to switch between the customer and shop experiences.

As a consequence, the admin app's Orders tab was removed — order management belongs to
the shop, not to the platform admin.

**Reuse:** `shop-view.tsx`'s body was extracted into
`src/features/admin/components/ShopDetailView.tsx` (`{ shopId, showBack }`). Both the
admin route and the shop tab render this same component — a single source of truth
instead of a duplicated ~1200-line screen (Architecture Principle 14: logic maintained
in two places drifts).

## Consequences

**Makes easy:**
- One shop-detail implementation (`ShopDetailView`) serves both the admin's
  cross-shop view and the owner's own-shop view — changes to shop-detail UI/logic only
  need to happen once.
- Role→home routing is centralized in a single `roleHome(activeRole)` utility
  (`src/utils/roleHome.ts`), called from all three places that previously computed it
  independently (`app/_layout.tsx`'s `AuthGuard`, the `(onboarding)/index.tsx` splash
  screen, and `ProfileScreen`'s role switch). Adding a future role only requires
  updating one function instead of auditing three call sites for drift.

**Makes hard / accepted risk:**
- `activeRole = roles[0]` is non-deterministic for dual-role owners: since the backend
  returns `["USER", "SHOP"]`, `roles[0]` resolves to `USER`, so an owner lands in the
  customer app on first login and must manually switch to SHOP via the Profile tab.
  This is mildly confusing but not broken, and was accepted rather than fixed —
  **status: deferred**. Revisit (e.g. default `activeRole` to the highest-privilege
  role) if owners report friction.

**Rules out:**
- The platform admin app no longer has its own Orders tab — order management for a
  shop is only reachable through that shop's owner (SHOP role), not through the admin
  role.

No database tables were affected — this is a pure frontend routing/navigation change.
No new API contract was introduced (it reuses the existing `GET /api/shops/my`).
Migration cost was none; risk was assessed low, since `(shop)` is an additive route
group and existing USER/ADMIN flows were left unchanged.

## Enforced in

- `app/(shop)/_layout.tsx` — the `(shop)` bottom-tab navigator (Orders / My Shop / Profile).
- `app/(shop)/orders.tsx`, `app/(shop)/shop.tsx`, `app/(shop)/profile.tsx` — the three tab screens.
- `src/features/admin/components/ShopDetailView.tsx` — shared shop-detail body, rendered by both the admin route and the shop tab.
- `src/utils/roleHome.ts` — the single `roleHome(activeRole)` function that all role→home call sites use.
- `app/(admin)/_layout.tsx`, `app/(admin)/shop-view.tsx` — admin route group, with the Orders tab removed and `shop-view` refactored onto `ShopDetailView`.
- `app/_layout.tsx` (`AuthGuard`), `app/(onboarding)/index.tsx` (splash), `src/features/profile/ProfileScreen.tsx` (role switch) — the three call sites now delegating to `roleHome.ts`.

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
