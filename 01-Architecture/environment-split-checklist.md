# Environment split checklist (dev vs production)

Run this when production and development get separate databases and keys (planned by Samivan, Nov 2026).
Until then the single Neon database is used as a test database, because Food Ninja is not live.

## Samivan
- [ ] Create the development database (Neon branch or project) and its own login; production keeps its own.
- [ ] Rotate the production database password and any keys that have been on this laptop (Neon, AWS, Razorpay).
- [ ] Production credentials live only on the EC2 server (and the deploy secrets), not in local `.env` files.
- [ ] Razorpay: live keys only on EC2; this laptop keeps test keys only; live-mode webhook points at the production URL.
- [ ] Local backend and web `.env` files point at the development database by default (closes ENV-3: no default path to production).
- [ ] Decide GitHub Pro, so `main` gets server-side protection (PR required, no force push, no deletion).

## Claude (same day, on Samivan's word)
- [ ] Add the production database host to `~/.claude/hooks/safety-guard.config.json` → `blockedHosts`, then pipe-test that a command naming it is denied.
- [ ] Update memory `project_safety_and_test_lane` and `feedback_local_dev_is_not_isolated`: production is no longer usable as a test database.
- [ ] Set up the masked `ai-dev` branch (reset from parent + mask script + branch-only login), if not already done.
- [ ] If GitHub Pro is bought: enable branch protection on `main` for Food-Ninja-Java-Backend, Ninjasu_Web, Food-Ninja-Frontend and Ninjasu_Rider_App.
