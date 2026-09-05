---
id: ADR-0002
title: "ADR-0002: Order / OrderLine Snapshot-Pricing Schema (Risk 6)"
summary: "Order/OrderLine/OrderLineAddon snapshot item name, price, MRP, and discount at order time instead of joining live addon/item prices, so order history never changes when shop prices change later."
type: decision
status: accepted
apps: ["backend","customer"]
module: "cart"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/Order.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/OrderLine.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/OrderLineAddon.java" }
  - { repo: customer, path: "src/features/cart/types.ts" }
verified_against: "backend@ff5ade334891238d16b8010e372fdbbc502c193e customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-05-21
---

# ADR-0002: Order / OrderLine Snapshot-Pricing Schema (Risk 6)

## Context

No `Order` entity or schema existed yet when this decision was made — the snapshot model had
to be designed before any order-placement code was written.

ARCHITECTURE.md Principle 18 requires the Order entity to snapshot, at the time the order is
placed: item name, image, and description; exact pricing (selling price, MRP, discount
applied); all selected addons/modifiers with their option names and prices; and the shop
reference.

The pricing model adds complexity because price comes entirely from addon options (Schema
Rule S1 — no `price` field on `items`), so an order line's snapshot must preserve, per
selected addon: the `addonId`, `addonName`, `groupId`/`groupName`, the selling price and MRP
*at the time of order* — not a reference to the current `addons.price` (which the shop can
change at any time) — and the `discountPercent` that applied (which could come from the addon
or be inherited from the item).

The frontend cart store already snapshotted these values correctly (price/MRP/discountPercent
captured per cart addon at add-to-cart time). The alternative on the table was for the backend
`Order` entity to store only FK references (`addonId`) and join back to `addons.price` for
display — which is cheaper to build but reconstructs the *current* price, not the historical
one, every time an old order is viewed.

## Decision

The backend `Order` entity mirrors the frontend's snapshot semantics rather than deriving
prices by FK join at read time.

- `orders`: holds order-level snapshot totals (subtotal, delivery fee, platform fee, grand
  total) plus a delivery-address snapshot, alongside identity/status/idempotency fields.
- `order_lines`: holds `item_name`, `item_image_url`, `quantity`, and a
  `line_total_snapshot` per line, referencing the item by ID for reorder resolution only —
  never for price display.
- `order_line_addons`: holds `addon_name`, `group_name`, `mrp`, `selling_price`, and
  `discount_percent` per selected addon, referencing `addon_id` by FK for reorder resolution
  only.

The snapshot columns on `order_lines` and `order_line_addons` are non-negotiable per
Principle 18 and Schema Rule S15: an order line's displayed price must never be computed by
joining back to the live `addons`/`items` tables.

## Consequences

- Order history and reorder screens always show the price the customer actually paid, even if
  the shop has since changed addon prices or discounts — this is the entire point of the
  decision.
- Reorder flow can still resolve back to the live item/addon via the retained `item_id` /
  `addon_id` FKs, to check current availability, without touching the snapshot columns.
- Every order-line and order-line-addon row duplicates pricing data that also exists (in
  possibly-changed form) on `items`/`addons` — this is intentional denormalization, not drift
  to be "fixed" later.
- Any future code that adds a price-bearing field to addons/items must also decide whether
  that field belongs in the snapshot tables; the pattern established here (snapshot everything
  price-relevant, FK only for resolution) is the default answer.

## Enforced in

- `Order.java`, `OrderLine.java`, `OrderLineAddon.java` (backend) — entity definitions for
  the three-table snapshot schema described above.
- `cart/types.ts` (frontend) — cart-side snapshot fields (`snapshotMrp`,
  `snapshotSellingPrice`, `snapshotDiscountPercent`, `snapshotItemName`, `snapshotLineTotal`)
  that this schema mirrors on the backend.

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
