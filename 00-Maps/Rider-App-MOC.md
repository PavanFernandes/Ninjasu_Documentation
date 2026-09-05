---
id: ""
title: "Rider App — Map of Content"
summary: "Hub note for Ninjasu_Rider_App — build/verification status, where to debug dispatch notifications, and rider-specific ADRs."
type: reference
status: active
apps: [rider]
module: "meta"
anchors:
  - { repo: "Ninjasu_Rider_App", path: "app" }
verified_against: "07d0f59"
updated: 2026-07-30
---

# Rider App — Map of Content

**Ninjasu_Rider_App** — React Native (Expo SDK 54) delivery-rider app, a client of the same shared
backend as the customer and web apps. **The core delivery loop is built but has never been run on a
real device.**

> **Status corrected 2026-07-30.** This MOC previously said the app "has not been built yet" — that
> was true when written (2026-07-11) and is now badly wrong. The repo, the code, and the backend
> lifecycle all exist.

## Start here

| If you are… | Read |
|---|---|
| Debugging "the rider got no notification" | [Dispatch triggers](../06-Rider-App/dispatch-triggers.md) — **the canonical answer to "when does a rider get notified?"**; six gates, walk them top-down |
| New to the project / taking it over | [Handover](../06-Rider-App/handover.md) — what it is, plain-language user flow, built vs not built |
| Picking up implementation work | [Implementation roadmap](../06-Rider-App/implementation-roadmap.md) — phased, split into decisions vs build tasks |
| Reviewing the design or its risks | [Phase 3 plan](../06-Rider-App/rider-dispatch-phase3-plan.md) — technical findings, §9 review table, open questions |
| Looking for a specific file | `Food-Ninja-Frontend/skills/code_map.md` — this vault does not duplicate file locations |

## Current state in one paragraph

Riders log in by phone + OTP, go online, and receive a ringing notification when a shop they cover
marks an order ready — **but only if that shop is in `BROADCAST` dispatch mode**; `MANUAL` shops
never auto-notify anyone and rely on staff assigning a rider by hand (see
[dispatch triggers](../06-Rider-App/dispatch-triggers.md)). Where it does apply, the notification
goes to **every** eligible online rider at once and the first to accept wins, protected by a
database constraint rather than application logic. The winner picks
up, the customer is shown a 4-digit code, and the rider completes the delivery by entering that code
plus the cash collected (a short payment is flagged, never blocked). Backend, web admin (riders +
delivery zones), and rider-app screens are all built and committed — **except** the rider app itself
is not yet in version control, and the customer-facing tracking map does not exist.

## Immediate priorities

1. **Commit the rider app** — every file is untracked; one cleanup command destroys it.
2. **Device-verify the loop** — nothing has run on a phone; treat "built" as unverified.
3. **Fix the silent failures** — a PLATFORM shop in no zone does nothing at all, and
   "all riders ignored it" is indistinguishable from "no riders online."

## Rider-specific decisions

- [ADR-0013 — live tracking uses polling, not WebSocket](../01-Architecture/decisions/ADR-0013-rider-live-tracking-poll-not-websocket.md) — still correct; the objection to polling was database load, which caching removes.
- [ADR-0014 — COD completion bundles the delivery code with cash, plus discrepancy control](../01-Architecture/decisions/ADR-0014-rider-cod-completion-cash-discrepancy-control.md) — the code proves arrival, **not** that the cash was right.
- [ADR-0015 — one active on-duty device per rider](../01-Architecture/decisions/ADR-0015-rider-single-active-on-duty-device.md) — structured in the data model but not yet enforced.
- [ADR-0016 — multi-client backend boundary](../01-Architecture/decisions/ADR-0016-multi-client-backend-boundary.md) — why rider endpoints are audience-prefixed.

## Shared foundations this app inherits

- [Backend contracts](../03-Backend/auth-and-security.md) — same API envelope, auth, and error shape as every client.
- [Domain rules](../02-Domain/README.md) — order lifecycle and delivery-address rules apply directly. The
  backend owns all business logic; the app renders what the API returns.
- [Architecture principles](../01-Architecture/principles.md) — read `[SHARED]` and `[FRONTEND]`.
- [ADR-0009 — pluggable OTP auth](../01-Architecture/decisions/ADR-0009-pluggable-otp-auth.md) —
  riders authenticate through the same OTP layer (dev provider: code is always `1234`).
- [ADR-0008 — saved delivery addresses](../01-Architecture/decisions/ADR-0008-saved-delivery-addresses.md)
  — note the address **book** is separate from the delivery-address snapshot taken on an order.

## Business / market context

`Ninjasu_Rider_App/agents/market/rider-dispatch-scout.md` — competitor benchmark, business-logic
loopholes (unbounded cash exposure, unverified availability, unmasked customer numbers), and the GTM
brief with internal demo red flags.
