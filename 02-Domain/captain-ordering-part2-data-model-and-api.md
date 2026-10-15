---
id: ""
title: "Captain Ordering, Part 2 — Data Model, Lifecycles, Auth & API"
summary: "New tables (table_checks, shop_tables, shop_counters), Order column additions, status lifecycles, auth/role gating, notification routing, and the full REST API contract (as implemented 2026-07-10)."
type: domain
status: active
apps: [backend, customer]
module: "captain-ordering"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/controller/PosOrderController.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/controller/PosSetupController.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/TableCheckService.java" }
verified_against: "backend@ff5ade334891238d16b8010e372fdbbc502c193e"
updated: 2026-07-11
---

# Captain Ordering, Part 2 — Data Model, Lifecycles, Auth & API

> Part of [captain-ordering.md](captain-ordering.md) — see that index for the other parts and the executive summary.

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
  billed_total       numeric(10,2) null  -- snapshot of sum-of-KOTs at close (report immutability); PRE-TAX — net sales sums it. Amount charged incl. tax = bills.grand_total
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

