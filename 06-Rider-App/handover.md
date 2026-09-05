---
id: ""
title: "Ninjasu Rider App — Handover"
summary: "Non-technical handover explaining what the rider app is, its end-to-end delivery flow, what is built vs not, key silent-failure risks, and locked decisions not to reopen."
type: reference
status: active
apps: [rider]
module: "rider"
anchors:
  - { repo: "Ninjasu_Rider_App", path: "app" }
  - { repo: "ninja delivery service java", path: "src/main/java/com/example/ninja/service/impl/DeliveryServiceImpl.java" }
  - { repo: "ninja delivery service java", path: "src/main/java/com/example/ninja/listener/DeliveryDispatchListener.java" }
  - { repo: "ninja delivery service java", path: "src/main/java/com/example/ninja/listener/DeliveryRiderNotificationListener.java" }
verified_against: "cc1ce62"
updated: 2026-08-06
---

# Ninjasu Rider App — Handover

> ✅ **2026-08-06 — DELIVERY_ASSIGNED/REVOKED device-verified on a real phone, same day as
> deploy.** [ADR-0019](../01-Architecture/decisions/ADR-0019-dispatch-mode-vs-delivery-mode.md)'s assign/revoke push notifications were
> confirmed working end-to-end (direct assign, direct cancel, AND the order-tab decline cascade —
> the case that matters most) on a real Android device, watched directly by the account holder.
> Live testing also found and fixed 2 real bugs same-day: a notification-channel registration gap
> (affected the pre-existing `order-updates` channel too, not just new work) and a 500 on
> order-decline that masked an already-successful state change. Both fixed, deployed, re-verified.
> **Still genuinely unverified: the full broadcast→accept path** — needs a `dispatchMode=BROADCAST`
> shop with a zoned/online `PLATFORM`-type rider, which the test shop used this round (MANUAL/NONE)
> couldn't exercise. That loop has never run on a real device across this feature's entire history.
> Full trail: `project_rider_assign_notification_plan` (memory — not a vault file).

**Read this first.** It explains what the project is, how it works in plain language, what is
already built, and what is not. It assumes no prior context.

- **What to build next, and in what order:** [implementation-roadmap.md](./implementation-roadmap.md)
- **Technical review findings + open design questions:** [rider-dispatch-phase3-plan.md](./rider-dispatch-phase3-plan.md)
- **Where a specific file lives:** `Food-Ninja-Frontend/skills/code_map.md` (the file-finder — this
  vault deliberately does not duplicate file locations)

> **Working split.** Planning, costing, and tool/vendor decisions are **not** part of this handover
> — those stay with Samivan. This document and the roadmap are written so the implementer never has
> to make an architectural or spend decision alone. If a task feels like it needs one, it is
> mis-scoped: stop and escalate rather than deciding.

---

## 1. What this project is

Ninjasu is a food-delivery platform. It is **four codebases sharing one backend and one database**:

| Repo | What it is | Who uses it |
|---|---|---|
| `ninja delivery service java` | Spring Boot backend + Neon Postgres | everyone (the only source of truth) |
| `Food-Ninja-Frontend` | React Native app — customer + shop-owner in one | customers, restaurant staff |
| `Ninjasu_Web` | Next.js web — platform admin + shop dashboard | Ninjasu admins, shop owners |
| `Ninjasu_Rider_App` | React Native app — **this project** | delivery riders |

The rider app is the newest and least finished of the four. It does not contain business rules of
its own; the backend owns all logic and the app renders what the API returns.

### Two kinds of rider (this distinction drives everything)

- **Restaurant rider** — belongs to one specific shop's own fleet. Only ever delivers for that shop.
- **Platform rider** — a Ninjasu-wide rider. Reaches shops only by being placed in a **delivery
  zone** that contains those shops.

A **delivery zone** is a named group of shops (for example "HSR Zone"). Admins put shops into a zone
and put platform riders into the same zone. That membership is what decides whose phone rings.

**Two independent settings exist on the shop side** (as of ADR-0019, 2026-08-06 — this used to be
one conflated setting, corrected below):
- **Delivery mode** (`SELF` / `PLATFORM` / `NONE`) — *who* the eligible riders are. `SELF` = the
  shop's own fleet only. `PLATFORM` = own fleet **plus** riders in a zone covering the shop.
- **Dispatch mode** (`MANUAL` / `BROADCAST`) — *how* dispatch reaches them. `MANUAL` = staff pick a
  rider by hand (works for either delivery mode). `BROADCAST` = automatic, every eligible online
  rider's phone rings at once, first to accept wins.

A `SELF` shop can now be `BROADCAST` — its own fleet's phones ring automatically without the shop
having to (mis)represent itself as `PLATFORM` and share orders with the shared rider pool. Staff can
always fall back to manually calling a rider (the "see & call" list), regardless of dispatch mode.

---

## 2. How the app works — plain-language flow

No technical terms. This is the flow to walk a new person through, and it is also the exact
end-to-end test in Phase 1 of the roadmap.

**Getting started (once per rider)**
1. Rider installs the app and enters their phone number.
2. They get a 4-digit code and type it in. *(In development the code is always `1234`.)*
3. First time only: they fill in vehicle details (type and registration number).
4. They land on the home screen.

**A normal working shift**
5. Rider taps a toggle to go **online** — this is them saying "I'm available for work."
6. Meanwhile, a customer somewhere orders food. The restaurant accepts it and starts cooking.
7. When the food is packed, restaurant staff mark the order **Ready**.
8. **Every** available rider who covers that restaurant gets a notification at the same time — their
   phones ring with the shop name, how many items, and how much cash to collect.
9. The **first** rider to tap **Accept** gets the job. Everyone else who taps a moment later sees
   "Already taken" — nobody can double-book an order.
10. The rider who won sees the pickup address, the drop address, and the customer's name and phone.
11. Rider drives to the restaurant and taps **Picked Up**. At this moment the system generates a
    4-digit delivery code and shows it to the *customer* in their app.
12. Rider taps **Out for Delivery** and drives to the customer.
13. At the door: the customer reads out their 4-digit code, the rider types it in. This proves the
    rider actually reached the right person.
14. Rider enters how much cash they actually collected, and taps complete. If the amount is short,
    they must give a reason — but **they are never blocked from finishing**. The shortfall is flagged
    for office staff to sort out later.
15. Delivery done. The order shows as delivered in the customer's app automatically.

**When things go wrong** — office staff can reassign a delivery to a different rider, cancel it, or
force-complete it (for example if the customer's phone is dead and the code can't be read out).

### The one thing to understand about step 8

The notification goes to **everyone at once**, and whoever taps first wins. This is deliberate and
simple. It means the *fastest* rider wins, not necessarily the *closest* one — which is fine with a
handful of riders per zone, and becomes a real problem past roughly five. That threshold is recorded
in the roadmap as the trigger to revisit it. **Do not redesign this without asking.**

---

## 3. What is already built

Nearly all of the core loop exists in code. The important caveat is in §4.

**Backend — complete and committed for the whole rider lifecycle**
- Rider signup that never rejects an existing phone number (so a customer can also become a rider)
- Rider profile, go-online/offline, vehicle registration
- Delivery zones, rider types, and the rule deciding whose phone rings
- Automatic dispatch when an order becomes Ready
- Rider accept, with genuine protection against two riders taking the same order
- Status progression, delivery-code generation, cash collection with shortfall flagging
- Office-staff paths: reassign, cancel, force-complete, cash reconciliation
- Order and delivery status kept in step automatically, in both directions (including: cancelling
  an order terminates a live delivery)
- **(2026-08-06)** `dispatchMode` (MANUAL/BROADCAST, independent of delivery mode — ADR-0019) +
  `DELIVERY_ASSIGNED`/`DELIVERY_REVOKED` rider push on staff assign/reassign/cancel, including the
  customer-cancels-the-order path, which previously terminated a delivery with no audit trail and
  no notification of any kind

**Rider app — the full loop has screens**
- Phone + code login, signup, vehicle registration
- Home screen with the online toggle and the rider's deliveries
- Incoming-offer screen that rings, with Accept / Dismiss and "Already taken" handling
- Active-delivery screen with status buttons and location sending
- Delivery-code + cash completion

**Web admin — built and committed**
- Manage riders and their type/shop
- Create and edit delivery zones, add shops and riders to them
- A panel showing shop staff which riders are online so they can phone them

**Customer app**
- Shows the 4-digit delivery code on the order screen (this was previously a blocker; it is fixed)

Quality note for whoever picks this up: the tricky concurrency parts were done carefully and
deliberately — the double-booking protection and the accept endpoint both contain non-obvious
choices that are correct. `code_map.md` records *why* for each, marked "don't 'fix' this." Read
those notes before touching them.

---

## 4. What is NOT built, and the honest status

### The single most important fact

**Steps 1-2 and 10-15 of the §2 journey are device-verified (2026-08-06) — steps 3-9, the actual
broadcast/ring/accept loop, are not.** A shop's staff manually assigning or cancelling a delivery
correctly rings the rider's phone and syncs status, confirmed on a real Android device, including
the order-decline cascade that used to fail silently. But **nobody has ever watched an order reach
Ready, watched every eligible rider's phone ring at once, and watched the first tap win** — that
specific loop (steps 3-9) has never run on a real device, at any point in this feature's history.
Do not treat "assign/cancel works" as evidence the broadcast loop works too — they share almost no
code path. Phase 1 of the roadmap exists to establish that the broadcast loop actually works.

### Not built at all

| Gap | Consequence today |
|---|---|
| **Customer cannot see the rider on a map** | The rider sends their location and the backend serves it, but no screen anywhere displays it. Live tracking effectively does not exist for the customer. |
| **Location only sends while the app is open and on screen** | A rider who pockets their phone stops transmitting. Since that is what riders normally do, tracking is unusable in practice until this is fixed. Needs a proper background service, which needs a special build of the app. |
| **No rider ID** | Riders are identified by a long internal code that cannot be read aloud on a support call. |
| **No earnings screen** | Riders cannot see what they have earned. Deliberately parked — the payout formula has not been decided, so there is nothing to display yet. |
| **"Missions" wording** | The plan is to call deliveries "missions" in the rider app for the ninja theme. Not done. Cosmetic only. |
| **Assigning zones from the shop's own page** | Admins can add shops to a zone, but cannot open a shop and set its zones. Same data, missing direction. |

### Risks that are worse than missing features

These are things that *look* like they work but fail silently. They are the priority.

1. **A shop set to PLATFORM but not placed in any zone does nothing at all.** Orders reach Ready, no
   phone ever rings, and the only trace is a line in a server log. The shop appears fully configured.
   This will happen during a demo.
2. **"All riders ignored it" is indistinguishable from "no riders online."** Dismissing an offer
   writes nothing anywhere, so if every rider ignores an order it simply sits at Ready with nobody
   alerted.
3. **Riders carry unlimited platform cash.** Cash is recorded and reconciled afterwards, but nothing
   stops one rider accumulating a large amount across many deliveries before depositing any of it.
   Every control is after-the-fact. This is a money-loss risk, not a technical one.
4. **The loud ring may quietly become a normal notification.** An Android policy change (January
   2025) restricts full-screen alerts to phone/messaging/alarm apps. A delivery app does not
   qualify, and the system downgrades silently rather than reporting an error.
5. **"Online" is an unverified self-declaration.** No heartbeat, no idle location, no record of who
   accepts or ignores work. Staff can be shown a rider who is asleep.
6. **A zone has no geographic boundary.** It groups shops, so it controls where a rider *picks up*
   but nothing limits how far the *drop-off* can be.

### ⚠️ Version control — this section is stale, now resolved

This used to warn that `Ninjasu_Rider_App` was entirely untracked. As of 2026-08-06 the repo has
real history on `main` (multiple merged PRs, most recently the dispatchMode/notification work
above) — it is no longer a single-commit, uncommittable-loss risk. Roadmap Phase 0 ("save the
work") can be considered done; not independently re-verified whether `.env`/secrets are correctly
gitignored, so still worth a quick look before assuming that specific detail is clean.

---

## 5. Decisions already locked — do not reopen

The implementer should treat these as settled. Each was decided deliberately, and re-litigating them
wastes time.

- **A delivery is never edited, only replaced.** Reassigning keeps the old record as history and
  creates a new one. Never mutate a delivery in place.
- **The notification goes to everyone; first to accept wins.** Not one-at-a-time offers, no queue,
  no ranking. Revisit only past ~5 riders per zone.
- **Nothing is written to the database until a rider accepts.** There is no "offered" state.
- **Live location is fetched by polling, not a persistent connection** (ADR-0013).
- **The delivery code proves the rider arrived — it does not prove the cash was right** (ADR-0014).
  A short payment still completes and gets flagged; it must never trap the rider.
- **One on-duty device per rider** (ADR-0015).
- **Riders are not shop staff.** They are never invited through the shop team screen.
- **"Missions" is display text only.** Never rename anything in the API, database, or code.

---

## 6. Where to look things up

| Question | Go to |
|---|---|
| Where is the file that does X? | `Food-Ninja-Frontend/skills/code_map.md` |
| What should I build next? | [implementation-roadmap.md](./implementation-roadmap.md) |
| Why was this designed this way? | [Decisions index](../01-Architecture/decisions/README.md) — ADR-0013/0014/0015/0019 are the rider ones |
| What are the known risks in detail? | [rider-dispatch-phase3-plan.md](./rider-dispatch-phase3-plan.md) §9 |
| What did the competitor/business review find? | `Ninjasu_Rider_App/agents/market/rider-dispatch-scout.md` |
| What rules apply to every app? | [`../01-Architecture/principles.md`](../01-Architecture/principles.md) |
| How does the backend talk to apps? | [`../03-Backend/auth-and-security.md`](../03-Backend/auth-and-security.md) |

**House rules that matter on day one**
- The backend is the only source of truth. Never re-implement a pricing, discount, or validation
  rule in the app — render what the API returns.
- One HTTP client per app. Never write a second fetch wrapper.
- Never put a font family in a stylesheet — use the shared text component.
- Features must not import from each other; share through the store or shared folder.
- Colours come from the constants file, never hard-coded.
