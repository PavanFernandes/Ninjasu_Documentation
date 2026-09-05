---
id: ADR-0008
title: "ADR-0008: Saved Delivery Addresses (Customer Address Book)"
summary: "Built a server-backed, DPDP-compliant saved-address book fully decoupled from the order's own delivery_* snapshot, so deleting a saved address can never corrupt past order history."
type: decision
status: accepted
apps: ["backend","customer"]
module: "addresses"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/SavedDeliveryAddress.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/repository/SavedDeliveryAddressRepository.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/SavedDeliveryAddressServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/controller/SavedDeliveryAddressController.java" }
  - { repo: customer, path: "src/features/addresses" }
  - { repo: customer, path: "app/select-location.tsx" }
  - { repo: customer, path: "app/address-form.tsx" }
  - { repo: customer, path: "src/store/useLocationStore.ts" }
verified_against: "backend@ff5ade334891238d16b8010e372fdbbc502c193e, customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-06-22
---

# ADR-0008: Saved Delivery Addresses (Customer Address Book)

## Context

There was no address book. The active delivery location lived only in `useLocationStore`
(in-memory, not even AsyncStorage-persisted, so it was lost on every app restart), and
`select-location.tsx` showed a hardcoded mock "Saved Addresses" list with fake coordinates. The
only address data that was ever actually persisted was the order's denormalized `delivery_*`
snapshot. The goal was a reusable, server-backed address book (Swiggy/Zomato-style) — save
Home/Work/Other once, pick at checkout.

**Compliance (DPDP Act 2023 / DPDP Rules 2025, India):** storing addresses is permitted but must
honour explicit purpose-bound consent (the "Save this address" button — nothing persists
silently), data minimisation (flat/landmark/alt-phone are optional), deletability (DELETE now,
account purge later), and easy withdrawal. This was researched explicitly before proceeding;
verdict was to store it, consented and deletable.

## Decision

- **Naming**, to avoid confusion with the existing order snapshot: table
  `saved_delivery_addresses`, entity `SavedDeliveryAddress`, DTOs `SavedAddressDto` /
  `SavedAddressRequest`, endpoints `/api/delivery-addresses`. The order request shape keeps its
  own name `DeliveryAddressDto`; the order table's columns keep their `delivery_*` prefix.
- `user_id` is a shared-ID column with no JPA `@ManyToOne` to `User` — matching the existing
  `Wishlist` pattern.
- Ownership is enforced in the service layer via `findByIdAndUserId`; a non-owner id resolves to
  404 (`ResourceNotFoundException`), **not** 403. This closes an IDOR (Insecure Direct Object
  Reference) hole, and specifically avoids 403 because the frontend's `fetchFn` treats a 403 as a
  session-invalidating response and would clear the session.

### Risks considered

- **Deleting a saved address must not corrupt order history (high risk if unmitigated).**
  Scenario: a user deletes "Home" after ordering; if `Order` had an FK to
  `SavedDeliveryAddress`, the order detail screen would blank out or 500. Mitigation: `Order` is
  never FK'd to `SavedDeliveryAddress` — the order keeps its own `delivery_*` snapshot. The
  address book is convenience data; the order address is transaction data, permanently decoupled.
- **Two defaults / zero default (medium risk).** Mitigated with a single `@Transactional`
  `clearDefaultForUser` call before setting a new default. The first address saved is
  auto-defaulted. Deleting the current default promotes the newest remaining address.
- **Migration (low risk).** Purely additive table; `ddl-auto=update` creates it. The old
  in-memory store was never persisted, so there is no backfill to run.
- **Frontend re-deriving the display string (low risk, drift risk).**
  `useLocationStore.setSavedAddress` uses the saved `formattedAddress` verbatim rather than
  re-deriving it from parts. The parts-based derivation path is kept only for the "fresh current
  location" (GPS) flow, not for saved addresses.

## Consequences

**Makes easy:**
- Reusable, persistent Home/Work/Other addresses selectable at checkout, matching the
  Swiggy/Zomato pattern users already expect.
- Safe deletion of a saved address at any time — order history is structurally immune because it
  never references the address book by FK.
- Adding new optional fields to the address book (flat, landmark, alt-phone) without touching the
  order snapshot shape.

**Makes hard / rules out:**
- Cannot enforce address book / order-address consistency via foreign key — any future feature
  that assumes an order can look up its live address book entry must instead re-fetch it
  explicitly, understanding the two are intentionally decoupled.
- Cannot rely on JPA relationship loading for `user_id`; every query goes through explicit
  `userId`-scoped repository methods (`findByUserIdOrderByIsDefaultDescCreatedOnDesc`,
  `findByIdAndUserId`, `existsByUserId`, `clearDefaultForUser`).

**Rules out:**
- A generic "addresses belong to orders" model — this ADR fixes the address book and the order
  snapshot as two permanently separate concerns, not a temporary shortcut.

## Enforced in

**Backend** (`ninja delivery service java`):
- `entity/SavedDeliveryAddress.java` — the entity, with `user_id` as a plain shared-ID column
  (no `@ManyToOne`).
- `repository/SavedDeliveryAddressRepository.java` — `findByUserIdOrderByIsDefaultDescCreatedOnDesc`,
  `findByIdAndUserId`, `existsByUserId`, `clearDefaultForUser`.
- `service/impl/SavedDeliveryAddressServiceImpl.java` — ownership check via `findByIdAndUserId`
  raising `ResourceNotFoundException` (404) on a non-owner id; `clearDefaultForUser` called inside
  `@Transactional` methods before assigning a new default.
- `controller/SavedDeliveryAddressController.java` — `GET/POST/PATCH/DELETE /api/delivery-addresses`,
  `PATCH /api/delivery-addresses/{id}/set-default`. No `SecurityConfig` change was needed;
  `anyRequest().authenticated()` already gated it.
- No FK from `Order`/order tables to `saved_delivery_addresses` — the order retains its own
  `delivery_*` snapshot columns.

**Frontend** (`Food-Ninja-Frontend`):
- `src/features/addresses/` — types, service, hooks (`useAddresses`,
  `useAutoSelectDefaultAddress`), `AddressFormScreen`, `SavedAddressList`, `LocationPromptCard`.
- `app/address-form.tsx` — route, registered in `app/_layout.tsx`.
- `app/select-location.tsx` — rewired from the hardcoded mock list to the real address book.
- `src/store/useLocationStore.ts` — `setSavedAddress` uses the saved `formattedAddress` verbatim
  (no re-derivation from parts).
- `ProfileScreen` — "Saved Addresses" entry point into the address book.

Reuse note: this mirrors the existing `Wishlist` pattern end-to-end (shared-ID entity reference,
controller `@AuthenticationPrincipal` idiom, TanStack Query hook). No separate `AddressListScreen`
was built — the existing `select-location.tsx` was wired to real data instead, to avoid two
competing address UIs.

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
