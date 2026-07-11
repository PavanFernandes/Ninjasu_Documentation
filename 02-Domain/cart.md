---
id: ""
type: domain
status: active
apps: [backend, customer]
module: "cart"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/util/CartKeyService.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/CartServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/CartSessionServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/util/PriceCalculator.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/IdempotencyService.java" }
  - { repo: customer, path: "src/store/useCartStore.ts" }
verified_against: "backend@ff5ade334891238d16b8010e372fdbbc502c193e customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-07-11
---

# Cart

Source of truth for cart behaviour. Both frontend and backend must agree on these rules.
If a rule changes, update this file first, then both sides.

The cart is the user's mutable pre-order workspace. Orders are a separate, immutable concept.
Nothing in this doc describes order placement.

## Rules

### Cart Model — One Active Cart Per Vertical

Food Ninja is multi-vertical. We support three verticals (cart_types):

| cart_type | Shop kind        |
|-----------|------------------|
| `FOOD`    | Restaurants      |
| `GROCERY` | Zepto-style      |
| `PRODUCT` | Ecommerce        |

Rules:

- A user may have **at most one ACTIVE cart per `cart_type`**.
- A user **can** have parallel carts across different `cart_type`s simultaneously
  (e.g. 1 FOOD cart + 1 GROCERY cart at the same time — no conflict).
- Within a single `cart_type`, only **one shop at a time** (Swiggy/Zepto rule).
- `cart_type` is **permanent** for a session. It is set at session creation from
  `shop.vertical` and can never change.
- If `shop.vertical` is not yet implemented, default `cart_type` to `FOOD` with
  a `TODO` marker in code.

### Session Lifecycle

#### Status machine — strictly enforced

```
ACTIVE ──► LOCKED       (payment starts)
LOCKED ──► ACTIVE       (payment failed, or partial checkout leftover items remain)
LOCKED ──► COMPLETED    (payment succeeded, all items checked out)
ACTIVE ──► ABANDONED    (user cleared cart, or resolved a shop conflict)
```

- `COMPLETED` and `ABANDONED` are **terminal**. Once there, the session is dead.
- Never transition backwards (no `COMPLETED → ACTIVE`).
- `LOCKED` rejects **all** mutations with `409 SESSION_LOCKED` (intentionally NOT
  `423` — 423 is uncommon, may be mishandled by proxies/clients).
- `ABANDONED` sessions **keep their `cart_items` and `cart_item_addons` rows**
  for analytics. Reads always filter by `status = ACTIVE`, so kept rows do not
  pollute any user-facing query. This applies to BOTH `DELETE /api/cart/items/{id}`
  (when last item is removed) and `DELETE /api/cart?type=FOOD` (clear all).

#### Lazy creation

- A `cart_session` is **never** created on app open, restaurant browse, or store view.
- It is created **only on the first successful `POST /api/cart/items`**.
- Subsequent adds reuse the existing session if it matches the `cart_type` and shop.

#### Same-cart_type shop conflict

If a user has an ACTIVE FOOD cart from Shop A and tries to add an item from
FOOD Shop B, the backend returns **409 DIFFERENT_SHOP_CART_EXISTS** with conflict
details (existing shop name + new shop name). The frontend shows the
*"Clear cart to order from X?"* dialog. On confirm:

1. Frontend calls `DELETE /api/cart?type=FOOD` → old session is `ABANDONED`
   (rows kept).
2. Frontend re-issues the original `POST /api/cart/items` → new session is created.

A conflict across different `cart_type`s (FOOD vs GROCERY) is **not** a conflict —
the new session is created alongside the existing one.

### Pricing & Identity — Snapshot at Add, Validate at Read

This is the most important rule in the cart.

#### Snapshot at add time

When an item is added, the backend snapshots **both pricing and identity** so the
cart shows the customer exactly what they saw at the moment of adding:

**On `cart_items`:**
- `item_name` — display name at add time
- `item_image_url` — image URL at add time

**On `cart_item_addons` (per selected addon):**
- `addon_name`, `group_name`
- `mrp` — list price at add time
- `selling_price` — effective price after applicable discounts at add time
- `discount_percent` — discount applied at add time

The snapshot is the contract for what the customer expects to see and pay.
The single source of truth for price computation is `PriceCalculator` (backend,
3-arg overload). Frontend mirrors this for display but the **backend always
recomputes from DB on every add** — frontend prices in requests are display
hints only and are ignored by the server.

> **Why snapshot the item name and image too?** If a restaurant renames "Classic
> Burger" to "Veg Burger" mid-session, or swaps the photo, the cart should still
> show what the customer added until they explicitly accept the change. This
> also future-proofs the cart→order copy in the order module — the order's
> immutable line items become a direct snapshot of the cart's snapshot (see
> [ADR-0002](../01-Architecture/decisions/ADR-0002-order-orderline-snapshot-pricing-schema.md)).

#### Validate on every read

`GET /api/cart` must compare snapshot vs **live** DB state and tag each cart
item with one of:

| validation       | Meaning                                              |
|------------------|------------------------------------------------------|
| `OK`             | Snapshot still matches live state                    |
| `PRICE_CHANGED`  | Live addon price differs from snapshot               |
| `UNAVAILABLE`    | Menu item is no longer available or active           |
| `ADDON_REMOVED`  | A snapshotted addon no longer exists on the menu     |
| `NAME_CHANGED`   | Live `item_name` or `item_image_url` differs         |

- Backend **does not** auto-update snapshots on read.
- Customer must explicitly accept changes via `PUT /api/cart/accept-changes`.
- Cart-level `hasChanges` flag = true if any item has validation ≠ `OK`.

#### Accepting changes

`PUT /api/cart/accept-changes?type=FOOD`:

- `PRICE_CHANGED` → update `cart_item_addons` snapshots to current values.
- `NAME_CHANGED`  → update `cart_items.item_name`, `cart_items.item_image_url`.
- `UNAVAILABLE` or `ADDON_REMOVED` → delete the cart item.
- Returns the refreshed `CartResponse` with `hasChanges = false`.

#### Never trust frontend prices

At every server boundary (add, accept-changes, future order placement), the
backend recomputes prices from the DB. The frontend may *display* its computed
price but never *authoritatively send* one. Frontend prices are not part of any
request body that the server reads for computation.

#### Validation cost — known and accepted

For a cart with N items and M addons each, `GET /api/cart` is N×M validation
operations. **Acceptable at current scale.** Future optimizations (not yet built):

- Batch fetch all referenced addon IDs in one query.
- Cache item/addon availability for a short TTL (e.g. 60s).
- On frontend, only call `GET /api/cart` when the user opens the cart screen —
  not on every CartBar refresh.

### Cart Lines — `cart_key` (locked formula)

A single menu item can appear multiple times with **different addon selections**
(e.g. one "Large + Extra Cheese" and one "Medium + No Cheese" of the same burger).
Each distinct selection is its own cart line.

#### Locked formula — identical on frontend and backend

```
cart_key = sha256(
  menuItemId + "|" + addonIds.sortedLexicographic().join(",")
).hexEncoded().toLowerCase()
```

- `menuItemId` is the UUID string of the menu item.
- `addonIds` are UUID strings of the selected addons.
- Sort lexicographically as **strings** (not by any other field).
- Join with a literal comma, no spaces.
- Output is hex-encoded (64 characters) and lowercase.

#### Backend re-derives, frontend value is ignored

- Frontend may compute `cart_key` locally for UI line tracking, but **does NOT
  send it in any request body**. The server derives it from `menuItemId` + the
  request's `selectedAddons[].addonId` list.
- This prevents a malicious or buggy client from forcing collisions or
  non-collisions with a hand-crafted key.

#### How lines combine or split

- `UNIQUE(cart_session_id, cart_key)` enforces one row per distinct selection.
- Same `cart_key` re-added → quantities combine (UPSERT pattern).
- Different `cart_key` → separate cart lines, even if the underlying item is
  identical.

> ⚠️ If the formula ever changes, change it in frontend AND backend in **one
> coordinated edit**. Mismatched formulas silently split or merge lines.

### Quantity Rules

Every cart line enforces a **min** and a **max** computed by the backend and returned on each `CartItemResponse` as `minQuantity` / `maxQuantity`.

- **`minQuantity`** = `items.min_order_qty` (per-item, default 1, CHECK ≥ 1, never 0).
- **`maxQuantity`** = Phase 1: `app.cart.default-max-line-qty` (10 — since raised to 25, see
  [ADR-0011](../01-Architecture/decisions/ADR-0011-cart-per-line-quantity-cap.md)) for all
  items. Phase 2 (stock-tracked): remaining stock in the open period.
- **Guard is on the COMBINED result**, not the request quantity. `addToCart` combines quantities on an existing line (`CartServiceImpl:addToCart`) — a naive `@Max` on the request DTO does NOT prevent abuse. The service guards `existing + request ≤ maxQuantity` explicitly. Same guard in `updateQuantity`.
- A cart item with quantity 0 is never a valid state.
- `PATCH /api/cart/items/{id}/quantity` with `{ quantity: 0 }` → **400** with message `"Use DELETE to remove items"`. The client translates this to a DELETE.
- Frontend stepper: `+` disabled and greyed at `maxQuantity`; `−` at `minQuantity` becomes a trash/remove action.
- Quantity is absolute, not a delta — the client sends the new total quantity.

### Partial Checkout — `selected_for_checkout`

Every cart item carries a boolean `selected_for_checkout` (default `true`).

- The customer may uncheck individual lines on the cart screen. Unchecked items
  are skipped at order placement.
- After a successful checkout, only the **selected** items are deleted from the
  cart. Unchecked items remain.
- Surviving items have their `selected_for_checkout` reset to `true` so they
  default to checked next time.

The column exists from day one; the UI for it lands in a later slice.

### Validation at Add

Before creating or updating a cart item, the backend enforces:

- `menuItemId` exists and is available (`is_available && is_active`).
- All `addonId`s exist and belong to addon groups linked to this item.
- Every **required ITEM-scoped addon group** is satisfied (at least one option
  per required group — see [menu.md](menu.md) for group rules).
- The item's shop is active and matches the cart's existing shop (if a session
  already exists for this `cart_type`).
- `quantity > 0`.

Validation failures return `400` with a field-level error map matching the
project's standard error envelope.

### Idempotency on Add

`POST /api/cart/items` accepts an optional `Idempotency-Key` header (UUID v4).

- Backend stores `(idempotency_key, user_id, endpoint, request_hash, response)`
  for a 5-minute window.
- Same key + same payload within window → return cached response, do **not**
  process again. This is what prevents network-retry double-adds.
- Same key + **different** payload → `400` with
  `"Idempotency key reused with different payload"`.
- Without the header → endpoint still works, just no replay protection.
- Frontend MUST generate a fresh UUID per add-to-cart click and include it as
  the header.

> The idempotency table grows unbounded without a cleanup job. The plan defers
> the cleanup job to a separate scheduled task. The `IdempotencyService.findCached`
> contract **must** filter by `created_at > NOW() - INTERVAL '5 minutes'` so stale
> rows are logically ignored even before cleanup exists.

### Endpoints — At a Glance

All endpoints require JWT. User identity comes from the security context, never
the request body.

| Method | Path                                              | Purpose                          |
|--------|---------------------------------------------------|----------------------------------|
| POST   | `/api/cart/items`                                 | Add item (creates session if needed) |
| GET    | `/api/cart?type=FOOD`                             | Get one cart by cart_type        |
| GET    | `/api/carts`                                      | List all of user's active carts  |
| PATCH  | `/api/cart/items/{cartItemId}/quantity`           | Update quantity only             |
| PATCH  | `/api/cart/items/{cartItemId}/selection`          | Update `selected_for_checkout`   |
| DELETE | `/api/cart/items/{cartItemId}`                    | Remove one line                  |
| DELETE | `/api/cart?type=FOOD`                             | Clear / abandon a whole cart     |
| PUT    | `/api/cart/accept-changes?type=FOOD`              | Accept price/name/availability   |

#### Status code conventions

| Code | When                                                                  |
|------|-----------------------------------------------------------------------|
| 200  | Success                                                               |
| 400  | Validation failure (bad quantity, required addon missing, idempotency conflict) |
| 404  | `cartItemId` not found, or not owned by this user                     |
| 409  | `DIFFERENT_SHOP_CART_EXISTS` (different shop) or `SESSION_LOCKED`     |

Every mutating endpoint returns the **full refreshed `CartResponse`** so the
client never needs a second round-trip after a write.

### What the Cart Does NOT Own

To prevent scope creep, the cart module explicitly does **not** handle:

- Order placement, payment, or `LOCKED → COMPLETED` transitions (separate slice).
- Coupons or promotion codes (separate slice).
- Delivery fees, taxes, packaging charges (computed at order time, not in cart).
- Address selection (separate module).
- Tip, instructions, or scheduled delivery.
- Cross-cart_type UX (the picker between FOOD/GROCERY/PRODUCT carts is later).

The cart returns money + UX-driver fields below. Final order total (after
coupons, taxes, surge, distance-based delivery) is computed at order placement.

#### Money fields on `CartResponse`

| Field                  | Type      | Meaning                                                  |
|------------------------|-----------|----------------------------------------------------------|
| `currency`             | string    | ISO 4217 code (`"INR"` today)                            |
| `subtotal`             | decimal   | Sum of snapshot selling prices for selected items × qty  |
| `totalSavings`         | decimal   | Sum of `(mrp - sellingPrice) × qty` for selected items   |
| `deliveryFee`          | decimal?  | Shop-level base fee from `delivery_config`; null if none |
| `platformFee`          | decimal   | Platform-wide constant (`app.cart.platform-fee`)         |
| `freeDeliveryAbove`    | decimal?  | Threshold from `delivery_config`; null if not configured |
| `amountToFreeDelivery` | decimal?  | `max(0, freeDeliveryAbove - subtotal)`; null if no threshold |
| `lastUpdatedAt`        | ISO 8601  | Most recent session/item update — drives cache staleness |
| `messages`             | array     | UI signal chips. Empty today. `{ kind, text }`           |
| `offers`               | array     | Reserved for offers slice. Empty today.                  |

Why these fields, not others:

- `discount` total is `totalSavings`; the cart screen renders it from there.
- **No** `grandTotal` field. The cart screen computes `subtotal + deliveryFee +
  platformFee` for display only; order placement recomputes authoritatively.
- **No** coupon fields. Coupons land in their own slice.
- `messages` and `offers` are empty arrays today so the contract is forward-
  compatible — adding chips later does not bump the contract version.

## Related decisions

- [ADR-0002](../01-Architecture/decisions/ADR-0002-order-orderline-snapshot-pricing-schema.md) — the order/order-line snapshot schema mirrors the cart's snapshot-at-add semantics described above.
- [ADR-0011](../01-Architecture/decisions/ADR-0011-cart-per-line-quantity-cap.md) — per-line quantity cap (raised from the Phase 1 default of 10 to 25).

## Where it's enforced

- Backend: `CartServiceImpl` (add/update/remove/accept-changes orchestration),
  `CartSessionServiceImpl` (session lifecycle — lazy creation, lock/unlock,
  shop-conflict resolution), `CartKeyService` (the locked `cart_key` formula),
  `PriceCalculator` (price computation, 3-arg overload), `IdempotencyService`
  (add-to-cart replay protection).
- Frontend: `useCartStore` — a server-synced store that mirrors the last
  `CartResponse` and applies optimistic-overlay maps (`optimisticQuantity`,
  `optimisticallyRemoved`) while a mutation is in flight. Its addon snapshot
  fields (`mrp`, `sellingPrice`, `discountPercent`) line up with the server's
  `cart_item_addons` fields — keep them in sync. It computes `cart_key` locally
  for UI line tracking using the exact same formula as the backend, but never
  sends it on requests.

### Frontend behaviour notes

- A successful mutation returns the full cart; do not re-issue `GET /api/cart`
  after every mutation.
- On `409 DIFFERENT_SHOP_CART_EXISTS`, surface the *"Clear cart to order from X?"*
  dialog using `existingShopName` and `newShopName` from the response.
- On `409 SESSION_LOCKED`, show *"Order in progress, please wait"* and disable
  cart actions until the payment flow resolves.
- On any item with `validation ≠ OK`, render an inline warning on that line and
  a banner offering "Accept changes" mapped to `PUT /api/cart/accept-changes`.
- Until the vertical picker UI exists, always send `type=FOOD` on cart calls.
- Generate a fresh UUID v4 `Idempotency-Key` header per add-to-cart click.
