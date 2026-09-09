---
id: ""
title: "Spatial Table View (Floor Map) — Vision"
summary: "Vision for a top-down floor-plan view of tables alongside the existing grid, with the v1 scope line that keeps it a quick win and the data model that leaves 3D open."
type: how-to
status: designing
apps: [backend, web, customer]
module: "roadmap"
anchors: []
verified_against: ""
updated: 2026-09-05
---

# Spatial Table View (Floor Map) — Vision

> **Picked up 2026-09-06.** Full build plan, devil's-advocate findings, and phases:
> `Food-Ninja-Frontend/skills/agents/arch-notes/floor-map-FINAL.md`.

## Problem

The Floor board currently renders tables as a uniform grid. A grid is fine for counting state but
it does not match the room: a captain reads *labels* rather than recognising a *place*. Arranging
tables is an inherently spatial task, and the grid gives the owner no way to express their actual
layout.

Two jobs:

1. **Table setup** (the primary one) — the owner lays out their room once. Spatial editing is the
   natural fit for a spatial task, and setup is a **calm, low-pressure moment**, not mid-service.
2. **Demo value** — nothing in the category photographs like a real floor plan. It is the strongest
   single visual differentiator available cheaply.

## Design

A **Grid / Map toggle** on the Floor tab. Grid stays exactly as it is — the map is additive, so no
existing flow changes and there is no migration risk.

Tables gain layout attributes:

```
table: x, y, seats, shape, floor
```

> **Supersession (2026-09-06):** grouping uses the existing `ShopTable.area` field, not a new `floor`
> column. `area` already exists in the entity/DTO/setup form; adding `floor` alongside it would give
> owners two overlapping free-text grouping fields that could drift (map groups by one, the table list
> by the other). `seats` was also dropped from v1 — no consumer exists yet (`covers`, the actual guest
> count, already renders elsewhere); it can be added later at zero cost. Full build plan:
> `Food-Ninja-Frontend/skills/agents/arch-notes/floor-map-FINAL.md`.

Colour/state semantics on the map are identical to the grid (available / occupied / ready to serve /
no order). A floor selector handles multi-floor venues.

## The v1 scope line — this is what keeps it quick

**v1 is: drag a table, save x/y. That is all.**

What turns this from a week into a month, and is therefore **out of v1**:

- Editable room furniture — walls, doors, counter, plants
- Rotation, resizing, snapping, collision detection
- Arbitrary table shapes beyond a small fixed set

**The room itself ships as a static background image per floor.** The plants, counter and doorway in
the mockup are decoration, not objects. The moment the owner can move the counter, this has become a
level editor rather than a table layout tool.

## 3D is not foreclosed

An earlier idea was a 3D floor view (including animated staff movement). The judgement:

- 3D aimed at **service time** is delight at the wrong moment — anything costing a captain's
  attention while busy is hostile.
- 3D as a **setup/dashboard** surface is defensible, and that is how it would be reached.

The layout data (`x, y, seats, shape, floor`) is **identical either way**, so shipping 2D first is a
rendering decision, not a rebuild. Nothing is lost by starting flat, and the demo value arrives
immediately.

## Where "fun" belongs

Related principle from the same discussion, worth recording because it generalises:

> **Put delight where there is slack, not where there is pressure.**

Service-time surfaces should cost zero attention. The natural pauses — a table settling, end of
shift, close of day — are wide open: a staff recap ("you served 34 covers today"), a restaurant
record broken ("best Saturday yet — 142 covers"), a satisfying KDS ticket clear.

Strategic note: **the waiter decides whether a restaurant keeps using the software.** Every POS is
designed for the owner who buys it; being the one staff actually like is uncontested ground and is
continuous with what Ninjasu already does well.

## Open questions

1. Does the captain **mobile** app render the map, or is it web-only? (Mobile's constraint is
   different — see the mobile note in [pricing-and-positioning.md](pricing-and-positioning.md).)
2. Who can edit the layout — admin-tier only, presumably, matching the POS role model.
3. Is the background image uploaded per floor by the shop, or chosen from presets?

## Related

- [../02-Domain/captain-ordering.md](../02-Domain/captain-ordering.md) — the Floor board this extends
- [pricing-and-positioning.md](pricing-and-positioning.md) — why this ranks where it does
- [vision-inventory-module.md](vision-inventory-module.md) — the other current vision item
