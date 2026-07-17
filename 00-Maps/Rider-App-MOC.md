---
id: ""
type: reference
status: active
apps: [rider]
module: "meta"
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Rider App — Map of Content

**Ninjasu_Rider_App** — this app has **not been built yet**. This is a stub hub note reserving
its place in the vault structure so links and cross-references resolve correctly once work
starts. There is no repo, no code, and no anchors yet.

## What it will share

When built, this app is still a client of the same shared backend and domain rules as the other
two clients (customer, admin) — it does not get its own business logic:

- [Backend contracts](../03-Backend/) — shared backend (`ninja delivery service java`); same API
  envelope, auth, and endpoints the other apps consume.
- [Domain rules](../02-Domain/) — shared business rules that every client renders, not
  re-implements. In particular, order lifecycle and delivery-address rules will apply directly.
- [Architecture Principles](../01-Architecture/principles.md) — read the `[SHARED]` tagged
  principles when scaffolding starts; `[FRONTEND]` principles will likely apply too once this
  becomes a client app, but confirm against whatever stack the rider app ends up built in.

## When this app is built

Its own knowledge (screens, flows, rider-app-specific decisions, UX reviews) goes in
[`../06-Rider-App/`](../06-Rider-App/) — mirroring how `../04-Customer-App/` and
`../05-Web/` are organized for their respective apps. This MOC should then be
expanded from a stub into a full map pointing into that folder.

## Relevant decisions

These ADRs concern order lifecycle and delivery, and most plausibly carry over to the rider app
once it exists. Not yet confirmed against real rider-app code — re-check each when the app is
actually built.

- [Pre-Phase-1E Devil's Advocate Risk Review — Verdict & Blocking Punch List](../01-Architecture/decisions/ADR-0001-pre-phase-1e-devils-advocate-risk-review.md) — covers the Cart → Order flow, order status transitions, and delivery provider integration directly.
- [Order / OrderLine Snapshot-Pricing Schema (Risk 6)](../01-Architecture/decisions/ADR-0002-order-orderline-snapshot-pricing-schema.md) — the order/order-line shape a rider app would read to know what to deliver.
- [Order Placement Idempotency (Idempotency-Key Design, Risk 7)](../01-Architecture/decisions/ADR-0003-order-placement-idempotency.md) — idempotency pattern for order-lifecycle actions; likely relevant if rider status-update actions (accept/pickup/deliver) need the same protection.
- [Restaurant vs Shop Entity Consolidation (Open Question, Risk 4)](../01-Architecture/decisions/ADR-0004-restaurant-vs-shop-entity-consolidation.md) — the shop entity is the rider's pickup location.
- [Saved Delivery Addresses (Customer Address Book)](../01-Architecture/decisions/ADR-0008-saved-delivery-addresses.md) — the address book a rider app would read for the drop-off location.
- [Pluggable OTP Auth (Backend Today, Firebase Now, MSG91 Later)](../01-Architecture/decisions/ADR-0009-pluggable-otp-auth.md) — riders will most likely authenticate through the same OTP infrastructure.

Not linked as not plausibly relevant to a rider app: ADR-0005 (shop staff invites), ADR-0006
(SHOP-role seller home), ADR-0007 (addon images), ADR-0010 (guest browsing — riders are
authenticated staff, not anonymous browsers), ADR-0011 (cart quantity cap), ADR-0012 (dine-in
captain ordering — no delivery leg).
