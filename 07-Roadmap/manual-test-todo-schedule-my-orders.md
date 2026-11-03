---
id: ""
title: "Manual test TODO — Schedule groups in My Orders (customer app)"
summary: "Manual test list for the customer app's Schedule groups in My Orders and the group screen, the request-ordering and account-switch fixes, the status label colours, and the shared GET timeout and 401 guard; unit tests and mutation checks pass, but nothing below has been run on a device"
type: how-to
status: active
apps: [customer, backend]
module: "schedule"
anchors:
  - { repo: frontend, path: "app/(tabs)/orders.tsx" }
  - { repo: frontend, path: "src/features/orders/components/ScheduleGroupScreen.tsx" }
  - { repo: frontend, path: "src/features/orders/hooks/useOrderHistory.ts" }
  - { repo: frontend, path: "src/features/orders/hooks/useScheduleGroups.ts" }
  - { repo: frontend, path: "src/lib/fetchFn.ts" }
verified_against: "app feature/schedule 7c4b122 (PRs #35 and #36 merged 2026-11-03); nothing below has been run on a device"
updated: 2026-11-03
---

# Manual test TODO: Schedule groups in My Orders (2026-11-03)

Owner: **S** = Samivan, **C** = Claude. Nothing below has been run. What IS verified in code: `tsc` clean, eslint 0 errors, full jest 217 tests on the My Orders branch (orders suites 171) and 76 on the timeout branch, about 80 deliberate breaks of the code under test that a test catches (the status dot colour is the one exception), and several Codex read-only reviews (the plan, the GET audit, the `fetchFn` diff twice, the My Orders branch). No device, emulator or real backend was involved.

Plan and review trail: [schedule-my-orders-review-fixes-plan.md](schedule-my-orders-review-fixes-plan.md) and [schedule-customer-app-orders-plan.md](schedule-customer-app-orders-plan.md). PRs: app #35 (`fetchFn` GET timeout and 401 guard, merge `6a2527f`) and #36 (My Orders, merge `7c4b122`), both into the app's `feature/schedule`, nothing on `main`.

## A. Setup (decide before any test)
- [ ] **S** **Which backend does the app talk to?** The app's `.env` and `.env.production` both point at `https://api.ninjasu.com`, and the project has one Neon database (production). Per the notes of 2026-11-03 the group list and detail endpoints (`GET /api/schedule/groups`, `GET /api/schedule/groups/{groupId}`) exist only on the backend's `feature/schedule` branch and are NOT deployed. Check this first: if the deployed backend has no such route, the Orders tab shows "Could not load Schedule orders" on production and no group can be seen. Options: (a) run the backend's `feature/schedule` locally against a Neon branch of prod and point the app at it (`EXPO_PUBLIC_API_URL`, ngrok or LAN), the same rule as the refunds list: write only against a branch; (b) the decision of 2026-11-03 (D5) to use the demo shop tied to phone 7483752912 on production only works once these routes are deployed.
- [ ] **S** The demo shop (phone 7483752912) has a Schedule-enabled service area, a slot and menu items; list the ids used.
- [ ] **C** Create test groups through the API (the app has no Schedule creation flow yet): (1) a group with one shop at PLACED, (2) a group with two shops, one ACCEPTED and one DECLINED with a reason, (3) a paid group with a rejected refund with a note, (4) a group with a payment problem (FAILED), (5) a finished group (all DELIVERED), (6) a group with a missing refund amount.
- [ ] **S** Record the ids of every test group and shop order created, and cancel or delete them before the pilot (cleanup step of D5). Test account: phone 9999999001 (dev OTP 1234), or the demo shop owner for the shop side.
- [ ] **C** Device: one Android phone (gesture navigation) and one iPhone with a notch; set the device timezone to something far from IST for section C.

## B. Orders tab
- [ ] **C** Regular orders and Schedule groups show in one list, newest first; a group and an order created at the same time order the same way every refresh. Active items sit under "Active", finished ones under "Past Orders · N".
- [ ] **C** Filter chips appear only when more than one vertical exists; a Schedule group counts as Food; selecting a chip hides the other vertical; a stale selection after a refresh falls back to All.
- [ ] **C** Group card: "Schedule", the slot date and time, the group code, one row per shop with status label and coloured dot, the member total, "Total ₹X", and a "Refund" flag only when the group has a refund. Pressing the card opens the group screen.
- [ ] **C** Skeleton on first load (throttle the network); no flash of "No orders yet" between the skeleton and the list.
- [ ] **C** Empty state ("No orders yet") only when both sources loaded with nothing; guest sees "Sign in to see your orders" and the Log In button works.
- [ ] **C** One source down: block the Schedule endpoint; the orders still show with a banner "Could not load Schedule orders"; its Retry reloads only the groups. Block the orders endpoint instead: groups show with a banner "Could not load your orders", Retry reloads only the orders. Block both with nothing cached: the full-screen error and one Retry that reloads both.
- [ ] **C** Pull to refresh reloads both sources. Switch to another tab and back: both reload (a pull-to-refresh spinner shows briefly, known behaviour, see G).
- [ ] **C** Polling: with an active group on screen the list refreshes about every 60 s (watch the backend log: one request per minute); with only finished groups, or the tab not focused, no polling; polling pauses while a manual refresh is loading.
- [ ] **C** A shop declines in the shop app while the Orders tab is open: within about a minute the card shows "Declined" without a manual refresh.
- [ ] **C** More than 20 groups is a known limit (only the latest 20 show, same as regular orders); confirm nothing breaks, record that older groups are missing (see G).

## C. Group screen
- [ ] **C** Slot date and time match the server's values exactly with the device timezone set far from IST (for example UTC-8 and UTC+12); no day shifts.
- [ ] **C** One block per shop with status label and dot, items with quantity and line total, add-ons under the item, the decline reason ("Reason: ...") only on a declined shop, the member total.
- [ ] **C** Delivery block shows "—" when the label or address is empty. Totals card: delivery fee, packaging fee, round-off, total, in rupees, no raw numbers.
- [ ] **C** Payment line is hidden for a PAID group; a CREATED group reads "Payment pending", FAILED reads "Payment failed", REFUND_PENDING reads "Refund initiated", REFUNDED reads "Refunded"; an unknown value reads "Payment status unavailable".
- [ ] **C** Refunds card: INITIATED "Refund initiated", REFUNDED "Refunded on <date>" (check the date against the refund's processed time), NOT_APPROVED "Refund not approved: <note>"; a refund with no amount shows "—"; the card is absent when there are no refunds. The same words as a regular order (see the refunds list, section I).
- [ ] **C** Skeleton on first load; a failed first load shows the error with Retry that works; a failed refresh keeps the group on screen with the compact "Could not refresh Schedule order" banner and tapping it reloads.
- [ ] **C** Safe area: top inset on the notch phone, bottom inset with gesture navigation on Android; the last card is not hidden behind the home indicator; long content scrolls.
- [ ] **C** Pull to refresh works; an active group refreshes about every 60 s while the screen is focused and stops when you leave it.
- [ ] **C** The screen never offers a link to `/order/[id]`; open it from the Orders tab and from a deep link (`/schedule-group/<id>`) while signed in.
- [ ] **C** Deep link while signed OUT: you land on the login screen, never an error or Retry (AuthGuard redirect); cold start with a stored session: skeleton, then the group, never "Could not load Schedule order" first.
- [ ] **C** TalkBack and VoiceOver: the card reads the date, time, each shop with its status, "total ₹X" and "has a refund"; the two Retry buttons on the Orders tab are announced with their source ("Retry: Could not load Schedule orders").

## D. Account switching and sessions (fixes from the judge)
- [ ] **C** Sign in as user A (with orders and a group), sign out, sign in as user B: the Orders tab never shows A's orders or groups, not even for a frame (screen-record and step through), and shows the skeleton, not "No orders yet", until B's data arrives.
- [ ] **C** Same for a token refresh (expire A's token and sign in again as A): the list reloads and shows A's data again.
- [ ] **C** Sign out while the group screen is open: the screen shows the skeleton while AuthGuard sends you to login; A's group is not visible for a frame.
- [ ] **C** Late 401 for an old token (needs a proxy such as Charles or mitmproxy): hold a GET as A, sign out, sign in as B, release the held request with a 401. B stays signed in. (Unit-tested; this is the end-to-end check.)
- [ ] **C** A genuine 401 for the current session still signs the user out and lands on login.

## E. Timeouts (PR #35)
- [ ] **C** Make a GET hang (proxy that never answers) on the Orders tab with no cached orders: after about 30 s the error state appears with Retry, not an endless skeleton; Retry works once the proxy answers. The title reads "Taking longer than usual".
- [ ] **C** Same on a screen using `ErrorState` (restaurant detail, wishlist): "Taking longer than usual" with the clock icon, not the offline wording.
- [ ] **C** POS check detail (shop role), table loaded, then make the next poll hang: the table and its actions stay on screen with a compact error; they are not replaced by a full-page error. Same check on the kitchen board and floor board (they keep their data) and order tracking.
- [ ] **C** Razorpay test payment on a slow network (throttled, not blocked): payment verify is a POST and is never timed out; the order ends PAID with no failure screen. Upload of a menu image (presigned PUT) is unaffected.
- [ ] **C** A real offline device (airplane mode) still shows the offline wording, not the timeout wording.
- [ ] **S** Measure the slowest real GET (home, search, menu, reports if called) and the Neon wake-up after idle; if either is near 30 s, raise `GET_TIMEOUT_MS` or let that caller pass `timeoutMs`.

## F. Visual
- [ ] **C** Status labels are readable outdoors on both phones: "Waiting for the restaurant", "Accepted", "Preparing", "On the way" in the dark amber (not the old orange); Delivered green, Declined and Cancelled red, unknown status grey. The dot keeps the brighter amber.
- [ ] **C** Group code and add-on lines (grey) are readable.

## G. Open decisions and follow-ups
- [ ] **S** Backend deploy of the group list and detail endpoints (blocks any production use), and whether `schedule_enabled` stays OFF in production (it should until the pilot).
- [ ] **S** Run `/judge full --base feature/schedule` on the merged state (the Skill tool cannot start it; the earlier run was focused and found no High, tests C+).
- [ ] **C** GET audit: 5 of 39 app GET paths were traced to their controllers (the order GETs start `@Async` reconciliation, so an abort cannot cancel it); trace the other 34 for state changes.
- [ ] **C** Audit the other account-scoped hooks (cart, wishlist, saved addresses, notifications) for the same first-render window after an account switch; only the three Orders hooks are fixed.
- [ ] **C** Contrast of the status text on the regular order cards is unchanged (same orange); decide whether to fix both card types.
- [ ] **C** Schedule history load-more, before one customer can place more than 20 Schedule orders.
- [ ] **C** The focus reload shows the pull-to-refresh spinner without a pull (needs a silent focus refresh).
- [ ] **C** `orders.tsx` is 568 lines and `OrdersScreen` 152 lines (over the limits); split when next touched.
- [ ] **C** Customer Schedule creation flow (slot picker, menu, cart, checkout and payment) does not exist in the app yet; the pilot needs it.
- [ ] **C** `CheckDetailScreen` change (keeps the table on a failed poll) has no automated test.
