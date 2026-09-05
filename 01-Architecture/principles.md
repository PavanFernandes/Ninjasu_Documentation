---
id: ""
title: "Food Ninja — Architectural Principles"
summary: "Index of the 20 long-horizon architectural principles (tagged SHARED/FRONTEND/BACKEND), split into 3 parts by topic, plus what-not-to-build and the resolved decisions log."
type: reference
status: active
apps: [backend, customer, admin, rider]
module: "architecture"
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Food Ninja — Architectural Principles

This file holds the **long-horizon decisions** that shape every implementation choice. Source: senior architectural review + additions for delivery-app-specific gaps.

**How to use this file:**
1. Before any non-trivial task, scan for relevant principles.
2. If a task contradicts a principle here, **STOP and warn the user** with: the principle, the specific contradiction, and the suggested resolution.
3. If a principle is missing or needs revision, propose the update before doing the work.
4. Litmus test for every architectural decision: *"Will this help or hurt the app as the delivery business becomes more complex?"*

**Tags:**
- **[SHARED]** — applies to frontend, backend, or the boundary
- **[FRONTEND]** — frontend only
- **[BACKEND]** — backend only

This file is split into 3 parts (each under ~400 lines) plus this index:

| Part | Covers |
|---|---|
| [Part 1](principles-part1-cart-vertical-perf.md) | Core Insight + Principles 1-7 — cart/order/checkout as one domain, food as a vertical, generic home sections, ID-only navigation, local-first cart, checkout re-validation, high-frequency-screen perf |
| [Part 2](principles-part2-admin-realtime-typedrift.md) | Principles 8-14 — admin plan (web primary), cross-cutting concerns, error-class UX, mutation idempotency, real-time order updates, force-update mechanism, frontend/backend type-drift prevention |
| [Part 3](principles-part3-hardening-stage-decisions.md) | Principles 15-20 — production hardening, interruptible/resumable flows, backend-owned availability, orders as future cart sources, ephemeral search state, architecture-by-stage — plus "What NOT To Build," "Things That CAN Evolve Gradually," the Resolved Decisions Log, and Open Questions |
