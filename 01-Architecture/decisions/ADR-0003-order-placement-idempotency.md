---
id: ADR-0003
type: decision
status: accepted
apps: ["backend","customer"]
module: "cart"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/controller/OrderController.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/OrderServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/Order.java" }
  - { repo: customer, path: "src/features/orders/hooks/usePlaceOrder.ts" }
  - { repo: customer, path: "src/utils/idempotency.ts" }
verified_against: "backend@ff5ade334891238d16b8010e372fdbbc502c193e customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-05-21
---

# ADR-0003: Order Placement Idempotency (Idempotency-Key Design, Risk 7)

## Context

ARCHITECTURE.md Principle 11 requires idempotency to be designed in when order placement is
built, not retrofitted afterward: "Design this in when orders is built. Retrofitting is a
nightmare."

The `Place Order` action had no debouncing, no loading state, and no idempotency mechanism.
A user double-tapping "Place Order" (or a network layer retrying the POST) would create two
separate orders. On a real delivery platform this means two payments charged, two restaurants
receiving the same order, avoidable customer-support load, and revenue loss on the resulting
refund.

The alternative on the table was to rely on client-side debouncing alone (disable the button
after first tap). That mitigates the common double-tap case but does nothing for a network-level
retry of the same POST, which is the harder case idempotency is actually for.

## Decision

`POST /api/orders` accepts an `Idempotency-Key` header. The frontend generates one UUID per
cart-to-checkout flow and re-uses it across retries of the same order attempt; if the header is
missing, the backend generates one so the endpoint degrades safely rather than rejecting the
request.

- On the backend, the key is stored as a unique column directly on the `Order` row itself
  (`idempotency_key`, unique, non-null) rather than in a separate generic cache table. Before
  doing any cart/pricing/order work, `placeOrder` looks up an existing `Order` by that key; if
  found, it returns the already-placed order instead of creating a new one.
- On the frontend, the key is generated once per screen mount (`usePlaceOrder`) and held in a
  ref so it is stable across re-renders and reused verbatim if the same request is retried.
  The "Place Order" button is also disabled (`submitting` state) from first tap until the
  server responds, covering the common double-tap case client-side in addition to the
  server-side guarantee.

## Consequences

- A double-tap or client retry with the same key is guaranteed to produce exactly one `Order`
  row — the second call is a cheap lookup-and-return, not a re-run of cart validation, pricing,
  or cart-session locking.
- Because the key lives directly on `Order` (unique constraint) rather than a separate
  request/response cache, there is no explicit TTL/expiry window for order placement — a stale
  key simply continues to resolve to the same order for its lifetime. This is a deliberate
  simplification for this endpoint; not a general-purpose HTTP idempotency layer.
- A generic idempotency cache (key + request hash + cached response, with a TTL) exists
  separately in the codebase for other write endpoints (POS ordering) — that pattern is
  reusable for future endpoints but is not what `POST /api/orders` uses today.
- If the frontend ever needs to let a user intentionally place a *new* order after a failed
  attempt without navigating away, it must explicitly mint a new key — reusing the same
  ref-held key would silently return the old (failed-to-complete-client-side) order.

## Enforced in

- `OrderController.java` (backend) — reads the `Idempotency-Key` header on `POST /api/orders`,
  generating one server-side if absent.
- `OrderServiceImpl.java` (backend) — `placeOrder` short-circuits via
  `orderRepository.findByIdempotencyKey` before any cart/pricing/locking work.
- `Order.java` (backend) — `idempotency_key` column, unique + non-null.
- `usePlaceOrder.ts` (customer) — mints one UUID per mount (`useRef`), reuses it on retry, and
  drives the button's `submitting`-disabled state.
- `idempotency.ts` (customer, `src/utils/`) — UUID v4 generator used to create the key.

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
