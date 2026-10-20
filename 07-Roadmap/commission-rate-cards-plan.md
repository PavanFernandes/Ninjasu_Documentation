# 2b.13 Commission rate cards — implementation plan

Status: **BUILT 2026-10-20 on `feature/schedule-2b13`** (backend 5 commits, web 1 commit; local only: not pushed, not merged, not deployed). Devil's advocate + four Codex reviews were folded into the plan, and a fifth Codex review of the code found three issues, all fixed. See "As built" at the end. Replaces the 2a.4 percentage `commission_rate` model.
Decisions: [schedule-plan.md](schedule-plan.md) #45, #46, D17-D26; task row 2b.13 in
[schedule-implementation-order.md](schedule-implementation-order.md).

## Terms

- **Rate card**: a named table of slabs (formerly "plan"). Example: *Standard*.
- **Slab**: one band of a rate card (Rs100-149 → Rs10).
- **Version**: an immutable copy of a card's slabs. Editing slabs creates a new version.
- **Assignment**: "shop X uses card version V for channel C from date D". Channel = `FulfilmentType` (`EAT_NOW`, `SCHEDULE`).

## Decisions locked (Samivan, 2026-10-19)

1. Name: commission rate card; slab = one band.
2. D18: a shop can have the same or a different card per channel. Stored as **one append-only assignment stream per (shop, channel)**. The admin "copy to both channels for this change" checkbox writes two rows in one transaction with one `operation_id`. It does not link the channels permanently. (Codex second opinion agreed; a single BOTH row plus overrides was rejected because of precedence bugs at checkout.)
3. Assignments **pin a card version**. Editing a card moves nobody. A restaurant moves to a new version only through an assignment with a **chosen `effective_from`**, one shop at a time or with a bulk "move all N" action.
4. **Every restaurant always has a card on both channels (2026-10-20, supersedes D24 and the null-snapshot answer).** A system card **"No commission"** (one slab `(0, 0, 0)`) is the default: the one resolver returns it when a (shop, channel) has no assignment row, so every customer order placed after 2b.13 snapshots a card version, never NULL. Nobody becomes unsellable on deploy day. The default card's slabs are locked (a new version would silently charge every unassigned shop with no notice); its name is fixed. Admin list "shops on the default card" replaces "shops with no card". Prices unchanged.
5. D21: seed **Standard only**. Card names are editable (name on the card header; versions immutable; rename audited; unique ignoring case).
6. Changing a shop's card needs a confirmation dialog (old → new, channel, effective date, worked example). Backend independently enforces the date rules (decision 7) and writes a platform audit row. **No `consent_ref` / reference field in 2b.13** (Samivan 2026-10-20: build the agreement/notice reference later, after everything else); it can be added later as a nullable column.
7. **Notice, not approval (2026-10-20).** A commission change is Ninjasu's decision; restaurants receive notice and may object externally (Ninjasu and the restaurant talk it out; no in-app objection flow now). A change takes effect on its `effective_from` with no restaurant approval.
   - A change must start **at least 24 hours** after it is saved.
   - Exception 1: a shop's **first real card** on a channel may start immediately. "First" is judged from history: that (shop, channel) has never had an effective non-default row (no rows at all counts as on the default). A shop that had a real card, returned to the default, and gets a real card again needs the 24h (or the override).
   - Exception 2: the admin may tick **"apply immediately"** with a mandatory reason (e.g. Ninjasu's own restaurant, pre-launch shop), audited. Single and bulk changes alike.
   - The 2a.4 per-area `commission_notice_days` is no longer used (column kept; drop later, DO NOT RUN NOW). A shop with no service area can be assigned a card.
8. **Forward-only + cancel (2026-10-20).** A new assignment must start later than every existing (non-cancelled) row for its (shop, channel). A row not yet effective can be cancelled (append-only cancellation row, audited); the one resolver ignores cancelled rows. A started row cannot be cancelled; add a later change instead. After a cancellation, a new row may start earlier than the cancelled one (forward-only counts non-cancelled rows only).
8. 2b.12(c) stays unmerged; 2b.13 branches from `origin/main`.

## Commission rule (unchanged from #45)

Per order line: `unit = sum of the line's selected add-on selling prices` (online price after the restaurant-funded discount, D17; this is what `OrderAssembler.computeLineTotal` already sums from the cart snapshot, `CartPricingServiceImpl` uses `SalesChannel.DELIVERY`). Find the slab with the largest `from_amount ≤ unit`;
`unit_commission = round_half_up_to_rupee(flat_amount + percent_above × (unit − from_amount) / 100)`;
`line_commission = unit_commission × quantity`; order commission = sum of lines. Payout is **not** computed or stored per order: it is a batch figure (item proceeds − commission − GST on commission − TDS ± refunds) built in 2c.
Delivery and packaging are excluded. GST on commission is **not computed in 2b.13** (CA task 0.7); the snapshot stores the pre-GST commission.

Standard card v1: `(0, 5, 0) (100, 10, 0) (150, 15, 0) (200, 20, 0) (250, 25, 0) (300, 25, 10)` as `(from_amount, flat_amount, percent_above)`.

Validation of a version's slabs: at least one slab; the first `from_amount` is 0; `from_amount` strictly increasing; `flat_amount ≥ 0`; `percent_above` in 0-100; **commission never decreases as price rises** (at each boundary the new slab's flat amount ≥ the previous slab's commission at that price), so a dearer unit can never pay less.

## Slices (each a draft PR into `feature/schedule-2b13`; one final PR to `main`)

### S1 Backend — rate cards, versions, calculator
- Tables (hand-run SQL `db_manual/commission-rate-card-migration.sql`, idempotent):
  - `commission_rate_card(id, name, is_system_default BOOLEAN NOT NULL DEFAULT false, created_by, created_at, updated_at)`; unique index on `lower(btrim(name))`; partial unique index `ON (is_system_default) WHERE is_system_default` (at most one default). Only `name`/`updated_at` may change, and never on the default card.
  - `commission_rate_card_version(id, card_id, version_no, created_by, created_at)`; unique `(card_id, version_no)`; append-only trigger (UPDATE/DELETE/TRUNCATE blocked, copy of `commission_rate` triggers).
  - `commission_slab(id, version_id, from_amount NUMERIC(10,2), flat_amount NUMERIC(10,2), percent_above NUMERIC(5,2))`; unique `(version_id, from_amount)`; CHECKs; append-only trigger.
  - Seed the system card **"No commission"** v1 (`(0, 0, 0)`, `is_system_default = true`; a partial unique index allows only one; the API refuses rename and new versions for it).
  - Seed Standard v1 under a **fixed card id** (names are editable, so a rerun keyed on the name could create a second Standard); reruns leave the existing card and v1 alone.
  - Adding a version locks the card row; a duplicate `version_no` maps to 409.
- `CommissionSlabCalculator` (pure, no Spring): `unitCommission(slabs, unit)`, `lineCommission(slabs, unit, qty)`; `SlabValidator` (pure).
- Admin API (`/api/admin/commission-rate-cards`, `@PlatformAuditedEndpoint`): list; get with versions; create (name + first version); rename; add version. New audit actions `RATE_CARD_CREATED`, `RATE_CARD_RENAMED`, `RATE_CARD_VERSION_CREATED`.
- `ScheduleSchemaGuard`: add the new tables, unique indexes and triggers.
- Tests: slab boundaries (99 → 5, 100 → 10, 299 → 25, 300 → 25, 305 → 26, 400 → 35, 500 → 45); thali 200 + 20 + 10 = 230 → 20, × qty 3 → 60; validator rejects gaps, unsorted, negative, a decreasing boundary; rename keeps versions; duplicate name (case-insensitive) rejected; version rows immutable (schema test).

### S2 Backend — assignments
- Table `commission_rate_card_assignment(id, shop_id, fulfilment_type, card_version_id, effective_from BIGINT, operation_id, immediate_reason, created_by, created_at)` plus `commission_rate_card_assignment_cancellation(assignment_id PK, reason, created_by, created_at)` (append-only); unique `(shop_id, fulfilment_type, effective_from)`; append-only trigger; FK to `commission_rate_card_version` only (no FK to shops, cross-domain rule).
- Resolver (the only reader): among non-cancelled rows for `(shop, channel)`, the one with the greatest `effective_from ≤ at`; **none → the system "No commission" card's v1**; no area fallback.
- Assign endpoint: body `{ shopId, channels: [EAT_NOW, SCHEDULE] (1 or 2), cardVersionId, effectiveFromMs | applyNow + immediateReason, expectedLatest: {channel: assignmentId|null} }`. Rules: shop exists and is not deleted; version exists (the default card's v1 is a valid target: an explicit, audited return to no commission); the server takes one instant `now` for validation and the row; `effectiveFromMs ≥ now + 24h`, except (a) first real card for that (shop, channel), judged from history as in decision 7 (`≥ now` allowed) or (b) `applyNow` with a non-blank `immediateReason`; **forward-only**: `effectiveFromMs` > every non-cancelled row of that (shop, channel); within `MAX_HORIZON_DAYS` (constant moves here from `CommissionRateValidator`); **row lock on the shop**, then compare `expectedLatest` = the **latest assignment id per channel, including scheduled (future) rows**, and reject with 409 on any mismatch; both channel rows in one transaction with one `operation_id`.
- Cancel endpoint: only a row with `effective_from > now`; writes a cancellation row + audit `RATE_CARD_ASSIGNMENT_CANCELLED`; same shop lock + `expectedLatest` check.
- Preview endpoint for the confirmation dialog: current card + version per channel, the proposed one, worked example (Rs230 unit before → after).
- Bulk move: `GET .../versions/{id}/affected` lists (shop, channel) pairs whose **latest** assignment (current or scheduled) points to an older version of the same card, with N; `POST .../versions/{id}/move` with `effectiveFromMs` (or `applyNow` + reason), and the previewed pairs **each with its expected latest assignment id** (any mismatch rejects the whole move; nothing is written; the admin re-previews). The preview simply never lists pairs whose latest row points elsewhere. At most 200 pairs per request; shops locked in id order. The 24h rule applies to every pair; the first-real-card exception never applies (bulk moves only move shops already on a real card); `applyNow` + reason is allowed.
- Audit: `RATE_CARD_ASSIGNED` (one row per pair), `RATE_CARD_BULK_MOVED`; `operationId` is added to both actions' metadata allowlists (the recorder drops unlisted keys).
- Admin list "shops on the default card" — the S5 query (implicit and explicit cases, both tested); feeds the post-deploy checklist.
- Tests: copy-to-both writes 2 rows in one tx (and neither if one fails); stale `expectedLatest` → 409; a date under 24h rejected, exactly 24h accepted; first real card off the default may start now; `applyNow` without a reason rejected; a date not after an existing scheduled row rejected (forward-only); cancel works only before the row starts and the resolver then ignores it; no row → default card v1; shop without an area accepted; resolver picks the latest effective row and never a future one; a card edit moves nobody; bulk move moves exactly the previewed set; a placed order keeps its version after a reassignment (re-proves T2a-12/T2a-13).

### S3 Backend — Eat Now order snapshot
- Columns (nullable, hand-run SQL): `orders.commission_card_version_id`, `orders.commission_total`; `order_lines.unit_commission`, `order_lines.line_commission`. Every customer order after 2b.13 has values (the default card gives 0). NULL means only "not applicable": a dine-in channel (POS, guest QR, counter sale) or an order placed before 2b.13; written as a column comment.
- Rounding uses one shared rupee helper (the #27 function, built here, reused by 2c).
- In `OrderAssembler.buildLinesFromCartItems` (shared by COD `OrderServiceImpl` and online `PaymentServiceImpl`), for `OrderSource.CUSTOMER` orders only: resolve the shop's `EAT_NOW` card version through the one resolver at the assembly instant (no row → default "No commission" v1, commission 0); always fill line and order snapshots. POS, guest QR and counter sale record nothing.
- Prices, totals and customer responses unchanged (no DTO change for customers).
- Tests: snapshot equals the calculator for a multi-line order; delivery fee excluded; a shop with no assignment row → default v1 pinned, commission 0; a later reassignment doesn't change a placed order; POS order has nulls; online checkout path snapshots identically to COD.

### S3b Backend — order invoice snapshot (Samivan 2026-10-20: in 2b.13, same for Eat Now and Schedule)
Freeze at order time everything a later invoice, payout statement or GST return needs, so nothing is re-read from live, editable records (Codex payout research 2026-10-19).
- One shared step (e.g. `OrderInvoiceSnapshot`) called by `OrderAssembler` for customer orders; the Schedule checkout (2b.3/2b.5) must call the same step, never a copy.
- New nullable `orders` columns (hand-run SQL `db_manual/order-invoice-snapshot-migration.sql`, added to `ScheduleSchemaGuard` and to the pre-deploy SQL list): `restaurant_gstin` (`Restaurant.gstNumber`, NULL = unregistered), `restaurant_gst_regime` (`Shop.gstRegime`), `restaurant_address`, `restaurant_state` (`Shop` address fields); `platform_legal_name`, `platform_gstin`, `platform_address` (`PlatformBillingConfig`). The trade name is already frozen in `orders.shop_name`.
- Per line, the existing snapshot (`tax_class_code`, `tax_price_mode`, `tax_rate_percent`, `line_total_snapshot`) is the frozen tax classification; whether a line is a 9(5) restaurant service is read from its frozen `tax_class_code` (`RESTAURANT_SERVICE`). No new line columns.
- **No tax amounts are computed or stored in 2b.13.** Customer orders charge no GST today (`OrderAssembler`: `grand_total = subtotal + delivery fee`), and the dine-in `GstTaxEngine` taxes by the restaurant's GST regime, which is the wrong basis for 9(5) online orders (Ninjasu owes the food GST whatever the restaurant's regime). The online tax basis (prices GST-inclusive, or 5% added at checkout) is a separate decision (open question H) and must be settled before go-live.
- Data gaps found (not invented here; recorded for CA task 0.7 / onboarding): no **restaurant legal name** field (only the trade name); `Shop.state` is free text, not a GST state code; orders store no **delivery state** (only lat/lng + formatted address), which the place-of-supply rule may need. Each is a follow-up, not a 2b.13 build item, unless Samivan pulls it in.
- No invoice numbers, PDFs, payout batches, TDS or credit notes here: those are 2c, built from these frozen facts.
- Tests: snapshot equals the live values at order time and does not change when the shop's GSTIN/name or `PlatformBillingConfig` is edited afterwards; unregistered shop → NULL GSTIN; customer totals (`subtotal`, `grand_total`) are byte-for-byte unchanged by S3/S3b; POS, guest QR and counter-sale orders get no snapshot.

### S4 Retire 2a.4
- Remove the `CommissionRate` entity, repository, resolver, validator, service, controller, DTOs and their guard entries and tests; fix the `ServiceAreaValidator.java:28` comment; move the old controller's case in `AdminRoutesSecurityTest` to the new admin routes. Before the DROP script: Samivan runs `SELECT count(*) FROM commission_rate` on prod. **Keep** the `COMMISSION_RATE_CREATED` audit enum value (old `platform_audit_events` rows reference it). Keep `service_area.commission_notice_days` (deferred notice rule may use it).
- The `commission_rate` table stays; a DROP script is written and labelled **DO NOT RUN NOW** (run after 2b.13 is live and the table is confirmed empty or archived).

### S5 Web (Ninjasu_Web) — admin screens
- Rate cards page: list (name, latest version, shops on it per channel); create; rename; new version with a slab editor and a live example (Rs99 / 230 / 305 / 500 → commission and payout); version history (read-only).
- Shop commission panel (admin shop detail): current + scheduled assignment per channel; Change → card + version, channels, "copy to both channels for this change" (default on), effective date (min 24h ahead unless first real card) or "apply immediately" + reason; cancel a scheduled change; **confirmation dialog** with old → new and the worked example.
- Bulk move dialog on a new version: "this affects N restaurants", the list, one date (or apply immediately + reason), confirm.
- "Shops on the default (No commission) card" list, per channel, showing **implicit** (never assigned) vs **explicit** (assigned back, audited). Backend: one paginated query over live shops left-joined to each (shop, channel)'s latest non-cancelled effective assignment (index on `(shop_id, fulfilment_type, effective_from DESC)`), never a per-shop resolver loop.
- No mobile (RN) change: customers see no difference; the restaurant sees no commission yet (D25).

## Open questions for Samivan (from the devil's-advocate + Codex reviews, 2026-10-19)

- ~~A~~ decided: no per-order payout column; payout is a 2c batch figure.
- ~~B~~ decided → decision 8. ~~C~~ decided → decision 4 (write the D24 supersession into schedule-plan.md). ~~D~~ decided → decision 7 (update #46 and the 2b.13 row to match).
- ~~F~~ decided: S3b in 2b.13, shared by both channels. ~~G~~ decided: no reference field now; build later.
- **H. Online GST basis (NOT a 2b.13 build item; must be decided before go-live).** Customer orders charge no GST today. Under 9(5) Ninjasu must collect and pay the 5% food GST on every restaurant-service order. Decide with the CA (0.7): are online prices GST-inclusive (customer total unchanged, Ninjasu's taxable value = price ÷ 1.05) or is 5% added at checkout (customer total rises)? Then build the online tax calculation and its stored tax lines as their own task.
- Not live yet (Samivan 2026-10-20): no payouts are running, so no backfill or migration of live money data is needed.
- **E. D25** (the "keeps Rs X" line): **confirmed out of 2b.13** (Samivan 2026-10-19).

Review checks that passed (Codex, files read): COD and online checkout both go through `OrderAssembler.assemble`; online confirm loads the saved order and never reprices; counter sale and guest QR build lines in `PosOrderServiceImpl`; `DeliveryServiceImpl` does not assemble orders; the cart uses `SalesChannel.DELIVERY` → online price after discount; `ScheduleSchemaGuard` fails boot when hand-run objects are missing, so **SQL must run before the deploy**.

## Out of scope / deferred

- **D25: "Ninjasu keeps Rs X, you get Rs Y" in the restaurant menu editor — Samivan wants to discuss before 2b.13 proceeds.**
- Notice-period minimum (decision 7).
- GST on commission, 9(5) treatment (CA 0.7, before 2b.3).
- Partial refunds: customer orders today refund whole orders only (`orders.refund_id`); the per-line snapshot is what a future partial refund will return. The "partial refund returns that line's commission" test lands with the refund feature (2c/2d).
- The agreement/notice reference on assignments (former `consent_ref`), and any in-app objection flow.
- Settlement export / payouts (2c).

## Rollout

1. S1, S2, S3 and S3b SQL handed to Samivan and run **before** the backend deploy (`ScheduleSchemaGuard` fails boot on any missing object; each script additive, nullable columns, no backfill).
2. Merge order: backend final PR first (prod auto-deploy), then web.
3. After deploy: Samivan assigns Standard v1 to pilot shops on `EAT_NOW` (and `SCHEDULE`) from the admin page.
4. S4 DROP script: DO NOT RUN NOW.

## As built (2026-10-20)

**Branches:** backend and web `feature/schedule-2b13` from `origin/main`. Backend commits: S1, S2, S3, S3b+S4, review fixes. Web: S5. Nothing pushed.

**Hand-run SQL, in this order, before the backend deploy** (all idempotent; `ScheduleSchemaGuard` fails boot if any object is missing):
1. `db_manual/commission-rate-card-migration.sql` (cards, versions, slabs, triggers, seeds "No commission" + Standard v1 under fixed ids)
2. `db_manual/commission-rate-card-assignment-migration.sql` (needs 1)
3. `db_manual/order-commission-snapshot-migration.sql` (needs 1)
4. `db_manual/order-invoice-snapshot-migration.sql`

**DO NOT RUN NOW:** `db_manual/commission-rate-drop-DO-NOT-RUN-NOW.sql` (drops the 2a.4 `commission_rate` table; run only after 2b.13 is live and `SELECT count(*) FROM commission_rate` is 0).

**Production note (2026-10-20):** a local `mvnw test` booted the app on the production Neon database (the default datasource) and left three empty, constraint-less tables: `commission_rate_card`, `commission_rate_card_version`, `commission_slab`. SQL file 1 uses `CREATE TABLE IF NOT EXISTS` and adds the constraints, indexes, triggers and seeds on top, so running it repairs them; nothing else was touched. Full-suite runs now exclude the context test: `-Dtest='!NinjaDeliveryServiceApplicationTests'`.

**Admin routes (all under the `/api/admin/**` catch-all):** `commission-rate-cards` (list, get, create, rename `PATCH`, `/{id}/versions`, `POST /preview` for the slab editor), `commission-rate-card-assignments` (state by `shopId`, `/preview`, `/on-default`, assign, `/{id}/cancel`), `commission-rate-card-versions/{id}` (`/affected`, `/move`). Web: `/admin/commission-cards`, `/admin/commission-cards/[id]`, and a Commission tab on the shop page.

**Differences from the plan text:**
- `POST /commission-rate-cards/preview` (stateless, `@NotAudited`) was added so the slab editor shows live commission and violations without the web app re-implementing the calculator.
- A `Clock` bean (`config/ClockConfig`) was added. The assign, cancel and bulk-move services read "now" after the shop lock is held, so a lock wait cannot shorten the 24-hour notice or let a change that has started be cancelled (Codex review finding).
- The shared rupee helper the plan put in S3 is `CommissionSlabCalculator` itself; there is no separate class.
- Snapshot columns are guarded by CHECK constraints (version and total both set or both null, never negative; regime values match `GstRegime`).
- A cancelled assignment still occupies its (shop, channel, start) key; a new row at exactly that moment is rejected with `DUPLICATE_EFFECTIVE_FROM`.
- The "shops on the default card" list says "Never assigned" (implicit) or "Set to no commission" (assigned on purpose).

**Verified:** backend suite with the context test excluded (990 tests, 0 failures), JPQL parse-checked offline, web `tsc` and `eslint` clean, 13 pure-logic web specs, static render of the list, detail, shop panel and slab editor.
**Not verified (no scratch database, browser or device):** the SQL scripts and trigger behaviour against Postgres; JPQL result correctness (parse only); every dialog (they render in a portal); any real click-through. Run both on a Neon branch before merging.

**Open before go-live:**
- `platform_billing_config` row 1 must exist; if it is missing, orders still complete but carry no platform legal facts (a warning is logged).
- Question H (online GST basis, CA task 0.7) is still undecided; the order snapshots store no tax amounts.
- Restaurant legal name, GST state code on shops and delivery state on orders are still missing (follow-ups for 0.7 and onboarding).
