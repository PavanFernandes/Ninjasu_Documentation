---
id: ""
title: "Manual test TODO — admin-approved refunds"
summary: "Manual test list for everything the refund feature built but could not prove from code: the real database (constraints, unique indexes, row lock), Razorpay test mode (duplicate receipt, partial and failed refunds, webhooks), the admin API, the cancel/decline/orphan/stock-fail flows, the customer view, the legacy backfill and net sales, the 409 idempotency rule, and the web board and app copy (built, committed on branches, not yet run in a browser or on a device); nothing below has been run"
type: how-to
status: active
apps: [backend, web, customer]
module: "refunds"
anchors:
  - { repo: backend, path: "db_manual/payment-refunds-migration.sql" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/refund/PaymentRefundServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/refund/PaymentRefundSubmitter.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/refund/RefundWebhookHandler.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/controller/AdminRefundController.java" }
verified_against: "backend main e2e26cc (PR #69, merged and deployed 2026-10-29); nothing below has been run"
updated: 2026-10-29
---

# Manual test TODO: admin-approved refunds (2026-10-29)

Owner: **S** = Samivan, **C** = Claude. Nothing below has been run. What IS verified in code: backend suite 1166 tests (context test excluded), the offline JPQL parse of the new queries, a bare-Spring wiring test (no bean cycle), and mutation checks that the money-path tests can fail. The migration `payment-refunds-migration.sql` was run on the production database on 2026-10-29 (15 statements, success) and the deploy was green; the new version was not independently confirmed.

**Write only against a Neon branch, never prod.** The backend defaults to the production datasource and the web `.env.local` points at ngrok, so "local" writes hit production. A branch of prod already has the refund tables. Run tests as `./mvnw test "-Dtest=!NinjaDeliveryServiceApplicationTests"` with `MAVEN_OPTS=-Xmx512m` on this machine.

Plan: [refund-approval-plan.md](refund-approval-plan.md). Judge findings that these tests close or watch are named as `F<n>`.

## A. Setup
- [ ] **S** Create a Neon branch of prod (name it `test-refunds`); copy its connection string.
- [ ] **S** Run the backend locally with `DB_URL`, `DB_USERNAME`, `DB_PASSWORD` set to the BRANCH; confirm with `select current_database(), current_setting('neon.endpoint_id', true);` before any write.
- [ ] **C** Razorpay TEST keys only; online payments enabled; a webhook tunnel (ngrok) pointed at the local backend with the test webhook secret.
- [ ] **C** Users on the branch: a platform ADMIN (`PLATFORM_ADMIN_USER_IDS`), two customers (test phone 9999999001, dev OTP 1234, and a second), one single-merchant shop with a menu, one route-split shop.
- [ ] **C** Backend started once on the branch: log shows "Payment refund schema verification passed".

## B. Real-database facts (what mocks cannot prove)
- [ ] **S** `select conname from pg_constraint where conrelid = 'payment_refunds'::regclass` lists the 7 `chk_payment_refunds_*` constraints plus the self FK and the orders FK; `payment_refund_allocations` has its check and 2 FKs.
- [x] **S** Subject check: insert a row with both `order_id` and `order_group_id` null, and one with both set: both refused. (sprint 2026-11-04, smoke-cut 1.1)
- [ ] **S** Decision check: a SYSTEM row with status SUBMITTING and no `decided_by_admin_id` is refused; a REJECTED row with no `decision_note` is refused; approved above requested is refused; SUBMITTING with no `lease_until` is refused.
- [x] **S** Unique obligation index: two live rows with one `obligation_key` are refused; the same key is allowed once the first row is FAILED (partial index). (sprint 2026-11-04, smoke-cut 1.3)
- [x] **S** Unique receipt and unique gateway refund id: duplicates refused; many NULL gateway ids allowed. (sprint 2026-11-04, smoke-cut 1.4)
- [ ] **S** Allocation check: `component = 'ORDER'` needs an `order_id`, a fee component must have none; amount 0 refused. Deleting a refund cascades its allocations; deleting an order that has refunds is refused.
- [ ] **C** `sumOpenAmountForOrder`: REQUESTED counts the requested amount, SUBMITTING/ISSUED/PROCESSED the approved amount, REJECTED and FAILED nothing.
- [ ] **C** `findLegacyRefundPending` and `findLegacyRefundOwed` return the right orders (REFUND_PENDING with and without a refund id, with and without refund rows).
- [ ] **C** `sumProcessedPartialRefundsForPeriod`: only PROCESSED rows, only DELIVERED/COLLECTED orders, excludes REFUND_PENDING and REFUNDED orders, and only counts allocations whose refund belongs to the same order (F6).
- [ ] **C** Order row lock: two sessions approve and reject the same REQUESTED row at once; exactly one wins and the other is refused with "Refund is not requested" (F9).
- [ ] **C** `technical_detail` jsonb round trip: a map written by `raise` reads back unchanged.
- [ ] **C** Boot guard negative case (on a second branch WITHOUT the migration): the backend refuses to start and names the missing objects and the SQL file.
- [ ] **S** The migration runs a SECOND time on a branch with no error and the same object counts (idempotent).

## C. Razorpay test mode
- [ ] **C** Duplicate receipt: create two refunds on one payment with the same `receipt`. Record whether the second is rejected (judge F2). If it is NOT rejected, stop and claim a single-use submission state before the gateway call.
- [ ] **C** `fetchAllRefunds(paymentId)` returns the receipt we sent; a refund created in the dashboard has no receipt.
- [ ] **C** Full refund: approve a full request; the row goes SUBMITTING, then ISSUED or PROCESSED; the `refund.processed` webhook marks it PROCESSED and the order REFUNDED with `refund_id` and `refunded_on` set.
- [ ] **C** Partial refund (single-merchant shop): approve 20 of 100 with a note; Razorpay receives 2000 paise; the order stays PAID; net sales drop by 20 for the order's period.
- [ ] **C** Partial approval on the route-split shop is refused; a full refund goes with `reverse_all=1`.
- [ ] **C** A refund Razorpay rejects (for example more than the captured amount): the row becomes FAILED with the message, the order stays REFUND_PENDING, and Retry creates a new row that goes through.
- [ ] **C** Unknown outcome: block the network after the create call (or kill the app between create and save); the row stays SUBMITTING; after the 10-minute lease the hourly job finds the refund by receipt and moves the row forward without a second refund.
- [ ] **C** Webhook before our save: replay `refund.processed` for a row still SUBMITTING with no gateway id; it matches by receipt (or by the fetched receipt) and PROCESSES it.
- [ ] **C** Duplicate webhook delivery: the second `refund.processed` changes nothing.
- [ ] **C** Dashboard refund (no receipt) on a PAID order: an EXTERNAL PROCESSED row appears, the order stays PAID for a partial and becomes REFUNDED when the sum equals the total; no Razorpay fetch holds the webhook transaction open (F35).
- [ ] **C** A `refund.failed` event for an ISSUED row marks it FAILED.
- [ ] **C** Lost webhook: an ISSUED row with no webhook stays ISSUED forever today (known gap F3); note how long it takes to notice.

## D. Admin API (platform admin token; Postman or curl)
- [ ] **C** `GET /api/admin/refunds` returns REQUESTED rows oldest first, `totalPages` is right, `size=1000` is clamped to 100, `status=FAILED` filters.
- [ ] **C** `GET /api/admin/refunds/{id}` shows reasons, technical cause and detail, shop name and order total; unknown id gives 404.
- [ ] **C** Approve with no body amount approves the full requested amount; amount above requested is refused; `20.005` is refused (two decimals only); a partial without a note is refused.
- [ ] **C** Reject needs a note; the order returns to PAID only for a full request with no other open row.
- [ ] **C** Retry works only on a FAILED row with no live row for the same key.
- [ ] **C** No token: 401. A non-admin customer token: 403. Another admin deciding an already decided row gets the refusal message, not a 500.
- [ ] **C** Every mutation writes a platform audit row (requested, approved, rejected, issued, processed, failed, external) with the admin as actor for decisions and SYSTEM for the rest.

## E. The four trigger flows (customer app or API)
- [ ] **C** Customer cancels a PAID online order: a REQUESTED row appears, the order is REFUND_PENDING, nothing is sent to Razorpay until approval.
- [ ] **C** Shop declines a PAID online order: same, with reason `RESTAURANT_DECLINED`.
- [ ] **C** Orphan capture: fail an order (back out of checkout), then complete the UPI payment late; a `PAYMENT_AFTER_FAILURE` request appears with the payment id on the order.
- [ ] **C** Stock failure at confirm: make the item sold out between checkout and payment; the order is CANCELLED, the payment stays PAID until the request is raised, then REFUND_PENDING.
- [ ] **C** COD order, and an online order that never reached PAID: cancel and decline never raise a refund.
- [ ] **C** Cancel after a dashboard partial refund (F1): Rs 20 of Rs 100 refunded outside the system, then the customer cancels; the request is for Rs 80 and the cancel succeeds. When the whole amount was refunded outside, the cancel succeeds and no request is raised.
- [ ] **C** Cancel and decline are all-or-nothing: force `raise` to fail (for example remove the payment id on the branch); the cancel is rolled back and the order is unchanged.

## F. Customer view
- [ ] **C** Order detail and order history show `refunds`: INITIATED with the plain reason, REFUNDED with the processed date, NOT_APPROVED with the admin's note and the order back at PAID.
- [ ] **C** The response never contains the technical cause or detail, and the shop and admin order views carry an empty `refunds` list.
- [ ] **C** A FAILED refund with no retry shows as INITIATED (decision F5); with a retry it shows only the retry.

## G. Legacy orders and reports
- [ ] **S** On the branch, count `REFUND_PENDING` orders with and without `refund_id` (read-only) before the first hourly tick.
- [ ] **C** Run `PaymentReconciliationJob` once: orders without a refund id get a LEGACY request (reason from the order status), orders with a refund id are finished by the old path only, no unapproved refund reaches Razorpay.
- [ ] **C** Net sales for a shop and period with one processed partial: the figure drops by the partial and the order is not counted twice.

## H. Idempotency keys (F8)
- [ ] **C** Customer B sends customer A's `Idempotency-Key` to place order: 400 with the generic message "Checkout attempt unavailable" and no data about A's order. Customer A repeating the key gets the same order.
- [ ] **C** Customer B sends customer A's key to checkout: 400 with the generic message "Checkout attempt unavailable"; A's own PENDING_PAYMENT key still resumes.

## I. Web board and app copy (BUILT 2026-10-29, committed on branches, never run in a browser or on a device)
Code: Ninjasu_Web `feature/refund-board-web` (`69359a3`), Food-Ninja-Frontend `feature/refund-app-copy` (`86e40ac`), neither pushed nor merged. Checked so far: typecheck and lint clean, web unit spec `tests/refund-utils.spec.ts` (36), app `__tests__/orders/refundCopy.test.ts` (16), a Codex correctness lens on both. Board at `/admin/refunds`. Run against the Neon branch from section A, never prod.

Board (needs a browser on the admin host, signed in as the platform admin)
- [ ] **C** Tabs: Needs action shows FAILED above REQUESTED; In progress shows SUBMITTING then ISSUED; Refunded; Rejected. Each list pages at 20 and each has a loading skeleton, an empty text and an error state with Retry (stop the backend to see it).
- [ ] **C** REQUESTED rows are oldest first; the badge reads "Waiting · 5h" and turns red at 24 hours. Leave the board open across the 24-hour mark (or set a row's `requested_at` back on the branch): the badge changes within a minute without a reload.
- [ ] **C** A FAILED row shows "Failed"; once 24 hours past its decision time it shows "Action needed · 1d". Known limit: measured from approval time, not failure time (the API has no failure time).
- [ ] **C** Detail dialog shows every field, "—" where empty, copy buttons on ids, the technical detail as JSON.
- [ ] **C** Approve full: the amount field is prefilled with the requested amount and the button reads "Approve ₹X and send to Razorpay"; the toast shows, the dialog closes, the row leaves Needs action and appears under In progress or Refunded.
- [ ] **C** Approve partial: type a lower amount; the partial-refund hint appears and Approve stays disabled until a note is typed; the request sent has the amount and note (see browser network tab); amounts above the request, 0, `abc` and three decimals are refused in the field.
- [ ] **C** Reject: the button stays disabled until a note is typed; the customer app then shows "Refund not approved: <note>".
- [ ] **C** Retry on a FAILED row sends one request and creates a new attempt; double-click does not send two.
- [ ] **C** Conflict: open a REQUESTED row in two admin sessions, decide it in one, then decide in the other. The second shows the backend message, then a banner "This refund changed while you were reviewing it. It is now: ..." and the Approve and Reject buttons go away.
- [ ] **C** Close race: click Approve, close the dialog at once, open another refund; the new dialog stays open when the first answer arrives.
- [ ] **C** Opening a row refreshes it (one `GET /api/admin/refunds/{id}`); the dialog never offers Approve for a row that is no longer REQUESTED.
- [x] **C** A non-admin account and a signed-out browser cannot open `/admin/refunds` (proxy redirect) and the three decision calls return 401/403. (sprint 2026-11-04, smoke-cut 3.2)
- [ ] **C** Dark mode: badges, banner and dialog read correctly; mobile width: the table scrolls sideways and the dialog scrolls.

App (device or Expo build against the branch backend). Group refunds on the Schedule group screen use the same wording; they are tested in [manual-test-todo-schedule-my-orders.md](manual-test-todo-schedule-my-orders.md), section C.
- [ ] **C** Order summary: INITIATED shows "Refund initiated" with the plain reason; REFUNDED shows "Refunded on <date>"; NOT_APPROVED shows "Refund not approved: <note>" plus "Contact support if you have questions."; two refunds on one order show a "Refunds" heading.
- [ ] **C** An order whose payment status is only REFUND_PENDING shows "Refund initiated" in the payment row, never "Refunded"; REFUNDED shows "Refunded".
- [ ] **C** An order response without `refunds` (point the app at an old backend or strip the field) still renders the summary.
- [ ] **C** Shop decline of a paid online order: the confirm reads "Declining will initiate the customer's refund. Are you sure?" with the button "Yes, decline order".

Open decisions and follow-ups
- [ ] **S** Timeout: default on `apiClient` and the proxy (affects 30 service files) or only on the five refund calls. The proxy `fetch` and the axios client have none today (judge, web F1).
- [ ] **S** Who checks the board each day, and what happens when a request is older than 4 hours.
- [ ] **S** Backend `failedAt` on the refund, so "Action needed" counts from the failure and not the approval.
- [ ] **S** Whether the board should poll for new requests; today it refetches on window focus only, because polling keeps the scale-to-zero database awake.
- [ ] **C** Ninjasu_Web order views carry no refund text today (nothing to change there for L-10); decide whether the shop order view should show its refund state.
- [ ] **C** Re-run `/judge deep` on both branches before any merge; the partial-approval note, conflict, clock and `refunds` default fixes have not been re-judged.

## J. Deploy and rollback checks
- [ ] **S** Production container log has "Payment refund schema verification passed" after the 2026-10-29 deploy.
- [ ] **S** Rollback note: the switch is code only; the refund tables can stay. A rollback to the previous backend would restore automatic refunds and the hourly sweep would again pay every REFUND_PENDING order, including those with requests still waiting for approval; decide before rolling back.
