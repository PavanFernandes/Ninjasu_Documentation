---
id: ""
title: "Architectural Principles, Part 3 — Hardening, Resilience & Stage (Principles 15-20)"
summary: "Principles 15-20: pre-launch backend hardening list, interruptible/resumable flows, backend-owned availability, order-as-future-cart-source, ephemeral search state, and staged architecture, plus the resolved decisions log."
type: reference
status: active
apps: [backend, customer]
module: "architecture"
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Architectural Principles, Part 3 — Hardening, Resilience & Stage (Principles 15-20)

> Part of [principles.md](principles.md) — see that index for the other parts and how to use this file.

## 15. Production Hardening — Backend [BACKEND]

These exist in the current backend and **must be fixed before production launch**. Flag any task that ships before these are fixed:

- ❌ OTP hardcoded to `"1234"` — integrate real SMS provider
- ❌ DB credentials in `application.properties` — move to env vars, scrub git history
- ❌ JWT secret is a default base64 value — generate per-environment secret
- ❌ **No shop ownership enforcement** in any shop/menu/addon controller — any JWT user can edit any shop today. Add `@PreAuthorize` or in-service ownership checks.
- ❌ `ddl-auto=update` in production — switch to Flyway/Liquibase migrations
- ❌ No rate limiting on `/auth/send-otp` — vulnerable to OTP spam / SMS cost attack

---

## 16. Flows Must Be Interruptible And Resumable [SHARED]

Delivery apps operate under constant interruptions: app backgrounding, poor network, payment retries, session restoration.

For every critical flow (cart, checkout, payment, active order), ask before building:
- **What happens if the user leaves halfway and returns later?**
- **Can this flow resume from where it left off?**
- **Is the user's intent preserved across backgrounding or network loss?**

If the answer to any of these is "start over," the state model needs work. This especially affects checkout and active orders — getting it wrong means lost orders and lost revenue.

---

## 17. Availability Is A Backend Decision — Frontend Only Renders [SHARED]

Delivery apps are constrained by: shop open status · delivery range · item stock · kitchen hours · preparation time.

These are **business constraints**, not UI conditions.

- **Backend decides:** whether ordering is allowed, whether delivery is possible, whether an item is purchasable.
- **Frontend only renders:** availability states, disabled UI, fallback messaging.

Never infer availability on the frontend. Never grey out a button because frontend logic "thinks" the shop is closed. Ask the backend.

---

## 18. Orders Are Future Cart Sources — Not Just History [SHARED]

Most delivery platforms eventually become **reorder platforms**, not exploration platforms. Habit beats discovery.

### [BACKEND]
The order model must preserve:
- Item names, images, descriptions **at the time of order** (snapshots — items get renamed/deleted)
- Exact pricing at time of order
- All selected addons/modifiers
- Shop reference

### [FRONTEND]
Reorder reconstructs a cart from a past order, then revalidates against current availability before checkout.

**Rule:** Never design the order entity as "historical display only." It is both an operational record and a future intent signal.

---

## 19. Search State Is Ephemeral — Never Global [FRONTEND]

Search state is query-scoped and UI-driven. It does not belong in global Zustand store.

- Search query, results, loading state → local to the search screen
- Recent searches → persisted locally (AsyncStorage), not in global store
- Ranking, relevance, personalization → backend concerns, frontend just renders what the API returns

---

## 20. Architecture By Stage [SHARED]

We are currently in **Early Stage**. Do not apply patterns from later stages.

| Stage | What to prioritize | What to avoid |
|---|---|---|
| **Early (now)** | Funnel reliability · dev speed · clean state ownership · performance on hot screens | Plugin systems · offline sync · over-generalization · microservices thinking |
| **Growth** | Maintainability · observability · feature flags · role/permission enforcement · error monitoring | Deep abstraction layers · internal frameworks |
| **Scale** | Experimentation · personalization · server-driven rendering · richer caching | Only introduce if operational scale truly demands it |

**Rule:** When someone proposes a pattern, identify which stage it belongs to. If it's a Growth or Scale pattern and we're in Early, flag it.

---

## What NOT To Build — Premature For Current Stage

Flag and refuse if asked without explicit user-approved trigger:

- ❌ Multi-vertical abstraction (build food concretely first)
- ❌ Offline-first / sync engine
- ❌ Generic CMS-driven UI
- ❌ Micro-frontend / module federation
- ❌ Custom navigation abstraction over Expo Router
- ❌ Custom state management (Zustand + TanStack Query is enough)
- ❌ Recommendation engine on frontend (backend concern)
- ❌ Premature component library extraction

---

## Things That CAN Evolve Gradually (Reversible)

- Individual screen internals
- Component extraction (do it as files grow)
- Adding hooks, utils, services
- TanStack Query adoption (incremental)
- Folder reorganization within a feature
- Design token refinement

---

## Resolved Decisions Log

Decisions made on 2026-05-15:

| # | Decision | Implication |
|---|---|---|
| Cart model | **Per-vertical:** restaurant = one-shop; grocery = multi-shop | Cart domain layer dispatches rules by vertical; "one shop only" is NOT a core cart rule (principle 1) |
| Grocery timeline | **6–12 months after restaurant launch** | Build food concretely now, but write code so restaurant-specific assumptions are pluggable (principle 2) |
| Real-time orders | **Push + polling** (no WebSocket / live map) | FCM/APNs + foreground polling on active-order screen (principle 12) |
| Admin app | **Web is primary, mobile is minimal subset** | Mobile admin gets bare-minimum on-the-go features only; web (separate project) gets full feature set; backend enforces strict role/ownership (principle 8 + 15) |

## Open Questions

None outstanding. Add new entries here as they arise.
