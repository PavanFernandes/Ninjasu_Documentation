# Schedule 3.1: admin Service areas page (web) + backend prerequisites

Lane 1, slice 3.1 of [lanes-schedule-p3-p4.md](lanes/lanes-schedule-p3-p4.md). Parent row: Phase 3 row 3.1 in [schedule-implementation-order.md](schedule-implementation-order.md).
Every PR goes INTO `feature/schedule` (never `main`; backend and web `main` deploy to production). Production keeps `schedule_enabled` OFF.

**Status:** FINAL (APPROVED WITH CHANGES, 2026-11-15, Samivan); 3.1a built and merged (backend #94); 3.1b built and merged 2026-11-18 (web #49, f198371ca; browser check not done); Part B refined 2026-11-18 against the built code (see "Build refinements") · reviewed by devil's advocate + geld (deep, Codex blind second opinion) · build order: 3.1a backend PR, then 3.1b web PR, both into `feature/schedule`

## Goal

An admin manages Schedule service areas from Ninjasu_Web instead of the database: create and edit an area, manage its slots, assign shops to it. Today only the API exists (`AdminServiceAreaController`, `AdminShopScheduleController`); the web has no page.

## Scope

In: area create/edit (every field of `ServiceAreaRequest`), slot add/edit/deactivate/delete, shop assignment (set, move, clear).
Out of 3.1: commission plans, audit view, Orders filters, dish price list, price-cap setting, dine-in price editing (the wider row in schedule-implementation-order.md; those pages exist or are separate slices). **Needs Samivan's yes** (recommended: lane-plan scope).

## Facts the design rests on (verified in code 2026-11-15)

- Endpoints: `POST/GET /api/admin/service-areas`, `GET/PUT /{areaId}`, `POST /{areaId}/slots`, `PUT/DELETE /{areaId}/slots/{slotId}`, `PUT /api/admin/shops/{shopId}/schedule-assignment` (body `{serviceAreaId}`; null unassigns). No area DELETE, by design. No client (web, app, rider app) calls the assignment endpoint today.
- Validation is server-only (`ServiceAreaValidator`); a rule failure is HTTP 400 with `data` = map `CODE -> message` (`ScheduleValidationException`). While `scheduleEnabled` is on the server requires `advanceDays = 0` and `windowOpenDayOffset = 0` (`SCHEDULE_SAME_DAY_ONLY`).
- Area and slot edits take a row lock on the area, write a platform audit event, and evict the per-JVM `ServiceAreaCatalog` cache (30 s TTL; one backend instance in production).
- `Shop` has `service_area_id`; `ShopDto` has no area field and there is no read endpoint for a shop's assignment. `ShopServiceAreaAccessGuardTest.noOwnerOrCustomerDtoCarriesTheServiceAreaId` (T2a-08) fails the build if any DTO outside `dto/admin` and `dto/ops` mentions `serviceAreaId`.
- `PUT /api/shops/{id}` binds `ShopDto` from the request body (owner write path) and `GET /api/shops/{id}` is public to guests.
- `deleteSlot` deletes with no reference check. Slot references: `order_groups.slot_id` (FK), `cart_sessions.slot_id`, `service_area_slot_day.service_area_slot_id`, `schedule_slot_freeze.slot_id`, ticket publications (all but the first have no FK). Reservation lines reach a slot only through their reservation's slot-day row, not directly. `GlobalExceptionHandler` has no handler for a database FK violation: it falls to the catch-all (HTTP 500, "Something went wrong").
- Carts, holds and the menu read slots through the catalog or `findByIdAndServiceAreaId` and filter `isActive`, so a deactivated or missing slot reads as `SLOT_CLOSED` (soft failure).
- `ScheduleSlotFreezer.freezeSlot` reads the CURRENT slot start time and area settings (timezone, last call, pickup lead) when it freezes a slot day (it does not filter `isActive`), so an edit before the freeze moves the freeze time of groups already paid. `ShopServiceDates` throws "Service area not found" for a shop with no area, so the shop's live board stops working for today's paid orders after an unassign or move.
- `ServiceArea.updatedAt` exists (`@UpdateTimestamp`) but `ServiceAreaDto` does not carry it; `ServiceAreaRequest` is a full replace with no precondition.
- Five error shapes reach the form (verified against the built 3.1a code, 2026-11-18): bean-validation 400 (`data` = field name -> message), unreadable body 400 (`message: "Malformed request body"`, no `data`), domain validation 400 (`message: "Validation failed"`, `data` = CODE -> message), admin conflict 409 (`ScheduleAdminConflictException`: `message: "Conflict"`, `data` = CODE -> message; every 3.1a guard uses it), and plain-message errors (`ConflictException` 409 / `ResourceNotFoundException` 404, `message` only). The shared `extractErrorMessage` reads only `message`, so it would show "Conflict" / "Validation failed".
- `GroupPaymentSettlement.finishPaid` computes the order release time and the group's cancel window from the LIVE area settings at payment confirmation, then stores them (`orders.release_at`, `order_groups.cancel_until_at`, `late_cancel_from_at`). `order_groups.slot_start_local_time` is a snapshot.
- Hold checks compare `shop.serviceAreaId` with the cart's area (`ScheduleHoldChecker`, `ScheduleCartWriter`), so moving a shop mid-day rejects carts holding it; paid orders keep their own area.

## Final design

### Part A: backend (repo `ninja delivery service java`; branch `feature/schedule-3.1a-admin-area-reads` cut from fresh `origin/feature/schedule`; PR into `feature/schedule`)

A1. **Read a shop's current area, admin only.** `GET /api/admin/shops/schedule-assignments` returns `[{shopId, shopName, shopStatus, serviceAreaId}]` for every non-DELETED shop, in `dto/admin` (new `ShopServiceAreaRowDto`). No field is added to `ShopDto` (the T2a-08 tripwire and the owner `PUT` body make that unsafe). One small list serves the area page's "shops in this area" and the picker's "currently in area X". Unpaginated; revisit above ~500 shops.
A2. **Slot delete guard.** `deleteSlot` refuses with a 409 (as built: `message: "Conflict"`, `data` = `{CODE: text}`) when the slot is still active (`SLOT_ACTIVE`: deactivate first) or has ever been used: any `order_groups`, `service_area_slot_day`, `schedule_slot_freeze` or ticket-publication row references it (`SLOT_IN_USE`). Checks run inside the existing area-row-locked transaction. Deactivating first closes the race with new holds (a hold needs an active slot); the `order_groups` FK is the backstop, and `deleteSlot` catches a `DataIntegrityViolationException` and answers the same 409. Deactivating is the supported way to retire a used slot, allowed once no live order exists (A4): `ScheduleSlotFreezer` itself ignores `active`, but `DueSlotDays` schedules freezes for active slots only.
A3. **Unassign contract.** `PUT .../schedule-assignment` requires a non-null `serviceAreaId` (`@NotNull`, 400 otherwise); new `DELETE .../schedule-assignment` clears the area, same audit action, same shop-row lock and status check. No client calls the old null form.
A4. **Live-commitment lock on timing fields.** A "live commitment" for a slot or area is an `order_groups` row that is held or paid (not failed, cancelled or expired) with `service_date >= today` in the area's timezone. While one exists: a slot `startLocalTime` change, or deactivating an active slot, is refused (409 `SLOT_HAS_LIVE_ORDERS`; the freeze scheduler skips inactive slots, so deactivation would stop the tickets of paid orders), and an area update that changes `timezone`, `lastCallMinutes` or `pickupLeadMinutes` is refused (409 `AREA_HAS_LIVE_ORDERS`). Capacity, active, fees, pause, packaging, the window, cancel freeze and grace stay editable (they act on new holds, or are snapshotted at payment). The build resolves the exact group status values from `OrderGroup`/payment enums.
A5. **Shop move/unassign lock.** Changing a shop from one area to another, or clearing it, is refused (409 `SHOP_HAS_LIVE_ORDERS`) while the shop has a member order in a live commitment (A4's definition). First assignment (from none) is always allowed.
A6. **Edit precondition.** `ServiceAreaDto` gains `updatedAt` (additive); `ServiceAreaRequest` gains an optional `expectedUpdatedAt`; when present and different from the stored value (equal when within 1 ms: Hibernate's in-memory timestamp and the stored microsecond value can differ in the last digits) the update answers 409 `AREA_CHANGED` and writes nothing. The web always sends it. Absent = today's behaviour, so no client breaks.
A7. Tests: contract test per new/changed endpoint, a service test per guard branch (including the race backstop and each live-commitment status), the existing T2a-08 tripwire stays green, one mutation check per guard (remove the check, a named test must fail). Full backend suite locally (`./mvnw -B test -Dtest='!NinjaDeliveryServiceApplicationTests'`), never the context-load test.

### Part B: web (repo `Ninjasu_Web`; branch `feature/schedule-admin-service-areas` cut from fresh `origin/feature/schedule`; PR into `feature/schedule`; after Part A merges)

- Routes `/admin/service-areas` (list) and `/admin/service-areas/[id]` (edit; `new` for create) as 5-line wrappers under `src/app/(admin)/admin/`, nav entry in `src/app/(admin)/layout.tsx`.
- `features/admin/services/service-area.service.ts` (types mirror `ServiceAreaDto`, `ServiceAreaRequest`, slot DTOs, `ShopServiceAreaRowDto`; fees are JSON numbers, shown and sent with at most 2 decimals; times parse as `HH:mm` or `HH:mm:ss` and are sent as `HH:mm:ss`; one error normaliser maps the three error shapes (field-name keys, unreadable-body, domain codes) to field messages with a form-level fallback for unknown keys; `updatedAt` kept from the last GET and sent as `expectedUpdatedAt`, a 409 `AREA_CHANGED` reloads the form), `components/service-area/*`: list, form, slot editor, shop assignment panel. Copy `DeliveryZonesList` / `DeliveryZoneForm` / `delivery-zone.service.ts`. Use the `ui-engineer` skill.
- Form mirrors the server rules (field limits and ranges) and shows the server's `CODE -> message` map beside fields; the server stays the only validator. While Schedule is on, advance days and window offset are locked to 0. Timezone is a select of IANA ids; centre/radius as numbers (map picker is out of scope).
- Confirm dialogs (name the consequence): turning Schedule on, turning Eat Now off, changing last call / cancel freeze / grace ("applies from now; does not change orders already paid"). A pause action sends `pausedOn` after a fresh GET of the area (full-replace `PUT`, no version field).
- Slots: add, edit capacity/time/active; Delete only on an inactive slot; a 409 (`data` key `SLOT_IN_USE`) shows "This slot has been used. Keep it inactive."; `SLOT_HAS_LIVE_ORDERS` / `AREA_HAS_LIVE_ORDERS` (also `data` keys) show "This area / slot has live Schedule orders (today or a later date). Change this once they are finished." (the backend guard counts held or paid groups with `service_date >= today`, not only today) Lowering capacity keeps confirmed bookings (new holds see the new limit).
- Shop panel: list from A1 (shows unassigned shops and each shop's current area), assign/move and clear (A3 `DELETE`); `SHOP_HAS_LIVE_ORDERS` (`data` key) shows "This shop has live Schedule orders."
- Tests: pure `.ts` unit specs through the Playwright unit runner (request builders, error-map mapping, same-day lock rule, time/fee formatting pinned to a real response sample); lint, `tsc`, build.

### Build refinements (pre-build review, 2026-11-18)

Defaults 6 and 7 below are the recommended picks, adopted so the build is unblocked; Samivan can override either before the PR.

1. **Error normaliser reads `data` keys, not `message`** (see the five shapes under Facts). One pure function `normaliseAreaError(error)` returns `{ fields: Record<field, string>, form: string | null, conflict: ConflictCode | null }`: a `data` key that is a known code maps to its field; a `data` key that is a conflict code (`AREA_CHANGED`, `AREA_HAS_LIVE_ORDERS`, `SLOT_HAS_LIVE_ORDERS`, `SHOP_HAS_LIVE_ORDERS`, `SLOT_ACTIVE`, `SLOT_IN_USE`) sets `conflict`; a bean-validation key is already a field name; an unknown key or `message`-only error goes to `form` (`message`, else a generic line). Never show the literal "Conflict" / "Validation failed".
2. **Code -> field table** (in `service-area.utils.ts`, pinned by a spec; unknown codes fall to `form`): `NAME_REQUIRED`, `NAME_TOO_LONG` -> name; `TIMEZONE_INVALID` -> timezone; `CENTER_INVALID` -> centre; `RADIUS_INVALID` -> radius; `NO_MODE` -> form (Eat Now / Schedule toggles); `ADVANCE_DAYS_INVALID`, `WINDOW_OFFSET_INVALID`, `SCHEDULE_SAME_DAY_ONLY` -> advance days / window offset; `WINDOW_OPEN_REQUIRED`, `WINDOW_AFTER_FIRST_LAST_CALL` -> window open time; `LAST_CALL_INVALID`, `PICKUP_LEAD_INVALID`, `CANCEL_FREEZE_INVALID`, `LATE_CANCEL_GRACE_INVALID` -> their fields; `DELIVERY_FEE_INVALID`, `PACKAGING_FEE_INVALID`, `MAX_SHOPS_INVALID`, `COMMISSION_NOTICE_INVALID` -> their fields; `SLOT_START_REQUIRED`, `SLOT_CAPACITY_INVALID`, `SLOT_DUPLICATE` -> slot editor (row-level, the message names the time). Source: `ServiceAreaValidator`; re-check the list at build.
3. **`updatedAt` is a zone-less `LocalDateTime` string: keep it verbatim.** Store the string from the last GET and send it back unchanged as `expectedUpdatedAt`; never parse it into a `Date` and re-serialise (precision and zone would change, and the server compares within 1 ms).
4. **Pause action.** `pausedOn` is a service DATE in the area's time zone (`ServiceDateResolver.isPaused`: that exact date is closed). "Pause today" computes today in the area's `timezone` (not the browser's) with a pure `todayInZone(zone, nowMs)` in `features/admin/services/service-area.utils.ts` (`Intl.DateTimeFormat("en-CA", { timeZone })`, `YYYY-MM-DD`), after a fresh GET; "Resume" sends null. The form also shows the current `pausedOn` and an explicit date field so a paused-tomorrow value is visible. Spec: a zone ahead of and behind UTC around midnight.
5. **Component split from the start** (templates are 226 / 303 lines; warn limit 250): `ServiceAreasList`, `ServiceAreaForm` (composition only) over field groups (`AreaBasicsFields`, `AreaWindowFields`, `AreaFeeFields`, `AreaModeFields`), `SlotEditor`, `ShopAssignmentPanel`, `AreaConfirmDialog`, as the `commission/` folder does. Fetch with the same one-effect rule (React Query keys like `deliveryZoneKeys`).
6. **Centre uses the shared `MapPicker`** (`shared/components/MapPicker.tsx`: `latitude`, `longitude`, `onChange`) plus number fields for lat/lng and radius that stay in sync; the picker only fills the numbers, the server still validates (`CENTER_INVALID`). Replaces "map picker out of scope".
7. **Time zone select**: a fixed list of IANA ids (Asia/Kolkata first) from `Intl.supportedValuesOf("timeZone")`, with the stored value always present so an unusual stored id never blanks the field.
8. **Test area, never a live one.** Before the browser check create a dedicated "TEST area (do not use)" with Schedule OFF, Eat Now ON, no shops assigned (one database, also production). Exercise slots on it; exercise shop assignment only with a shop that has no live orders, and clear it afterwards.
9. **Web `CLAUDE.md` is a stub:** conventions come from the code; run `/gcp` and `ui-engineer` before building; the PR description states "production keeps `schedule_enabled` OFF; no SQL".

### Part C: rollout

1. Backend PR (A1-A5) into `feature/schedule`; no SQL. 2. Web PR into `feature/schedule`. Nothing goes to `main` from 3.1; `schedule_enabled` stays OFF in production. Device/browser check on a local run before the PR; production data is the only database (Neon), so test with a dev area, never edit a live area.

## Review (devil's advocate + geld, 2026-11-15)

### Summary
**Verdict:** APPROVED WITH CHANGES. The page itself is straightforward; the backend has seven gaps that the page would put one click away, so a backend slice (3.1a) goes first.
**What changes** (before -> after):
- Reading a shop's area: no way -> one admin-only list endpoint (not a field on `ShopDto`).
- Deleting a slot: unchecked, a used slot hits a database error shown as "Something went wrong" -> a clean 409, and only an inactive, never-used slot can be deleted.
- Unassigning a shop: any empty or null body does it -> an explicit `DELETE`.
- Editing timing (slot start, timezone, last call, pickup lead) or moving a shop while today has live orders: allowed, and silently moves freeze times or breaks the shop's live board -> refused with a 409 until the service day is over.
- Saving an area form: last write wins -> a stale form is refused (409) instead of reverting a pause.
**Decisions for Samivan:** scope (lane-plan scope vs the wider row) and approval of changes 1-6 below. Everything else is decided in the findings.
**What geld decided for you:** read endpoint over a `ShopDto` field (an existing test forbids the field); `DELETE` for unassign over a null-vs-absent trick (no client uses it, so no compatibility cost); lock timing edits only while live orders exist (not forever); no server-side snapshot rework (too large for a pilot area).
**Must happen before deploy:** backend PR (3.1a) first, then web PR; no SQL.
**Unknowns:** none that block. Check at build: the exact "live" group statuses in `OrderGroup`/payment enums, and a real JSON sample for time and money shapes.

**Lenses run:** 0 environment, 1 purpose and access, 3 placement and ownership, 4 time and truth, 7 evolution, 8 isolation and API. **Skipped:** 2 data model (no table or column change), 5 money (fees are validated settings, no ledger), 6 performance (a small admin list; the catalog is cached 30 s). **Reference designs:** skipped (no new data model).
**Target:** Spring Boot, Neon Postgres (one database, also production), hand-run SQL (none here), one backend instance, Next.js admin.
**Codex second opinion:** see the Codex section below.

### Findings
**API-1 · risk · MUST — a `ShopDto.serviceAreaId` field is blocked and unsafe.** Evidence: `ShopServiceAreaAccessGuardTest` T2a-08 (fact); `ShopController.updateShop` binds `ShopDto` from the body and `GET /api/shops/{id}` is public (fact). Failure: adding the field fails the build, and if forced through, an owner write could move their shop into any area and guests would see internal topology. Change: A1 (dedicated admin list in `dto/admin`). Cost now: cheap.
**STATE-1 · risk · MUST — slot delete is unguarded.** Evidence: `deleteSlot` and `order_groups.slot_id` FK (fact), no FK-violation handler (fact). Failure: delete a slot that ever took an order -> database error -> "Something went wrong"; delete a used slot with no group row left -> orphan `service_area_slot_day`, `schedule_slot_freeze` and ticket rows. The API is already reachable, so this is a latent bug the page makes one click away. Change: A2. Cost now: cheap.
**API-2 · risk · MUST — empty body unassigns a shop.** Evidence: `SetShopServiceAreaRequest` comment and the deferred-list note in schedule-implementation-order.md (fact: "use DELETE or a required field when the admin assignment UI is built"). Failure: a client bug that omits the field removes a shop from its area and every Schedule menu for it. Change: A3. Cost now: free (no client).
**TIME-1 · risk · MUST — a timing edit moves a paid order's freeze.** Evidence: `ScheduleSlotFreezer.freezeSlot` reads the current slot start and area timezone, last call and pickup lead (fact, lines 38-52); `finishPaid` stored the order's `release_at` from the old values (fact). Failure: an admin moves a slot from 12:00 to 12:30 at 11:00 with paid groups for today: `release_at` says 11:00-ish, the freeze fires at the new time, the ticket and the restaurant's timing disagree. Same for timezone, last call and pickup lead. Change: A4 (lock while live orders exist). Other edits (fees, window, cancel freeze and grace) act on new holds or are snapshotted at payment; the in-flight-hold gap (a hold started before an edit, paid after) stays and is covered by the confirm dialog. Cost now: cheap.
**OWN-1 · risk · DEFAULT — full-replace `PUT`, no version.** Failure: admin A saves a stale form and reverts admin B's emergency `pausedOn`. Change: A6 (`updatedAt` / `expectedUpdatedAt`, optional, 409 on mismatch). Cost now: cheap; additive.
**MIG-1 · risk · MUST — moving or unassigning a shop with live orders.** Evidence: `ShopServiceDates` line 23 and `ScheduleHoldChecker` read the shop's current area; groups keep their own (fact). Failure: unassign a shop that has paid orders today: its live board answers "Service area not found" and the hold checker rejects its carts; a move points it at another area's slots. Change: A5. Cost now: cheap.
**API-3 · risk · SHOULD — three error shapes, and time/money formats.** Evidence: three handlers (fact); Jackson `JavaTimeModule` with timestamps off, `BigDecimal` as a JSON number (fact). Failure: a form that maps only domain codes shows nothing for a missing field or a bad time. Change: web error normaliser and parse-tolerant time handling (Part B); a real response sample pinned in a unit spec. Cost now: free.
**ENV-1 · risk · DEFAULT — one click flips Schedule on in production.** Evidence: single Neon database serves production. Mitigation: confirm dialog on turning Schedule on or Eat Now off; the "production stays OFF" rule is written in the PR description. Keep.
**Keep:** server is the only validator, forms mirror its messages; audit already written on every edit; no area DELETE; assignment under the admin namespace (guarded by tests); `findByIdForUpdate` row locking on edits.

### Design changes
| # | before | after | problem it solves | why better | cost | alternative, why it lost |
|---|---|---|---|---|---|---|
| 1 | no read of a shop's area | `GET /api/admin/shops/schedule-assignments` | API-1 | admin-only, tripwire-safe, one list for both views | one DTO, one query, one test | field on `ShopDto`: blocked by T2a-08 and owner write path |
| 2 | `deleteSlot` unchecked | 409 `SLOT_ACTIVE` / `SLOT_IN_USE` | STATE-1 | no DB error, no orphans; deactivate stays the retire path | four existence queries | UI-only (no Delete button): the API stays reachable |
| 3 | null/empty unassigns | `PUT` needs a value, new `DELETE` | API-2 | explicit intent | one endpoint, no client to migrate | keep null: silent removal |
| 4 | timing fields editable any time | slot start, timezone, last call, pickup lead refused while live orders exist (A4) | TIME-1 | freeze time and `release_at` cannot drift apart | one existence query per edit | snapshot freeze inputs on the group: a schema change, much larger, not needed for a pilot area |
| 5 | shop can move or clear any time | refused while the shop has live orders (A5) | MIG-1 | the shop's live board and hold checks stay valid | one existence query | migrate carts/groups to the new area: undefined business policy |
| 6 | area `PUT` last write wins | optional `expectedUpdatedAt`, 409 on mismatch (A6) | OWN-1 | a stale form cannot revert a pause | one DTO field each way, one compare under the existing row lock | ETag header: same effect, more plumbing |

### Devil's advocate trace
| DA point | outcome |
|---|---|
| derived vs stored: shop's area read from the DB, not inferred | already handled (stored on `shops.service_area_id`) |
| business logic in two places (form vs server rules) | already handled: server only; form mirrors messages (see web design) |
| nullable meaning: `serviceAreaId` null | absorbed (API-2) |
| shared mutable state: area settings full-replace | absorbed (OWN-1) |
| migration pain | rejected: no SQL in 3.1 |
| goal vs delta: slot delete reachable today | absorbed (STATE-1) |
| absence claims ("no read endpoint", "no FK handler") | searched by mechanism: DTO tripwire test, handler file, schedule-assignment consumers in all three client repos: confirmed |

### Invariants (locked decisions for /gcp and /judge)
| id | decision | enforced where | must honour |
|---|---|---|---|
| L1 | no DTO outside `dto/admin` and `dto/ops` mentions `serviceAreaId` | T2a-08 test | the new row DTO lives in `dto/admin` |
| L2 | a slot is deleted only when inactive and never referenced | `ServiceAreaAdminServiceImpl.deleteSlot`, same locked transaction | tables: `order_groups`, `service_area_slot_day`, `schedule_slot_freeze`, ticket publication, reservation lines |
| L3 | unassign is `DELETE`; `PUT` requires a value | controller + `@NotNull` | `AdminShopScheduleControllerTest`, `AdminRoutesSecurityTest` |
| L4 | while live orders exist (held or paid group, `service_date >= today` in the area timezone): slot start, timezone, last call and pickup lead do not change | `ServiceAreaAdminServiceImpl.update` / `updateSlot` | validator stays pure; this rule needs a repository read |
| L5 | the server is the only validator of area rules | `ServiceAreaValidator` | web mirrors messages only |
| L6 | a shop with live orders is not moved or cleared | `ShopScheduleAssignmentServiceImpl` | first assignment from none always allowed |
| L7 | an area update carrying a stale `expectedUpdatedAt` writes nothing | `ServiceAreaAdminServiceImpl.update`, under the row lock | field is optional |

### Rollout
Backend then web, both into `feature/schedule`; no expand/contract (no schema change); N-1 compatible (new endpoint, stricter `PUT`, no consumer); rollback = revert the PR. Lens 0: one shared database, so no test run edits a live area; web CI is lint plus build only, so the lane runs unit specs and `tsc` locally.

### Codex second opinion
Blind, read-only, plan path and questions only. Agreed with: the shop read must be admin-only and include unassigned shops, slot delete is unsafe, the reference inventory needs correcting, the three error shapes, the shop-move gap. Codex-only, verified in code and adopted: the freeze reads current slot/area settings (TIME-1 became MUST and now covers slot start, last call and pickup lead, not only timezone); the live board breaks after a shop move (MIG-1 became MUST); the stale full `PUT` (OWN-1 became DEFAULT with A6); the reservation lines are not a direct slot reference (inventory corrected); time and money JSON shapes (API-3). Disagreements, decided on evidence:
- **Unassign contract:** Codex keeps `PUT` with an explicit null and rejects an omitted property. Kept `DELETE`: a plain DTO cannot tell absent from null without extra machinery, and no client uses the endpoint, so there is no compatibility cost.
- **Capacity lowered below confirmed bookings (its I1):** not changed. Confirmed groups stay; only new holds see the new limit, which is the existing 2b.6 rule. The page says so.
- **Payment races for expired holds (its I2) and cross-instance cache lag (its I3):** out of 3.1; existing 2b.6 behaviour, and production runs one instance. Revisit at a second instance.
- **Delete race (its I6):** handled by deactivate-first plus the `order_groups` FK as the database backstop (A2), not a shared lock order.
Caveat: Codex's file:line citations were not all re-checked; every adopted point above was re-read in code.

### Implementation review (Codex read-only, on the built 3.1a diff, 2026-11-15)
Mutation evidence: 21 of 21 mutants killed, each by a named test, baseline green first (harness in the session scratchpad; guards, service wiring and the three live-query boundaries).
| # | Codex finding | Disposition |
|---|---|---|
| 1 | live-order check races an in-flight checkout | accepted residual: `finishPaid` computes `release_at` and the cancel window from the live area at payment, so a group that commits after an edit is consistent with it; only the displayed last call at hold time can differ; a shop moved in the same milliseconds as its checkout is the one narrow miss |
| 2 | deactivating a used slot stops its freeze (`DueSlotDays` skips inactive slots) | VERIFIED, fixed: deactivation joins the A4 lock |
| 3 | delete check vs a freezer holding a stale active snapshot | accepted residual: needs the freezer to fire for the deleted slot in the same instant; the only result is one orphan freeze row nothing joins |
| 4 | expiry boundary `>=` vs settlement `>` | kept: the conservative direction (one extra 409 at one millisecond); D2 mutation pins it |
| 5 | updatedAt precision after flush | VERIFIED as a real risk (Windows 100 ns clock vs Postgres microseconds), fixed: compare within 1 ms |
| 6 | tests: list contract and 409 envelope thin | fixed: row assertions and a 409 envelope test added |
| 7 | `ServiceAreaAdminServiceImpl` over 250 lines | kept: it was 256 before this slice (now 263); extracting the mappers is a separate refactor |

### Approval record
| finding or decision | option chosen | by | date |
|---|---|---|---|
| scope: lane-plan scope vs wider row | lane-plan scope | Samivan | 2026-11-15 |
| changes 1-6 (read endpoint, slot delete guard, unassign `DELETE`, timing lock, shop move lock, edit precondition) | approve all six | Samivan | 2026-11-15 |
