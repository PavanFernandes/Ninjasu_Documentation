---
id: ""
title: "Schedule branching and merge policy"
summary: "Where each Schedule change merges: the long-lived feature/schedule branch for anything a customer can see or that touches orders, payments, carts or menu availability; main only for admin-only phases that pass the gates below. Decided by Samivan 2026-10-22."
type: how-to
status: active
apps: [web, backend, customer]
module: "schedule"
anchors:
  - { repo: backend, path: ".github/workflows/ci.yml" }
  - { repo: web, path: ".github/workflows/ci.yml" }
verified_against: "backend, Ninjasu_Web and Food-Ninja-Frontend feature/schedule created from main on 2026-10-22"
updated: 2026-10-22
---

# Schedule branching and merge policy

Decided by Samivan on 2026-10-22 (the "hybrid" option). It applies from phase 2b.2 onward.

## Why this exists

Backend `main` and web `main` deploy to production the moment a PR merges. Until 2026-10-22 each Schedule phase was merged to `main` on its own (2a, 2b.1, 2b.12 a and b, 2b.12(c), 2b.13). The 2b.12(c) editors reached production before any browser test ran. This policy stops that and removes the doubt about where a change goes.

## The branches

| Repo | Short | Long-lived branch | Deploys from `main`? |
|---|---|---|---|
| Food-Ninja-Java-Backend | **BE** | `feature/schedule` | yes, EC2 on every push to `main` |
| Ninjasu_Web | **NW** | `feature/schedule` | yes, EC2 on every push to `main` |
| Food-Ninja-Frontend (Expo app) | **FE** | `feature/schedule` | no deploy; a phone build is a separate, manual EAS step (ask first, it costs credits) |

`feature/schedule` was created from `main` on 2026-10-22 in all three repos. It is the pre-main branch for the whole Schedule feature.

## Which way does a change go?

Answer in order. The first "yes" decides.

1. **Is it a hotfix to something already live?** Branch from `main`, PR to `main`, then merge `main` back into `feature/schedule`.
2. **Can a customer see it, or does it touch orders, payments, carts, menu availability, checkout, refunds, notifications or the rider?** It goes to `feature/schedule`. This covers 2b.2 to 2b.11, 2c, 2d and phases 3 to 7.
3. **Is it admin-only or internal, with no customer-visible change?** It may go to `main`, but only when every gate below is true, and only with Samivan's yes for that merge. Otherwise it goes to `feature/schedule` too.

### Gates for a direct merge to `main`

All must hold:
- The phase's own test list has passed, including browser or device checks where it has them.
- Any hand-run SQL is already applied and idempotent, and the backend's boot guard is satisfied.
- It works with the versions of the other two repos that are live today.
- `/judge full` has been run and every decision-free finding is fixed.
- Samivan said yes to that specific merge, after being told it deploys to production.

Past phases against these gates: 2b.13 was admin-only and qualified except that its manual tests are still open. 2b.12(c) did not qualify: it changes live menu editors and its 57 browser checks have not run.

## The flow for a slice

1. Branch `feature/schedule-<phase>-<name>` from the current `feature/schedule`.
2. Open a draft PR with base `feature/schedule`. CI runs on it (backend and web CI cover `feature/**`).
3. Run `/judge quick` after the slice. Merge into `feature/schedule` when CI and the slice tests pass.
4. When a phase is complete, run `/judge full` on `feature/schedule` and its manual test list on a Neon branch.
5. Nothing from `feature/schedule` reaches `main` until the release gate below.

## Keeping `feature/schedule` current

- Merge `main` into `feature/schedule` before opening each slice PR and at least once a week, in each repo. Fix conflicts on `feature/schedule`, never on `main`.
- A hotfix on `main` must be merged back the same day.

## The release gate (feature/schedule to main)

Done once, when the Schedule is ready for the HSR pilot, or earlier for a self-contained group of phases that Samivan chooses:
- `/judge deep` on `feature/schedule` in BE and NW; `/judge full` in FE.
- Every phase test list passed, including the Android device list.
- All SQL applied and verified on a Neon branch first, then production.
- One PR per repo, opened as a draft. Merge order: **BE first** (confirm the deploy is healthy), then NW, then FE. Do not merge two at once.
- A flag or a no-op path keeps the customer app unchanged until the pilot is switched on (phase 8 gives each part its own flag and ADR).

## Rules for Claude

- Say "this deploys to production" before any merge to `main` in BE or NW, and ask for the go-ahead for that merge.
- Never open a slice PR with base `main` for a phase that falls under rule 2.
- Never merge FE and trigger an EAS build without asking.
- Before adding a branch to a workflow trigger, read every job's `if:` (a deploy job gated only by `event_name == 'push'` deploys production from that branch).

## Open question

None at the time of writing. If the release gate needs a staging environment later, record it in an ADR in `01-Architecture/decisions/`.
