---
id: ADR-0015
title: "ADR-0015: One active on-duty device per rider, claimed on Go Online"
summary: "Only the device that most recently tapped Go Online is a rider's active on-duty device, gating location posting, assignment acceptance, and delivery completion to prevent GPS ping-pong, double-completion, and accomplice-phone spoofing."
type: decision
status: accepted
apps: [rider, backend]
module: rider-app
anchors: []
verified_against: ""
updated: 2026-07-12
---

# ADR-0015: One active on-duty device per rider, claimed on Go Online

## Context

A rider is a `User` (`ROLE_RIDER`) + one `riders` profile row. The JWT is per-device, so a rider
can legitimately log in on two phones (both authenticate). With no rule, both devices act as the
same rider, which breaks three things:
1. **GPS truth ping-pongs** — both POST `/api/riders/location`; last writer wins, so a customer's
   pin teleports between two devices in different places.
2. **Double-completion race** — both devices could enter OTP + confirm cash on the same delivery.
3. **Fraud vector** — a second phone handed to an accomplice enables location spoofing while the
   rider is elsewhere.

Real driver/delivery apps do not allow dispatch on two devices at once.

## Decision

**One active on-duty device per rider, claimed on Go Online.**
- Both phones may be logged in (auth unchanged). Only the device that most recently tapped
  **Go Online** is "on duty."
- `riders.active_device_id` (references the existing per-device `DeviceToken`) is stamped on
  Go Online. No new "ride session" entity — active device is a field on the rider.
- **Duty actions** (location post, accept assignment, OTP + cash completion) are gated on
  `device_id == rider.active_device_id`. A superseded device receives `SESSION_SUPERSEDED` and
  drops to passive (may still view profile/earnings, cannot act).
- Going online on device B flips `active_device_id` to B and pushes A offline
  ("You're now online on another device").
- The duty slot is claimed by **Go Online**, NOT by login — a rider glancing at earnings on a
  second phone must not knock their working phone offline.

## Consequences

- Single GPS source of truth and single completion authority — eliminates ping-pong, the
  completion race, and the accomplice-phone spoof by construction.
- Reuses `DeviceToken` (already per-device, keyed to user) — no new identity/login system.
- The `SESSION_SUPERSEDED` response on the stale device flows through the same
  `useUserStore.clearUserData()` single session-end cascade (see memory
  `feedback_auth_single_persistence_owner`) — no separate logout path.
- Passive/view-only is an explicit device state the rider app must render.

## Enforced in

To build: `riders.active_device_id`; Go-Online handler (stamp + push-offline prior device); duty
guard on location/accept/complete endpoints. Related: [ADR-0013](ADR-0013-rider-live-tracking-poll-not-websocket.md),
[ADR-0014](ADR-0014-rider-cod-completion-cash-discrepancy-control.md), DeviceToken (push infra).

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
