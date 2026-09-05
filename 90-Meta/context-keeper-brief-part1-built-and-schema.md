---
id: ""
title: "Context Keeper Brief, Part 1 — What Was Built (Historical Snapshot)"
summary: "2026-05-21 snapshot of completed/pending build phases (auth, shop/menu, addon groups, home feed, orders), the 20 architectural principles recap, and the locked schema decisions (S1-S15)."
type: reference
status: active
apps: [backend, customer, admin, rider]
module: "meta"
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Context Keeper Brief, Part 1 — What Was Built (Historical Snapshot)

> Part of [context-keeper-brief.md](context-keeper-brief.md) — a point-in-time (2026-05-21) snapshot; see that index for the other parts and the migration note on current relevance.

## 3. What Has Been Built So Far

### Phase 1A — Auth & Users (COMPLETE)
- OTP flow: `POST /auth/send-otp`, `POST /auth/verify-otp`
- User signup: `POST /users/signup`
- JWT issued on OTP verify; stored in AsyncStorage + Zustand (`useUserStore`)
- Auth guard in `app/_layout.tsx` routes to `(tabs)` or `(admin)` based on role

### Phase 1B — Shop & Menu Structure (COMPLETE)
- Shop CRUD: `GET/POST/PUT/DELETE /api/shops/**`
- Menu categories (hierarchical, max 2 levels, soft delete): `/api/shops/{shopId}/menu-categories/**`
- Cuisines: `GET /api/cuisines`

### Phase 1C — Menu Items + Addon Groups (COMPLETE)
- Item CRUD: `/api/shops/{shopId}/menu-items`
- Full menu endpoint: `GET /api/shops/{shopId}/menu` (includes addon groups per item, batch-fetched)
- Item detail: `GET /api/shops/{shopId}/menu-items/{itemId}` — includes `addonGroups`
- Addon groups: standalone management + shop-scoped `/api/shops/{shopId}/addon-groups/**`
- Individual addons: `/api/addon-groups/{groupId}/addons`, `/api/addons/{addonId}/**`
- Item-addon group linking/unlinking: `/api/menu-items/{itemId}/addon-groups/**`
- Item creation (`POST /api/shops/{shopId}/menu-items`) creates addon groups + addons + links in a **single @Transactional call**
- S3 image upload: `UploadController` (presigned URL flow)

### Phase 1D — Home Page Feed (COMPLETE)
- `GET /api/home` — paginated restaurant feed with:
  - Haversine distance filtering
  - Cuisine chips filter
  - Item previews
  - Price extraction (from addon groups)
  - Cursor pagination
  - Swagger documented

### Phase 1E — Orders (PENDING)
- Cart -> Order flow
- Order status transitions
- Delivery provider integration

### Phase 2 — Combos (PENDING)
- Combo items (`item_type = COMBO`)
- Combo group management
- NOTE: `MenuItemServiceImpl.deleteItem` line ~252 has a TODO: check `combo_items` table once combo phase is implemented

### Frontend Features Built
- **Onboarding:** splash screen
- **Auth:** login (OTP send), verify OTP, signup
- **Home:** restaurant feed (`HomeServiceImpl`), cuisine filter chips, promo carousel (currently hardcoded — will move to API-driven sections per Principle 3)
- **Restaurant:** `RestaurantScreen.tsx` — full menu browse with category sidebar scroll-sync, item cards, addon customization sheet (`AddonSheet.tsx`), item detail sheet, cart bar
- **Admin panel (mobile):** shop creation/editing, `CategoryFormModal.tsx`, `ItemFormModal.tsx`, `SharedAddonsTab.tsx`
- **Cart:** `app/cart.tsx` modal overlay; `useRestaurantCartStore.ts` (the active cart store)
- **Location select:** `app/select-location.tsx` modal overlay

---

## 4. Key Architectural Principles (from ARCHITECTURE.md)

All 20 principles, tagged [SHARED] / [FRONTEND] / [BACKEND]:

**1. [SHARED] Cart / Order / Checkout is ONE domain.** Cart state in `useCartStore.ts`/`useRestaurantCartStore.ts`. Cart rules in `src/domain/cart/` (to be built). Screens never implement cart rules directly. Cart rules are **per-vertical** (restaurant = one-shop-only; grocery = multi-shop). "One shop only" is NOT a core cart rule — it is a restaurant-specific rule.

**2. [SHARED] Food is a vertical implementation, not the app.** Grocery timeline: 6-12 months post-launch. Every function that needs to know "this is a restaurant" should ask: could grocery do this differently? If yes — parameterize, don't hardcode.

**3. [SHARED] Home is a generic section renderer.** Home API must return typed sections (`PROMO_CAROUSEL`, `RESTAURANT_LIST`, `CUISINE_FILTERS`, etc.) reorderable without an app update. Frontend renders by `type`. Currently `HeaderPromoSection.tsx` is hardcoded — this must move to API-driven.

**4. [FRONTEND] Navigation passes IDs only — never objects.** Store selected entity in Zustand slice, pass only `id` as the navigation param. Current `/restaurant` pattern (passing objects as URL params) is flagged as the wrong approach.

**5. [FRONTEND] Cart is local truth — network is background sync.** Cart mutations must feel instant. Optimistic updates always. Server sync is background, never blocking. Re-validate at checkout only (not on every add).

**6. [SHARED] Cart re-validation at checkout.** On entering checkout: call `POST /api/cart/validate` (not yet built). Returns per-item availability, current prices, shop open status, deliverability. Must be designed in from day one of checkout.

**7. [FRONTEND] High-frequency screens must stay cheap to re-render.** Home feed: FlatList virtualization, image caching, pure+memoizable item cards. Restaurant menu: scroll-sync hook is the perf risk — isolate it, keep item cards pure. Cart updates: local-first. Search: debounced, ephemeral. **Item cards are dumb and presentational — business logic in card components kills scroll perf.**

**8. [SHARED] Admin plan — web is primary, mobile is minimal.** Mobile `(admin)` routes = bare minimum on-the-go features only. New admin features default to web. Mobile admin uses its own services. Backend admin endpoints must enforce role + ownership (currently missing — Principle 15 flag).

**9. [FRONTEND] Cross-cutting concerns are not features.** Cart, user session/auth, location, connectivity -> `src/store/` with rules in `src/domain/<concept>/`. If multiple unrelated screens share state, it is cross-cutting — not a feature.

**10. [SHARED] Error categories need different UX.** Network -> retry; Auth -> re-login; Validation -> per-field highlight; Business -> in-context message; Server -> generic retry. Backend must add `code` field to error responses (`"code": "SHOP_CLOSED"`). Frontend `ApiError` must surface `code` once backend adds it.

**11. [SHARED] API idempotency for mutations.** When orders/payments are built: backend accepts `Idempotency-Key` header; frontend generates UUID per mutation attempt. Design in when orders is built — retrofitting is a nightmare.

**12. [SHARED] Real-time order updates — push + polling.** Push notifications (FCM + APNs via Expo Notifications) + foreground polling every 10-15s on active-order screen. No WebSocket. No live map tracking. Push payload: order id + new status only.

**13. [SHARED] App force-update mechanism.** Not building now. Document the placeholder: backend endpoint returns min supported version + optional soft-update version. Frontend checks on launch.

**14. [SHARED] Frontend <-> backend type drift prevention.** Before any frontend interface, check backend DTO (`dto/` package). DTO field change = frontend interface update in **same task**. Future: OpenAPI codegen from Swagger (not building now).

**15. [BACKEND] Production hardening — must fix before launch:**
- OTP hardcoded to "1234" — integrate real SMS provider
- DB credentials in `application.properties` — move to env vars, scrub git history
- JWT secret is default base64 — generate per-environment secret
- No shop ownership enforcement in shop/menu/addon controllers — any JWT user can edit any shop
- `ddl-auto=update` in production — switch to Flyway/Liquibase
- No rate limiting on `/auth/send-otp` — OTP spam / SMS cost attack vector

**16. [SHARED] Flows must be interruptible and resumable.** For every critical flow (cart, checkout, payment, active order): what happens if user leaves halfway? Can it resume? Is intent preserved across backgrounding/network loss?

**17. [SHARED] Availability is a backend decision — frontend only renders.** Shop open status, delivery range, item stock, kitchen hours, prep time are backend business constraints. Frontend never infers availability. Never grey out a button because frontend "thinks" the shop is closed.

**18. [SHARED] Orders are future cart sources — not just history.** Order model must snapshot: item names/images/descriptions at time of order, exact pricing, all selected addons/modifiers, shop reference. Reorder reconstructs a cart then revalidates.

**19. [FRONTEND] Search state is ephemeral — never global.** Query, results, loading -> local to search screen. Recent searches -> AsyncStorage, not global store. Rankings/relevance -> backend.

**20. [SHARED] Architecture by stage — we are in Early Stage.** Do not apply Growth or Scale patterns. Avoid: plugin systems, offline sync, over-generalization, microservices thinking, generic CMS-driven UI, micro-frontend, custom navigation abstraction, custom state management, recommendation engine on frontend, premature component library extraction.

---

## 5. Schema Decisions That Are Locked

These are non-negotiable. Any task contradicting these must be stopped and flagged.

| # | Decision | Detail |
|---|---|---|
| S1 | **No `price` column on `items`** | Price always comes from addon groups. There is no separate base price field on items. |
| S2 | **Every item must have >=1 ITEM-scoped addon group with `is_required = true`** | This defines the item's base price. Error: "Add at least one item-specific required option to define this item's base price." A SHARED-scoped group alone does NOT satisfy this. |
| S3 | **Category max depth = 2** | Top-level + one sub-category level. Sub-category's parent must have `parent_category_id = NULL`. |
| S4 | **Parent category cannot have direct items if it has sub-categories** | And vice versa: a category with items cannot receive a sub-category. |
| S5 | **`group_scope` is ITEM or SHARED — set at creation, not derived** | SHARED -> `is_required = false` always, no discounts. ITEM -> linked to exactly one item via join table. |
| S6 | **Addon `discount_percent` is nullable with cascade semantics** | `NULL` = inherit from `item.discount_percent`. `0` = explicit override (no discount). Non-null = explicit override. Discounts NEVER apply to SHARED-scoped addon options. |
| S7 | **DB stores S3 keys. API always returns full URLs. Incoming requests always extract keys.** | `s3Service.buildFullUrl(key)` in every `toDto()`. `s3Service.extractKey(urlOrKey)` on every create/update. Never return raw S3 key in API response. |
| S8 | **All IDs are UUIDs** | UUIDs generated by `gen_random_uuid()` at DB level. On frontend: always `string`, never `number`. |
| S9 | **Cart is NOT persisted on the backend** | Backend only sees a cart when it becomes a Place Order request. |
| S10 | **Order lifecycle is an explicit enum + transitions** | `PLACED -> ACCEPTED -> PREPARING -> READY -> OUT_FOR_DELIVERY -> DELIVERED`, plus `DECLINED`, `CANCELLED`. No string comparisons in business logic. |
| S11 | **Max 4 addon groups visible per item** | Combined SHARED attachments + ITEM groups. |
| S12 | **Each addon group must have > 1 addon option** | `min_select` cannot exceed the number of options. |
| S13 | **Combo cannot contain another combo. No circular references.** | Combo availability: if any child item has `is_available = false`, combo is hidden. Computed at query time. |
| S14 | **Item visibility requires ALL of:** `items.is_active = true`, `items.is_available = true`, `menu_categories.is_available = true` for all its categories, and for combos: all child items pass rules 1-2 | — |
| S15 | **Price calculation formula (locked):** `effective_discount = COALESCE(addon.discount_percent, item.discount_percent, 0)` then `selling = option.price x (1 - effective_discount / 100)` | Line total = sum of selling across all selected options. Frontend computes live; backend is authoritative. Implemented in `PriceCalculator.java`. |

---

