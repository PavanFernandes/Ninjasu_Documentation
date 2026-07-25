---
id: ADR-0018
type: decision
status: accepted
apps: ["backend", "customer"]
module: "payment"
anchors: []
verified_against: ""
updated: 2026-07-18
---

# ADR-0018: Razorpay Online Payment — Two-Phase Checkout/Confirm + Pluggable Settlement

## Context

Food Ninja's customer DELIVERY flow (`orderType=DELIVERY`, `orderSource=CUSTOMER`) has only
ever supported COD, placed synchronously in `POST /api/orders`. Adding online payment (UPI/card
via Razorpay) cannot reuse that synchronous shape: a gateway call sits between "order intent"
and "money actually captured," and that gap must not corrupt inventory, duplicate shop
notifications, or leave orders in limbo if the customer's network dies mid-payment.

KOT / dine-in / takeaway are explicitly **out of scope** — they settle via
`table_checks.payment_mode` at the counter ([[ADR-0012-captain-ordering-dine-in-pos-kds]]); the
two money paths never overlap and this ADR does not touch that flow.

Three things forced explicit decisions:
- **When does stock decrement, and when does the order become visible to the shop?** A naive
  "decrement + notify at order-creation" (the COD shape) would hold inventory hostage against
  abandoned payment sheets and would ring the shop kitchen for orders nobody paid for.
- **How is "payment succeeded" learned, given two independent, unreliable signals** — the
  client polling after the Razorpay Checkout sheet closes, and Razorpay's server-to-server
  webhook? Either one can arrive first, twice, or not at all (app killed, network drop, sheet
  dismissed but payment actually went through).
- **Does every shop settle to the same merchant account?** Some shops will want funds to land in
  their own linked account (Razorpay Route) rather than the platform's, and that has to be an
  opt-in per shop, not a platform-wide fork.

The alternative considered and rejected for all three: extend the existing single-transaction
`placeOrder` path with a payment step inline. Rejected because a DB transaction must never span
an external gateway call (the gateway can hang or fail independently of the DB, and Spring
self-invocation would bypass `@Transactional` proxies for the compensating rollback anyway).

## Decision

**Two-phase checkout/confirm, with a single idempotent confirm reached by two independent
triggers.**

```
Phase 1  POST /api/payments/checkout   → validates cart+address (shared OrderAssembler,
                                          same code COD's placeOrder uses), locks the cart
                                          session, creates Order{status=PENDING_PAYMENT},
                                          creates the Razorpay order, returns checkout params.
Phase 2  confirmPayment(orderId, ...)  → reached by EITHER:
           (a) POST /api/payments/verify   — client, immediately after the sheet closes (fast UX)
           (b) POST /api/webhooks/razorpay — Razorpay server callback (authoritative net)
         CAS payment_status CREATED→PAID gates it: the loser of the race no-ops.
         Only on the winning call: stock decrements, order→PLACED, cart→COMPLETED,
         OrderPlacedEvent publishes AFTER_COMMIT (same event, same shop-ring path as COD).
         Stock failure post-capture → order CANCELLED, paymentStatus REFUND_PENDING (money is
         never silently lost — a refund worker completes it later).
```

Stock decrements **at confirm, not at checkout** — an abandoned payment sheet holds no
inventory. `PENDING_PAYMENT` orders are excluded from every shop/customer read path until they
either confirm or die.

**Why both webhook and client-verify exist, rather than picking one:** client-verify alone is
not authoritative — a killed app or dropped connection after a successful payment would strand
the order in `PENDING_PAYMENT` forever with no compensating signal. Webhook alone is not fast
enough for UX — its delivery latency is untrusted, and the customer needs an immediate
success/failure state when the Checkout sheet closes. Running both against **one** shared,
CAS-guarded `confirmPayment` gets the fast path and the durable path without duplicating the
money-mutating logic in two call sites (the failure mode that duplication invites: the two
paths silently drifting on stock/notification behavior).

**Settlement is a per-shop pluggable strategy** (`SettlementStrategy`, mirroring the existing
pluggable-OTP-provider pattern — [[ADR-0009-pluggable-otp-auth]]): `SINGLE_MERCHANT` is the
default for every shop (`shop.settlement_mode IS NULL` resolves to it, so no migration is
needed for existing rows); `ROUTE_SPLIT` is opt-in per shop once it has a linked Razorpay
account. The strategy only contributes JSON parameters (`transfers[]` on order-create,
`reverse_all` on refund) — `PaymentServiceImpl` remains the sole caller of the gateway. A
`ROUTE_SPLIT` shop with no linked account **rejects checkout outright** rather than silently
falling back to single-merchant settlement, because a silent fallback would misroute that shop's
money without anyone noticing.

**Money-state machine** (order and cart states are separate but move together):

```
cart:    ACTIVE ─checkout→ LOCKED ─confirm→ COMPLETED   |  LOCKED ─cancel/timeout→ ACTIVE
order:   (created) → PENDING_PAYMENT ─confirm→ PLACED → …normal fulfilment
                          └─ cancel/timeout → PAYMENT_FAILED (terminal)
payment: NONE(COD) | CREATED ─capture→ PAID ─(cancel/decline/stock-fail)→ REFUND_PENDING → REFUNDED
                   └──────────────────→ FAILED
```

`payment.failed` from Razorpay is **per-attempt**, not per-order — the Checkout sheet allows
retries while open, so that webhook event is log-only and never transitions the order. An order
only dies via explicit `/payments/cancel` or reconciliation timeout. A `PENDING_PAYMENT` order
can be **resumed** (same `razorpayOrderId`, same idempotency key); a `PAYMENT_FAILED` order is
terminal and requires a fresh checkout with a new idempotency key — retrying with the same key
must never resurrect a dead order.

COD is deliberately left as a **separate, untouched synchronous path** (`POST /api/orders`
unchanged) rather than folded into the two-phase shape — COD has no external gateway call and
no capture-lag, so the phase split would add a lock/unlock cycle and an idempotency-key protocol
for zero benefit. The two payment methods share the order/cart entities and the
`OrderAssembler` validation logic, but not the placement control flow.

Refunds are **persisted (`REFUND_PENDING`) before the gateway call, not after** — a
fire-and-forget refund that fails silently on a gateway 5xx would leave a customer's money
stuck with no record it was ever owed back.

Launch is gated by a single flag, `app.payments.online-enabled` (default `false`) — rollback is
a flag flip with no migration, in the same shape as prior feature-flag launches on this project.

## Consequences

**This makes easy:**
- COD stays byte-identical and zero-regression-risk; online payment is additive.
- A stranded payment (app killed, network dropped, webhook delayed) self-heals via the webhook
  or lazy/hourly reconciliation — no manual ops intervention for the common failure modes.
- Adding a new settlement mode later (e.g. a marketplace-commission Route variant) is a new
  `SettlementStrategy` implementation, not a fork of checkout/confirm.
- Ghost order states (`PENDING_PAYMENT`, `PAYMENT_FAILED`) are excluded from every shop/customer
  read by construction, so an unpaid order never appears as a real order to the shop — except
  the admin-oversight read, which deliberately keeps them visible for reconciliation.

**This makes hard / rules out:**
- Any code path that mutates money/stock outside `confirmPayment` is now a bug by definition —
  the CAS + single-caller shape is the only place PAID transitions are legal. This rules out
  "quick" direct status writes elsewhere (e.g. an admin manually flipping an order to PLACED)
  without going through the same gate.
- A DB transaction can never wrap the Razorpay call; checkout is necessarily multi-transaction
  (validate/lock → external call → persist gateway id, with an explicit compensating rollback on
  gateway failure). This is more moving parts than the COD single-transaction shape, accepted as
  the cost of a gateway boundary.
- Reconciliation is intentionally *not* a tight polling loop — a frequent `@Scheduled` job would
  defeat Neon's autosuspend. This means a genuinely orphaned `PENDING_PAYMENT` order (no user
  traffic to trigger lazy reconcile) can sit unresolved for up to an hour, bounded by the hourly
  sweep, not seconds.
- Route platform commission is out of scope for this decision — a Route-split shop currently
  receives 100% of the transfer; a take-rate is a deliberately deferred follow-up.

## Enforced in

Not enforced in code as of this ADR — status is **plan only**, hardened across architect /
devil's-advocate / api-contracts / market review passes on 2026-07-18. Full phased build order
(backend entities/migrations, `PaymentServiceImpl`, `SettlementStrategy` + resolver, webhook
controller, RN `RazorpayCheckoutSheet`, the full read-audit of ghost-status exclusions, and the
13-scenario failure-matrix test plan) lives at
`Food-Ninja-Frontend/skills/agents/arch-notes/razorpay-payment-FINAL.md`. Related context:
[[ADR-0002-order-orderline-snapshot-pricing-schema]] (order/cart shapes this extends),
[[ADR-0003-order-placement-idempotency]] (idempotency-key precedent this reuses),
[[ADR-0009-pluggable-otp-auth]] (the pluggable-provider pattern settlement strategy mirrors),
[[ADR-0012-captain-ordering-dine-in-pos-kds]] (the separate money path this does not touch).
Memory: `project_razorpay_payment`.

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
