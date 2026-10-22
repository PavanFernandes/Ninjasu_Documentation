---
id: ""
title: "Roadmap — Index"
summary: "Index of backlog ideas, known loopholes, pending flags, sales/GTM briefs, and in-progress feature designs."
type: reference
status: active
apps: [backend, customer, admin, rider, web]
module: "roadmap"
anchors: []
verified_against: ""
updated: 2026-09-05
---

# Roadmap — Index

Backlog, competitive/business research, sales/GTM briefs, and features still being designed. Per
the root [README.md](../README.md)'s recording table: a feature still being designed lives here
from `90-Meta/templates/feature-template.md` with `status: designing`, and promotes its decided
parts into an ADR once locked.

**`status: vision` precedes `designing`.** A vision doc records *why* and *what for* — the reasoning,
constraints and decisions already taken — but is not scoped to build. Promote it to `designing` (and
the feature template) when the build is actually picked up, so a session can resume from the thinking
instead of re-deriving it.

| Doc | What it covers |
|---|---|
| [browser-test-todo-2b12c.md](browser-test-todo-2b12c.md) | Full manual browser test list for the 2b.12(c) add-on price editors and the admin Pricing page (cap, review queue); nothing run in a browser yet |
| [admin-access-redesign.md](admin-access-redesign.md) | **Proposed** — platform staff access: `platform_staff` table (admin + area roles) instead of `users.roles`, separate staff login/token/console host, `platform_audit_events`; effort + build order. Lands before Schedule Phase 2 |
| [schedule-design-review.md](schedule-design-review.md) | Schedule Phase 1 devil's-advocate review: P1–P8 verdicts, plan corrections, D1–D8 |
| [schedule-plan.md](schedule-plan.md) | **Designing** — Schedule (planned lunch delivery) vs Eat Now as per-area modes; HSR pilot with manual batching; locked decisions, vocabulary, kill criterion, blockers, phases 0–8 |
| [vision-inventory-module.md](vision-inventory-module.md) | **Designing** — Raw-Material Inventory: purchase capture, grocery-list loop, data model, 14 DA conditions, phases. Build gated on POS cohort |
| [audit-log-plan.md](audit-log-plan.md) | **Designing** — cross-module append-only audit log (who did what, when; filter by module/event/staff/date), competitor case studies, 15 DA conditions, phases. Build after RBAC merges |
| [audit-log-phase1-followup.md](audit-log-phase1-followup.md) | Audit Log Phase 1 build notes — deploy order, deviations from the plan, known gaps, endpoint backlog for later phases |
| [vision-spatial-table-view.md](vision-spatial-table-view.md) | **Vision** — Spatial Table View / floor map |
| [pricing-and-positioning.md](pricing-and-positioning.md) | POS pricing verdict, positioning, deferred directions |
| [backlog-ideas.md](backlog-ideas.md) | Backlog Ideas — Food Ninja |
| [loopholes.md](loopholes.md) | Business Logic Loopholes — Food Ninja |
| [pending-flags.md](pending-flags.md) | Pending Flags |
| [research-notes-menu-module.md](research-notes-menu-module.md) | Innovation Research — Menu Module |
| [sales-captain-ordering.md](sales-captain-ordering.md) | Captain Ordering — GTM / Sales Brief |
| [sales-feature-brief-addon-groups.md](sales-feature-brief-addon-groups.md) | Shared Addon Groups — Feature Brief |
| [sales-onboarding-notes.md](sales-onboarding-notes.md) | Food Ninja — Restaurant Owner Onboarding Audit |
| [scale-concerns.md](scale-concerns.md) | Food Ninja — Business Scale Concerns |
| [stock-ledger-design.md](stock-ledger-design.md) | Daily Stock Ledger ("Prep Assistant") — Design |
| [tests-todo.md](tests-todo.md) | Tests Todo — Menu Category & Item Business Rules |
