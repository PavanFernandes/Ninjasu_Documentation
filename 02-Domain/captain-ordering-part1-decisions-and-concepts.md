---
id: ""
title: "Captain Ordering, Part 1 — Locked Decisions & Core Concepts"
summary: "The 7 locked design decisions (D1-D7) and the glossary of Check/KOT/cover/floor-board/KDS concepts, including the reference-number and serial-number schemes."
type: domain
status: active
apps: [backend, customer]
module: "captain-ordering"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/TableCheck.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/Order.java" }
verified_against: ""
updated: 2026-07-11
---

# Captain Ordering, Part 1 — Locked Decisions & Core Concepts

> Part of [captain-ordering.md](captain-ordering.md) — see that index for the other parts and the executive summary.

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

