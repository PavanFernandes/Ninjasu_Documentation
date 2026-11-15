# Lanes profile — Food Ninja / Ninjasu

Project facts the `/lanes` skill reads. Checked 2026-11-15; re-check a row when it looks wrong.

## Repos

| Repo (folder under `Food Ninja/`) | Target for Schedule work | Deploys on merge to | CI on PRs into `feature/**` |
|---|---|---|---|
| `ninja delivery service java` (backend) | `feature/schedule` | `main` → production EC2 | **compile only** (`./mvnw -B compile`); no tests run in CI |
| `Ninjasu_Web` | `feature/schedule` | `main` → production | `pnpm run lint` + `pnpm run build`; no tests |
| `Food-Ninja-Frontend` (customer app) | `feature/schedule` | nothing (EAS builds by hand, ask first) | **none** |
| `Ninjasu_Documentation` (vault) | `main` | nothing | none |

Every branch is cut from a fresh `origin/<target>` (`/ship next`); every PR goes into the target. A merge
into backend or web `main` is a production deploy: ask first.

## Checks per repo (fast tier, run in the lane)

| Repo | Fast checks | Full suite |
|---|---|---|
| backend | `./mvnw test -Dtest='<touched test classes>'` | `./mvnw test -Dtest='!NinjaDeliveryServiceApplicationTests'` (~2,600 tests; `contextLoads` boots on prod Neon, never run it) |
| web | `pnpm run lint`, `npx tsc --noEmit`; unit specs via the Playwright runner (memory `reference_web_tests_playwright_unit_runner`) | lint + build (CI) |
| app | `npx tsc --noEmit`, `npm run lint`, `npx jest <touched folders>` | `npx jest` |

Because CI runs no tests, the lane runs its repo's test suite locally before the PR until CI gains a test job.

## Risk folders (money / state machine: mutation run + second-model review per PR)

Backend `service/payment/**`, `service/refund/**`, `service/schedule/payment/**`, `service/schedule/checkout/**`,
`service/schedule/settlement/**`, any `db_manual/*.sql`, order or group status transitions. Fast mutation
harness: one-file `javac -parameters` + `surefire:test`, failing-test COUNT per kill (memory
`feedback_mutation_harness_must_prove_it_ran`).

## People, devices, models

- Device tests and every SQL run: Samivan. Real-payment rounds need his phone.
- Codex edits files and runs Node/TS checks; it cannot run Maven and cannot write `.git`. Claude branches and commits.
- One machine: never two Maven suites or mutation runs at once.
- Dev ports: web 3010; Expo 8081 in the main app checkout, 8082 in an app worktree.
- Worktrees: only when Samivan approves a lane plan that needs one; own `npm ci`/`pnpm install`, never a junction.
