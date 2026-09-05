---
id: ""
title: "UX Reviews — Item Form Modal"
summary: "Screen-level UX review of the mobile admin ItemFormModal: 10 issues (hidden edit-mode limitations, no data-loss warnings, missing live price preview) with fixes and priority order."
type: reference
status: active
apps: [admin]
module: "meta"
anchors:
  - { repo: customer, path: "src/features/admin/components/ItemFormModal.tsx" }
verified_against: "customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-07-11
---

# UX Reviews — Item Form Modal

> Part of [ux-reviews.md](ux-reviews.md) — see that index for the other part and context on how to read these reviews.

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
