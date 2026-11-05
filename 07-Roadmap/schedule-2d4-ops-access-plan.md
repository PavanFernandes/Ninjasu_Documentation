---
id: ""
title: "Schedule 2d.4 — area staff access and /api/ops/**"
summary: "Plan for AreaAccessService, the /api/ops/** matcher, the area-staff audit actor and /api/ops/me. Built on service_area_staff (task 0.5) and the admin-request model (admin-access-redesign.md)."
type: how-to
status: final
apps: [backend]
module: "auth"
anchors: []
verified_against: "backend bug/prepaid-cash-due working tree (2026-11-04)"
updated: 2026-11-04
---

# Schedule 2d.4 — area staff access and `/api/ops/**`

Source task: [schedule-implementation-order.md](schedule-implementation-order.md) 2d.4 ("Staff per ADR (0.5),
`AreaAccessService`, `/api/ops/**` matcher; handlers load the resource and read its area; ADMIN bypass audited";
tests: cross-area denial, forged area id ignored). Design history: [schedule-design-review.md](schedule-design-review.md) P2,
[admin-access-redesign.md](admin-access-redesign.md).

## Goal

One mechanism that answers "may this caller act on this Schedule resource", for area staff and the platform admin,
so 2d.5, 2d.6 and the Phase 3 ops board only call it. 2d.4 ships the mechanism, not the ops actions.

## Already built (verified in code)

- `service_area_staff(user_id, service_area_id NOT NULL, role)`, unique `(user_id, service_area_id)`, role CHECK
  `AREA_MANAGER | AREA_OPS`, FK to the area (`entity/ServiceAreaStaff.java`, `entity/AreaRole.java`,
  `repository/ServiceAreaStaffRepository.java`, `db_manual/service-area-staff-migration.sql`; required by
  `config/ScheduleSchemaGuard.java:79-81`).
- Admin is a property of the request: `JwtAuthFilter` grants `ROLE_ADMIN` only for a verified admin token
  (`security/JwtAuthFilter.java:73-78`), user tokens get `users.roles` minus ADMIN (`:85-87`);
  `AdminRequestAccess.isAdminRequest()` reads that authority.
- `PlatformAuditRecorder` writes `platform_audit_events` with `service_area_id`, same transaction (MANDATORY),
  but `record()` throws Forbidden unless `isAdminRequest()` (`service/impl/PlatformAuditRecorderImpl.java:44`).
- Resource areas: `OrderGroup.serviceAreaId`, `ServiceAreaSlot.serviceAreaId`, `Shop.serviceAreaId`.
  `Order` has only `groupId` (`entity/Order.java:47-48`), so an order's area is its group's area.

## Scope (build)

1. **`AreaAccessService`** (`service/schedule/access/`). Resource-taking methods, never a bare area id from a
   handler: `requireForGroup(groupId, minRole)`, `requireForOrder(orderId, minRole)` (via `groupId`; an order with
   no group is rejected), `requireForSlot(slotId, minRole)`, and `requireForArea(areaId, minRole)` for
   area-addressed reads (board, lists) where the id is a filter checked against the caller's own rows. Each loads
   the row, resolves the area, authorizes, and returns the loaded entity. Role order `AREA_OPS < AREA_MANAGER`.
   ADMIN request passes every check. Caller comes from the security context, not a parameter.
   Returns an `AreaGrant(entity, areaId, actorKind, role)`; handlers act only on the returned entity and check any
   second resource belongs to it (DA-3).
2. **Matcher.** `/api/ops/**` → `.access(opsAuthorizationManager)`, placed before `anyRequest()`: allow if
   `isAdminRequest()`, or (user token) the caller has at least one `service_area_staff` row and the dev-OTP gate
   passes (DA-1, DA-2). No `ROLE_OPS` authority anywhere. `JwtAuthFilter` also drops a stored `OPS` role,
   case-insensitively, like `ADMIN` (Codex 3).
3. **Area-staff audit actor.** New `AuditActorType.AREA_STAFF`. The recorder takes the `AreaGrant` and reads actor
   id, kind and area from the security context and the grant, never from caller arguments; metadata `actorRole`
   snapshot (DA-4, SNAP-1, Codex 7). Admin path unchanged.
4. **`GET /api/ops/me`** → `{ admin: boolean, areas: [{ serviceAreaId, name, role }] }`; `admin` means an admin
   **request** (admin token), not an admin user id.
5. **Guard tests.** An ops-specific guard: every mutating `/api/ops` handler is `@PlatformAuditedEndpoint`, plus an
   integration test that the recorder is called and a recorder failure rolls the mutation back (the existing
   declaration test checks annotations only, Codex 11); no resource-addressed ops request DTO carries
   `serviceAreaId`; no code reads `OPS` or `ADMIN` from `users.roles`.
6. **Housekeeping.** Fix the stale "FK-free" comments (DOC-1); grant/revoke SQL snippet that writes the audit row
   in the same transaction with the operator's own user id (DA-5, Codex 8).

## Decisions (LOCKED 2026-11-05)

Samivan approved the direction; closed with devil's advocate, geld, Raphael and Codex below.

| # | Question | Decision |
|---|---|---|
| D1 | How does staff pass the matcher | Custom `AuthorizationManager` on `/api/ops/**` reads `service_area_staff`; no `ROLE_OPS` authority; stored `OPS` stripped |
| D2 | Token for area staff | Ordinary user token for the pilot, **only behind the dev-OTP gate in code**; separate staff login when area staff are not Ninjasu employees |
| D3 | ADMIN bypass "audited" | Mutations audited (actor from the security context); reads logged at DEBUG with actor, resource id, area, no customer data |
| D4 | Grant API | None; SQL grants that write the audit row in the same transaction |
| D5 | Eat Now orders on `/api/ops` | Out; an order with null `groupId` is rejected |
| D6 | Cross-area / missing | Missing resource 404, exists in another area 403 (shop convention; ids are random UUIDs, so enumeration risk accepted) |
| D7 | Revoke during an in-flight request | No row locking. A request already past the gate may finish reading; an audited mutation re-reads the staff row when it writes its audit row and rolls back if the row is gone or its role changed (fail closed; built in `recordAreaAction`) |

## Tests (exit)

- Staff of area A: allowed on A's group/order/slot, 403 on B's; AREA_OPS denied an AREA_MANAGER action.
- Forged area id: a handler given B's group while the request also names area A authorizes against B (the row).
- A user with no staff row (any user token, customer or shop) → 403 on `/api/ops/**`; a staff row holder passes
  on either; row deleted → denied on the next request.
- `OPS`, `ops` or `ADMIN` written into `users.roles` grants nothing.
- Path variants (`/api/opsx`, trailing slash, `//api/ops`, `;` params, encoded slash) never reach an ops handler
  without the ops check.
- Tokens: admin token passes and `/ops/me` says `admin: true`; the same person's user token says `admin: false`;
  wrong key, wrong audience, legacy no-audience, inactive user.
- `OTP provider = dev` and override off → staff denied, admin unaffected.
- Order with null / missing / other-group `groupId` rejected.
- Admin mutation writes a PLATFORM_ADMIN row, staff mutation an AREA_STAFF row with `actorRole`; recorder failure
  rolls back the mutation.

## Devil's advocate (2026-11-04)

> **DA-1 — D1, ROLE_OPS granted in the filter by URL prefix.**
> **Failure:** the filter's own path check (`getRequestURI()`) and Spring's matcher normalise paths differently
> (`//api/ops`, `;` params, encoded slashes), so the two disagree; and an invented authority is one more thing
> every later matcher author can misuse.
> **Mitigation:** no authority in the filter. The matcher uses a custom `AuthorizationManager`
> (`.requestMatchers("/api/ops/**").access(opsAccess)`): allow if `isAdminRequest()` or the caller has at least
> one `service_area_staff` row. Same matcher decides path and access; nothing is added to `users.roles` or the token.
> **Verdict:** `proceed with conditions` (use the AuthorizationManager).

> **DA-2 — D2, area staff on the ordinary 7-day user token.**
> **Failure:** if production login runs the `dev` OTP provider (fixed code), anyone who knows an area manager's
> phone gets ops power, including refund approval in 2d.6.
> **Mitigation:** the ops AuthorizationManager denies non-admin staff when the phone OTP provider is `dev`, unless
> `app.ops.allow-dev-otp=true` (local only, default false). Revocation stays immediate (row read per request).
> **Verdict:** `proceed with conditions` (dev-OTP gate in code).

> **DA-3 — handler authorizes one resource and acts on another.**
> **Failure:** path has group A (authorized), body names order X of area B; handler loads X separately.
> **Mitigation:** `AreaAccessService` returns an `AreaGrant(entity, areaId, actorKind, role)`; handlers act only on
> the returned entity; for a second resource, check it belongs to the first (`order.groupId == group.id`).
> **Verdict:** `proceed with conditions`.

> **DA-4 — area-staff audit actor chosen by the caller.**
> **Failure:** a handler passes the wrong actor kind or area id, so the trail says the wrong person or area.
> **Mitigation:** the recorder takes the `AreaGrant`, not a raw area id or actor kind; actor = PLATFORM_ADMIN if
> admin request, else AREA_STAFF with a staff row for that area, else Forbidden.
> **Verdict:** `proceed with conditions`.

> **DA-5 — D4, SQL grants leave no trail.** The ADR wanted grant/revoke recorded.
> **Mitigation:** the documented grant/revoke SQL also inserts a `platform_audit_events` row in the same
> transaction (actor PLATFORM_ADMIN = Samivan). **Verdict:** `proceed with conditions`.

> **D3, D5, D6:** `proceed`. Revoke racing an in-flight request allows at most that one request (same as shop access); accepted.

## Geld (2026-11-04, proportionate run: no new table)

- **Built state:** `service_area_staff` in code and required at boot by `ScheduleSchemaGuard`; the feature/schedule
  backend booted on the one Neon DB during the test sprint, so the table is applied there *(inferred)*.
- **KEEP-1:** unique `(user_id, service_area_id)` serves the per-request `WHERE user_id = ?` lookup; area index for lists.
- **MODEL-1 (free):** new enum value `AuditActorType.AREA_STAFF`. `platform_audit_events.actor_type` is
  `VARCHAR(20)` with only the SYSTEM/actor_id CHECK (`db_manual/platform-audit-migration.sql:30-33`), so **no
  migration**. Do not reuse `STAFF` (means shop staff in `audit_events`).
- **SNAP-1 (CONSIDER):** record the actor's area role at action time in metadata (`actorRole`), since the row can change later.
- **DOC-1 (cheap):** `ServiceAreaStaff` and the migration header still say "FK-free", but the guard requires
  `fk_service_area_staff_area` (`ScheduleSchemaGuard.java:79`). Fix the comments.
- **PERF-1 (revisit at Phase 3 board polling):** one indexed staff lookup per ops request is fine; board polling
  must still follow the no-Postgres-per-poll rule.
- **Verdict:** APPROVED WITH CHANGES (MODEL-1, DOC-1). No SQL to run.

## Raphael (product / skeptic, 2026-11-04)

Pilot ops is one to three Ninjasu people, so SQL grants (D4), Schedule-only (D5) and the user token (D2) are right
for now. The one trust risk is D2 under a dev OTP; DA-2 closes it in code. Revisit D2 (separate staff login) when
area staff are not Ninjasu employees.

## Codex review (2026-11-05, read-only, 14 points; key ones verified)

Agreed with DA-1 to DA-5. Added: strip stored `OPS` (3, verified `JwtAuthFilter.java:85-87`); recorder takes
`adminId` from the caller today (7, verified `PlatformAuditRecorderImpl.java:41-49`); declaration test checks
annotations only (11, verified); possible Hibernate-generated CHECK on `actor_type` (9, verified
`ddl-auto=update` at `application.properties:32`), so the pre-deploy check below; existing admin-only Schedule
service paths (`ScheduleCancelServiceImpl` accept) must be widened deliberately in 2d.6, not by the matcher (14).

## Pre-deploy check (read-only, run before merging 2d.4)

```sql
-- READ-ONLY. Lists every constraint on the audit table; look for a Hibernate CHECK listing actor_type values.
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint WHERE conrelid = 'public.platform_audit_events'::regclass;
```
If a CHECK lists `actor_type` values, 2d.4 ships a migration that replaces it to include `AREA_STAFF` (geld
MODEL-1 then becomes a migration). Otherwise no SQL.

## Out of scope

Ops actions (2d.5 address fix, 2d.6 tickets/cancel/approvals, including widening the admin-only accept path),
grant UI, console host, staff token.

## Built (2026-11-05, branch `feature/schedule-2d4-ops-access`, uncommitted until Samivan asks)

`AreaAccessService` (+ `AreaGrant`, `ActorKind`), `OpsAccessAuthorizationManager` and the `/api/ops/**` matcher,
`RequestUser`, `AuditActorType.AREA_STAFF`, `PlatformAuditRecorder.recordAreaAction`, `AREA_STAFF_GRANTED/REVOKED`
audit actions, `GET /api/ops/me`, `JwtAuthFilter` strips `OPS`, grant/revoke SQL with audit rows in the
migration header, stale FK-free comments fixed. Config: `app.ops.allow-dev-otp` (default false).
Checked: targeted tests pass; four mutations (staff row ignored, role check dropped, OPS kept, dev gate off)
each fail a named test. Reviewed by Codex (general diff review plus correctness, security, tests lenses):
no correctness or security findings; test findings fixed except the two below.

## Not verified / owed (carry into the first ops mutation, 2d.5)

- **Database-backed audit tests.** Recorder transaction and rollback on a real database, and the grant/revoke SQL
  against Postgres, are not tested: there is no test database (the one Neon DB is production). Add a rollback
  test with 2d.5, the first ops mutation. Until then the grant/revoke SQL in the migration header is unrun.
- **Pre-deploy constraint check** (above) is still to be run before merge.
- Widening the admin-only accept path (`ScheduleCancelServiceImpl`) stays in 2d.6.

## Next

Commit when Samivan asks, PR into `feature/schedule`, then 2d.1/2d.3/2d.5/2d.2/2d.6 per the build order.

## Branch

From `feature/schedule`; PR into it. Do not switch branches in the shared checkout while the 2d.7 session has
uncommitted work (`bug/prepaid-cash-due`). No schema change.
