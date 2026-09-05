---
id: ""
title: "UX Reviews — Addon Sheet"
summary: "Screen-level UX review of the customer-facing AddonSheet: 9 issues (radio/checkbox mode mismatches, missing min-select validation, ₹0-addable items) with fixes and priority order."
type: reference
status: active
apps: [customer]
module: "meta"
anchors:
  - { repo: customer, path: "src/features/restaurant/components/AddonSheet.tsx" }
verified_against: "customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-07-11
---

# UX Reviews — Addon Sheet

> Part of [ux-reviews.md](ux-reviews.md) — see that index for the other part and context on how to read these reviews.

## Addon Sheet

Screen: `AddonSheet.tsx` (see `anchors`). Reviewed: 2026-05-21.

### Context

AddonSheet is the customer-facing bottom sheet that appears when a user taps ADD on any
customisable menu item. It lets the customer pick options from addon groups, see the live price,
and add to cart. It is triggered from `RestaurantScreen` via `useCartActions → handleAdd`.

### Issues

#### Issue 1 — Radio-only UI ignores `min_select` / `max_select` for multi-required groups (CRITICAL)

**Current:** The sheet distinguishes groups using only `group.isRequired` — required groups get a
radio button (single-select, `toggleRequired`), optional groups get a checkbox (multi-select,
`toggleOptional`). No use of `minSelect` or `maxSelect` from the API.

**User sees:** Any group with `isRequired = true` is rendered as a radio (pick exactly one). But
`menu.md`'s UI rendering logic table specifies four distinct states: radio-1, radio+None,
checkbox-optional, checkbox-required-range. Specifically, a group with
`is_required=true, min_select=1, max_select=N` must render as checkboxes letting the user pick
1-to-N. The current code collapses this into a radio, silently stripping the multi-pick rule.

**Failure scenario:** A pizza restaurant creates a "Toppings" group with
`isRequired = true, min_select = 1, max_select = 3` (customer must pick at least 1 topping, up to
3). The sheet renders it as a radio. The customer can only pick 1 topping — the `max_select` of 3
is silently ignored. The owner set this up correctly; the UI breaks the intent.

**Fix:** Read `group.minSelect` and `group.maxSelect` from the API. Map to the four UI modes per
`menu.md`:
- `isRequired=true, max=1` → radio (current behaviour is correct for this case only)
- `isRequired=false, max=1` → radio + "None" option prepended
- `isRequired=false, max>1` → checkbox, 0-to-max
- `isRequired=true, max>1` → checkbox, min-to-max, validate before "Add to Cart"

Validate `min_select` on "Add to Cart" before `doAdd()` fires.

#### Issue 2 — "Add to Cart" fires even when required `min_select` is not satisfied (CRITICAL)

**Current:** `doAdd()` runs unconditionally when the user taps the button. Auto-selection
pre-fills the first available option in required groups, but there is zero validation that
`min_select` is actually satisfied for all groups before the item is sent to the cart.

**User sees:** No error. The button fires and the item goes to cart — possibly with fewer addons
than the group rule requires.

**Failure scenario:** If auto-selection fails (e.g. all options in a required group are
`isAvailable = false`), the required group gets no selection, but "Add to Cart" is still active
and tappable. The user adds an item with an empty required group — the cart item has no base
price contribution from that group, leading to ₹0 as the price for the required group's
contribution. The order reaches the backend with an incomplete addon set.

**Fix:** Before calling `doAdd()`, iterate `item.addonGroups`, check each group's `minSelect`
against `selected[group.id]?.length ?? 0`. If unsatisfied, display an inline error below that
group header (not an Alert — inline per Principle 10, validation errors = per-field highlight).
Disable the "Add to Cart" button until all required minimums are met, OR keep it active and show
the inline error on tap.

#### Issue 3 — Auto-selection of first option is invisible to the user (MEDIUM)

**Current:** On mount, the `useEffect` auto-selects the first available option in each required
group (`init[group.id] = [first.id]`). The price in the header immediately reflects this
selection. The user never sees the selection change happen — it is pre-populated silently.

**User sees:** The sheet opens. The header shows "₹150". One radio is already filled. The user
may not notice they have a selection they did not make. On small screens, if the auto-selected
option is out of the initial scroll viewport, the user has no idea why the price is ₹150.

**Failure scenario:** A restaurant has a "Protein" group: Paneer (₹150), Chicken (₹100), Tofu
(₹80). Auto-selection picks Paneer (the first). The customer wanted Tofu. They open the sheet,
see ₹150, assume that's the only price, and add to cart without scrolling. They intended ₹80 but
are charged ₹150.

**Fix:** After auto-selection, scroll the sheet to reveal the auto-selected option OR add a
subtle animation/glow on the pre-selected option when the sheet opens to draw the eye. At
minimum, ensure the first group is always visible in the initial viewport without scrolling.

#### Issue 4 — "Add to Cart — ₹0" is a valid state (CRITICAL)

**Current:** If an item has only optional groups (no ITEM-scoped required group exists in the
response — e.g. a data issue or a SHARED-only item), `totalPrice` will be 0. The button reads
"Add to Cart — ₹0" and fires successfully.

**User sees:** "Add to Cart — ₹0". The item is added at zero price.

**Failure scenario:** Schema rule S2 says every item must have at least one ITEM-scoped required
group. But the frontend places full trust in whatever the API returns. If backend data is
inconsistent (item created before the S2 rule was enforced, or an edit-mode bug), the customer
adds a ₹0 item. This leads to a ₹0 line in the cart and the eventual order.

**Fix:** Guard `doAdd()` — if `totalPrice === 0`, show an inline error: "This item has no price
configured. Contact the restaurant." Do not add to cart. This is a business-class error per
Principle 10 and should appear in-context.

#### Issue 5 — "Clear cart?" Alert is a native dialog over a custom sheet (MEDIUM)

**Current:** When a user adds an item from a different restaurant, a native `Alert.alert()` fires
while the `AddonSheet` bottom sheet is still visible behind it. The alert text reads "Your cart
has items from [shop name]. Clear cart and add this item?"

**User sees:** A native OS dialog appears over the custom sheet. The cancel button says "Cancel"
— ambiguous: does this cancel the alert or the add flow entirely? The shop name could be long and
truncated in the alert title area depending on OS.

**Failure scenario:** A user spent 30 seconds configuring addons (choosing size, extras) for
their selected item. The native Alert pops. They tap "Cancel" by accident (it's on the left, the
more natural thumb position). Their configured selection is discarded — the sheet closes, nothing
was added, and their custom configuration is gone. They have to start over.

**Fix:** Replace the native Alert with an in-sheet confirmation UI: slide the sheet content to a
"clear cart" confirmation view (similar to how other apps handle this), showing what they're
about to lose. If an Alert must be used, ensure "Keep cart" (safe action) is on the right and
"Clear & Add" is on the left — this matches iOS destructive action convention (destructive on
right for action sheets, but in alerts the primary action should be clearly labelled). Also:
re-open the sheet after dismiss so the user's addon selections are preserved.

#### Issue 6 — Max-select enforcement absent for optional checkbox groups (MEDIUM)

**Current:** `toggleOptional` appends freely to `selected[group.id]` with no cap. There is no
check against `group.maxSelect`.

**User sees:** Can tick every option in an optional group even if `max_select = 2`.

**Failure scenario:** A "Choose up to 2 dips" group has 5 options. The customer selects all 5.
The cart stores 5 selected addons for that group. The backend may reject or silently truncate the
order. The customer sees no error in the UI — only a potential surprise at order time.

**Fix:** In `toggleOptional`, check `(current.length >= group.maxSelect)` before appending. If at
max, either ignore the new tap (and show a toast: "Max N options reached") or deselect the oldest
pick.

#### Issue 7 — "Optional" badge uses `#F5F5F5` background on white sheet — near-invisible (LOW)

**Current:** `badgeOptional: { backgroundColor: '#F5F5F5' }` with `badgeTextOptional: { color:
'#888' }`. The sheet background is `#FFF` and the group background is effectively white. The
optional badge is a light grey on white.

**User sees:** The "Optional" label is barely distinguishable from empty space on most device
screens, especially in bright outdoor lighting. The "Required" badge correctly uses `#FFEBEE`
with red text — high contrast.

**Failure scenario:** A customer glances at the sheet quickly. The "Optional" badge fades into
the background. They are unclear whether they must pick from the group. If the auto-selected
required group is already filled, they mistake the optional group for something they must also
fill and feel anxious or confused about the "incomplete" state.

**Fix:** Use `BRAND.colors.sectionBg` (`#F5F5F7`) with a slightly darker text
(`BRAND.colors.textSecondary`, `#666`), and add a `1px` border in `BRAND.colors.borderLight`. Or
use a subtle teal/blue tint to differentiate clearly from the Required red. The visual hierarchy
must be immediately scannable.

#### Issue 8 — Price display anomaly: `+₹0` shown for free options in non-required groups (LOW)

**Current:** In the option row, the price display logic is: `if (sell === 0) return
<Text>Free</Text>`. This shows "Free" correctly for priced-at-zero options. However, options
where the sum of selected free options is 0 still show the correct "Free" label per-option. The
header price shows `₹0` if only free items are selected, with the MRP strikethrough only
appearing if `mrpTotal > totalPrice`. So far acceptable.

BUT: the "Add to Cart" button reads "Add to Cart — ₹0" — "₹0" is confusing as it looks like a
glitch. The customer may think the app has failed to load the price.

**Failure scenario:** Item with optional free toppings and no required group (data bug scenario
from Issue 4). The button reads "Add to Cart — ₹0". Customer hesitates — "Is this a free item? Is
this a bug?" Support tickets increase.

**Fix:** When `totalPrice === 0`, the button should read "Add to Cart — Free" not "Add to Cart —
₹0". Update `formatPrice` to return "Free" when price is 0, or handle inline in the button label.

#### Issue 9 — C2 conflict: promo carousel hardcoding has no direct UX surface in AddonSheet, but the RestaurantScreen it lives within shows customer-facing context (LOW, DOCUMENTED)

**Current:** C2 (HeaderPromoSection hardcoded) is documented. AddonSheet itself is clean of this
issue — it has no promo rendering. The concern here is the customer journey: if the promo
carousel shows false/stale promotions (because it's hardcoded, not API-driven), a customer may
arrive at the addon sheet with a price expectation set by the promo that doesn't match the actual
addon prices.

**Failure scenario:** Hardcoded promo says "20% off all items today". Customer opens AddonSheet
expecting discounts. Addon prices show no discount because the promo wasn't actually configured.
Customer friction, possible support contact.

**Fix:** This is tracked as C2. Resolving C2 (moving promo to API-driven) is the actual fix.
AddonSheet does not need a change here — but the dependency is noted.

### Specific Positive Observations

- **Price is live and instant.** The `useMemo` recomputes on every `selected` state change. Price
  in the header and the "Add to Cart" button are always in sync. This is exactly right per
  Principle 5 (cart mutations must feel instant).
- **MRP + selling price display is correct.** The MRP strikethrough only appears when `mrpTotal >
  totalPrice`. No false discounts.
- **Required groups sort first.** The `sortedGroups` sort puts required groups at top — correct
  priority.
- **Color tokens used consistently.** All colors via `BRAND.colors.*`. No hardcoded hex in the
  runtime render path (only in StyleSheet which is acceptable).
- **BRAND token compliance: almost clean.** Sheet background `#FFF` and handle `#E0E0E0` are
  hardcoded — minor; could use `BRAND.colors.cardBg` and `BRAND.colors.border`. Not blocking.
- **Animation uses `useNativeDriver: true`.** Correct for performance per Principle 7.
- **Interruptible:** Sheet closes cleanly on backdrop tap and Android back button
  (`onRequestClose`). Principle 16 is satisfied for the open/close flow.

### Verdict

**DO NOT SHIP** — Issue 1 (wrong UI mode for multi-required groups) and Issue 2 (no `min_select`
validation before cart add) are CRITICAL correctness failures that will generate wrong cart
compositions. Issue 4 (₹0 items addable to cart) is a financial integrity issue. Issues 5 and 6
are significant friction. All three critical issues can be triggered with valid restaurant
configurations the backend already supports.

**Priority fix order:**
1. Issue 2 — add `min_select` validation gate on `doAdd()` (1 hour)
2. Issue 4 — guard ₹0 adds (30 minutes)
3. Issue 1 — implement all four UI modes per `menu.md` table (half-day)
4. Issue 6 — cap `max_select` on checkbox groups (1 hour)
5. Issue 5 — replace Alert with in-sheet confirmation (half-day)
6. Issues 3, 7, 8 — polish (2 hours total)

---
