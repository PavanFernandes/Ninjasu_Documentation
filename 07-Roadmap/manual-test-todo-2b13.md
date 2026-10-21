---
id: ""
title: "Manual test TODO — 2b.13 commission rate cards, order snapshots and platform seller profiles"
summary: "Manual test list for everything 2b.13 built but could not prove from code: the five hand-run SQL files and their triggers, the JPQL results, concurrent admins, checkout snapshots, the admin web screens and the platform profile API. Run on a Neon branch, never on prod."
type: how-to
status: active
apps: [web, backend]
module: "schedule"
anchors:
  - { repo: backend, path: "db_manual/commission-rate-card-migration.sql" }
  - { repo: backend, path: "src/main/java/com/example/ninja/repository/CommissionRateCardAssignmentRepository.java" }
  - { repo: web, path: "src/features/admin/components/commission/ShopCommissionPanel.tsx" }
  - { repo: web, path: "src/features/admin/components/commission/ChangeCardDialog.tsx" }
verified_against: "backend 69017a8 and Ninjasu_Web bf29f54 on feature/schedule-2b13 (2026-10-21); nothing below has been run"
updated: 2026-10-21
---

# Manual test TODO: 2b.13 (updated 2026-10-21)

Owner: **S** = Samivan, **C** = Claude. Nothing below has been run. What IS verified in code: backend suite 1036 tests with the context test excluded, web `tsc` and ESLint clean, 13 pure specs, a static render of the list, detail, shop panel and slab editor. What no check could prove: the SQL on a real Postgres, JPQL results, locks under two admins, every dialog, and the screens in a browser.
**Write only against a Neon branch, never prod.** The backend's default datasource is production; a bare `mvnw test` once booted the app on prod. Run tests as `./mvnw test "-Dtest=!NinjaDeliveryServiceApplicationTests"` (no `-o`: the offline cache lacks the Spring Boot parent).

## What a Neon branch is
A Neon branch is an instant copy of the production database (copy-on-write, so it costs almost nothing). Writes to the branch never touch prod, and you delete it when finished. Create it in the Neon console: project, Branches, Create branch, parent `main` (production), then copy its connection string.

## A. Setup
- [ ] **S** Create a Neon branch of prod (name it `test-2b13`). Copy its connection string.
- [ ] **S** Run the backend locally with `DB_URL`, `DB_USERNAME`, `DB_PASSWORD` set to the BRANCH, then confirm with `select current_database(), current_setting('neon.endpoint_id', true);` that you are on the branch before any write. Also set `APP_JWT_SECRET`.
- [ ] **C** Point Ninjasu_Web `.env.local` at the local backend (not ngrok or prod); serve the admin area on the admin host the proxy expects.
- [ ] **C** Test users on the branch: a platform ADMIN (`PLATFORM_ADMIN_USER_IDS`), a customer (test phone 9999999001, dev OTP 1234), two live shops with a menu (one with a required price group), one shop with NO assignment.
- [ ] **C** Test from `feature/schedule-2b13` in backend and Ninjasu_Web.

## B. SQL files, on the branch, in this order (folder `ninja delivery service java/db_manual/`)
- [x] **S** (ran 2026-10-21 on endpoint ep-morning-violet-a1f3okbi, 94 orders; cards "No commission" + "Standard" both INR, 7 slabs, verified read-only) 1 `commission-rate-card-migration.sql` — runs without error; `select name, is_system_default from commission_rate_card` shows "No commission" (default) and "Standard"; `select count(*) from commission_slab` is 7 (1 + 6).
- [ ] **S** Run file 1 a SECOND time: no error and the same counts (seeds are not duplicated).
- [x] **S** 2 `commission-rate-card-assignment-migration.sql` (ran 2026-10-21).
- [x] **S** 3 `order-commission-snapshot-migration.sql` (ran 2026-10-21; column is `commission_rate_card_version_id`, three constraints validated).
- [x] **S** 4 `order-invoice-snapshot-migration.sql` (ran 2026-10-21; table and both triggers exist, 0 rows).
- [x] **S** (ran 2026-10-21; table empty, FK from the snapshot exists) 5 `platform-seller-profile-migration.sql` — if the old `platform_billing_config` had a row it appears as profile `PRIMARY`, default and active; otherwise the table is empty.
- [x] **S** (done 2026-10-21: files 4 and 5 rerun with "already exists, skipping"; counts unchanged: 2 triggers, 3 constraints on the snapshot, 2 checks and 2 unique indexes on the profile table) Rerun files 2 to 5 once each: no error, no duplicates.
- [x] **S** (verified 2026-10-21, all true) After file 3: `select conname, convalidated from pg_constraint where conrelid in ('orders'::regclass, 'order_lines'::regclass) and conname like '%commission%'` shows `convalidated = true` for all three.
- [ ] **S** The default card "No commission" has version 1 with its one slab 0/0/0, and `currency_code = 'INR'`.
- [x] **S** (done 2026-10-21: old column gone, new column present, no duplicate constraints) Upgrade path (database that ran the OLD files 1-3): rerun file 1 then file 3. `commission_rate_card.currency_code` exists and `orders.commission_card_version_id` is renamed to `commission_rate_card_version_id`, with no duplicate constraints.
- [ ] **S** Backend-started-first case (on a second branch of prod, before running file 3): boot the new backend once so Hibernate adds `commission_rate_card_version_id` beside the old column, then run file 3. Afterwards only the new column exists, the three constraints exist once, and an order insert works. (Codex review finding, 2026-10-21.)
- [ ] **S** After the last file, `show lock_timeout;` is back to its default (file 3 ends with `RESET lock_timeout`).
- [ ] **S** `update commission_rate_card set currency_code = 'USD' where name = 'Standard'` fails (currency is immutable).
- [ ] **S** `order_seller_snapshot` rejects update, delete and truncate (append-only).
- [ ] **S** Bare-table repair: on a second branch, let the backend boot once BEFORE running file 1 (Hibernate creates empty shell tables), then run file 1: the constraints, indexes, triggers and seeds appear (`\d commission_slab` shows the unique index and the trigger).
- [ ] **S** Boot the backend after the five files: the schema guard passes (no "Schedule schema verification failed").
- [ ] **S** Boot it with file 5 NOT run: it must refuse to start and name `platform-seller-profile-migration.sql`.

## C. Database rules (psql on the branch)
- [ ] `update commission_slab set flat_amount = 1;` fails ("append-only"); same for `delete from commission_slab`, `truncate commission_slab`.
- [ ] Same three statements fail on `commission_rate_card_version`, `commission_rate_card_assignment` and its cancellation table.
- [ ] `update commission_rate_card set name = 'X' where is_system_default;` fails; renaming "Standard" works; `delete from commission_rate_card` fails.
- [ ] A second system default card cannot be inserted (unique partial index).
- [ ] Two cards named `standard` and `STANDARD ` cannot coexist (case and space insensitive).
- [ ] A slab with `percent_above = 101` or negative amounts is refused by the CHECK.
- [ ] `platform_seller_profile`: two defaults refused; default with `active = false` refused; GSTIN of 14 characters refused; code `ka` and `KA` clash.

## D. Rate cards API (admin token; run against the local backend)
- [ ] `GET /api/admin/commission-rate-cards` lists both seeded cards with latest version 1.
- [ ] `POST .../preview` with Standard's slabs returns commission 5, 20, 26, 45 for 99, 230, 305, 500; with a first slab not at 0 it returns the violation and no samples.
- [ ] Create a card with 21 slabs: refused (`TOO_MANY_SLABS`); with a decreasing boundary: refused.
- [ ] Add a version identical to the latest: refused (`SAME_AS_LATEST`); change one amount: version 2 is created; shops stay on version 1.
- [ ] Rename to an existing name (any case): 409. Rename or add a version on "No commission": refused.
- [ ] Non-admin tokens (shop owner, rider, customer) get 403 on every route; no token gets 401.

## E. Assignments API: the rules, with real data
- [ ] Shop with no row: `GET .../commission-rate-card-assignments?shopId=` shows the default card on both channels, `latestAssignmentId` null, first-card eligible.
- [ ] Create a card with `currencyCode: "USD"` and assign it to an INR shop: refused with `CURRENCY_MISMATCH`, nothing written. Assigning the system default card to any shop is allowed.
- [ ] Assign Standard v1 starting NOW to a never-assigned shop: accepted (first real card).
- [ ] Assign Standard v2 to the same shop starting in 1 hour: refused (24h notice); at exactly 24h ahead: accepted; "apply immediately" without a reason: refused, with a reason: accepted.
- [ ] A start earlier than or equal to the shop's latest scheduled change: refused (`NOT_AFTER_EXISTING`).
- [ ] Both channels in one request writes two rows with one `operationId`; if one channel breaks a rule neither is written.
- [ ] Stale `expectedLatest` (send a wrong id): 409 and nothing written.
- [ ] Cancel a scheduled change: accepted; the resolver ignores it (order test in F); cancelling a started change: refused; cancelling twice: 409.
- [ ] After a cancel, a new change at exactly the cancelled start time is refused (`DUPLICATE_EFFECTIVE_FROM`); a later time works.
- [ ] Assign the default "No commission" card back to a shop that had a real card: accepted only with 24h notice.
- [ ] **Two admins at once** (two terminals, same shop, same `expectedLatest`): exactly one succeeds, the other gets 409.
- [ ] Bulk: create Standard v2, then `GET .../commission-rate-card-versions/{v2}/affected` lists only shops whose LATEST row is on v1 (not shops on another card, not deleted shops, not shops already on v2); `POST .../move` moves exactly that set with one `operationId`; a stale pair rejects the whole move and writes nothing; 201 pairs refused.
- [ ] `GET .../on-default?channel=EAT_NOW` lists shops with no row ("Never assigned") and shops assigned the default on purpose ("Set to no commission"); a shop with a real card is absent; page size above 100 or page above 1000 refused.

## F. Checkout snapshots (customer app or API)
- [ ] Order from a shop with NO assignment: `orders.commission_rate_card_version_id` = the default card's version, `commission_total` = 0.00, every line 0.00; `grand_total` identical to before this feature.
- [ ] Order from a shop on Standard v1 with a 2-addon line (200 + 30) x3: unit 20.00, line 60.00, total 60.00; delivery fee not in the commission.
- [ ] Reassign the shop to v2 and place a new order: the OLD order keeps v1 and its figures.
- [ ] A scheduled (future) change is NOT used by an order placed today; once its start time passes it is.
- [ ] A cancelled future change is never used.
- [ ] Online (Razorpay) checkout and cash-on-delivery both write the same snapshot.
- [ ] A GROCERY or PRODUCT cart order: commission columns NULL, an `order_seller_snapshot` row still written.
- [ ] POS, guest QR and counter-sale orders: all commission columns NULL and no `order_seller_snapshot` row.
- [ ] Seller facts on a customer order (`order_seller_snapshot`): `seller_gstin`, `seller_gst_regime`, `seller_address`, `seller_state` match the shop at order time; edit the shop's GSTIN afterwards: the old row does not change, and an UPDATE or DELETE on it fails.
- [ ] Platform facts: with a default active profile, `platform_seller_profile_id`, `platform_legal_name`, `platform_gstin` and `platform_address` on the snapshot row are filled; edit the profile afterwards: old orders keep the old text.
- [ ] With NO active default profile: the order still completes and the backend log shows the warning.

## G. Platform seller profiles API
- [ ] `GET /api/admin/platform-seller-profiles` lists profiles; `POST` the first one: it becomes the default automatically.
- [ ] Add a second profile (different GSTIN) not as default: default unchanged; `PUT` it with `defaultProfile: true`: the default moves and the old one is cleared.
- [ ] Deactivate or switch off the current default: refused (`DEFAULT_LOCKED`); duplicate code in another case: 409; bad GSTIN: refused.
- [ ] Audit log entries exist for create and update (and only for real changes).

## H. Admin web screens (browser; light AND dark; one narrow window about 360 px wide)
- [ ] Sidebar has "Commission"; `/admin/commission-cards` lists cards with version and updated time, the system card badged "System default"; empty state text when no cards.
- [ ] "New card": name + slab editor; first slab start is locked at 0; Save disabled until the preview is valid; a violation shows the backend text; kill the backend mid-edit: an error with Retry (not an endless skeleton).
- [ ] Preview table shows 99 / 230 / 305 / 500 with commission and "Restaurant keeps", and the GST/TDS note.
- [ ] Card detail: versions newest first with "Latest"; "New version" starts from the latest slabs; saving identical slabs shows the backend message; "Move shops on older versions to vN" shows only on versions above 1.
- [ ] Rename dialog; the system card shows no Rename or New version buttons.
- [ ] Bulk move dialog: lists affected shops, count, the 200 note when above 200, start choice; moving updates the shop tabs.
- [ ] Shop page, "Commission" tab: both channels show the card in force, the "since" time, the scheduled changes; never-assigned shop shows "Never assigned a card" and "No commission".
- [ ] "Change card": pick card, version, channels (both on by default), start. Review step shows old to new per channel with the worked table; for a shop with a change already scheduled it says the new one replaces it. "Confirm change" works; Back works.
- [ ] Choosing "No commission" for a never-assigned shop with a start inside 24 hours: the hint does NOT promise "can start now" and the backend message is shown on Confirm.
- [ ] Two browser tabs on one shop: change in tab A, then confirm in tab B: 409 message shown and the tab refreshes to the new state.
- [ ] Cancel a scheduled change needs a reason; the row disappears.
- [ ] "Shops on the default card": channel switch never shows the other channel's shops (check with a slow network throttle); paging works; an error shows Retry.
- [ ] Narrow window: slab rows stack, preview table scrolls inside its box, dialogs do not overflow sideways.
- [ ] Keyboard: Tab reaches both selects in the change dialog and a screen reader announces "Rate card" and "Version".
- [ ] Platform profiles screen: sidebar "Platform profiles" (/admin/platform-profiles). Empty state text shows while no profile exists; "Add profile" with an empty table makes it the default automatically; invalid GSTIN shows the backend message; editing the default shows both switches locked; a second profile "Default" switch moves the default; the Default and Inactive badges match; light and dark; narrow window.

## I. Close the phase
- [ ] **S** Everything above passes, or each failure is logged here with its fix.
- [ ] **S** Delete the Neon branch(es).
- [ ] **S** Run the five SQL files on PRODUCTION in order, immediately before the backend deploy (boot fails without them); then add the platform profile through the API.
- [ ] **S** Merge order: backend final PR first (prod auto-deploys; a ~30 s 502 is normal), then the web PR. Do NOT run `commission-rate-drop-DO-NOT-RUN-NOW.sql`.
- [ ] **S** After deploy, assign Standard v1 to the pilot shops on Eat Now (and Schedule) from the new Commission tab.
- [ ] **C** Update `schedule-implementation-order.md` (2b.13 done), the project focus note, and move the open items (GST basis H, restaurant legal name, GST state code, delivery state) to CA task 0.7.

## Known limits (not defects of this phase)
Concurrent renames are last-write-wins. A slab can charge more than the unit price (payout can go negative); the rule is undecided. `commission_notice_days` on service areas is no longer used. No tax amounts are stored (GST basis open question H).
