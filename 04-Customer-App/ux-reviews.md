---
id: ""
type: reference
status: active
apps: [customer, admin]
module: "meta"
anchors:
  - { repo: customer, path: "src/features/restaurant/components/AddonSheet.tsx" }
  - { repo: customer, path: "src/features/admin/components/ItemFormModal.tsx" }
verified_against: "customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-07-11
---

# UX Reviews — Customer App

Screen-level UX review notes. Each section below is a standalone review of one screen: what's
wrong, why it matters, and how to fix it. These are working notes for the frontend team, not
locked decisions — treat "Verdict" and "Priority fix order" per section as the reviewer's
recommendation at the time of review, not a shipped commitment.

---

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

## Item Form Modal

Screen: `ItemFormModal.tsx` (see `anchors`). Reviewed: 2026-05-21.

### Context

ItemFormModal is the mobile admin form (59 KB, 1201 lines) for creating and editing menu items.
It is used by restaurant owners on their phone. It handles: item metadata (name, description,
food type, prep time), image upload to S3, category selection, required ITEM-scoped addon groups
(which define the item's base price), optional ITEM-scoped groups, and attaching SHARED addon
groups from the shop library. It is the most complex form in the admin panel.

### Issues

#### Issue 1 — Edit mode silently blocks adding/removing addon groups with a terse italic note (CRITICAL)

**Current:** In edit mode (`isEditMode = true`), `addRequiredGroup`, `addOptionalGroup`, and the
shared-attach button are all hidden (wrapped in `!isEditMode &&`). At the bottom of the scroll, a
single small italic `editNote` reads: *"To restructure addon groups or change shared attachments,
delete and recreate the item."*

**User sees:** They open an existing item to edit it. The "Add required group" and "Add item-only
group" buttons have disappeared with no explanation until they scroll all the way to the very
bottom of a long form. They may think it's a bug.

**Failure scenario:** A non-technical restaurant owner — say, Rahul who runs a biryani shop —
opens an item to add a new "Add-ons" optional group he forgot when creating the item. He scrolls
the form, sees no button to add a group anywhere, and cannot find the note (it's at the bottom,
in `#aaa` italic text). He closes the form confused. He doesn't know he must delete and recreate
the item. He calls support. This is a real scenario for mobile-first admin users who are not
developers.

**Fix (two options):**
- Option A — Surface the limitation immediately. Place the "delete and recreate" notice as a
  visible banner at the TOP of the addon groups section when in edit mode, not at the bottom. Use
  a warning-level callout (amber background, icon). This makes the constraint discoverable before
  the owner wastes time looking for the button.
- Option B — Actually support adding new groups in edit mode. The backend supports
  `MenuService.addAddonToGroup` and creating new groups — `handleEditSave` simply doesn't wire up
  group creation. This is the correct long-term fix. For now, Option A is the minimum.

#### Issue 2 — Pricing block: hidden group creation issue — still present, partially mitigated (CRITICAL)

**Current:** The form starts with `requiredGroups = [makeBlankRequiredGroup()]` — one blank
required group pre-populated. The group has name `"Size"` (default) and one blank option `{
name: '', price: '' }`. The validation (`validate()`) correctly requires at least one required
group AND at least one required option with `price > 0`. So the form does gate correctly on
submission.

However — the gate fires only at submission time (tapping "Save Item"). There is no live feedback
during form filling that tells the owner: "your item currently has no valid base price." A
restaurant owner who skips the Required Groups section entirely (scrolls past it) only discovers
the error when they tap Save and get: "At least one required option must have a price greater
than 0" — a generic bottom error far from the group that caused it.

Additionally: the validation error `errors.requiredGroups` renders ABOVE the "Add required group"
button, NOT adjacent to the blank group that triggered the error. The blank group itself shows no
inline error — only the section-level error below the last group's block.

Status vs known issue: the core "pricing block hidden group creation issue" referenced in the
brief appears to be the scenario where a SHARED group exists but no ITEM-scoped required group is
present. The current form mitigates this by: (a) always initialising with one blank required
group, and (b) validating that at least one required priced option exists. The mitigation is
partially effective — it's not possible to SUBMIT without a required group. BUT it IS possible to
interact with the form for minutes without understanding why price isn't set, because there is no
live price preview.

**Failure scenario:** A restaurant owner creates an item, fills in name/description, uploads a
photo (S3 upload takes ~10 seconds), picks categories, then scrolls to the pricing section. The
blank "Size" group confuses them — they don't know "Size" means they must create options with
prices here. They type "Size" in the name, then add one option "Regular" with price "0" (thinking
base price is free). They tap Save. Error: "At least one required option must have a price
greater than 0." They don't understand why. The error is displayed at the section level, not on
the ₹0 price field. This is a validation-class error that should be per-field per Principle 10.

**Fix:**
1. Move the zero-price error to be inline on the specific price field that is ₹0 within a
   required group (per-field highlight, Principle 10).
2. Add a live price summary line at the top of the "Required Item Groups" section: "Base price:
   ₹–" (dashed when no price is set) → "Base price: ₹150" (when a valid price is configured). This
   gives the owner real-time confirmation that the pricing block is correctly set up.
3. Rename the default group name from `"Size"` to empty string with placeholder `"e.g. Size,
   Portion, Protein"` — "Size" as a default is confusing when the restaurant's item genuinely
   doesn't have sizes (e.g. a fixed-portion item).

#### Issue 3 — "Delete and recreate the item" is a destructive hidden requirement with no data-loss warning (CRITICAL)

**Current:** Edit mode prevents adding new addon groups. The only path to restructuring is
deleting the item and recreating it. The `editNote` mentions this but gives no warning about
consequences. Item deletion is not handled within this modal — the owner must navigate back to
find a delete action elsewhere.

**User sees:** "To restructure addon groups or change shared attachments, delete and recreate the
item." (Small italic grey text.)

**Failure scenario:** A restaurant owner with an item that has been live for weeks (with reviews,
order history, etc.) needs to add a new option group. Following the editNote instruction, they
delete the item. The item ID is gone — any order history referencing that item ID now points to a
non-existent item. If the order snapshot doesn't fully capture item data (a risk noted in
Principle 18), reorder functionality breaks for past customers. The owner had no warning this
would happen.

**Fix:** (a) In the editNote, add explicit consequences: "⚠️ Deleting an item will remove it from
your menu permanently. Past orders will still appear in history, but reordering from them may not
work correctly." (b) Long-term: implement proper add-group support in edit mode (see Issue 1,
Option B).

#### Issue 4 — Image upload has no maximum file size guard or format validation (MEDIUM)

**Current:** `handleImagePick` uses `expo-image-picker` with `quality: 0.8`, `aspect: [1,1]`. It
calls `fetch(asset.uri)` to get a blob, then PUTs it to S3 via presigned URL. There is no check on
`asset.fileSize`, `asset.type`, or maximum dimensions before attempting the upload.

**User sees:** A "Uploading..." spinner while a 15 MB RAW photo slowly uploads (or times out).

**Failure scenario:** A restaurant owner selects a screenshot of their paper menu (a 4K JPEG, ~8
MB). The upload starts (spinner shows). On a poor mobile data connection, it times out after 30
seconds. Error: "Could not upload image." The owner has now spent 40 seconds with the form locked
on the upload step and has no idea what went wrong or what size is acceptable.

**Fix:** Before starting the upload:
- Check `asset.fileSize`: if > 5 MB, show an inline error (not Alert): "Photo is too large. Please
  choose one under 5 MB."
- Accepted formats: JPEG/PNG only — check `asset.mimeType`.

This also means the `isUploading` spinner should be accompanied by a text explanation:
"Compressing and uploading…" not just a spinner.

#### Issue 5 — Form closes on backdrop tap, discarding all unsaved work with no confirmation (MEDIUM)

**Current:** `<TouchableWithoutFeedback onPress={close}>` wraps `<View
style={StyleSheet.absoluteFill}>`. Any tap outside the modal (on the backdrop) fires `close()`
immediately, calling `onClose()` after an animation. No "discard changes?" confirmation.

**User sees:** Nothing — the form disappears instantly.

**Failure scenario:** A restaurant owner has spent 5 minutes on the form: uploaded an image (S3
key stored in state), entered item name, description, added 3 option groups. While filling the
last price field, the keyboard dismissal causes a scroll bounce. Their thumb lands on the
backdrop. The form closes. All work is gone. The S3 image was already uploaded — it's an orphaned
object in S3. The owner must start over.

**Failure scenario 2 (Principle 16):** The app is backgrounded during form fill (phone call). On
foreground, the form state is local React state — it is not preserved across full app kills. This
is acceptable for Early Stage, but the backdrop dismiss risk compounds the problem.

**Fix:** Detect "dirty" state: any field changed from its initial value → `isDirty = true`. On
backdrop tap OR X button press, if `isDirty`, show a confirmation: "Discard changes?" with "Keep
editing" (primary) and "Discard" (secondary/destructive). This is standard pattern for all admin
forms.

#### Issue 6 — Category selection: parent categories are untappable with no visual cue that they're disabled (MEDIUM)

**Current:** `toggleCategory(id, isParent)` returns immediately if `isParent === true`. The
parent category label renders as a plain `<Text>` (not a chip). Sub-categories render as
selectable chips. The distinction between "label" and "selectable chip" is purely positional —
there is no explicit disabled indicator on parent labels.

**User sees:** A list of category names. Some look like headers (plain text), some look like
chips. The logic is clear if you know the data model (parents can't hold items). It is NOT clear
to a restaurant owner who just sees names.

**Failure scenario:** A restaurant has: "Biryanis" (parent) → "Chicken Biryani", "Veg Biryani"
(sub-cats). The owner wants to assign the item to "Biryanis" (the parent). They tap "Biryanis".
Nothing happens. They tap again. Nothing. They assume it's a bug. They don't realise they need to
pick the sub-category.

**Fix:** Add a visual indicator on parent labels: a small lock icon or "(select a sub-category)"
sub-text. OR show parent names in a muted style with a chevron-down to indicate they are
non-interactive group headers. This is a taxonomy comprehension problem — the UI must teach the
rule, not silently ignore taps.

#### Issue 7 — Options in edit mode: price field is editable but the ₹ symbol input state is not connected to a "dirty" or "update pending" signal (LOW)

**Current:** In edit mode, option name and price fields are all editable (the `editable` prop is
not conditionally set for existing options — only the group name is gated by
`canEditStructure`). `syncGroups` in `handleEditSave` calls `MenuService.updateAddon(o.id,
payload)` for every existing addon on save. This is functionally correct.

**User sees:** An existing option price of "120". They change it to "150". No visual indicator
that this change is staged (pending save). The save button says "Update Item" which implies
everything is being saved — that's technically correct but gives no per-field feedback.

**Failure scenario:** Owner changes the price of "Small" from ₹120 to ₹150, then notices the name
field also needs updating. They change the name. They accidentally tap the X button (see Issue 5
— no discard confirm). The price change is lost. Because there's no "staged change" indicator,
they may not realise the price wasn't saved and publish the item at ₹120.

**Fix:** Low-cost fix: add a subtle "unsaved changes" banner at the top of the form whenever any
field has been edited. Highlight edited price/name fields with a subtle border color change
(amber border) while changes are pending. This is the minimum UX for financial data editing.

#### Issue 8 — "Attach shared addon" section is hidden from edit mode with no explanation of why (MEDIUM)

**Current:** The "Attach shared addon" button and the detach (X) button on existing shared
attachments are hidden in edit mode (`!isEditMode &&`). So in edit mode, the owner can SEE their
attached shared groups (the rows are shown) but cannot detach them or add new ones. The editNote
at the bottom is the only explanation.

**User sees:** A list of attached shared addons with no way to interact with them. No detach
button. The X icon is gone. They try tapping the row — nothing happens. No affordance explaining
this is read-only in edit mode.

**Failure scenario:** An owner wants to detach "Extra Sauce" from an existing item because the
restaurant stopped offering it as an add-on for that specific item. In edit mode, they can't. The
editNote says to delete and recreate — an extreme action just to change a shared group
attachment.

**Fix:** Detaching a SHARED group in edit mode is a backend-supported operation
(`SharedAddonGroupService.attachToItem` with a detach variant). The edit mode should support
detach. This should be a quick fix — re-enable the detach button (the X) in edit mode and call the
unlink API on save. This is less risky than "add a new group" (Issue 1).

#### Issue 9 — "Required groups" section: minimum 2-option rule is enforced at submit but not inline during editing (LOW)

**Current:** Schema rule S12 states each group must have more than 1 addon option. `validate()`
checks `if (group.options.length < 2) e[...] = 'Each group needs at least 2 options'`. This fires
only on submit.

**User sees:** While filling in options, after adding the first option, the "Add option" link
appears. There is no indicator that 1 option is insufficient. The error only appears when they
tap Save.

**Failure scenario:** Owner adds a "Size" group with one option "Regular" at ₹120. They assume
one option is valid (single price = single choice). They tap Save — error. They don't understand
why — the error says "Each group needs at least 2 options" but the UX never told them this rule
upfront.

**Fix:** Under each group block, show a persistent counter: "2 options minimum" with a green
checkmark when ≥2 are added. Or show the "Add option" link with a visual hint "Add at least 1 more
option" until 2 exist. This proactive guidance eliminates a category of submit-time errors for
non-technical owners.

#### Issue 10 — C2 impact: no UX signal that promo pricing shown elsewhere may differ (LOW, DOCUMENTED)

**Current:** C2 is a documented conflict: `HeaderPromoSection` has hardcoded promo data.
ItemFormModal has no promo-related controls — this is correct, promo is a separate concern.
However, restaurant owners using the admin form have no visibility into whether their item is
currently part of an active promotion, what promotional price a customer would see, or whether
the discount will be reflected in the AddonSheet price.

**Failure scenario:** Owner sets "Size → Regular = ₹120". A hardcoded promo on the home screen
shows "20% off all items". The owner doesn't know if this applies to their item. They see ₹120 in
the admin form. The customer sees (potentially) ₹96 in the AddonSheet. There is no feedback loop
for the owner.

**Fix:** This is a C2 resolution task (API-driven promos). Once promos are API-driven, the item
form can show: "Active promotions on this item: [list]" as a read-only section. Noting here so
it's designed in — retrofitting this later is harder.

### Specific Positive Observations

- **Form validation architecture is solid.** The `errors` state with key-per-field is correctly
  structured (Principle 10, validation = per-field highlight). Most fields correctly clear their
  error when the user starts typing. This is the right pattern.
- **The group limit guard is correctly enforced.** `visibleGroupCount < VISIBLE_GROUP_LIMIT`
  correctly counts required + optional + shared against the 4-group cap from `menu.md` S11. Both
  the UI (button opacity) and validation block correctly.
- **Group uniqueness check works.** The `seen` set approach correctly catches duplicate group
  names across all three group types.
- **Required group must have a priced option — enforced.** `anyRequiredPriced` correctly flags if
  all required options are ₹0. This directly implements the "Swiggy Constraint" from `menu.md`.
- **S3 upload with presigned URL is the correct pattern.** Upload feedback (spinner + "Uploading..."
  text) is present.
- **Image load error handling is correct.** `imageLoadError` state + `onError` on ExpoImage
  prevents broken image frames.
- **KeyboardAvoidingView is present.** Correct for forms with many text fields.
- **`keyboardShouldPersistTaps="handled"` on ScrollView.** Correct — prevents keyboard dismiss on
  scroll, which would be frustrating during form filling.
- **BRAND color tokens used for primary UI.** Most StyleSheet entries use `BRAND.colors.primary`.
  Some hardcoded values remain (`#F0F0F0`, `#111`, `#888`) — these are in StyleSheet constants
  (not runtime logic) and are low priority.

### Verdict

**DO NOT SHIP** — Three critical issues make this form dangerous for real restaurant operators:

1. **Issue 1** — Edit mode removes the "Add group" button with no explanation until the bottom of
   a long scroll. Non-technical owners will think it's a bug and call support.
2. **Issue 3** — The "delete and recreate" requirement has no data-loss warning. An owner could
   wipe a live item with order history associations.
3. **Issue 5** — Backdrop tap silently discards all work including an already-uploaded S3 image.
   This will generate rage and support tickets from day one.

**Priority fix order:**
1. Issue 5 — Dirty-state confirmation on close (2 hours). Ship-blocking on all admin forms, not
   just this one.
2. Issue 1 — Surface edit-mode limitation at top of addon section, not bottom (30 minutes for the
   banner; half-day for proper edit-mode group-add support).
3. Issue 2 — Live price preview + per-field zero-price error (half-day).
4. Issue 8 — Re-enable shared group detach in edit mode (2 hours).
5. Issue 3 — Explicit data-loss warning in editNote (30 minutes).
6. Issues 4, 6, 7, 9 — Polish (1 day total).
7. Issue 10 — Design in when C2 is resolved.
