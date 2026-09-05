---
id: ""
title: "Architecture Decisions — Index"
summary: "Index of every ADR in the vault, in numeric order, each with a one-line pointer to what it decided."
type: reference
status: active
apps: [backend, customer, admin, rider, web]
module: "architecture"
anchors: []
verified_against: ""
updated: 2026-09-05
---

# Architecture Decisions — Index

Every ADR in this vault, in numeric order. An ADR is a locked, dated decision — never edited in
place, only superseded by a newer one (see the root [README.md](../../README.md)'s "two layers"
table). Read [`principles.md`](../principles.md) for the long-horizon principles these decisions
sit on top of.

| ADR | Decision |
|---|---|
| [ADR-0001](ADR-0001-pre-phase-1e-devils-advocate-risk-review.md) | Pre-Phase-1E devil's-advocate risk review — verdict & blocking punch list |
| [ADR-0002](ADR-0002-order-orderline-snapshot-pricing-schema.md) | Order / OrderLine snapshot-pricing schema |
| [ADR-0003](ADR-0003-order-placement-idempotency.md) | Order placement idempotency (Idempotency-Key design) |
| [ADR-0004](ADR-0004-restaurant-vs-shop-entity-consolidation.md) | Restaurant vs Shop entity consolidation |
| [ADR-0005](ADR-0005-shop-membership-staff-invites.md) | Shop membership (`user_shops`) + staff invites (`shop_invites`) |
| [ADR-0006](ADR-0006-shop-role-app-area.md) | SHOP role app area (seller home) |
| [ADR-0007](ADR-0007-per-option-images-shared-addons.md) | Per-option images for shared addons |
| [ADR-0008](ADR-0008-saved-delivery-addresses.md) | Saved delivery addresses (customer address book) |
| [ADR-0009](ADR-0009-pluggable-otp-auth.md) | Pluggable OTP auth (backend today, Firebase now, MSG91 later) |
| [ADR-0010](ADR-0010-guest-browsing-gate-at-add-to-cart.md) | Guest browsing ("Skip for Now") with gate at add-to-cart |
| [ADR-0011](ADR-0011-cart-per-line-quantity-cap.md) | Cart per-line quantity cap = 25 |
| [ADR-0012](ADR-0012-captain-ordering-dine-in-pos-kds.md) | Captain Ordering (dine-in POS + KDS) — append-KOT-under-check architecture |
| [ADR-0013](ADR-0013-rider-live-tracking-poll-not-websocket.md) | Rider live GPS tracking — REST + polling, not WebSocket |
| [ADR-0014](ADR-0014-rider-cod-completion-cash-discrepancy-control.md) | Rider COD completion bundles OTP + cash, with a cash-discrepancy control |
| [ADR-0015](ADR-0015-rider-single-active-on-duty-device.md) | One active on-duty device per rider, claimed on Go Online |
| [ADR-0016](ADR-0016-multi-client-backend-boundary.md) | Multi-client backend — code by domain, API surface by audience |
| [ADR-0017](ADR-0017-ninjasu-web-stack-and-auth.md) | Ninjasu_Web stack (Next.js) + BFF cookie auth |
| [ADR-0018](ADR-0018-razorpay-two-phase-checkout-confirm.md) | Razorpay online payment — two-phase checkout/confirm + pluggable settlement |
| [ADR-0019](ADR-0019-dispatch-mode-vs-delivery-mode.md) | `dispatchMode` split from `deliveryMode` |
