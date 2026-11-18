# Shared helpers registry

One owner per cross-cutting job, per repo. Read by `/gcp` step 8b (grep the job's row, do not read the whole file) and by the `/judge` reuse lens (the Intentional variants rows are settled decisions, not findings).

**Rules.** Before writing a helper for a job listed here, use or extend its owner (add a parameter or an option). A job with no owner: search the repo by mechanism once, then add the row in the same PR. A copy that must stay different gets a row under Intentional variants with the reason, and a name that says the difference. Last full census: 2026-11-17 (`node <great-sage-core>/good-coding-practice/scripts/census.mjs <repo> --source-only`).

## Food-Ninja-Frontend (app)

| Job | Owner | Contract | Known copies (merge targets) |
|---|---|---|---|
| money display | `src/utils/formatCurrency.ts` `formatCurrency(amount, currency='INR', { nullText = '' })`; `formatCurrencyOrDash(amount, currency)` for server money that can be absent | amount is a number or numeric string; null, undefined or NaN -> `nullText`; rounds to 2 decimals first, then a whole number shows no decimals, else 2; symbol map INR/USD/EUR, else the code and a space; `currency` null prints no symbol | none: the cart and Schedule `formatMoney` copies were merged in PR3. The rest are Intentional variants below |
| money arithmetic (paise) | `src/utils/money.ts` (`toPaise`, `paiseToRupees`, `parseRupeesToPaise`, `paiseToInputText`) | integer paise; parse returns null on bad text | none found |
| device time zone | `src/utils/deviceTimeZone.ts` `deviceTimeZone()` | `Intl.DateTimeFormat().resolvedOptions().timeZone` | none |
| Schedule dates and clock times | `src/shared/utils/dateTimeFormat.ts` (`formatServiceDate`, `formatSlotTime`, `formatClockTime(epochMs, timeZone)`) | formats in the zone it is given and never reads the device zone itself | date formatting also in `src/features/orders/refundCopy.ts`, `src/features/pos/components/CheckBillScreen.tsx`, `src/features/pos/components/PosHistoryScreen.tsx` (not yet compared) |
| reason code -> customer text | Schedule: `src/features/schedule/scheduleReasonCopy.ts` (one table per surface: `ADD_REFUSAL_COPY`, `CART_LINE_PROBLEM_COPY`, `CHECKOUT_LINE_REASON_COPY`; a sentence two surfaces share is defined once) | the add refusal, a cart line and a refused checkout use different codes and word the same code differently, so each surface keeps its own table (unifying the wording needs the owner's approval); an unknown code falls back to a generic line, or to null for a cart line. Callers: `scheduleReasons.ts`, `scheduleCartState.ts` `lineProblem`, `checkout/scheduleRefusalCopy.ts` | Eat Now `src/features/cart/components/CartLineRow.tsx` (not Schedule, not compared) |
| idempotency key | `src/utils/idempotency.ts` `newIdempotencyKey()` | UUID v4, `crypto.randomUUID` first | pure copy in `src/features/cart/utils/idempotency.ts` (unscheduled) |
| API error text | `ApiError` from `src/lib/fetchFn.ts` | `message` is NOT always customer text: 401/403 throw the codes `SESSION_EXPIRED` / `ACCESS_DENIED` (also in `cart.service.ts`, `orders.service.ts`), a 4xx with no body gives `Request failed (<status>)`, a 5xx with no body gives `FRIENDLY_SERVER_MESSAGE`; otherwise it is the backend's `message`. Check the code and `kind` before showing it; field errors are in `fieldErrors`. No shared code-to-text mapping exists yet | none found |
| category icon | none | | `getCategoryIcon` pure copy in `src/features/pos/components/PosCategorySidebar.tsx`, `src/features/restaurant/components/CategorySidebar.tsx` (unscheduled) |

### Intentional variants (app)

| Name and paths | Why it stays different |
|---|---|
| `formatMoney` in `src/features/orders/components/OrderSummaryCard.tsx` | INR only; `toFixed(2)` with a trailing `.00` stripped and no rounding step. Merging changes how an order's bill reads; compare against the owner before merging |
| `formatMoney` in `src/features/admin/components/ShopOrdersScreen.tsx` | whole rupees (`toFixed(0)`) on purpose in the admin order list |
| `fmtPrice` in `src/features/restaurant/components/{CompactHeader,MoreInfoView,RestaurantInfoBlock}.tsx` | whole rupees for fees and minimums; a fractional fee rounds |
| `formatPrice` in `src/features/admin/components/ItemViewModal.tsx`, `src/shared/components/ItemDetailSheet.tsx` | whole or 2 decimals with no rounding step; INR only |

## Ninjasu_Web

Census 2026-11-17 triaged by the Lane 1 fix (branch `web-shared-helpers`). Shared helpers live in `src/shared/utils/` (and `src/shared/api/errors.ts` for error text); a helper used by one feature stays in that feature's `utils/`.

| Job | Owner | Contract | Removed copies |
|---|---|---|---|
| rupee amount (number) | `src/shared/utils/money.ts` `formatInr(amount, decimals = "auto")` | `0` whole rupees, `2` always two decimals, `"auto"` two decimals only with paise; Indian digit grouping; sign after the rupee mark ("₹-50"); a negative that rounds to zero prints "₹0" | `formatMoney` x12 (9 whole, 3 two-decimal), `formatInr` x6 (2 whole, 4 up-to-two) |
| rupee amount (paise) | `money.ts` `formatPaise(paise)` | `formatInr(paise / 100)` | none |
| empty-value text | `src/shared/utils/format.ts` `display(value)` | null, undefined, "" give "—"; 0 stays "0" | `display` x3 |
| localhost check | `src/shared/utils/host.ts` `isLocalhost(hostname)` | `localhost` or `*.localhost` | `isLocalhost` x2 (admin-auth routes) |
| list error text | `src/shared/api/errors.ts` `getListErrorMessage(error, noun)` | 403 names the permission; else the server or Error message; else a load-failed text with the noun | `getErrorMessage` x3 (shops, delivery zones, riders) |
| time of day | `src/features/shop/utils/auditTime.ts` `formatTime(ms, zone = IST)` | "3:45 pm"; `null` zone uses the viewer's own time zone | `formatTime` in `CounterSaleSalesList` (device zone, passes `null`) |
| calendar date (YYYY-MM-DD) | `src/features/shop/utils/reportFormat.ts` `formatDate(iso)` | "27 Nov 2026" in en-IN, no UTC shift; text that is not a date comes back unchanged | `formatPurchaseDate` x2, `FoodCostCard.formatDay` (now en-IN instead of the viewer's locale) |
| service date in an area's zone | `features/admin/services/service-area.utils.ts` `todayInZone(zone, nowMs)` | "YYYY-MM-DD" via `Intl` in that zone; a zone the browser does not know gives null (any other failure throws); the caller must stop, never write a null as a pause | none |
| service-area error text | `features/admin/services/service-area.errors.ts` `normaliseAreaError(error, fallback)` | The five backend error shapes (bean 400, domain 400, admin 409 code map, unreadable body, message-only) become `{fields, form, conflict}`; `errorText` / `slotRuleText` pick what each screen shows | none |
| default time zone for a service area | `service-area.utils.ts` `DEFAULT_ZONE` | "Asia/Kolkata": first in the zone select and the start value of a new area | none |

Intended output changes in the same PR: POS amounts now group thousands ("₹1,250", was "₹1250"); a negative round-off prints "₹0" instead of "₹-0"; purchases amounts with one decimal print two ("₹300.50", was "₹300.5"); `FoodCostCard` dates use en-IN.

### Intentional variants (Ninjasu_Web)

| Name and path | Why it stays different |
|---|---|
| `inr` in `features/shop/utils/reportFormat.ts` | Reports show exact amounts: always two decimals, sign before the rupee mark ("-₹5.00"). |
| `formatRupees` in `features/admin/services/commission.utils.ts` | Null becomes "—" and the output comes from `Intl` currency style (sign before the mark). Could move onto `formatInr` with a null wrapper in a later pass. |
| `formatRupees` in `shared/components/menu/itemPricing.ts` | Thin wrapper over `formatPaise(toPaise(rupees))`; rupees in, paise arithmetic inside. |
| `formatInrCompact` in `purchases/SpendBreakdown.tsx` | Compact "₹1.2L" / "₹5k" labels for the month bars. |
| `formatEventStamp` in `shop/DeliveryTimelineDialog.tsx` | ISO input, viewer's locale and time zone, shows day and month with the time. |
| `formatDayMonth` in `purchases/PriceHistoryPanel.tsx` | Day and month only, no year, in the viewer's locale. |
| `show` in `shop/utils/auditDescribe.ts` | Stringifies objects with JSON; `display` does not. |
| `toAreaTimeInput` in `admin/services/service-area.utils.ts` | Keeps non-zero seconds (a full-replace save must not drop them); `toTimeInput` in `shop-form.utils.ts` always cuts to `HH:mm`. |
| green on/off badge classes in the service-area list | Sixth copy of the same classes across the repo. A shared status badge replacing all six is its own PR (Judge 2026-11-18, F2). |

## Backend (ninja delivery service java)

Not surveyed.
