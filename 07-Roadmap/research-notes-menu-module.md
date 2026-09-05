---
id: ""
title: "Innovation Research — Menu Module"
summary: "Competitor comparison of addon-group models (Swiggy, Zomato, Deliveroo, DoorDash) against Food Ninja's, identifying genuine differentiators and gaps to feed the backlog."
type: reference
status: active
apps: [backend, customer, admin]
module: "roadmap"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/util/PriceCalculator.java" }
  - { repo: customer, path: "src/features/admin/components/SharedAddonsTab.tsx" }
verified_against: "backend@ff5ade334891238d16b8010e372fdbbc502c193e, customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-07-11
---

# Innovation Research — Menu Module
**Maintained by:** Innovation Scout
**Created:** 2026-05-21
**Scope:** Addon groups, shared customisations, per-option discounts — competitor comparison vs. Food Ninja's current model.

---

## 1. How Competitors Handle Addon Groups

### Swiggy
- Uses "Customisations" groupings. Groups are named (e.g., "Choose your base", "Add-ons").
- Supports `min_select` / `max_select` per group (functionally identical to Food Ninja's model).
- **Shared modifier groups:** Swiggy's merchant portal allows a modifier group to be created once and applied to multiple items. A price change propagates to all linked items — same as Food Ninja's SHARED scope.
- **No per-addon-option discounts** in the native platform. Discounts are always at the cart level (percentage off entire order) or item level (% off a specific dish). Addon options always appear at their listed price.
- **No nested/conditional modifiers** natively in the Swiggy customer app. The pattern is flat: one level of modifier groups per item.

### Zomato
- Identical flat modifier group structure. Groups have required/optional status, min/max selection.
- "Dish Discounts" (percentage off a dish, not an addon option) are restaurant-funded or split with the platform.
- **No per-addon-option discounts** in Zomato's menu system. Discount logic lives at the item or cart level, never the addon option level.
- Zomato **does not surface shared modifier groups** visually to users — but merchants can reuse groups via the Zomato Partner App.
- **Nested modifiers:** Not natively supported. Merchants flatten them (e.g., "Side Salad with Ranch" as a single option instead of "Side Salad" → [Dressing group]).

### Deliveroo
- Uses "Option Groups" — functionally equivalent to addon groups.
- Supports mandatory vs. optional groups, min/max selection rules.
- **Conditional / nested modifiers:** Deliveroo supports one additional level of nesting via their API (a modifier option can trigger a child modifier group). Their customer app renders this via progressive disclosure — the child group appears only after the parent option is selected.
- **Shared modifier groups:** Deliveroo allows option groups to be reused across items in their restaurant portal.
- **Per-option discounts:** Not a native feature. Discounts are cart-level or item-level.

### DoorDash
- "Modifier Groups" are the equivalent concept.
- Full support for nested modifiers (up to 5 levels deep via DoorDash Drive API), though the customer-facing app typically shows 2 levels.
- DoorDash uses **progressive disclosure UX** for nested groups — child groups only appear after the parent option is picked.
- **Shared modifier groups:** Yes — create a modifier group once, assign to multiple menu items.
- **Per-option discounts:** Not natively supported. "Percentage Dish Discounts" are per-item, not per-option.
- DoorDash's modular design system ensures nested modifiers feel native and fast, not bolted on.

---

## 2. Feature Comparison Matrix

| Feature | Swiggy | Zomato | Deliveroo | DoorDash | **Food Ninja** |
|---|---|---|---|---|---|
| Addon / modifier groups | ✅ | ✅ | ✅ | ✅ | ✅ |
| Required vs. optional groups | ✅ | ✅ | ✅ | ✅ | ✅ |
| Min / max select per group | ✅ | ✅ | ✅ | ✅ | ✅ |
| Shared modifier groups (merchant-side) | ✅ | ✅ | ✅ | ✅ | ✅ (SHARED scope) |
| Per-option discounts | ❌ | ❌ | ❌ | ❌ | ✅ (ITEM scope only) |
| Nested / conditional modifiers | ❌ | ❌ | ✅ (1 level) | ✅ (up to 5 levels) | ❌ |
| Item-level discounts | ✅ | ✅ | ✅ | ✅ | ✅ (item.discount_percent) |
| Cart-level discounts / promos | ✅ | ✅ | ✅ | ✅ | ❌ (not yet) |
| Combo / meal builder | ✅ | ✅ | ✅ | ✅ | 🔄 (Phase 2 planned) |
| Scheduled / advance orders | ✅ | ✅ | ✅ | ✅ | ❌ |
| Subscription / loyalty perks | ✅ (One) | ✅ (Gold) | ✅ (Plus) | ✅ (DashPass) | ❌ |
| API-driven home sections | ✅ | ✅ | ✅ | ✅ | 🔄 (designed, hardcoded now) |

---

## 3. Food Ninja's Genuine Differentiators

### 3a. Per-Addon-Option Discounts (UNIQUE)
Food Ninja is the **only platform in this comparison** that models discounts at the individual addon option level. The cascade logic (`COALESCE(addon.discount_percent, item.discount_percent, 0)`) gives restaurants fine-grained control:
- A restaurant can mark a specific size (e.g., "Large" option in a "Size" group) at 20% off without affecting "Small" or "Medium".
- `addon.discount_percent = 0` as an explicit override (no discount even when item has one) is a sophisticated design that competitors simply don't have.
- **Risk:** This power comes with UX complexity. The admin UI must make it crystal clear when a discount applies to an addon vs. the item vs. the whole. Currently the `SHARED` scope correctly blocks discounts — this is the right guard rail.

### 3b. ITEM vs. SHARED Scope Architecture (DIFFERENTIATED)
Food Ninja's explicit `group_scope` enum (set at creation, not derived) is cleaner than how competitors handle this. Competitors implicitly share groups by assignment, but there's no enforced semantic that says "this group has no discounts and no required selection." Food Ninja's SHARED scope rules (`is_required = false` always, `discount = 0` always) are invariants, not conventions.

### 3c. Price-From-Addons-Only (ALIGNED WITH SWIGGY)
The "no price column on items" model matches Swiggy's internal architecture, where base price is defined by the mandatory modifier group (e.g., "Choose your size — Small ₹99, Medium ₹129, Large ₹159"). The Swiggy constraint label in `menu.md` acknowledges this lineage. It forces every item to have a real, resolvable price — preventing ghost items with ₹0 prices.

---

## 4. Food Ninja's Gaps vs. Competitors

### Gap 1 — No Nested / Conditional Modifiers
- Deliveroo supports 1 level of nesting; DoorDash supports up to 5.
- Real use cases: "Choose sauce type" → if "Spicy" selected → "Choose spice level". Burger builders with progressive topping reveals.
- Food Ninja's current data model (flat addon groups per item, max 4) cannot express this.
- **Phase relevance:** Not needed for launch, but restaurants with complex menus (burger chains, pizza customizers) will hit this wall. File as Phase 3+ consideration.

### Gap 2 — No Cart-Level Discounts / Promos
- All competitors have cart-level promo codes, minimum-order discounts, buy-X-get-Y, free-delivery thresholds.
- Food Ninja has zero discount infrastructure at the cart or order level. The only discount is per-addon-option.
- **Phase relevance:** Needed before growth phase. Without promos, user acquisition campaigns have no mechanism.

### Gap 3 — No Scheduled / Advance Orders
- Swiggy and Zomato both allow 2h–2d advance scheduling.
- Food Ninja has no time-slot or scheduled-delivery concept in the schema or order lifecycle.
- `Shop.opening_time` / `closing_time` exist, but there's no `scheduled_for` field on orders.
- **Phase relevance:** Medium priority. Valuable for lunch pre-orders and catering use cases.

### Gap 4 — No Subscription / Loyalty Program
- Swiggy One and Zomato Gold are retention engines that drive repeat orders.
- Food Ninja has no loyalty or subscription concept at any layer.
- **Phase relevance:** Phase 3+. High GTM value once order volume warrants it.

### Gap 5 — No Shared Modifier Pricing Warning in Admin UX
- Food Ninja's SHARED group model is architecturally correct, but the required UX warning ("Used by N items — price change affects all of them") from `menu.md` is flagged as required but may not be implemented yet in `SharedAddonsTab.tsx`.
- All competitors either don't have this problem (no true shared groups) or show a warning in their merchant portals. Food Ninja must show it.

---

## 5. Key Observations for Backlog

1. **Nested modifiers are a Phase 3 feature** — not urgent for restaurant vertical launch, but the data model should not actively prevent it. The current max-4-groups cap and flat structure will need revisiting when requested.
2. **Cart-level promos are a Phase 2 requirement** — without them, running any discount campaign is impossible. The order model snapshot should include `promo_code_applied` from day one of the orders module.
3. **The SHARED group price-change warning is a NOW requirement** — it's already in the business rules doc and should be in the admin UX before the first real merchant goes live.
4. **Per-option discounts are a genuine differentiator** — but they need admin UX that makes discount cascade rules visible and understandable. Competitors avoid this complexity by not having the feature. Food Ninja has it — make it feel like a feature, not a footgun.

---

*See also:* [backlog-ideas.md](backlog-ideas.md) for the feature ideas this research fed into, and [loopholes.md](loopholes.md) for the SHARED-scope discount cascade bug (L2) this research's cascade-logic description maps to.
