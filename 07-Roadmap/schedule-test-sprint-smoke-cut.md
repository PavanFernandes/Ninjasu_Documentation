---
id: ""
title: "Schedule test sprint — risk-ranked smoke cut"
summary: "About 60 checks chosen from the ~305 open manual items and the Schedule acceptance spec, ranked by risk: live-on-production features never tested first, then the Schedule money path, then web, then mobile. Backend items run as CLI scripts on a Neon branch; Claude writes and runs them, Codex reviews."
type: how-to
status: active
apps: [backend, web, customer]
module: "schedule"
anchors:
  - { repo: backend, path: "db_manual/payment-refunds-migration.sql" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/refund/PaymentRefundServiceImpl.java" }
verified_against: "backend feature/schedule 10ac545; web and app feature/schedule (refund board 69359a3 and app copy 86e40ac are in feature/schedule, NOT on main); nothing below has been run"
updated: 2026-11-04
---

# Schedule test sprint: smoke cut (2026-11-04)

Source lists (full detail lives there, this file only picks and orders): [manual-test-todo-refunds.md](manual-test-todo-refunds.md), [manual-test-todo-2b13.md](manual-test-todo-2b13.md), [browser-test-todo-2b12c.md](browser-test-todo-2b12c.md), [schedule-acceptance-tests.md](schedule-acceptance-tests.md) (R1-R13 and T2b), [manual-test-todo-schedule-my-orders.md](manual-test-todo-schedule-my-orders.md), [pos-mobile-permissions-device-test.md](pos-mobile-permissions-device-test.md).

Owner: **S** Samivan, **C** Claude (runs scripts), **X** Codex (writes script files from a spec file, blind read-only review; Claude re-verifies every claim). Result column: PASS / FAIL (fix id) / BLOCKED. `main` equals `feature/schedule` in all three repos, so testing the `feature/schedule` HEAD covers both.

Order rule: money that is already live on production, then money that Schedule will move, then screens. Stop and fix on the first FAIL in tiers 1 and 2; do not start building until tiers 1 and 2 are green.

## Tier 0: environment (blocks everything)
| # | Step | Owner | Result |
|---|---|---|---|
| 0.1 | Neon branch of production named `test-schedule`; host, user, password saved to `keys/test-branch.env` | S | |
| 0.2 | Razorpay TEST key id, secret, webhook secret in the same file; ngrok tunnel to the local backend for webhooks | S | |
| 0.3 | Boot guard: script refuses to start unless `DB_URL`, `DB_USERNAME`, `DB_PASSWORD` are set; startup log datasource host equals the branch host | C | |
| 0.4 | Backend boots on the branch from the CLI (`./mvnw spring-boot:run`, dev profile): "Payment refund schema verification passed" and the Schedule schema guard passes | C | |
| 0.5 | Seed script: platform admin, two customers (9999999001 plus one), one single-merchant shop with menu, one ROUTE_SPLIT shop, a Schedule area, slots, stock rows | C+X | |
| 0.6 | `select status, count(*) from payment_refunds group by status;` on PRODUCTION (read-only) to learn if any refund rows exist | S | |

## Tier 1: live on production, never tested (backend scripts)
Refund core (backend PR #69, migration run 2026-10-29). Highest risk because it holds real customers' money and the admin board is not on `main`.
| # | Check | Source | Owner | Result |
|---|---|---|---|---|
| 1.1 | The seven `chk_payment_refunds_*` constraints, the self FK and orders FK exist; subject check refuses both-null and both-set | refunds B | C | |
| 1.2 | Decision checks: SYSTEM row SUBMITTING without admin refused; REJECTED without note refused; approved above requested refused | refunds B | C | |
| 1.3 | Unique obligation index: two live rows, one key refused; allowed after the first is FAILED | refunds B | C | |
| 1.4 | Unique receipt and gateway refund id; many NULL gateway ids allowed | refunds B | C | |
| 1.5 | Two sessions approve and reject one REQUESTED row at once: exactly one wins (F9) | refunds B | C | |
| 1.6 | Migration runs a second time with no error (idempotent) | refunds B | C | |
| 1.7 | Duplicate Razorpay receipt: second create rejected? (judge F2; if not, stop and fix) | refunds C | C | |
| 1.8 | Full refund path: approve, SUBMITTING, ISSUED/PROCESSED, `refund.processed` webhook, order REFUNDED with `refund_id` and `refunded_on` | refunds C | C | |
| 1.9 | Partial refund 20 of 100 on a single-merchant shop: Razorpay gets 2000 paise, order stays PAID, net sales drop by 20 | refunds C | C | |
| 1.10 | Partial approval on ROUTE_SPLIT shop refused; full goes with `reverse_all=1` | refunds C | C | |
| 1.11 | Razorpay rejects (more than captured): row FAILED with message, order stays REFUND_PENDING, Retry creates a new row that goes through | refunds C | C | PARTIAL: approve returns 200 and the row goes SUBMITTING (t4-refunds). Gateway reject to FAILED and Retry need a real captured payment (phone test). |
| 1.12 | Unknown outcome: kill after create, before save; after the 10-minute lease the job finds the refund by receipt, no second refund | refunds C | C | |
| 1.13 | Duplicate `refund.processed` webhook changes nothing; webhook before our save matches by receipt | refunds C | C | PARTIAL PASS: duplicate external refund.processed leaves the same row. Receipt-before-save order still open. |
| 1.14 | Dashboard refund (no receipt) creates an EXTERNAL PROCESSED row; PAID stays PAID for a partial | refunds C | C | PASS: signed external Rs 20 partial makes an EXTERNAL PROCESSED row, order stays PAID. |
| 1.15 | Admin API authz: no token 401, customer token 403, non-admin 403; decided-already row returns the message, not 500 | refunds D | C | PASS 401/403 for anon, customer, owner on all 5 routes (t1-admin-api, 2026-11-04). Decided-row part open (needs a refund row). |
| 1.16 | Approve rules: amount above requested refused, `20.005` refused, partial without note refused; reject needs a note and returns a full-request order to PAID | refunds D | C | PASS: above-requested, 20.005, partial without note, reject without note all 400; reject 200 and order back to PAID. |
| 1.17 | Every admin mutation writes an audit row (admin actor for decisions, SYSTEM otherwise) | refunds D | C | |
| 1.18 | Four triggers raise a REQUESTED row: customer cancel of PAID online, shop decline, orphan capture, stock failure at confirm | refunds E | C | PARTIAL PASS: customer cancel, shop decline (RESTAURANT_DECLINED) and orphan capture (ORPHAN_CAPTURE) each raise a REQUESTED row. Stock-failure trigger open. |
| 1.19 | COD and never-PAID online orders: cancel and decline raise nothing | refunds E | C | PARTIAL PASS: COD cancel and unpaid online cancel raise nothing. Decline variants open. |
| 1.20 | Cancel after a dashboard partial refund requests the remainder only; force `raise` to fail and the cancel rolls back | refunds E | C | PARTIAL PASS: cancel after a Rs 20 partial requests the remainder only (Rs 201 of 221). Forced-raise rollback open. |
| 1.21 | Customer order view shows `refunds` and never the technical cause; shop and admin views carry an empty list | refunds F | C | PARTIAL PASS: customer order view shows refunds, shop view 200. Admin list and history views open. |
| 1.22 | `PaymentReconciliationJob` once: legacy REFUND_PENDING without refund id gets a LEGACY request and no unapproved refund reaches Razorpay | refunds G | C | |
| 1.23 | Idempotency-Key reuse by another customer on place order and checkout: 400 "Checkout attempt unavailable" (generic, no leak) | refunds H | C | PASS (400 not 409): other customer reusing a key on place order and on checkout is refused and no order id leaks. Doc updated 2026-11-04 (F-D1) |

Commission cards and platform profiles (2b.13, SQL run 2026-10-21):
| # | Check | Source | Owner | Result |
|---|---|---|---|---|
| 1.24 | `commission_slab`, version, assignment tables and `order_seller_snapshot` reject update, delete, truncate | 2b13 C | C | |
| 1.25 | Assignment rules: 24h notice, `NOT_AFTER_EXISTING`, stale `expectedLatest` 409, currency mismatch, two admins at once exactly one wins | 2b13 E | C | PASS notice 400, currency 400, stale 409, concurrent 200+409, NOT_AFTER_EXISTING 400 (t1-admin-api). |
| 1.26 | Checkout snapshot: no-assignment shop gets default card, commission 0.00, `grand_total` unchanged; shop on Standard v1 with add-ons gives 20.00 per unit; reassign does not change old orders | 2b13 F | C | |
| 1.27 | Snapshot columns for POS, guest QR, counter sale and grocery orders are NULL and no seller snapshot for POS | 2b13 F | C | |
| 1.28 | Non-admin tokens 403 on every commission and platform-profile route | 2b13 D,G | C | PASS 401/403 on all card, assignment, version-move and platform-profile routes. |

Add-on pricing (2b.12c):
| # | Check | Source | Owner | Result |
|---|---|---|---|---|
| 1.29 | Online price above cap refused with server message; exactly at cap accepted; dine-in 0 and online 5 refused (T2b-29) | 2b12c, T2b-29 | C | PASS over cap 400, at cap 200, dine-in 0 refused. |
| 1.30 | Shop owner cannot CHANGE a dine-in price on any edit path (add-on group, inline options, shared group): 403; creation may set both prices (D27) (T2b-30, T2b-37) | T2b-30/37 | C | PASS owner edit 403, admin edit 200. Code lets an owner set both prices on CREATE (see findings). Doc fixed 2026-11-04 (F-A1 resolved: code matches D27) |
| 1.31 | Create idempotency: same key returns the same option; different body 400; key longer than 64 refused | 2b12c H | C | PASS replay same option, different body 400, 65-char key 400. |

## Tier 2: Schedule money path (backend scripts; no manual test list exists, built from R1-R13 and T2b)
| # | Check | Source | Owner | Result |
|---|---|---|---|---|
| 2.1 | `GET /api/schedule/context` returns dishes with the right availability reason; hidden vs greyed rules (T2b-36) | T2b-36 | C | PARTIAL PASS: seed dishes ORDERABLE at online prices, other date 400 (t2-schedule-nopay). Sold-out/cutoff/hidden fixtures still to do. |
| 2.2 | Schedule cart accepts two shops; Eat Now second shop still rejected; mixed date or slot rejected; COD `placeOrder` rejects Schedule | T2b-10 | C | PASS two Schedule shops 200, mixed slot 409, mixed date 400, COD Schedule 400, Eat Now second shop 409. |
| 2.3 | Hold: two customers, last unit: exactly one holds; held qty derived; hold expires at 180 s and releases | 2b.6 | C | |
| 2.4 | Checkout creates one group and two member orders coded `XXXX-A`, `XXXX-B`; same key retried creates no second group (R8) | T2b-12/21, R8 | C | PARTIAL PASS: same key returns same group and gateway order; two member codes. Concurrent replay open. (Needed the OrderAssembler discount fix: see F-C1.) |
| 2.5 | Happy path pay, verify, then webhook: group PAID once, members confirmed, holds converted (R1) | R1 | C | |
| 2.6 | Verify and webhook race together: one settlement (R2) | R2 | C | |
| 2.7 | Captured amount differs: CAPTURE_MISMATCH and the real captured amount refunded (R4) | R4 | C | |
| 2.8 | Capture after the group was cancelled, failed or swept: orphan refunded in full (R5) | R5 | C | |
| 2.9 | Pay after the hold deadline: checkout refuses, late capture refunded, stock not double-sold (R6) | R6 | C | |
| 2.10 | Gateway order creation fails: group FAILED, holds voided, cart reopens (R7) | R7 | C | |
| 2.11 | `PRICE_CHANGED` returned when an online price moved since the cart; no payment created until reconfirmed | T2b-11 | C | PARTIAL: mismatched quote returns 409 PRICE_CHANGED; real price move + reconfirm not yet tested. |
| 2.12 | Money identity: member totals plus group fees and round-off equal the Razorpay amount in paise on a two-shop group (R13) | R13 | C | PASS: members + fees = Rs 339 = 33900 paise = Razorpay order amount. |
| 2.13 | Customer cancels the whole group before `cancel_until_at`: one full refund, reservations voided, restock; after the deadline refused (R9, T2b-16) | R9 | C | |
| 2.14 | Cancel refused when any order is ACCEPTED or later (T2b-16d); cancel with one declined order refunds the rest once (16e) | T2b-16d/e | C | |
| 2.15 | Shop declines one member: that member refunded, holds restocked, others unaffected (R10) | R10 | C | |
| 2.16 | Release job: orders become PLACED once, two instances race safely, voided order ignored (T2b-18) | T2b-18 | C | |
| 2.17 | Hourly sweep resolves an unpaid CREATED group past its hold and never touches a paid SCHEDULED order (R11, T2b-19) | R11 | C | |
| 2.18 | Group refund: row closed by `refund.processed`, FAILED can be retried (R12, T2b-27) | R12 | C | |
| 2.19 | Rider guards: delivery completion after cancel refused; projection never overwrites CANCELLED (T2b-16o/q) | T2b-16o/q | C | |
| 2.20 | Customer group list and detail: owner only, another customer 403/404, refunds use the regular-order contract | PR 5 | C | PARTIAL PASS: owner reads own unpaid group, other customer cannot, list is captured-only. Refund contract needs a paid group. |
| 2.21 | Eat Now regression: COD order, online verify then webhook, shop with no service area behave as before (T0, T2a-07) | T0, T2a-07 | C | PARTIAL PASS: COD order placed, ACCEPTED, PREPARING, READY all 200; online verify/webhook and no-area shop still to do. |

## Tier 3: web (Playwright against the branch backend; S checks visuals and the Razorpay screen)
| # | Check | Source | Owner | Result |
|---|---|---|---|---|
| 3.1 | Refund board `/admin/refunds`: tabs, approve full, approve partial with note, reject with note, retry (double click sends one request), conflict banner | refunds I | C | PASS 2026-11-04 (a-f; 3.1g retry needs a real Razorpay failure, deferred). Double click sent 2 requests: FIXED, see F-E1 |
| 3.2 | Board access: non-admin and signed-out cannot open it; decision calls 401/403 | refunds I | C | PASS 2026-11-04 (signed out, customer token, no CSRF header). F-E2 FIXED: customer token in the admin cookie now redirects to login (3.2b), proxy decision still 403 (3.2d) |
| 3.3 | Commission cards: create with slab preview, new version, rename, bulk move, shop Commission tab, change-card review step | 2b13 H | C | PASS 2026-11-04 (create with slab preview, rename, review and confirm, new version, bulk move; shop A only). F-F1 FIXED: review step blocks and explains a clash with a scheduled change (3.3b) |
| 3.4 | Shop owner menu editor: dine-in read-only, online editable, over-cap refused, no duplicate on retry | 2b12c B | C | PASS 2026-11-04 (dine-in read-only, over-cap refused, one PUT) |
| 3.5 | Admin Pricing page: cap save, review queue Mark reviewed (one request) | 2b12c D | C | PASS 2026-11-04 (cap save and restore, Mark reviewed sends one request) |
| 3.6 | Shop Schedule tab: accept/decline a member; card shows the member order code (`XXXX-A` form, carrying the group code), customer, items, paid label and member status; it does not show group or refund state (shop views carry an empty refunds list, row 1.21) | PR 5 / shop tab | C | PARTIAL 2026-11-04: tab and history render with no errors; accept, decline and ready need a paid group (phone test). See F-H1 Doc updated 2026-11-04 (F-H1) |
| 3.7 | Razorpay checkout screen once in test mode, UPI | S | S | |
| 3.8 | Dark mode and 360 px width on the board and commission screens | refunds I, 2b13 H | S | |

## Tier 4: mobile (S on a device, after C pre-verifies the API responses)
Run [manual-test-todo-schedule-my-orders.md](manual-test-todo-schedule-my-orders.md) (49 items) against the branch backend, plus:
| # | Check | Owner | Result |
|---|---|---|---|
| 4.1 | App refund wording: Refund initiated, Refunded on date, Refund not approved with note (refunds I) | S | |
| 4.2 | Shop decline confirm text and button (refunds I) | S | |
| 4.3 | POS mobile permission gating on a device (PR #26) | S | |
| 4.4 | Restaurant app item create and edit price boxes on 360 dp, airplane-mode retry makes no duplicate (2b12c J) | S | |

## Not in this cut (deliberately)
2b.4a (46 items) and the rest of the 305 stay open; pick from them only for a failure that points there. Not testable yet: customer Schedule creation flow (no app screens), STATE-4 bulk delivery (Schedule orders stall at READY; later statuses are set directly on the branch).

## Findings log
Add one line per FAIL: id, what broke, fix commit, retest result.

- F-A1 (doc vs code, not a failure): acceptance T2b-37 says a shop owner cannot write a dine-in price on any path; the code (`AddonPriceWriter.java:30,50`) lets an owner set BOTH prices when CREATING an option, and rejects only edits that carry a dine-in price (`:96`). The sprint seed itself created items this way. Decide: fix the doc or tighten the code.
  Resolution: F-A1 resolved by doc (D27).
- F-A2 (doc wording): the 24-hour assignment notice (1.25) has a first-real-card exception in code (`AssignmentStartRules.java:59`); the smoke cut wording omits it. Seen in `manual-test-todo-2b13.md:72`, so only this table is wrong.
- F-A3: Job B's 2.11 only proves a wrong quoted total returns PRICE_CHANGED, not that a moved add-on price is detected; keep 2.11 open until a price is actually changed between cart and checkout.

- **F-C1 (REAL BUG, fixed, uncommitted):** every Schedule checkout for a dish with no discount returned HTTP 500: `OrderAssembler.assembleSchedule` set the order add-on `discount_percent` to the add-on discount, else the item discount, both null, and the column is NOT NULL (Eat Now coalesces to 0 at its builder). Fix: coalesce to `BigDecimal.ZERO` at `OrderAssembler.java:240`. Found by t3-schedule-pay 2026-11-04. No unit test covered `assembleSchedule`; add a regression test before commit.
- F-D1 (doc vs code): cross-customer reuse of an Idempotency-Key returns HTTP 400 ("Checkout attempt unavailable"), not 409 as the refund plan (1.23) says. No data leak, so the intent holds; fix the doc or the code.
  Resolution: F-D1 test expectation changed to 400; the 400-versus-409 product decision stays open in `schedule-branching-policy.md`.
- F-D2: Eat Now capture webhooks trust the webhook payload (`PaymentServiceImpl.java:455,478`), so fake signed webhooks settle Eat Now orders. Schedule verify and capture fetch the payment from Razorpay (`GroupPaymentServiceImpl.java:32,43-49`), so Schedule settlement (2.5-2.9, 2.13-2.15, 2.18) needs a real captured test payment: deferred to the phone test (Samivan, 2026-11-04). Refund submission of a made-up payment id stays SUBMITTING, not FAILED (`PaymentRefundSubmitter.java:89`).
- F-D3: the order API response has no refund id or refunded-on field (`OrderResponse.java:19`), so 1.8 metadata needs the DB.
- Test-harness note: `/auth/send-otp` allows 5 codes per phone per hour (`app.otp.phone-rate-limit-per-hour`); sprint scripts now cache tokens in `keys/seed-state.json` and customers 9999990001/2 alias to 9999990003/4.

- Withdrawn recommendation: tightening the backend to refuse an owner dine-in price on create would break web and mobile item creation (D27).
- **F-E1 (REAL BUG, fixed, uncommitted in Ninjasu_Web):** double click on Approve/Reject/Retry in the refund dialog sent TWO POSTs (button disables only after a re-render). Backend first-wins keeps money safe; UI now uses a single-flight guard (`useSingleFlight` in RefundDetailDialog.tsx). Found by 3.1e; retest passes.
- F-E2 (doc vs code): `proxy.ts` checks the admin cookie exists and is unexpired, not the admin role, so a valid customer JWT in the admin cookie reaches the page shell; Spring rejects the data and decisions (3.2b passes). The manual list says non-admins cannot open the board.
  Resolution: F-E2 FIXED in Ninjasu_Web `src/proxy.ts` (admin page gate requires audience admin; UX redirect only), uncommitted.
- F-F1 (UI copy vs rule): the change-card review step says "This also replaces the change already scheduled for this channel", but confirming an immediate change is refused with "A change must start after the shop's latest change; cancel a scheduled change first". Fix the copy, or let the rule replace.
  Resolution: F-F1 FIXED in Ninjasu_Web `ChangeCardDialog.tsx` (copy plus pre-check that disables Confirm), uncommitted.
- F-H1 (doc vs code): the shop Schedule order card shows code, customer, items, paid label and status; the smoke cut expects group and refund state too. Decline picks a reason directly, no separate confirm button.
  Resolution: F-H1 doc only.
- Web tier harness: web checkout is feature/schedule-shop-history (3 ahead of feature/schedule); specs live in Ninjasu_Web/tests/sprint (git-excluded, delete at sprint end); tests leave ZZ rows (refund fixtures, ZZ web commission cards, shop A moved to a ZZ web card).
