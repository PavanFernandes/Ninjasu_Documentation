---
id: ADR-0013
title: "ADR-0013: Rider live GPS tracking uses REST + polling + client-side interpolation, not WebSocket"
summary: "Rider live GPS tracking uses REST polling plus client-side marker interpolation instead of WebSocket, since interpolation — not the transport — produces the smooth pin, keeping the write path transport-agnostic for later."
type: decision
status: accepted
apps: [rider, customer, backend]
module: rider-app
anchors: []
verified_against: ""
updated: 2026-07-12
---

# ADR-0013: Rider live GPS tracking uses REST + polling + client-side interpolation, not WebSocket

## Context

The rider app needs customer-facing live GPS tracking (watch the rider move on a map). The initial
rider plan (§6) proposed a STOMP **WebSocket** broadcast layer (`/topic/delivery/{id}/location`).
This directly contradicts **Principle 12** (user decision 2026-05-15): *"Push notifications +
polling. No WebSocket / live map tracking."*

Phase-0 competitor research (Swiggy/Zomato/Shadowfax, 2026-07-12) resolved the apparent conflict:
- The "smooth moving pin" that reads as professional comes from **client-side interpolation**
  (tweening the marker 300-500ms between updates using speed + heading), **not** from the WebSocket
  transport. Polling + interpolation looks identically smooth.
- WebSocket's only real advantages are lower latency and lower server cost at high concurrency.
  For delivery tracking, 5-10s latency is imperceptible, and single-town pilot volume makes poll
  cost trivial.
- On patchy small-town connectivity, independent polls are **more robust** than a WebSocket
  connection that drops and must reconnect.
- The rider-side write path is REST in both designs, so the customer-side read transport is
  swappable later with zero write-path change — low lock-in.

## Decision

Implement rider live tracking **within Principle 12**:
- Rider app posts GPS via REST `POST /api/riders/location` every 5-10s (adaptive: faster near
  pickup/drop, slower when stationary), payload carries lat/lng/timestamp/speed/**heading**.
- Customer app **polls** `GET /api/deliveries/{id}/location` every 5-10s while the tracking screen
  is foregrounded (stops on blur).
- **Client-side interpolation** (300-500ms tween via speed+heading) renders the smooth marker;
  last-known position + "location unavailable" shown after a staleness threshold (~2 min).
- **No WebSocket / STOMP for launch.** The write path is transport-agnostic so a WebSocket read
  layer can be added later without changing it.

## Consequences

- No new realtime infrastructure; horizontally scalable on the existing request/response stack;
  robust on flaky networks; ~5-10s latency (imperceptible for delivery).
- Reinforces Principle 12 rather than amending it; consistent with Principle 20 (Early stage —
  avoid Growth-tier infra).
- Poll load scales with concurrent active-delivery watchers. **Revisit trigger:** when concurrent
  watcher poll cost becomes material (second town / rider-idle scale), evaluate a WebSocket read
  layer behind the unchanged write path.
- Background-GPS survival on budget Android (foreground service, throttling, offline-queued
  batched uploads) is a mandatory engineering requirement of the write path, not optional.

## Enforced in

To build: `RiderController.postLocation`, `DeliveryController.getLocation` (backend); rider-app
location-tracking hook (poll + reanimated interpolation). Related: [ADR-0009](ADR-0009-pluggable-otp-auth.md),
principles.md #12, #20.

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
