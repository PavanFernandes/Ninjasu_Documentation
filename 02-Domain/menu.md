---
id: ""
title: "Menu Module"
summary: "Defines menu category nesting, item availability flags, addon group scope (SHARED vs ITEM) and pricing/discount rules, combo constraints, and availability precedence for the menu fetch."
type: domain
status: active
apps: [backend, customer, admin]
module: "menu"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/MenuCategory.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/MenuCategoryServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/Item.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/AddonGroup.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/AddonGroupServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/MenuItemAddonGroup.java" }
  - { repo: customer, path: "src/features/admin/services/addon-group.service.ts" }
  - { repo: customer, path: "src/features/restaurant/services/menu.service.ts" }
  - { repo: customer, path: "src/features/restaurant/utils/itemPrice.ts" }
verified_against: "backend@ff5ade334891238d16b8010e372fdbbc502c193e, customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-10-18
---

# Menu Module

Source of truth for menu behaviour — categories, items, addon groups, combos, and
availability. Both the backend and every frontend (customer app, admin dashboard) must
agree on these rules. If a rule changes, update this doc first, then update the code on
both sides.

## Rules

### Category Rules

- Max **2 levels**: a top-level category and one sub-category level. No deeper nesting.
- A category that has sub-categories **cannot have items attached directly** to it.
- A category with no sub-categories **can have items directly**.
- A sub-category's `parent_category_id` must point to a category whose own `parent_category_id` is NULL.
- A category cannot be deleted while items are attached to it.
- Parent category must belong to the same shop as the sub-category.

```
Valid:   Main Course → Chicken Biryani (sub) → items here
Valid:   Starters → items directly (no sub-categories)
Invalid: Main Course → items directly AND also has sub-categories
```

### Item Rules

- `is_available` — restaurant toggles daily (e.g. biryani sold out). Hides item from users.
- `is_active` — admin-level kill switch. Overrides `is_available`. Both must be true to show.
- `item_type = FOOD` **must** have a `food_item_details` row created in the same transaction.
- Every item must be assigned to **at least one category**.
- An item cannot be assigned to a parent category that has sub-categories — must go to the leaf.
- No `price` column on `items`. Price always comes from addon groups.

### Addon Group Rules

#### Group scope (explicit, set at creation time)

Every addon group has a `group_scope` chosen when it is created. The scope is **not** derived from other fields.

| Scope    | Where created                  | `is_required` | Priced options | Discounts | Shared across items |
|----------|--------------------------------|---------------|----------------|-----------|---------------------|
| `SHARED` | Admin → Shared Addons tab      | Must be false | Allowed        | ❌ No     | ✅ Yes              |
| `ITEM`   | Admin → Item form, inline      | true or false | Allowed        | ✅ Yes    | ❌ No (single item) |

**Invariants enforced by backend:**
- `SHARED` ⇒ `is_required = false`. No discounts on any option.
- `ITEM` ⇒ linked to exactly one item via `menu_item_addon_groups`.
- Every item must have **at least one `ITEM`-scoped addon GROUP with `is_required = true`** before it can be saved. This group defines the item's base price. Error message: *"Add at least one item-specific required option to define this item's base price."*

**Shared price coupling is intentional.** When a SHARED group's option price changes, every linked item reflects the change immediately. The admin edit dialog must warn: *"Used by N items — price change affects all of them."* If a restaurant needs per-item pricing for what is currently a SHARED option, they must convert that group to ITEM-scoped on the specific item.

#### Other group rules

- Max **4 addon groups visible per item** (SHARED attachments + ITEM groups combined — this is what the customer sees in the customize sheet).
- No two addon groups on the same item can share the same name (applies after merging SHARED + ITEM views).
- Each addon group must have **at least 1 addon option**.
- `min_select` cannot exceed the number of options in the group.

#### UI Rendering Logic

| `is_required` | `min_select` | `max_select` | UI                                    |
|---------------|--------------|--------------|---------------------------------------|
| true          | 1            | 1            | Radio buttons — must pick exactly one |
| false         | 0            | 1            | Radio + None option — optional single |
| false         | 0            | N            | Checkboxes — pick up to N, optional   |
| true          | 1            | N            | Checkboxes — pick 1 to N, required    |

#### Price Calculation (computed live on frontend, authoritative on backend)

For each selected addon option:

```
effective_discount = COALESCE(addon.discount_percent, item.discount_percent, 0)
selling            = option.price × (1 − effective_discount / 100)
```

Line total = sum of `selling` across all selected options. Base item price is always 0 — there is no separate base price field.

**Discount rules:**
- `addon.discount_percent` is **nullable**. `NULL` means inherit from `item.discount_percent`. `0` is an explicit override (no discount even when the item has one). Any non-null value is an explicit override.
- Discounts only apply to options inside `ITEM`-scoped groups. SHARED options always use `effective_discount = 0`, regardless of which item they're attached to.
- Discount is meaningful only when `option.price > 0`. UI must hide the discount field on free options.

### Combo Rules

- A combo is an `item` with `item_type = COMBO`.
- A combo **cannot contain another combo** as a child item.
- **Circular references** are not allowed (A → B → A).
- If **any child item** has `is_available = false`, the entire combo is **automatically hidden** from users. Compute this at query time.
- Restaurant creates a combo by selecting from items they have already created for that shop.

### Availability Precedence (menu fetch)

An item is visible to users only when ALL of the following are true:

1. `items.is_active = true`
2. `items.is_available = true`
3. `menu_categories.is_available = true` (for every category it belongs to)
4. For combos: all child items must also pass rules 1–2

### Price Rule (Swiggy Constraint)

An item cannot be published with a net price of zero. The enforcement mechanism is the rule above: every item must have at least one `ITEM`-scoped addon GROUP with `is_required = true`, and that group's selected option(s) must define a non-zero base price.

A SHARED priced group alone does not satisfy this rule — base price must be item-atomic.

## Dine-in price and online price (decided 2026-10-18; part (a) live)

**Live since 2026-10-18 (2b.12(a), PR #54):** every option has `addons.price` (dine-in) and `addons.online_price`. POS, counter sale and guest QR read the dine-in price; the customer app (home, search, wishlist, menu with `channel=DELIVERY`, cart) reads the online price; the restaurant's editor (no channel) shows the online price. `online_price` is still generated from `price` in the database, so the two are always equal until 2b.12(b) lets the restaurant set it. One owner each: `AddonPricing` (which price a channel charges), `StartsAtPriceQueries` (starts-at SQL), `AddonDtoMapper` (option DTO).

**Not built yet (2b.12(b)):** points 3 and 4 below, the separate online price edit, and the admin dine-in endpoint. Decision numbers, commission slabs and commission plans live in [schedule-plan.md](../07-Roadmap/schedule-plan.md) (decisions dated 2026-10-17 / 2026-10-18).

**Decided (Samivan, 2026-10-18):**

1. Each add-on option keeps its current price as the **dine-in price** and gains an **online price**. Items still have no price column; the item price is still the sum of the selected options, with the required `ITEM` group giving the base price, using the price of the channel being sold on.
2. Ninjasu POS, counter sale and the dine-in guest QR menu read the **dine-in price**. The customer app (Eat Now and Schedule) reads the **online price**. The restaurant sets the online price.
3. **Online-price cap:** one global platform setting, "max online price over dine-in price" (a percentage). No per-restaurant setting. A save that puts an online price above dine-in price + cap % is refused with a clear message. If Ninjasu tightens the setting later, options already above it are flagged and their dishes are hidden from Schedule until fixed.
4. **Who edits the dine-in price:** only the Ninjasu admin, for every shop with or without POS (set at onboarding from the printed menu, changed on the restaurant's request). The restaurant edits the online price. Every price change is audited.
5. Commission is never built into a menu price and never shown as "restaurant price + X %". It is computed on the order from the restaurant's commission plan (schedule-plan.md). If Ninjasu changes its commission, online prices are updated by hand; nothing is recomputed automatically.
6. The restaurant menu editor shows a read-only line next to each online price: "Ninjasu keeps ₹X, you get ₹Y", computed from the restaurant's plan. Commission is per unit on the online price including the chosen add-ons (schedule-plan.md #45), so a line on an add-on option alone would show the wrong commission; which options carry the line is open (below).

**Open (suggestion in brackets):**

- The cap percentage [suggested 10 %, roughly the median premium restaurants add on Swiggy/Zomato today].
- Empty online price: fall back to the dine-in price [suggested, so Eat Now looks unchanged until a restaurant sets online prices], or require an online price before a dish is sold online.
- Whether item and add-on `discount_percent` apply to both prices [suggested yes].
- An add-on running out before the dish on a Schedule day: reuse the live option's availability flag (shared kitchen) [suggested for v1], or a per-day Schedule flag.
- Which options carry the "Ninjasu keeps ₹X, you get ₹Y" line [suggested: only each base option's online price in the required `ITEM` group, computed by the backend on that option alone; add-on options carry no line].

## Related decisions

- [ADR-0007: Per-Option Images for Shared Addons](../01-Architecture/decisions/ADR-0007-per-option-images-shared-addons.md)

## Where it's enforced

- **Backend** — `MenuCategoryServiceImpl` and `MenuCategory` entity own category nesting/deletion rules. `AddonGroupServiceImpl` and `AddonGroup`/`MenuItemAddonGroup` entities own group-scope invariants, discount inheritance, and the required-base-price check. `Item` entity carries `item_type`, `is_available`, `is_active`.
- **Customer app** — `features/restaurant/services/menu.service.ts` fetches menu data honoring availability precedence; `features/restaurant/utils/itemPrice.ts` mirrors the price-calculation rule for live UI pricing (backend remains authoritative).
- **Admin** — `features/admin/services/addon-group.service.ts` (inside the customer app repo, under the admin feature area) drives addon group creation/editing, including the SHARED vs ITEM scope choice and the shared-price-coupling warning.
