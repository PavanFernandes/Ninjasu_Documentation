---
id: ""
title: "Domain — Shared Business Logic"
summary: "Index and entry point for the cross-repo domain folder, listing which module doc (core, menu, cart, wishlist, captain-ordering) covers which shared business rule."
type: reference
status: active
apps: [backend, customer, admin, rider]
module: "meta"
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Domain — Shared Business Logic

This folder is the **source of truth** for business rules shared across the whole Ninjasu platform. It is not backend code and not any one app's code — it belongs to the product. Every app (backend, customer, admin, rider) must read the relevant module before implementing a feature that touches it; if a rule here is wrong or missing, update it and inform the other teams.

## Contents

| File | What It Covers |
|------|-----------------|
| [core.md](core.md) | Cross-cutting rules: API envelope, auth, money, discount precedence, snapshot pricing, validation boundaries, time, idempotency |
| [menu.md](menu.md) | Categories, items, addon groups, combos, availability |
| [cart.md](cart.md) | Cart sessions, multi-vertical carts, snapshot pricing, validation |
| [wishlist.md](wishlist.md) | Wishlist rules |
| [captain-ordering.md](captain-ordering.md) | Captain ordering (dine-in POS + KDS) rules |
