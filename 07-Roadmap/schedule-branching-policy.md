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

## Branch ledger (audited 2026-10-29)

What is where, so nothing is lost. Re-audit with: `git log --oneline origin/main..origin/feature/schedule` and the reverse, per repo.

| Repo | On `feature/schedule`, not on `main` | On `main`, not on `feature/schedule` |
|---|---|---|
| Backend | 14 untested Schedule commits: 2b.3a/b/c, Eat Now GST, 2b.4b order groups, 2b.2 menu API, public Schedule context, 2b.5 cart, 2b.6 holds | the admin-approved refund core (#69, `60287bc`, merge `e2e26cc`): **merge-back OWED** (policy: same day) |
| Ninjasu_Web | 1 commit: item subtotal on shop order views | none |
| Food-Ninja-Frontend | 2 commits: Eat Now tax in cart, code-map 2b.5/2b.6 | none |

- Every `feature/schedule-*` slice branch is fully contained in `feature/schedule` (checked: 0 commits outside it) except the ones already on `main` (2a, 2b.1, 2b.12 a/b/c, 2b.13). Older merged slice branches show "not in main" only because they are inside `feature/schedule`.
- Older Schedule phases (2a, 2b.1, 2b.12, 2b.13) reached `main` and production BEFORE this policy (2026-10-22). Schedule SQL `schedule-reservation-migration.sql` is NOT RUN anywhere.
- Open PR: Food-Ninja-Frontend #31 `docs/code-map-2b13` -> `main` (draft, conflicting, docs only; not decided).

### Refund follow-ups (2026-10-29)
Refunds are customer-visible, so policy rule 2 sends them to `feature/schedule` (the backend core went to `main` as #69 by decision OD1(a)). The follow-ups (backend #70, web #43, app #34) were merged into a temporary `feature/refund-approval` branch in each repo (backend branch = `main`; web/app created from `main`). NEXT: merge them into `feature/schedule` via slice PRs, backend first (merge `main` into `feature/schedule` first; dry-run shows a conflict in `ScheduleSchemaGuard.java`, plus auto-merged `PaymentServiceImpl`, `OrderServiceImpl`, `OrderRepository`, `PaymentReconciliationJob`: run the suite). Web and app merge cleanly. Then they reach `main` only through the release gate.

### Refund merge into `feature/schedule` (2026-10-29, in progress, NOT pushed)
Done locally in all three repos by merging `origin/feature/refund-approval` into `feature/schedule` (after fast-forwarding the local branch to `origin`: pull FIRST, a stale local branch hid the conflicts once; the stale result is tagged `backup/stale-local-schedule-merge-2026-10-29` in the backend, delete when no longer needed). Web and app merged with no conflicts. Backend had 8 real conflicts, resolved as:
- `ScheduleSchemaGuard`: refund branch's `RequiredObject.existsIn` kept, extended with `CONSTRAINT_ALLOWS` / `CONSTRAINT_ABSENT`; old private `exists()` removed.
- Legacy REFUND_PENDING sweep (`retryPendingRefunds`, `LegacyRefundBackfill`): refund branch's `findLegacyRefundPending/Owed`, now with `o.groupId IS NULL` so Schedule group members stay out of the legacy sweep. `findByPaymentStatusAndGroupIdIsNull` removed. `OrderRepositoryGroupFilterTest` now also accepts an `@Query` that carries `o.groupId IS NULL`.
- Audit enum: both sets of values kept. Duplicate `findByIdForUpdate` removed.
- OPEN DECISION for Samivan: another customer's checkout idempotency key. Schedule's `CustomerOrderIdempotency.requireOwner` (stricter: also refuses staff KOTs, group members, non-delivery) throws `BusinessRuleViolationException` (400, "Checkout attempt unavailable"); the refund branch had decided 409 `ConflictException`. Kept Schedule's helper; say if you want 409.
Then: backend suite result, web/app lint+tests, push `feature/schedule` (ask), retire `feature/refund-approval`, bring `main` and `feature/schedule` in step.
Status 2026-10-29: backend merge COMMITTED locally (`f7ca01e`), suite green (1629 tests, 0 failures, `-Dtest='!NinjaDeliveryServiceApplicationTests'`). Test fixes needed after the merge: `DatabaseObjects` fake gained `constraintDefinitionContains`; `refundExecutor` setup removed; `OrderResponseEnricher` (takes `PaymentRefundQueryService`) and `paymentRefundService` set in order/payment test setups. Web and app merges committed locally, lint/tests NOT yet run. All three local `feature/schedule` branches are ahead of `origin` and NOT pushed.
Unmerged leftovers reviewed: app `docs/code-map-2b13` (Schedule docs; merge into `feature/schedule`, one `code_map.md` conflict); app `feature/tax-classes-and-sales-channels` and web `feature/orders-dinein-shell-redesign` are local-only and already superseded on `main`: do NOT merge (conflicts, would regress); push as backup branches only.

### Stale branches (2026-10-29, Samivan: back up, do NOT merge)
Pushed to origin as backups only, never merge without a fresh review (both are superseded on `main`; merging would conflict and regress):
- Food-Ninja-Frontend `feature/tax-classes-and-sales-channels` (Sept 25-26, tax-class picker, sales-channel toggles, POS tax lines): `main` already has these in newer form (`salesChannel.ts`, `ItemFormModal` tax class, POS `taxTotal`/`payableTotal`); 3 conflicting files.
- Ninjasu_Web `feature/orders-dinein-shell-redesign` (Aug 13, ACCEPTED->READY fix): `main` `OrderTicket.tsx` already has `actionsForStatus`.
App `docs/code-map-2b13` (Schedule docs) IS merged into app `feature/schedule` (`06e160a`, local); its 113 cited files were verified to exist; two stale phrases fixed.

### State at end of session 2026-10-29 (nothing pushed except the two backups)
Local `feature/schedule` is ahead of origin in all three repos: backend `f7ca01e` (suite green), web (merge of refund follow-ups, lint/tests NOT run), app (refund merge + docs merge, lint/tests NOT run). Next: run web/app lint+tests, ask, push the three `feature/schedule` branches, delete the temporary `feature/refund-approval` branches and the backend tag `backup/stale-local-schedule-merge-2026-10-29`, commit the vault docs (refund plan, manual test list, this file are UNCOMMITTED on `docs/schedule-final-review`), then bring `main` and `feature/schedule` in step. Release to `main` only through the release gate above.
