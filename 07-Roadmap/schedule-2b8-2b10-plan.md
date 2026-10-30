# Schedule 2b.8 to 2b.10: checkout, group payment, cancellation (geld deep review)

Status: FINAL (Q1 answered 2026-10-30). Reviewed 2026-10-30 as ONE design because the three phases share one state machine. Rows in [schedule-implementation-order.md](schedule-implementation-order.md) (2b.8, 2b.9, 2b.10; 2b.11 stays off until 2d) still hold the task text; this page holds the review and wins where they differ. Related: [2b.4 order group plan](schedule-2b4-order-group-plan.md), [2b.6 holds plan](schedule-2b6-holds-plan.md), [refund plan](refund-approval-plan.md), [restaurant terms](../02-Domain/restaurant-schedule-terms.md).

## Data model review

### Summary (read this first)
**Verdict:** the three phases can be built together on one branch as three reviewed slices (8, then 9, then 10), with seven changes to the written plan, mostly gaps between the group state machine and the refund core. Release is blocked only by the environment items you already deferred. Nothing is built; no SQL is needed by 2b.8 to 2b.10 beyond what already ran, and the one table the plan wanted (`order_payout_snapshot`) moves to 2c.
**What changes** (before → after):
1. Legacy payment code (734 lines, 10 methods that assume one order) is extracted into a shared core → built side-by-side as `GroupPaymentService`, legacy touched only at the webhook and sweep entry (Q1).
2. The group refund core only accepts a PAID group → it must also accept a capture that lands on a FAILED, CANCELLED or CAPTURE_MISMATCH group, because that is exactly when a refund is needed.
3. A second payment on one Razorpay order had no rule → it is refused as a payment, recorded, and refunded as its own obligation.
4. The hourly stale sweep skips groups, so a stuck unpaid group would never resolve → a group sweep is part of 2b.9.
5. The late-cancel endpoint depends on four writers of DELIVERED being safe → shipped OFF behind its own flag until a concurrency test proves it.
6. `order_payout_snapshot` (2b.8) has no reader until 2c and its shape depends on an unconfirmed GST rule → created in 2c.
7. Checkout freezes each line's tax with `LineTaxApportioner` in the order-creation transaction, with a sum assertion.
**Decisions you need to make:**
| # | decision | options | recommended, and why | if you pick the other option |
|---|---|---|---|---|
| Q1 | How to reuse the legacy Eat Now payment code for groups | (a) side-by-side `GroupPaymentService`, share only small pure helpers, touch legacy at two entry points · (b) extract a `PaymentOwner` core now (plan decision 43) | (a): the legacy file is live on production, already over the size limit, and 10 methods change under (b) with no Eat Now benefit today; the plan's flexibility goal is kept because `GroupPaymentService` is generic over the group | (b): one shared core sooner, but the live payment path is edited and re-tested first; the legacy race suite becomes a release gate |
**What geld decided for you:** no new group payment status (refund progress comes from refund rows, a PAID group whose members are all cancelled stays PAID); no `cancelled_at` column; checkout refuses unless the area's `schedule_enabled` is on; capture checks run before the status change; late capture on a lapsed hold stays all or nothing (your 2026-10-28 decision).
**What must happen before deploy:** (1) your slice 3 and slice 4 SQL steps, then deploy, then slice 3 Block 5; (2) Razorpay TEST-mode rehearsal of every payment race on a Neon branch; (3) `schedule_enabled` stays off in production; (4) `/judge deep`; (5) the late-cancel flag stays off until its gate passes.
**Unknowns:** the GST rule on commission (CA, blocks 2c not this); Razorpay duplicate-capture behaviour on one order (test mode); whether production runs more than one backend instance.

**Status:** FINAL · **Verdict:** APPROVED WITH CHANGES · geld deep, 2026-10-30
**Target:** PostgreSQL 17.11 on Neon (the one database is production), Spring Boot 4, hand-run SQL plus boot guards, single payment account (no Route split).
**Lenses run:** 0, 1, 2, 3, 4, 5, 7, 8 · **skipped:** 6 (pilot volume is tens of groups a day, no new hot table) · **reference designs:** skipped, a well-known class (two-phase hold then capture), applied by name.
**Codex second opinion:** blind pass; agreed 9, Codex-only verified 4 (refund core rejects non-PAID groups, second capture on one order, four DELIVERED writers, stale per-member text in the 2b.9 row), disagreements 1 (Codex kept the `PaymentOwner` extraction, see Q1).
**Open inputs:** Q1; D30 (GST on commission); Razorpay duplicate capture; backend instance count.

### Lens 0 (environment)
1 migration authority FAIL, 2 unreviewed schema writer FAIL (`ddl-auto=update`), 3 default path to production FAIL: the known ENV-1 to ENV-3, deferred by you, respected. 4 split credentials unknown. 5 recovery unknown (Neon restore window). 6 rehearsal: on a Neon branch, Razorpay test mode. 7 n/a. 8 rollout order: below. New for this release: the first group payment becomes possible, so the area flag and test-mode rehearsal are the safety.

### Built vs plan
| element | plan | in code | applied | note |
|---|---|---|---|---|
| `order_groups` and group columns, payment_status CHECK (CREATED, PAID, FAILED, CAPTURE_MISMATCH, CANCELLED) | 2b.4b | built | applied, 0 rows | CAS exists only for CREATED to PAID and CREATED to FAILED (`OrderGroupRepository`) |
| holds: acquire, confirm, void, restock | 2b.6 | built (`ScheduleReservationService`) | tables applied | confirm settles reservations, markPaid; checkout does not call acquire yet |
| group refund core, lock order, item slices | 2b.7 | built, branch `feature/schedule-2b7-group-refund-raise` | refund SQL applied except slice 4 | `GroupRefundServiceImpl.requireRefundable` accepts PAID only |
| `schedule_enabled` area flag, cart policy | 2a, 2b.5 | built | applied | the production switch |
| checkout, group payment, cancel | 2b.8 to 2b.10 | not built | n/a | `PaymentServiceImpl` webhook resolves only an Order; legacy sweep skips groups |

### Findings
#### Must change before the first group payment
**STATE-1 · risk · MUST** — group transitions have one writer each, all conditional: CREATED to PAID (`markPaid`), CREATED to FAILED (`markFailed`), plus the missing CREATED to CAPTURE_MISMATCH and CREATED to CANCELLED, and a conditional write of the captured payment id and amount. Failure: two callers (webhook and verify) both move a group, or a late capture overwrites the stored payment id. Change: add the missing CAS methods to `OrderGroupRepository`; the capture writer refuses a different payment id once one is stored. Cost now: free.
**STATE-2 · risk · MUST** — the refund core refuses any group that is not PAID (`GroupRefundServiceImpl.java` requireRefundable). Failure: a capture lands after the group was voided or cancelled, 2b.9 calls raise, it throws, the customer's money sits uncovered. Change: accept FAILED, CANCELLED and CAPTURE_MISMATCH when `razorpay_payment_id` and `captured_amount` were durably written first (as the legacy orphan path does), with `RefundEvent.PAYMENT_AFTER_FAILURE` and `CAPTURE_MISMATCH`.
**MONEY-1 · risk · MUST** — a second capture on one Razorpay order. Failure: the single stored payment id is overwritten, or the second capture is never refunded. Change: the writer rejects a different id; the extra capture is refunded as its own obligation keyed by its payment id, capped by that payment's own captured amount read from Razorpay (a refund row already carries its own `razorpay_payment_id`). Razorpay behaviour on duplicate capture is unverified: test mode.
**INV-1 · risk · MUST** — the hourly stale sweep skips group members, so an abandoned CREATED group never resolves and its holds linger. Change: a group sweep job: for CREATED groups past `hold_expires_at` plus grace, fetch the Razorpay order; captured, run the same confirm path; not captured, void and fail. One writer: the same CAS as STATE-1.
**INV-2 · risk · MUST** — the late-cancel gate. DELIVERED has four writers today: rider completion (`DeliveryServiceImpl.java:547`), staff force-complete (`:811`), the delivery-to-order projection (`DeliveryOrderSyncListener.java:47`), and the seller status route (`OrderServiceImpl.java:379`); assign, accept and pickup must also refuse a cancelled order. Change: each takes the member lock and writes conditionally on the current order status; the late-cancel endpoint ships behind its own flag, OFF, until a concurrent completion test, the rider-recall notice and the transition matrix all pass. The ordinary whole-group cancel before the freeze, and the restaurant decline, ship ON (they only touch SCHEDULED and PLACED orders).
**MONEY-2 · risk · MUST** — freeze each line's tax. In the order-creation transaction (`OrderAssembler`, after line ids exist) call `LineTaxApportioner.split(order.taxTotal, line taxable values)` and write `order_lines.tax_amount`; assert the shares sum to `tax_total`. Failure otherwise: item refunds have no tax and are refused.
**API-1 · risk · MUST** — the webhook resolves the owner by Razorpay order id: orders first, then groups (both unique); unknown logs and audits; one dispatch branch, not a refactor. Capture validation before the CAS: status captured, the group's Razorpay order id, amount in paise equal to `payable_total`, currency INR; on mismatch write the actual id and amount durably, set CAPTURE_MISMATCH, alert, refund in full.
**DOC-1 · MUST (docs)** — stale text: the 2b.9 row still lists per-member partial success (superseded by all-or-nothing); H-20 names a `group_refunds.reason` table (the reason lives in `payment_refunds`); 2b.10's "may add `cancelled_at`" is declined. Fix the rows.
**EVOL-1 · decided** — `order_payout_snapshot` moves from 2b.8 to 2c: no reader until 2c, and its shape depends on D30 (GST on commission, unconfirmed). Orders already carry the commission snapshots. If the CA later says otherwise, 2c adds it with a backfill from those columns.
#### Fine now, revisit at
- **PLACE-1 · revisit when Eat Now moves to holds or a third fulfilment type appears:** extract the shared payment core then; the group service is generic over the group so that move stays cheap.
- **ENV-5 · revisit:** guards check names, not `convalidated`.
- **COST-1 · revisit at 2c:** Razorpay refund speed, fees.
- 2b.11 release job stays off until 2d; the ticket and notification work is 2d.
#### Keep
- Lock order cart, group, members by id, then capacity and ledger rows; one writer per transition; conditional updates.
- The hold converts without a re-check while active and re-checks the whole group when lapsed (all or nothing).
- One unresolved group per customer per date (`uq_order_groups_open_checkout`); checkout idempotency key with request hash on the group.
- Manual refund approval; cancel freezes at ACCEPTED; platform account only.

### Devil's advocate trace
| point | outcome |
|---|---|
| "Do all three in one merge to save time" | rejected: 2b.9 captures real money and 2b.10 has a hard safety gate; one branch, three slices, each reviewed |
| "Extract the PaymentOwner core first, as decision 43 says" | Q1; recommended side-by-side, owner decides |
| "Add REFUNDED and PARTIALLY_REFUNDED group statuses" | rejected: refund rows are the one source of truth (2b.4 L-6); a second copy would drift |
| "Add `cancelled_at` to the group" | rejected: derivable from members and refunds; no reader |
| "Create `order_payout_snapshot` now, it is small" | rejected (EVOL-1): unconfirmed tax rule, no reader |
| "The area flag is enough, skip a test-mode rehearsal" | rejected: the flag stops customers, not our own first payment bugs |
| "Ship late-cancel with the rest" | absorbed (INV-2): ships OFF behind its own flag |

### Future phases
| phase | new tables | change forced here |
|---|---|---|
| 2b.11 release job | none | uses the member CAS SCHEDULED to PLACED |
| 2c settlement | `order_payout_snapshot`, `order_tax_lines` | derive payout from refund slices; none forced |
| 2d tickets and notifications | ticket tables | reads group and member states; none forced |
| 4 customer app | none | checkout contract (`PRICE_CHANGED`, `holdExpiresAt`, typed 409) is frozen by 2d.6 |

### Rollout
| step | change | order | safe with deployed backend |
|---|---|---|---|
| 0 | your SQL: slice 3 Blocks 0 to 4 (applied), slice 4 file | before deploy | yes |
| 1 | deploy the branch with `schedule_enabled` off everywhere | after step 0 | n/a |
| 2 | slice 3 Block 5 (drop the old allocation check) | after step 1 | yes |
| 3 | rehearse on a Neon branch in Razorpay test mode: checkout, pay, webhook-first, verify-first, duplicate capture, late capture, cancel, refund | before enabling any area | n/a |
| 4 | enable one area | pilot | n/a |
No new SQL for 2b.8 to 2b.10 unless Razorpay duplicate-capture behaviour needs a record table (decided at rehearsal).

### Design versions
| version | phase | date | what changed | why |
|---|---|---|---|---|
| v1 | 2b.8 to 2b.10 | 2026-10-30 | combined review; payout snapshot to 2c; side-by-side payment (Q1); refund core widened; late-cancel flagged off | geld deep and Codex |

### Locked decisions (handoff to /gcp and /judge; locked 2026-10-30)
| id | decision | enforced where |
|---|---|---|
| P-1 | one writer per group transition, all conditional (`markPaid`, `markFailed`, `markCancelled`, `markCaptureMismatch`, capture writer rejects a second id) | `OrderGroupRepository` + service + tests |
| P-2 | `GroupRefundService.raise` accepts PAID, FAILED, CANCELLED, CAPTURE_MISMATCH when payment id and captured amount are stored | service + test |
| P-3 | a second capture on one order is refused as payment and refunded as its own obligation | `GroupPaymentService` + test mode |
| P-4 | capture validation (status, order id, paise, INR) before any status change | service |
| P-5 | group sweep job resolves stale CREATED groups | job + test |
| P-6 | all DELIVERED writers and assign/accept/pickup refuse a cancelled order under the member lock; late-cancel endpoint behind its own flag, OFF | `DeliveryServiceImpl`, `DeliveryOrderSyncListener`, `OrderServiceImpl` + concurrency test |
| P-7 | line tax frozen in the order-creation transaction, shares sum to `tax_total` | `OrderAssembler` + test |
| P-8 | checkout refuses when the area's `schedule_enabled` is off; webhook resolves order then group | service |
| P-9 | no new group payment status, no `cancelled_at`, payout snapshot in 2c | design |

### Approval record
| finding or decision | option chosen | by | date |
|---|---|---|---|
| Q1 payment reuse | side-by-side group service (recommended option) | Samivan | 2026-10-30 |

## System design

### Main flow (2b.8 to 2b.10)
```mermaid
sequenceDiagram
  participant C as Customer app
  participant K as Checkout (2b.8)
  participant G as order_groups
  participant R as Razorpay
  participant W as Webhook / verify / sweep (2b.9)
  participant X as Cancel / decline (2b.10)
  participant F as Group refund core (2b.7)
  C->>K: checkout (idempotency key)
  K->>G: tx: lock cart, acquire holds, create group + orders, freeze line tax (CREATED, hold_expires_at)
  K->>R: create Razorpay order for payable_total (outside the tx)
  R-->>W: payment captured (webhook or verify)
  W->>G: validate capture, lock group then members, CAS CREATED to PAID, confirm holds, orders SCHEDULED, set cancel snapshots
  W->>F: capture on a FAILED/CANCELLED/MISMATCH group: raise refund (admin approves)
  X->>G: lock group then members, conditional status writes (never a DELIVERED order)
  X->>F: raise group, member or item refund; void holds and restock
```

### Decisions
- **Payment reuse:** side-by-side group service over refactoring the live payment path (Q1); revisit when a second fulfilment type needs groups.
- **Group status:** five values, derived refund state; the alternative (refund statuses on the group) loses because refund rows already are the truth.
- **Late cancel:** off by flag until the concurrency gate passes; the alternative (ship it ON with the transition-matrix test only) loses because a cancelled order that still gets delivered is the worst failure here.

### Isolation, tenancy, API
Payments module owns group payment and refunds; Schedule module owns reservations and carts; order status writes go through the member lock. The checkout request carries an idempotency key per customer, a request hash and a typed `PRICE_CHANGED`; money is amount plus currency; the webhook is signature-checked and audited.

## Build status (2026-10-30)

**BUILT and committed locally** on backend branch `feature/schedule-2b7-group-refund-raise` (commits `4f7ef92`, `64b2311` and the legacy-guard commit after it). Not pushed. Full suite green (about 1870 tests). Nothing has run against real Razorpay or a real database. Specs the implementer followed: [specs/](specs/).

| Phase | What exists |
|---|---|
| Foundations | group status writers (`markPaidWithCapture`, `markCancelled`, `markCaptureMismatch`, `recordOrphanCapture`), `CancelWindowResolver`, `GroupCaptureValidator`, `GroupKeys`, `GroupPaymentGateway` (Razorpay), the refund core accepting FAILED, CANCELLED and CAPTURE_MISMATCH groups with the actual captured amount |
| 2b.8 checkout | `POST /api/schedule/checkout`: area gate, ROUTE_SPLIT refusal, server re-pricing, group round-off, holds in the same transaction, frozen line tax weighted by each line own rate, idempotent replay, compensation only for the request that fails the group, typed PRICE_CHANGED and LINE_UNAVAILABLE |
| 2b.9 group payment | verify (stored order id), webhook dispatch (one branch in `PaymentServiceImpl.processWebhook`), capture validation, confirm or void with all-or-nothing refund, orphan and mismatch refunds, extra-capture refund, `cancelCheckout`, hourly stale-group sweep |
| 2b.10 cancel | whole-group cancel before `cancel_until_at`, member decline with `voidMember` restock, accept (admin accept audited), late cancel behind `schedule.late-cancel.enabled=false`, seller route delegation, DELIVERED writers refuse cancelled orders, legacy cancel and history refuse or skip group members |

**Reviews:** three blind Codex reviews of `4f7ef92` found nine real defects (gateway replay race, cart reopen, mixed-tax split, silent foreign line ids, refund of a different captured amount, verify message, late cancel on a delivered order, active-order query, stale seller guard) and I added a tenth (legacy `cancelCheckout` on a group member). All fixed with tests; each fix was mutation-checked.

**Not done, by design or by risk (read before enabling anything):**
1. Razorpay test-mode rehearsal of every payment race; duplicate-capture behaviour is unverified.
2. SQL not run: `payment-refunds-lines-migration.sql` (slice 4) and slice 3 Block 5; the new backend does not boot until the slice 4 file is applied (guard).
3. Late cancel stays OFF: rider recall notice has no listener, the rider app change is a teammate task, and the concurrency test against a real database is missing.
4. `release_at` is assumed to be the slot last-call instant (2b.11 release job is not built and stays off until 2d).
5. `schedule_enabled` stays off in production until the pilot.
6. Codex reported nothing on some attack points (member totals versus payable versus Razorpay paise, hold error mapping, ROUTE_SPLIT and the Eat Now edits in `OrderAssembler` and `BillTotalsCalculator`): treat them as unreviewed and cover them in `/judge deep`.
7. One Codex job for the group payment build stalled on a network reconnect; its files were complete when I checked, and the suite and mutation checks cover them.
