---
id: ""
title: "Architectural Principles, Part 1 — Cart Domain, Verticals & Performance (Principles 1-7)"
summary: "Core funnel insight plus principles 1-7: cart/order/checkout as one domain, food as a vertical, generic home sections, ID-only navigation, local-first cart, checkout re-validation, and render-cost discipline on hot screens."
type: reference
status: active
apps: [backend, customer]
module: "architecture"
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Architectural Principles, Part 1 — Cart Domain, Verticals & Performance (Principles 1-7)

> Part of [principles.md](principles.md) — see that index for the other parts and how to use this file.

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
