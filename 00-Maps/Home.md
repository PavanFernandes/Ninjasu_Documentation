---
id: ""
title: "Ninjasu — Home"
summary: "Vault entry point — routes to each app's map of content and to the shared architecture, domain, backend, roadmap, and ops sections."
type: reference
status: active
apps: [backend, customer, admin, rider]
module: meta
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Ninjasu — Home

Start here. Pick the app you're working in, or go straight to a shared section if you already
know what you need.

## By app

- [Customer App MOC](Customer-App-MOC.md) — Food-Ninja-Frontend
- [Web App MOC](Web-App-MOC.md) — Ninjasu_Web (admin + shop dashboards, marketing, guest)
- [Rider App MOC](Rider-App-MOC.md)
- Backend is shared — see **By shared layer** below, all of it applies.

## By shared layer

- [Architecture](../01-Architecture/principles.md) — long-horizon principles, tagged
  `[SHARED]` / `[FRONTEND]` / `[BACKEND]`
- [Decisions (ADRs)](../01-Architecture/decisions/README.md) — why things are the way they are
- [Domain rules](../02-Domain/README.md) — menu, cart, wishlist, core, captain-ordering, guest-ordering —
  true for every client
- [Backend contracts](../03-Backend/auth-and-security.md) — API shape, auth, data model
- [Roadmap](../07-Roadmap/README.md) — backlog, in-progress designs, pending flags
- [Ops](../08-Ops/docker.md) — deploy, signing, docker

## Meta

- [How this vault works, how to record something new](../README.md)
- [Maintenance guide — drift triggers, `/sweep`, code↔doc IDs](../90-Meta/maintenance-guide.md)
