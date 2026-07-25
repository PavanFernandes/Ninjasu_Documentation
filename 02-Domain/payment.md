---
id: ""
type: domain
status: active
apps: [backend, customer]
module: "payment"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/PaymentServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/controller/PaymentController.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/OrderAssembler.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/SettlementStrategy.java" }
  - { repo: customer, path: "src/features/payments/services/payments.service.ts" }
verified_against: "PLAN — not yet built; verified_against pending first implementation commit"
updated: 2026-07-18
---

# Payment

Source of truth for online (prepaid) payment behaviour. Both frontend and backend must agree
on these rules. If a rule changes, update this file first, then both sides.

> **Status note:** this doc describes the locked design in
> `Food-Ninja-Frontend/skills/agents/arch-notes/razorpay-payment-FINAL.md`. Nothing is built yet.
> Once Phase 1–6 land, re-verify every rule against the actual code and update `verified_against`.

## Scope

Online prepaid payment for the **customer DELIVERY flow only**
(`orderType=DELIVERY`, `orderSource=CUSTOMER`).

- **KOT / dine-in / takeaway are explicitly excluded.** Those settle via
  `table_checks.payment_mode` at the counter — see
  [ADR-0012](../01-Architecture/decisions/ADR-0012-captain-ordering-dine-in-pos-kds.md).
  The two money paths never overlap: Captain Ordering never touches `Order.paymentStatus`,
  and this module never touches `table_checks`.
- **COD and ONLINE coexist.** COD keeps today's synchronous `POST /api/orders` path completely
  untouched — this module adds a new, parallel checkout path, not a replacement.
- Gateway is **Razorpay**, client SDK is **Web Checkout inside `react-native-webview`**
  (not `react-native-razorpay` — no official Expo config plugin).
- Gateway fee (~2%+GST) is absorbed by the platform; no separate bill line for it.
- Entire feature is **flag-gated**: `app.payments.online-enabled` (default `false`). Rollback
  is a flag flip, no migration required.

## Rules

### State machines — strictly enforced

Three state machines move together but are **not the same state**: the cart session, the
order, and the payment itself.

```
cart:    ACTIVE ──checkout──► LOCKED ──confirm──► COMPLETED
                    LOCKED ──cancel/timeout──► ACTIVE

order:   (created) ──► PENDING_PAYMENT ──confirm──► PLACED ──► …normal fulfilment
                              └──cancel/timeout──► PAYMENT_FAILED   (terminal)

payment: NONE (COD)
         CREATED ──capture──► PAID ──cancel/decline/stock-fail──► REFUND_PENDING ──► REFUNDED
                 └──────────────────────────────────────────► FAILED
```

- `PAYMENT_FAILED` and `REFUNDED` are terminal for their respective machines. A `PAYMENT_FAILED`
  order never resumes — the customer must start a fresh checkout with a new idempotency key
  (see condition 4 below).
- `PENDING_PAYMENT` orders are **shop-invisible** — excluded from every seller/customer read
  until they resolve to `PLACED` or `PAYMENT_FAILED` (see "Ghost-status audit" below).
- Stock decrements at **confirm**, not at checkout. An abandoned payment sheet holds no
  inventory — this mirrors the cart's own "never commit early" philosophy.

### Two-phase checkout, one idempotent confirm

```
PHASE 1: POST /api/payments/checkout          PHASE 2: confirm — two independent triggers
  validate cart+address (shared               (a) POST /api/payments/verify   ← client, fast UX
  OrderAssembler, same logic COD uses)         (b) POST /api/webhooks/razorpay ← authoritative
  lock cart ACTIVE→LOCKED                            │
  create Order status=PENDING_PAYMENT                ├─ BOTH call the ONE confirmPayment():
  create Razorpay order (amount server-              │    CAS payment_status CREATED→PAID
    computed, receipt=orderId, settlement            │    order→PLACED, stock decrement,
    plugin params)                                   │    cart→COMPLETED
  return {orderId, razorpayOrderId, keyId,           │    publish OrderPlacedEvent
          amount(paise), currency, prefill}          │    (AFTER_COMMIT, rings shop)
                                                       └─ stock-fail after capture →
                                                          CANCELLED + REFUND_PENDING
```

`OrderAssembler` is the shared extraction of `OrderServiceImpl.placeOrder`'s validation/pricing
steps (load session, empty check, shop load, haversine, totals, delivery fee, build lines from
cart items). COD and online checkout call the **same** assembler — business logic never lives
in two places. `OrderServiceImpl` delegates to it; COD's public behaviour stays byte-identical.

### The 7 load-bearing conditions

These came out of the devil's-advocate gate and are all mandatory — skipping any one reopens a
money-correctness or double-charge bug.

1. **ONE `confirmPayment` method**, CAS-guarded on `CREATED→PAID`
   (`UPDATE ... WHERE payment_status='CREATED'`, update-count checked). Both the client
   `/verify` call and the `/webhooks/razorpay` callback call this single method — whichever
   wins the race does the work, the other is a no-op that just reloads and returns.
2. **Refunds are durable, never fire-and-forget.** `REFUND_PENDING` is persisted first, the
   gateway refund call happens second, and a reconciliation job retries on gateway failure.
   Route-split shops set `reverse_all=1` on refund so the linked account is clawed back too.
3. **Every order read excludes ghost statuses.** `PENDING_PAYMENT` and `PAYMENT_FAILED` must
   never appear in a customer's order history, a seller's order list, KDS, or POS queries —
   see the audit table below for every call site.
4. **A retry never resurrects a terminal order.** Same idempotency key while
   `PENDING_PAYMENT` → resume the same `razorpayOrderId` (return the cached `CheckoutResponse`).
   Same key against a `PAYMENT_FAILED` order → `400`; the client must rotate to a fresh
   idempotency key and open a brand-new checkout.
5. **Webhook signature is verified on the raw body, before parsing.** HMAC needs the exact
   bytes Razorpay sent — never a re-serialized DTO. Dedupe on `x-razorpay-event-id`
   (`PaymentWebhookEvent.existsByEventId`) so a redelivered webhook is a 200 no-op.
6. **Amount is always server-computed**, bound to the Razorpay order via signature
   verification. The client never sends an authoritative amount, exactly like the cart's
   "never trust frontend prices" rule.
7. **Flag-gated launch.** `app.payments.online-enabled` defaults `false`. Checkout 400s while
   off; COD is completely unaffected either way.

#### Webhook semantics — encode exactly this

`payment.failed` is per-**attempt**, not per-order — a single Razorpay order allows multiple
payment attempts while the checkout sheet stays open. `payment.failed` is therefore **log-only**
and must NOT transition the order. An order only dies via an explicit `POST /api/payments/cancel`
or the reconciliation timeout. The only events that call `confirmPayment` are
`payment.captured` (or `order.paid`). `refund.processed` moves `REFUND_PENDING → REFUNDED` and
sets `refundedOn`.

### Settlement — pluggable per-shop strategy

Mirrors the pluggable OTP-provider pattern (see
[`project_otp_pluggable`](../../CLAUDE.md) memory / ADR-0009): a shop-level mode selects an
injectable strategy, the service layer never branches on mode directly.

```java
public interface SettlementStrategy {
    SettlementMode mode();
    void validateShop(Shop shop);                                          // ROUTE: linked account present, else BusinessRuleViolation
    void configureOrderCreate(JSONObject orderReq, Order order, Shop shop); // ROUTE: transfers[]{account, amount, currency, on_hold:0}
    void configureRefund(JSONObject refundReq, Order order, Shop shop);     // ROUTE: reverse_all=1
}
```

- `SettlementMode`: `SINGLE_MERCHANT` (default) or `ROUTE_SPLIT` (Razorpay Route linked
  account).
- `Shop.settlement_mode` is `NULL` on existing rows ⇒ the resolver defaults to
  `SINGLE_MERCHANT`. `Shop.razorpay_linked_account_id` is `NULL` ⟺ not a Route shop.
- A `ROUTE_SPLIT` shop with no linked account **rejects checkout with 400** — never a silent
  fallback to single-merchant settlement.
- Strategies only *contribute JSON params* onto requests `PaymentServiceImpl` builds.
  `PaymentServiceImpl` remains the **sole** caller of the Razorpay SDK — settlement strategies
  never call the gateway themselves.
- Platform commission on Route splits is a deferred TODO — the shop currently gets 100% of a
  split transfer.

### Idempotency and resumability

- `POST /api/payments/checkout` accepts `Idempotency-Key` (server-generates if absent, same
  convention as `POST /api/orders`).
- Same key + an order still `PENDING_PAYMENT` → return the same `CheckoutResponse`
  (RESUME — condition 4). This is what lets a user reopen a killed checkout sheet without
  double-creating a Razorpay order.
- Same key + an order already `PLACED` → `400 "already placed"`.
- Same key + an order `PAYMENT_FAILED` → `400 "start a new checkout"` — the frontend must
  rotate the idempotency key as **state**, not a one-per-mount `useRef`.

### Ghost-status audit — every read site must exclude PENDING_PAYMENT / PAYMENT_FAILED

| Site | Rule |
|---|---|
| `getActiveOrder` (`findFirstByUserIdAndStatusNotIn`) | add both statuses to the excluded list |
| `getOrderHistory` (customer) | new `...AndStatusNotIn` query variant, backed by a shared `GHOST_STATUSES` constant |
| Seller list/detail (`findByShopIdAndOrderType…`) | bake `status NOT IN (ghosts)` into both variants |
| `findForAdminOversight` | **stays visible** — admins are the reconcilers, this is deliberate |
| `cancelOrder` `CANCELLABLE_STATUSES` | already excludes ghosts naturally — verify only, don't change |
| KDS / POS queries | `DELIVERY` orders never enter Captain Ordering — verify only |

### Reconciliation — Neon-aware

A tight `@Scheduled` poll defeats Neon's autosuspend (the Hikari pool config exists precisely
to let the DB sleep between requests), so reconciliation is **lazy-first, scheduled-second**:

- Inline check inside `getOrder` / `getActiveOrder`: a `PENDING_PAYMENT` order older than
  ~15 minutes triggers a gateway lookup (`orders.fetchPayments`) — captured → confirm;
  no capture after 30 minutes → `PAYMENT_FAILED` + cart unlocked. Driven by user traffic, so
  the DB is already awake.
- One **hourly** `@Scheduled` sweep (gated on `app.payments.online-enabled`) catches stragglers
  and retries `REFUND_PENDING` rows that failed their initial gateway call.

### Endpoints — At a Glance

All endpoints require JWT except the webhook, which is public but HMAC-verified.
User identity comes from the security context, never the request body.

| Method | Path                          | Purpose                                                   |
|--------|-------------------------------|-------------------------------------------------------------|
| POST   | `/api/payments/checkout`      | Validate cart+address, lock cart, create `PENDING_PAYMENT` order + Razorpay order |
| POST   | `/api/payments/verify`        | Client-side confirm trigger — signature-verified, calls `confirmPayment` |
| POST   | `/api/payments/cancel`        | Sheet dismissed / abandoned — `CREATED→FAILED`, cart unlocked (no-op if already PAID) |
| POST   | `/api/webhooks/razorpay`      | Gateway-side confirm trigger — authoritative, HMAC-verified, event-id deduped |

#### Status code conventions

| Code | When |
|------|------|
| 200  | Success (webhook also returns 200 on log-only / unknown events — a non-2xx makes Razorpay retry forever) |
| 400  | Flag off, validation failure, tampered/missing signature, idempotency-key reused against a terminal order, ROUTE_SPLIT shop missing linked account |
| 404  | `orderId` not found, or not owned by this user (ownership check on `/verify` and `/cancel`) |

### What This Module Does NOT Own

- Order placement mechanics for COD — untouched, lives entirely in `OrderServiceImpl.placeOrder`.
- KOT / dine-in / takeaway settlement — owned by Captain Ordering (ADR-0012).
- Coupons, taxes, delivery-fee computation — computed by `OrderAssembler`, shared with COD,
  not re-derived here.
- Cart mutation rules (snapshot pricing, `cart_key`, quantity caps) — see [cart.md](cart.md).
  This module only calls the cart's lock/unlock transitions; it does not touch cart line
  contents.
- Shop settlement onboarding UX (linked-account setup screen) — separate ops-facing slice.

## Related decisions

- [ADR-0012](../01-Architecture/decisions/ADR-0012-captain-ordering-dine-in-pos-kds.md) — the
  dine-in/KOT payment path (`table_checks.payment_mode`) this module deliberately excludes.
- [ADR-0009](../01-Architecture/decisions/ADR-0009-pluggable-otp-auth.md) — the pluggable
  provider pattern the settlement-strategy design mirrors.
- **New ADR pending** (tracked as the sibling `p6:adr` task, not yet committed at the time of
  writing — filename unconfirmed, likely `ADR-00XX-razorpay-online-payment-two-phase-checkout`
  or similar): covers the two-phase checkout / single-`confirmPayment` design and the
  settlement-strategy plugin. Link it here once it lands.

## Where it's enforced

- Backend: `PaymentServiceImpl` (checkout orchestration across the 3-transaction boundary
  around the Razorpay gateway call, `confirmPayment`, refund initiation), `PaymentController`
  (`/api/payments/*` + `/api/webhooks/razorpay`, raw-body webhook handling), `OrderAssembler`
  (shared cart→order validation/pricing extracted so COD and online checkout never diverge),
  `SettlementStrategy` + its `SINGLE_MERCHANT` / `ROUTE_SPLIT` implementations + the resolver
  that picks between them per shop.
- Frontend: `src/features/payments/` — `services/payments.service.ts` (`checkout`,
  `verifyPayment`, `cancelPayment` via `fetchFn`), `components/RazorpayCheckoutSheet.tsx`
  (full-screen WebView hosting Razorpay's Web Checkout, bridges `handler`/`modal.ondismiss`
  back via `postMessage`, routes `upi://`/`intent://` through `Linking.openURL` for app-to-app
  UPI), `hooks/useOnlinePayment.ts` (orchestrates checkout → sheet → verify/cancel).

### Frontend behaviour notes

- `usePlaceOrder` branches on the selected payment method: COD stays on the existing
  synchronous path; ONLINE routes through `useOnlinePayment`.
- On successful verify, reload the cart (it is now `COMPLETED`, a fresh session will lazily
  create on the next add) and navigate to the order detail screen.
- On sheet dismiss, call `/api/payments/cancel` and stay on the cart screen — the cart is
  unlocked (`LOCKED → ACTIVE`) and items remain untouched.
- Idempotency key is **rotatable state**, not a one-per-mount ref — regenerate it after any
  terminal failure so a retry always opens a fresh checkout instead of hitting condition 4's
  `400`.
- Gate the "Pay Online" option's visibility on `APP_CONFIG.PAYMENTS_ONLINE`
  (`EXPO_PUBLIC_PAYMENTS_ONLINE`), but never rely on it alone — the backend flag is the actual
  authority and still 400s if somehow reached with it off.
- `OrderStatus` gains `PENDING_PAYMENT | PAYMENT_FAILED` — audit every exhaustive
  `Record<OrderStatus, …>` map (`OrderStatusStepper.tsx`, `OrderTrackingScreen.tsx`,
  `ShopOrdersScreen.tsx` chips, orders-tab list) so these two new statuses render something
  sane rather than falling through undefined.
</content>
