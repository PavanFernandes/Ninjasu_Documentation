---
id: ""
type: domain
status: active
apps: [backend, customer]
module: "wishlist"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/Wishlist.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/repository/WishlistRepository.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/WishlistServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/controller/WishlistController.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/dto/wishlist/AddWishlistRequest.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/dto/wishlist/WishlistItemDto.java" }
  - { repo: backend, path: "db_manual/wishlist_module_constraints.sql" }
  - { repo: customer, path: "src/store/useWishlistStore.ts" }
  - { repo: customer, path: "src/features/wishlist/hooks/useWishlistToggle.ts" }
  - { repo: customer, path: "src/features/wishlist/hooks/useWishlistQuery.ts" }
  - { repo: customer, path: "src/features/wishlist/components/WishlistBootstrap.tsx" }
  - { repo: customer, path: "src/features/wishlist/services/wishlist.service.ts" }
  - { repo: customer, path: "src/features/wishlist/WishlistScreen.tsx" }
  - { repo: customer, path: "src/shared/components/HeartButton.tsx" }
verified_against: "backend@ff5ade334891238d16b8010e372fdbbc502c193e customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-07-11
---

# Wishlist Module — Business Rules & Logic

Source of truth for wishlist behaviour. Both frontend and backend must agree on these rules.
If a rule changes, update this doc first, then both sides.

The wishlist is the user's personal, cross-shop collection of saved **items**. It is a pure
save/unsave bookmark — it holds no pricing, no quantity, and never places an order. Adding a
wishlisted item to the cart goes through the **normal cart flow**, never a bypass path.

## Model — One Unified, Cross-Shop List

- There is **one** wishlist per user. No separate "favourites" vs "save for later".
- It is **cross-shop**: any item from any restaurant can be saved, and the list mixes shops.
- The unit saved is the **item**, never an addon selection and never a shop.
  - The heart on the RestaurantScreen hero bar saves the *restaurant* — that is a different,
    pre-existing concept and is **not** part of this module.
- **v1 scope = FOOD (restaurant) items only.** The schema and endpoints are vertical-agnostic;
  grocery/product saving is a later phase with no migration required.

## Identity & Idempotency

- A wishlist entry is uniquely `(user_id, item_id)`, enforced by a unique DB constraint (see
  the `db_manual` anchor).
- **Add is idempotent**: adding an already-saved item is a no-op that still returns success —
  the service checks for existence and skips the insert.
- **Remove is idempotent**: removing succeeds even if the entry did not exist.
- User identity always comes from the JWT, never the request body.

> Why idempotent both ways: the heart is an optimistic toggle. Network retries and double-taps
> must never error or create duplicates — the DB constraint is the hard guard, the existence
> check is the soft guard.

## Local ID Set — Why the Home Feed Has No `isWishlisted` Flag

The hottest read path (the home feed) is **unauthenticated** native SQL. Adding a wishlisted
flag to the item preview shape would force authenticating that endpoint and joining a per-user
table into the home query — a breaking change to the busiest endpoint, for a single boolean.

Instead, the frontend keeps the wishlist as a **set of item IDs** in a Zustand store, hydrated
**once** from the wishlist API on login / app start, and cleared on logout. Every heart reads
`set.has(itemId)` — O(1), zero DTO changes, zero extra joins on any feed.

- `WishlistBootstrap` (mounted at app root next to `CartBootstrap`) drives the hydrate/clear
  lifecycle off auth-token transitions.
- `useWishlistQuery` (the wishlist screen's data source) also re-hydrates the set on every
  successful fetch, so the screen and the hearts never disagree.

## Optimistic Toggle (frontend rule)

`useWishlistToggle(itemId)` is the only way to flip a heart. The sequence:

1. **No token** → route to login. (Wishlisting requires an account — see
   [ADR-0010](../01-Architecture/decisions/ADR-0010-guest-browsing-gate-at-add-to-cart.md) for
   the guest-browsing gate-at-action pattern this follows.)
2. **In-flight guard** → if a toggle for this item is already running, ignore the tap. This
   prevents double-fire add/remove races.
3. **Flip the set immediately** (optimistic), then call the service.
4. **On error, roll back** the set to its previous state.

The store mutates by creating new set instances so subscribed hearts re-render.

## Price on the Wishlist Card — Must Match the Home Card

The wishlist card shows a **"starting price"**. This MUST equal the price the same item shows
on the home feed, or the same item appears to cost two different amounts.

The locked rule (mirrors the home feed's min-price query exactly):

- Pick the **lowest raw-price** required **ITEM-scoped** addon. SHARED groups never define base
  price.
- The query returns that addon's raw price plus its discount and the item's discount. The
  effective discount is resolved in **`PriceCalculator`** (Java) — **never** computed in SQL.
- The display price is **nullable**: null when the item has no required ITEM-scoped addon group.
  The frontend hides the price line when null.

> ⚠️ Price logic lives in exactly one place: `PriceCalculator`. If the home feed's price
> selection rule changes, the wishlist repository query changes in the **same edit**. Drifting
> them silently shows two prices for one item.

## Availability

The wishlist item's availability flag reflects live item state at read time: available AND
active AND not deleted.

- A wishlisted item can become unavailable (shop disabled it) — it **stays in the list**, shown
  dimmed with a "Currently unavailable" label and a disabled ADD button.
- A **deleted** item is excluded from the list entirely (joined out).

> The availability field is deliberately named to avoid a Lombok `Boolean` getter-naming pitfall
> that serializes wrong under Jackson — see the DTO anchor for the exact field name both sides
> must match.

## Adding a Wishlisted Item to Cart — No Bypass

The ADD button on a wishlist card **always routes to the restaurant screen**, it does **not**
add to cart directly.

Reason: addon-group selection (required ITEM-scoped groups define the price and are mandatory)
only exists on the restaurant screen. There is no correct way to add a customizable item to the
cart without that selection. This keeps the wishlist consistent with `ItemCard` behaviour and
ensures every add goes through the normal cart-mutation add path — including the existing
single-shop "Clear cart?" conflict handling. The wishlist never gets its own cart-mutation path.

## Endpoints — At a Glance

All wishlist endpoints require JWT — user identity comes from the security context, never the
request body. All return the standard API envelope.

| Method | Path                       | Purpose                                  |
|--------|----------------------------|-------------------------------------------|
| GET    | `/api/wishlist`            | List the user's wishlist (newest first)   |
| POST   | `/api/wishlist`            | Add an item (idempotent)                  |
| DELETE | `/api/wishlist/{itemId}`   | Remove an item (idempotent)               |

`GET` orders by most-recently-saved first. See the `WishlistController` and `WishlistItemDto`
anchors for the exact request/response shapes — do not hand-copy them here.

## What the Wishlist Does NOT Own

- Cart mutation — adding to cart routes through the restaurant screen + normal cart flow.
- Pricing logic — it only *displays* a price computed by `PriceCalculator`.
- Saving restaurants — the RestaurantScreen hero heart is a separate concept.
- Grocery / product items — v1 is FOOD only.
- Quantity, addon selection, notes, or any order concept.
- Notifications ("price dropped on a saved item" etc.) — not in v1.

## Related decisions

- [ADR-0010](../01-Architecture/decisions/ADR-0010-guest-browsing-gate-at-add-to-cart.md) — the
  guest-browsing gate-at-action pattern that `useWishlistToggle`'s no-token step follows.

## Where it's enforced

**Backend** (`anchors` above)
- `entity/Wishlist.java` — the `(user_id, item_id, created_on)` row, UUID PK.
- `repository/WishlistRepository.java` — exists/delete by user+item, native list query that
  mirrors the home feed's price selection.
- `service/impl/WishlistServiceImpl.java` — idempotent add/remove, resolves display price via
  `PriceCalculator`.
- `controller/WishlistController.java` — the three endpoints.
- `dto/wishlist/AddWishlistRequest.java`, `dto/wishlist/WishlistItemDto.java` — request/response
  shapes.
- `db_manual/wishlist_module_constraints.sql` — the uniqueness constraint + index on `user_id`
  (run once after the app boots and Hibernate creates the table).

**Frontend** (`anchors` above)
- `src/store/useWishlistStore.ts` — the local ID set (+ in-flight set).
- `src/features/wishlist/hooks/useWishlistToggle.ts` — optimistic toggle.
- `src/features/wishlist/hooks/useWishlistQuery.ts` — screen data + re-hydrate.
- `src/features/wishlist/components/WishlistBootstrap.tsx` — login/logout lifecycle.
- `src/features/wishlist/services/wishlist.service.ts` — the three API calls.
- `src/features/wishlist/WishlistScreen.tsx` — the list screen + its route.
- `src/shared/components/HeartButton.tsx` — the reusable heart (home ItemCard + restaurant row).
