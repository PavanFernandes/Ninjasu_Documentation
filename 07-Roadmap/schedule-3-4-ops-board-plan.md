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

## 3.4e data model review: ready-since (geld, 2026-11-20)

Status: **APPROVED 2026-11-20 (Samivan chose option A: `orders.ready_at`).** SQL file may be written; it is NOT run until ENV-4 is answered and the SQL is rehearsed. Board shape: per group `readySince` (when the group became ready, null while any live shop is still packing) and per shop `{shopId, shopName, orderCount, readyCount, readySince}` (readySince = latest `ready_at` of that shop's live orders once all are ready, else null).

### What exists (read from the code, 2026-11-20; live DB not read)

- A Schedule order becomes READY in exactly one place: `ScheduleCancelServiceImpl.markMemberReady` (`transition(order, READY)`, line ~127). `OrderServiceImpl.updateOrderStatus` routes Schedule members there (line ~341); Eat Now and POS orders use other paths and are out of scope. `ScheduleMemberTransitions` allows ACCEPTED -> READY and nothing leaves READY, so the first READY is the only READY.
- `orders` has NO status timestamps (only `release_at`). `markMemberReady` already writes an `audit_events` row (`schedule.member_ready`, `occurred_at` epoch ms, immutable by trigger), but every `audit_events` index leads with `shop_id` (`idx_audit_shop_time`, `_root`, `_actor`, `_module`), and a board read spans the several shops of a group.
- Time convention in this codebase: epoch milliseconds as `bigint` (`orders.release_at`, `audit_events.occurred_at`, batch events).

### Finding MODEL-1 (must change before the board can show ready-since)

Ready-since is an operational fact the board needs per order, and the order row is the row that owns it. Deriving it from the audit log (option B) would need a multi-shop lookup on `entity_id` + `action` that no existing index supports, and ties an operational screen to an audit feature's retention and shape. Recommended: store it on the order (option A).

| Option | Design | Cost | Verdict |
|---|---|---|---|
| **A (recommended)** | `orders.ready_at bigint NULL`, set once in `markMemberReady` (only when null), read for free because the board already loads the orders of each group | 1 nullable column, metadata-only `ADD COLUMN` on Postgres (no rewrite, no lock beyond a brief catalog lock), 1 line in the writer, 1 entity field, 1 DTO field, 1 schema-guard entry; no backfill needed (older orders show "-") | recommended |
| B | derive from `audit_events` where `action='schedule.member_ready'` | no schema; needs a new index or a per-shop query loop; couples the board to audit retention | rejected |
| C | a `schedule_order_events` table | a new table for one timestamp; over-built | rejected |

Name and semantics: `ready_at` = "when a Schedule order first reached READY", set only by `markMemberReady`; null for orders that never reached READY and for every non-Schedule order. The column comment in the SQL says so (a half-filled generic column is a trap: EVOL-1). Optional backfill later from `audit_events` for orders readied before the deploy: not required, since only today's board matters.

### Deploy order (MIG-1, the real risk)

`orders` is the hottest entity: once `Order.readyAt` is mapped, every order query fails if the column does not exist in the database. So the SQL runs BEFORE the backend that maps it is deployed, and a `ScheduleSchemaGuard` entry makes the backend refuse to boot without it (same as the batch tables). DO NOT RUN, sketch for review:

```sql
-- DO NOT RUN — sketch for review (3.4e)
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS ready_at bigint;
COMMENT ON COLUMN public.orders.ready_at IS 'Epoch ms the Schedule order first reached READY (set by markMemberReady); null otherwise';
```

### Shown on the board (after the column exists)

Per group: which shop is not READY yet and since when (per-order `ready_at`, "-" when null); per unbatched group and per batch member: the latest ready-since of its orders and the oldest still-waiting order; feeds the STATE-4 warning.

### Decisions for Samivan

1. **MODEL-1:** store `ready_at` on `orders` (A), derive from audit (B), or defer ready-since? Recommended: A.
2. **ENV-4:** still open (Postgres version, backup/PITR, rehearsal copy). It blocks running this SQL as well as the batch SQL; both can go in one rehearsal.
