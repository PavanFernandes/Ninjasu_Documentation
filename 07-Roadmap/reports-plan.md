---
id: ""
title: "Reports (Day Summary + Sales Breakdown, XLSX + PDF) — Research & Plan"
summary: "Client wants a daily report their MD can be sent, filterable (category / alcohol), in XLSX + PDF. Minimal v1 built on bills only (dine-in), two report types, one range endpoint that also serves monthly/annual; category snapshotted onto lines first. Records the data facts, the DA/Codex-hardened decisions, and how to improve it once real data exists."
type: how-to
status: built-v1-undeployed
apps: [backend, web]
module: "reports"
anchors: []
verified_against: "backend main @ e88e6a8 (cashier-role merged) 2026-09-27"
updated: 2026-09-27
---

# Reports — Research & Plan

## Problem (client requirement, 2026-09-27)

1. A **daily report** the owner can send to their MD.
2. **Filtered reports** — only a category, only beer/alcohol.
3. **Excel and PDF** export.
4. Samivan: monthly + annual too — but **build very basic now**; once real data exists we mine the database and improve.
   The product is **not live**, so schema changes that make the data correct (category on the bill line) are approved *if correct*.

## Positioning check

[pricing-and-positioning.md](pricing-and-positioning.md) rejects "80+ report suites" ("build insight, not volume") and says
back-office work waits until a customer blocks on it — this client is that trigger. So: **two report types, one range
endpoint**; "beer report" is a filter over the same report, not a new report.

## Facts the design rests on (verified in code)

| Fact | Where | Consequence |
|---|---|---|
| Every dine-in settlement writes **exactly one Bill**, atomically with the payment (`generateAndSettle` / `generateAndWriteOff`). Bill carries `business_date` (shop start hour, default 5), lines, `bill_tax_lines`, `bill_payments`, frozen totals. | `BillServiceImpl`, `TableCheckServiceImpl.recordPayment` | **Bills alone are a complete, frozen, business-day-aware source for dine-in.** No dependence on `SalesReadModelService`'s calendar-day window. |
| Bill money: `subtotal` = Σ `line_total_snapshot` = `taxable_total`; `grand_total = subtotal + tax_total + rounding` (fees are 0 for dine-in). `TableCheck.billedTotal` = Σ KOT grand totals = the same number. | `BillTotalsCalculator`, `TableCheckServiceImpl` | Report Sales = Σ `bills.subtotal` (PAID) is the **same number** as the dine-in half of `SalesReadModelService` **for the same set of settlements** — but the windows differ (report = `business_date`; read-model = calendar-day IST), so a venue open past midnight will legitimately differ day-by-day. Two named sources, one meaning: reports read bills; food-cost % reads the read-model. Cross-reference comments on both + one manual reconciliation on a scratch DB (DA-2). |
| GST engine adds tax only for REGULAR shops, only on TAX_EXCLUSIVE lines; `ALCOHOL` = OUT_OF_SCOPE (no tax line), `PACKAGED_MRP` = TAX_INCLUSIVE (tax embedded, no tax line). | `GstTaxEngine`, `CountryMigrationRunner` | "Net sales" is *before added tax*, not strictly ex-tax (inclusive items embed tax). Label it **"Sales (before GST added)"**; embedded GST is not separated in v1. |
| `line_discount` on a bill line = MRP − selling price (already baked into the price). **There is no manual bill discount.** | `BillServiceImpl.toBillLine` | "Discount" in the report = **menu discount (vs MRP)**, one info line. No discount-leakage section. |
| `bill_lines` has **no item id / category**; item↔category is many-to-many (`menu_item_categories`), items require ≥1 category in the UI. | `BillLine`, `MenuItemCategory`, `ItemFormDialog` | Snapshot **item id + one primary category (id + name)** onto `order_lines` (both creation sites) and copy to `bill_lines`. Primary = lowest `sort_order`, then name, then id. Every line counts under exactly one category ⇒ category totals **always** sum to net sales. |
| `tax_class_code` is already snapshotted on order + bill lines. | `OrderLine`, `BillLine` | **Alcohol filter = `tax_class_code = 'ALCOHOL'`** (legally meaningful: outside GST, state excise/VAT). "Beer" = the shop's own category. |
| Payments are **bill-level**; tax rows are per **(tax class, rate)** per bill (`bill_tax_lines.tax_class_code`); neither has a category. | `bill_payments`, `bill_tax_lines`, `GstTaxEngine` | ⇒ **Two report types** (below). A filtered report never shows payments. **GST added is shown only when the filter is tax-class-only (exact via `bill_tax_lines.tax_class_code`); any category filter suppresses it** (Codex #5 — my earlier "tax can never be shown" was too strong). |
| Bills: `WRITTEN_OFF` bill later settled → new PAID bill and old one gets `superseded_by_bill_id`. `VOIDED` is never set anywhere. | `BillServiceImpl.settleWrittenOffBill` | Sales = status `PAID`. Write-offs = status `WRITTEN_OFF` **and** `superseded_by_bill_id IS NULL`. |
| Delivery/takeaway have **no bill**; `Order` has only `subtotal`/`deliveryFee`/`grandTotal` (per code map: no bill/payment recorded for takeaway). | `Order`, code map | **Out of v1.** Reports are labelled "Dine-in". Delivery/takeaway is a v2 decision once real volume is known. |
| Permissions are **per-shop DB rows** (`shop_role_permissions`); owners get `EnumSet.allOf`; `PermissionTemplates.DEFAULT` only seeds *new* shops; `LEGACY` is used only to derive the old-app `myRole` string. `RbacSchemaGuard` verifies, never backfills. History exposes per-check totals but **not** item/category mix, tax-class mix, write-off reasons or annual roll-ups. | `PermissionServiceImpl`, `PermissionTemplates`, `ShopServiceImpl.seedDefaultRoles`, `RbacSchemaGuard` | **New permission `reports.sales.view`** (Codex #4 accepted — reusing history would give legacy Staff/Chef commercial intelligence, and roles doc says "reports must be hideable"). Add to `DEFAULT` for Manager + Accountant (Admin gets it via `allOf`); **do not touch `LEGACY`** (would break `legacyMyRole` for old app builds); an idempotent runner grants it to existing shops' ADMIN/MANAGER/ACCOUNTANT roles. |
| Existing indexes (created by `DineInBillMigrationRunner`, not by entity annotations): `idx_bills_shop_business_date (shop_id, business_date)`, `idx_bills_shop_status_created`, `idx_bill_lines_bill_id`, `idx_bill_payments_bill_id`, `idx_bill_refunds_bill_id`. **`bill_tax_lines.bill_id` has none.** | `DineInBillMigrationRunner` L64-79 | Add `idx_bill_tax_lines_bill_id` to that runner (project pattern; non-fatal try/catch). No `@Index` annotations. (Earlier draft wrongly claimed lines/payments were unindexed — corrected.) |
| Schema management: `spring.jpa.hibernate.ddl-auto=update`; nullable new columns are auto-added. Local backend defaults to **Neon (shared)** — booting it runs DDL there. | `application.properties`, memory | New columns are **nullable, no backfill**; rows before the change show "Uncategorised". **Do not boot the backend locally against Neon** without a scratch branch. |
| No xlsx/pdf library in backend or web; `recharts` exists in web; SES client exists. Prod = one shared 20 GB EC2. | poms/package.json | Add Apache POI + OpenPDF (backend). No headless Chrome. |

## v1 scope (deliberately basic)

**Source:** `bills` only (dine-in). **Range:** `from`/`to` business dates, inclusive — one endpoint serves a day, a month
(preset) and the financial year (preset, Apr–Mar). Series = per day when the range ≤ 62 days, else per month.
**Auth:** new `reports.sales.view`. **Formats:** on-screen preview, XLSX, PDF (download; no email yet).

### Report 1 — Day Summary (unfiltered, bill-level) — *the one the MD receives*
- Header: outlet, business date range ("business dates as assigned when each bill was issued" — **no precise cutoff window**, the cutoff isn't snapshotted and the shop can change it), "all times IST", generated-at. **Every page/sheet titled "Dine-in"; footer: "Dine-in bills only — takeaway and delivery orders are not included."** v1 is India/IST only (no shop timezone exists).
- Banner: "N tables still open" (count of OPEN checks) **only when the range includes the current business day** (`BusinessDayResolver.resolve(now, shop.businessDayStartHour)`, never `LocalDate.now`).
- Printed equation: **Sales (before GST added) + GST added + Round-off = Amount collected**; GST by name+rate from `bill_tax_lines`; note that tax-inclusive (MRP) items carry their GST inside Sales. Plus Bills · Average bill. Basis = **settlement date**; "of which recovered from earlier write-offs: N bills ₹X". (Menu-discount line dropped — nobody asked for it.)
- Collections by payment type (group by `payment_type_id`, fall back to `method` for legacy null ids). Σ = Total collected (asserted in the assembler; a mismatch is shown, not hidden).
- Sales by tax class (Food / Alcohol / Packaged).
- Written-off bills: count + amount by reason, **including ones later settled**, with "of which recovered later" shown separately — a past day's figures must not change retroactively.
- Series table (per day / per month) when range > 1 day. SQL always groups by `business_date`; months are folded in Java.

### Report 2 — Sales Breakdown (filterable, line-level)
- Filters: date range · tax class (multi) · category (multi, incl. "Uncategorised").
- Table by category (qty, sales, % of total) and by item (qty, sales), within the filter. Filter echoed in the header.
- **Unfiltered total must equal Day Summary "Sales"** (asserted by a test).
- Presets: "Bar" = tax class ALCOHOL; any category = the shop's own category.

### Not in v1 (deferred on purpose — revisit with real data)
Delivery/takeaway · payment-type filter · hourly · covers/per-cover · week-over-week · voided-KOT leakage and staff-wise (need the audit log) · scheduled email to the MD · saved presets · frozen day snapshots/rollups · liquor **stock** register · GSTR-1-shaped export (route via `ca-cs-pm`) · `original_business_date` for recovered write-offs · shop timezone / snapshotted cutoff.

## Build design

- **Schema (P0, all nullable, no backfill):** `order_lines.category_id/category_name`; `bill_lines.menu_item_id/category_id/category_name`; `idx_bill_tax_lines_bill_id` via `DineInBillMigrationRunner`. **NULL means "line created before the snapshot existed"** (also shown as "Uncategorised"); it is not a valid state for new lines because items require ≥1 category. One snapshot helper (`ItemCategorySnapshot`) used by both `PosOrderServiceImpl` and `OrderAssembler`; unit-tested (multi-category order, soft-deleted category, null sort_order, no category).
- **Backend:** `ReportController` → `ReportService` → JPQL **GROUP BY** queries in `BillRepository` (+ one OPEN-check count on `TableCheckRepository`; repository-level reads only, no cross-domain service calls). A pure assembler builds `ReportResult` (percentages, totals, reconciliation checks); XLSX (POI) and PDF (OpenPDF, embedded ₹-capable OFL font) renderers consume the **same** object as the JSON preview, so screen/Excel/PDF cannot disagree.
- **Endpoints:** `GET /api/shops/{shopId}/reports/day-summary` and `/sales-breakdown` with `?from&to[&taxClass=..&categoryId=..]` and `&format=json|xlsx|pdf`.
- **Web (Ninjasu_Web):** one "Reports" page in the shop area: range picker + presets (Today, Yesterday, This month, Last month, This FY), report tabs, filters on the breakdown tab, preview tables, Download Excel / PDF. New files only + one sidebar entry (other session has uncommitted menu/AppShell changes — do not touch those files).
- **Gotchas to design around:** optional filters are handled by **building the JPQL string per request** (append `AND … IN :param` only when that filter is present; no `:list IS NULL` / sentinel tricks) in an `EntityManager`-based repository; the offline test builds every combination and parses it. **Every query joins `bills` to exactly one child table** (lines *or* tax lines *or* payments — never two, or split-tender × multi-line × two GST rows multiplies sales 16×). XLSX cells numeric with number formats + SUM formulas; user text only ever via `setCellValue(String)`; PDF font must contain U+20B9; response filenames sanitised; every query scoped by `shop_id` from the path **and** `requirePermission(shopId, caller, REPORTS_SALES_VIEW)` before any query. **Abuse caps:** range ≤ 366 days, ≤ 10 tax classes (must be known codes), ≤ 50 category ids (deduped), ≤ 2 concurrent exports (else 429-style conflict), PDF item table capped at top 300 rows (XLSX has all).

## Verification plan (what can and cannot be proven locally)

- Compile + unit tests: assembler (totals/percent/reconciliation), primary-category picker, both renderers (render fake data → open the PDF/XLSX and inspect).
- **JPQL syntax/mapping is validated offline** by extending the existing `RbacJpqlOfflineValidationTest` pattern (bare Hibernate, no Spring, no DB, connection provider refuses everything) to the new report repository queries. That proves the queries *parse* against the entity mappings — **not** that they return the right numbers.
- Query *results* (group-by correctness, the SalesReadModel reconciliation, Postgres param typing) still need a **scratch Neon branch** (user action) or first deploy to a non-prod DB. Never boot the backend against the shared Neon DB. State this plainly in any "done" report.
- Web: `tsc` + `eslint` (not tsc alone) + Playwright with mocked API (local dev is not isolated — never point the UI at prod data for capture).

## Devil's-advocate conditions (2026-09-27) — all `proceed with conditions`, 0 `stop`

| # | Failure scenario | Condition folded in |
|---|---|---|
| DA-1 | **Primary category makes a "Beer" filter wrong.** A beer in both "Bar Specials" (sort 1) and "Beer" (sort 5) is counted under Bar Specials → the Beer report understates and the MD trusts it. | Category filter/table is labelled **"primary category"** everywhere. The exact bar/alcohol cut is the **ALCOHOL tax class** filter (recommended, unambiguous). Frequency of multi-category items is checklist item 1. Not solved with a category array in v1 (over-build without data). |
| DA-2 | **Two definitions of a dine-in sale** (bills vs `table_checks`, different windows). | Named sources + cross-reference comments on `SalesReadModelService` and the report service ("same meaning, different window; keep in sync"). One manual reconciliation on a scratch DB comparing Σ `bills.subtotal` (PAID, business_date = D) with Σ `table_checks.billed_total` (CLOSED, payment_mode NOT NULL) over the **cutoff-aligned interval** `[D+startHour, D+1+startHour)` IST on `paid_at` — never the same calendar `from/to`. |
| DA-3 | **Implicit-filter trap** (check #8): `bills` can hold GENERATED/PARTIALLY_PAID/VOIDED rows — and, once Counter Sale ships (`counter-sale-PLAN.md`), bills whose source is `WALK_IN_TAKEAWAY` (added 2026-09-27 after a parallel session flagged it: the sale predicate had no source filter while every title said "Dine-in") (nothing writes them today — verified: `BillStatus` is only set PAID/WRITTEN_OFF in `BillServiceImpl`), and a future "bill before pay" feature would add GENERATED rows that silently inflate any query that forgot `status = PAID`. | One shared predicate (`SALE_BILL`: shop + PAID + **DINE_IN source** + business-date range) for "sale" and a matching one for "write-off"; comment naming the trap; the offline JPQL test asserts every report query contains the status predicate. |
| DA-4 | **Retroactive drift:** MD received "1 write-off ₹2,000"; at noon it is settled; regenerating yesterday shows 0. | Write-offs are counted regardless of `superseded_by_bill_id`; "recovered later" shown separately. |
| DA-5 | **Renamed category splits into two rows** if grouped by (id, name). | SQL groups by `category_id` (and `menu_item_id`); the assembler merges names, newest wins. |
| DA-6 | **"Open tables" banner uses the wrong day** for a bar open past midnight. | Banner keyed to `BusinessDayResolver`, not the calendar. |
| DA-7 | **Silent omission:** takeaway/delivery revenue absent from an MD's "daily sales". Verified: `BillSource` has 4 values but only `DINE_IN` is ever written, and `billService.generate*` is called only from `TableCheckServiceImpl`. | "Dine-in" in every title + static footer; memo line with order counts deferred until data (checklist 5). |
| DA-8 | **PDF font boxes:** Latin+₹ font renders Devanagari/Kannada item names as missing glyphs. | Accepted in v1; script frequency of item names is a checklist item. |
| DA-9 | **XLSX injection** from shop-controlled names (`=HYPERLINK…`). | Strings written only via `setCellValue(String)` (stored as text, never evaluated); no formula is built from user text. Numbers rounded to 2 dp from `BigDecimal`. |
| DA-10 | **Scope inflation** (LEARNINGS #45): menu-discount line, saved presets, email were never asked for. | Menu-discount dropped; presets/email deferred. |
| DA-11 | **Multi-session collision in Ninjasu_Web** (menu + AppShell changes uncommitted by another session). | New files only + one additive sidebar edit in `(shop)/layout.tsx` after re-checking `git status`; never touch `AppShell.tsx` or menu components. |
| DA-12 | Migration pain (check #6): nullable columns → metadata-only in Postgres, no backfill, no visibility-default inversion (the new columns don't gate anything). | Proceed. |

## Codex review (2026-09-27) — 15 findings, verified against code before accepting

| # | Sev | Finding | Verdict → action |
|---|---|---|---|
| 1 | HIGH | Day Summary vs `SalesReadModel` not day-for-day reconcilable (02:00 settlement lands on yesterday's report, today's read-model). | **Accepted.** Reconcile by a cutoff-aligned epoch interval `[date+startHour, date+1+startHour)` on `table_checks.paid_at` (or by check/bill ids) — never identical `from/to` dates. Fixed in DA-2 wording. |
| 2 | HIGH | Recovered write-off (Fri walkout paid Mon): Monday's PAID bill carries Friday's lines, so Monday's sales/product mix include Friday's items; `paidAt` overwritten. | **Adjusted.** Basis is **settlement-date (cash) basis**, labelled. Day Summary adds "of which recovered from earlier write-offs: N bills ₹X" (detect via `EXISTS bill w WHERE w.supersededByBillId = b.id`). No `original_business_date` column in v1 — rare event, revisit with data. |
| 3 | HIGH | `copyMoneySnapshot` overwrites tax class/rate on new bill lines **by list index** from two unordered collections → Food/Alcohol classes can swap on a recovered bill (corrupts Alcohol filter). Pre-existing bug. | **Accepted, fix in code.** Add `bill_lines.order_line_id`; correlate old↔new lines by it; positional fallback only when ids are null (pre-change rows). Unit-tested via an extracted helper. |
| 4 | HIGH | Reusing `REPORTS_HISTORY_VIEW` widens access. | **Accepted** — new `reports.sales.view` (see facts table). |
| 5 | HIGH | "Tax can't be shown when filtered" is false for tax-class-only filters. | **Accepted** — see facts table. |
| 6 | MED | "Business-day window" header can lie after a cutoff change. | **Accepted** — header says business dates, no window. |
| 7 | MED | Timezone is platform-global (`Asia/Kolkata`). | **Accepted** — v1 India/IST, stated in exports. |
| 8 | MED | Primary-category rule under-specified (null `sort_order`, soft-deleted, parent/child, cross-shop). | **Accepted** — spec: exclude `is_deleted`, require `category.shop_id = item.shop_id`, `sort_order ASC NULLS LAST, name, id`, **leaf (directly linked) category not its parent**, zero eligible ⇒ NULL. |
| 9 | MED | Plan contradicted itself on `@Index`. | **Accepted** — stale sentence removed; runner only. |
| 10 | MED | `DineInBillMigrationRunner` is one big try — an earlier DDL failure skips the new index. | **Accepted** — new separate `ReportsMigrationRunner` (own guarded blocks: index; permission grant). Existing runner untouched. |
| 11 | MED | Join multiplication across lines × tax rows × payments. | **Accepted** — one-child-table-per-query rule; aggregate assembler test uses multi-line / multi-tax / split-tender fixtures. |
| 12 | MED | Optional multi-value filters fragile on Hibernate 6/Postgres. | **Accepted, changed approach** — dynamic JPQL strings, no sentinels; uncategorised is its own predicate. |
| 13 | MED | 366-day cap doesn't bound filters/exports. | **Accepted** — caps listed under gotchas. |
| 14 | LOW | XLSX formula injection. | **Accepted** (= DA-9) + malicious-name renderer test. |
| 15 | LOW | "Sales" vs "Total collected" read as competing revenue. | **Accepted** — print the equation `Sales before GST added + GST added + round-off = Amount collected`; note embedded GST in TAX_INCLUSIVE lines. |

Codex also independently confirmed: payments sum to `grandTotal` for PAID bills; `subtotal` and `billedTotal` derive from the same active KOT lines; cancelled KOTs are excluded pre-bill; only two `OrderLine` constructors and one `BillLine` constructor exist (no missed line-copy path); tenant scoping by `b.shopId` prevents cross-tenant filter leaks.

## Improve-with-real-data checklist (run once the first client has ~2 weeks of bills)

1. % of lines with null category; how many items sit in >1 category (does "primary category" mislead?).
2. Bills created between 00:00 and the start hour (is the business-day cutoff right for this venue?).
3. Share of TAX_INCLUSIVE lines (does "before GST added" need a real ex-tax split?).
4. Write-off frequency and reasons (does the MD care?).
5. Delivery/takeaway share of revenue (is dine-in-only acceptable, or add orders?).
6. Payment-type cardinality; unmapped legacy `method`s.
7. Query latency for a 31-day and a 366-day range → decide if a daily rollup is needed.
8. Which sections the MD actually forwards/asks about → cut the rest.

## Built 2026-09-27 (v1, uncommitted, undeployed)

**Backend** (`ninja delivery service java`, on `main`, uncommitted): `ItemCategorySnapshot` + `order_lines`/`bill_lines`
category/item/order-line columns; `BillServiceImpl` links bill lines to order lines and matches by id when copying a
write-off's tax snapshot; `Permission.REPORTS_SALES_VIEW` (+ `DEFAULT` templates, legacy SQL seed line);
`ReportsMigrationRunner` (bill_tax_lines index + grant to existing ADMIN/MANAGER/ACCOUNTANT roles);
`ReportQueryRepository` / `ReportAssembler` / `ReportServiceImpl` / `ReportController`;
`ReportXlsxRenderer` (POI 5.5.1) / `ReportPdfRenderer` (OpenPDF 3.0.5 + bundled Noto Sans).
Endpoints (`/api/shops/{shopId}/reports/…`, all need `reports.sales.view`): `day-summary`, `sales-breakdown`,
`filter-options` (JSON) and `day-summary/export`, `sales-breakdown/export` (`format=xlsx|pdf`).
**Web** (`Ninjasu_Web`, worktree `../ninjasu-web-reports-worktree`, branch `feature/reports-page` from `origin/main` — local
`main` was 21 commits behind and lacked the RBAC permission gating): `/shop/reports/sales` under the Reports nav group.

**Verified:** backend compile + 192 tests green (all but the DB-booting context test): assembler math with split-tender /
multi-tax fixtures, category picking, id-based line matching, offline JPQL parse of every filter combination + the
"one child table per query" and "sale predicate present" rules, XLSX cells (numeric, live SUMs, malicious names stay
text), PDFs rendered and inspected visually. Web: `tsc` clean, `eslint` 0 errors (17 pre-existing warnings, none in new
files), and a Playwright run with every API call mocked: nav entry, presets, both tabs, filters, Excel download name,
phone width (no overflow), light + dark, no console errors.

**NOT verified — needs a scratch database:** the JPQL was proven to *parse*, never *executed*. Group-by numbers, the
`EXISTS` recovered-sale subquery, Postgres parameter typing, the `ReportsMigrationRunner` SQL and the
`ddl-auto=update` column adds have not run against Postgres. Also unverified against real data: business-date
assignment, multi-category items, write-off recovery flow. **Do not boot the backend against the shared Neon DB to check.**

**Known gaps (accepted for v1):** dine-in only — every bill query filters `source = DINE_IN`, so Counter Sale bills (when built) stay OUT until reports gain a "Counter sale" channel (v2, must also revisit the "Dine-in" titles); no delivery; PDF font has no Devanagari/Kannada glyphs;
`roles-permissions.md` (02-Domain, Context-Keeper-owned) does not yet list `reports.sales.view`; the role-editor label
for it is auto-derived ("Sales view" under Reports).

**Deploy order:** backend first (web calls the new endpoints; backend main auto-deploys — open as a DRAFT PR), then web.
The worktree branch tracks `origin/main` — push with an explicit `-u origin feature/reports-page`.

## Open questions for the client (defaults in brackets)
1. Headline: Sales before GST, or Total collected? [both shown; Sales leads]
2. "Beer report": a sales report, or the state excise stock register? [sales report; stock register is a separate future module]
3. Dine-in only acceptable for v1? [yes]
4. Business-day cutoff / when should it arrive? [shop's existing start hour; manual download for now]
5. Bar bill needs a liquor VAT line? [not in v1 — `ALCOHOL` computes no state VAT today]
