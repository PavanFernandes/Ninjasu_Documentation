# Schedule My Orders: review-fix plan (FINAL v1.1, 2026-11-03)

Source: `/judge` focused run on app commit 55aea5b (correctness, tests, ui, security): F1-F12 plus 13 Lows, grade tests C+, no High. Reviewed by devil's advocate, geld and a blind Codex pass (2026-11-03). Status: FINAL, not built. Decisions D1-D5 are Samivan's (end of file).

Branch: slices 1-3, 5, 6 are follow-up commits on `feature/schedule-my-orders-groups` (local, not pushed, no PR). Slice 4 is its own PR into the app's `feature/schedule`. Nothing goes to `main`. No push or PR without Samivan's word.

## Build status (2026-11-03)
**MERGED 2026-11-03 into the app's `feature/schedule`** (not `main`): PR #35 `feature/fetchfn-get-timeout` (merge `6a2527f`, 4 commits after a final Codex pass) and PR #36 `feature/schedule-my-orders-groups` (merge `7c4b122`, 7 commits after 55aea5b). Manual tests still to run: [manual-test-todo-schedule-my-orders.md](manual-test-todo-schedule-my-orders.md). Open correction to D5: the group list and detail endpoints are not deployed, so the device test cannot use production until the backend is deployed (see section A of that list).
The text below was written before the push; the branches are no longer local-only. Mutation-checked; tsc, eslint and the full jest suite green on each branch.
- Branch `feature/fetchfn-get-timeout` (from `feature/schedule` a76ac9d): da82cef GET timeout, 2955fda 401 token guard, cc74593 unreadable-store fallback plus code map. 13 tests in `__tests__/lib/fetchFn.test.ts`.
- Branch `feature/schedule-my-orders-groups` (on top of 55aea5b): ce9be15 slice 1, f38e1f8 slice 2, 4bfbc4b slice 3, f80afec OrdersScreen test (written by Codex, 11 mutations killed), f2128fb slice 5 tests, e13431e slice 6 fixes.
- Deviations from the plan: slice 2 gates in the screen (`ScheduleGroupScreen`), not in `useScheduleGroupDetail`; the refund amount now shows a dash when missing (frontend rule); dot colour of the status dot is untested (no handle).
- Codex review of the fetchFn diff: its race claim on the 401 guard was rejected (the compare and the clear start in the same continuation); its two body-read claims do not apply because React Native's fetch resolves only after the whole body is buffered (`whatwg-fetch` `xhr.onload`); the unreadable-store point was applied.
- Still open: the GET audit (5 of 39 paths traced; the traced order GETs start `@Async` reconciliation, so an abort is harmless), the 30 s value is a default not a measurement, the device test (D5), `/judge full --base feature/schedule` with all lenses, and the push and PRs (ask first). The two branches are independent: the timeout PR goes into `feature/schedule` first, then the My Orders branch rebases onto it.

## Order of work
1. Slice 4 (fetchFn timeout) and 4b (401 guard, approved), own PR.
2. Slice 1 (request ordering).
3. Slices 2, 3, 5, 6.
4. tsc, eslint, full jest (not only `__tests__/orders`), the mutation scripts for slices 1, 2, 4, 5; then `/judge full --base feature/schedule` with all lenses.
5. Device test with the demo shop (D5), reported as unverified until Samivan runs it.

## Slice 4: fetchFn timeout (F1)
- `src/lib/fetchFn.ts`: AbortController timeout on GET only; POST/PUT/PATCH/DELETE stay untimed unless the caller passes `timeoutMs`. The timer covers `fetch` and `response.json()` and is cleared in `finally`.
- A timeout raises a new `ApiErrorKind` `'timeout'` with its own copy ("taking longer than usual, try again"), added to the typed kind map in `ErrorState.tsx`; it is not folded into `offline`.
- Value: 30 s unless a measurement of the slowest real GET and the Neon wake-up says otherwise.
- Why GET only: `api/payments/verify` and `api/payments/cancel` are POSTs through `fetchFn` (`payments.service.ts:24,30`); an abort after the server captured a payment would show a failure. Uploads, order POST and cart POST use raw `fetch`, so they are untouched.
- Reach: about 128 call sites in 18 files (single-line pattern `fetchFn(` or `fetchFn<...>(`; 194 mentions in 41 files including imports), 60 of them with an explicit mutation method.
- Before the value is set: (a) list the GET paths the app really calls and check each backend controller for state changes (the backend `GET /guest/check` does change state but the app never calls it: no match under `src` or `app`); (b) check the polling screens that can overlap a 30 s GET: KDS 15 s, floor board 20 s, check detail 20 s, order tracking; a timeout there must keep the last data, not blank the board.
- Tests (`fetchFn.test.ts`): timeout fires on GET; timer cleared on success and on error; body stall is covered; POST is not timed; `timeoutMs` opt-in works; 401/403 behaviour unchanged.

### Slice 4b: guard the 401/403 session clear (approved, D6; separate commit)
- Failure (confirmed in `fetchFn.ts:43,56-59`): account A's GET starts, B signs in, A's late 401 calls `clearUserData()` and logs B out. No hook-level gate can stop it.
- Change: remember the token the request was sent with; on 401/403 clear the session only if the stored token is still that one; otherwise throw `SESSION_EXPIRED` without clearing.
- Test: late 401 for an old token leaves the new session intact.

## Slice 1: request ordering (F2, F4)
**`useOrderHistory`** (only importer: `app/(tabs)/orders.tsx:4`):
- Depend on `token`, not `isGuest`, so a refresh or an account switch reloads.
- `createRequestGate`; only the latest `load()` may set `orders`, `error`, `loading`.
- Tag the loaded orders with the token that loaded them and expose them only while `ownerToken === token`; clearing in an effect alone is too late, because the first render after a switch would show the old orders. Also clear on logout and invalidate in cleanup.
- Rule for the app: every hook that holds account data hides and drops it when the token changes. The cart, wishlist, address and notification hooks have not been audited: log as a follow-up.

**`useScheduleGroups` and `useScheduleGroupDetail`** (single-flight polls):
- Keep `silentId` (a request id, not a boolean). A silent poll is skipped only while `silentId` is set. The `finally` clears it only when `silentId === id`, whether or not the request is still current.
- Reset `silentId` on explicit reload, token change, group change and unmount, so an old request can never clear a newer poll's flag or leave it stuck.
- Safety net while the timeout is not live: a silent poll older than 2 intervals is superseded. Keep it after the timeout lands (settling is not guaranteed on every React Native version).
- Tests: logout with a request in flight (both hooks, assert before unmount); poll hangs then explicit reload; poll A superseded by B, A's finally leaves B's flag; login as another user never shows the previous user's orders (history hook).

## Slice 2: group screen before hydration (F12, re-rated Low)
- No sign-in prompt: `AuthGuard` (`app/_layout.tsx:50-71`) redirects a signed-out user away from `schedule-group/[groupId]` once hydrated, after it has skipped `(onboarding)` and an undefined root.
- `ScheduleGroupScreen` renders the skeleton synchronously whenever `!hasHydrated || !token`; `useScheduleGroupDetail` keeps `loading` true in those states and never sets it false for them.
- Known and out of scope: `useUserStore.ts:55` never sets `hasHydrated` if rehydration itself fails; `AuthGuard` has the same dependency.

## Slice 3: colour and contrast (F10, F11)
- `scheduleTone.ts`: drop the `#FF9500` literal; the dot uses `BRAND.colors.amber`; the label uses the existing `BRAND.colors.warningText` (#B45309, `constants/brand.ts:67`), about 5.0:1 on white; check it on `amberLight` (#FFF4E6) and the real card backgrounds during the build.
- Neutral and hint tones use `textSecondary`. Regular order cards keep their coloured text; the same contrast gap there is a follow-up.
- Share tokens only; do not merge the tone map with `STATUS_COLOR` in `orders.tsx` (different status sets).

## Slice 5: tests (F5-F9)
- `OrdersScreen.test.tsx` (new): orders fail and groups succeed (list plus banner); both fail with nothing cached (Retry calls both reloads); both empty and clean; guest; first focus no reload, second focus both reload.
- Hooks: logout while pending, negative poll cases (inactive groups, inactive detail, `pollEnabled` false, later focus with `refreshOnFocus` false), first-load failure, `groupId` change mid-request.
- Screen: group plus error shows the compact banner and Retry calls `reload`; non-PAID line; `refunds: []` shows no heading.
- `scheduleFormat.test.ts`: '2026-00-10', '2026-13-01', '2026-01-00', '2100-02-29', '24:00', '23:60', '12:30:60', '23:59:59'.
- The three small gaps the judge counted as Lows: `scheduleRefundCopy` asserts `.tone` with literals (not circular); `scheduleTypes.ts:23` `hasOwnProperty` guard (`'toString'`, `'constructor'` rows); a non-terminal order in `scheduleMerge`.
- Behaviour change and its test land in the same commit. The mutation scripts are run, not described.

## Slice 6: cheap Lows
Per-source `accessibilityLabel` on the two Retry buttons; card label includes total and refund flag; `activeOpacity` like the sibling cards; remove unused `staleBanner`/`staleText`; payment-status enum to a label; `clearAllMocks` to `mockReset`; remove the dead `useUserStore` mock. Not here: the focus reload showing the pull-to-refresh spinner (needs a silent-focus design).

## Deferred
- F3 pagination of Schedule groups: before one customer can place more than 20 Schedule orders. The endpoint already takes `page` and `size`, so adding it later is not a breaking change.
- `orders.tsx` at 568 lines and `OrdersScreen` at 152 lines: the structure lens has not run; the full `/judge` in step 4 covers it.

## Risks that remain
- The device test writes to production (D5): use the demo shop, record the ids of the test groups, and cancel or delete them before the pilot.
- The GET audit (slice 4) is by the app's GET paths, not every backend controller; finish it before setting the default.
- Polling load: 60 s per viewing user while an active group is on screen (about 1.7 requests/s at 100 viewers); recheck if the pilot passes a few hundred concurrent viewers.

## Locked decisions (Samivan, 2026-11-03)
| # | decision | answer | effect |
|---|---|---|---|
| D1 (F1) | where the timeout goes | shared `fetchFn`, all GETs | slice 4 as above, own PR, lands first |
| D2 (F10) | label colour | darker text-safe amber on Schedule cards only | `warningText` token; regular cards are a follow-up |
| D3 (F12) | guest prompt | not built | slice 2 waits for hydration only |
| D4 (F3) | pagination | deferred | see Deferred |
| D5 (ENV-1) | device test data | the real shop tied to phone 7483752912, a demo restaurant, on production | cleanup step above |
| D6 (new) | slice 4b, 401 guard | yes, add it (Samivan, 2026-11-03) | separate commit after the timeout |

## Review trail
- Devil's advocate (conditions C1-C9) and geld (APPROVED WITH CHANGES; ENV-1, TRACE-1, MIG-1, PLACE-1) are folded into the slices above.
- Codex blind review: confirmed `useOrderHistory` has one importer, `AuthGuard` covers the group route, payments POST goes through `fetchFn`, and raw `fetch` is used for uploads/order/cart. Found and fixed here: the plan contradicted itself (rewritten), the cross-account 401, the first-render window and token refresh in slice 1, the undefined single-flight lifecycle, the hydration flash condition, the existing `warningText` token, and the wrong call counts.
