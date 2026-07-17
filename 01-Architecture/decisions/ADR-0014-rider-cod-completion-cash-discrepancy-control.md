---
id: ADR-0014
type: decision
status: accepted
apps: [rider, customer, backend]
module: rider-app
anchors: []
verified_against: ""
updated: 2026-07-12
---

# ADR-0014: Rider COD completion bundles OTP + cash, with a cash-discrepancy control

## Context

Rider delivery completion bundles OTP verification + cash collection into one atomic step (bundling
is confirmed correct — separating them lets a rider close with OTP but never collect cash, or vice
versa). Short-pay handling was accepted as "complete + flag discrepancy" (rider enters actual
amount, OTP still required, delivery completes, cash row flagged for staff).

Phase-0 fraud research (2026-07-12) found that "complete + flag" **as specced is a one-tap,
self-authorizing skim**: a rider can collect the full COD, enter a lower amount, and mark the
customer short-paid — the OTP still validates, so the discrepancy looks legitimate. **OTP proves
the customer received the order; it does not prove how much cash changed hands.** Without a
customer-side control, "flag for staff" is an after-the-fact ledger note, not a control.

## Decision

Keep bundled OTP + cash completion and the "complete + flag" short-pay path, but add three controls:

1. **Customer-visible recorded amount** — after completion, the customer's app shows the amount the
   rider recorded as collected. Under-reporting becomes customer-visible (and disputable).
2. **Discrepancy cap + mandatory reason** — a short-pay below the order total requires a reason
   code; a discrepancy beyond a configured cap requires staff override (logged), not rider
   self-authorization.
3. **Per-rider discrepancy monitoring** — track discrepancy frequency per rider; threshold
   auto-flag/block for review.

Schema: `delivery_cash_collections` stores `amount_expected` + `amount_collected` +
`discrepancy_reason`. OTP remains non-skippable; the only bypass is a staff-issued, logged override
(also the terminal state after the 5-attempt cap and the dead-customer-phone fallback).

## Consequences

- Turns an after-the-fact ledger note into a live fraud control; a legitimate short-pay still
  completes (rider never stranded).
- Requires a customer-app surface for the recorded amount and a staff reconciliation/monitoring
  view; adds small fields to `delivery_cash_collections`.
- Pairs with the ungated-onboarding decision: a cash-handling rider must be traceable/blockable
  (rider status flag + delivery audit columns) even though KYC gating is deferred.

## Enforced in

To build: delivery completion endpoint (OTP + cash, ownership-enforced), `delivery_cash_collections`
schema, customer order-view amount display, staff reconciliation view. Related:
[[ADR-0009-pluggable-otp-auth]], principles.md #15 (production hardening — ownership enforcement).

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
