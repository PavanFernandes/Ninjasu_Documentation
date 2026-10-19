---
id: ""
title: "Browser test TODO — 2b.12(c) dine-in / online price editors and admin Pricing page"
summary: "Full manual browser test list for the web add-on price editors (shop + admin) and the admin Pricing page (cap + review queue), plus build and live-contract checks. Written because none of it has been run in a browser yet."
type: how-to
status: active
apps: [web, backend]
module: "schedule"
anchors:
  - { repo: web, path: "src/shared/components/menu/PriceChoicesEditor.tsx" }
  - { repo: web, path: "src/shared/components/menu/AddonFormDialog.tsx" }
  - { repo: web, path: "src/features/admin/components/OnlinePriceCapCard.tsx" }
  - { repo: web, path: "src/features/admin/components/AddonReviewQueue.tsx" }
verified_against: "web, backend and frontend feature/schedule-2b12c integration branches (2026-10-20); nothing run in a browser yet"
updated: 2026-10-20
---

# Browser test TODO: 2b.12(c) (2026-10-19)

Owner: **S** = Samivan, **C** = Claude. Nothing below has been run in a browser. Code-level checks done so far:
`tsc` and ESLint clean, pure-helper tests green (slice 1: 48, slice 2: 29), `next build` green on slice 1 + key and on slice 2.
**Write only against a Neon branch, never prod** (local web `.env.local` points at ngrok and the backend defaults to prod Neon; a local "write" is a production write).

## A. Setup and build
- [ ] **C** Test from the integration branches `feature/schedule-2b12c` (backend, Ninjasu_Web, Food-Ninja-Frontend); the final PRs to `main` are open as DRAFTS and must not be merged until this list passes. Merge order when it does: backend, then web, then frontend.
- [ ] **S** Create a Neon branch of prod; run the backend locally against it (profile with that `DATABASE_URL`); confirm `select current_database()` is the branch before any write.
- [ ] **C** Point Ninjasu_Web `.env.local` at the local backend (not ngrok/prod). Admin host: serve the admin area on the admin host name the proxy expects (`isAdminHost`).
- [ ] **C** Create two test users on the branch: a shop OWNER (shop with POS off) and a platform ADMIN (`PLATFORM_ADMIN_USER_IDS`). Dev OTP is 1234; test phone 9999999001.
- [ ] **C** `next build` on the merged integration branch (no dev server may share `.next`). Slice 1 + key and slice 2 were each green on their own branches (2026-10-20).
- [ ] **C** Seed: one shop with a required price group and an optional group; cap = 10%.

## B. Restaurant (shop owner) menu editor: slice 1
- [ ] New item: both price fields per choice; submit with dine-in blank, online blank, both 0, negative, text. Messages name the choice and the field.
- [ ] New item, valid (100 / 110) saves; the app price shows 110, the POS price 100.
- [ ] Online above cap (100 / 111): save refused, the SERVER message is shown, form stays open and keeps the values.
- [ ] Dine-in 0 / online 5: refused (zero dine-in must stay zero online).
- [ ] Edit item: dine-in shown READ-ONLY (`₹100`, or `—` if empty), online editable; the restaurant cannot type in dine-in (also check by keyboard Tab).
- [ ] Edit online only: network shows `PUT /api/addons/{id}` with `onlinePrice` and NO `dineInPrice`; no call for untouched rows.
- [ ] Discounted choice: "sells at" line under the row, name box keeps its width; line disappears after the price changes.
- [ ] Add two new choices where the second is over the cap: first is created, error shown, fix the second, Save again: the first is NOT created twice.
- [ ] While Save runs the choice editor is locked (inputs and trash/add buttons disabled); unlock after an error.
- [ ] Remove a saved choice + add a new one in the same Save; order of calls is add/edit first, delete last.
- [ ] Shared addons tab: new addon group (each option both prices), add addon, edit addon (name/image/sort/online). The group card shows `Dine-in ₹x · Online ₹y`, `—` when empty.
- [ ] A STAFF/CHEF member (no manage permission) still sees "Only owners and managers can manage the menu".
- [ ] Audit: restaurant price edits appear in the shop activity log under the Menu module with before/after.

## C. Admin editing a shop's menu: slice 1
- [ ] Admin shop page > Menu: dine-in is EDITABLE in item edit and in the shared addon dialog.
- [ ] Change dine-in only (110 online unchanged): ONE call `PUT /api/admin/shops/{shopId}/addons/{id}/dine-in-price` with `dineInPrice` only (no `onlinePrice`), no shared PUT.
- [ ] Change online only: shared PUT only. Change both: ONE admin call with both prices.
- [ ] Change dine-in AND name: admin call first, then shared PUT; if the second fails the dialog shows the error and a retry resends.
- [ ] Dine-in change that would put the unchanged online price over the cap: refused with the "send both" message; sending both works.
- [ ] Admin dine-in edits write `platform_audit_events` rows; none for a no-op save.
- [ ] Concurrency: restaurant changes online 110 to 120 while the admin dialog is open; the admin changes dine-in only: online stays 120.

## D. Admin Pricing page: slice 2
- [ ] Nav shows "Pricing"; `/admin/pricing` loads on the admin host; on the main host `/admin/*` is 404; a non-admin session gets 401/403 from the API.
- [ ] Cap card: skeleton while loading, saved value shown, "Last changed" shows a date or `—`.
- [ ] Inputs: `10` and `12.5` save; `.5`, `5.`, `00010`, `12.500` are accepted; `101`, `-1`, `abc`, `1e2`, `12.345` show a message and disable Save; unchanged value disables Save.
- [ ] Server refusal shows the server message; draft is kept after a failed save; typing during a save is not lost.
- [ ] Lowering the cap does NOT change existing options; the NEXT save of an over-cap option is refused.
- [ ] Review queue: have the restaurant create an option (section B); it appears with shop link, both prices, date; "Mark reviewed" removes it and writes a platform audit row.
- [ ] Queue with more than 20 rows: Next/Previous, "Page x of y · n waiting"; reviewing the only row of the last page steps back; moving pages while a review is pending does not jump.
- [ ] Empty state, error state (stop the backend) with Retry, double-click on Mark reviewed (one request).

## E. Price parity across the app (T2b-39)
- [ ] Customer app / web storefront: home "starts at", search, wishlist, shop menu, cart, checkout all show the ONLINE price.
- [ ] POS, counter sale and guest QR menu show the DINE-IN price.

## F. Layout and accessibility
- [ ] Item dialog at 1280, 1024, 768 and phone width: no horizontal scroll, price boxes do not overlap the trash button.
- [ ] Light and dark mode, keyboard-only pass through each dialog, screen-reader names ("Dine-in price", "Online price").

## G. Live backend contract (read-only on prod, writes on the branch only)
- [ ] **C** With an admin session on prod: `GET /api/admin/settings/online-price-cap` and `GET /api/admin/addon-review-queue?page=0&size=20` return the shapes in `api_contracts.md`.
- [ ] **C** On the branch: every write call above matches its request body (no bare `price` with the new fields).

## H. Create idempotency (backend `feature/schedule-2b12c-addon-create-idempotency` + web key)
- [ ] The browser sends `Idempotency-Key` on `POST /api/addon-groups/{groupId}/addons` (item edit "Add choice", shared addon "New addon") and the BFF proxy forwards it to Spring (check the request on the backend log).
- [ ] Throttle the network / drop the response after the request is sent: Save again creates NO second option (one row in the group, same id returned).
- [ ] Two different new choices in one Save carry different keys; reopening the dialog uses a new key.
- [ ] Same key, edited body (change the price after a lost response): the backend answers 400 with the idempotency conflict message and the UI shows it.
- [ ] Waiting more than 5 minutes between the lost response and the retry creates a second option (the window is documented as 5 minutes).
- [ ] Item create and addon-group create (inline options) are NOT covered: confirm they still behave as before.
- [ ] Known limits to observe, not fix: (a) fire two identical Saves at once: one succeeds, the other errors, no duplicate; (b) after a lost response, edit the price then Save: 400 idempotency conflict message; (c) after a lost response, close and reopen the dialog and Save: a duplicate is possible (the list shows it).
- [ ] Reusing a key after 5 minutes on the same option replaces the old stored row and creates normally (no 500).
- [ ] A key longer than 64 characters is refused with a clear message (curl, not the UI).

## J. React Native restaurant app (slice 3): real Android device
- [ ] Item create: each choice shows Dine-in and Online price boxes under the name; blank / negative / text show a message under the boxes; both required; valid saves and the customer app shows the online price.
- [ ] Item edit: a saved choice shows its dine-in price READ-ONLY (`₹x`, `—` when empty, "set by Ninjasu" hint) and only the online box is editable; saving sends only the online price (no 403).
- [ ] A choice added in edit mode takes both prices; fail the next step (e.g. a later choice over the cap), fix it, Save again: the first choice is not duplicated, and editing its price before the retry works (it was recorded with its id).
- [ ] Shared addons tab: new group, add option, edit option; the card shows `Dine-in ₹x · Online ₹y`.
- [ ] Layout on a 360dp phone: two price boxes side by side under the name, keyboard (decimal-pad) does not hide the boxes, error text readable; light text sizes via AppText.
- [ ] Airplane mode after the request leaves: Save again does not create a second option (same Idempotency-Key); an edited price after a lost response gives the idempotency conflict message.

## I. Still open from the reviews
- [ ] F6 per-role journey test (restaurant cannot edit dine-in, admin can): write once a mocked-API Playwright harness exists.
- [ ] `AddonFormDialog` save plan has no component test.
