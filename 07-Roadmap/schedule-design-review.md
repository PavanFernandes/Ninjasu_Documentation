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
updated: 2026-10-18
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
> **P3a — restaurant cutoff as optional lead minutes (D4, devil's advocate 2026-10-14)** — *superseded 2026-10-15 by per-dish order-until (plan #15/#16); no `schedule_lead_minutes` column.*
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
> - Store the rate on the order at placement (`commission_rate` NULL = legacy, not computed); compute the amount at settlement from delivered net lines, never at placement. *Superseded 2026-10-18 by P20/P21: each order line snapshots its slab commission at order time; no stored rate, no settlement-time computation.*
> - Area default per mode now, a nullable per-shop override later, both behind the one resolver.
> **Verdict (updated 2026-10-14):** `proceed with conditions` after the owner decided D10: manual payout, commission on delivered/completed orders only, base = item subtotal after restaurant-funded discounts. Build an append-only commission ledger (accrual at DELIVERED/COMPLETED, reversal entries for later refunds) and a settlement statement; the GST invoice is deferred. Open: who holds COD cash.
> **Superseded 2026-10-18 by P20/P21:** commission is a flat-rupee slab per unit, snapshotted per order line at order time from the restaurant's named plan (plan §3.4); no rate, no settlement-time computation, no commission ledger. The discount basis ("after restaurant-funded discounts") is reopened (see Open, review 4).

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
> **Superseded 2026-10-18 by review 4 (P19-P21):** the menu price is no longer derived from a rate; commission is computed on the order from a named slab plan.

## Open decisions: recommendations

| # | Decision | Recommendation |
|---|---|---|
| D1 | One restaurant per order or several | **One per order**; the manager combines at batch level. Verify the cart already enforces a single shop *(not checked)* |
| D2 | Cancellation | **Free before release** (cutoff), refund + capacity release. After release: no customer refund; a **restaurant decline after release always refunds** (existing decline path) |
| D3 | Menu | **Short daily list** = `scheduled_menu_item` (P5) |
| D4 | Restaurant cutoff | **Decided 2026-10-14: optional lead minutes** (`schedule_lead_minutes` INT NULL, CHECK 0..240, on the shop; no `schedule_enabled` flag, see P1 (i)); NULL = slot cutoff only; the customer sees a computed clock time per slot (P3a). *Superseded 2026-10-15 by per-dish order-until (plan #15/#16).* |
| D6 | Shop to area | **Decided 2026-10-14: assigned by admin**, `service_area_id` UUID NULL on the shop, no FK, one area per shop, conditions P1 (e)-(j) |
| D8 | Audit approach | **Decided 2026-10-08: separate `platform_audit_events`** (admin + area ops; see [admin-access-redesign.md](admin-access-redesign.md)) |

## Findings outside Schedule (log, don't fold in)

- Item stock ledger credit-path leaks and the missing partial unique index (P5).
- `findActiveByShopId` dead code that omits the ghost exclusion.
- Shop push body says "COD" for every delivery order, including prepaid.
- `doConfirmPayment` stock-failure refund waits for the hourly sweep.
- `AuditSchemaGuard` checks only table existence; a column added by manual SQL is not detected.
- Delivery orders ignore shop opening hours entirely (only guest QR ordering checks them).

## Review 4 (2026-10-18): pricing and commission model

Scope: owner decisions of 2026-10-17/18 on how a Schedule dish is priced and how Ninjasu earns on it. Code fact
behind the change: an item has no price of its own; the price is the sum of the selected add-on options, and one
required ITEM group gives the base price ([02-Domain/menu.md](../02-Domain/menu.md)). Today the customer app and
POS both read the same `Addon.price`, so the app shows the dine-in price with no commission.

**Status of earlier items (2026-10-17).** P4 is built as 2b.1 (backend PR #53, merge `b1a9080`): `OrderStatus` is
classified LIVE / SCHEDULED_ONLY / GHOST / TERMINAL (SERVED and COLLECTED are TERMINAL); shop board, shop detail,
customer active order and KDS exclude SCHEDULED; customer history keeps it. `findActiveByShopId` did not exist, so
staff `assignDelivery` needed a new guard to refuse SCHEDULED. The new-order push says COD only for cash on delivery
(closes the "COD" finding above).

## P18 — one split price per dish cannot express sizes or paid add-ons (problem found)

> **Proposal (decision 21, P12):** a per-day `scheduled_menu_item.split_price` per dish; menu price = split + commission.
> **Failure scenarios:**
> - (a) A thali in Regular and Large, plus egg / kebab / papad, plus a choice of dal or sambar: one number per dish cannot price any of it. The price is built from options, not stored on the item.
> - (b) Adding a split price per option per day re-types the whole option price list daily, and drifts from the live menu.
> - (c) Forbidding paid add-ons on Schedule dishes (the earlier "v1: no paid add-ons, pending Samivan's OK") removes the dishes restaurants actually sell at lunch.
> **Mitigation (decided 2026-10-18):**
> - Paid add-ons ARE allowed on Schedule dishes; the "no paid add-ons" proposal is rejected.
> - `scheduled_menu_item` keeps only stock and availability (`stock_qty`, `reserved_qty`, `order_until`, `active`, plus `copied_from_id` etc.) and has **no `split_price`**. Prices come from the add-on options (P19).
> - The price-preview endpoint built on split price is dropped.
> **Verdict:** `proceed`. P12's `schedule_price` and P15 (b)'s "split-price edit" now read as "online-price edit".

## P19 — two prices per option; commission on the order, never in the menu

> **Proposal:** each add-on option carries a **dine-in price** and an **online price**. Ninjasu POS, counter sale and the guest QR menu show dine-in; the customer app (Eat Now and Schedule) shows app. The restaurant sets the online price. Commission is computed on the order.
> **Failure scenarios:**
> - (a) A commission built into each option ("restaurant price + %") rounds per option and compounds across add-ons; the customer sees a derived number nobody chose.
> - (b) A rate change recomputes every online price at once: thousands of menu prices move overnight without the restaurant touching them (P17's midnight case).
> - (c) The restaurant cannot see in the app the price it set, so price complaints have no owner.
> **Mitigation (decided 2026-10-18):**
> - Commission is computed on the order, never shown in or built into a menu item. The app never displays "restaurant price + 10%".
> - If Ninjasu changes its commission, online prices are updated by hand; nothing is recomputed automatically.
> - The restaurant menu editor shows a read-only line next to each online price: "Ninjasu keeps RsX, you get RsY", computed from the restaurant's plan (P21).
> **Verdict:** `proceed`.

## P20 — commission is a flat-rupee slab per item unit

> **Proposal:** commission per unit from a slab on the unit's online price including the add-ons chosen for that unit; × quantity; order commission = sum of lines; restaurant payout = item total at online prices − commission. Delivery and packaging fees excluded; GST on commission charged extra.
> **Standard slab:**
>
> | Unit online price | Commission per unit |
> |---|---|
> | Rs0-99 | Rs5 |
> | Rs100-149 | Rs10 |
> | Rs150-199 | Rs15 |
> | Rs200-249 | Rs20 |
> | Rs250-299 | Rs25 |
> | Rs300 and above | Rs25 + 10% of the amount above Rs300 (Rs400 → Rs35, Rs500 → Rs45) |
>
> Example: thali Large 200 + Egg 20 + Papad 10 = Rs230 → Rs20 per thali.
> **Why a slab and not a percentage:** a rupee amount a restaurant owner can read off a table and check on a statement; whole rupees below Rs300; the 10% tail above Rs300 is not a whole rupee in general (Rs333 → Rs28.30), so it is rounded per unit by the shared #27 rounding function before multiplying by quantity (test a tail case such as Rs333); the 10% tail above Rs300 starts at Rs25, so there is no jump at the top band.
> **Failure scenarios:**
> - (a) Basis per line instead of per unit: two thalis at Rs230 fall in the Rs400+ band (Rs41) instead of 2 × Rs20. The slab must be applied to one unit, then multiplied.
> - (b) Low-priced items: Rs5 on a Rs30 snack is about 17%. A bakery or snack shop on Standard pays a high effective rate.
> - (c) Band edges: a restaurant prices at Rs149 instead of Rs150 to pay Rs10 instead of Rs15. Accepted: the step is Rs5 and the customer's price falls too.
> - (d) A partial refund or a declined line recomputes commission from today's plan and returns a different amount.
> **Mitigation:** one commission function, unit-based, used by checkout and the menu-editor preview line; settlement and refunds read the snapshotted per-line commission and never call the function. Each order line snapshots its commission so a partial refund returns exactly that line's commission (P21). Case (b) is what a named low-price plan is for (P21). Effective revenue is about 5-10% of item value; check it against rider cost per order with pilot numbers (open).
> **Verdict:** `proceed with conditions`.

## P21 — named, versioned commission plans created by admin

> **Proposal:** Ninjasu platform admin creates and names slab plans (Standard; a low-price plan for snacks/bakeries or a partner/launch plan only when needed; a custom plan for one restaurant is allowed and is still a recorded named plan). Each restaurant is assigned one plan.
> **Why named plans and not one slab per restaurant:** a bespoke slab per restaurant means as many rule sets as restaurants to explain, audit, attach to agreements and change with notice; nobody can say which restaurants are on which terms. Named plans keep the set small and comparable; the one-off case is still possible, but as a named plan.
> **Failure scenarios:**
> - (a) A plan edited in place changes the meaning of past orders and statements.
> - (b) A plan change applied without notice breaks the agreement.
> - (c) A restaurant with no assignment: a silent fallback to 0 or to Standard hides a missing setup (P11 (e): missing means "not configured", never 0).
> **Mitigation (decided 2026-10-18):**
> - Plans are versioned and append-only. A change is a new version and needs the existing notice period.
> - Each order snapshots the plan id + version and the per-line commission; later plan changes never alter past orders.
> - The assignment keeps the existing ideas from decision 22 / 2a.4: scope, `effective_from`, notice check, `consent_ref` (the signed agreement's reference).
> - This supersedes the 2a.4 percentage model (`commission_rate.rate_percent` per shop/area, `CommissionRateResolver`, `rateAt`), which has no production caller yet.
> - Onboarding agreement (handled outside the code): plan name + version with the slab table attached, notice period, online-price cap, refund handling, payout schedule, GST on commission. Legal/CA review of the text is needed.
> **Verdict:** `proceed with conditions`. Case (c) still needs an explicit rule.

## P22 — one global online-price cap, outside the commission math

> **Proposal:** one platform setting "max online price over dine-in price" (%). A save that puts an online price above dine-in + cap% is refused with a clear message.
> **Why global:** the cap is a customer promise ("the app is never much dearer than the restaurant"); a per-restaurant setting becomes a negotiation and the promise stops being one rule.
> **Why outside the commission:** parity is NOT part of the commission math. Commission depends on the online price only; the cap is a validation on save. Mixing them (lower commission for parity) makes commission depend on two prices and rewards moving the dine-in price (P23).
> **Failure scenarios:**
> - (a) Ninjasu tightens the cap later: items already above it stay on sale at the old premium.
> - (b) The cap is checked only in the form and not on the API.
> **Mitigation:** the check lives in the server-side save path. When the setting is tightened, items already above it are flagged and hidden from Schedule until fixed.
> **Verdict:** `proceed`. The percentage itself is open.

## P23 — gaming risk for restaurants not on Ninjasu POS: dine-in edit gating

> **Failure scenarios:**
> - (a) The cap is relative to the dine-in price. A restaurant that does not bill dine-in on Ninjasu POS can raise its dine-in price in Ninjasu at no cost (no walk-in customer is ever billed at it), which raises the cap headroom, then raise its online price. The cap would hold only on paper.
> - (b) (added 2026-10-18) `posEnabled` is an owner toggle (`Shop.java:101`; owner-only PATCH `/api/shops/{id}/pos-settings`, `ShopTableServiceImpl.setPosEnabled`). A restaurant can turn POS on, raise the dine-in price and turn POS off again, so a gate that reads the toggle alone holds only on paper.
> **Mitigation (decided 2026-10-18):**
> - **POS not enabled:** the restaurant CANNOT edit the dine-in price. Only Ninjasu admin can, set at onboarding from the printed menu.
> - **POS enabled (withdrawn the same day, see Revised below):** the restaurant's owner/admin can change the dine-in price. It is the price walk-in customers are billed, so raising it also raises real dine-in prices; the cost keeps it honest.
> - Every price change (dine-in and app) is audited.
> - Side benefit: a reason for restaurants to adopt Ninjasu POS.
> **Residual risk (not closed):** a POS-enabled restaurant could raise the POS price and bill walk-ins outside Ninjasu; the audit trail makes the change visible, nothing more. A non-POS restaurant whose printed menu changes must ask Ninjasu to update the dine-in price.
> **Revised 2026-10-18 (Samivan; closes (b) and D23):** the POS gate is withdrawn. Only the Ninjasu admin edits the dine-in price, for every shop, POS or not; the restaurant edits only the online price. This closes (a) and (b) without needing any POS signal. Cost: POS restaurants ask Ninjasu for dine-in price changes, and the existing restaurant menu editor must write the online price, not the dine-in price.
> **Verdict:** `proceed` (updated 2026-10-18).

## P24 — Schedule-menu permissions

> **Proposal (decided 2026-10-18):** `schedule_menu.view`, `schedule_menu.manage` (dishes, order-until, copy day), `schedule_menu.stock` (restock, mark sold out, move order-until only). Owner/admin all; Manager all; Chef view + stock.
> **Failure scenario:** adding the new keys to the LEGACY permission sets breaks `legacyMyRole`, which matches a role by `containsAll` on LEGACY: existing members stop resolving to their legacy role.
> **Mitigation:** add the keys to DEFAULT templates only, never to LEGACY.
> **Verdict:** `proceed`. Delivered in 2b.2 (b) with the shop-side API under `/api/shops/{shopId}/schedule-menu`.

## Alternatives rejected (review 4)

- **Per-option markup, "restaurant price + %":** derived prices per option, rounding compounds across add-ons, every rate change rewrites the menu (P19).
- **Parity tiers inside the commission** (lower commission when online price equals dine-in): couples two concerns and rewards inflating the dine-in price; the global cap (P22) and edit gating (P23) handle parity instead.
- **Bespoke per-restaurant slabs:** unmanageable rule sets and agreements (P21); a one-off is a named plan.
- **One split price per dish per day:** cannot express sizes or paid add-ons (P18).

## Open (review 4)

Suggestions in brackets are suggestions, not decisions.

- The cap percentage [10%, roughly the median premium restaurants add on Swiggy/Zomato today].
- Empty online price: fall back to the dine-in price [suggested, so Eat Now looks unchanged until a restaurant sets online prices], or require an online price before a dish is sold online.
- Whether item/add-on discount percentages apply to both prices [suggested yes], and whether the slab uses the price after a restaurant-funded discount [suggested yes; a Ninjasu-funded coupon never changes commission].
- Same commission plan for Schedule and Eat Now, or separate plans per fulfilment type.
- Whether Eat Now orders also record commission and payout snapshots at order time [suggested yes, prices unchanged].
- An add-on running out before the dish: reuse the live option's `isAvailable` flag (shared kitchen) [suggested for v1], or a per-day Schedule flag.
- Which plans exist at launch [suggested: Standard only; add others when a real restaurant needs one].
- A restaurant with no plan assigned (P21 (c)).
- ~~How the POS on/off loophole of P23 (b) is closed~~ closed 2026-10-18: only the Ninjasu admin edits dine-in prices (P23, plan #48).
- GST on commission, the aggregator-style model and the 9(5) question go to the CA (task 0.7) before 2b.3.
- Ninjasu revenue per order (about 5-10% effective) must be checked against rider cost per order with pilot numbers.
