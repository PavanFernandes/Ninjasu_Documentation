---
id: ""
title: "Business Logic Loopholes — Food Ninja"
summary: "Eight documented loopholes (L1-L8) where the menu/addon system technically passes validation but violates business intent, each with severity, scenario, and required fix."
type: reference
status: active
apps: [backend, customer, admin]
module: "roadmap"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/MenuItemServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/AddonGroupServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/util/PriceCalculator.java" }
  - { repo: customer, path: "src/features/admin/components/SharedAddonsTab.tsx" }
  - { repo: customer, path: "src/features/restaurant/components/AddonSheet.tsx" }
verified_against: "backend@ff5ade334891238d16b8010e372fdbbc502c193e, customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-07-11
---

# Business Logic Loopholes — Food Ninja
**Maintained by:** Innovation Scout
**Created:** 2026-05-21
**Source:** [principles.md](../01-Architecture/principles.md), [menu.md](../02-Domain/menu.md), context-keeper-brief.md (Schema Decisions + Conflicts)

> A loophole is something that **technically passes validation** but **violates business intent**. These are distinct from bugs (things that break) or TODOs (known missing features).

---

## L1 — Zero-Price Item via Priced SHARED Group Alone
**Severity:** HIGH
**Send to:** QA Strategist (test case), UX Critic (admin warning UX)

**Scenario:**
A restaurant creates an item with only SHARED-scoped addon groups — no ITEM-scoped group. The SHARED group has priced options (e.g., "Drinks Add-on — Coke ₹40"). The customer can see the item, picks the optional Coke, pays ₹40.

But the backend rule is: *every item must have at least one ITEM-scoped addon group with `is_required = true`*. If this is enforced correctly, the item cannot be saved at all.

**The loophole:** The check is per the `menu.md` spec, but it lives in service-layer validation. If the admin uses the raw API (bypassing the admin app), they can `POST /api/shops/{shopId}/menu-items` with only SHARED group links and no ITEM group. The item then exists in the DB with no required group, effectively ₹0 base price, but potentially visible on the menu.

**Business intent violated:** Schema Rule S2 — every item must have a base price defined by a required ITEM group. A ₹0 base item can be ordered for free if the SHARED group options are all optional.

**Fix needed:** Backend must validate in `MenuItemServiceImpl` that at least one linked addon group is ITEM-scoped with `is_required = true` **before setting `is_available = true`**. This must be a DB-layer constraint or a hard service-layer check, not just admin-UI enforcement.

---

## L2 — SHARED Group Discount Bypass via Item-Level discount_percent
**Severity:** HIGH
**Send to:** QA Strategist (test case), Devil's Advocate (architecture)

**Scenario:**
Schema Rule S6 states: discounts never apply to SHARED-scoped addon options. The price formula uses `COALESCE(addon.discount_percent, item.discount_percent, 0)`.

For a SHARED group option, `addon.discount_percent` should always be `NULL` (SHARED groups have no discount). So the COALESCE falls through to `item.discount_percent`. **If the item has a non-zero `discount_percent`, this cascades to options inside SHARED groups.**

Example:
- Item "Chicken Biryani" has `discount_percent = 20`.
- SHARED group "Beverages" is attached, with option "Masala Chai ₹30".
- `addon.discount_percent` for Masala Chai is NULL (correct — no addon-level discount set).
- `COALESCE(NULL, 20, 0) = 20` → Masala Chai sells at ₹24 instead of ₹30.

**Business intent violated:** `menu.md` explicitly states "Discounts only apply to options inside ITEM-scoped groups. SHARED options always use effective_discount = 0."

**Fix needed:** `PriceCalculator.java` and the frontend live-price computation must check `group_scope` before applying cascade. If `group_scope == SHARED`, force `effective_discount = 0` regardless of `item.discount_percent`. This is a formula-level fix, not a UI fix.

**Current state:** `menu.md` documents this as a rule but it's unclear if `PriceCalculator.java` enforces it via group scope check or only by convention (assuming SHARED addon options will always have `addon.discount_percent = 0`).

---

## L3 — Max-4-Groups Cap Enforced Client-Side Only
**Severity:** MEDIUM
**Send to:** QA Strategist (API-level test), Devil's Advocate (backend enforcement)

**Scenario:**
Schema Rule S11 states: max 4 addon groups visible per item (SHARED attachments + ITEM groups combined). This limit exists to prevent overwhelming the customer customization sheet.

However, if this cap is enforced only in the admin UI (e.g., disabling the "Add Group" button after 4), a merchant using the raw API can call `POST /api/menu-items/{itemId}/addon-groups` to link a 5th, 6th, or 7th group. The backend linking endpoint may not enforce the cap.

**Business intent violated:** The customer's addon customization sheet (`AddonSheet.tsx`) is designed for ≤4 groups. Beyond 4, the UX becomes unmanageable, but more critically, the system was never tested for >4 group rendering.

**Fix needed:** `MenuItemAddonGroupServiceImpl` (or equivalent) must count existing groups when a new link is requested and reject if count ≥ 4. The error response should include `"code": "ADDON_GROUP_LIMIT_REACHED"` per Principle 10.

---

## L4 — Deleted Addons Inflate min_select Violation Silently
**Severity:** MEDIUM
**Send to:** QA Strategist (test case), Devil's Advocate (soft-delete design)

**Scenario:**
Schema Rule S12: `min_select` cannot exceed the number of options in the group. If a group has 3 options and `min_select = 3`, this is valid.

But addons use soft delete (`is_deleted = true`). If a merchant soft-deletes 2 options from that group, only 1 option remains active. Now `min_select (3) > active_option_count (1)` — an impossible selection requirement.

The customer sees the customization sheet, must pick 3, but only 1 option exists. The UI either breaks, forces a loop, or lets the user proceed with an invalid selection count.

**Business intent violated:** `min_select` must be validated against *active* (non-deleted) option count at all times, not just at creation time.

**Fix needed:** On addon soft-delete, recheck `min_select` vs. active option count. If the delete would violate it: either auto-adjust `min_select` (with a warning) or block the delete until `min_select` is lowered first. This check must be in `AddonGroupServiceImpl`.

---

## L5 — Cart Key Collision on Identical Addon Selections with Different Quantities
**Severity:** MEDIUM
**Send to:** QA Strategist (test case), Devil's Advocate (cart store design)

**Scenario:**
`useRestaurantCartStore.ts` uses `cartKey = itemId::sortedAddonIds` as the unique key for a cart line. Two separate additions of the same item with identical addon selections produce the same `cartKey` — which is intentional (they should merge into one line item with quantity 2).

The loophole: there is no quantity field tracked beyond a simple increment. If the user adds Item A (addons: X, Y) then navigates away, returns, and tries to add Item A (addons: X, Y) again, the expected behavior is quantity → 2. But if the cart hydration from AsyncStorage has any staleness, or if two rapid taps both trigger the add before the first resolves, you get a race condition that results in quantity being incremented twice from the same base state.

**Business intent violated:** Cart must be the local source of truth (Principle 5 — optimistic, never blocking). Race conditions in the cart update path break the single-source-of-truth guarantee.

**Fix needed:** Cart mutation in `useRestaurantCartStore` should use a reducer pattern (immer-style or explicit immutable update) rather than a read-then-write pattern. Zustand's `set` is synchronous, but if there's any `async` gap before calling `set`, two concurrent taps will both read stale state.

**Note (migration, 2026-07-11):** this loophole was written against the cart store as it existed pre-[cart module rebuild](../02-Domain/cart.md). Re-verify against the current cart store implementation before acting on it.

---

## L6 — No Ownership Check Means Any Authenticated User Can Link Addon Groups to Any Item
**Severity:** HIGH
**Send to:** Devil's Advocate (architecture), QA Strategist (security test)

**Scenario:**
Architecture Principle 15 / Conflict C5: there is no shop ownership enforcement on any menu/addon controller. This means:

1. User A (owns Shop X) authenticates and gets a valid JWT.
2. User A calls `POST /api/menu-items/{itemId}/addon-groups` where `itemId` belongs to Shop Y (owned by User B).
3. The link is created. User A has now modified User B's menu without any permission error.

This is not a theoretical edge case — it's a documented confirmed gap (C5 in the context keeper brief).

**Business intent violated:** Principle 8 — admin endpoints must enforce role AND ownership. Any admin operation on a shop's items must first verify that the requesting JWT user is the owner of that shop.

**Fix needed:** All menu-item and addon-group controllers must add ownership verification: fetch the item's shop → compare shop.owner_id to the JWT user ID → 403 if mismatch. This is Principle 15, already flagged as a production blocker.

---

## L7 — Combo Deletion Does Not Check Child Item References (TODO at line ~252)
**Severity:** LOW (becomes HIGH before Phase 2 ships)
**Send to:** QA Strategist (pre-Phase-2 test), Devil's Advocate (deletion cascade design)

**Scenario:**
`MenuItemServiceImpl.deleteItem` has a TODO at line ~252: check `combo_items` table before deleting an item. Currently, if an item is a child of a combo, it can be soft-deleted independently. The combo then references a soft-deleted child.

Schema Rule S13: if any child item has `is_available = false`, the combo is hidden. But `is_deleted` is not the same as `is_available`. A soft-deleted item with `is_available = true` may still be hidden from the menu but its combo reference is dangling.

**Business intent violated:** Combo visibility should be computed from real child item state. A dangling reference to a deleted child item either causes a runtime exception on combo fetch or silently produces an incomplete combo.

**Fix needed:** Before Phase 2 ships, `deleteItem` must check `combo_items` table. If the item is referenced as a child of any combo: either reject the delete (force the restaurant to remove it from the combo first) or cascade-remove it from all combos and re-evaluate those combos' visibility.

**Note (migration, 2026-07-11):** combos are not yet implemented in the backend (no `Combo`/`ComboItem` entity exists as of this doc's migration) — this loophole applies once the Phase 2 combo work lands.

---

## L8 — SHARED Group "Used by N items" Warning Not Confirmed in Admin UX
**Severity:** MEDIUM
**Send to:** UX Critic (admin UX implementation)

**Scenario:**
`menu.md` explicitly states: when editing a SHARED group's option price, the admin UI must warn "Used by N items — price change affects all of them."

There is no confirmation in the codebase review that `SharedAddonsTab.tsx` implements this warning. The business rule is documented but the UX enforcement point is unverified.

**Business intent violated:** A restaurant owner changing a shared Beverages group's price from ₹30 to ₹50 may not realize this affects 12 items on their menu simultaneously. Without the warning, this is a silent high-impact mutation.

**Fix needed:** `SharedAddonsTab.tsx` must, when showing an edit dialog for a SHARED group, fetch and display the count of linked items. A confirmation step ("This change affects 12 menu items. Proceed?") should gate the save action.

---

## Summary Table

| ID | Description | Severity | Recipient |
|---|---|---|---|
| L1 | Zero-price item via SHARED-only groups (API bypass) | HIGH | QA Strategist + UX Critic |
| L2 | SHARED group gets item-level discount via cascade | HIGH | QA Strategist + Devil's Advocate |
| L3 | Max-4-groups cap enforced client-side only | MEDIUM | QA Strategist + Devil's Advocate |
| L4 | Soft-deleted addons break min_select invariant | MEDIUM | QA Strategist + Devil's Advocate |
| L5 | Cart key race condition on rapid double-tap | MEDIUM | QA Strategist + Devil's Advocate |
| L6 | No ownership check — any user can modify any shop's menu | HIGH | Devil's Advocate + QA Strategist |
| L7 | Combo child deletion TODO — dangling references | LOW→HIGH | QA Strategist + Devil's Advocate |
| L8 | SHARED group price-change warning not confirmed in UX | MEDIUM | UX Critic |
