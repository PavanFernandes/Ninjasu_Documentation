---
id: ""
title: "Captain Ordering — Dine-in POS + Kitchen Display (KDS)"
summary: "Full spec for dine-in ordering: Check/KOT model, the 7 locked decisions, data model, API, frontend spec, phased delivery status, and devil's-advocate risk register, split into 3 parts."
type: domain
status: active
apps: [backend, customer]
module: "captain-ordering"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/controller/PosOrderController.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/controller/PosSetupController.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/TableCheckService.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/PosOrderService.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/PosOrderServiceImpl.java" }
  - { repo: customer, path: "app/(shop)/dinein.tsx" }
  - { repo: customer, path: "src/features/pos/components/PosLauncherScreen.tsx" }
  - { repo: customer, path: "src/features/pos/services/pos.service.ts" }
  - { repo: customer, path: "src/features/pos/types.ts" }
verified_against: "backend@ff5ade334891238d16b8010e372fdbbc502c193e customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-07-11
---

# Captain Ordering — Dine-in POS + Kitchen Display (KDS)
## Full Specification & Build Plan

**Branch:** `feature/captain-ordering` (frontend + backend)
**Date:** 2026-07-10
**Status:** Model locked, verified against code, devil's-advocate passed. Ready to break into build tickets.
**Skills applied:** architect · market (scout + GTM) · ui_engineer · error_audit · api_contracts · devils-advocate.
**Related docs:** `agents/arch-notes/decisions.md` (decision record) · `agents/sales-docs/captain-ordering-sales.md` (GTM brief) · `agents/innovation/backlog-ideas.md` (deferrals).

> See [ADR-0012](../01-Architecture/decisions/ADR-0012-captain-ordering-dine-in-pos-kds.md) for the architecture decision this spec implements.

---

## 0. Executive summary

We are adding a **restaurant-facing ordering mode** to Food Ninja: shop staff take a table's order
on the app, it appears on the kitchen's screen instantly, every additional round stays on one
running bill, and the waiter is pinged the moment food is ready to serve. It is the well-known
**POS + KDS** (Point-of-Sale + Kitchen Display System) pattern — the same thing Petpooja's Captain
App does — but built as an **extension of Food Ninja's existing order engine**, not a new system.
The core modelling choice: a dine-in table is a **Check** (a mutable running tab), and each round of
ordering is an **immutable KOT** (kitchen order ticket) that is just an `Order` tagged
`order_type=DINE_IN`. Payment is recorded on the check. Delivery is untouched.

---

## 1. The goal

Let a restaurant run its **in-house dining and counter takeaway** on the same app it already uses
for delivery — turning Food Ninja from a delivery channel into the restaurant's **operating system
for every order**, regardless of where the order comes from.

Concretely, after this ships a restaurant can:
- Give a waiter a phone that takes orders at the table and sends them straight to the kitchen.
- Show the kitchen a live screen of tickets to cook, with a one-tap "ready" bump.
- Keep every round of a table's meal on one bill and settle it in a tap.
- See dine-in and takeaway sales **separately** from delivery.

---

## 2. The real-world problem we're solving

**Today, in a typical small/mid Indian restaurant, dine-in ordering is paper and shouting.**

1. A waiter writes the order on a paper pad (a "KOT").
2. He walks it to the kitchen, or calls it out. Tickets get **lost, misread, or delivered late**.
3. The kitchen has **no way to tell** that the second round of naan belongs to the same table as
   the first — so items get duplicated, missed, or made for the wrong table.
4. When the food is ready, someone **shouts for the waiter**, who may be across the floor.
5. At the end, the bill is **added up by hand** from the scattered paper — slow and error-prone.
6. If the restaurant also uses a delivery app, that's a **second, disconnected system** — dine-in
   and delivery numbers never live in one place.

Each of these is a concrete cost: lost tickets = remade food = wasted stock; late tickets = slow
tables = fewer covers per night; hand-added bills = math errors and disputes; disconnected systems
= no single view of the day's revenue.

**The industry-standard fix is POS + KDS.** The waiter's order enters in a standard digital format,
transmits instantly to a kitchen screen (no printing, no shouting), the kitchen bumps each item
when done which pings the front-of-house, and every order — dine-in, takeaway, delivery — flows into
**one queue labelled by type**. This is a solved pattern, which is exactly why it's low-risk to
build on our existing model.

> **Grounding / sources:** [Petpooja Captain App](https://www.petpooja.com/poss/captain-ordering-app)
> (the direct Indian analog — steward takes the order at the table, KOT auto-sent to kitchen, bill
> settled at the table), [Toast KDS](https://pos.toasttab.com/hardware/kitchen-display-system) and
> [Restaurant365's KDS guide](https://www.restaurant365.com/blog/kitchen-display-system/) (single
> queue labelled by order type; bump → ready), [Eat App](https://restaurant.eatapp.co/pay-at-table)
> / [sunday](https://sundayapp.com/) (pay-at-table QR — deferred to our backlog).

**Why this is an extension, not a rebuild:** Food Ninja already has `Order` / `OrderLine` /
`OrderLineAddon`, a `PLACED→ACCEPTED→PREPARING→READY` status machine, `UserShop` staff membership
(OWNER/MANAGER/STAFF), a `PriceCalculator`, and an FCM notification listener that *already rings
every shop member on a new order*. The captain flow reuses all of it.

---

## 3. Who it's for (personas)

| Persona | Role in the system | What they do |
|---|---|---|
| **Owner / Admin** | `OWNER` membership | Turns the feature on (`pos_enabled`), sets up the table list, sees all sales. |
| **Manager** | `MANAGER` membership | Everything a waiter does + table setup; later: discounts/comps. |
| **Waiter / Captain** | `STAFF` membership | Opens a table's check, fires KOTs, serves, records payment. The primary user. |
| **Kitchen** | any member on the KDS device | Watches the live ticket board, taps Start / Ready. |
| **Guest** | walk-in (not a platform user) | Sits, orders via the waiter — or scans the table's QR to order themselves, gated on a one-time staff approval per table-session. See [`guest-ordering.md`](guest-ordering.md) (built 2026-08-03, separate from this spec's original scope). |

---

## 4. A day in the life (end-to-end walkthrough)

1. **Seat.** A party of 3 sits at Table 7. The waiter opens Food Ninja's floor board, taps the green
   **T7** tile, sets covers = 3 (optional), and a **Check** opens for T7.
2. **First round.** He taps 3 drinks and 2 starters, hits **Fire KOT**. `KOT #1` is created as an
   immutable `Order` under T7's check and instantly appears on the **kitchen screen**.
3. **Cook.** The kitchen taps **Start** (→ PREPARING), then **Ready** (→ READY). The waiter's phone
   buzzes: *"T7 ready to serve."* The T7 tile shows a green "ready" badge.
4. **Serve.** He serves and taps the KOT **Served**.
5. **Second round.** The table wants mains + more naan. He opens T7's check, taps **＋ Add items**,
   fires `KOT #2`. The kitchen sees *"T7 · KOT 2"* — unambiguously the same table, a new ticket.
6. **Bill.** After the meal he taps **Record payment**, picks **UPI**, confirms. The check sums
   KOT 1 + KOT 2 into one total, marks paid, and **closes**. T7 goes green (free) again.
7. **Reporting.** That sale lands in the day's numbers tagged **DINE_IN**, kept separate from
   delivery.

Takeaway is the same, minus steps 1 and 4–6's table: the counter staff fires a single KOT tagged
`TAKEAWAY`, the kitchen makes it, it's marked collected, payment recorded.

---

## 5. What success looks like · Non-goals

**Success metrics (post-launch):**
- Time from "waiter takes order" to "kitchen sees it": from minutes (walk/shout) to **seconds**.
- Zero lost tickets; every add-on round correctly attributed to its table.
- Dine-in + takeaway revenue visible **separately** from delivery in the shop's own numbers.
- A waiter can fire a KOT in **under ~20 seconds** and few taps.

**Non-goals for this feature (explicitly out of scope — see backlog §14):**
- Money movement / payment gateway, printed GST bill, QR pay-at-table, split bill.
- Guest self-ordering via QR — now built as its own feature, see [`guest-ordering.md`](guest-ordering.md); was designed-for but out of scope when this spec was written.
- Delivery "add to order" (Blinkit-style), rider app, kitchen-station routing, offline mode,
  move/merge tables, discounts/comps.

---

This spec is split into 3 parts (each under ~400 lines) plus this index/overview:

| Part | Covers |
|---|---|
| [Part 1](captain-ordering-part1-decisions-and-concepts.md) | §6-7 — the 7 locked decisions (D1-D7) and the Check/KOT/cover/floor-board/KDS glossary, incl. reference- and serial-number schemes |
| [Part 2](captain-ordering-part2-data-model-and-api.md) | §8-12 — data model (new tables + `Order` changes), status lifecycles, auth/role gating, notifications, and the full REST API contract |
| [Part 3](captain-ordering-part3-frontend-and-delivery-plan.md) | §13-17 — frontend/UI spec, phased delivery plan with build status, devil's-advocate risk register, open items, and appendix |
