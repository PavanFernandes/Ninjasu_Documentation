# Schedule Phase 2c.1 + 2c.2: settlement inputs — geld + devil's advocate review

**Status:** BUILT 2026-11-05 (backend PR #79, merge e2c7f44 into `feature/schedule`; D1-D4 answered) · **Verdict:** APPROVED WITH CHANGES (no new tables; payout formula split out and gated on the CA) · next: 2c.4 payout (after the CA), 3.5 XLSX export, SalesReadModel fix
**Reviewed:** 2026-11-05 against backend branch `bug/prepaid-cash-due` @ `1ee83d9` (2b.7, 2b.8, 2b.9, 2b.10, 2b.12, 2b.13 built; 2b.11 parked). Plan under review: [schedule-implementation-order.md](schedule-implementation-order.md) lines 138-146.
**Method:** code investigation (Explore agent, ~40 file reads) + blind read-only Codex pass (not shown my findings) + my own spot checks. Codex and Explore agreed on every blocker; the items I re-read myself are marked (verified).
**Lenses run:** 0 (n/a, see below), 1, 3, 4, 5, 6, 7, 8 · **skipped:** 2 (no table, column or key is proposed) · **reference designs:** skipped (not a new data store; the ledger question is MONEY-2, already gated).
**Target:** PostgreSQL on Neon · SQL hand-run, Hibernate `ddl-auto=update` · single DB that is production (memory `feedback_one_neon_db_is_prod`). This slice adds no DDL, so lens 0 checks 1-4 do not apply; the read queries do run against production when run locally.

## Summary (read this first)

**Verdict:** the direction holds (2c.1 and 2c.2 can be read-only, no new tables), but the plan's one-line rule "DELIVERED and not refunded" cannot be implemented as written, and 2c.2's "payout" must be split out until the CA answers.

**What changes (plain, before → after):**
- "Not refunded" was read off `Order.paymentStatus`. After → derived from refund rows (`payment_refunds` + `payment_refund_allocations`), because Schedule group refunds never change a member order's `paymentStatus`.
- "Refunded" had no single meaning. After → three states per order: **processed** (cash gone), **in flight** (requested, submitting, issued), **none**; a fully refunded order is out, a partly refunded one is in at its net value, an in-flight one is held.
- 2c.2 "payout" had no stored home. After → 2c.2 exports the **components** (item value, tax, round-off, commission, refunds, group charges); the payout formula becomes 2c.4, blocked on the CA.
- The export is stamped with `as_of` and `generated_at`, and counts a refund only when its `processed_at` is at or before `as_of`; it is a preview until a payout batch freezes a run.
- "Shared with Numbers" is dropped: Numbers is Phase 8 and does not exist. The only existing "net sales" query (`SalesReadModelService`) ignores group refunds and is fixed or retired separately.

**Decisions you need to make:**
| # | decision | options | recommended, and why | if you pick the other option |
|---|---|---|---|---|
| D1 | A delivered order with a **partial** refund | (a) stays settleable at its net value (b) excluded whole | (a): the restaurant delivered the rest; excluding underpays it | (b) needs a manual claim path for the unrefunded part |
| D2 | A delivered order with an **in-flight** refund (requested, submitting or issued) | (a) hold it out of this run and list it (b) pay it and claw back if processed | (a): paying first means Ninjasu fronts money it may have to take back | (b) needs a negative-adjustment line in the next run |
| D3 | 2c.2 payout | (a) export components only, payout formula waits for the CA (b) compute payout now with the quote calculator's rule (18% GST on commission borne by the restaurant) | (a): GST on commission and TDS are unconfirmed; (b) would bake a guess into a money file | (b) is wrong if the CA says otherwise, and every exported file must be redone |
| D4 | Which orders the export covers | (a) Schedule groups only (b) Schedule + Eat Now food orders (they also carry a commission snapshot) | (a): Eat Now has no group, no fee split and no payout rules yet | (b) needs an Eat Now settlement design first |

**What geld decided for you:**
- No `refunded_amount` / `refund_state` columns anywhere: refund position is derived from refund rows (those columns were removed on purpose in 2b.4/2b.7).
- Group delivery and packaging are exported once per group, never repeated on member rows.
- Period basis for Schedule is the group's service date (business date), not `placed_on`.
- External (gateway-side) group refunds have no slices, so any group holding one is held whole and listed for an admin; attributing them is a later write feature, not part of this read-only slice.

**What must happen before deploy:** (1) D1-D4 answered; (2) the refund-position function exists with the status × refund matrix test; (3) the reconciliation fixture below passes; (4) branch from `feature/schedule`, PR into it, not `main`; (5) nothing to run in SQL.

**Unknowns that could change this:** the CA (0.7) on GST on commission, TDS 194-O, and who remits the 5% order GST (gates 2c.4 only); whether late cancel (flag off) ever goes live; whether line/quantity refunds get a production caller (today only tests call `forItems`).

## Findings

### Must change before this slice is built
**MONEY-7 · risk · MUST — "not refunded" cannot be read from `Order.paymentStatus` for Schedule.**
- Evidence: group refunds never touch member `paymentStatus` (members stay PAID, `GroupPaymentSettlement.java:145`); the order-level flip to `REFUND_PENDING` happens only when open refunds equal the grand total (`PaymentRefundServiceImpl.java:96-100`, verified). `OrderRepository.sumNetSalesForPeriod` and `sumProcessedPartialRefundsForPeriod` filter on `paymentStatus` and `r.orderId = o.id` (`OrderRepository.java:213-246`, verified): they never see a group refund.
- Failure: a two-restaurant group, member A fully refunded by a group refund, A is DELIVERED with `paymentStatus` PAID → the predicate marks A settleable → A's restaurant is paid for a refunded order.
- Change: the predicate takes a refund position computed from `payment_refund_allocations` joined to `payment_refunds`, for order refunds and group refunds alike (order refunds also write an allocation, `PaymentRefundServiceImpl.java:95`). Legacy orders with `refund_id` and no refund row fall back to `paymentStatus`.
- Cost to change now: free (not built).

**MONEY-8 · risk · MUST — "open" refund sums mix requests with cash.**
- Evidence: `sumOpenAmountFor*` add REQUESTED (requested amount) to SUBMITTING, ISSUED and PROCESSED (approved amount) (`PaymentRefundRepository.java:17-21`, verified).
- Failure: a REQUESTED refund later REJECTED or FAILED reduces a restaurant's payout in a run, then reappears in the next → payout moves with no business event.
- Change: the refund position keeps **processed** (status PROCESSED, `processed_at <= as_of`) and **in flight** (REQUESTED, SUBMITTING, ISSUED) as two separate amounts; only processed reduces the net; in flight triggers the hold (D2).
- Cost to change now: free.

**MONEY-9 · risk · MUST — the exit identity leaves out tax and round-off.**
- Evidence: payable = member subtotals + member tax + group delivery + packaging + group round-off (`ScheduleCheckoutWriter.java:122,159`); the plan's identity is "captured − refunds = payouts + commission + group charges" (plan line 146).
- Failure: the reconciliation test is off by exactly the 5% GST and the round-off on every group.
- Change: identity becomes captured − processed refunds = Σ member net item value + Σ member tax (liability, not payout) + commission + group charges + group round-off, each net of their refund slices. Export columns: `item_value`, `tax_total`, `round_off`, `commission_total`, `delivery_fee`, `packaging_fee`, each with its refunded part.
- Cost to change now: free.

**MONEY-10 · risk · MUST — unallocated refunds make a group unreconcilable.**
- Evidence: EXTERNAL gateway refunds on a group are stored with no slices (`RefundWebhookHandler.java:150-167`, Codex + Explore); a second payment id (extra capture) has its own refund path (`ExtraCaptureRefundService`).
- Failure: Razorpay shows a refund the allocations cannot place on a member → group-level totals reconcile, member payouts silently do not.
- Change: a group with an EXTERNAL refund or a mismatch/extra-capture status is held whole and listed in an exceptions section with the amount and payment id; refunds on a payment id other than the group's captured one are listed apart, never netted into the group.
- Cost to change now: free.

**TIME-5 · risk · MUST — the export is not repeatable.**
- Evidence: refund status is overwritten in place (no status history); only `processed_at` is write-once (`PaymentRefund.java:103`, verified).
- Failure: finance re-runs "last week" on Friday and gets different numbers because a refund was processed Thursday; or an in-flight hold from last week cannot be reconstructed.
- Change: every export row set carries `as_of` and `generated_at`; processed refunds count by `processed_at <= as_of`; in-flight state is "as of generation time" and labelled so; the file is called a preview until a payout batch (2c.4+) freezes a run. Schedule period = group `service_date` in the area's time zone, not `placed_on` (`Delivery.deliveredAt` is a zone-less `LocalDateTime`, not usable as a period key).
- Cost to change now: free.

**MONEY-11 · trade-off · MUST (owner decision D3) — payout depends on unconfirmed tax facts.**
- Evidence: `PayoutCalculator` exists but is quote-only (`PriceQuoteCalculator.java:28`); no payout is stored (commission plan decision); GST on commission, TDS and ECO 9(5) are with the CA (memory `project_gst_fssai_billing`).
- Failure: a payout figure in a money file assumes 18% GST on commission is borne by the restaurant; if the CA says otherwise every file is wrong.
- Change: 2c.2 exports components only; payout becomes **2c.4**, blocked on the CA answer; severity keeps the risky answer, per geld rule.
- Cost to change now: free.

### Fine now, revisit at a trigger
- **Late cancel after ACCEPTED** (`schedule.late-cancel.enabled=false`): never refunds fees and never reaches DELIVERED. Revisit when the flag is turned on.
- **Line/quantity refunds** (`forItems`) have no production caller, so commission reversal by `refunded_quantity × unit_commission` is built in the math but unreachable. The matrix test builds these rows directly; revisit when an "item unavailable" flow ships.
- **Typed partial approval** shrinks a single allocation silently and keeps commission and payout unchanged (OD2, `refund-approval-plan.md:483`, verified): the export must show this as a platform-funded refund, not a restaurant deduction.
- **Query cost**: batch read over orders, allocations and refunds per service date and shop. Not a hot path; run per service date and shop, off peak. Measure before adding an index on `payment_refunds(status, processed_at)`.
- **MONEY-2 ledger gate**: this slice produces ledger inputs only; the double-entry settlement ledger stays gated at 2c.4+.
- **SalesReadModelService** (`SalesReadModelServiceImpl.java:33-51`) ignores group refunds, so purchasing's food-cost % overstates sales for Schedule. Fix before the first Schedule order is DELIVERED in production; adopt the new refund position rather than a second rule.

### Keep (good decisions)
- Group delivery and packaging live only on `order_groups`; members carry 0 (`OrderAssembler.java:218-220`): one place, no double counting.
- Commission is frozen per order and per line (`commission_rate_card_version_id`, `unit_commission`, `line_commission`); refunds never rewrite it.
- Plan id is reached by `CommissionRateCardVersion.cardId` from the order's pinned version id: no copy to drift.
- No refund or payout columns on `orders` (2b.4 decision) stays.
- DELIVERED is final in code: no path reverts it (Explore, writers listed in the review).

## Design (no tables)

**New code only, all read-only:**
- `RefundPosition` per order: `processed`, `inFlight`, `fullyRefunded` (processed ORDER allocations + fee/round-off slices at group level equal the order's grand total), computed once for a set of order ids in one query.
- `SettleableOrderPredicate.evaluate(order, position, asOf)` → `SETTLEABLE` / `FULLY_REFUNDED` / `HELD_REFUND_IN_FLIGHT` / `HELD_GROUP_EXCEPTION` / `NOT_DELIVERED`. One owner; the export calls it, and later Numbers and the retired net-sales query call the same one.
- `SettlementRowAssembler` (2c.2) builds the rows: per member order `item_value`, `tax_total`, `commission_total` (+ card id, version number), `commission_reversed` (Σ item-slice `refunded_quantity × unit_commission`), `refunded_processed`, `refunded_in_flight`; per group `captured_amount`, `delivery_fee`, `packaging_fee`, `round_off`, fee refunds, `as_of`, `generated_at`, exception flags.

**Allocation rules (documented, to be repeated in 02-Domain):**
1. A member's refundable value is its grand total; group charges are refundable at group level only.
2. Item slices reverse commission by `refunded_quantity × unit_commission`; ORDER and typed-amount slices leave commission unchanged (platform-funded, OD2); a fully refunded order's commission is 0.
3. Delivery and packaging are exported once per group and reduced by their own fee refunds; they are Ninjasu revenue.
4. The group's round-off appears once, on the group row.
5. Tax is a liability column, never part of a restaurant's item value.

**Phase map:** 2c.1 predicate + refund position · 2c.2 component export + reconciliation test · 2c.3 unchanged (Route-split guard) · **2c.4 payout formula (blocked on the CA)** · 3.5 settlement XLSX consumes 2c.2 rows.

## Tests
- Status × refund matrix: {not delivered, delivered} × {none, partial processed, full processed, requested, submitting, issued, failed, rejected} × {order refund, group refund, legacy `refund_id` only} → each lands on one outcome.
- Reconciliation fixture (independent expected values, written by hand, not derived by the code under test): two-restaurant group, one item-slice partial refund processed, fees untouched. captured − processed refunds equals the sum of exported components to the paisa; both pass and fail with a deliberately wrong capture.
- Exceptions: EXTERNAL group refund; `CAPTURE_MISMATCH`; extra-capture refund on a second payment id; each holds the whole group and appears in the exceptions section.
- Repeatability: run at `as_of` T, process a refund, run again at T: identical; run at T+1: differs by that refund only.
- Guard: no new query outside the predicate filters on `paymentStatus NOT IN (REFUND_PENDING, REFUNDED)` to decide settleability (same style as `CustomerItemQueryGuardTest`).

## Devil's advocate trace
| DA point | outcome |
|---|---|
| Derived vs stored refunded (check 1) | already handled: no stored columns by design (2b.4, 2b.7); MONEY-7 derives from refund rows |
| Business logic in two places (check 3) | absorbed: MONEY-7 and the SalesReadModel item; one predicate owns "settleable" |
| Implicit filter trap (check 8): members stay PAID after a group refund | absorbed: MONEY-7 plus the guard test |
| Goal left partial (check 9): "one definition of settleable" has three live readers (`sumNetSalesForPeriod`, `sumProcessedPartialRefundsForPeriod`, legacy REFUND_PENDING sweeps `OrderRepository.java:205-211`) | absorbed: readers listed; only SalesReadModel is replaced (separate PR, before the first Schedule delivery); the legacy sweeps are refund-raising machinery and stay |
| Absence claims (check 10): "Numbers" and `order_payout_snapshot` | verified by search of `src` and `db_manual` (Explore): neither exists; Numbers is Phase 8 |
| Export reproducible? | absorbed: TIME-5 |
| Partial quantity refund unreachable | recorded under revisit; matrix builds the rows directly |
| Working tree is dirty (2d.7 cash-due, uncommitted) | rejected as a blocker: 2c touches no `Delivery*` file; still branch from `feature/schedule`, not from this branch |

## Codex second opinion
Agreed on all five risks: eligibility vs net, lifecycle mixing (verified), unallocated external refunds, commission formula, group fees once. Disagreement: Codex called the commission reversal formula "undefined"; it is defined for item slices and typed partials in `refund-approval-plan.md:483` and is restated above as allocation rule 2. Codex also found two stale sentences in `commission-rate-cards-plan.md` (:79 says customer orders charge no GST, :111 says only whole-order refunds exist); both should be corrected in a docs pass.

## Future phases
| phase | new tables it adds | change forced on this design |
|---|---|---|
| 2c.4 payout formula | none yet | needs CA answers; may add a payout batch record |
| payout batch / ledger (MONEY-2) | batch, ledger entries | freezes a run; replaces the "preview" label |
| 3.5 settlement XLSX | none | reuses the 2c.2 rows; adds the XLSX renderer path |
| 8 Numbers | none | calls the same predicate |

## Rollout
Code only, no SQL. Branch from `feature/schedule`; PR into `feature/schedule`. Deploy order: nothing before the code. Rollback: remove the code; no data changes.

## Open inputs
- CA (0.7): GST on commission, TDS 194-O, who remits the 5% order GST (2c.4 only).
- Whether Eat Now food orders join the export (D4).
- Settlement period basis for Eat Now (not needed under D4a).

## Design versions
| version | phase | date | what changed | why |
|---|---|---|---|---|
| v0.1 | 2c.1-2c.2 | 2026-11-05 | first review: refund position, split payout to 2c.4, as_of | code check showed group refunds bypass `paymentStatus` |

## Approval record
| finding or decision | option chosen | by | date |
|---|---|---|---|
| D1 partial refund on a delivered order | settle at net value | Samivan | 2026-11-05 |
| D2 in-flight refund on a delivered order | hold out of the run and list it | Samivan | 2026-11-05 |
| D3 payout | components only; payout formula = 2c.4 after the CA | Samivan | 2026-11-05 |
| D4 scope | Schedule groups only | Samivan | 2026-11-05 |
| MONEY-7 to MONEY-10, TIME-5 | accepted as written (geld-decided, not asked) | geld | 2026-11-05 |

## Locked decisions (handoff to /gcp and /judge)
| id | decision | enforced where | code paths that must honour it |
|---|---|---|---|
| L-1 | Refund position comes from `payment_refunds` + `payment_refund_allocations`, never from `Order.paymentStatus` alone (legacy `refund_id` with no refund row is the only fallback) | service (one `RefundPosition` query) + guard test | settlement export, retired net-sales query, any new settlement reader |
| L-2 | Processed (PROCESSED, `processed_at <= as_of`) and in-flight (REQUESTED, SUBMITTING, ISSUED) are separate amounts; only processed reduces net | service | `RefundPosition`, predicate, export rows |
| L-3 | Partly refunded delivered order stays settleable at net (D1); fully refunded is out; in-flight is held and listed (D2); FAILED and REJECTED are ignored | predicate | `SettleableOrderPredicate` |
| L-4 | A group with an EXTERNAL refund, `CAPTURE_MISMATCH` or a refund on a second payment id is held whole and listed apart | predicate + exceptions section | export assembler |
| L-5 | Export rows carry `as_of` and `generated_at`; labelled a preview until a payout batch exists; Schedule period = group service date in the area zone | service + file header | export assembler |
| L-6 | Components only: `item_value`, `tax_total`, `round_off`, `commission_total` (+ card id, version number), `commission_reversed`, refunds, group delivery and packaging; no payout column (D3) | assembler | 2c.2; payout waits for 2c.4 |
| L-7 | Commission reversal = Σ item-slice `refunded_quantity × unit_commission`; ORDER and typed-amount slices leave commission unchanged (platform-funded, OD2) | assembler | 2c.2 |
| L-8 | Group delivery, packaging and round-off appear once per group, never on member rows | assembler | 2c.2 |
| L-9 | Scope is Schedule groups only (D4): rows with a non-null `group_id` | predicate | Eat Now orders never enter |
| L-10 | Branch from `feature/schedule`, PRs into it | process | all 2c PRs |

## Build record (2026-11-05)
Backend PR #79 into `feature/schedule`, merge e2c7f44. Code: `service/schedule/settlement/` (`SettlementModel`, `RefundPositionCalculator`, `GroupExceptions`, `SettleableOrderPredicate`, `SettlementRowAssembler`, `SettlementReport`, `SettlementReadService`), three repository queries, `MoneyRules.money`. Full suite without contextLoads: 2092 tests, 0 failures. Codex wrote the code; an independent read-only Codex review found nine items and four were fixed before merge (order-level refunds missed by the loader, exception refund details, full-refund commission net, payment-status guard).

**Not done / follow-ups:**
- `/judge quick` was not run (user-invoked only): run it before `feature/schedule` goes to `main`.
- No endpoint or XLSX: task 3.5 consumes `SettlementReport`.
- Payout formula: 2c.4, blocked on the CA.
- `SalesReadModelService` (food-cost %) still ignores group refunds: fix before the first Schedule order is DELIVERED in production.
- Deferred review items: refunded tax per component (typed refunds record 0 tax today); a null `captured_amount` shows as a large unreconciled amount with no named flag; groups with no delivered member are omitted by design; no negative round-off test; no real-database test (repo has no test DB).
- Three private copies of the scale-2 rounding helper remain (`GroupRefundMath`, `LineTaxApportioner`, `FeeResolver`): point them at `MoneyRules.money` in a separate refactor if approved.
- Stale sentences in `commission-rate-cards-plan.md` (:79 customer GST, :111 whole-order refunds only).
