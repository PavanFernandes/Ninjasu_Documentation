# Shared helpers registry

One owner per cross-cutting job, per repo. Read by `/gcp` step 8b (grep the job's row, do not read the whole file) and by the `/judge` reuse lens (the Intentional variants rows are settled decisions, not findings).

**Rules.** Before writing a helper for a job listed here, use or extend its owner (add a parameter or an option). A job with no owner: search the repo by mechanism once, then add the row in the same PR. A copy that must stay different gets a row under Intentional variants with the reason, and a name that says the difference. Last full census: 2026-11-17 (`node <great-sage-core>/good-coding-practice/scripts/census.mjs <repo> --source-only`).

## Food-Ninja-Frontend (app)

| Job | Owner | Contract | Known copies (merge targets) |
|---|---|---|---|
| money display | `src/utils/formatCurrency.ts` `formatCurrency(amount, currency='INR')` | null -> `''`; rounds to 2 decimals first, then a whole number shows no decimals, else 2; symbol map INR/USD/EUR, else the code and a space | `formatMoney` in `src/features/cart/utils/format.ts`, `src/shared/utils/scheduleFormat.ts` (string input, null currency), `src/features/orders/components/OrderSummaryCard.tsx`, `src/features/admin/components/ShopOrdersScreen.tsx`; `fmtPrice` in `src/features/restaurant/components/CompactHeader.tsx`, `MoreInfoView.tsx`, `RestaurantInfoBlock.tsx`; `formatPrice` in `src/features/admin/components/ItemViewModal.tsx`, `src/features/restaurant/components/AddonSheet.tsx`, `src/shared/components/ItemDetailSheet.tsx`. Structure PR3 merges them |
| money arithmetic (paise) | `src/utils/money.ts` (`toPaise`, `paiseToRupees`, `parseRupeesToPaise`, `paiseToInputText`) | integer paise; parse returns null on bad text | none found |
| device time zone | none yet | `Intl.DateTimeFormat().resolvedOptions().timeZone` | `deviceTimeZone` in `src/features/orders/scheduleCancelCopy.ts`, `src/features/schedule/hooks/useScheduleRecovery.ts`. PR3 creates the owner |
| Schedule dates and clock times | `src/shared/utils/scheduleFormat.ts` (`formatServiceDate`, `formatSlotTime`, `formatClockTime(epochMs, timeZone)`) | renamed by what it does in PR3 | date formatting also in `src/features/orders/refundCopy.ts`, `src/features/pos/components/CheckBillScreen.tsx`, `src/features/pos/components/PosHistoryScreen.tsx` (not yet compared) |
| reason code -> customer text | none yet | | `src/features/schedule/scheduleReasons.ts`, `src/features/schedule/checkout/scheduleRefusalCopy.ts` (LINE_REASON), `src/features/schedule/scheduleCartState.ts`; Eat Now `src/features/cart/components/CartLineRow.tsx`. PR4 creates one table for Schedule |
| idempotency key | `src/utils/idempotency.ts` `newIdempotencyKey()` | UUID v4, `crypto.randomUUID` first | pure copy in `src/features/cart/utils/idempotency.ts` (unscheduled) |
| API error text | `ApiError` from `src/lib/fetchFn.ts` | `message` is NOT always customer text: 401/403 throw the codes `SESSION_EXPIRED` / `ACCESS_DENIED` (also in `cart.service.ts`, `orders.service.ts`), a 4xx with no body gives `Request failed (<status>)`, a 5xx with no body gives `FRIENDLY_SERVER_MESSAGE`; otherwise it is the backend's `message`. Check the code and `kind` before showing it; field errors are in `fieldErrors`. No shared code-to-text mapping exists yet | none found |
| category icon | none | | `getCategoryIcon` pure copy in `src/features/pos/components/PosCategorySidebar.tsx`, `src/features/restaurant/components/CategorySidebar.tsx` (unscheduled) |

### Intentional variants (app)

| Name and paths | Why it stays different |
|---|---|
| (none recorded yet) | |

## Ninjasu_Web

Census 2026-11-17, not yet triaged (Lane 1): `formatMoney` x12 (2 bodies), `formatInr` x6 (2 bodies), `display` x3 (pure copy), `formatTime` x3 (3 bodies), `getErrorMessage` x3 (3 bodies), `formatPurchaseDate` x2 (pure copy), `isLocalhost` x2 (pure copy). Owners and intentional variants: to be filled by the Lane 1 fix.

## Backend (ninja delivery service java)

Not surveyed.
