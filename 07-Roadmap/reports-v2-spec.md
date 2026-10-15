---
id: ""
title: "Reports v2 — Reports hub, Daily Report (rows-first), Monthly Report (insight) — Implementation spec"
summary: "Follow-up to reports-plan.md after client feedback: one Reports sidebar entry opening a hub; Daily Report is a filterable rows table (bills, items) with insights secondary; Monthly Report is insight-only; annual removed. Exact JSON contract so backend and web build in parallel."
type: how-to
status: implementing
apps: [backend, web]
module: "reports"
anchors: []
verified_against: "backend main @ 88eb334, web main @ a529fa8 (2026-09-30)"
updated: 2026-09-30
---

# Reports v2 — implementation spec

Builds on [reports-plan.md](reports-plan.md) (v1 is merged to main). Client feedback: **the Daily Report is about ROWS the owner can filter; insight is secondary. The Monthly Report is insight. Annual is removed (built separately later).**

Unchanged rules: basis = PAID `DINE_IN` bills by `business_date`; every bill query embeds `ReportQueryRepository.SALE_BILL`; one bill child table per query; permission `reports.sales.view` checked before any query; dine-in only ("Dine-in" chip, no takeaway/delivery); user text in XLSX only via `setCellValue(String)`; India/IST.

## A. Web information architecture

- Sidebar: the Reports group becomes ONE item **Reports** → `/shop/reports` (hub). Shown when the caller holds ANY report permission (sales, history, audit). No other report items in the sidebar.
- Hub page `/shop/reports`: a card grid, one card per report the caller may open (title + one-line description + icon). Driven by a single catalog array (`reportCatalog.ts`: id, title, description, href, icon, permission check) so a future report is one entry. Cards now: **Daily Report** (`/shop/reports/daily`), **Monthly Report** (`/shop/reports/monthly`) — both `reports.sales.view`; **Dine-In History** (`/shop/reports/history`, history view); **Activity** (`/shop/reports/activity`, audit view). Existing History/Activity pages are NOT changed. If the caller holds no report permission, show the same "no access" card the other pages use.
- Every report page has a small "← Reports" back link above its heading.
- The old `/shop/reports/sales` route is removed; make it redirect to `/shop/reports/daily`.
- UI clean-up (both new pages): no shop-name subtitle under the heading; no repeated title/outlet/basis block on screen (that block stays in the XLSX/PDF only); a small "Dine-in only" chip instead of the basis paragraph; no Refresh button; one toolbar row (date control left, Excel/PDF right); tables sit directly on the page, not each wrapped in a Card; consistent spacing; max content width (~`max-w-6xl`) so wide screens don't stretch rows; phone-width works with no horizontal page scroll.

## B. Daily Report (`/shop/reports/daily`) — rows first

Toolbar: date picker with previous/next arrows (default = current business day; no future days; use the shop's `businessDayStartHour` via existing `businessToday`), a "Custom range" toggle revealing from/to (max 62 days here), Excel + PDF buttons.

Filter row (compact chips/selects): tax class (multi; includes Alcohol), category (multi, incl. Uncategorised), payment type (single select), bill-number search box (debounced 300 ms, digits). Filters apply to the Bills tab and totals strip; **payment type applies to Bills only** (payments are bill-level) — the Items tab shows a one-line note when a payment filter is set.

Totals strip (one compact line under the filters): Sales (before GST) · GST · Collected · Bills — from the server `totals` for the WHOLE filtered set (not just the page). When a tax-class/category filter is active GST/Collected are `null` ⇒ show "—" and the Bills table hides those two columns (bill-level tax cannot be split by line filters; show the existing "GST is not shown…" note).

Tabs: **Bills** (default) · **Items** · **Insights**.
- Bills: table, one row per bill: Bill no., Time (paidAt, IST), Table, Payment, Sales, GST, Total. Sortable by time/total (server `sort=paidAt|total`, `dir=asc|desc`, default paidAt desc), paginated (page size 50) with prev/next. Clicking a row opens the existing receipt dialog for that bill's check (`ReceiptDialog`/`getBill` for `checkId`) — if that proves non-trivial, fall back to no row action and note it.
- Items: existing sales-breakdown data (per item: name, category, qty, sales, %), with the by-category table above it. Same filters (tax class, category).
- Insights: the current Day Summary content moved here (equation, payments, tax-class split, GST rows, write-offs, recovered note, per-day/per-month series when the range is >1 day). Open-tables warning banner stays at the TOP of the page (all tabs) when `openTables > 0`.

Exports (`format=xlsx|pdf`): Daily export contains the Bills rows (with the active filters, echoed in the header), the Items rows, and the existing summary sheets/sections. Bills rows in XLSX = a `Bills` sheet with numeric cells + autofilter + frozen header + SUM totals; in PDF a Bills table section (cap 300 rows with a "see Excel" note).

## C. Monthly Report (`/shop/reports/monthly`) — insight

Month picker (previous/next arrows + label like "September 2026", no future months), Excel + PDF. No filters in v1.
Sections (no per-row bill list): headline stats (Sales, Collected, Bills, Avg bill) each with change vs comparison period; daily sales chart (Recharts, brand token color, tooltip with ₹) with best and worst day called out; weekday pattern (bar per weekday: average sales/day); top 10 and bottom 10 items (by sales); category share; payment mix; Food vs Alcohol split; small write-offs line. Comparison period = SAME day-count of the previous month when the selected month is the current, incomplete month; the FULL previous month otherwise. Label it ("vs 1–29 Aug").

## D. Backend contract

All under `/api/shops/{shopId}/reports`, all require `reports.sales.view`, all return the usual `ApiResponse<T>` envelope (exports return raw files exactly like the existing export endpoints). Money = number (2 dp); percents 1 dp; dates ISO `YYYY-MM-DD`; timestamps epoch ms.

### D1. `GET /daily-bills`
Params: `from`,`to` (required, ≤ 62 days), `taxClass`* , `categoryId`* (repeatable; literal `uncategorised` allowed, same parsing/validation as sales-breakdown), `paymentTypeId` (single UUID, optional), `q` (optional digits = bill number), `page` (0-based, default 0), `size` (default 50, max 100), `sort` (`paidAt`|`total`, default `paidAt`), `dir` (`asc`|`desc`, default `desc`).
```json
{ "header": {…existing Header…},
  "filterSummary": "All bills (no filter)" ,
  "lineFiltersActive": false,
  "totals": { "bills": 143, "salesBeforeGst": 184250.50, "gstAdded": 6412.25, "amountCollected": 190662.00 },   // gstAdded/amountCollected = null when lineFiltersActive
  "page": 0, "size": 50, "totalBills": 143,
  "rows": [ { "billId": "…", "checkId": "…", "billNo": "D-12", "businessDate": "2026-09-26", "paidAt": 1790000000000,
              "tableLabel": "T5", "payment": "UPI + Cash", "salesBeforeGst": 1288.50, "gstAdded": 64.43, "amountCollected": 1353.00 } ] }   // gstAdded/amountCollected = null when lineFiltersActive
```
Semantics: bills = PAID + DINE_IN + business-date range (SALE_BILL). Line filters (taxClass/categoryId) keep only bills that have at least one matching line (EXISTS over `BillLine`, no join multiplication) and, when active, `salesBeforeGst` per row and in `totals` = sum of MATCHING line totals, GST/collected null. Payment filter keeps bills having a `BillPayment` with that `paymentTypeId` (EXISTS). `q` matches `billNumber`. `billNo` = `series + "-" + billNumber`. `tableLabel` from `TableCheck` for the bill's `checkId` via a repository read by ids (no JPA association; no cross-domain service call). `payment` = payment names of the bill joined " + " (by `BillPayment.method`, ordered by amount desc). Page size/total are computed on the filtered bill set; sorting has a stable tiebreaker (`id`). Every JPQL string is built per request (append predicates only when present), embeds SALE_BILL, and joins at most one child table (use EXISTS/subqueries and separate id-scoped queries for the page's line sums, payments, table labels). Must be added to `ReportJpqlOfflineValidationTest` for every filter combination.

### D2-amendment (2026-09-30, after code review — supersedes the export text below)
`/day-summary/export` is UNCHANGED from v1 (full unfiltered summary, no filter params, no Bills rows). The Bills rows export is its own endpoint: `GET /daily-bills/export` with the same params as `/daily-bills` minus `page`/`size` plus `format=xlsx|pdf` (≤ 62 days; all matching bills in one query, capped at 5000; Excel lists them all, PDF the first 300, both say when the list is shorter than the totals; GST/Total columns omitted under a tax-class/category filter). Web: Daily → Bills tab downloads `daily-bills/export` with the active filters; Daily → Insights tab downloads `day-summary/export`; Items tab downloads `sales-breakdown/export`. `filter-options.paymentTypes` lists ALL the shop's payment types (inactive ones are labelled "(inactive)" since old bills still carry them). `sort=total` under a tax-class/category filter falls back to time order. Weekday `avgSales`/`days` count trading days (days with bills) only. `page` ≤ 100000. Bill-number search `q` is an exact match, 1–9 digits.

### D2. Existing endpoints
`GET /day-summary`, `/sales-breakdown`, `/filter-options` (+ `/export` variants) stay. Add `filter-options.paymentTypes: [{id,label}]` (the shop's ACTIVE payment types; read via the existing payment-type repository, ordered by name) for the payment filter. `/day-summary/export` gains optional `taxClass`,`categoryId`,`paymentTypeId`,`q` params and its workbook/PDF include the Bills rows (capped at 5000 rows in XLSX, 300 in PDF) built from the same D1 query logic (share the code — one definition).

### D3. `GET /monthly?month=YYYY-MM`
```json
{ "header": {…}, "month": "2026-09", "range": {"from":"2026-09-01","to":"2026-09-29"},
  "comparison": { "from":"2026-08-01","to":"2026-08-29","label":"1–29 Aug","isSameDays":true },
  "sales": {…existing Sales…}, "previous": {…existing Sales…},
  "delta": { "salesBeforeGstPct": 8.2, "amountCollectedPct": 7.9, "billsPct": 5.0, "averageBillPct": 3.1 },   // null when previous is 0
  "series": [ {"date":"2026-09-01","bills":71,"salesBeforeGst":90210.00} ],       // every day in range, zero-filled
  "bestDay": {"date":"…","salesBeforeGst":…}, "worstDay": {…},                     // over days with ≥1 bill; null if none
  "weekday": [ {"dow":1,"label":"Mon","days":4,"totalSales":…,"avgSales":…} ],    // Mon..Sun, all seven
  "topItems": [ {"name":"…","category":"…","quantity":…,"sales":…,"percent":…} ], // 10, by sales desc
  "bottomItems": [ … ],                                                           // 10, by sales asc, only items sold at least once
  "byCategory": [ {"name":"…","quantity":…,"sales":…,"percent":…} ],
  "payments": [ {"name":"…","amount":…,"count":…,"percent":…} ],
  "byTaxClass": [ {"code":"…","label":"…","quantity":…,"sales":…,"percent":…} ],
  "writeOffs": {"bills":…,"amount":…,"recoveredBills":…,"recoveredAmount":…} }
```
`month` must be a valid past-or-current month; reject future with a business-rule error. Compute by reusing the existing repository queries/assembler pieces (bills-by-date, payments, lines by tax class, lines by category/item, write-offs) — do NOT add a second definition of a sale. Comparison "same days" when `month` is the current business month and today's business day is before month end: previous month days 1..(today's day-of-month, capped to that month's length); otherwise the full previous month.
`GET /monthly/export?month=&format=xlsx|pdf`: XLSX sheets Summary (both periods + delta), By day, Weekday, Top items, Bottom items, Category, Payments; PDF = one insight page (stats table, by-day table, top/bottom item tables, payments, category). Same shared renderers/fonts/rate-limit semaphore rules as the existing exports (validate `format` before any query).

## E. Tests required
Backend: assembler unit tests for monthly (delta, zero-fill, best/worst, weekday, comparison-period selection incl. current partial month and 31→30-day months), daily-bills paging/sort/filter logic where pure, JPQL offline parse of every new query variant + the SALE_BILL/one-child-table/DINE_IN rules (extend `ReportJpqlOfflineValidationTest`), controller route-set test updated with the new routes (extend `ReportControllerTest`), request validation (range ≤ 62, month not future, size cap), renderer tests for the new sheets/sections (malicious names stay text). Web: `tsc --noEmit` and `eslint` clean on changed files (run via node, NOT pnpm); a mocked-API Playwright capture (see how v1 was captured: mock `**/api/proxy/**` at the Playwright layer; dev server with `API_BASE_URL` pointing at a dead port, unique port) covering hub, daily (bills/items/insights, filter, custom range, phone width), monthly, dark mode, zero console errors.

## F. Hard constraints
Never boot the backend or run any Spring-context test against the shared Neon DB (run `./mvnw -o test -Dtest='!NinjaDeliveryServiceApplicationTests'`). Never run pnpm/npm in the junctioned worktree (run tsc/eslint through `node ./node_modules/...`). Do not commit, push, or open PRs. Do not touch files outside the assigned repo. Do not modify the existing History/Activity pages.
