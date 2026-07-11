---
id: ""
type: reference
status: active
apps: [backend, customer, admin, rider]
module: "meta"
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Food Ninja — Context Keeper Onboarding Brief

**Maintained by:** Context Keeper Agent  
**Created:** 2026-05-21  
**Last updated:** 2026-05-21  
**Source files read:** CLAUDE.md, ARCHITECTURE.md, Modules/menu.md, Modules/README.md, project_pending_flags.md, tests-todo.md, all entity classes, all CLAUDE.md files, pom.xml, package.json, store files, feature structures.

> This brief is the first thing every agent should read. It replaces the need to scan the whole project for orientation. After reading this, read only the FILE MAP section to know which additional files your specific role requires.

---

## 1. What Is Food Ninja?

Food Ninja is a **multi-vertical food/delivery platform** modelled on the Swiggy/Zomato pattern. It is in early-stage active development. Currently only the **restaurant vertical** is being built; grocery is targeted 6–12 months post-restaurant launch.

### The Three Platforms

| Platform | Status | Primary Surface | Notes |
|---|---|---|---|
| **Customer App** | In development | React Native (mobile) | Home feed, browse restaurants, cart, checkout, orders, profile |
| **Admin / Seller Panel** | In development (minimal) | React Native (mobile) `(admin)` routes | Shop CRUD, menu management, addon groups. Mobile = minimal on-the-go subset only |
| **Web Admin** | Planned (not started) | Separate web project | Full feature set for shop owners; mobile admin is a constrained subset of this |
| **Delivery** | Not started | TBD | Order lifecycle tracked; delivery provider field exists on `shops` table |

### The Funnel Mental Model
```
Discover → Browse store → Build cart → Checkout → Place order → Track → Reorder
```
The cart **becomes** the order. The order **becomes** the reorder source. This is the single most important architectural insight: cart/checkout/orders are **ONE domain**, not three separate features.

---

## 2. Tech Stack

### Backend
| Layer | Technology |
|---|---|
| Framework | Spring Boot 4.0.3 |
| Language | Java 21 |
| Database | PostgreSQL (Neon serverless) |
| ORM | Spring Data JPA / Hibernate |
| Auth | JWT (JJWT 0.12.6) via Bearer token |
| API Docs | Springdoc OpenAPI 2.8.6 (Swagger UI at `/swagger-ui/index.html`) |
| Image Storage | AWS S3 (SDK 2.25.6) |
| Validation | Spring Boot Starter Validation |
| Logging | SLF4J |
| Build | Maven |
| Boilerplate reduction | Lombok |

### Frontend
| Layer | Technology |
|---|---|
| Framework | React Native 0.81.5 |
| Build toolchain | Expo ~54.0.33 |
| Routing | Expo Router ~6.0.23 (file-based) |
| Language | TypeScript ~5.9.2 |
| State management | Zustand ^5.0.11 |
| Server state | TanStack Query (React Query) ^5.100.10 |
| HTTP client | Custom `fetchFn.ts` wrapper (single source) |
| Maps | react-native-maps 1.20.1 |
| Location | expo-location |
| Image picking | expo-image-picker |
| Animations | react-native-reanimated ~4.1.1 |
| Gestures | react-native-gesture-handler |
| Color system | `constants/brand.ts` -> `BRAND.colors` (single source of truth) |

---

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

## 6. Key Files and What They Do

### Backend

| File | What it does |
|---|---|
| `ninja delivery service java/CLAUDE.md` | Backend-specific rules: response contract, S3 rule, coupling guard, logging standard, endpoint table |
| `entity/Item.java` | DB table `items`. No `price` column. Has `item_type` (FOOD/COMBO), `is_available`, `is_active`, `is_deleted` (soft delete), `discount_percent` (nullable). UUIDs everywhere. |
| `entity/Shop.java` | DB table `shops`. Has `shop_type` (RESTAURANT/GROCERY), `owner_id`, delivery fields (`delivery_radius_km`, `delivery_provider`, `supports_pickup`), `opening_time`, `closing_time`, `status` (DRAFT/LIVE), coordinates. |
| `entity/AddonGroup.java` | DB table `addon_groups`. Has `group_scope` (ITEM or SHARED enum), `is_required`. The scope is the pivot for all addon group business rules. |
| `entity/Addon.java` | DB table `addons`. Has `price` (BigDecimal), `discount_percent` (nullable — cascade discount logic), `is_available`, `is_deleted`. |
| `entity/FoodItemDetails.java` | DB table `food_item_details`. PK = `item_id` (1-to-1 with items). Has `food_type` (VEG/NON_VEG/EGG), `prep_time_mins`, `is_customizable`. Pattern for future verticals: add `GroceryItemDetails` similarly. |
| `entity/MenuCategory.java` | DB table `menu_categories`. Has `parent_category_id` (NULL = top-level), `is_available`, `is_deleted`. |
| `entity/MenuItemCategory.java` | Join table `menu_item_categories`. Embedded composite PK. Items-to-categories is many-to-many via this join table. |
| `entity/MenuItemAddonGroup.java` | Join table `menu_item_addon_groups`. Embedded composite PK. Items-to-addon-groups linkage. ITEM-scoped groups must link to exactly one item. |
| `entity/DeliveryConfig.java` | DB table `delivery_config`. Uses `@OneToOne` JPA join to Shop (unlike other entities that use plain UUID). Has `base_fee`, `per_km_fee`, `free_delivery_above`. See conflict C4. |
| `entity/lookup/Cuisine.java` | Lookup table for cuisine types. |
| `entity/lookup/RestaurantCuisine.java` | Join table: shop <-> cuisine many-to-many. |
| `entity/GroupScope.java` | Enum: `ITEM`, `SHARED`. |
| `util/PriceCalculator.java` | The **authoritative backend price calculation utility.** Implements cascade: addon discount overrides item discount; null = inherit. Two `applyDiscount` overloads + `resolveEffectiveDiscount`. Has unit tests in `PriceCalculatorTest.java`. |
| `service/impl/MenuItemServiceImpl.java` | Largest service (26KB). Item CRUD, addon group linking, item creation in single transaction, soft delete with combo TODO at line ~252. |
| `service/impl/AddonGroupServiceImpl.java` | Addon group and addon management (23KB). |
| `service/impl/HomeServiceImpl.java` | Home feed logic (21KB) — Haversine filtering, cursor pagination, price extraction from addon groups. |
| `service/impl/MenuCategoryServiceImpl.java` | Category rules enforcement (8.7KB) — depth check, items-vs-subcategories mutual exclusion, soft delete. |
| `service/impl/ShopServiceImpl.java` | Shop CRUD (8KB). |
| `service/impl/S3ServiceImpl.java` | `buildFullUrl(key)` and `extractKey(urlOrKey)`. Must be called in every service that handles imageUrl. |
| `security/JwtUtil.java` | JWT generation and validation. |
| `security/JwtAuthFilter.java` | Request filter — attaches JWT claims to security context. |
| `config/SecurityConfig.java` | Route-level auth rules. Public: `/auth/**`, `/users/signup`, `/api/home`, `/swagger-ui/**`, `/v3/api-docs/**`. JWT required: everything else. |
| `exception/GlobalExceptionHandler.java` | Maps exceptions to `ApiResponse<T>` error envelopes. |
| `dto/ApiResponse.java` | The universal response wrapper. Every endpoint returns this. `status` = "SUCCESS" or "ERROR" only. |
| `src/main/resources/application.properties` | DB credentials + JWT secret + S3 config. Contains hardcoded secrets — PRODUCTION BLOCKER (Principle 15). |

### Frontend

| File | What it does |
|---|---|
| `Food-Ninja-Frontend/CLAUDE.md` | Frontend-specific rules: folder structure, color system, HTTP client rule, S3 image URL rule, error handling, auth flow, routing, coupling guard |
| `src/lib/fetchFn.ts` | The **one and only HTTP client.** Signature: `fetchFn(path, method, payload?)`. Throws `ApiError` with `message` + `fieldErrors`. Never call `fetch` directly anywhere else. |
| `src/store/useUserStore.ts` | Auth state — user object, token, role. Persisted via Zustand persist + AsyncStorage. |
| `src/store/useRestaurantCartStore.ts` | **The active cart store for the restaurant vertical.** Holds `RestaurantCartItem[]` (selected addons, `unitPrice`, `totalPrice`, `cartKey`). Enforces one-shop-only rule: returns `'different_shop'` if adding from another shop. Cart key = `itemId::sortedAddonIds`. |
| `src/store/useCartStore.ts` | **Legacy/older cart store** — simpler `IItem` shape without addon support. Uses `item.price * quantity` for price which contradicts schema rule S1. SEE CONFLICT C1. |
| `src/store/useLocationStore.ts` | Delivery address + current coordinates. Cross-cutting global state. |
| `src/store/useSelectedRestaurantStore.ts` | Holds the currently selected restaurant data for navigation (correct pattern per Principle 4). |
| `constants/brand.ts` | Single source of truth for all colors. `BRAND.colors.<token>`. Never hardcode a hex in StyleSheet or inline style. |
| `constants/config.ts` | API base URL read from `.env` / `.env.production`. |
| `app/_layout.tsx` | Root layout + AuthGuard. Routes to `(tabs)` or `(admin)` based on role. |
| `app/cart.tsx` | Cart modal overlay (27KB — see open question OQ8). |
| `app/select-location.tsx` | Location selection modal (17KB). |
| `src/features/restaurant/RestaurantScreen.tsx` | Main restaurant screen (20KB) — category sidebar with scroll-sync, item cards, addon sheet. |
| `src/features/restaurant/components/AddonSheet.tsx` | Addon customization bottom sheet (14KB). Customer picks options. Price computed live. |
| `src/features/restaurant/components/CategorySidebar.tsx` | Category sidebar with scroll-sync (6.5KB). The perf risk per Principle 7 — keep isolated. |
| `src/features/restaurant/components/MenuItemCard.tsx` | Item card component (6KB). Must stay dumb/presentational per Principle 7. |
| `src/features/admin/components/CategoryFormModal.tsx` | Admin category create/edit form (20KB). UX-level enforcement of category rules. |
| `src/features/admin/components/ItemFormModal.tsx` | Admin item create/edit form (59KB — the largest frontend file). Full item + addon group creation flow. |
| `src/features/admin/components/SharedAddonsTab.tsx` | Admin UI for managing SHARED-scoped addon groups (17KB). |

---

## 7. File Map — Which Agent Should Read Which Files

### Backend Developer Agent
Must read:
- `ninja delivery service java/CLAUDE.md` — rules, response contract, S3 rule, coupling guard
- `ARCHITECTURE.md` — all [BACKEND] and [SHARED] principles
- `Modules/menu.md` — business rules the backend must enforce in service layer
- `entity/` — all entity classes (ground truth for DB schema)
- `dto/` — response shapes your code must match
- `service/impl/MenuItemServiceImpl.java` — before touching anything menu-related
- `service/impl/AddonGroupServiceImpl.java` — before touching addon logic
- `project_pending_flags.md` — what's done, what's pending

### Frontend Developer Agent
Must read:
- `Food-Ninja-Frontend/CLAUDE.md` — folder structure, color system, HTTP client, error handling, auth flow
- `ARCHITECTURE.md` — all [FRONTEND] and [SHARED] principles
- `Modules/menu.md` — business rules you render/guard in UI
- `src/store/useRestaurantCartStore.ts` — the active cart store (use this, not useCartStore)
- `src/lib/fetchFn.ts` — the HTTP client you must use
- `constants/brand.ts` — color tokens you must use

For menu/restaurant features also read:
- `src/features/restaurant/RestaurantScreen.tsx`
- `src/features/restaurant/components/AddonSheet.tsx`

For admin features also read:
- `src/features/admin/components/ItemFormModal.tsx`
- `src/features/admin/components/CategoryFormModal.tsx`

### QA Strategist Agent
Must read:
- `Modules/menu.md` — the complete rule set to test against
- `tests-todo.md` — 20 test cases already specified (backend + frontend); your starting checklist
- `ARCHITECTURE.md` Principle 15 — production hardening gaps = security test targets
- `project_pending_flags.md` — pending features = no tests needed yet (orders, combos)
- `entity/Item.java`, `entity/AddonGroup.java`, `entity/Addon.java` — DB schema for test data setup

### UX Critic Agent
Must read:
- `Modules/menu.md` — particularly the UI Rendering Logic table (radio vs checkbox, required vs optional)
- `ARCHITECTURE.md` Principle 7 (high-frequency screen perf), Principle 10 (error UX categories), Principle 16 (flows must be interruptible)
- `src/features/restaurant/components/AddonSheet.tsx` — the addon customization UX
- `src/features/restaurant/components/MenuItemCard.tsx` — must stay dumb/presentational
- `src/features/admin/components/ItemFormModal.tsx` — the admin creation UX (59KB, complex)
- `constants/brand.ts` — design tokens

### Devil's Advocate Agent
Must read:
- `ARCHITECTURE.md` — all 20 principles (your job is to flag violations)
- `CLAUDE.md` (root) — coupling guard rules
- `Modules/menu.md` — business rules (flag any code that violates these)
- `src/store/useCartStore.ts` — CONFIRMED CONFLICT with schema rule S1 (see Section 8)
- `project_pending_flags.md` — Principle 15 violations that are currently open
- `entity/DeliveryConfig.java` — has `@OneToOne` JPA join (potential coupling flag)

### Architect / Code Reviewer Agent
Must read all of the above, plus:
- `src/store/useRestaurantCartStore.ts` vs `src/store/useCartStore.ts` — two cart stores coexisting (architectural debt)
- `ARCHITECTURE.md` Principle 20 (architecture by stage) — flag anything Growth/Scale-level being introduced in Early Stage
- `implementation_plan_md/custom_domain_mail_performance_analysis.md` — review whether this decision was actioned

### Context Keeper Agent (this role)
Read everything. Update this brief when decisions are made or contradictions are resolved. Never update silently — show the diff first.

---

## 8. Contradictions and Conflicts Detected

### C1 — Two Cart Stores Coexisting (Architectural Debt) [HIGH]

**Files:** `src/store/useCartStore.ts` vs `src/store/useRestaurantCartStore.ts`

`useCartStore.ts` is an older, simpler cart store using `IItem` with a `price` field. It calculates price as `item.price * quantity`.

`useRestaurantCartStore.ts` is the newer, addon-aware cart store that correctly tracks selected addons, computes `unitPrice` from addon selection, and enforces the one-shop-only restaurant rule.

**The conflict:** `useCartStore.ts` uses `item.price` for price calculation — but Schema Rule S1 states there is NO `price` column on `items`. Price always comes from addon groups.

**Impact:** If `useCartStore` is still being used in customer-facing code, prices will be wrong. It also violates Principle 1 (cart rules must live in domain layer, not the store).

**Resolution needed:** Determine if `useCartStore.ts` is still in active use or is dead code. If dead, remove it. If active, migrate all usages to `useRestaurantCartStore.ts`.

---

### C2 — `HeaderPromoSection.tsx` Has Hardcoded Promo Data [MEDIUM]

**The conflict:** ARCHITECTURE.md Principle 3 states home sections must be API-driven (typed sections from backend). The current implementation hardcodes promo slides on the frontend.

**Resolution needed:** Backend needs to add `PROMO_CAROUSEL` section support to `GET /api/home`. Frontend moves `HeaderPromoSection` to consume API data.

---

### C3 — Navigation Passing Objects (Principle 4 Violation) [MEDIUM]

**File:** `app/restaurant.tsx` (and likely navigation callers in home feature)

ARCHITECTURE.md Principle 4 explicitly calls out: *"Don't pass restaurant object as 10 stringified URL params (current /restaurant pattern)."* The correct pattern: store entity in Zustand, pass only `id` as param. `useSelectedRestaurantStore.ts` exists for this purpose.

**Resolution needed:** Audit how navigation to `/restaurant` is triggered. If object-passing pattern is still present: refactor callers to write to `useSelectedRestaurantStore` and navigate with ID only.

---

### C4 — `DeliveryConfig` Uses JPA `@OneToOne` Join (Coupling Risk) [LOW]

**File:** `entity/DeliveryConfig.java`

This entity uses `@OneToOne @JoinColumn(name = "shop_id")` pointing to the `Shop` entity — making it a live JPA relationship. All other cross-entity references use plain UUID columns, not JPA joins.

Per the backend coupling guard: entities referencing each other across domains via JPA joins creates tight coupling at the DB layer.

**Resolution needed:** Evaluate whether `DeliveryConfig` needs a live JPA join or whether a plain `UUID shopId` column (matching all other entity patterns) is sufficient.

---

### C5 — All 6 Production Hardening Items Are Open (Principle 15) [CRITICAL before launch]

- OTP hardcoded to "1234"
- DB credentials in `application.properties`
- JWT secret is a default base64 value
- No shop ownership enforcement (any authenticated user can edit any shop)
- `ddl-auto=update` still set (not Flyway/Liquibase)
- No rate limiting on `/auth/send-otp`

These are known, documented production blockers. Any agent working on orders/payment/launch-readiness tasks must flag these before shipping.

---

### C6 — `src/domain/cart/` Does Not Exist Yet [LOW — watch list]

**Expected by:** ARCHITECTURE.md Principle 1, Principle 9

Cart rules (per-vertical dispatch logic) are supposed to live in `src/domain/cart/`. Currently, the one-shop-only enforcement lives directly inside `useRestaurantCartStore.ts`. Pragmatically fine for Early Stage but is a known architectural gap.

**Resolution needed:** When building checkout or adding the grocery vertical, extract cart rules into `src/domain/cart/` before adding vertical-specific logic to the store.

---

## 9. Open Items and Unresolved Questions

| # | Item | Source |
|---|---|---|
| OQ1 | What delivery provider will be integrated (Phase 1E)? Field exists on `shops.delivery_provider` but no value is set. | `project_pending_flags.md`, `Shop.java` |
| OQ2 | Is `useCartStore.ts` dead code or actively used? (See C1) | Scan required |
| OQ3 | Has the `/restaurant` object-passing navigation pattern been fixed? (See C3) | Scan required |
| OQ4 | When does the web admin project start? What framework? | `ARCHITECTURE.md` Principle 8 |
| OQ5 | Will push notifications (FCM/APNs) be set up during Phase 1E orders, or as a separate phase? | `ARCHITECTURE.md` Principle 12 |
| OQ6 | The `implementation_plan_md/custom_domain_mail_performance_analysis.md` doc — was this actioned? What decision was made? | `implementation_plan_md/` |
| OQ7 | `Restaurant.java` entity exists in `entity/` but appears unused (no controller references found). Is this a leftover stub or planned? | `entity/Restaurant.java` |
| OQ8 | `app/cart.tsx` at 27KB is very large for a route file. Per CLAUDE.md: route files must be thin. Was this intentional or does it need refactoring? | Frontend CLAUDE.md |
| OQ9 | No `src/domain/` folder exists yet. When will cart rules be extracted out of the store? (See C6) | Principle 1, 9 |
| OQ10 | `ARCHITECTURE.md` "Open Questions" section says "None outstanding" but the hardening items (Principle 15) and combo TODO are open. This section should be kept current. | `ARCHITECTURE.md` line 384 |

---

## 10. Resolved Decisions Log (from ARCHITECTURE.md, 2026-05-15)

| Decision | Detail |
|---|---|
| Cart model | Per-vertical: restaurant = one-shop-only; grocery = multi-shop. "One shop only" is NOT a core cart rule. |
| Grocery timeline | 6-12 months after restaurant launch. Build food concretely now. |
| Real-time orders | Push + polling (no WebSocket, no live map tracking). FCM/APNs + foreground polling every 10-15s. |
| Admin app | Web is primary, mobile is minimal subset. Backend enforces strict role/ownership. |

---

## 11. Project File Structure at a Glance

```
Food Ninja/                              <- Project root
├── ARCHITECTURE.md                      <- 20 architectural principles (read this first always)
├── CLAUDE.md                            <- Root guide: structure, coupling guard, team rules
├── Modules/
│   ├── README.md                        <- How to use Modules/
│   └── menu.md                          <- Business rules for menu (the only module so far)
├── agents/
│   └── context-keeper-brief.md          <- THIS FILE (original location — since migrated to the vault)
├── project_pending_flags.md             <- Phase checklist (done vs pending)
├── tests-todo.md                        <- 20 specified test cases (backend + frontend)
├── implementation_plan_md/
│   └── custom_domain_mail_performance_analysis.md
├── Food-Ninja-Frontend/                 <- React Native / Expo frontend
│   ├── CLAUDE.md                        <- Frontend-specific rules
│   ├── app/                             <- Expo Router routes (thin wrappers only)
│   │   ├── (admin)/                     <- Seller panel routes
│   │   ├── (auth)/                      <- Login, signup, OTP verify
│   │   ├── (onboarding)/               <- Splash
│   │   ├── (tabs)/                      <- Customer home, search, orders, profile
│   │   ├── restaurant.tsx               <- Restaurant detail entry point
│   │   ├── cart.tsx                     <- Cart modal (27KB — large for a route file)
│   │   └── select-location.tsx          <- Location modal
│   ├── src/
│   │   ├── features/
│   │   │   ├── admin/                   <- CategoryFormModal, ItemFormModal, SharedAddonsTab
│   │   │   ├── auth/
│   │   │   ├── home/
│   │   │   ├── profile/
│   │   │   └── restaurant/              <- RestaurantScreen, AddonSheet, CategorySidebar, etc.
│   │   ├── shared/                      <- Generic UI components (no feature knowledge)
│   │   ├── lib/fetchFn.ts               <- The one HTTP client
│   │   ├── store/
│   │   │   ├── useRestaurantCartStore.ts <- Active cart (addon-aware, use this)
│   │   │   ├── useCartStore.ts           <- Older store (CONFLICT with schema S1)
│   │   │   ├── useUserStore.ts
│   │   │   ├── useLocationStore.ts
│   │   │   └── useSelectedRestaurantStore.ts
│   │   └── utils/
│   └── constants/
│       ├── brand.ts                     <- Color token system (single source of truth)
│       └── config.ts                    <- API base URL
└── ninja delivery service java/         <- Spring Boot backend
    ├── CLAUDE.md                        <- Backend-specific rules
    ├── pom.xml                          <- Dependencies
    └── src/main/java/com/example/ninja/
        ├── controller/                  <- REST endpoints (12 controllers)
        ├── service/impl/                <- Business logic (8 service implementations)
        ├── repository/                  <- JPA queries
        ├── entity/                      <- DB table mappings (14 entities + 2 lookup)
        ├── dto/                         <- Request/response shapes
        ├── security/                    <- JWT filter + util
        ├── exception/                   <- GlobalExceptionHandler
        ├── config/                      <- SecurityConfig
        └── util/PriceCalculator.java    <- Authoritative price calculation utility
```

> **Note (migration):** This brief is a point-in-time snapshot (created 2026-05-21) of the Food Ninja
> project as it existed then — phase status, file sizes, and the structure diagram above describe that
> moment, not necessarily the current state. It has been moved here from `agents/context-keeper-brief.md`
> as part of the Ninjasu_Documentation vault migration. Treat the snapshot content as historical
> orientation; for current shape/status, follow the `anchors:` pattern in newer vault docs and check the
> live code/`Modules/` docs.
