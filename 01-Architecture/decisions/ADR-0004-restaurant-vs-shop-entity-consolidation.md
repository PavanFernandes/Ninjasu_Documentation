---
id: ADR-0004
title: "ADR-0004: Restaurant vs Shop Entity Consolidation (Open Question, Risk 4)"
summary: "Shop remains the single cross-domain entity; Restaurant becomes a 1:1 vertical-extension table read and written exclusively through ShopService, avoiding a fork between two entities for order/menu references."
type: decision
status: accepted
apps: ["backend"]
module: "architecture"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/Restaurant.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/Shop.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/ShopServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/repository/RestaurantRepository.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/controller/ShopController.java" }
verified_against: "ff5ade334891238d16b8010e372fdbbc502c193e"
updated: 2026-05-21
---

# ADR-0004: Restaurant vs Shop Entity Consolidation (Open Question, Risk 4)

## Context

`entity/Restaurant.java` mapped to a `restaurants` DB table and carried a `@OneToOne` back to `Shop`:

```java
@OneToOne
@JoinColumn(name = "shop_id", insertable = false, updatable = false)
private Shop shop;
```

At the time this was flagged, the entity was orphaned: no controller, no service, no repository. If the
`restaurants` table existed in Neon it had been created silently by `ddl-auto=update`; if it didn't,
Hibernate risked erroring on startup.

The entity held fields that genuinely belong to restaurant-vertical shops — `rating`, `totalOrders`,
`fssaiLicense`, `gstNumber`, `avgPrepTime` — but with no service layer to write or read them, an Orders
developer would hit a fork: reference `Shop` (used everywhere else across the codebase) or `Restaurant`
(holds the order-relevant fields)? Referencing `Shop` would mean `totalOrders`/`rating` never update.
Referencing `Restaurant` would mean picking up an untested, un-wired entity with a live JPA join that
violates the project's dependency/coupling guard (see root `CLAUDE.md`).

Compounding this, `@JoinColumn(insertable = false, updatable = false)` made the `shop` association
read-only — `Restaurant` could never be saved with a `shop` reference through that field, making the
entity effectively un-creatable via the JPA association alone.

The open question: does `Restaurant.java` get wired up as its own authoritative restaurant-specific
entity (own service/controller), or do its fields fold into `Shop.java` directly?

## Decision

Neither extreme. `Shop` stays the single authoritative, cross-vertical entity — every other domain
(menu, cart, orders) continues to reference shops by `Shop`/`shopId`, never `Restaurant`. `Restaurant`
is kept as a **vertical-specific extension table**, 1:1 keyed on `shop_id`, but it is given no
independent existence: no `RestaurantService`, no `RestaurantController`. It is read and written
exclusively through `ShopService`/`ShopController`, the same pattern already used for `DeliveryConfig`.

Concretely:
- `RestaurantRepository` exists and is injected only into `ShopServiceImpl`.
- Writes go through `ShopController`'s `POST /{shopId}/restaurant` → `ShopService.addRestaurantDetails`,
  which persists via the entity's plain `UUID shopId` `@Id` column (`restaurant.setShopId(shopId)`), not
  through the `@OneToOne shop` association.
- Reads are merged back into `ShopDto` inside `ShopServiceImpl.convertToDto`, gated on
  `shopType == "RESTAURANT"`, so callers of the shop API get `restaurantType`/`avgPrepTime`/etc. as
  plain fields on the shop response — they never see `Restaurant` as a separate resource.
- `rating`/`totalOrders` are actively read today (e.g. home-feed and search ordering/display), closing
  the "fields with no service to access them" gap.
- Shop activation (`activateShop`) enforces that a `RESTAURANT`-typed shop has a matching `Restaurant`
  row before it can go `ACTIVE`, closing the "orphaned entity might not exist" gap.

## Consequences

**Makes easy:** Orders/menu/cart code has one unambiguous entity to reference (`Shop`) — no fork.
Adding another vertical's detail table (e.g. a future `Grocer` or `Pharmacy` extension) can follow the
same satellite-table-owned-by-`ShopService` pattern without touching other domains.

**Makes hard / residual wart:** the `@OneToOne shop` field on `Restaurant` is still present in the
entity and is still read-only (`insertable = false, updatable = false`). It is not used anywhere in the
codebase for reads or writes — all access goes through the plain `shopId` `@Id` column instead. This is
dead mapping left over from the original design; it doesn't violate the coupling guard in practice
(nothing traverses it), but it's a latent trap for a future developer who instinctively reaches for
`restaurant.getShop()` expecting it to be populated/writable the way a normal association would be.
Removing that field was part of the original mitigation suggestion but was not carried out — only the
service-ownership half of the decision was enforced.

**Rules out:** a standalone `RestaurantController`/`RestaurantService` surface, or any other domain
reading/writing `Restaurant` directly instead of going through `ShopService`.

## Enforced in

- `entity/Restaurant.java` — satellite entity, `shopId` as plain `@Id` column (the actual persistence
  key), `shop` `@OneToOne` kept but unused.
- `entity/Shop.java` — remains the single cross-domain entity referenced by menu/cart/orders.
- `repository/RestaurantRepository.java` — injected only into `ShopServiceImpl`, no other consumer.
- `service/impl/ShopServiceImpl.java` — `addRestaurantDetails(...)` (write path), `convertToDto(...)`
  (merges restaurant fields into `ShopDto`), `activateShop(...)` (enforces a `Restaurant` row exists
  before a `RESTAURANT`-typed shop can activate).
- `controller/ShopController.java` — `POST /{shopId}/restaurant` is the only write entrypoint for
  restaurant details.

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
