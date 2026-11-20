# Schedule 3.4: ops board, remaining slices

Status: **v0.1 DRAFT 2026-11-20** (investigation done, build order proposed, two gates open for Samivan)
Source rows: [schedule-implementation-order.md](schedule-implementation-order.md) Phase 3 row 3.4; lane plan [lanes/lanes-schedule-p3-p4.md](lanes/lanes-schedule-p3-p4.md); batches plan [schedule-batches-3-2-3-3-plan.md](schedule-batches-3-2-3-3-plan.md) (OPS-3, STATE-4, PII-1, EVOL-1, EVOL-7).

## Goal

The ops board at `/admin/ops-board` lets an area manager see a day's Schedule run and act on it. The row 3.4 scope is: slot columns, capacity/cutoff, ticket state, map of group drops, unbatched and late-order warnings, problem queue with pending "can't make" approvals, batch sheet with labels.

## Built so far (slice 3.4a+b, web only, branch `feature/schedule-ops-board`, commit 5347a25, not pushed)

Slot columns, batch cards, unbatched list, add/move/remove/cancel/assign/reassign, warnings from batch data (empty, waiting, drop failed, stale open), no polling (refresh on load, tab focus when data is older than 30 s, after actions, Refresh button). It makes one detail request per batch (finding F6 of the 2026-11-20 judge run).

## What exists on the backend today (investigated 2026-11-20, code and vault only; the live DB was not read)

| Needed by the board | State | Where |
|---|---|---|
| Slot capacity | EXISTS as a number (counts groups, not orders) | `ServiceAreaSlot.capacity` |
| Booked per slot and date | EXISTS as a column, no read | `ServiceAreaSlotDay.reservedGroups`; read only by `ScheduleHoldChecker` and `ScheduleReservationSettler` |
| Cutoff | EXISTS | `ServiceArea.lastCallMinutes`, `pickupLeadMinutes`; frozen instants in `ScheduleSlotFreeze` (`lastCallAt`, `slotStartsAt`, `readyByAt`) |
| Ticket state | EXISTS per shop only | derived by `TicketStatusDeriver` (NOT_STARTED, IN_PROGRESS, READY, CANCELLED); read at `GET /api/shops/{shopId}/orders/schedule/live`; no ops list across shops |
| Group drop coordinates | EXISTS | `BatchMember` and `UnbatchedGroup` carry `deliveryLat`, `deliveryLng` |
| Ready-since per shop | MISSING | no timestamp on the READY transition; readiness is computed by `BatchGroupGate.isReady` without a time |
| Late-order detection | MISSING | inputs exist (`readyByAt`, `slotStartsAt`), nothing compares them |
| Bag count | MISSING as a field | code treats one bag as one order (`BatchRunServiceImpl.everyLiveOrderHasItsBag`) |
| Rider live batch count | PARTIAL | batch state is derived from events; no count-per-rider query |
| "Can't make" approvals | MISSING | only the constant `ScheduleTicketAmendment.CANT_MAKE_APPROVED`; designed as `ticket_issue` in slice **2d.6** (implementation-order line 158), which is not built |
| Drop points (saved places) | MISSING | `schedule_drop_points` deferred to 3.4 by decision D1 |
| Pickup and drop order | MISSING | `schedule_batch_pickups`, `drop_seq` deferred (EVOL-1) |
| Batch sheet / labels | MISSING for batches | the reports module has PDF and XLSX renderers (`ReportPdfRenderer`, `ReportXlsxRenderer`, poi-ooxml and openpdf in `pom.xml`), shop-scoped |

## Proposed build order

Each slice: `/gcp` first, a build by one model and a cross-review by the other (Sonnet 5.5 and Codex gpt-6.2-sol), `/judge` before the PR. A slice that adds a table or column runs `/geld` first and waits for approval before any SQL.

| Slice | What | Needs | Schema |
|---|---|---|---|
| **3.4c** | One read-only board endpoint `GET /api/ops/board?areaId&date`: batches with members and events, unbatched groups per slot, per slot booked/capacity and cutoff instants, derived bag count (live orders per batch), rider live batch count, ops-wide ticket state per slot. The web board switches to it and drops the per-batch detail requests (fixes finding F6). | backend + web | none |
| **3.4d** | Late-order and cutoff warnings on the board (order not READY past `readyByAt`; slot past last call with unbatched groups), computed from 3.4c data. | web, small backend field | none |
| **3.4e** | Ready-since per shop: a timestamp written when an order becomes READY, shown per group in the unbatched list and on batch members (STATE-4). | `/geld`, SQL | 1 column or event table |
| **3.4f** | Drop points, the map of group drops, pickup/drop order, and the batch sheet with labels (PII-1: the sheet carries customer names and addresses outside the app; access and expiry need a decision). | `/geld`, SQL, decision | `schedule_drop_points`, `schedule_batch_pickups`, `drop_seq` |
| **3.4g** | Problem queue with "can't make" approvals (approve, reject, choose which orders). **Blocked on 2d.6** (`ticket_issue`, per-order cancellation, partial refund, ticket amendment). Money and state: its own geld and devil's advocate. | 2d.6 first | per 2d.6 |

3.4 is complete only when 3.4g lands, so it can finish only after 2d.6.

## Decisions for Samivan

1. **2d.6 (blocks 3.4g).** Build 2d.6 now as the next backend slice after 3.4e/3.4f, or accept shipping 3.4 without the problem queue and track "can't make" under 2d.6 on its own? Recommended: ship 3.4c to 3.4f, plan 2d.6 next, add the queue (3.4g) when 2d.6 lands.
2. **PII-1 for the batch sheet.** Who may open it and for how long (area manager and ops only, signed link with an expiry, or no shareable link and print from the board only)? Recommended: print from the board only, no shareable link.
3. **ENV-4 (still open).** The batch SQL is not run; the board cannot be exercised against real batch data until Postgres version, backup/PITR and a rehearsal copy are answered.

## Review notes

- 3.4c needs no table, so it needs no `/geld`; it is a new read service in the Schedule module and joins only Schedule data and the rider repository (no cross-domain service call).
- Money and state: 3.4g only. 3.4c to 3.4f are reads and one timestamp.
- The 2026-11-20 focused judge run on the web slice (correctness C+, performance B, ui A-, tests C+) is recorded in the rulebook history; F6 (per-batch requests) is closed by 3.4c.
