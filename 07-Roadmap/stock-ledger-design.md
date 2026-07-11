---
id: ""
type: how-to
status: designing
apps: [backend, admin]
module: "roadmap"
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Daily Stock Ledger ("Prep Assistant") — Design

## Problem

Today, items carry no stock/inventory concept at all — only `is_available` (see
[menu.md](../02-Domain/menu.md)), a manual boolean the seller flips by hand, which never
auto-restores. There is no stock count, no daily reset, no scheduled job of any kind. This
means:

- Sellers have to remember to manually re-enable a "sold out" item the next day.
- There is no visibility into whether a seller under-prepped or over-prepped a dish — no
  data point ever gets captured.
- When a dish sells out, all further demand for it becomes invisible. The seller never learns
  *how much* business they turned away, only that the item ran out.

**The purpose of this feature is not to be a limiter.** It's a **demand-sensing instrument.** A
daily stock reset is a daily *measurement*. Built right, every reset is a permanent data point
that answers "did I prep too much or too little, and do I need more stock tomorrow?" — and rolls
up into trends over time. The eventual pitch to sellers is a **"Prep Assistant"** (a helpful
recommendation), not "inventory management" (a chore) — framing that should carry through the
admin UI copy when this is built.

This design is **stock only**. The separate, already-decided per-line cart quantity ceiling
(flat max per line, `minQuantity`/`maxQuantity` guard on the combined result) is
[ADR-0011](../01-Architecture/decisions/ADR-0011-cart-per-line-quantity-cap.md) and the
"Quantity Rules" section of [cart.md](../02-Domain/cart.md) — not duplicated here. The two
features share one resolver (see below) but are independently phased.

## Design

### Relationship to the per-line quantity cap

Every item exposes two numbers the app enforces on a cart line, both computed by the backend
via **one shared resolver** (never duplicated per call site — menu, home, cart, and order reads
all call the same helper):

- `minQuantity` — the item's minimum order quantity (flat rule, covered by the cart quantity-cap
  work, not this doc).
- `maxQuantity` — branches on the item's `stock_mode`:
  - `UNTRACKED` → the flat per-line cap from [ADR-0011](../01-Architecture/decisions/ADR-0011-cart-per-line-quantity-cap.md) (not this doc).
  - `DAILY` → remaining stock in **today's** open stock period (this doc).
  - `ONE_TIME` → remaining stock in the single open batch period (this doc).
- `effectiveAvailable` — `isActive AND isAvailable AND (UNTRACKED OR remaining > 0) AND (remaining IS NULL OR remaining >= minQuantity)`.
  **Manual pause (`isAvailable = false`) always wins** — stock can only *additionally* hide an
  item, never override a manual pause.

The flat cap and the stock ledger are one system with two branches. Phase 1 (the flat cap) ships
first and lays the `minQuantity`/`maxQuantity` contract on the DTOs; this feature (Phase 2/3)
makes the `DAILY`/`ONE_TIME` branches stock-driven with **no rework** to the contract itself.

### Load-bearing decision: journal, don't overwrite

A single `stock_remaining` column reset nightly would lose all history — no trends possible.
Instead: **one row per (item, stock period)**. A reset is an INSERT of a new period's row, never
an overwrite of an existing one. The reset mechanism *is* the analytics-capture mechanism.

### Stock recurrence modes

Three explicit modes per item — tracking is **config, first-class on the item, never inferred**
from whether a ledger row exists:

- **`UNTRACKED`** (default) — no stock tracking; the flat cap applies (ADR-0011). Existing items
  stay on this mode with zero migration/blast-radius impact.
- **`DAILY`** — resets automatically each business day (owner sets "portions prepped per day").
- **`ONE_TIME`** — a fixed batch; sells out and stays out until the owner manually restocks/reopens
  (no auto-reset).

### Data model sketch

This is a design sketch, not yet implemented — no migration has been run.

```
items (new columns):
  stock_mode   VARCHAR   -- UNTRACKED | DAILY | ONE_TIME, default UNTRACKED
  stock_qty    INT NULL  -- configured amount: per-day allotment (DAILY) or batch size
                          -- (ONE_TIME); NULL/ignored for UNTRACKED. Must be >= the item's
                          -- own minQuantity when tracked (a tracked item must be orderable).

item_stock_ledger (new table, one row per item per STOCK PERIOD — not just per day):
  item_id, shop_id, stock_mode (write-once copy of the mode this period ran under)
  period_start        -- shop-local date the period opened
  planned_qty          -- prepped/allotted this period (seeded from items.stock_qty; owner may override)
  sold_qty              -- incremented atomically at ORDER PLACEMENT
  restocked_qty         -- mid-period top-ups
  turned_away_count     -- unmet demand: adds blocked AFTER the item truly sold out
  sold_out_at            -- timestamp remaining first hit 0 this period (NULL if never) — the "prep more" signal
  is_open                -- exactly one open period per tracked item at a time
```

- **`remaining` is always DERIVED** (`planned_qty + restocked_qty - sold_qty`), **never stored** —
  avoids the two-columns-one-truth drift trap.
- `DAILY` = one row per business day (the reset job closes yesterday's row and opens today's, kept
  as history). `ONE_TIME` = one row per batch, stays open across days until sold out or the owner
  reopens — the reset job never touches it. The same table serves both recurrence modes while
  keeping full history either way.
- `item_id` FK is fine (same domain as `items`). `shop_id` stays FK-free per the project's
  cross-domain decoupling rule.
- Read access to *live* state must always filter `is_open = true` — a plain unfiltered query
  returns every historical period and will overcount or read a stale row. Live decisions never
  read a closed row.

### Two-tier enforcement

Stock is shared across customers but only decremented at **order placement**, never at
add-to-cart (a cart-hold decrement would open a denial-of-inventory loophole — one user could
"lock" the last plate by adding it to cart and never checking out):

- **Soft (cart/stepper):** uses the last-read `minQuantity`/`maxQuantity`. May be slightly stale —
  two customers can both be shown the last plate as available. Expected and acceptable.
- **Hard (order placement):** an atomic conditional decrement is the real gate — exactly one of
  two racing customers wins; the loser is told the item "just sold out" at checkout. This is the
  standard "oversell at cart, reconcile at checkout" pattern used by airlines, Amazon, Blinkit.

### Backend logic (design)

- **Decrement at order placement** (tracked items only) happens through a **shared repository**
  atomic UPDATE (`... WHERE planned_qty + restocked_qty - sold_qty >= :qty`, check rows-affected),
  **not** a cross-module `OrderService → StockService` call — the project's architecture forbids
  direct cross-domain service calls; a shared repo query is the sanctioned pattern. Zero
  rows-affected → reject that line with "only N left" / "just sold out". Lazy-open a missing
  `DAILY` period here as a self-healing backstop.
- **Cancel/decline credits `sold_qty` back** to the *original order's* stock period (matched by
  the order's business date, even if that period is now closed). Without this reverse path, a
  declined order leaves a phantom "sold" plate — a false stockout plus inflated demand data.
  `sold_out_at` itself is left as a historical fact; availability recomputes from `remaining`, so
  a still-open period correctly reappears.
- **Turned-away counter** — increment `turned_away_count` on the open period **only** when a
  *tracked* item blocks an add because it has truly sold out (`remaining = 0`). Not when the flat
  untracked cap or the minimum-quantity rule fires — those aren't lost demand.
- **Reset/seed job (`DAILY` only)** — idempotent and shop-timezone-aware: in one transaction,
  close yesterday's open period and open today's (seeded from `items.stock_qty`), using
  `ON CONFLICT DO NOTHING` so re-running the job is safe. `ONE_TIME` and `UNTRACKED` items are
  skipped entirely — that's the point of those modes. Self-healing: also lazy-open on first
  read/decrement so a failed job never silently hides an item. `period_start` uses the shop-local
  date in v1; a per-shop custom rollover hour is a documented v2 refinement (see Open items below).

### Admin / owner flow (in scope for this feature)

- **Item create/edit form** — add a stock-mode selector with three choices (mirrors Square's
  model): *Unlimited* (default, untracked), *Resets daily* (set portions-per-day), *One-time
  batch* (set a total, no auto-reset). The quantity field only shows when tracked, with inline
  validation (must be >= the item's own minimum order quantity).
- **Live availability control** — new owner-facing, ownership-checked endpoints to mark an item
  sold out early, restock mid-period, or reopen a fresh `ONE_TIME` batch. The existing manual
  `isAvailable` pause toggle is unchanged and continues to always win over stock state.
- **Item list/detail (seller panel)** — for tracked items, surface remaining-today, `sold_out_at`,
  and a restock action.

### Prep Assistant dashboard (Phase 3)

Per item per day: sold / remaining / `sold_out_at` / `turned_away_count`, plus a plain-language
recommendation ("sold out 8h early, ~N turned away → prep more" / "leftover N → prep less") and
7/30-day trends. This is the payoff of journaling every period instead of overwriting a counter —
after several weeks the ledger can surface patterns like "biryani sells out by 1pm every Friday."

### Sold-out display strategy (research-backed, decided as part of this design)

Conclusion: **show, don't hide — but nuance by surface.** Backed by Baymard research (a dead-end
out-of-stock page drives ~30% of users to abandon to a competitor, and most sites miss the chance
to keep the intent) and back-in-stock notification data (meaningful conversion and open rates,
mostly within the first hour). Two points sharpen this for Food Ninja specifically: this is a
native app, so the SEO argument some retail sites use for showing out-of-stock pages doesn't
apply here — the decision rests purely on UX/conversion; and Food Ninja's sold-outs are typically
short and predictable (a `DAILY` item reliably returns tomorrow), which makes "Available
tomorrow" / notify-me messaging unusually effective compared to generic retail.

Decision by surface:
- **Menu (restaurant detail):** show greyed out, `+` disabled, "Available tomorrow" (`DAILY`) or
  "Sold out" (`ONE_TIME`); sort sold-out items to the bottom of their category. Hiding a dish
  entirely makes the menu look broken/incomplete.
- **Search & wishlist:** show greyed with a badge — the user is actively seeking that item, so
  hiding it is a dead end. Wishlist + sold-out + daily-reset is the single best "notify me"
  trigger available.
- **Home curated rails:** rank sold-out items down/last (don't spend a scarce discovery slot on
  something currently unbuyable); hard-hide only if a rail would otherwise be mostly sold-out.
- **Consequence for the shared read paths:** because the decision is to *show* (not filter), the
  home/search/wishlist read paths only need to *return* the availability flag for badging/ranking
  purposes — not add an availability `WHERE` filter. This is lower risk than a filter would be,
  but all three read paths must still be updated in the same change and re-verified for price/
  availability parity with each other (they are a known drift-prone set — see
  [cart.md](../02-Domain/cart.md) and the home filter/sort work for the existing parity
  requirement across these surfaces).

### Guardrail conditions to satisfy before this ships

Carried forward from a devil's-advocate pass — these are build-time conditions, not open product
questions:

- Live reads of `item_stock_ledger` must go through a repository method that filters
  `is_open = true`; never read a closed row for a live decision (see the "implicit-filter trap" —
  a plain unfiltered `SELECT` over this table silently overcounts or reads stale history).
- Wrap the reset job's close-yesterday + open-today in one transaction; treat "no open period for
  a tracked item" as **lazy-open from `items.stock_qty`**, never as "treat it as untracked."
- The `ADD` action must seed the cart quantity at the item's own `minQuantity` (not a hardcoded
  1) — otherwise an item with a minimum above 1 fails on the very first add.
- Decrement targets `WHERE is_open = true` so it is self-correcting even if it lands at the exact
  instant the nightly reset job swaps periods; run the reset job at each shop's low-traffic
  rollover time and accept sub-second boundary imprecision.
- A tracked item must never be saved with a null `stock_qty`, or a `stock_qty` below its own
  minimum order quantity (would make it permanently un-orderable) — enforce with a DB check
  constraint plus inline admin-form validation.
- `item_stock_ledger`'s own `stock_mode` copy is write-once history (the mode a period actually
  ran under); live decisions always read `items.stock_mode`, never the ledger's copy — the two
  are allowed to differ across a mode change and should never be reconciled.
- `turned_away_count` is a rough directional signal in v1 (a single frustrated user tapping a
  sold-out item repeatedly inflates it) — acceptable for v1; a deduplicated "notify me" list is
  the v2 replacement.
- Once `stock_mode` values are persisted, renaming the stored string later is a data migration —
  settle on `UNTRACKED` / `DAILY` / `ONE_TIME` as the stored values now (an admin-facing label can
  still read differently, e.g. "Always available").

### Scale note

At an estimated ~10k shops × ~50 items × 365 days, the ledger is on the order of ~180M rows/year.
Index on `(item_id, period_start)` and `(shop_id, period_start)`; plan for archival of closed
periods in Phase 3.

## Phases (if phased)

This feature is Phases 2 and 3 of a 3-phase rollout; Phase 1 (the flat per-line cap and the
`minQuantity`/`maxQuantity` contract itself) is covered separately by
[ADR-0011](../01-Architecture/decisions/ADR-0011-cart-per-line-quantity-cap.md) and
[cart.md](../02-Domain/cart.md).

- **Phase 2 — Stock ledger.** `items.stock_mode` / `stock_qty`; `item_stock_ledger` table;
  `DAILY` reset/seed job; atomic decrement at order placement; cancel/decline credit;
  `INSUFFICIENT_STOCK` cart validation state; `turned_away_count`; admin stock-mode selector and
  restock endpoints; `minQuantity`/`maxQuantity` become stock-driven for tracked items.
- **Phase 3 — Prep Assistant + scarcity.** Owner dashboard with recommendations and 7/30-day
  trends; "Only N left" scarcity chip on tracked items with low remaining stock.
- **Deferred to v2 (explicitly out of scope for Phase 2/3):** a "notify when back" waitlist,
  pre-order of tomorrow's batch (the highest-commitment version of the notify-me idea — promoted
  ahead of plain notify-me given Food Ninja's short, predictable daily cycle), substitution
  suggestions on sell-out, a Square-style custom per-shop reset time / `day_start_hour` (v1 uses
  shop-local date only), and a platform-wide, cross-shop supply-gap map.

## Related

- [ADR-0011](../01-Architecture/decisions/ADR-0011-cart-per-line-quantity-cap.md) — the decided
  per-line quantity cap this design shares a resolver with (the `UNTRACKED` branch).
- [cart.md](../02-Domain/cart.md) — "Quantity Rules" section documents the current
  `minQuantity`/`maxQuantity` contract this design extends.
- [menu.md](../02-Domain/menu.md) — "Item Rules" documents the current `is_available` /
  `is_active` manual-pause behaviour that this design's `effectiveAvailable` rule must always
  defer to.
