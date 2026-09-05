---
id: ""
title: "Pending Flags"
summary: "Phase-by-phase backlog of build work (auth, shop/menu, addon groups, home feed, cart, orders, combos) tracking which items have shipped and which are still pending."
type: reference
status: active
apps: [backend, customer, admin, rider]
module: "roadmap"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/CartSessionServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/MenuItemServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/IdempotencyService.java" }
  - { repo: customer, path: "src/store/useCartStore.ts" }
verified_against: "backend@ff5ade334891238d16b8010e372fdbbc502c193e customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-07-11
---

# Pending Flags

Backlog of build phases and open work items, tracked in the order they were planned.
Checked items are shipped; unchecked items are still pending.

## Phase 1A — Auth & Users
- [x] OTP flow (send + verify)
- [x] User signup

## Phase 1B — Shop & Menu Structure
- [x] Shop CRUD
- [x] Menu categories (hierarchical, soft delete)
- [x] Cuisines

## Phase 1C — Menu Items + Addon Groups
- [x] Item CRUD (`/api/shops/{shopId}/menu-items`)
- [x] Full menu endpoint (`/api/shops/{shopId}/menu`)
- [x] Addon groups and addons — complete implementation
  - Item creation now creates addon groups + addons + links in a single `@Transactional` call
  - Standalone addon group management APIs added
  - Individual addon management APIs added
  - Item-addon group linking/unlinking APIs added
  - `GET /api/shops/{shopId}/menu-items/{itemId}` includes `addonGroups` in response
  - `GET /api/shops/{shopId}/menu` includes `addonGroups` per item in response (batch-fetched)

## Phase 1D — Home Page Feed
- [x] `GET /api/home` — paginated restaurant feed with Haversine distance filtering,
  cuisine chips, item previews, price extraction, cursor pagination, and Swagger docs

## Phase 1D.5 — Cart Module (in progress on `feature/cart`)
Business rules locked in [Cart](../02-Domain/cart.md). Backend slice in progress.

- [ ] **Backend** — cart_sessions / cart_items / cart_item_addons / idempotency_keys tables,
      JPA entities, services, controllers, exception handlers (per [Cart](../02-Domain/cart.md))
- [ ] **Backend** — `IdempotencyService.findCached` must filter by
      `created_at > NOW() - INTERVAL '5 minutes'` so stale rows are logically ignored
      even before cleanup job exists
- [ ] **Backend** — Scheduled cleanup job for `idempotency_keys` (deletes rows older than 1 hour).
      Stubbed in this slice — table grows unbounded until built.
- [ ] **Backend** — `shops.vertical` column. Until it exists, `CartSessionService.determineCartType`
      defaults to `FOOD` with a `TODO` marker. Required before GROCERY/PRODUCT verticals ship.
- [ ] **Frontend** — Replace device-only `useRestaurantCartStore` with server sync layer.
      Always send `?type=FOOD` query param until vertical picker UI exists.
- [ ] **Frontend** — Generate fresh UUID v4 `Idempotency-Key` header per add-to-cart click.
- [ ] **Frontend** — Mirror the locked `cart_key` formula (sha256, hex, lowercase,
      lex-sorted addonIds joined by comma). Do NOT send `cartKey` in request bodies —
      backend re-derives.
- [ ] **Frontend** — Multi-shop conflict dialog on `409 DIFFERENT_SHOP_CART_EXISTS`,
      "Order in progress" banner on `409 SESSION_LOCKED`,
      validation warnings + "Accept changes" banner when any item has `validation ≠ OK`.
- [ ] **Frontend** — Vertical picker UI (FOOD/GROCERY/PRODUCT cart switcher) — later slice.
- [ ] **Frontend** — `selected_for_checkout` checkbox UI on cart lines — later slice.
- [ ] **Perf (later)** — Batch addon fetch and short-TTL availability cache on
      `GET /api/cart` to reduce the N×M validation cost. Acceptable at current scale.

## Phase 1E — Orders (pending)
- [ ] Cart → Order flow (consumes cart sessions; copies snapshots into immutable order tables)
- [ ] `LOCKED` ↔ `COMPLETED` cart session transitions during order placement
- [ ] Order status transitions
- [ ] Delivery provider integration

## Phase 2 — Combos (pending)
- [ ] Combo items (referenced by TODO in `MenuItemServiceImpl.deleteItem`)
- [ ] Combo group management

## Known TODOs in Code
- `MenuItemServiceImpl.deleteItem`: check `combo_items` table once combo phase is implemented
