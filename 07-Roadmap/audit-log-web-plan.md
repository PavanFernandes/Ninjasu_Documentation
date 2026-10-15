---
id: ""
title: "Audit Log — Web Activity page (Phase 2) design plan"
summary: "Design direction, screen inventory, data/contract findings and scope decisions for the Ninjasu_Web Activity page, per-check activity timeline and Staff & Roles link; built on branch feature/audit-activity-page."
type: how-to
status: designing
apps: [web]
module: "audit"
anchors: []
verified_against: "Ninjasu_Web origin/main a81d671 + backend feature/audit-log 9ab2933"
updated: 2026-09-27
---

# Audit Log — Web Activity page (Phase 2) design plan

Tier: **new screen** (not a revamp). Design skill applied as: understand the product → diagnose data → one
direction → plan → build. No live capture (local dev writes hit production), so visual verification is via a
network-mocked browser run only.

## Who and what for

The reader is the **shop owner or manager at end of day / after an incident**, on a laptop (and sometimes a
phone), asking three things: *who handled table X*, *who voided / wrote off / settled*, *what did Asha do
today*. They are auditing people, so the screen must read like **evidence**: unambiguous who/what/when, sensitive
actions impossible to miss, nothing decorative competing with that.

## Data diagnosis (the sparse-screen check)

The backend event carries: `occurredAt, module, action, actionLabel, actorType, actorId, actorName, actorRoles,
entityType, entityId, entityLabel, rootType, rootId, reason, amount, changes`. Findings that shape the UI:

1. **No root label.** A KOT event knows `entityLabel="KOT #42"` but not "Table 5" — the table label lives on the
   check. So a row cannot say "voided KOT #42 on Table 5" by itself. UI: row shows the KOT, and a **"View table"**
   link opens the check story dialog whose header resolves the table label. *Follow-up (backend):* denormalize a
   `rootLabel` onto `audit_events` so rows are self-sufficient.
2. **No text search on the API.** Filtering loaded rows client-side would silently lie once a range spans several
   pages, so the "search by number" idea from the plan is **deferred** until the API supports it (needs a
   server-side `q` on `entity_label`). Not faked.
3. **Members query is gated by `team.manage`,** so a Manager/Accountant with `audit.view` cannot list staff. The
   Staff filter therefore takes its options from the **actors seen in the loaded events** (names are snapshots, so
   removed staff still appear), merged with the members list when the caller may read it.
4. **Staff ids are not displayed anywhere today** (`openedByStaffId`/`closedByStaffId` are typed but never
   rendered), so "names instead of UUIDs" becomes: show **Opened by / Closed by** names on the check detail,
   derived from that check's own activity events (works for removed staff, needs only `audit.view`).
5. **Only Phase 1 events exist** (floor, takeaway, billing, table settings). Module/event filters come from the
   catalog endpoint, so later modules appear with no web change; module *labels/icons* have a graceful fallback
   for keys the web has not seen.
6. **Time zone.** API days are India-only for now. The page builds Today/Yesterday/7-days/Custom in
   `Asia/Kolkata` (UTC+5:30, no DST) and sends UTC millis; span capped at 92 days.

## Direction — "Ledger spine"

Concept: a **day-grouped vertical timeline** (a spine with one node per event), not a data table. A table is right
for aggregates; an audit trail is a *narrative* ("who, then who, then who") and the per-check story is inherently
sequential. One layout serves the shop-wide feed and the single-table story.

```
 Activity                                       [↻ Refresh]
 Today · 7 days · Custom          Module ▾  Event ▾  Staff ▾  [Clear]
 ─────────────────────────────────────────────────────────────────
 TODAY · Sat 27 Sep
  ●  9:41 pm   Asha  Cashier        Settled bill  B-104 · ₹1,240
  │                                  Cash ₹700 + UPI ₹540                       View table
  ◉  9:32 pm   Ravi  Manager  ⚑      Voided KOT #42 · ₹640
  │            reason: customer left · was READY                               View table
  ●  8:58 pm   Guest                 Fired KOT #41 · ₹380                      View table
  ●  8:40 pm   Asha  Cashier        Opened table 5
 YESTERDAY · Fri 26 Sep
  …                                             [ Load more ]
```

- **Signature element:** the spine itself, with **sensitive events ringed in the brand rose** and flagged (⚑). The
  brand token is used *only* there (void, write-off, refund, QR regenerate, guest rejection) — everything else is
  neutral, so the eye lands on exactly the events an owner is hunting for. Uses the catalog's `sensitive` flag, not a
  hardcoded list.
- **Module** is shown by a small icon on the node (Floor, Takeaway, Billing, Settings), neutral-toned — colour is
  reserved for "sensitive".
- **Actor chip:** initials avatar + name + role in muted text; non-staff actors are labelled honestly — `Guest`,
  `System`, `Ninjasu Support` (platform admin) — never blank.
- **Expandable detail:** rows with `changes` get a chevron → `field: from → to` lines. Null/absent values show `—`.
- **Typography:** the app's existing font stack; times in tabular numerals for alignment. No new fonts, no new
  colour tokens.

Rejected: (a) **report-style table** — good for totals, poor for reading a sequence and for one component reused as
both feed and per-table story; (b) **Petpooja-style leakage summary cards** — needs an aggregate endpoint (Phase 4),
and cards over a partial page of rows would mislead.
Gives up: dense one-line scanning of many rows (a table would show more per screen). Mitigation: comfortable-but-tight
row height and a 50-row page.

## Screens & changes

| # | Surface | Change |
|---|---|---|
| a | `/shop/reports/activity` (new) | Activity page: date presets + custom range, Module / Event (grouped, from catalog) / Staff filters, day-grouped spine, expandable diffs, "View table", keyset Load more, skeleton / empty / error / no-access states. Deep-linkable: `?actor=<userId>`, `?module=…`, `?action=…`. |
| b | `CheckPanel` (check detail) | Adds an **Activity** section (the table's story, ascending) shown when the caller holds `audit.view`, and an **Opened by / Closed by** line with names from those events. Same `CheckActivityTimeline` component as the Activity page's "View table" dialog. |
| c | Staff & Roles → Team tab | Member row gains **View activity** (only with `audit.view`) → `/shop/reports/activity?actor=<userId>`. |
| d | Nav + landing | "Activity" item in the Reports group gated by `audit.view`; `ShopHome` redirect learns it so an audit-only role does not land on "no access". `audit.view` added to the web permission catalog + `useShopRole.canViewAudit`. |

New shared pieces (built reusable from the start): `MultiSelectFilter`, `ActorChip`, `AuditEventRow`,
`ActivityTimeline` (day grouping), `ChangesDiff`, `CheckActivityTimeline`, `ActivityFilters`.

## State & fetching rules honoured

One `useInfiniteQuery` keyed on the whole filter object (no stacked effects → one fetch per filter change); keyset
cursor from the API; catalog fetched once (long stale time); Skeleton for loading, `ErrorState` for failures;
whole-number spacing; `—` for null fields; no spinners for full-section loads.

## Not doing (and why)

- Search by number — API has no `q` (see finding 2).
- Aggregate/leakage cards, CSV export — Phase 4, needs endpoints.
- Kitchen events, guest/attention detail — deliberately not logged (Decisions 4, 8).
- Any change to the RN app.

## Verification approach

`tsc --noEmit` + `eslint` via `node` (never pnpm in the junctioned worktree); a Playwright run with the API
**mocked at the network layer** (`/api/proxy/**`), never a real backend. Anything not exercised is reported as
unverified.

## Build status (2026-09-29) — PUSHED, DRAFT PR Ninjasu_Web#27 (`feature/audit-activity-page`, 2 commits)

Devil's-advocate, an independent Codex review and a `/code-review` pass all ran before the PR. What the
shipped code does after those fixes:

- `checkStaffNames` counts `bill.writeoff_settled` as a closing action (a written-off-then-settled check
  used to credit whoever wrote it off).
- **Cache safety:** the login page clears the QueryClient on mount. It is deliberately NOT cleared in
  `useLogout` — there the layout's own polling queries are still mounted and would refetch against a dead
  session (a spurious "session expired" after an explicit logout).
- **Freshness:** `auditKeys.activity` is nested under the check (`["shop", shopId, "checks", checkId,
  "activity"]`, like `posKeys.bill`), so every existing `["shop", shopId, "checks"]` invalidation refreshes
  it. No per-dialog invalidations exist; do not add them.
- Custom range rejects pre-1970 dates and requires an exact round-trip; "Today" rolls forward on Refresh
  and when the tab becomes visible; the Staff filter accumulates staff seen so far; rows have content-based
  keys; the Activity section is keyed per check; amounts use the shared `formatPaise`; the single-select
  Staff filter is a real radio group.

**Declined on purpose:** raw JSON for object-valued `changes` (tenders/forceServedKotIds live in `metadata`,
which the list DTO omits, so it never renders); IST-vs-server-`zone` grouping (India-only v1 — a shop
timezone rollout must update `auditTime.ts` together with the API).

~55 mocked-browser checks pass; `tsc`/eslint clean (remaining warnings are in files this PR does not touch).

## Build status (2026-09-27) — built, UNCOMMITTED

Worktree `personal/ninjasu-web-audit-worktree`, branch `feature/audit-activity-page` (from origin/main `a81d671`).
17 files: new `features/shop/components/audit/*`, `audit.service.ts`, `auditTime.ts`, `auditDescribe.ts`,
`useAuditCatalog`, `useCheckActivity`, shared `FilterMenu` + `SegmentedControl`, route
`/shop/reports/activity`; edits to nav (`(shop)/layout.tsx`), `ShopHome` redirect, `TeamTab` (Activity link),
`CheckPanel` (+ its two callers), `useShopRole.canViewAudit`, `permissions.ts`.

**Verified:** `tsc` 0 errors; eslint 0 errors and 0 warnings in touched files; 45 mocked-browser checks (feed,
filters, cursor paging, repeated `module=` params with no brackets, IST day windows, story dialog, Details diff,
empty/error/loading/no-access, deep link, 390px mobile with no horizontal scroll, real dark mode, CheckPanel
names + Activity section with a single shared request, no leakage without `audit.view`, Team-tab link). Contrast
measured with `color.mjs`: brand text on its own wash was 4.41:1 (light) and 3.97:1 (dark), so the label text is
plain foreground and brand is used only for the ring, flag glyph and border (non-text, 3:1).

**Not verified:** anything against a real backend (the backend audit API is not deployed); the SQL/audit table
on Postgres; a phone-sized run of the check dialog; real-data volume/perf. A pre-existing `ThemeToggle` quirk
(dev StrictMode overwrites the saved theme) is unrelated and untouched.

## Follow-ups this build surfaced

- **Backend:** add a `rootLabel` to `audit_events` (a KOT row cannot say "on Table 5"); add a server-side `q`
  search on `entity_label` (search-by-number is deferred until then).
- `ItemStockControl`-style permission checks elsewhere already use `can()`; nothing else needed for `audit.view`.
- Staff-name lines exist only on the check detail (History rows carry no actor); add if wanted once the list
  endpoint returns opener/closer.
