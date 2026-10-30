# Fix spec: Schedule checkout review findings (2b.8)

Four defects found by a blind Codex review of commit 4f7ef92. Repo: `ninja delivery service java`. You cannot run Maven or a database: read the code carefully. Edit only the checkout files named here plus `OrderGroupRepository` (additive) and their tests. Do not touch refund, payment, cancel or delivery code.

## 1. Gateway replay race (ScheduleCheckoutServiceImpl)
Two requests with the same idempotency key can both reach Razorpay while the group has no stored gateway order. If one gateway call fails and its compensation fails the group, the other can still store its Razorpay order id (the store only checks that the id is null) and return a payable response for a FAILED group.
Fix: storing `razorpay_order_id` becomes ONE conditional native update in `OrderGroupRepository` that requires `razorpay_order_id IS NULL AND payment_status = 'CREATED'` and returns the rows changed. When it changes 0 rows, re-read the group: if it is still CREATED with a stored order id, return that stored result (the other request won); if it is not CREATED, throw a clear conflict (BusinessRuleViolationException saying the checkout expired) and never return a payable response. The extra Razorpay order created by the loser is left unpaid.

## 2. Compensation reopens a cart another request completed (ScheduleCheckoutServiceImpl)
Compensation sets the cart ACTIVE before checking whether the group is still CREATED. Fix: run the compensation steps (void holds, member orders failed, cart back to ACTIVE) ONLY when this request wins the `OrderGroupRepository.markFailed` conditional update (returns 1). If markFailed returns 0 another request already moved the group, so do nothing else and rethrow.

## 3. Tax assigned to exempt lines (ScheduleCheckoutWriter)
`LineTaxApportioner.split` is fed each line value as its basis, so in a mixed-tax order (one exempt line, one taxed line) the exempt line receives tax. Fix: the basis for each line is that line own tax weight: line total multiplied by its tax rate percent (an exempt line, rate 0, has basis 0 and receives 0.00). If every basis is zero and the order tax is positive, fall back to the line totals so the shares still sum to the order tax. The sum-equals-order-tax assertion stays. Add a test with one exempt line and one taxed line proving the exempt line gets 0.00 and the taxed line the whole order tax.

## 4. Foreign or unticked line ids silently ignored (ScheduleCheckoutRules)
A request listing one of the customer ticked line ids plus another id (another customer line, or a line that is not ticked) proceeds with only the valid one. Fix: when `selectedLineIds` is non-empty, EVERY requested id must be one of the customer own ticked cart lines, otherwise throw a BusinessRuleViolationException (message: a selected line is not in your cart) and write nothing. Update the existing rules test that expects the silent filtering to expect the refusal, and add cases: all valid, one foreign, one unticked, empty list means all ticked lines.

## Tests and rules
Add or adjust unit tests beside each change (JUnit 5 plus Mockito, no database): the two-request race ordering (store returns 0 rows on a FAILED group, never a payable response), compensation only on a won markFailed, the mixed-tax split, the line id refusal. Keep files under 250 lines and comments to one sentence stating the rule. Reply with the files changed and anything unverified. Do not claim anything compiles or passes.
