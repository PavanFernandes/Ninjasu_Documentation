# Schedule Phase 4: customer app implementation plan (phase by phase)

PROPOSED 2026-11-15, awaiting Samivan's yes. Owner: Lane 2 ([lanes-schedule-p3-p4.md](lanes/lanes-schedule-p3-p4.md)). Repo: Food-Ninja-Frontend, every PR into `feature/schedule`.
Read with: [schedule-phase4-customer-app-plan.md](schedule-phase4-customer-app-plan.md) (what the backend gives, DA rules), the screens in [schedule-phase4-app-design.html](schedule-phase4-app-design.html) (frames F1 to F23, cited below), [schedule-plan.md](schedule-plan.md) (vocabulary, rules).

## Facts this plan rests on (checked 2026-11-15)

| Fact | Where |
|---|---|
| Backend 4.0 is merged into `feature/schedule` (PR #81): cart `payableTotal`, `roundOff`, `members[]`; `serverNowMs`; dish `customizable` + `unavailableAddonIds`; `UNRESOLVED_GROUP {groupId, holdExpiresAtMs, paymentInProgress}` | backend `ScheduleContextDto`, `CartResponse`, `ScheduleCheckoutError` |
| Cart split is merged (PR #92): a cart is now vertical + fulfilment. App calls send no `fulfilment`, which the server reads as Eat Now. **Schedule calls must send `fulfilment=SCHEDULE`** | backend `CartController` |
| The context feed sends dishes with reason ORDERABLE, SOLD_OUT or ORDER_BY_PASSED only (any other reason hides the dish). `orderableSlotIds` is empty unless ORDERABLE | `ScheduleContextDto.DishInfo` |
| A slot is a start time (`startLocalTime`) and a `lastCallAtMs`. No end time | `ScheduleContextDto.SlotInfo` |
| Error codes: `SCHEDULE_CART_SLOT_CONFLICT` (409), `SCHEDULE_CART_SHOP_LIMIT` (409), `SCHEDULE_DISH_REFUSED` (400, `reason`), `SESSION_LOCKED`; checkout 409s `PRICE_CHANGED`, `LINE_UNAVAILABLE`, `AREA_CLOSED`, `ROUTE_SPLIT_SHOP`, `UNRESOLVED_GROUP`; 400 `CART_EMPTY` | backend exceptions + `ScheduleCheckoutError` |
| The app has `src/features/orders/` Schedule files (types, format, tone, refund copy, group screen, hooks) and no `src/features/schedule/` yet | app repo |
| The app has one `useCartStore` and a Eat Now payment hook `useOnlinePayment` built for Eat Now | `src/store/useCartStore.ts`, `src/features/payments/hooks/` |
| App has no CI and tests live in `__tests__/<area>/`; `npm test` = jest | `package.json` |

## Principles (from the plan, repeated so a lane session cannot miss them)

1. The app never decides availability, prices, tax, round-off or refund amounts. It renders server fields; where the server sends none, it shows nothing.
2. Branch on `data.error`, never the HTTP status. Every detail field is optional with a generic fallback.
3. Every Schedule call passes `type=FOOD&fulfilment=SCHEDULE`. The Eat Now cart and store are never touched.
4. Customer text uses plain words: "delivery time", "ordering closed", never "slot", "last call", "checkout" (as a noun for an unfinished order), "reason codes".
5. No new dependency. Everything below uses what the app already has.

## Phase 0: gate and groundwork (no UI)

**Goal:** the decisions and facts 4.1 needs are written down, and the shared types exist.

| Step | Detail |
|---|---|
| 0.1 Record decisions | DONE 2026-11-15 in the lane plan: D3/OD1 (toggle in the Home hero; intro shown once; "How it works" link to replay it; heading "When should we deliver?"). OD3 (app CI) recommended yes, awaiting Samivan's word. "Eat Now delivery in 15 mins" copy goes in 4.1. |
| 0.2 OD3 (if yes): app CI | One small PR: GitHub workflow running `tsc --noEmit`, `expo lint`, `jest` on PRs into `feature/schedule` and `main`. First PR of Lane 2, before 4.1. |
| 0.3 Seed a test area | Device work needs an area, slots and a restaurant with a Schedule menu on the backend. Use the existing admin service-area endpoints (3.1's web page is not built). Samivan or Lane 1 seeds it; record the area name and the test address here when done. |
| 0.4 Types + contracts | `src/features/schedule/types.ts` mirroring `ScheduleContextDto`, the cart `schedule` block, `members[]`, the 409/400 bodies and `ScheduleCheckoutResponse`. Add the same to `skills/api_contracts.md` (plan §3 asks for this in 4.1). |

**Exit:** types compile; contracts doc updated; seed area exists.

## Phase 1: slice 4.1, area bootstrap (frames F1 to F6)

**Branch:** `feature/schedule-4.1-area-bootstrap`. **Size:** M. **Risk:** UI, touches the Home screen.

**New**
- `src/features/schedule/services/scheduleContext.service.ts`: `GET api/schedule/context?lat&lng` through `fetchFn` (guests allowed).
- `src/features/schedule/hooks/useScheduleContext.ts`: reads `useLocationStore`; returns `{context, status, reload}`; stores `serverNowMs - Date.now()` as clock skew; re-reads at the next `lastCallAtMs` and on focus. No polling.
- `src/store/useOrderModeStore.ts`: `{mode: 'EAT_NOW' | 'SCHEDULE', selectedSlotId}`; in memory, default Eat Now.
- `src/features/schedule/components/OrderModeToggle.tsx` (F1), `SlotStrip.tsx` + `SlotTicket.tsx` (a tappable ticket: "Delivery around 12:30 PM", "Order by 11:30 AM", a text countdown "8 min left" that turns amber in the last 15 minutes, a tick when selected, grey when `!orderable`; no progress bar, the server sends nothing to draw one from), `ScheduleStateView.tsx` (F3 to F6: not open yet, paused, no times left, no area).
- `app/schedule-intro.tsx` + `src/features/schedule/components/ScheduleIntro.tsx` (F2). Registered in `app/_layout.tsx`. Param `replay=1` switches it to the replay form: one "Got it" button, back to the menu, never touches `scheduleIntroSeen`.
- `src/features/schedule/components/SlotHeading.tsx`: "When should we deliver?" on the left, a "How it works" link on the right that opens the intro with `replay=1`. Rendered above the delivery times on every Schedule screen that shows them.
- `src/features/schedule/scheduleTime.ts`: skew-corrected "N min left" and "Order by HH:mm" helpers (display only).

**Changed**
- `src/store/usePreferencesStore.ts`: add persisted `scheduleIntroSeen`.
- `src/features/home/components/hero/HeroNavRow.tsx`: location row copy depends on mode ("Delivery in 15 mins" / "Lunch · Today"). The hardcoded "10 mins" becomes 15.
- `src/features/home/components/HeaderPromoSection.tsx`: render the toggle under the nav row when `area.scheduleEnabled`; hide the cuisine dial in Schedule mode.
- `app/(tabs)/index.tsx`: in Schedule mode render the Schedule body (slot strip + state view; the menu arrives in 4.2) instead of the Eat Now list.

**Behaviour**
- Toggle appears only when `context.area?.scheduleEnabled`. First tap on Schedule opens the intro unless `scheduleIntroSeen`; "Not now" also marks it seen and stays in Eat Now.
- State order: no area (F6) → paused (F4) → `windowOpensAtMs` in the future (F3) → no orderable slot (F5) → ready. "Order now instead" and "Change address" actions per the frames.
- Guests browse; no login gate in this slice.

**Tests (jest)**
- `scheduleTime` helpers (skew, amber threshold at 15 min, exactly-at-last-call).
- State resolver: a pure function `resolveScheduleState(context, nowMs)` covering all four states and the ready state.
- `OrderModeToggle` hidden when `scheduleEnabled` is false; intro shown once.
- `HeroNavRow` copy per mode.

**Exit:** on a device, toggle switches modes, intro shows once, each state renders from a real or mocked context. `tsc`, `lint`, full jest green.

## Phase 2: slice 4.2, delivery-time menu and add to cart (frames F7 to F12)

**Branch:** `feature/schedule-4.2-slot-menu`. **Size:** L. **Risk:** UI + cart. **Depends on:** 4.1 merged (it builds on the Home Schedule body).

**New**
- `src/features/schedule/scheduleReasons.ts`: the one mapping table (design F12 table): reason → chip copy and refusal copy, unknown → "Not available". Chips only for SOLD_OUT and ORDER_BY_PASSED; refusal copy covers the rest.
- `src/features/schedule/components/ScheduleMenu.tsx`, `ScheduleRestaurantBlock.tsx`, `ScheduleDishRow.tsx` (greyed + reason chip, no ADD; "Min. order N" from `minOrderQty`; a restaurant with `hasOrderableDish: false` collapses to one grey row).
- `src/features/schedule/services/scheduleCart.service.ts`: `getScheduleCart`, `addScheduleItem` (POST `api/cart/items` with `schedule {areaId, serviceDate, slotId}`, same headers and error shape as `addToCart`), `updateScheduleQuantity`, `removeScheduleItem`, `clearScheduleCart`, `acceptScheduleChanges`, all with `type=FOOD&fulfilment=SCHEDULE`.
- `src/store/useScheduleCartStore.ts` + `src/features/schedule/hooks/useScheduleCart.ts` + `ScheduleCartBootstrap.tsx` (own load on login, foreground refresh, reset on logout; mounted at the app root next to `CartBootstrap`).
- `src/features/schedule/components/ScheduleCartBar.tsx` (F7): delivery time + "Order by" on the left, "View cart · N items" on the right (no amount: the total depends on fees and tax and appears only in the cart, so the bar can't be misread as the price); opens `app/schedule-cart.tsx` (screen arrives in 4.3, so the bar is wired to a placeholder route until then).
- `src/features/schedule/hooks/useScheduleAdd.ts`: ADD flow. Guest → `useLoginPromptStore`. Customizable dish → fetch the menu item (`getMenuItem`) → existing `AddonSheet` with `unavailableAddonIds` removed (F9) → add. Not customizable → add directly with the single required option, as `useCartActions` does today.
- `ScheduleAddDialogs.tsx`: the three 409/400 dialogs (F10 slot conflict with "Clear and switch", F11 restaurant can't join, F12 dish refused) plus a "Refresh menu" button on the refused-dish dialog that re-reads context (F12). F10 and F11 buttons: "Keep 12:30 / Clear and switch", "Keep my cart / Clear and add"; each clears only the Schedule cart, then retries the add once.

**Changed**
- `src/features/restaurant/components/AddonSheet.tsx`: accept an optional `hiddenAddonIds` prop (and an optional `onSubmit` override so Schedule can send its own request). Smallest possible change; the Eat Now path is unchanged.
- `app/(tabs)/index.tsx`: Schedule body renders `ScheduleMenu`; slot taps change `selectedSlotId`; pull-to-refresh re-reads context.
- `app/_layout.tsx`: mount `ScheduleCartBootstrap`.

**Coupling to confirm (CLAUDE.md guard):** `features/schedule` importing `features/restaurant` (`AddonSheet`, `getMenuItem`) and `features/cart` (idempotency key). Both exist today as cross-feature imports elsewhere. Recommended: leave `AddonSheet` where it is, and move `features/cart/utils/idempotency.ts` to `src/utils/` in this slice (one move, imports updated); `getMenuItem` is a service call, imported as a service. Samivan to approve before 4.2 starts.

**Tests (jest)**
- `scheduleReasons` table: every known reason, unknown fallback.
- ADD flow reducer/hook: guest gate, customizable vs direct add, each of the three refusals mapped by `data.error` (including a 400 for refusal, and 409 for the others), `Clear and switch` clears only the Schedule cart.
- `ScheduleDishRow`: greyed dish has no ADD; "Min. order 2" quantity.
- Eat Now regression: `useCartStore` untouched after a Schedule add (assert no calls to Eat Now cart service).

**Exit:** device: add a customizable and a plain dish into the Schedule cart, see each refusal dialog, Eat Now cart unaffected.

## Phase 3: slice 4.3, Schedule cart, checkout and payment (frames F13 to F20)

Money path on the client. Gate: **E3 merged** (Lane 1's "Confirming payment" component, F20) before 3b. Proposed split into three PRs because 4.3 as one PR would be the largest in the lane.

### 3a: cart screen (read-only checkout inputs)
**Branch:** `feature/schedule-4.3a-cart`. **Size:** M.
- `app/schedule-cart.tsx` + `src/features/schedule/components/ScheduleCartScreen.tsx`: slot ticket header, one card per restaurant, address card (existing saved-address sheet), bill card (F13).
- `ScheduleBillDetails.tsx`: renders `subtotal`, `deliveryFee`, `packagingFee`, `taxTotal`/`taxLines`, `roundOff`, `payableTotal` only. When `payableTotal` is null (a price changed or the cart is locked) show no bill and the "Check new price" button that calls accept-changes (F14).
- Cart `schedule.state` SLOT_CLOSED or DATE_PASSED: banner, Pay replaced by "Clear cart" / "Browse times" (F18). "Browse times" keeps the cart and returns to the menu; the first ADD for a new time hits the F10 dialog. `AREA_CLOSED` is its own state (F18b: "Change address").
- Restaurants render as separate cards (F13), each with its own lines.
- Lines: quantity stepper, remove (reuses the Schedule cart service from 4.2).
- **Tests:** bill never sums anything (a test feeds mismatched fields and asserts the rendered values are the server's); `payableTotal === null` hides the bill; each cart state.

### 3b: checkout and Razorpay
**Branch:** `feature/schedule-4.3b-checkout`. **Size:** L. **Needs:** E3 merged.
- `scheduleCheckout.service.ts`: `POST api/schedule/checkout` with `Idempotency-Key`, body `{deliveryAddress, selectedLineIds?, expectedPayableTotal}`; `verifyGroupPayment`, `cancelGroupPayment`.
- `useScheduleCheckout.ts`: the sequence checkout → Razorpay open → verify or cancel → navigate to `schedule-group/[groupId]`. Razorpay options mirror `useOnlinePayment` but: `timeout` = `(holdExpiresAtMs - serverNowMs)/1000 - 10`, prefill from `useUserStore`, `amount` in paise from the server.
- **Idempotency rule:** one key per request body. Persist `{key, body}` to AsyncStorage before sending; replay unchanged after a timeout or relaunch; mint a new key only after PRICE_CHANGED, a line-selection change or an address change; clear on a terminal outcome.
- Error handling by `data.error`: `PRICE_CHANGED` sheet (F15), `LINE_UNAVAILABLE` (F16: SOLD_OUT lines removable and block Pay; HELD lines stay), `AREA_CLOSED` (address message, F18), `ROUTE_SPLIT_SHOP` (generic "can't be ordered right now"), `CART_EMPTY` (refresh cart), `UNRESOLVED_GROUP` (F17: "Pay" / "Cancel order"; with `paymentInProgress`, F17b offers only "View order").
- After the Razorpay sheet closes without success: show the E3 component in its "Checking your payment" form (F20b), poll the group up to 20 s, call `payments/cancel` only if nothing arrived (DA-2).
- Verify returns waiting-for-capture or fails on the network: E3 "Confirming your payment" form, no Cancel, go to the group screen, which polls (`usePollWhileFocused`; a pending group counts as active; Codex note in the plan).
- **Tests:** a state-machine test per outcome (confirmed, pending, dismissed, verify network failure, each 409); key reuse vs new key; `timeout` arithmetic; no amount is computed in the app (`expectedPayableTotal` equals the cart's `payableTotal` string/number as received). Codex read-only review at the PR (money path).

### 3c: recovery and edge states
**Branch:** `feature/schedule-4.3c-recovery`. **Size:** S to M.
- `ScheduleRecoveryBootstrap.tsx` at app root: on launch, if a persisted `{key, body}` or open `groupId` exists, resolve it (replay, or open the unfinished-payment sheet, F17) before the customer can start another checkout.
- Hold-expiry display on the cart/payment path; late-capture message wording agreed with Lane 1.
- **Tests:** app killed mid-checkout (persisted entry replays with the same key); persisted entry cleared on terminal outcome.

**Exit for Phase 3:** device round with a real UPI payment (B2): pay, dismiss, kill-app, price-change, sold-out. Razorpay `timeout` behaviour on Android recorded.

## Phase 4: slice 4.4, cancel and group screen (frames F21 to F23)

**Branch:** `feature/schedule-4.4-cancel`. **Size:** S to M. **Depends on:** 4.3b (lands the customer on the group screen).

- `ScheduleGroupScreen.tsx` (existing, `src/features/orders/components/`): add a paid/booked banner, the delivery-time ticket in the header, and a "Need to cancel?" card when `canCancel` showing `cancelUntilAt` (F21). Existing member, totals and refunds cards stay.
- Cancel confirm dialog with no refund amount (F22); action `POST /api/schedule/groups/{id}/cancel`; after cancel, refetch so the refund rows appear.
- Late cancel per restaurant when that member's `canLateCancel` is true (F23); `POST /api/schedule/orders/{id}/late-cancel`. After it, the order shows "Cancelled" and a Refunds card with "Refund requested" and the server amount (F23b); no timing text ("5 to 7 working days") until the refund policy confirms one.
- Add `canCancel`, `cancelUntilAt`, `lateCancelFromAt`, `canLateCancel` to `scheduleTypes.ts` if missing.
- **Tests:** card visible only with `canCancel`; no client clock comparison for late cancel (a test with a skewed device clock); refund rows after cancel.

**Exit:** cancel a group end to end on a device; late cancel appears only when the server allows it.

## Phase 5: wave check and polish

- Codex read-only review of the combined 4.1 to 4.4 diff; `/gcp judge quick`.
- Device checklist for Samivan: toggle, intro once, each state, add (plain + customizable), each refusal, cart, price change, sold out, pay, dismiss, kill-app, cancel, late cancel, Eat Now still works.
- Copy pass against principle 4 (no "slot", "last call", "checkout" jargon).
- Fixes land as small PRs into `feature/schedule`.

## Merge order and hand-offs

`0.x` → 4.1 → 4.2 → 4.3a → (E3 merged) → 4.3b → 4.3c → 4.4. 4.3a may start before E3 merges; 4.3b may not. 4.1 and 4.2 can be built while Lane 1 works on E2c/E3.

Hand-offs to raise to Lane 1 if met: a "move cart to another time" endpoint (only if the two-step "choose another time" then "clear and switch" feels wrong on device); a window end time on slots (if "around 12:30" is not enough); a reason on the "restaurant can't join" 409 (only when pairing rules exist).

## Open items for Samivan

| # | Item | Recommendation |
|---|---|---|
| 1 | Split 4.3 into 3a/3b/3c PRs | Yes: the money path in one PR is too big to review |
| 2 | Cross-feature imports for `features/schedule` (see Phase 2) and moving `idempotency.ts` to `src/utils/` | Approve the move; keep `AddonSheet` in place with the small prop addition |
| 3 | Heading "When should we deliver?" above the delivery times | Added to the design (F1, F7) with the replay link below; drop it by deleting `SlotHeading` if Samivan objects |
| 3b | Brand pink contrast (white on #FF2D5B is about 3.6:1) | DECIDED 2026-11-15 (Samivan): no change, Schedule buttons use the normal brand pink |
| 3c | Cart bar shows no amount | DECIDED 2026-11-15 (orchestrator, design review): "1 item" only |
| 4 | Who seeds the test area (0.3) | Lane 1 or Samivan before 4.1's device test |
| 5 | Which restaurants can be combined (distance, dish, Ninjasu kitchen) | Not built; future work, needs a design review and a change to schedule-plan decision 40 |

## Status (Lane 2 updates its own rows)

| Phase | PR | State |
|---|---|---|
| 0.x groundwork | | proposed |
| 4.1 | | waiting on Phase 0 |
| 4.2 | | queued |
| 4.3a / 4.3b / 4.3c | | queued; 4.3b waits on E3 |
| 4.4 | | queued |
| Wave check | | queued |
