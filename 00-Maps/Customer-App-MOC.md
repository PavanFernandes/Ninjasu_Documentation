---
id: ""
type: reference
status: active
apps: [customer]
module: "meta"
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Customer App — Map of Content

**Food-Ninja-Frontend** — the customer-facing React Native (Expo) app: discover shops, browse
menus, build a cart, check out, track orders, and (for `SHOP`-role users) the in-app seller area
and captain-ordering (dine-in POS + KDS) surfaces that live in the same repo.

## Domain rules that apply

These are shared business rules — backend enforces, this app renders. Read the relevant one
before touching a feature in that area.

- [Core](../02-Domain/core.md) — API envelope, auth, money, discount precedence, snapshot
  pricing, validation boundaries, time, idempotency
- [Menu](../02-Domain/menu.md) — categories, items, addon groups, combos, availability
- [Cart](../02-Domain/cart.md) — cart sessions, multi-vertical carts, snapshot pricing, validation
- [Wishlist](../02-Domain/wishlist.md) — wishlist rules
- [Captain Ordering](../02-Domain/captain-ordering.md) — dine-in POS + KDS rules

## Backend contracts

- [Auth & Security](../03-Backend/auth-and-security.md) — OTP token exchange, guest-browsing
  public reads, ownership checks

## Customer-app-specific

- [UX Reviews](../04-Customer-App/ux-reviews.md)

## Relevant decisions

Directly shapes customer-app behavior:

- [Pre-Phase-1E Devil's Advocate Risk Review — Verdict & Blocking Punch List](../01-Architecture/decisions/ADR-0001-pre-phase-1e-devils-advocate-risk-review.md)
- [Order / OrderLine Snapshot-Pricing Schema (Risk 6)](../01-Architecture/decisions/ADR-0002-order-orderline-snapshot-pricing-schema.md)
- [Order Placement Idempotency (Idempotency-Key Design, Risk 7)](../01-Architecture/decisions/ADR-0003-order-placement-idempotency.md)
- [Per-Option Images for Shared Addons](../01-Architecture/decisions/ADR-0007-per-option-images-shared-addons.md)
- [Saved Delivery Addresses (Customer Address Book)](../01-Architecture/decisions/ADR-0008-saved-delivery-addresses.md)
- [Pluggable OTP Auth (Backend Today, Firebase Now, MSG91 Later)](../01-Architecture/decisions/ADR-0009-pluggable-otp-auth.md)
- [Guest Browsing ("Skip for Now") with Gate at Add-to-Cart (Option A)](../01-Architecture/decisions/ADR-0010-guest-browsing-gate-at-add-to-cart.md)
- [Cart Per-Line Quantity Cap = 25](../01-Architecture/decisions/ADR-0011-cart-per-line-quantity-cap.md)
- [Captain Ordering (Dine-In POS + KDS) — Append-KOT-Under-Check Architecture](../01-Architecture/decisions/ADR-0012-captain-ordering-dine-in-pos-kds.md)

Backend-infra-adjacent, still linked for completeness:

- [Restaurant vs Shop Entity Consolidation (Open Question, Risk 4)](../01-Architecture/decisions/ADR-0004-restaurant-vs-shop-entity-consolidation.md)
- [Shop Membership (user_shops) + Staff Invites (shop_invites)](../01-Architecture/decisions/ADR-0005-shop-membership-and-staff-invites.md)
- [SHOP Role App Area (Seller Home)](../01-Architecture/decisions/ADR-0006-shop-role-app-area.md)

## Architecture

- [Architecture Principles](../01-Architecture/principles.md) — read the `[FRONTEND]` and
  `[SHARED]` tagged principles; skip `[BACKEND]`-only ones unless touching the boundary.
