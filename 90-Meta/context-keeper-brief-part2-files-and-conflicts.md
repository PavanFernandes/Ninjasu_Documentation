---
id: ""
title: "Context Keeper Brief, Part 2 — Key Files, File Map & Conflicts"
summary: "2026-05-21 snapshot: what each backend/frontend key file does, which files each agent role should read, and the 6 known contradictions (C1-C6) detected in the codebase at that time."
type: reference
status: active
apps: [backend, customer, admin, rider]
module: "meta"
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Context Keeper Brief, Part 2 — Key Files, File Map & Conflicts

> Part of [context-keeper-brief.md](context-keeper-brief.md) — a point-in-time (2026-05-21) snapshot; see that index for the other parts and the migration note on current relevance.

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

