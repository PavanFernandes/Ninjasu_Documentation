---
id: ""
title: "Payment types and split payment (dine-in settle)"
summary: "Per-shop payment methods (Cash/UPI/Card seeded, owners add more) and settling one dine-in bill with several payments; defines what payment_mode and bill_payments.method now hold and which one reports must group by."
type: domain
status: active
apps: [backend, web, mobile]
module: "pos-payments"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/PaymentTypeServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/BillServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/config/PaymentTypesMigrationRunner.java" }
  - { repo: web, path: "src/features/shop/components/pos/RecordPaymentDialog.tsx" }
  - { repo: web, path: "src/features/shop/components/PaymentMethodsCard.tsx" }
  - { repo: mobile, path: "src/features/pos/components/PaymentMethodPicker.tsx" }
updated: 2026-09-26
---

# Payment types and split payment

Scope: dine-in check settlement (`recordPayment`, and `settleWrittenOffBill` for correcting a write-off).
Takeaway and delivery record no payment here.

## Rules

- **Payment types are per shop** (`shop_payment_types`). Cash, UPI and Card exist for every shop from first use
  (seeded lazily by `ensureDefaults`, backfilled for existing shops by `PaymentTypesMigrationRunner`).
  Owners/managers add types, rename custom ones and turn any type on/off on the web Settings page. **The default Cash/UPI/Card cannot be renamed** (the API rejects it) — legacy `{mode}` requests and reports rely on those names. **Types are never deleted, only
  disabled**, and at least one must stay active.
- `system_code` (CASH/UPI/CARD) is set only on the seeded rows and survives renames. It is how a legacy
  `{mode}` request and "which one is cash" find the right row. Custom types have `system_code = NULL`.
- **A bill can be paid with 1–10 payments.** Their amounts must add up to `Bill.grandTotal` exactly, or the whole
  settlement is rejected and rolled back (no bill number is used). The same type may appear twice.
- Request body: `{ payments: [{ paymentTypeId, amount }] }`. Old app builds send `{ mode: CASH|UPI|CARD }`,
  which pays the whole bill with the shop's seeded type (accepted even if the shop disabled it — old builds
  cannot see the list). Sending both, or neither, is rejected.

## What is stored where

| Column | Holds | Use |
|---|---|---|
| `bill_payments.payment_type_id` | FK to the shop's payment type | **Group/filter money reports by this** (join `system_code` for "was it cash") |
| `bill_payments.method` | the type's NAME at payment time (legacy rows: CASH/UPI/CARD) | display only |
| `table_checks.payment_mode` | display summary of the names used ("Cash", "UPI + Cash"); legacy rows CASH/UPI/CARD | display only, plus `IS NOT NULL` = "was actually paid" |

- **`table_checks.payment_mode IS NOT NULL` is the revenue predicate** (`sumPaidDineInTotalForPeriod`,
  `SalesReadModelService`). A write-off leaves it NULL, so it is never counted as revenue. Every real settlement —
  single, custom type or split — must set it. Never parse the text; never write a value for an unpaid check.
- No `OTHER`/`SPLIT` codes exist anywhere: screens show exactly the names configured in Settings.

## API

`GET /api/shops/{shopId}/payment-types?includeInactive=` (POS floor roles for active only; owner/manager for
`includeInactive=true`) · `POST` `{name}` and `PATCH /{id}` `{name?, active?}` (owner/manager).
Names: 1–40 chars, unique per shop ignoring case, max 20 types per shop.

## Deploy notes

- `PaymentTypesMigrationRunner` widens `table_checks.payment_mode` to varchar(500) and `bill_payments.method` to
  varchar(40) and drops every CHECK that mentions those columns (the hand-named `chk_table_checks_paymode` and
  Hibernate-generated `*_check` ones). It is **non-fatal** (a boot-time DDL runner must never crash the API): DDL runs
  only when the catalog says it is needed, under a 5s `lock_timeout`, and a failure logs at ERROR — until it succeeds,
  settlements that record a type name are rejected by the old constraint, so check the logs after deploy.
- Rolling the backend back after new rows exist breaks reads (old code expects the enum) — fix forward.

## Not built

Takeaway payment capture, tips, cash tendered/change, partial payment / a BILLED state, credit / pay-later
(a custom type named "Credit" would count as collected revenue — that needs a receivables feature, not a type),
reordering types, `reference` capture, managing types from mobile.
