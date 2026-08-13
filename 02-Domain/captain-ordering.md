---
id: ""
type: domain
status: active
apps: [backend, customer]
module: "captain-ordering"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/controller/PosOrderController.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/controller/PosSetupController.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/TableCheckService.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/PosOrderService.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/PosOrderServiceImpl.java" }
  - { repo: customer, path: "app/(shop)/dinein.tsx" }
  - { repo: customer, path: "src/features/pos/components/PosLauncherScreen.tsx" }
  - { repo: customer, path: "src/features/pos/services/pos.service.ts" }
  - { repo: customer, path: "src/features/pos/types.ts" }
verified_against: "backend@ff5ade334891238d16b8010e372fdbbc502c193e customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-07-11
---

# Captain Ordering — Dine-in POS + Kitchen Display (KDS)
## Full Specification & Build Plan

**Branch:** `feature/captain-ordering` (frontend + backend)
**Date:** 2026-07-10
**Status:** Model locked, verified against code, devil's-advocate passed. Ready to break into build tickets.
**Skills applied:** architect · market (scout + GTM) · ui_engineer · error_audit · api_contracts · devils-advocate.
**Related docs:** `agents/arch-notes/decisions.md` (decision record) · `agents/sales-docs/captain-ordering-sales.md` (GTM brief) · `agents/innovation/backlog-ideas.md` (deferrals).

> See [ADR-0012](../01-Architecture/decisions/ADR-0012-captain-ordering-dine-in-pos-kds.md) for the architecture decision this spec implements.

---

## 0. Executive summary

We are adding a **restaurant-facing ordering mode** to Food Ninja: shop staff take a table's order
on the app, it appears on the kitchen's screen instantly, every additional round stays on one
running bill, and the waiter is pinged the moment food is ready to serve. It is the well-known
**POS + KDS** (Point-of-Sale + Kitchen Display System) pattern — the same thing Petpooja's Captain
App does — but built as an **extension of Food Ninja's existing order engine**, not a new system.
The core modelling choice: a dine-in table is a **Check** (a mutable running tab), and each round of
ordering is an **immutable KOT** (kitchen order ticket) that is just an `Order` tagged
`order_type=DINE_IN`. Payment is recorded on the check. Delivery is untouched.

---

## 1. The goal

Let a restaurant run its **in-house dining and counter takeaway** on the same app it already uses
for delivery — turning Food Ninja from a delivery channel into the restaurant's **operating system
for every order**, regardless of where the order comes from.

Concretely, after this ships a restaurant can:
- Give a waiter a phone that takes orders at the table and sends them straight to the kitchen.
- Show the kitchen a live screen of tickets to cook, with a one-tap "ready" bump.
- Keep every round of a table's meal on one bill and settle it in a tap.
- See dine-in and takeaway sales **separately** from delivery.

---

## 2. The real-world problem we're solving

**Today, in a typical small/mid Indian restaurant, dine-in ordering is paper and shouting.**

1. A waiter writes the order on a paper pad (a "KOT").
2. He walks it to the kitchen, or calls it out. Tickets get **lost, misread, or delivered late**.
3. The kitchen has **no way to tell** that the second round of naan belongs to the same table as
   the first — so items get duplicated, missed, or made for the wrong table.
4. When the food is ready, someone **shouts for the waiter**, who may be across the floor.
5. At the end, the bill is **added up by hand** from the scattered paper — slow and error-prone.
6. If the restaurant also uses a delivery app, that's a **second, disconnected system** — dine-in
   and delivery numbers never live in one place.

Each of these is a concrete cost: lost tickets = remade food = wasted stock; late tickets = slow
tables = fewer covers per night; hand-added bills = math errors and disputes; disconnected systems
= no single view of the day's revenue.

**The industry-standard fix is POS + KDS.** The waiter's order enters in a standard digital format,
transmits instantly to a kitchen screen (no printing, no shouting), the kitchen bumps each item
when done which pings the front-of-house, and every order — dine-in, takeaway, delivery — flows into
**one queue labelled by type**. This is a solved pattern, which is exactly why it's low-risk to
build on our existing model.

> **Grounding / sources:** [Petpooja Captain App](https://www.petpooja.com/poss/captain-ordering-app)
> (the direct Indian analog — steward takes the order at the table, KOT auto-sent to kitchen, bill
> settled at the table), [Toast KDS](https://pos.toasttab.com/hardware/kitchen-display-system) and
> [Restaurant365's KDS guide](https://www.restaurant365.com/blog/kitchen-display-system/) (single
> queue labelled by order type; bump → ready), [Eat App](https://restaurant.eatapp.co/pay-at-table)
> / [sunday](https://sundayapp.com/) (pay-at-table QR — deferred to our backlog).

**Why this is an extension, not a rebuild:** Food Ninja already has `Order` / `OrderLine` /
`OrderLineAddon`, a `PLACED→ACCEPTED→PREPARING→READY` status machine, `UserShop` staff membership
(OWNER/MANAGER/STAFF), a `PriceCalculator`, and an FCM notification listener that *already rings
every shop member on a new order*. The captain flow reuses all of it.

---

## 3. Who it's for (personas)

| Persona | Role in the system | What they do |
|---|---|---|
| **Owner / Admin** | `OWNER` membership | Turns the feature on (`pos_enabled`), sets up the table list, sees all sales. |
| **Manager** | `MANAGER` membership | Everything a waiter does + table setup; later: discounts/comps. |
| **Waiter / Captain** | `STAFF` membership | Opens a table's check, fires KOTs, serves, records payment. The primary user. |
| **Kitchen** | any member on the KDS device | Watches the live ticket board, taps Start / Ready. |
| **Guest** | walk-in (not a platform user) | Sits, orders via the waiter — or scans the table's QR to order themselves, gated on a one-time staff approval per table-session. See [`guest-ordering.md`](guest-ordering.md) (built 2026-08-03, separate from this spec's original scope). |

---

## 4. A day in the life (end-to-end walkthrough)

1. **Seat.** A party of 3 sits at Table 7. The waiter opens Food Ninja's floor board, taps the green
   **T7** tile, sets covers = 3 (optional), and a **Check** opens for T7.
2. **First round.** He taps 3 drinks and 2 starters, hits **Fire KOT**. `KOT #1` is created as an
   immutable `Order` under T7's check and instantly appears on the **kitchen screen**.
3. **Cook.** The kitchen taps **Start** (→ PREPARING), then **Ready** (→ READY). The waiter's phone
   buzzes: *"T7 ready to serve."* The T7 tile shows a green "ready" badge.
4. **Serve.** He serves and taps the KOT **Served**.
5. **Second round.** The table wants mains + more naan. He opens T7's check, taps **＋ Add items**,
   fires `KOT #2`. The kitchen sees *"T7 · KOT 2"* — unambiguously the same table, a new ticket.
6. **Bill.** After the meal he taps **Record payment**, picks **UPI**, confirms. The check sums
   KOT 1 + KOT 2 into one total, marks paid, and **closes**. T7 goes green (free) again.
7. **Reporting.** That sale lands in the day's numbers tagged **DINE_IN**, kept separate from
   delivery.

Takeaway is the same, minus steps 1 and 4–6's table: the counter staff fires a single KOT tagged
`TAKEAWAY`, the kitchen makes it, it's marked collected, payment recorded.

---

## 5. What success looks like · Non-goals

**Success metrics (post-launch):**
- Time from "waiter takes order" to "kitchen sees it": from minutes (walk/shout) to **seconds**.
- Zero lost tickets; every add-on round correctly attributed to its table.
- Dine-in + takeaway revenue visible **separately** from delivery in the shop's own numbers.
- A waiter can fire a KOT in **under ~20 seconds** and few taps.

**Non-goals for this feature (explicitly out of scope — see backlog §14):**
- Money movement / payment gateway, printed GST bill, QR pay-at-table, split bill.
- Guest self-ordering via QR — now built as its own feature, see [`guest-ordering.md`](guest-ordering.md); was designed-for but out of scope when this spec was written.
- Delivery "add to order" (Blinkit-style), rider app, kitchen-station routing, offline mode,
  move/merge tables, discounts/comps.

---

## 6. Locked decisions

| # | Decision | Why |
|---|---|---|
| **D1** | **Orders are immutable** (delivery *and* dine-in). "Add more items" = append a **new immutable KOT**, never mutate an existing order. | A KOT is a fired ticket; mutating it changes the ticket under the chef's hands mid-cook — the exact error KDS exists to prevent. Append is kitchen-correct and reuses the frozen `Order` snapshot untouched. |
| **D2** | **A KOT *is* an `Order`** with `order_type=DINE_IN` + `check_id`. Same table & machinery as a delivery order; branch the *flow*, not the schema. | Avoids duplicating OrderLine / snapshot / PriceCalculator logic (ARCHITECTURE.md Principle 14: business logic in two places = drift). |
| **D3** | **Check = mutable per-table container** (the party's tab); **KOT = immutable artifact** under it. | "Void" = cancel a whole KOT (existing `CANCELLED`); audit trail = the list of KOTs; no per-line status machine or `modification_count`. |
| **D4** | v1 fulfillment = **DINE_IN + TAKEAWAY**. DELIVERY unchanged. | Takeaway = dine-in minus the table; same discriminator, same recompute, same KDS queue — near-zero extra cost. |
| **D5** | Payment = **record-only** (mode + mark paid) recorded **on the Check**. | The check is the correct aggregation point — one payment settles all its KOTs. Bill/QR/GST deferred. |
| **D6** | Multi-staff = **no hard table assignment**; shared floor visibility + **attribution** (`opened_by_staff_id`, `placed_by_staff_id`) + a soft **"My Tables"** filter. | Restaurants split between sectioned and pooled service, and staff cover for each other; a hard lock causes "I can't serve that table" failures. Serves both styles with zero config. |
| **D7** | Contact = optional `customer_mobile` / `customer_name` on the Check, **not linked to any user account**. | A walk-in is not a platform user; auto-linking by phone risks wrong-person spend attribution + privacy. Loyalty linking is a later opt-in. |

---

## 7. Core concepts (glossary)

- **Check** (`table_checks`) — a party's running tab at a table. Mutable container; opens when they
  sit, closes when they pay. Holds many KOTs. **This is the durable per-table object.**
- **KOT** (Kitchen Order Ticket) — one round of ordering = one immutable `Order` (`order_type=DINE_IN`,
  `check_id` set, `kot_number` = 1,2,3…). Fires to the kitchen; never edited.
- **Cart / draft KOT** — the in-progress selection the waiter is building *before* he taps Fire.
  Client-side (Zustand), **one draft per table** on that device. Becomes a KOT on fire. (Not a
  server `cart_session` — that model is one-per-user and would fight multi-table.)
- **Cover** — one guest. `covers` = party size (optional).
- **Floor board** — the grid of table tiles the waiter works from.
- **KDS** — the always-on kitchen screen of live tickets.

### 7.1 Reference numbers — type prefixes (so a glance tells you what it is)

Every human-facing reference carries a **type prefix**, derived from the UUID (stateless, no
counter) — the same `substring(0,6).toUpperCase()` shape as the existing `shortRef`:

| Thing | Prefix | Example | Where it shows |
|---|---|---|---|
| Delivery order (customer) | `ORD-` | `ORD-3F9A2C` | customer + seller order screens, push copy |
| Dine-in KOT | `KOT-` | `KOT-7B1E04` | KDS ticket, check detail, push copy |
| Takeaway order | `TKA-` | `TKA-9C22A1` | KDS ticket, pickup call-out |
| Table check (the bill) | `CHK-` | `CHK-A50F3D` | check detail, payment record |

```java
// one helper; replaces the local shortRef in OrderNotificationListener
public final class Ref {
  public static String of(Order o) {
    String p = switch (o.getOrderType()) {
      case DELIVERY -> "ORD"; case DINE_IN -> "KOT"; case TAKEAWAY -> "TKA";
    };
    return p + "-" + code(o.getId());
  }
  public static String check(UUID id) { return "CHK-" + code(id); }
  private static String code(UUID id) {
    return id.toString().replace("-", "").substring(0, 6).toUpperCase();
  }
}
```

The `ORD-/KOT-/TKA-/CHK-` ref is the **globally unique system handle** (logs, support, search,
push) — stable but not shoutable. The **shoutable/accounting numbers are separate serials** (§7.2).
A dine-in ticket on the KDS reads **"T7 · KOT #42"** — table for context, daily serial for the ticket.

### 7.2 Serial numbers — internal ID vs human number (locked 2026-07-10)

Two identifiers, never conflated:

| Layer | Field | Shape | Scope | Resets |
|---|---|---|---|---|
| **Internal identity** | `Order.id` | UUID (`gen_random_uuid()`) | global | never — **stays UUID, never serial** |
| **System handle** | `Ref.of()` (§7.1) | `KOT-7B1E04` (UUID-derived) | global | never |
| **Kitchen call-out** | `orders.kot_number` | `#42` (serial) | **per shop** | **daily** |
| **Bill / GST invoice** | `table_checks.bill_no` | `2026-27/000123` (gapless serial) | **per shop** | **financial year** |

**Why the PK is never serial:** the FK-free shared-id architecture needs UUIDs; idempotency already
dedupes; a serial PK leaks daily volume and creates insert hotspots.

**Why daily for KOT, FY for bill:** the KOT is an operational number the kitchen shouts within a
shift → reset at midnight so it stays small. The bill is an accounting artifact → GST requires a
**consecutive serial, unique within a financial year, ≤16 chars**, so it resets on 1 April. Not
monthly (satisfies neither norm).

**`kot_number` meaning:** a **per-shop daily serial** (the shoutable ticket number), **not** a
round-within-check counter. "Round 2 for T7" is just the KOT's position in the check's list (derived,
no column). `bill_no` is built with the deferred bill/GST module but its counter is reserved now.

**Gapless + concurrency-safe:** both serials come from `shop_counters(shop_id, counter_type,
period_key, value)`, incremented under a row lock in the same transaction (`INSERT … ON CONFLICT DO
UPDATE SET value = value + 1 RETURNING value`). `period_key` (a date for KOT, the FY string for bill)
is what makes it reset per period — a Postgres `SEQUENCE` is wrong here because it gaps on rollback.

---

## 8. Data model

> All cross-domain references are **shared-id, FK-free** (per `project_cross_domain_fk_free` and the
> Dependency & Coupling Guard).

### 8.1 New table — `table_checks` (the running tab)

```
table_checks
  id                 uuid pk (gen_random_uuid())
  shop_id            uuid            -- shared-id ref, no FK
  table_id           uuid null       -- shared-id ref to shop_tables
  table_label        varchar         -- denormalized snapshot ("T7")
  covers             int null        -- guest count, optional (D7)
  customer_mobile    varchar null    -- optional contact, NOT a user FK (D7)
  customer_name      varchar null
  opened_by_staff_id uuid            -- attribution (D6)
  opened_at          bigint          -- epoch millis (matches Order.placed_on)
  status             varchar(20)     -- OPEN | BILLED | CLOSED | VOIDED
  billed_total       numeric(10,2) null  -- snapshot of sum-of-KOTs at close (report immutability)
  payment_mode       varchar(20) null    -- CASH | UPI | CARD  (the payment source of truth, per DA-5)
  paid_at            bigint null
  closed_by_staff_id uuid null
  updated_at         bigint

  -- INVARIANT: one open party per table (load-bearing — see DA / Risk R4)
  PARTIAL UNIQUE (shop_id, table_label) WHERE status = 'OPEN'
```

The partial unique index stops two consecutive parties at the same table from merging into one
bill, and makes "find the open check for T7" a single lookup.

### 8.2 New table — `shop_tables` (table setup; powers the grid)

```
shop_tables
  id          uuid pk
  shop_id     uuid
  label       varchar        -- "T7", "Patio 2"
  area        varchar null   -- optional section ("Rooftop", "AC")
  sort_order  int default 0
  is_active   boolean default true

  -- (shop_id, label) unique only among ACTIVE rows (partial index,
  -- uq_shop_tables_shop_label_active) — a deactivated table's label is free
  -- for a new table to reuse; a plain UNIQUE would permanently squat it
  -- (found in code review 2026-07-10, fixed same day).
```

### 8.3 `Order` changes (Phase-0 migration)

```
+ order_type          varchar(20) NOT NULL DEFAULT 'DELIVERY'   -- DELIVERY | DINE_IN | TAKEAWAY
+ order_source        varchar(20) NOT NULL DEFAULT 'CUSTOMER'   -- CUSTOMER | STAFF
+ check_id            uuid null                                 -- set ⟺ order_type = DINE_IN
+ kot_number          int null                                  -- per-shop DAILY serial (call-out #), from shop_counters (§7.2)
+ placed_by_staff_id  uuid null                                 -- who fired it (staff orders)
~ user_id             -> make NULLABLE   (dine-in/takeaway have no customer account)
~ delivery_lat/lng/formatted_address/label -> make NULLABLE
~ payment_method      -> ignored/nullable for order_source=STAFF (truth is table_checks.payment_mode, DA-5)
```

**Migration semantics (existing rows):** `order_type='DELIVERY'`, `order_source='CUSTOMER'`,
`check_id`/`kot_number`/`placed_by_staff_id` NULL, `user_id` unchanged. Delivery flow unaffected.
**Nullable meaning is explicit:** `check_id NOT NULL ⟺ order_type=DINE_IN`; `user_id NULL ⟺ order_source=STAFF`.

### 8.4 `OrderStatus` additions
Add `SERVED` (dine-in) and `COLLECTED` (takeaway). Existing values untouched.

### 8.5 `Shop` setting
```
+ pos_enabled  boolean default false   -- owner-only toggle; gates the whole POS surface
```

### 8.6 New table — `shop_counters` (gapless per-shop serials, §7.2)
```
shop_counters
  shop_id      uuid           -- shared-id ref
  counter_type varchar(20)    -- 'KOT' | 'BILL' — CHECK-constrained
  period_key   varchar(10)    -- '2026-07-10' (daily) | '2026-27' (FY)
  value        int default 0
  PRIMARY KEY (shop_id, counter_type, period_key)
  CHECK (counter_type IN ('KOT','BILL'))
```
Incremented in ONE round trip via a non-`@Modifying` native query returning `RETURNING value` as a
scalar (`ShopCounterRepository.upsertAndGetNext`) — deliberately not the upsert-then-separate-`find`
shape, which risked Hibernate's first-level cache returning a stale managed `ShopCounter` for the
same composite ID (found in code review 2026-07-10, fixed same day — see decisions.md addendum).
Feeds `orders.kot_number` (daily) and `table_checks.bill_no` (FY).

---

## 9. Status lifecycles

```
Check:         OPEN ──► BILLED ──► CLOSED            (VOIDED = abandoned before any KOT)

Dine-in KOT:   PLACED(fired) ──► PREPARING ──► READY ──► SERVED
               any non-terminal ──► CANCELLED (with reason)   = "void this KOT"

Takeaway KOT:  PLACED(fired) ──► PREPARING ──► READY ──► COLLECTED

Delivery:      unchanged (PLACED→ACCEPTED→PREPARING→READY→OUT_FOR_DELIVERY→DELIVERED)
```

Dine-in/takeaway have **no ACCEPTED/DECLINED** — the waiter *is* the shop. `validateSellerStatusTransition`
branches on `order_type`.

---

## 10. Auth & gating

- **Fix `verifyShopOwnership`** (currently `userId == shop.ownerId` only) → membership-based: caller
  must hold a `user_shops` row for the shop. Staff already get a `ROLE_SHOP` token (via invite
  consumption) so they pass `SecurityConfig`; the *service* is the only gate that wrongly rejects
  them today. **Pure service-layer fix.**
- **Add `SecurityConfig` matchers** for the new POS paths (DA-1): `/api/shops/*/checks/**`,
  `/tables/**`, `/kds`, `/takeaway-orders` → `hasRole("SHOP")`. Without this they fall through to
  `anyRequest().authenticated()` and any customer could call them.
- **Role matrix (v1):**

  | Action | OWNER | MANAGER | STAFF |
  |---|---|---|---|
  | Toggle `pos_enabled` | ✅ | ❌ | ❌ |
  | Set up tables | ✅ | ✅ | ❌ |
  | Open check / fire KOT / serve | ✅ | ✅ | ✅ |
  | Void a KOT (with reason) | ✅ | ✅ | ✅ (attributed) |
  | Record payment / close check | ✅ | ✅ | ✅ |
  | Discount / comp a bill | ✅ | ✅ | ❌ (deferred) |

---

## 11. Notifications (reuse existing FCM infra)

- **New dine-in/takeaway KOT fired** → ring the kitchen. Reuse `OrderPlacedEvent` + `tokensForShop`.
  Add `order_type` to the payload so the board/KDS can route.
- **KOT hits READY** → ring the **placing waiter** (`placed_by_staff_id`), *not* a customer. The one
  routing change in `OrderNotificationListener`: for `order_source=STAFF`, push "ready to serve" to
  the placer's tokens + drop a floor-board badge.

---

## 12. API contracts (new — under `/api/shops/{shopId}`, ROLE_SHOP + membership) — IMPLEMENTED 2026-07-10

```
# Table setup + POS toggle — PosSetupController
PATCH  /api/shops/{shopId}/pos-settings      { posEnabled }                    OWNER only
GET    /api/shops/{shopId}/tables                                             any member
POST   /api/shops/{shopId}/tables            { label, area? }                 OWNER/MANAGER
PATCH  /api/shops/{shopId}/tables/{id}       { label?, area?, sortOrder?, isActive? }  OWNER/MANAGER
DELETE /api/shops/{shopId}/tables/{id}       -> soft-deactivates (is_active=false), never a hard delete

# Checks (dine-in) + KOTs + takeaway + KDS — PosOrderController
POST   /api/shops/{shopId}/checks                         { tableId|tableLabel, covers?, customerMobile?, customerName? }
GET    /api/shops/{shopId}/checks?status=OPEN             -> defaults to OPEN if status omitted
GET    /api/shops/{shopId}/checks/{checkId}               -> detail: kots[] + runningTotal
POST   /api/shops/{shopId}/checks/{checkId}/kots          { items:[{ menuItemId, quantity, selectedAddonIds }] }
                                                           + header Idempotency-Key   -> fires a KOT (Order)
PATCH  /api/shops/{shopId}/checks/{checkId}/kots/{orderId}/status  { status }         -> PREPARING|READY|SERVED
POST   /api/shops/{shopId}/checks/{checkId}/kots/{orderId}/void    { reason }         -> CANCELLED
POST   /api/shops/{shopId}/checks/{checkId}/payment                { mode }           -> CLOSED directly (v1 skips BILLED)

# Takeaway (single-shot, no check) — same fireOrder/updateStatus/voidOrder primitives, checkId=null
POST   /api/shops/{shopId}/takeaway-orders          { items[], customerMobile?, customerName? } + Idempotency-Key
PATCH  /api/shops/{shopId}/takeaway-orders/{orderId}/status  { status }
POST   /api/shops/{shopId}/takeaway-orders/{orderId}/void    { reason }

# KDS live feed
GET    /api/shops/{shopId}/kds?sinceHours=6   -> non-terminal DINE_IN+TAKEAWAY orders, oldest-first, tableLabel-enriched
```

**Deviations from the original sketch (all intentional, see decisions.md):** added the `/pos-settings`
toggle endpoint (was implicit in Phase 0's "enforcement is Phase 1" note) and explicit status/void
endpoints for takeaway (the original sketch only showed them nested under checks) — both dine-in and
takeaway status/void route through the same `PosOrderService.updateStatus`/`voidOrder`, since a takeaway
order needs the identical PREPARING→READY→(terminal) lifecycle.

**Reuse rule (DRY) — implemented as designed:** `PosOrderService.fireOrder` is the shared primitive for
both dine-in KOTs and takeaway, recomputing every price through the existing `CartPricingService` →
`PriceCalculator.java` and re-validating required addon groups against the LIVE menu (mirrors
`CartServiceImpl`'s addon validation exactly — same rules, not a second implementation). The POS
**never** trusts a client-sent price. `kot_number` is the per-shop **daily** serial from `shop_counters`
(§7.2) — never trusted from the client, computed in a fixed `Asia/Kolkata` zone. `OrderMapper` (extracted
from `OrderServiceImpl.toResponse`) is the one shared Order→DTO mapper for both the delivery flow and
captain-ordering — no second copy to drift.

**Role enforcement (implemented via the new shared `ShopMembershipService`):** table setup + the
`pos_enabled` toggle are role-gated per §10's matrix (`ShopRoles.MANAGERS_AND_ABOVE` / `OWNER_ONLY`);
check/KOT/payment actions are membership-only (any OWNER/MANAGER/STAFF), matching "no hard table
assignment" (D6). `OrderServiceImpl`'s own membership check now delegates to this same shared service
instead of a second hand-rolled copy — the duplication the Altitude review finding flagged.

**Concurrency (DA-4, implemented):** `TableCheckRepository.findByIdAndShopIdForUpdate` takes a
`PESSIMISTIC_WRITE` row lock for the duration of the fire-KOT / record-payment transaction, so a
payment can't be recorded while another KOT is mid-fire on the same check. An idempotent replay
(same `Idempotency-Key`) short-circuits before the lock is ever taken.

Every endpoint above is now also documented in `skills/api_contracts.md` (request/response
shapes, drift risks, consumed-by — currently "none yet," frontend not started).

---

## 13. Frontend / UI spec (ui_engineer + error_audit)

**Location:** new `src/features/pos/` feature + routes under `app/(shop)/pos/` (the seller panel).
Entry appears only when `pos_enabled`. Reuse `BRAND.colors`, `AppText` variants (never `fontFamily`
in StyleSheet), `SafeImage`, FlashList, skeletons, safe-area insets. **Coupling flag (R2):** POS must
NOT import the menu picker / `AddonSheet` from `features/restaurant` — extract a shared lean picker
into `shared/` or build a POS-local one.

**13.1 Floor Board** (`FloorBoard.tsx`) — the hero screen. Grid of table tiles; each shows table
label, **status colour** (FREE / OCCUPIED / BILL-REQUESTED / **FOOD-READY**), covers `👥N`,
**turn-timer** (amber >45m, red >90m), running ₹ total, opened-by chip, "ready to serve" badge.
Header: shop name · **"My Tables"** soft filter · **Takeaway** · refresh. Tap free → open-check sheet
→ Check Detail. Tap occupied → Check Detail. States: no tables → "Set up your tables" CTA; all free →
"All tables free"; API fail → retry; slow → skeleton tiles. Live: poll ~15–20s + pull-to-refresh +
refetch on FCM data-message (R3: polling, not websockets, at this scale).

**13.2 Check Detail** (`CheckDetailScreen.tsx`) — header (table · covers · timer · opened-by · running
total); **KOT list** (each round: `KOT #n` · time · placed-by · items · status chip · void). Primary
CTA **"＋ Add items (new KOT)"** → Item Picker. Secondary **"Record payment"** (enabled once ≥1 KOT) →
mode sheet (Cash/UPI/Card) → check CLOSED. Show every field (`value ?? '—'`).

**13.3 Item Picker / KOT Builder** (`KotBuilder.tsx`) — the "one cart per table" (client-side draft,
one per open check). Search + category chips; tap item → +1 (stepper morph) or AddonSheet if
customizable. Bottom running-KOT bar + big **"Fire KOT →"**. On fire: `POST …/kots`, clear draft,
back to Check Detail.

**13.4 KDS Board** (`KdsBoard.tsx`, `app/(shop)/pos/kds.tsx`) — always-on kitchen device. Live tickets
(dine-in + takeaway), oldest-first, **colour-aging** green→amber→red by wait. Ticket = table label /
takeaway token · `KOT#` · items+addons+notes · timer. Buttons **Start** (→PREPARING), **Ready/Bump**
(→READY, notifies waiter + grays out). Filter: last 6h, non-terminal.

**13.5 Table Setup** (`TableSetupScreen.tsx`, owner/manager) — add/edit/remove tables (label + area).
**13.6 Setting toggle** — shop settings: "Enable Captain Ordering (Dine-in POS)", owner only.

**Error/empty/offline (error_audit) — key cases:** floor API fail → retry; offline → banner + block
the one write that matters (fire KOT) with a clear reconnect message (offline queue = backlog); item
unavailable at fire → 400 naming the item; double-fire → Idempotency-Key; payment on closed check → 409.

---

## 14. Phased delivery plan

**Phase 0 — Foundations (backend, unblocks all).**
- [x] Membership-based auth fix (`verifyShopOwnership` → `verifyShopMembership` via `user_shops`).
- [x] `SecurityConfig` matchers for new POS paths (DA-1) — `/tables/**`, `/checks/**`, `/kds/**`, `/takeaway-orders/**` → `hasRole("SHOP")`.
- [x] `pos_enabled` on `Shop` entity (owner-only toggle; enforcement at the endpoint is Phase 1).
- [x] `SERVED`/`COLLECTED` added to `OrderStatus`. (Transition-validation branching by `order_type` is Phase 1, once the KOT status-update endpoint exists.)
- [x] Type-prefixed `Ref` helper (§7.1) — `util/Ref.java`; replaced `shortRef` in `OrderNotificationListener`; `OrderPlacedEvent`/`OrderStatusChangedEvent` extended with `orderType` to carry it (entity-decoupled, per those events' existing design).
- [x] Branch `toResponse()` by `order_type` — no null `deliveryAddress` DTO for dine-in (DA-2); `OrderResponse` gained `ref`/`orderType`; FE `IOrderResponse` updated (`deliveryAddress` now `| null`, both consumers null-guarded); FE typecheck clean.
- [x] Type-filter every existing shop-orders read to `DELIVERY` (DA-3) — new `OrderRepository` methods (`findByIdAndShopIdAndOrderType`, `findByShopIdAndOrderTypeOrderByPlacedOnDesc`, `findByShopIdAndOrderTypeAndStatusOrderByPlacedOnDesc`) with the mandatory-filter warning documented on the repo interface; old unfiltered methods removed (no other callers).
- [x] Extract `buildLinesFromCartItems` out of `placeOrder` (reusable/testable). The raw-menu-item POS variant (KOT-fire endpoint) is genuinely Phase 1 — it needs new repository lookups + a controller that don't exist yet; building it now would be a half-finished endpoint, so it's deferred there by design, not oversight.
- [x] New entities + repositories for the schema below: `OrderType`, `OrderSource`, `CheckStatus`, `CheckPaymentMode` enums; `ShopTable`, `TableCheck`, `ShopCounter`(+`ShopCounterId`) entities; matching repositories; `ShopCounterService`/`Impl` (row-locked gapless increment, `Propagation.MANDATORY` so a rollback of the write also rolls back the number).
- [x] Backend compiles clean (`mvnw compile` — 227 source files, BUILD SUCCESS). Frontend `tsc --noEmit` clean (0 new errors; 4 pre-existing unrelated errors untouched).
- [ ] **Run the Phase-0 SQL migration** against Neon — [captain-ordering-migration.sql](../attachments/captain-ordering-migration.sql) (manual, no Flyway; run by Samivan).
- [x] **Audit every query touching `Order.user_id`** now that it's nullable — grepped all
      `order.getUserId()` call sites. Both (in `OrderServiceImpl.cancelOrder` / `updateOrderStatus`)
      only ever run on customer-placed orders (`cancelOrder` is customer-only; `updateOrderStatus`
      is now DA-3-scoped to `orderType=DELIVERY`), which always carry non-null `userId` — no unsafe
      null-dereference exists today. Auth/account-deletion flows operate on `User`, not `Order`, so
      unaffected. **Watch item for Phase 1:** any new code reading a STAFF-placed order's `userId`
      must not assume non-null.

**Phase 1 — Captain → Kitchen (core loop). Backend: DONE (2026-07-10). Frontend: not started.**
- [x] `shop_tables` CRUD backend (`ShopTableService`/`PosSetupController`, owner+manager only) + `pos_enabled` toggle (owner-only). Table Setup **screen** not built (frontend).
- [x] `table_checks` + open-check endpoint (`TableCheckService.openCheck`) — partial-unique invariant + friendly `ConflictException` (409) pre-check.
- [x] Fire-KOT endpoint (`TableCheckService.fireKot` → `PosOrderService.fireOrder`) — append immutable Order; guards `check.status='OPEN'` via `findByIdAndShopIdForUpdate` (PESSIMISTIC_WRITE row lock — DA-4); idempotent replay short-circuits before the lock.
- [x] `kot_number` = per-shop **daily** serial via `shop_counters` (row-locked, gapless — §7.2), computed in a fixed `Asia/Kolkata` zone (not JVM default — the timezone risk flagged before any code existed). Shown as `OrderResponse.kotNumber`.
- [x] Floor Board · Check Detail · KOT Builder **screens** — built 2026-07-10 (`src/features/pos/components/`). Typecheck clean.
- [x] KDS feed endpoint (`GET /kds?sinceHours=`, `PosOrderService.getKdsFeed`, enriched with `tableLabel`) + status-bump endpoints (`PATCH .../kots/{orderId}/status`). KDS **screen** built 2026-07-10 (`KdsBoardScreen.tsx`, polls 15s, Start/Ready bump).
- [x] Notifications: new KOT/takeaway → kitchen (`onOrderPlaced`, copy branched by `orderType`); READY → placing waiter (`onOrderStatusChanged` now routes staff orders to `placedByStaffId` instead of a customer — this also fixed the dormant NPE finding from the review, since it's the first code path that actually publishes this event for a null-`customerUserId` order).
- [x] Composite index `(shop_id, order_type, status, placed_on)` — already existed from the Phase 0 migration.
- [x] Takeaway (`POST /takeaway-orders` + status/void) — same `fireOrder`/`updateStatus`/`voidOrder` primitives, `checkId=null`.
- [x] Shared `ShopMembershipService` (role/membership check) — replaces the duplicated logic the review flagged (Altitude finding); `OrderServiceImpl` now delegates to it too.
- [x] Shared `OrderMapper` (extracted from `OrderServiceImpl.toResponse`) — used by both the delivery flow and captain-ordering, so the two can't drift. Also fixed the DA-5 gap (`paymentMethod` now omitted for non-CUSTOMER orders) since STAFF orders are real starting with this build.

**Phase 2 — Serve + payment. Backend: DONE (2026-07-10), folded into the same build (see note).**
- [x] `SERVED`/`COLLECTED` transitions (`PosOrderService.updateStatus`, terminal depends on `orderType`).
- [x] Record payment on the check → **CLOSED directly** (v1 skips `BILLED` — nothing sets it without the deferred bill-generation module; documented in `TableCheckServiceImpl.recordPayment`).
- [x] Void-a-KOT/takeaway-order with reason (`PosOrderService.voidOrder`).
- [ ] "My Tables" soft filter — frontend, not started. **Dependency:** needs `placedByStaffId`
      surfaced on `OrderResponse` (currently on the `Order` entity but NOT in `OrderMapper`/DTO —
      same class of gap as the `posEnabled`/ShopDto miss, just not yet triggered because nothing
      reads it yet). Add it to `OrderMapper.toResponse` + `IOrderResponse` when building this.
- [ ] Reporting: dine-in/takeaway segregated from delivery — not built (a dashboard/analytics concern, separate from the endpoints themselves; the data is already segregated at the query level via DA-3 type-filtering).

**Note on phasing:** Phase 2's KOT-lifecycle items (status/void/payment) were built together with Phase 1
rather than as a separate pass — they share the same files (`PosOrderService`, `TableCheckService`) and
splitting them would have meant reopening the same classes twice for no benefit. Only the genuinely
separate Phase 2 items (frontend filter, reporting dashboard) remain.

**Backlog (NOT this feature — see `agents/innovation/backlog-ideas.md`):** bill + QR pay-at-table +
**GST breakup** · split bill · move/merge tables · kitchen-station routing · offline KOT queue ·
**delivery add-to-order (Blinkit parity)** · covers/turn-time analytics · discounts & comps.
(**Guest QR-to-check** shipped separately — see [`guest-ordering.md`](guest-ordering.md), no longer backlog.)

---

## 15. Risks + Devil's Advocate (verified against code, 2026-07-10)

**HIGH — fold into Phase 0 (shared code paths / security):**
- **DA-1 — New POS endpoints open to any customer.** `SecurityConfig` only role-gates `/orders/**`,
  `/my`, `/invites|members/**`; the rest hits `anyRequest().authenticated()`. → add `hasRole("SHOP")`
  matchers + keep the service membership check.
- **DA-2 — Nullable `delivery_*` breaks in-flight readers.** `toResponse()` unconditionally builds a
  `DeliveryAddressDto`; a dine-in order ships nulls to every order-screen consumer. → branch by
  `order_type`; update FE `IOrderResponse` same PR.
- **DA-3 — Implicit-filter trap.** KOTs share the `orders` table, so `getOrdersForShop` leaks dine-in
  KOTs into the delivery list unless every read filters `order_type='DELIVERY'`. Violates the "don't
  mix dine-in with delivery" requirement. → type-filter every shop-orders query + document it.

**MED — fold into Phase 1:**
- **DA-4 — Check = shared mutable state.** Race: payment recorded (CLOSED) while another waiter fires
  a KOT → unpaid items. → fire rejects unless `status='OPEN'`; payment is a guarded transition with a
  row lock, one `@Transactional`.
- **DA-5 — `Order.payment_method` meaningless per-KOT** (NOT NULL, only `CASH_ON_DELIVERY`). → truth is
  `table_checks.payment_mode`; ignore/nullable on staff orders; don't overload the delivery enum.
- **DA-6 — Migration/rollback + Flyway.** `DROP NOT NULL`/default-adds are metadata-only (low pain) but
  re-adding NOT NULL is impossible once dine-in rows exist. → confirm Flyway; numbered migration;
  accept one-way rollback.

**Named earlier (architect pass):**
- **R2** POS↔restaurant menu-picker cross-feature import → extract to `shared/`.
- **R3** No websockets → poll 15–20s + FCM refetch; revisit at multi-terminal.
- **R4** Two parties, one table → `PARTIAL UNIQUE(shop_id, table_label) WHERE status='OPEN'`.
- **R6** Client forges price/kot_number → recompute via `PriceCalculator`; derive `kot_number` server-side.
- **R8** Void scope = whole KOT in v1; partial-line void deferred (tell the restaurant explicitly).
- **DA-7** Scale: polling load ≈ devices×shops/interval — fine now; add the KDS composite index.

**VERDICT: Proceed with conditions.** No `stop`: every open question has a decision or a safe default.
DA-1/2/3 move into Phase 0 because they touch shared code and security — cheapest before Phase 1.

**Verification that HELD:** append-KOT reuses `OrderLine`/`OrderLineAddon` cleanly; the auth fix is
genuinely service-layer only; `PriceCalculator` reuse is sound (POS snapshots fresh from the live menu
at fire time — simpler than the cart, no staleness).

---

## 16. Open items to confirm (safe defaults in place)

1. **Turn-timer thresholds** — default amber >45m / red >90m. Cosmetic.
2. **Who can void / record payment** — default: STAFF may (attributed); comps/discounts = manager (deferred).
3. **Takeaway token** — default: per-shop daily counter for call-out; falls back to order short-ref.
4. **Tables set up before go-live?** — default: yes; a "quick add table" exists on the board for ad-hoc.
5. **Migration** — run [captain-ordering-migration.sql](../attachments/captain-ordering-migration.sql) manually (no Flyway). One-way once dine-in rows exist (DA-6).
6. **Numbering** — LOCKED (§7.2): UUID PK stays; `kot_number` = per-shop daily serial; `bill_no` = per-shop FY serial (bill module); both via `shop_counters`. Takeaway call-out uses the `KOT`-type daily serial too.

---

## 17. Appendix

**Existing code this builds on:** `entity/Order.java`, `OrderLine.java`, `OrderLineAddon.java`,
`OrderStatus.java`, `entity/UserShop.java`, `entity/Shop.java`, `service/impl/OrderServiceImpl.java`,
`controller/ShopOrderController.java`, `notification/OrderNotificationListener.java`,
`config/SecurityConfig.java`, `util/PriceCalculator.java`; FE seller panel `app/(shop)/`.

**Sources (industry grounding):** Petpooja Captain App · Toast KDS · Restaurant365 KDS guide · Eat App
pay-at-table · sunday. (Links in §2.)

**Migration SQL:** [migration SQL](../attachments/captain-ordering-migration.sql)
