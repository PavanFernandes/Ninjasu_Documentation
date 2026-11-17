# Shared helpers registry

One owner per cross-cutting job, per repo. Read by `/gcp` step 8b (grep the job's row, do not read the whole file) and by the `/judge` reuse lens (the Intentional variants rows are settled decisions, not findings).

**Rules.** Before writing a helper for a job listed here, use or extend its owner (add a parameter or an option). A job with no owner: search the repo by mechanism once, then add the row in the same PR. A copy that must stay different gets a row under Intentional variants with the reason, and a name that says the difference. Last full census: 2026-11-17 (`node <great-sage-core>/good-coding-practice/scripts/census.mjs <repo> --source-only`).

## Food-Ninja-Frontend (app)

| Job | Owner | Contract | Known copies (merge targets) |
|---|---|---|---|
| money display | `src/utils/formatCurrency.ts` `formatCurrency(amount, currency='INR')` | null -> `''`; whole numbers no decimals, else 2; symbol map INR/USD/EUR | `formatMoney` in `features/cart/utils/format.ts`, `shared/utils/scheduleFormat.ts` (string input, null currency), `orders/components/OrderSummaryCard.tsx`, `admin/components/ShopOrdersScreen.tsx`; `fmtPrice` x3 (restaurant header/info); `formatPrice` x3 (`admin/ItemViewModal`, `restaurant/AddonSheet`, `shared/ItemDetailSheet`). Structure PR3 merges them |
| money arithmetic (paise) | `src/utils/money.ts` (`toPaise`, `paiseToRupees`, `parseRupeesToPaise`, `paiseToInputText`) | integer paise; parse returns null on bad text | none found |
| device time zone | none yet | `Intl.DateTimeFormat().resolvedOptions().timeZone` | `deviceTimeZone` in `features/orders/scheduleCancelCopy.ts`, `features/schedule/hooks/useScheduleRecovery.ts`. PR3 creates the owner |
| Schedule dates and clock times | `src/shared/utils/scheduleFormat.ts` (`formatServiceDate`, `formatSlotTime`, `formatClockTime(epochMs, timeZone)`) | renamed by what it does in PR3 | date formatting also in `orders/refundCopy.ts`, `pos/CheckBillScreen.tsx`, `pos/PosHistoryScreen.tsx` (not yet compared) |
| reason code -> customer text | none yet | | `features/schedule/scheduleReasons.ts`, `schedule/checkout/scheduleRefusalCopy.ts` (LINE_REASON), `schedule/scheduleCartState.ts`; Eat Now `cart/components/CartLineRow.tsx`. PR4 creates one table for Schedule |
| idempotency key | `src/utils/idempotency.ts` `newIdempotencyKey()` | UUID v4, `crypto.randomUUID` first | pure copy in `features/cart/utils/idempotency.ts` (unscheduled) |
| API error text | `ApiError.message` from `src/lib/fetchFn.ts` | safe to show; field errors in `fieldErrors` | none found |
| category icon | none | | `getCategoryIcon` pure copy in `pos/components/PosCategorySidebar.tsx`, `restaurant/components/CategorySidebar.tsx` (unscheduled) |

### Intentional variants (app)

| Name and paths | Why it stays different |
|---|---|
| (none recorded yet) | |

## Ninjasu_Web

Census 2026-11-17, not yet triaged (Lane 1): `formatMoney` x12 (2 bodies), `formatInr` x6 (2 bodies), `display` x3 (pure copy), `formatTime` x3 (3 bodies), `getErrorMessage` x3 (3 bodies), `formatPurchaseDate` x2 (pure copy), `isLocalhost` x2 (pure copy). Owners and intentional variants: to be filled by the Lane 1 fix.

## Backend (ninja delivery service java)

Not surveyed.
