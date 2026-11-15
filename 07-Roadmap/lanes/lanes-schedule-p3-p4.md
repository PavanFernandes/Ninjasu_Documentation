# Lanes — Schedule Phase 3 + Phase 4 + Eat Now payments

LOCKED 2026-11-15 (Samivan picked it in discussion). Skill: `/lanes`. Project facts: [lanes-profile.md](lanes-profile.md).
Every lane session reads this file first and updates only its own status and hand-off rows, with a targeted
Edit (both lanes edit this file; a whole-file Write would erase the other lane's update). Lane sessions do not
commit this file; the orchestrator commits it at each wave.

## What was picked, and why

- **Two lanes.** Lane 1 = backend + web, Lane 2 = app. Three lanes were proposed and dropped: too many PR streams.
- **Payments first in Lane 1.** E2c, then E3: E3 is the last code blocking the Eat Now manual-capture flag, and
  4.3 needs its "Confirming payment" component. Phase 4 does not wait: 4.1 and 4.2 do not need it.
- **One temporary app worktree**, only while Lane 1 builds E3 (both lanes then write in the app repo, different folders).
- **No second backend worktree** yet: nothing to run in parallel until the batch geld is done, and two Maven suites fight for CPU.
- **B2** (real UPI phone round) runs once, in wave 2, covering E3 + 4.3.

## Lanes

| Lane | Repos | Queue (in order, one slice at a time) |
|---|---|---|
| **1: payments, then ops board** | backend, Ninjasu_Web; app worktree for E3 only | L1.0 → E2c → E3 → 3.1 → 3.2 → 3.3 → 3.4 → 3.5 |
| **2: customer Schedule app** | Food-Ninja-Frontend (main checkout) | 4.1 → 4.2 → 4.3 → 4.4 |

Orchestrator (one Opus session, not a lane): open decisions, the batch geld, merge order, wave checks.

### Lane 1 slices

| # | Slice | Repo | Branch | Plan | Risk |
|---|---|---|---|---|---|
| L1.0 | **Proposed (needs Samivan's yes):** add a test job to backend CI (`./mvnw -B test -Dtest='!NinjaDeliveryServiceApplicationTests'`) so PRs stop relying on laptop runs | backend | `ci/backend-test-job` | this file | low |
| E2c | Detect a second captured payment on an Eat Now order; fetch, then order-aware refund by payment id (BUG-2, narrowed C4) | backend | `fix/eatnow-extra-capture-refund` | `eatnow-manual-capture-plan.md` DA: BUG-2, C4 | **money** |
| E3 | App "Confirming payment" state: CAPTURE_PENDING shows "Confirming payment", no Cancel or resume while pending. Build it as a shared component 4.3 reuses | app (worktree `Food-Ninja-Frontend-pay`) | `feature/eatnow-capture-pending` | same plan: phase E3, "Readers that change" | state |
| 3.1 | Web admin: Service areas page (modes, window, last call, slots, fees, packaging, advance days) + shop area assignment, on the existing `AdminServiceAreaController` / `AdminShopScheduleController` endpoints | web | `feature/schedule-admin-service-areas` | `schedule-implementation-order.md` Phase 3 row 3.1 | admin |
| 3.2 | Batches by group (`schedule_batches`, `schedule_batch_groups`, `batch_events`, `drop_points`) | backend | after geld | row 3.2 | state, **geld first** |
| 3.3 | `deliveries.batch_id` + `assignBatch` (needs 2d.7 merged; confirm first) | backend | — | row 3.3 | state |
| 3.4 | Ops board | web | — | row 3.4 | admin |
| 3.5 | Settlement export (XLSX) endpoint + web | backend + web | — | row 3.5; reads `SettlementReadService` | money read |

### Lane 2 slices

| # | Slice | Branch | Plan | Risk |
|---|---|---|---|---|
| 4.1 | Area bootstrap: `useScheduleContext`, Eat Now / Schedule switch, intro screen, no-area / paused / not-open / no-slot states | `feature/schedule-4.1-area-bootstrap` | `schedule-phase4-customer-app-plan.md` §3 | UI, **needs D3** |
| 4.2 | Slot-first menu, reason mapping, ADD → customize → `POST /api/cart/items` with `type=FOOD&fulfilment=SCHEDULE`, the three 409 dialogs | `feature/schedule-4.2-slot-menu` | §3 | UI + cart |
| 4.3 | Schedule cart + checkout + Razorpay (`timeout` = hold seconds), PRICE_CHANGED / LINE_UNAVAILABLE / UNRESOLVED_GROUP; reuses E3's component | `feature/schedule-4.3-checkout` | §3 + backend 4.0 notes | **money path (client)** |
| 4.4 | Cancel + group tie-in on the group screen | `feature/schedule-4.4-cancel` | §3 | state |

## File ownership

| Folder / file | Owner | Note |
|---|---|---|
| backend (all) | Lane 1 | Lane 2 raises a hand-off for any backend gap |
| Ninjasu_Web (all) | Lane 1 | |
| app `src/features/payments/**`, `src/features/orders/types.ts`, `OrderTrackingScreen.tsx`, `OrderStatusStepper.tsx`, `PaymentRecoveryBootstrap.tsx` | Lane 1 until E3 merges, then Lane 2 | 4.3 starts only after E3 merges |
| app home (`app/(tabs)/index.tsx` and its components), new `src/features/schedule/**`, `src/features/cart/**`, `src/store/useCartStore.ts`, routes in `app/` | Lane 2 | E3 needs a change here → hand-off |
| `Food-Ninja-Frontend/skills/code_map.md` | either, smallest possible edits | append rows; sync before PR |

## Merge order

- E3 before 4.3 (`ship after` on 4.3's branch once it exists).
- 4.1 → 4.2 → 4.3 → 4.4 in order. 3.2 → 3.3 → 3.4. 2d.7 before 3.3.
- Lane 1 and Lane 2 merges otherwise interleave freely; each lane syncs with `origin/feature/schedule` before every PR (`/ship`).

## Open decisions (orchestrator)

| # | Decision | Blocks | Recommendation |
|---|---|---|---|
| OD1 | D3: where the Eat Now / Schedule switch lives; HSR intro screen for the pilot? | 4.1 | **DECIDED 2026-11-15 (Samivan):** toggle in the Home hero; intro shown once, plus a "How it works" link above the delivery times to replay it; heading "When should we deliver?". Design: `schedule-phase4-app-design.html`; build plan: `schedule-phase4-app-implementation-plan.md` |
| OD2 | L1.0 backend CI test job | nothing (speed) | yes: the biggest saving, CI then runs the suite |
| OD3 | App CI (tsc + eslint + jest on PRs) as a Lane 2 slice before 4.1 | nothing (speed) | yes, small |
| OD4 | Batch schema geld | 3.2 | run in the orchestrator while Lane 1 builds E2c/E3/3.1 |
| OD5 | E3 wording and states (pending copy, what replaces Cancel) | E3 | settle at E3 start |

## Test tiers (from the profile)

| Tier | Here |
|---|---|
| Fast, per slice | backend touched test classes; web lint + tsc; app tsc + lint + jest on touched folders |
| PR | CI is compile-only (backend), lint + build (web), none (app). **Until OD2/OD3 land, the lane runs its repo's full test suite locally before the PR.** |
| Money / state | E2c, 3.2, 3.3: mutation run on the changed rule + Codex read-only review at the PR. E3, 4.3: jest for every state branch + Codex review |
| Wave | Wave 1 after E2c, E3, 3.1, 4.1, 4.2 merge. Wave 2 after 4.3, 4.4, 3.2-3.5. Each: Codex review of the combined diff, `/gcp judge quick`, device round (wave 2 = B2 UPI + E3 + 4.3 Razorpay `timeout`) |

## Hand-offs

| From | Need | Owner | Status |
|---|---|---|---|
| — | — | — | — |

## Status

| Slice | Lane | State | PR | Note |
|---|---|---|---|---|
| L1.0 | 1 | waiting on OD2 | | |
| E2c | 1 | merged 2026-11-15 (e1f613f into feature/schedule) | #93 | OD2 = no (local tests). Webhook-only trigger, route-split fails closed. Full suite 2639 (+1 tripwire fixed), 9/9 mutants killed, Codex x2. Open: customer summaries show extra refund; NULL-payment-id data audit |
| E3 | 1 | merged 2026-11-15 (6970837 into feature/schedule) | app #40 | Built in the main app folder, no worktree. Shared `PaymentConfirmingNotice` (`confirming` / `checking`), `isCapturePending()`. OD5: no action while pending, no client-side auto-cancel. jest 486 green, Codex reviewed. NOT device-tested (B2). Open: "Payment failed" title on a rejected checkout needs a backend error code; no help contact in the app; `OrderTrackingScreen.tsx` ~354 lines |
| 3.1a | 1 | plan FINAL 2026-11-15, ready to build | | backend `feature/schedule-3.1a-admin-area-reads` (read endpoint, slot delete guard, unassign DELETE, timing + shop-move locks, `expectedUpdatedAt`); plan: schedule-3.1-admin-service-areas-plan.md; money-adjacent state: mutation check per guard + Codex review at the PR |
| 3.1b | 1 | after 3.1a merges | | web `feature/schedule-admin-service-areas`; service areas page + slots + shop assignment (lane-plan scope; commission/audit/pricing not in this slice) |
| 3.2-3.5 | 1 | queued | | 3.2 waits on OD4 |
| 4.1 | 2 | merged | app PR #38 (9bd6536) | tsc, lint, 321 jest green; Codex review + /judge (focused, 7 lenses) done and fixed; device test pending (needs a seeded area); HomeScreen split deferred to the next Home change; OD3 app CI still unanswered |
| 4.2 | 2 | merged 2026-11-15 | app PR #39 (a225fcb into feature/schedule) | tsc, lint, 460 jest green; Codex review + /judge (full, ungraded: reuse and conventions lenses rejected twice) fixed; device test pending (needs a seeded area with a Schedule menu); open: second option set for a dish already in the cart, Schedule imports AddonSheet and getMenuItem (RN-STRUCT-02 needs a written decision) |
| 4.3 | 2 | E3 merged (app PR #40): 4.3a ready to start (new session), then 4.3b, 4.3c | | plan: schedule-phase4-app-implementation-plan.md Phase 3; reuse PaymentConfirmingNotice |
| 4.4 | 2 | queued | | |

## Brief — Lane 1 (payments, then ops board)

```
Lane 1: payments, then ops board   Repos: backend, Ninjasu_Web; app worktree for E3 only   Target: feature/schedule
Queue: L1.0 (if OD2 yes) → E2c → E3 → 3.1 → 3.2 → 3.3 → 3.4 → 3.5   (plan links in the Lane 1 table above)
Owns: backend, Ninjasu_Web; during E3 the app payment files listed under File ownership.
Must not touch: app home, src/features/schedule/**, src/features/cart/**, useCartStore, app routes (send a hand-off).
Waits on: OD4 geld before 3.2; 2d.7 merged before 3.3.
E3 setup: git worktree add ../Food-Ninja-Frontend-pay -b feature/eatnow-capture-pending origin/feature/schedule;
  npm ci inside it; Expo on --port 8082; remove the worktree after E3 lands (/lanes close step or ship).
Per slice: /ship next <branch> → /gcp brief if non-trivial → code + tests (Codex may write the tests from the spec)
  → fast checks; full backend suite locally until CI runs it; money slices: mutation + Codex review
  → /ship pr → update the Status row → stop for Samivan's merge word.
Stop and ask when: a file is owned by Lane 2, a decision is open, the plan is wrong, a check is red.
Report at slice end: PR link, checks run with results, hand-offs raised.
Model: Sonnet, xhigh effort.
```

## Brief — Lane 2 (customer Schedule app)

```
Lane 2: customer Schedule app   Repo: Food-Ninja-Frontend (main checkout)   Target: feature/schedule
Queue: (OD3 app CI if yes) → 4.1 → 4.2 → 4.3 → 4.4   (plan: schedule-phase4-customer-app-plan.md §3)
Owns: app home, src/features/schedule/**, src/features/cart/**, useCartStore, app routes; payment files only after E3 merges.
Must not touch: backend, Ninjasu_Web, app payment files before E3 merges (send a hand-off).
Waits on: OD1 (D3) before 4.1; E3 merged before 4.3.
Rules from the plan: never infer availability or prices client-side; branch on data.error, not HTTP status;
  every cart call sends type=FOOD&fulfilment=SCHEDULE.
Per slice: /ship next <branch> → /gcp brief → code + jest tests (Codex may write them from the spec)
  → tsc + lint + full jest locally (the app has no CI) → /ship pr → update the Status row → stop for the merge word.
Stop and ask when: a backend gap shows up (write a hand-off row, Lane 1 fixes it), a decision is open, the plan is wrong.
Report at slice end: PR link, checks run with results, hand-offs raised.
Model: Sonnet, xhigh effort.
```
