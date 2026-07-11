---
id: ADR-0001
type: decision
status: accepted
apps: ["backend", "customer"]
module: "architecture"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/Order.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/OrderLine.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/OrderLineAddon.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/controller/OrderController.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/IdempotencyKey.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/IdempotencyService.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/CartService.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/controller/CartController.java" }
  - { repo: customer, path: "app/cart.tsx" }
verified_against: "backend@ff5ade334891238d16b8010e372fdbbc502c193e, customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-05-21
---

# ADR-0001: Pre-Phase-1E Devil's Advocate Risk Review — Verdict & Blocking Punch List

## Context

Phase 1E was about to begin: **Orders** — the Cart → Order flow, Order status transitions,
and delivery provider integration. Before design was finalized, a devil's-advocate pass was
run against the codebase as it stood at the time, specifically to catch irreversible mistakes
(schema decisions, sequencing bugs, coupling violations) before any Phase 1E code was written.

Reviewed inputs: `ARCHITECTURE.md` (all 20 principles), the backend `CLAUDE.md`, `Modules/menu.md`,
`project_pending_flags.md`, `entity/DeliveryConfig.java`, `entity/Restaurant.java`, `entity/Shop.java`,
`src/store/useCartStore.ts`, `src/store/useRestaurantCartStore.ts`, `app/cart.tsx`, and
`agents/context-keeper-brief.md`.

At review time, the codebase had several properties that made Phase 1E dangerous to start
blind: `cart.tsx`'s "Place Order" button was a stub that faked success and cleared the cart
without ever calling a server; delivery fee and a coupon system were computed entirely
client-side; `Restaurant.java` existed as a parallel, unwired entity alongside `Shop.java`
with a read-only `@OneToOne` join; no `Order`/`OrderLine` schema existed yet; and there was
no idempotency design for order placement. Each of these, if Phase 1E were designed or built
around them uncritically, would have produced problems that are expensive or impossible to
retrofit later (a wrong order-snapshot schema in particular, since it would corrupt order
history for every order ever placed).

## Decision

**VERDICT: Proceed with conditions.** Phase 1E could not safely begin in its
then-current state. The review produced a staged, blocking punch list that had to be worked
through before design, before code, and before ship — reproduced here in full because each
item is itself a decision this ADR endorses:

**MUST-DO before Phase 1E design is finalized:**
1. Architectural decision on `Restaurant.java` — wire it up properly or merge its fields into
   `Shop.java`. This determines what the Order entity's shop reference points at (Risk 4).
2. Order entity schema design review (Risk 6) — approved before any code is written.
3. Remove or clearly stub-mark the fake `handlePlaceOrder` in `cart.tsx` (Risk 1).

**MUST-DO before Phase 1E code is written:**
4. Switch to Flyway migrations (C5-e) before creating Order tables.
5. Design `POST /api/cart/validate` as the first Phase 1E backend endpoint (Risk 10).
6. Add ownership enforcement to order status transition endpoints (C5-d).
7. Design `Idempotency-Key` support into `POST /api/orders` from day one (Risk 7).
8. Fix `DeliveryConfig`'s `@OneToOne` coupling before building `DeliveryConfigService` (Risk 9).
9. Delete `useCartStore.ts` after confirming no active imports (Risk 5).

**MUST-DO before Phase 1E ships:**
10. Remove the hardcoded delivery fee — it must come from the backend (Risk 2).
11. Remove or backend-validate the coupon system — a frontend-only coupon cannot ship
    alongside a real payment flow (Risk 3).
12. Fix timezone handling for shop hours (AF3) before the cart validation endpoint is built.

**Top 3 risks, ranked by severity:**

- **Rank 1 — Risk 6 (Order/OrderLine price-snapshot schema).** The one design decision that,
  if wrong, cannot be fixed without a data migration and potentially breaks order history for
  every order ever placed. Had to be designed correctly the first time.
- **Rank 2 — Risk 1 (fake `handlePlaceOrder` stub + wrong sequencing).** The stub cleared the
  cart before server confirmation. Wiring a real API call into it as-is would ship a
  cart-clearing bug that loses orders on network failure.
- **Rank 3 — Risk 4 (`Restaurant.java` architectural ambiguity).** Left undecided, Phase 1E's
  Order entity would reference the wrong thing and the system would accumulate technical debt
  poisoning rating, `totalOrders`, and restaurant-level analytics indefinitely.

## Consequences

The punch list above is the direct consequence of this review: it gated what Phase 1E was
allowed to build, and in what order. The full risk register and forward-looking assumption
flags that produced it are preserved below, since they document *why* each punch-list item
was mandatory rather than optional polish.

### Risk register

**Risk 1 — `handlePlaceOrder` in `cart.tsx` was a fake stub pretending to place orders (CRITICAL).**
It showed a hardcoded "Order Placed!" alert with a static ETA, called `clearCart()`, and
routed to the orders tab — no API call at all, and the cart was cleared *before* any server
confirmation could exist. A developer could mistake this for "mostly done" and wire a real
`POST /api/orders` call into it without addressing the sequencing bug underneath.
*Mitigation:* mark it with an explicit stub TODO immediately; redesign the checkout flow from
scratch as validate → POST order → receive order ID → navigate to tracking, with the cart
cleared only after server acceptance. *Status at review time:* OPEN — blocked Phase 1E as the
very first task.

**Risk 2 — Delivery fee was hardcoded in the frontend (`DELIVERY_FEE = 30`), violating
Principle 17 (HIGH).** The real fee depends on the user's distance from the shop (Haversine)
and the shop's `DeliveryConfig` (base fee + per-km fee + free-delivery threshold). Principle 17
is explicit that fee decisions are a backend concern; the frontend only renders what the
backend returns. Showing a wrong total at cart time and a different total at order placement
is a broken trust problem. *Mitigation:* Phase 1E must ship a backend cart-validation call
(Principle 6) that returns the computed delivery fee; the frontend must not calculate or
display a fee itself until validation returns one. *Status at review time:* OPEN — blocked
Phase 1E from being safe to ship; `DeliveryConfig` existed but no service used it yet.

**Risk 3 — The coupon system in `cart.tsx` was entirely client-side with hardcoded codes
(HIGH).** Codes and discount amounts lived in the JS bundle and were even hinted to users in
the UI copy. None of it was server-validated: no expiry, no per-user limit, no single-use
enforcement, and the discount subtracted on the frontend would never be known to a real
`POST /api/orders` call — the backend would charge the full price while the cart screen showed
a discounted one. *Mitigation:* remove the coupon UI before Phase 1E ships, or treat it as a
display-only placeholder explicitly excluded from any total sent to the backend; a real coupon
system needs its own backend service and was out of scope for Phase 1E. *Status at review
time:* OPEN — blocked Phase 1E; the coupon must not interact with the real order total.

**Risk 4 — `Restaurant.java` was a parallel entity to `Shop.java` with no controller, no
service, and a dangerous read-only `@OneToOne` join (HIGH).** It carried fields
(`rating`, `totalOrders`, `fssaiLicense`, `gstNumber`, `avgPrepTime`) that are genuinely
Phase 1E-relevant, but with no service layer to reach them, and
`@JoinColumn(insertable = false, updatable = false)` meant it could never be saved with a shop
reference via JPA at all. Phase 1E's Order entity would otherwise face a fork: reference `Shop`
(used everywhere else, but `totalOrders`/`rating` never update) or reference the untested,
unwired `Restaurant` (whose live JPA join violates the cross-domain coupling guard).
*Mitigation:* decide before Phase 1E design begins whether `Restaurant.java` gets wired up
properly or its fields move into `Shop.java`; replace the `@OneToOne` join with a plain
`UUID shopId` column regardless. *Status at review time:* OPEN — architectural decision
required before Phase 1E design was finalized.

**Risk 5 — `useCartStore.ts` (C1) was confirmed unused by `cart.tsx`, but risked ghost imports
elsewhere (MEDIUM).** It still existed and exported a store using `item.price * quantity` — a
field that does not exist on items per Schema Rule S1 — plus `minimumOrder`/`maximumOrder`
fields absent from `useRestaurantCartStore`'s cart item shape. A developer building a Phase 1E
checkout/orders screen from scratch could discover it via autocomplete and silently place
₹0 orders or send wrong data. *Mitigation:* delete `useCartStore.ts` before Phase 1E begins,
after scanning for and migrating any active usages to `useRestaurantCartStore`. *Status at
review time:* OPEN — recommended as a pre-Phase-1E cleanup task.

**Risk 6 — No `Order`/`OrderLine` schema existed yet, and the snapshot model had to be
designed before any code was written (HIGH).** Principle 18 requires the Order entity to
snapshot item name/image/description, exact pricing (selling price, MRP, discount applied),
every selected addon's name and price, and the shop reference — all *at the time of order*,
not by reference to current, mutable rows. Because price on this platform comes entirely from
addon options (Schema Rule S1 — no `price` on `items`), an order line's snapshot has to
preserve each selected addon's id/name/group alongside the selling price, MRP, and discount
percent that applied at order time, not a live FK back to `addons.price` (which a shop can
change at any time). `useRestaurantCartStore` already snapshotted these correctly on the cart
side; the risk was the backend `Order` entity failing to mirror that semantics, which would
make reorder/history reconstruct wrong prices months later. *Mitigation:* review the Order
entity design before implementation, with non-negotiable snapshot columns (per Principle 18
and Schema Rule S15) covering: an `orders` table with status, grand/delivery/platform fee
snapshots, a delivery-address snapshot, and a unique idempotency key; an `order_lines` table
with item name/image/quantity/unit price snapshots plus the item FK for reorder resolution;
and an `order_line_addons` table with addon/group name snapshots and selling-price/MRP/discount
snapshots. *Status at review time:* OPEN — no schema designed yet; the most consequential
design decision of Phase 1E.

**Risk 7 — No idempotency-key design existed for `POST /api/orders` (Principle 11) (HIGH).**
Principle 11 states this must be designed in when orders is built, since retrofitting it is a
nightmare. The "Place Order" button had no debouncing, no loading state, and no idempotency
mechanism — a double-tap or a network retry would create two separate orders, meaning two
payments charged, two shops receiving the same order, and a support/refund cost.
*Mitigation:* ship `Idempotency-Key` header support on `POST /api/orders` from day one — the
frontend generates a UUID on entering cart and re-uses it on retry; the backend stores the key
with a time window and returns the cached order on a duplicate; the Place Order button is also
disabled after first tap until the server responds. *Status at review time:* OPEN — a
design-in requirement, not something safe to retrofit.

**Risk 8 — C5: which hardening items from Principle 15 actually block Phase 1E from being
safe to build (MEDIUM)?** Assessed all six open hardening items individually:
(a) OTP hardcoded to "1234" does not block Phase 1E development — orders don't go through OTP
— but blocks production launch, since anyone can log in as anyone with phone + "1234" and place
orders under that identity. (b) DB credentials in `application.properties` do not block
development but block production launch, and the risk category rises because orders now carry
PII (delivery address, user data). (c) A default-value JWT secret does not block development
but blocks production launch — a known secret lets anyone forge a token and place orders as
any user. (d) No shop-ownership enforcement **partially blocks Phase 1E**: order-status
transitions (ACCEPTED, PREPARING, READY) must only be callable by the shop that received the
order, and without enforcement any authenticated user could advance any order's status — this
must land in the `OrderController` status-update endpoints. (e) `ddl-auto=update` **blocks
Phase 1E indirectly**: it adds new tables (`orders`, `order_lines`, `order_line_addons`) with
no migration history and no rollback path if the entity design changes mid-development —
recommend switching to Flyway before Phase 1E creates any new tables. (f) No rate limiting on
`/auth/send-otp` does not block Phase 1E. *Verdict on C5:* items (d) and (e) were the ones that
directly blocked Phase 1E from being safe to build.

**Risk 9 — `DeliveryConfig`'s `@OneToOne` JPA join created an N+1 risk in Order queries
(MEDIUM).** It used a live `@OneToOne @JoinColumn` to `Shop`, which is eagerly loaded by
default for `@OneToOne` in JPA. Once Phase 1E built `GET /api/orders/{id}` and
`GET /api/orders/active` including delivery-fee info, every order query would trigger an
additional `delivery_config` SELECT — and with active-order polling every 10–15s
(Principle 12), that becomes a steady N+1 on every poll cycle. The entity also violated the
cross-domain coupling guard (entities referencing each other via JPA joins creates tight
DB-layer coupling). *Mitigation:* replace the `@OneToOne` join with a plain `UUID shopId`
column, matching every other entity's pattern, and load `DeliveryConfig` explicitly by
`shopId` rather than relying on Hibernate to auto-join it. *Status at review time:* OPEN
(flagged as C4 in the Context Keeper brief) — should be resolved before Phase 1E service code
references `DeliveryConfig`.

**Risk 10 — `POST /api/cart/validate` did not exist; Principle 6 was unmet (MEDIUM).**
Principle 6 mandates a cart re-validation call on checkout entry returning per-item
availability, current prices, shop-open status, and deliverability. Without it, a shop could
be closed by the time an order was placed, an item could have gone out of stock between
add-to-cart and place-order, or a price could have changed — and these failures would surface
as cryptic order errors or, worse, accepted orders the kitchen can't fulfil. `handlePlaceOrder`
at review time had no validation call at all. *Mitigation:* build `POST /api/cart/validate` as
the first Phase 1E backend endpoint, before `POST /api/orders`; checkout flow is validate →
show diff to user → confirm → place order — skipping validation is not an option per
Principle 6. *Status at review time:* OPEN — a prerequisite for Phase 1E order placement.

**Risk 11 — `restaurant.tsx` navigation passing objects (C3) would break reorder navigation
back to the restaurant screen (LOW–MEDIUM).** The `/restaurant` route accepted object params
rather than IDs (a Principle 4 violation flagged earlier by Context Keeper). A Phase 1E
"Order Placed" → "Track Order" → "Reorder" flow needs to navigate back to the restaurant
screen for the correct shop; with the object-passing anti-pattern still in place, that would
require re-serializing and passing the full restaurant object again — fragile, and breaks on
large objects. *Mitigation:* fix C3 (navigate via `useSelectedRestaurantStore` + ID-only
params) before Phase 1E builds reorder flows. *Status at review time:* OPEN — low priority for
basic order placement, but a blocker for reorder specifically.

### Assumption flags (looked fine at review time, flagged to break later or at scale)

- **AF1 — `currentShopId` in `useRestaurantCartStore` was the only cross-shop enforcement.**
  The "one shop at a time" rule was enforced purely by comparing `currentShopId` client-side,
  with no server-side guard. If the store were ever cleared (app restart, logout) and the user
  navigated to checkout with a partially reconstructed cart, nothing would catch it. When a
  second (grocery) vertical arrives, this enforcement must move into a shared cart domain layer
  (C6) — otherwise two vertical-specific cart rules would collide in the same store.
- **AF2 — `RestaurantCartItem.imageUrl` was `string | null` with no S3-key enforcement.** Cart
  items snapshotted the full image URL at add-time rather than an S3 key. If the underlying
  URL later changed (bucket migration, CDN change), the cart item would hold a stale URL not
  re-validated. For order history (Principle 18), `order_line_addons` should store the S3 key
  and resolve to a full URL at display time, matching Schema Rule S7 — not snapshot full URLs.
- **AF3 — `Shop.openingTime`/`closingTime` were `LocalTime` with no timezone.** A cart
  validation "is the shop open?" check comparing against server system time (likely UTC) would
  silently mis-evaluate IST shop hours — a shop open at 10:00 IST (04:30 UTC) could appear
  closed. This is a silent correctness bug that surfaces only when shop hours straddle a
  timezone boundary, which every Indian shop does against a UTC server.
- **AF4 — `Restaurant.totalOrders` would never update unless a service was explicitly wired to
  it.** Left unaddressed, it would stay at its initialized 0 forever, which matters once
  restaurant ranking evolves from `sort_score` to a popularity signal based on order volume —
  the data would be wrong for every restaurant that processed orders before the incrementing
  logic was added.
- **AF5 — The coupon system had no backend model at all.** When a real coupon system is built
  later, the Order entity will need `coupon_code` and `coupon_discount_snapshot` columns to
  record what discount actually applied. If the initial `orders` table shipped without them,
  adding them later would require a migration — they should be nullable columns from the start
  to avoid future schema debt.
- **AF6 — `ddl-auto=update` meant no migration history for Phase 1E's new tables.** If the
  Order entity changed shape during development, Hibernate's auto-update cannot handle column
  renames or type changes — it silently leaves old columns in place, so by the time Phase 1E
  finished, the `orders` table in Neon could accumulate ghost columns from earlier iterations.
  A Flyway migration-first approach was called out as essential before creating any new tables.

## Enforced in

Backend, matching the Risk 6 snapshot-schema decision and the Risk 4 resolution (shop
referenced by a plain UUID, not a live JPA join to `Restaurant`):
- `entity/Order.java` — `shopId`/`shopName` snapshot fields (not a `Restaurant` join), plus
  `idempotencyKey` and the fee/total snapshot columns this risk register called for.
- `entity/OrderLine.java` — `itemName`/`itemImageUrl`/`lineTotalSnapshot` captured at order
  time rather than joined live from the menu item.
- `entity/OrderLineAddon.java` — `addonName`/`groupName`/`mrp`/`sellingPrice`/`discountPercent`
  snapshot columns, matching the non-negotiable schema this ADR mandated in Risk 6.

Backend, matching the Risk 7 idempotency decision:
- `controller/OrderController.java` — accepts an `Idempotency-Key` request header on order
  placement (generating one server-side when the client omits it).
- `entity/IdempotencyKey.java`, `service/IdempotencyService.java` — the persisted key +
  cached-response mechanism the mitigation called for.

Backend, matching the Risk 10 cart-validation decision:
- `service/CartService.java`, `controller/CartController.java` — a cart re-validation/
  accept-changes flow gates checkout on server-side availability rather than the frontend
  proceeding straight to order placement unchecked.

Frontend, matching the Risk 1 sequencing decision:
- `app/cart.tsx` — the checkout entry point that replaced the original fake
  `handlePlaceOrder` stub described in Risk 1.

Not yet enforced as of this review's `verified_against` commits — carried forward as open
follow-ups rather than claimed as resolved here: `entity/DeliveryConfig.java` still uses a
live `@OneToOne` join to `Shop` (Risk 9), and `spring.jpa.hibernate.ddl-auto=update` is still
the active DDL strategy with no Flyway migration history (C5-e / AF6).

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
