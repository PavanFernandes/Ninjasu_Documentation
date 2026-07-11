---
id: ""
type: reference
status: active
apps: [backend, customer, admin, rider]
module: "architecture"
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Food Ninja — Architectural Principles

This file holds the **long-horizon decisions** that shape every implementation choice. Source: senior architectural review + additions for delivery-app-specific gaps.

**How to use this file:**
1. Before any non-trivial task, scan for relevant principles.
2. If a task contradicts a principle here, **STOP and warn the user** with: the principle, the specific contradiction, and the suggested resolution.
3. If a principle is missing or needs revision, propose the update before doing the work.
4. Litmus test for every architectural decision: *"Will this help or hurt the app as the delivery business becomes more complex?"*

**Tags:**
- **[SHARED]** — applies to frontend, backend, or the boundary
- **[FRONTEND]** — frontend only
- **[BACKEND]** — backend only

---

## Core Insight — Delivery Apps Are Funnels, Not Feature Collections

```
Discover → Browse store → Build cart → Checkout → Place order → Track → Reorder
```

The cart **becomes** the order. The order **becomes** the reorder source. State flows through the whole funnel.

Treating cart/checkout/orders as separate features that own separate state is the #1 mistake delivery apps make. The principles below all flow from this one insight.

---

## 1. Cart / Order / Checkout Is ONE Domain — Not Three Features [SHARED]

**Wrong model:** `features/cart/`, `features/orders/`, `features/checkout/` each owning their own state.

**Why it breaks:** Home needs cart count badge · Restaurant screen needs "item in cart" state · Checkout reads cart · Order is created FROM cart · Reorder writes back INTO cart · Every vertical adds to the same cart.

### [FRONTEND]
- Cart **state** lives in `src/store/useCartStore.ts` (already exists — good)
- Cart **rules** live in `src/domain/cart/` — **separate from the store**
- Screens never implement cart rules directly. They call the domain layer.
- Store holds state. Domain holds rules. Screens never touch rules.
- Order status modeled as an **explicit state machine** in `src/domain/order/` when built. Screens read state, never infer from booleans.

**⚠️ Cart rules are PER-VERTICAL — not global** (user decision 2026-05-15)
- **Restaurant vertical:** one-shop-only. Adding from another restaurant prompts "clear cart?".
- **Grocery vertical:** multi-shop allowed. Cart can hold items from many grocery stores; checkout may split into multiple orders.
- The cart domain layer must dispatch the "can I add this item?" rule based on the vertical of the items in the cart. **Do not bake "one shop only" into the core cart abstraction** — that's a restaurant-specific rule.

### [BACKEND]
- Cart is **not persisted on the backend**. The cart lives on the device. The backend only sees a cart when it becomes a Place Order request.
- Order lifecycle (`PLACED → ACCEPTED → PREPARING → READY → OUT_FOR_DELIVERY → DELIVERED`, plus `DECLINED`, `CANCELLED`) modeled as enum + explicit transitions. No string comparisons in business logic.

### [FRONTEND] — Cart is a platform concern, not a feature

The cart module sits at a special tier in the frontend folder structure:

- **Other features may depend on cart.** `features/home/`, `features/restaurant/`,
  future `features/grocery/`, future `features/checkout/` all import from
  `features/cart/` to add items, read cart state, or react to cart events.
- **Cart must not depend on any other feature.** No imports from
  `features/home/`, `features/restaurant/`, etc. into `features/cart/`.
  If cart needs something feature-specific (e.g. an item shape), it accepts it
  as a generic input parameter — never imports.
- **Dependency direction is one-way and load-bearing.** A `features/cart/` import
  from `features/restaurant/` is a circular-coupling red flag — stop and resolve
  before writing.

This codifies cart's role as a cross-feature platform (like `shared/` or
`lib/`) while keeping it as a coherent feature folder for ownership clarity.

---

## 2. Food Is A Vertical Implementation — Not The App [SHARED]

**The trap that kills delivery apps:**
```
if (shopType === 'GROCERY') { ... }
if (shopType === 'RESTAURANT') { ... }
```
scattered across cart, checkout, item cards, search.

### [FRONTEND] — even with only food today
- **Timeline:** Grocery is targeted 6–12 months after restaurant launch (user, 2026-05-15). Far enough away to build food concretely; close enough that contract discipline matters.
- Define a **vertical contract** inside `src/features/<vertical>/`: how an item renders, how it's added to cart, **what cart rules apply** (see principle 1), what fields it needs.
- Cart and checkout do NOT know what vertical they're processing. They process "cart items" conforming to a shape.
- Build food **as** an implementation of the vertical contract, not as the app itself.
- Pragmatic rule: build food concretely, but every time a function or component is being written that needs to know "this is a restaurant," ask **could grocery do this differently?** If yes — make the function take it as a parameter/strategy, don't hardcode the restaurant assumption.

### [BACKEND]
- The existing pattern is already correct: `Item` is generic, `FoodItemDetails` is the food-specific extension via PK relationship. **Keep this pattern.**
- Grocery items would add `GroceryItemDetails` similarly — not a new top-level entity tree.
- `Shop.shopType` exists. When adding grocery, do NOT special-case grocery in shared code paths. Add `GroceryShopDetails` if needed.

### Do NOT build now
A generic "plugin system" or runtime vertical registry. Build food concretely. Extract the contract when grocery is real and you have two concrete implementations to abstract over.

---

## 3. Home Is A Generic Section Renderer — Not Hardcoded Sections [SHARED]

Search, recommendations, personalization, offers — these are **backend concerns**. The frontend impact is smaller than people think.

### [BACKEND]
Home API returns a **list of typed sections**, not a fixed shape:
```json
{
  "sections": [
    { "type": "PROMO_CAROUSEL", "title": "...", "items": [...] },
    { "type": "RESTAURANT_LIST", "title": "Near you", "items": [...] },
    { "type": "CUISINE_FILTERS", "items": [...] }
  ]
}
```
Sections are reorderable, addable, removable on the backend **without an app update**.

### [FRONTEND]
- Home screen renders a list of sections by `type`. Knows how to render each type. Does NOT hardcode order or presence.
- Current `PROMO_SLIDES` hardcoded data in `HeaderPromoSection.tsx` will move to API-driven sections.
- Not a CMS. Just "home is a list of typed sections."

Cheap to design now. Painful to retrofit.

---

## 4. Navigation Passes IDs Only — Never Objects [FRONTEND]

Screens fetch or read what they need. Navigation carries identifiers.

- ❌ Don't pass restaurant object as 10 stringified URL params (current `/restaurant` pattern)
- ✅ Store the selected entity in a Zustand slice, pass only `id` as the param

Applies to: restaurant, order, item, search result — every screen-to-screen transition.

---

## 5. Cart Is Local Truth — Network Is Background Sync [FRONTEND]

Cart mutations must feel instant. Never block on network.

- Cart store is the source of truth on the device
- Optimistic updates always
- Any server sync happens in background and never blocks UI
- On checkout, **revalidate the cart against the server** (see principle 6) — but only at checkout, not on every add

---

## 6. Cart Re-Validation At Checkout [SHARED]

**The hidden trap:** user adds items, leaves app for 2 hours, returns, taps Checkout.
- Shop may have closed
- Items may have gone out of stock
- Prices may have changed
- Delivery may no longer cover their location

### [FRONTEND]
On entering checkout, call a re-validation endpoint with the cart contents. Display any changes before the user pays.

### [BACKEND]
Provide `POST /api/cart/validate` (when built) — accepts cart contents, returns per-item availability, current prices, shop open status, deliverability.

This must be designed in from day one of checkout. Retrofitting means rewriting the checkout flow.

---

## 7. High-Frequency Screens Must Stay Cheap To Re-Render [FRONTEND]

| Screen | Hot path | Architecture rule |
|---|---|---|
| Home feed | Long list scroll | FlatList virtualization, image caching, item cards must be pure + memoizable |
| Restaurant menu | Long list + scroll-sync sidebar | The scroll-sync hook is the perf risk. Isolate it. Keep item cards pure. |
| Cart updates | Must feel instant | Local-first mutations |
| Search | Debounced, typeahead | Search state is ephemeral, never goes in global store |

**Cardinal rule:** Item cards are **dumb and presentational**. If business logic leaks into card components, scroll performance dies.

---

## 8. Admin Plan — Web Is Primary, Mobile Is Minimal [SHARED]

**User decision (2026-05-15):** A separate **web app** is planned for shop owners and admins (used on laptop/desktop with full feature set). The mobile app retains only a **minimal admin** surface for on-the-go use cases. Strict role-based permission enforcement on the backend is on the roadmap.

### [FRONTEND]
- Mobile `(admin)` routes keep **only the bare minimum** features a shop owner would do from a phone. New admin features default to web, not mobile.
- `(admin)` features fully isolated in `src/features/admin/`. **Zero shared business logic** with customer features.
- Admin uses its own services even if hitting the same endpoints.
- Treat the mobile admin surface as a **constrained subset** of the web admin — never the source of truth for admin functionality.

### [BACKEND]
- Admin endpoints separated by path prefix (`/api/admin/...` when needed).
- **All admin endpoints must enforce role and ownership** (see principle 15 — currently missing). This is non-negotiable before production: a `USER`-role JWT must not be able to call admin endpoints.
- Same backend serves both web admin and mobile admin — single source of truth.

---

## 9. Cross-Cutting Concerns That Are NOT Features [FRONTEND]

These flow through the whole app and must not become feature folders:

- **Cart** — global store + domain rules layer
- **User session / auth** — global store
- **Location** — global store (selected delivery address, current coords)
- **Connectivity / app state** — observed globally, screens react

**Rule:** If multiple unrelated screens read or write the same state, it is cross-cutting — not a feature. Put it in `src/store/` with rules in `src/domain/<concept>/`.

---

## 10. Error Categories Need Different UX [SHARED]

Delivery apps surface multiple error classes, each needing different handling:

| Class | Example | UX |
|---|---|---|
| Network | offline, timeout | Retry button |
| Auth | token expired, 401 | Re-login flow |
| Validation | missing field, bad format | Per-field highlight |
| Business | item out of stock, shop closed | In-context message |
| Server | 500 | Generic retry/fallback |

### [BACKEND]
`ApiResponse` envelope is consistent. Error `data` carries field-level info for validation. **Add a `code` field** to error responses for business errors (`"code": "SHOP_CLOSED"`, `"code": "ITEM_OUT_OF_STOCK"`). This is the only way the frontend can distinguish business errors deterministically.

### [FRONTEND]
`fetchFn` throws `ApiError` with `message` + `fieldErrors`. Once backend adds `code`, surface it on `ApiError`. Screens choose the right UX based on code/class — not by parsing the message string.

---

## 11. API Idempotency For Mutations [SHARED]

Users tap "Place Order" twice. Network retries duplicate a payment. This must not create two orders.

### [BACKEND]
When orders/payments are built: accept an `Idempotency-Key` header on mutating endpoints. Duplicate keys within a window return the cached response.

### [FRONTEND]
Generate a UUID per mutation attempt. Include it on retries.

Design this in when orders is built. Retrofitting is a nightmare.

---

## 12. Real-Time Order Updates — Push + Polling [SHARED]

**User decision (2026-05-15): Push notifications + polling.** No WebSocket / live map tracking.

### [BACKEND]
- Fire a push notification on every order status transition (`PLACED → ACCEPTED → PREPARING → READY → OUT_FOR_DELIVERY → DELIVERED`, plus `DECLINED`, `CANCELLED`).
- Expose `GET /api/orders/{id}` and `GET /api/orders/active` so the frontend can poll.
- Push payload carries the order id + new status — enough for the frontend to decide whether to refresh.

### [FRONTEND]
- Use **FCM (Android) + APNs (iOS)** via Expo Notifications.
- On the active-order screen: poll `/api/orders/{id}` every 10–15 seconds while the screen is foregrounded. Stop polling on blur.
- Push notification handler routes the user to the active-order screen.
- Do **not** poll when no order is active — battery cost without value.

---

## 13. App Force-Update Mechanism [SHARED]

Delivery apps need a kill switch. A bug in v1.0.3 that lets users place failing orders = revenue loss until app store approves the fix.

### [BACKEND]
A small endpoint or remote config returning: minimum supported app version, optional "soft update available" version.

### [FRONTEND]
On app launch, check version. Below minimum = blocking update screen. Above min but below latest = optional update prompt.

**Not building now.** But document the placeholder — when the first production bug hits, this is the difference between a 4-hour fix and a 4-day fix waiting on app store approval with broken code live.

---

## 14. Frontend ↔ Backend Type Drift Prevention [SHARED]

Frontend interfaces and backend DTOs diverge silently. Field renamed on backend → frontend still uses old name → no compile error → runtime bug.

- Before adding any frontend interface, check the backend DTO source (`dto/` package).
- A backend DTO field change is incomplete until the frontend interface is updated **in the same task**.
- Future: OpenAPI codegen for frontend types from backend Swagger (already exposed). Not building now.

---

## 15. Production Hardening — Backend [BACKEND]

These exist in the current backend and **must be fixed before production launch**. Flag any task that ships before these are fixed:

- ❌ OTP hardcoded to `"1234"` — integrate real SMS provider
- ❌ DB credentials in `application.properties` — move to env vars, scrub git history
- ❌ JWT secret is a default base64 value — generate per-environment secret
- ❌ **No shop ownership enforcement** in any shop/menu/addon controller — any JWT user can edit any shop today. Add `@PreAuthorize` or in-service ownership checks.
- ❌ `ddl-auto=update` in production — switch to Flyway/Liquibase migrations
- ❌ No rate limiting on `/auth/send-otp` — vulnerable to OTP spam / SMS cost attack

---

## 16. Flows Must Be Interruptible And Resumable [SHARED]

Delivery apps operate under constant interruptions: app backgrounding, poor network, payment retries, session restoration.

For every critical flow (cart, checkout, payment, active order), ask before building:
- **What happens if the user leaves halfway and returns later?**
- **Can this flow resume from where it left off?**
- **Is the user's intent preserved across backgrounding or network loss?**

If the answer to any of these is "start over," the state model needs work. This especially affects checkout and active orders — getting it wrong means lost orders and lost revenue.

---

## 17. Availability Is A Backend Decision — Frontend Only Renders [SHARED]

Delivery apps are constrained by: shop open status · delivery range · item stock · kitchen hours · preparation time.

These are **business constraints**, not UI conditions.

- **Backend decides:** whether ordering is allowed, whether delivery is possible, whether an item is purchasable.
- **Frontend only renders:** availability states, disabled UI, fallback messaging.

Never infer availability on the frontend. Never grey out a button because frontend logic "thinks" the shop is closed. Ask the backend.

---

## 18. Orders Are Future Cart Sources — Not Just History [SHARED]

Most delivery platforms eventually become **reorder platforms**, not exploration platforms. Habit beats discovery.

### [BACKEND]
The order model must preserve:
- Item names, images, descriptions **at the time of order** (snapshots — items get renamed/deleted)
- Exact pricing at time of order
- All selected addons/modifiers
- Shop reference

### [FRONTEND]
Reorder reconstructs a cart from a past order, then revalidates against current availability before checkout.

**Rule:** Never design the order entity as "historical display only." It is both an operational record and a future intent signal.

---

## 19. Search State Is Ephemeral — Never Global [FRONTEND]

Search state is query-scoped and UI-driven. It does not belong in global Zustand store.

- Search query, results, loading state → local to the search screen
- Recent searches → persisted locally (AsyncStorage), not in global store
- Ranking, relevance, personalization → backend concerns, frontend just renders what the API returns

---

## 20. Architecture By Stage [SHARED]

We are currently in **Early Stage**. Do not apply patterns from later stages.

| Stage | What to prioritize | What to avoid |
|---|---|---|
| **Early (now)** | Funnel reliability · dev speed · clean state ownership · performance on hot screens | Plugin systems · offline sync · over-generalization · microservices thinking |
| **Growth** | Maintainability · observability · feature flags · role/permission enforcement · error monitoring | Deep abstraction layers · internal frameworks |
| **Scale** | Experimentation · personalization · server-driven rendering · richer caching | Only introduce if operational scale truly demands it |

**Rule:** When someone proposes a pattern, identify which stage it belongs to. If it's a Growth or Scale pattern and we're in Early, flag it.

---

## What NOT To Build — Premature For Current Stage

Flag and refuse if asked without explicit user-approved trigger:

- ❌ Multi-vertical abstraction (build food concretely first)
- ❌ Offline-first / sync engine
- ❌ Generic CMS-driven UI
- ❌ Micro-frontend / module federation
- ❌ Custom navigation abstraction over Expo Router
- ❌ Custom state management (Zustand + TanStack Query is enough)
- ❌ Recommendation engine on frontend (backend concern)
- ❌ Premature component library extraction

---

## Things That CAN Evolve Gradually (Reversible)

- Individual screen internals
- Component extraction (do it as files grow)
- Adding hooks, utils, services
- TanStack Query adoption (incremental)
- Folder reorganization within a feature
- Design token refinement

---

## Resolved Decisions Log

Decisions made on 2026-05-15:

| # | Decision | Implication |
|---|---|---|
| Cart model | **Per-vertical:** restaurant = one-shop; grocery = multi-shop | Cart domain layer dispatches rules by vertical; "one shop only" is NOT a core cart rule (principle 1) |
| Grocery timeline | **6–12 months after restaurant launch** | Build food concretely now, but write code so restaurant-specific assumptions are pluggable (principle 2) |
| Real-time orders | **Push + polling** (no WebSocket / live map) | FCM/APNs + foreground polling on active-order screen (principle 12) |
| Admin app | **Web is primary, mobile is minimal subset** | Mobile admin gets bare-minimum on-the-go features only; web (separate project) gets full feature set; backend enforces strict role/ownership (principle 8 + 15) |

## Open Questions

None outstanding. Add new entries here as they arise.
