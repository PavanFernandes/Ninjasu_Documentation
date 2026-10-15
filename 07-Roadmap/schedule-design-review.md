---
id: ""
title: "Schedule — Phase 1 design review (devil's advocate)"
summary: "Per-proposal failure scenarios, mitigations and verdicts for the Schedule data model, grounded in backend main @ b428324. Settles D1-D4 and D6, corrects four assumptions in schedule-plan.md, and leaves one decision (audit scope) for the owner."
type: how-to
status: review-complete-awaiting-decision
apps: [backend, web, customer, rider]
module: "schedule"
anchors: []
verified_against: "backend main @ b428324; two read-only code investigations 2026-10-08"
updated: 2026-10-08
---

# Schedule — Phase 1 design review

Companion to [schedule-plan.md](schedule-plan.md). Verdict legend: `proceed`, `proceed with conditions`,
`stop` (needs the owner). Every claim about the code was found by searching the mechanism (table, query,
verb), not a guessed name. Where something is inference, it is marked *(inferred)*.

## Corrections this review forces into the plan

1. **Reserve capacity at payment confirm, not at checkout.** Online stock is taken at confirm (ADR-0018:
   abandoned payment sheets hold nothing). A checkout-time hold would live 15-30 minutes plus the hourly
   sweep, which is dangerous near cutoffs.
2. **A new order status `SCHEDULED`, released to `PLACED` at the cutoff.** A time filter on every read is the
   implicit-filter trap; a status transition is not. See P4.
3. **The audit log cannot take area actions as designed.** `audit_events.shop_id` is NOT NULL, the table has
   immutability triggers, and the audit plan already rules "never a sentinel shop UUID". See P7 (owner decision).
4. **Shop timezone is not a Schedule blocker.** The service area carries its own IANA timezone. Drop it from Phase 0.
5. **The ₹10 fee is not "one price calculator".** Delivery fee is `OrderAssembler.computeDeliveryFee` using a per-shop
   `DeliveryConfig`; a scheduled-fee branch is new logic there.

## P1 — `service_areas` + shop assignment (D6)

> **Proposal:** area row = center + radius, mode flags, ordering window, fee, paused flag; shops assigned by admin.
> **Failure scenarios:**
> - (a) Nullable semantics: `shops.service_area_id IS NULL` is read by some paths as "no area, legacy" and by others as "not served". The existing town has no area row, so a customer there would be told "not here yet".
> - (b) A boolean `paused_today` needs a reset job; if it fails to reset, tomorrow's lunch is silently closed.
> - (c) Two areas overlap (HSR and a neighbouring one): a customer or shop matches both.
> - (d) Mode flags both false = area that does nothing.
> **Mitigation:**
> - Absence of an area row means **legacy behaviour unchanged** (Eat Now by the shop's own radius). Area resolution is additive until Phase 4.
> - Explicit columns: `eat_now_enabled`, `schedule_enabled` with `CHECK (at least one true)`; `timezone` (IANA); `paused_on DATE` (paused iff `paused_on = today in area timezone`; nothing to reset).
> - Overlap: reject overlapping areas at save, or resolve to the nearest center deterministically.
> - Shop assignment is a plain UUID column on the shop, no FK (cross-domain rule), one area per shop in v1.
> - Name it `service_area` everywhere in code: "area" already means a seating area (`ShopTable.area`, `AuditAction` allowed key `area`).
> **Verdict:** `proceed with conditions` (above). **D6: assigned by admin**, confirmed.
>
> **D6 refinement (2026-10-14, devil's advocate):** v1 stays a single nullable column; no link table without a requirement. It is adaptable later only if these hold:
> - (e) **The order snapshots `service_area_id`.** Ops authorization, the board and refunds read the area from the order, never from the shop, so reassigning a shop mid-day orphans nothing, and a later many-areas change never touches live orders.
> - (f) **Admin-only write.** `service_area_id` is not on the shop-owner update DTO (SB-SEC-05, CORE-SEC-01): a restaurant owner could otherwise place their own shop into an area. Own admin-audience endpoint, audited.
> - (g) **One read point.** Every customer-facing "is this shop in the area" check goes through one SQL fragment (like `ItemChannelSql`) plus one eligibility function, with a guard test that fails when a new discovery query skips it. Moving to a link table later then edits that fragment, not every reader.
> - (h) **NULL means "in no area, legacy behaviour unchanged"** (Eat Now by the shop's own radius). Nothing is backfilled; existing shops stay NULL.
> - (i) **No `schedule_enabled` flag on the shop.** Scheduled availability is derived: assigned to an area (admin) AND has a `scheduled_menu_item` row for today (restaurant) AND area not paused. Two flags for the same fact would drift. The admin view shows "assigned, no list today".
> - (j) Distance from the area centre is computed at read for the admin warning, never stored. Customer matches only shops of the area their location resolves to; the overlap edge case (customer resolves to B, shop sits in A) is accepted.

## P2 — `service_area_members` + `/api/ops/**` (superseded by `platform_staff`, see admin-access-redesign.md)

> **Proposal:** (user, area, role AREA_MANAGER/AREA_OPS) with area derived server-side from the resource.
> **Failure scenarios:**
> - (a) Everything shop-side is keyed on shop: `PermissionService`, `user_shops`, `PermissionTemplates`, the audit recorder's membership check. Nothing resolves non-shop membership, so a copy-paste of shop checks lets an HSR manager act on another area.
> - (b) Route matchers use `hasRole("SHOP")`. Area staff have no shop membership, so they are locked out, or someone grants them SHOP and they gain shop-admin reach.
> - (c) Privilege escalation through a user-admin endpoint: ADMIN is DB-grant-only by design; an ops-role grant endpoint that passes roles through verbatim repeats the `createUserByAdmin` hole.
> - (d) The area id arrives in the URL and is trusted.
> **Mitigation:**
> - A parallel `AreaAccessService.requireAreaRole(areaId, user, minRole)`, modelled on `user_shops` (`(user_id, service_area_id)` unique). Two fixed roles as an enum on the member row; do not rebuild a configurable permission catalog.
> - Every ops handler loads the resource (order / slot day / batch), reads its area from that row, then authorizes. ADMIN bypass explicit and audited.
> - New role `OPS` (global, like RIDER) with its own `/api/ops/**` matcher: `hasAnyRole("ADMIN","OPS")`. The grant endpoint whitelists `OPS`; it can never write `ADMIN`. Do not reuse SHOP.
> - Every ops mutation needs `@AuditedEndpoint` or `@NotAudited(reason)`; the declaration test fails the build otherwise (it checks annotations only, so also test that the recorder is called).
> **Verdict:** `proceed with conditions`.

## P3 — slots, cutoffs, capacity, atomic reservation

> **Proposal:** slots with cutoff and capacity; reserve atomically; restaurant cutoff as prep lead time.
> **Failure scenarios:**
> - (a) Reservation at checkout holds capacity for abandoned payments (15-30 min + hourly sweep).
> - (b) Reservation at confirm lets a customer pay for a slot that filled meanwhile.
> - (c) Release called twice (cancel + orphan refund + stock-fail path) drives the counter negative; called zero times leaks capacity.
> - (d) Customer pays after the slot cutoff (sheet open for minutes).
> - (e) A counter saved, then an exception thrown inside `@Transactional`, rolls back the save (the PIN-lockout lesson).
> - (f) "Effective cutoff" computed in two places (customer app and backend) drifts.
> **Mitigation:**
> - **Soft check at checkout** (read remaining; reject if zero) **plus hard reservation at confirm** by one conditional UPDATE (`reserved < capacity`), next to `decrementStockAllOrCompensate`; if either capacity or stock fails the other is released and the order goes CANCELLED + REFUND_PENDING.
> - **A reservation row per order** (`schedule_reservations`, PK `order_id`, status RESERVED / RELEASED), so release is a CAS on that row and idempotent; one `release(orderId)` method is the only writer. Called from cancel, decline, orphan-refund, confirm-failure and ops-cancel.
> - Re-check the cutoff at confirm; past cutoff means refund.
> - Slot template (area, start `LocalTime`, lead/cutoff minutes, capacity) plus a **per-day row** created lazily (`INSERT ... ON CONFLICT DO NOTHING`) holding `reserved`, and the **cutoff and release instants persisted as epoch millis** computed once by one function, `min(slot cutoff, slot start - shop lead)`.
> - **Fix the refund gap:** `doConfirmPayment`'s stock-failure branch sets REFUND_PENDING with no immediate attempt, so the customer waits for the hourly sweep. This path will now be hit more; schedule the refund attempt after commit there.
> **Verdict:** `proceed with conditions`.
>
> **P3a — restaurant cutoff as optional lead minutes (D4, devil's advocate 2026-10-14)**
> - **Rule:** `effective cutoff = min(slot cutoff, slot start - shop lead)`; a NULL lead drops the second term. `shops.schedule_lead_minutes INT NULL`, `CHECK (schedule_lead_minutes BETWEEN 0 AND 240)`. NULL means "no restaurant-specific cutoff", never 0 and never a default 60.
> - **Failure (a): the cutoff differs per slot.** Lead 90 closes the restaurant for 12:30 at 11:00 but leaves 1:30 open until 12:00, so a restaurant is not simply open or closed. Mitigation: the customer picks the slot first; the restaurant list is evaluated against that slot and greyed with its computed clock time. Phase 4 must not show one per-restaurant "closed" badge.
> - **Failure (b): a lead shorter than the area's slot cutoff does nothing.** The setting looks saved but has no effect. Mitigation: the shop UI shows the computed clock time per slot, so the owner sees the real result.
> - **Failure (c): a mid-day edit.** Lowering the lead reopens slots; raising it closes them, including as a self-service "close me for today". Mitigation: the change applies to new orders only (cutoff and release instants are persisted at reservation, P3); accepted as a feature.
> - **Single source of truth:** one function computes the effective cutoff, used by the customer read, checkout, payment confirm and the release job (check #3).
> - **Verdict:** `proceed`, optional as decided. Ask the first restaurants the clock-time question before Phase 4 UI wording; the column is cheap to change until then.

## P4 — `orders` fulfilment + the live-order read audit

> **Proposal:** `fulfilment_type` + slot on orders; make sure scheduled orders never appear as live.
> **Failure scenarios (all from the read audit):**
> - Shop board `findForShopBoard` ACTIVE list shows a paid scheduled order as live. `SHOP_BOARD_ACTIVE_STATUSES` is *derived* (all statuses minus terminal minus ghost), so a new enum value is included silently.
> - The shop alarm fires at payment time: `OrderPlacedEvent` is published in `doConfirmPayment` (`PaymentServiceImpl:319`), the listener reads only the event, and its body hardcodes " · COD".
> - `getActiveOrder` returns one row (newest placed): a scheduled order becomes "the active order" or shadows a real one.
> - `updateOrderStatus` has no time gate: staff can accept a future order early. `assignDelivery` has no order-status gate.
> - Customer cancel before release pushes "Order cancelled" to a shop that never saw the order.
> - A `release_at` timestamp filter would need to be remembered by every future reader (check #8).
> **Mitigation:**
> - Status **`SCHEDULED`** = paid, not yet released. A **release job** (new scheduler; only `@EnableScheduling` exists) does a CAS `SCHEDULED -> PLACED` when `release_at <= now`, then publishes `OrderPlacedEvent`. It must be idempotent and catch up after a restart (`status=SCHEDULED AND release_at <= now`, partial index).
> - At confirm, scheduled orders go to `SCHEDULED` and **publish nothing**.
> - **An exhaustive classification test** over `OrderStatus.values()`: every status is exactly one of live / ghost / scheduled / terminal, so a future status can never be auto-included. Exclude `SCHEDULED` explicitly from the board's ACTIVE set and from `getActiveOrder`.
> - Customer: scheduled orders appear in history, and in a separate "upcoming" read, not in `getActiveOrder`.
> - `validateSellerStatusTransition` already returns false by default, so staff cannot advance a `SCHEDULED` order. Add `SCHEDULED` to the customer-cancellable set with the cutoff rule (D2); suppress the shop push for it. Reject `assignDelivery` for `SCHEDULED` orders.
> - Keep `orderType=DELIVERY` for scheduled orders (delivery orders never appear on the KDS feed, which reads DINE_IN/TAKEAWAY only). Do not model scheduled as TAKEAWAY.
> - Delete or fix the dead `findActiveByShopId` (it lacks the ghost exclusion and would leak if revived). Fix the hardcoded " · COD" push text.
> - `fulfilment_type` NOT NULL with `@ColumnDefault('EAT_NOW')`; slot and release columns nullable with documented meaning (NULL = not scheduled).
> **Verdict:** `proceed with conditions`. Already safe: rider READY broadcast, rider accept, net-sales/food-cost, reconciliation job, refund sweep.

## P5 — scheduled stock (and D3)

> **Proposal:** scheduled stock per item per day; extend or separate from the stock ledger?
> **Failure scenarios:**
> - The ledger has exactly one open row per item, no slot/date/channel dimension; `atomicDecrement` is keyed `item_id AND is_open`. Extending it entangles the 03:00 IST reset (reseeds from `items.stock_qty`) with morning-entered scheduled quantities.
> - The ledger's credit path is keyed by `placedOn` in IST, so it already has two latent leaks *(inferred, not run)*: an order placed 00:00-03:00 IST decrements the still-open previous-day row but credits `today`; a ONE_TIME batch cancelled on a later day credits nothing. The javadoc's partial unique index (one open row per item) is not in code.
> - Dine-in/POS and scheduled sell the same item from one kitchen against two counters.
> **Mitigation:**
> - **Separate table**, never touching `item_stock_ledger`: `scheduled_menu_item (shop_id, service_date, item_id, planned_qty NOT NULL > 0, reserved_qty)`, own conditional UPDATE, keyed on the **service date**, not `placedOn`. Do not reuse `creditStock`.
> - **This table is also D3's answer:** a row for today means the item is offered on Schedule; no row means it is not. Availability is explicit, never derived. Add a "same as yesterday" action.
> - `planned_qty` is the kitchen's allocation **for Schedule only**; state that in the shop UI so dine-in is not assumed to share it.
> - Release goes through the same idempotent `release(orderId)` as P3, iterating the order's line snapshot.
> - Log the two ledger leaks as a separate follow-up; they predate Schedule.
> **Verdict:** `proceed with conditions`. **D3: short daily lunch list**, via this table.

## P6 — batches, handover timestamps, drop points

> **Proposal:** `batches` + `batch_orders` + handover times + `drop_points`.
> **Failure scenarios:**
> - Handover and delivered times stored as mutable columns get overwritten on correction; the pilot's whole purpose (measuring lateness) is lost.
> - An order sits in two batches, or a soft "removed_at" column makes every reader remember a filter (check #8).
> - Batch status stored and also derivable from member deliveries: two sources of truth.
> - Drop point membership stored on the order goes stale when a drop point is edited; overlapping drop points group an order twice.
> **Mitigation:**
> - Timestamps as **append-only `batch_events`** (type, shop, at, actor), the KOT append-not-mutable pattern. Never update a past event.
> - `batch_orders.order_id` UNIQUE; moving an order deletes the row and inserts a new one, with the move recorded as an event.
> - No stored batch status: derive progress from the member `deliveries` plus events. Add a nullable `batch_id` (plain UUID) on `deliveries`; assignment reuses the existing manual-assign path.
> - Drop points: derive an order's drop point at read time (nearest center within radius); store only when the customer picks one (Phase 8). Snapshot the drop point name into the batch event.
> - Check before Phase 6 that a prepaid delivery snapshots `codAmount = 0`, so the rider app's cash step can be skipped *(not yet verified)*.
> **Verdict:** `proceed with conditions`.

## P7 — audit log scope — **stop, owner decision**

> **Proposal:** put area actions in the audit log by generalising `shop_id` to a scope type + id.
> **Facts:** `audit_events.shop_id` is NOT NULL, all four indexes lead with it, rows are immutable (UPDATE blocked by trigger, so old rows cannot be backfilled), the recorder is `@Transactional(MANDATORY)` and authorizes only shop members or global ADMIN (an area manager would get `ForbiddenException`), the cursor is signed per shop, reads are `/api/shops/{shopId}/audit-events` for SHOP/ADMIN roles, and `AuditSchemaGuard` checks only that the table exists, not its columns. `audit-log-plan.md` already ruled: shop-scoped only; platform actions get a separate table, never a sentinel UUID.
> **Failure scenarios:** generalising touches the entity, recorder, repository queries, cursor, indexes, controller, security matchers and a hand-run migration on a table with triggers; a missed manual SQL run fails on the first insert in production. A dual-scope event ("manager moved order X to slot Y": shop + area) has no model in one row.
> **Options:**
> - **A (recommended): a separate `platform_audit_events` table**, own hand-run SQL, own small recorder, area-scoped, with an optional `shop_id` for filtering. Zero change to the hardened shop audit. Ops actions that also matter to a shop are not mirrored into the shop's Activity page in v1.
> - B: generalise `audit_events` (scope type + id). One table and one UI, but the largest change to the most security-sensitive code, and it reverses the existing ADR.
> **Verdict:** `stop — ask the user`. Whichever is chosen needs a short ADR superseding the audit plan's scope line.

## P8 — prepaid-only enforcement

> **Proposal:** scheduled orders are prepaid; reservations tied to the Razorpay two-phase flow.
> **Failure scenarios:**
> - COD `POST /api/orders` is unconditional (not gated by anything) and `PlaceOrderRequest` carries only cart type and address. A scheduled order placed through it is unpaid and unreserved.
> - The online flag defaults off, so scheduled orders are impossible until it is on, and the flag is not exposed to clients (the app cannot know whether to offer Schedule).
> - Scheduled-order availability and cart validation read the live stock resolver, so a Schedule menu item looks sold out or available wrongly.
> - Checkout carries the slot; if it lived on the cart it would go stale.
> **Mitigation:**
> - `placeOrder` rejects any scheduled request explicitly. The slot travels in the **checkout request**, not the cart.
> - Expose a Schedule-available signal from the area-config read (it already must report modes and slots).
> - Menu and cart reads become mode-aware for Schedule areas: availability comes from `scheduled_menu_item`. Budget this in Phase 2 and Phase 4; it is a real cost, not a detail.
> - Keep scheduled orders on the DELIVERY sales channel for tax (ECO treatment); do not add a channel.
> **Verdict:** `proceed with conditions`. Blocked on Phase 0: online payment must be live and re-reviewed.

## Review 2 (2026-10-14): tomorrow-ready dates, admin-set config, commission, separate menu, prep ticket

Grounded in backend main @ 7434fd8. Mechanism searches: `computeDeliveryFee`, `commission`, `SettlementMode`, `RouteSplitSettlement`.

## P9 — `service_date` on every Schedule record (tomorrow-ready)

> **Proposal:** every Schedule row carries `service_date` (area timezone); `advance_days` 0 now, CHECK 0..1; window stored as day offset + time.
> **Failure scenarios:**
> - (a) "Today" computed in several places (customer read, reservation, job, prep list) with different clocks or zones; the first midnight-near order lands on the wrong date.
> - (b) The tomorrow path ships disabled and untested, so turning it on exposes bugs in cutoffs, release job, stock and refunds at once.
> - (c) Slot day rows are created lazily; an admin edit of the slot template mid-morning changes cutoff/capacity for untouched slots but not for slots that already have orders: the same setting copied across rows drifts.
> - (d) A `SCHEDULED` order now lives up to ~24 h; existing sweeps (orphan refund, reconciliation) were only checked against same-day lifetimes.
> **Mitigation:**
> - One function `ServiceDateResolver.today(area, instant)` and `isOrderable(area, serviceDate, instant)`; no other code computes a date.
> - Build and test the tomorrow path from the first slice (`advance_days=1` in tests), even though the setting ships at 0.
> - Day rows snapshot cutoff/capacity when created. Edit rules: capacity may not drop below `reserved`; a slot-day that has reservations keeps its cutoff; template edits apply to day rows created afterwards. State this in the admin UI.
> - Re-verify the refund sweep and reconciliation job against a 24 h `SCHEDULED` lifetime.
> **Verdict:** `proceed with conditions`.

## P10 — admin-set window, slots, `advance_days`

> **Proposal:** the platform admin sets window, slots (time, cutoff, capacity) and `advance_days` per area on the Service areas page.
> **Failure scenarios:** window opens after the first cutoff; cutoff after the slot start; overlapping or duplicate slots; capacity 0; validation duplicated in the form and the API so they drift.
> **Mitigation:** slots are rows (`service_area_slot`), not an array column. One server-side validator (`window.opens < first cutoff < slot start`, cutoff and capacity bounds, unique start per area); the form only mirrors messages. Every save writes `platform_audit_events`.
> **Verdict:** `proceed with conditions`.

## P11 — configurable fee and commission, snapshotted on the order — **stop, owner decision**

> **Facts:** there is no commission anywhere in the schema. `SettlementMode` is `SINGLE_MERCHANT | ROUTE_SPLIT`, and `RouteSplitSettlement` says platform commission is "a later param — shop gets 100%". The delivery fee today is per-shop `DeliveryConfig` (base + per-km + free-above) in `OrderAssembler.computeDeliveryFee`.
> **Failure scenarios:**
> - (a) A commission % snapshotted on the order has no consumer: no settlement path deducts it, so Ninjasu would show a number it never collects.
> - (b) Unknown money flow: with `SINGLE_MERCHANT` Ninjasu holds the money and no restaurant payout exists; with `ROUTE_SPLIT` only linked-account shops get paid, and a platform share must be added to the Route transfer.
> - (c) Basis undefined: commission on item subtotal, or on food + tax, after discounts, excluding the delivery fee? Refunds and declines after capture change it.
> - (d) Two fee sources: the scheduled flat fee in the area vs the shop's `DeliveryConfig` (including free-delivery-above) disagree.
> - (e) NULL meaning: no commission on legacy Eat Now orders is "not configured", not "0%".
> - (f) Razorpay keeps ~2.36% on every refund, so a free cancel loses money unless commission is computed on delivered orders only.
> **Mitigation (after the owner decides the money flow):**
> - One `FeeResolver` / `CommissionResolver`: order fulfilment SCHEDULED reads the area's scheduled values and ignores shop `DeliveryConfig` (free-delivery-above does not apply unless configured); legacy and Eat Now orders keep today's path.
> - Store the rate on the order at placement (`commission_rate` NULL = legacy, not computed); compute the amount at settlement from delivered net lines, never at placement.
> - Area default per mode now, a nullable per-shop override later, both behind the one resolver.
> **Verdict (updated 2026-10-14):** `proceed with conditions` after the owner decided D10: manual payout, commission on delivered/completed orders only, base = item subtotal after restaurant-funded discounts. Build an append-only commission ledger (accrual at DELIVERED/COMPLETED, reversal entries for later refunds) and a settlement statement; the GST invoice is deferred. Open: who holds COD cash.

## P12 — separate curated Schedule menu (D3) details

> **Failure scenarios:** a dish is deactivated or deleted in the main menu while listed for the day, and readers still offer it (implicit filter every reader must remember); the Schedule price is assumed equal to the menu price; the lunch list differs per date and is re-typed daily.
> **Mitigation:** one availability resolver: item active AND row for `service_date` AND `planned_qty > reserved_qty` AND shop assigned AND area not paused. `schedule_price` NULL = menu price (restaurants may later set a lunch price; the order line already snapshots price). "Same as yesterday" copies the previous service date.
> **Verdict:** `proceed with conditions`.

## P13 — prep batch ticket (D9)

> **Proposal:** one ticket per shop per slot per service date; one accept, one ready, one handover; customer orders stay the unit of payment, refund, tax and delivery.
> **Failure scenarios:**
> - (a) The release job publishes `OrderPlacedEvent` per order: a 14-order slot rings the shop alarm 14 times.
> - (b) Ticket status stored and orders' status stored: two sources of truth; a partial decline leaves them disagreeing.
> - (c) Lines change after the restaurant saw the ticket (restaurant decline, ops cancel).
> **Mitigation:**
> - Release publishes one `ScheduleTicketReleased` event; per-order alarm and push are suppressed for SCHEDULED orders; the board shows the ticket as one card with its orders collapsed.
> - Ticket status is derived from member orders; "accept ticket" fans out to the existing order-transition validator in one transaction, and a per-line "can't make" uses the existing decline path.
> - The first fired version is an immutable record; later changes append an amendment (the KOT append-not-mutable pattern).
> **Verdict:** `proceed with conditions`.

## Review 3 (2026-10-15): order groups, editable stock and cutoffs, locked rates, live counts

Scope: decisions in schedule-plan.md §3.4–3.6 made after review 2. Code facts: `orders.razorpay_order_id` is UNIQUE (`Order.java:153`), so a payment maps to exactly one order today.

## P14 — order groups (one payment, one order per restaurant)

> **Failure scenarios:**
> - (a) Two payment pipelines: Eat Now confirms per order, Schedule per group. Webhook, verify, reconciliation and refund retry each get a second branch; a fix applied to one is forgotten in the other (business logic in two places).
> - (b) Over-refund: a restaurant decline and an ops cancel on two orders of one group refund concurrently; the sum exceeds the captured amount, or the delivery fee is refunded twice.
> - (c) Group-level money (delivery fee, its GST, rounding) lives on the group; a per-order settlement export or report misses it.
> - (d) Customer notifications fire per order: a two-restaurant group gets two "being prepared" pushes.
> - (e) Group code collision on generation.
> **Mitigation:**
> - One shared payment core (signature check, payment-status CAS, Razorpay calls, refund call) used by both the order path and the group path; a test matrix runs webhook-first, verify-first, duplicate and failure cases on both.
> - Refunds are rows (`order_id`, amount, reason, status) written under a lock on the group row; the insert checks `sum(refunds) + amount <= captured`; the delivery fee is refunded only by the "last order in the group cancelled" rule, once.
> - The export has a group section (delivery fee, rounding) attributed to Ninjasu, never to a restaurant.
> - Customer notifications are emitted per group (one push naming all parts); restaurant events stay per order/ticket.
> - Group code: random 4 characters, unique `(service_area_id, service_date, group_code)`, retry on conflict.
> **Verdict:** `proceed with conditions`. This is the largest change since review 2; it touches the payment code that still needs its adversarial re-review, so do both together (Phase 0.2 + 2b).

## P15 — editable stock and order-until (Zepto-style), locked order cutoff

> **Failure scenarios:**
> - (a) Restaurant lowers stock while a payment confirms: the reservation succeeds against stale stock.
> - (b) A split-price edit between cart and checkout silently changes what the customer pays.
> - (c) Restaurant edits are shop actions, but the plan routes admin changes to `platform_audit_events`; a restaurant's edits could end up unaudited or in the wrong table.
> - (d) Reopening a dish after the bulk ticket was released creates orders that arrive after batching.
> **Mitigation:**
> - Stock edits and reservations both use conditional UPDATEs on the same row (`reserved_qty <= stock_qty` holds at all times).
> - Checkout re-prices from the server and returns a "price changed" response the app must confirm; the order snapshots what was confirmed.
> - Audit rule: restaurant actions (stock, order-until, split price, ticket accept/ready) → shop `audit_events`; admin/ops/area actions → `platform_audit_events`.
> - Late orders join the ticket as additions and appear in the problem queue as "unbatched"; the slot last call bounds how late.
> **Verdict:** `proceed with conditions`.

## P16 — live counts for restaurants by polling

> **Failure scenario:** every open restaurant dashboard polls the counters every few seconds; each poll queries Postgres, keeping Neon awake all day and adding load (Neon realtime constraint: polling must not reach Postgres).
> **Mitigation:** an in-process cache of per-shop/per-slot counts (single EC2 instance), updated on reservation/void and refreshed at most every 30 s; the poll endpoint reads only the cache; poll interval ≥ 30 s and only while the page is visible.
> **Verdict:** `proceed with conditions`.

## P17 — locked commission rate and derived menu price

> **Failure scenario:** the menu shows a price from the current rate, but the PENDING_PAYMENT order snapshots at checkout and confirm happens after a rate change at midnight: the customer pays the old price (fine) but a retry of checkout would show a new price.
> **Mitigation:** snapshot at checkout creation (the price shown in the payment sheet); a new checkout re-prices. Document as intended.
> **Verdict:** `proceed`.

## Open decisions: recommendations

| # | Decision | Recommendation |
|---|---|---|
| D1 | One restaurant per order or several | **One per order**; the manager combines at batch level. Verify the cart already enforces a single shop *(not checked)* |
| D2 | Cancellation | **Free before release** (cutoff), refund + capacity release. After release: no customer refund; a **restaurant decline after release always refunds** (existing decline path) |
| D3 | Menu | **Short daily list** = `scheduled_menu_item` (P5) |
| D4 | Restaurant cutoff | **Decided 2026-10-14: optional lead minutes** (`schedule_lead_minutes` INT NULL, CHECK 0..240, on the shop; no `schedule_enabled` flag, see P1 (i)); NULL = slot cutoff only; the customer sees a computed clock time per slot (P3a) |
| D6 | Shop to area | **Decided 2026-10-14: assigned by admin**, `service_area_id` UUID NULL on the shop, no FK, one area per shop, conditions P1 (e)-(j) |
| D8 | Audit approach | **Decided 2026-10-08: separate `platform_audit_events`** (admin + area ops; see [admin-access-redesign.md](admin-access-redesign.md)) |

## Findings outside Schedule (log, don't fold in)

- Item stock ledger credit-path leaks and the missing partial unique index (P5).
- `findActiveByShopId` dead code that omits the ghost exclusion.
- Shop push body says "COD" for every delivery order, including prepaid.
- `doConfirmPayment` stock-failure refund waits for the hourly sweep.
- `AuditSchemaGuard` checks only table existence; a column added by manual SQL is not detected.
- Delivery orders ignore shop opening hours entirely (only guest QR ordering checks them).
