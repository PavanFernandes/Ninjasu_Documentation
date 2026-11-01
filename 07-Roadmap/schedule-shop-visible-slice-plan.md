# Schedule: shop-visible orders, implementation plan (v2, 2026-10-30)

Status: v2 after blind Codex verification (8 findings, all verified or accepted). **First cut = PRs 1, 2, 3 and the web Schedule tab** (Samivan, 2026-10-30). PRs 4, 5, 6 and STATE-4 and STATE-5 are DEFERRED to [schedule-deferred-todo.md](schedule-deferred-todo.md); do not build them now. Next: `/gcp` for PR 1.
First-cut limits: orders stop at READY (no bulk delivery marking); whole-group cancel keeps today's rule; no customer group tracking or admin list yet.
Design source: [schedule-2b8-2b10-plan.md](schedule-2b8-2b10-plan.md), "Decision 2026-10-30", "Review 2026-10-30" (locked decisions) and "Second pass". Nothing below is built.
Branching: backend branch from `feature/schedule`, PRs into `feature/schedule`, never to `main` (schedule-branching-policy). Web follows the same rule.

## Goal
A paid same-day Schedule order stays `SCHEDULED`, the shop sees it in its own Schedule tab (count badge, no push), and it moves `SCHEDULED -> ACCEPTED -> READY -> OUT_FOR_DELIVERY -> DELIVERED`. It is never dispatched per order and never reaches POS, the kitchen display, the Eat Now board or the alarm.

## Rules that hold in every PR
1. "Schedule member" means `orders.group_id IS NOT NULL`: one method, used by every gate. A read-only pre-deploy audit proves it (see PR 1).
2. **Isolation lands before capability.** Every PR is independently deployable: no PR may let a Schedule member reach the Eat Now board, a rider, the alarm or POS, even for one deploy.
3. Every new member transition uses the existing lock order (group, then members) and the expected-status compare-and-set already in `OrderRepository.transitionScheduleMember`. No unconditional status write.
4. Eat Now behaviour is unchanged: each PR ends with the Eat Now tests green plus a test that an Eat Now order is unaffected.
5. No SQL expected. If one is needed (the cancel switch), it is a sketch labelled `DO NOT RUN NOW`, approved first.
6. Each PR: mutation check of every new guard (remove it, a named test must fail), blind Codex review of the diff against `feature/schedule`; `/judge deep` before the last PR merges.

## PRs (backend, in this order)
| PR | What | Touches | Tests |
|---|---|---|---|
| 1 Isolation | (a) the one `isScheduleMember` method; (b) dispatch gate at EVERY entry: manual assign (`DeliveryServiceImpl` ~267), reassignment (~686, which creates a fresh assignment and bypasses `buildDeliveryShell`), rider accept, gated BEFORE its idempotent existing-assignment return (~164), `DeliveryDispatchListener`, any broadcast or sweep; (c) Eat Now board excludes members (`OrderServiceImpl` ~268); (d) the Eat Now shop detail by id refuses members (~244); (e) the notification listener sends no shop push, no alarm and no `OrderPlacedEvent` for a member; (f) read-only audit queries: grouped orders that are not Schedule, Schedule orders without a group; remediation or a stronger discriminator if any turn up | `DeliveryServiceImpl`, `DeliveryDispatchListener`, `OrderServiceImpl`, `OrderNotificationListener`, audit SQL in the vault | each entry refuses an ACCEPTED, a READY, and a member that already has a delivery; guessed member id refused on the old detail route; event test: no push, alarm or placed event; Eat Now unaffected |
| 2 Transitions | transition table keyed by (member or not, status); Schedule rows `SCHEDULED->ACCEPTED/DECLINED/CANCELLED`, `ACCEPTED->READY/CANCELLED`, `READY->OUT_FOR_DELIVERY`, `OUT_FOR_DELIVERY->DELIVERED`; shop accepts and declines SCHEDULED (`acceptMember` needs PLACED today, `declineMember` is admin-only for SCHEDULED today); the member path routes READY, OUT_FOR_DELIVERY, DELIVERED (`OrderServiceImpl` ~331); READY publishes the status event; group lock then member locks, CAS on expected status | `OrderServiceImpl`, `ScheduleCancelServiceImpl`, `OrderRepository` | table-driven test of every pair for both kinds; shop accept, decline with refund and restock; no permission and wrong shop refused; real-database concurrent cancel versus READY or DELIVERED (the cancel result must survive) |
| 3 Shop reads | Schedule list, count and detail for the shop audience grouped by `order_groups.service_date` and slot; no KDS or POS read can return a member (test); permission and tenant isolation | new shop controller, service, DTO under the shop-audience prefix | list grouped by slot, count equals list, other shop's orders hidden, guessed id refused |
| 4 Group cancel | a DECLINED member keeps its status and is NOT cancelled or refunded again; cancel and restock only the remaining eligible members; refund allocations and fees computed against existing refund rows; switch (default ON) for the customer's "cancel the whole group" offer; ACCEPTED member rule per STATE-5 | `ScheduleCancelServiceImpl.cancelGroup` (transitions every member today, line 62) | decline A then cancel B; pending and processed decline refunds; no second refund of A; switch off refuses; rollback on failure |
| 5 Customer tracking | a group history and discovery contract (history and active-order reads exclude all members today, `OrderRepository` ~60 and ~72; a group view needs the group id already); statuses SCHEDULED, ACCEPTED, READY, OUT_FOR_DELIVERY, DELIVERED including the no-rider case | `OrderRepository`, group read service, customer DTO | customer finds a past group; each status renders; another customer's group refused |
| 6 Admin | unaccepted Schedule orders by slot; bulk mark of a slot's READY orders OUT_FOR_DELIVERY then DELIVERED (STATE-4); all-or-nothing per shop, CAS per member, audited, only READY members | admin controller and service, audit rows | bulk concurrent with cancel; non-READY member refused; audit rows written |
| 7 Docs | acceptance rows, vault docs, code map | docs | n/a |

Hard order: 1, then 2, then 3 to 6 in any order. PR 2 cannot merge before PR 1 is deployed to the integration branch.

## Web and app (after PR 3)
- Ninjasu_Web shop dashboard: Schedule tab grouped by slot, count badge refetching on window focus plus a slow interval while the tab is open, accept, decline and mark-ready actions (`ui-engineer` skill, shared components).
- Ninjasu_Web admin: the unaccepted list and the bulk slot actions (PR 6).
- Customer app: Schedule history and tracking from PR 5.

## Open
- STATE-4 default: admin or shop bulk-marks a slot OUT_FOR_DELIVERY then DELIVERED until bulk dispatch exists. Needs Samivan's yes.
- STATE-5 default: whole-group cancel may cancel an ACCEPTED member only before READY; the restaurant is unpaid for it unless the contract says otherwise. Needs Samivan's yes and a row in `restaurant-schedule-terms.md`.
- Where the group-cancel switch lives (platform setting or per area): decided in PR 4's `/gcp`.
- Tab query index: `EXPLAIN ANALYZE` on a branch before adding any.
- Not yet verified (by Codex or me): every POS and KDS reader, invoice path, scheduled job scanning READY orders, every status writer, historical rows. PR 1's audit and `/judge deep` cover them.
