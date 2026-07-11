---
id: ADR-0012
type: decision
status: accepted
apps: ["backend", "customer"]
module: "captain-ordering"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/Order.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/TableCheck.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/PosOrderService.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/PosOrderServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/TableCheckService.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/TableCheckServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/repository/TableCheckRepository.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/controller/PosOrderController.java" }
  - { repo: customer, path: "src/features/pos/types.ts" }
  - { repo: customer, path: "src/features/pos/services/pos.service.ts" }
  - { repo: customer, path: "src/features/pos/components/CheckDetailScreen.tsx" }
  - { repo: customer, path: "src/features/pos/components/KotBuilderScreen.tsx" }
verified_against: "backend ff5ade334891238d16b8010e372fdbbc502c193e; customer 49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-07-10
---

# ADR-0012: Captain Ordering (Dine-In POS + KDS) — Append-KOT-Under-Check Architecture

## Context

Captain Ordering adds a dine-in point-of-sale + kitchen-display flow: a staff member (captain)
seats a table, takes orders across possibly several rounds through the meal, and the kitchen
needs a stable ticket per round that it can act on without it changing mid-cook. None of this
has a customer account or a delivery address — the existing `Order`/`OrderLine` schema was
built for a single-round delivery snapshot, frozen once placed (ADR-0002).

The open question was how to model "keep adding items to the same table" and "settle the whole
table's bill at the end" without reopening that frozen-snapshot contract, while still giving the
kitchen an append-only stream of tickets and giving front-of-house one running tab per table.

**Alternative considered and rejected:** mutable orders — add an `OrderLine.VOIDED` status plus
a `modification_count`, and let staff append/void lines directly on one long-lived `Order` per
table. Rejected because mutating a fired ticket changes it under the chef mid-cook — the exact
class of error a KDS exists to prevent — and it would reopen the frozen `Order` snapshot
contract ADR-0002 established for pricing and audit integrity.

## Decision

Model a dine-in table as a **Check** — a new mutable container entity (`table_checks`)
representing the party's running tab, opened when the table is seated and closed on payment.

Each ordering round is captured as its own **immutable KOT**, modeled as an existing `Order` row
with `order_type=DINE_IN` and a `check_id` pointing at the Check that owns it. "Add more items"
always fires a brand-new KOT (a new `Order` row) — it never mutates an existing one. "Void"
cancels a whole KOT via the existing `CANCELLED` order status, not a per-line void. Mutability
lives in the container (the Check); immutability lives in the artifact (the KOT/Order) — the
same split a physical KOT slip already has in a kitchen.

KOT deliberately **reuses the `Order`/`OrderLine` tables** rather than introducing a parallel
schema: `order_type` is a discriminator (`DELIVERY` default | `DINE_IN` | `TAKEAWAY`), so a KOT
gets the exact same price-snapshot guarantees ADR-0002 already built for delivery orders, and
`PosOrderService.fireOrder` reuses the same menu-validation + price-calculation + snapshot
primitive the customer cart's add-to-cart flow uses — branching the flow by `order_type` instead
of forking the schema avoids a second, drifting copy of that validation logic.

**Also locked as part of this decision (v1 scope):**
- Order types in scope: `DINE_IN` + `TAKEAWAY` only. The delivery ordering flow is unchanged.
- Payment is record-only on the Check — there is no bill-generation/GST module yet; a `BILLED`
  check status is reserved in the enum for that future work but nothing transitions into it, so
  payment goes `OPEN → CLOSED` directly.
- No hard table assignment: any staff member can see and act on any open check (shared
  visibility), with attribution by who opened/fired it and a soft "My Tables" filter deferred.
- A Check may optionally carry a walk-in `customer_mobile`/`customer_name`, but this is never
  linked to a user account — dine-in guests stay unauthenticated.

**Two blockers in existing code that this decision required fixing** (prerequisites for the
decision to be implementable, not separate decisions):
1. Shop-order authorization only checked `shop.ownerId`, so STAFF/MANAGER shop members got a 403
   on shop-order endpoints — fixed to membership-based authorization.
2. `Order`'s delivery columns and `user_id` were `NOT NULL`, and order placement ran a delivery
   radius check — both incompatible with a dine-in order that has no address and no customer
   account. Made nullable and branched by `order_type`.

**Top risks** (ranked; full table in `captain-ordering-FINAL.md` §10):
- **R4** — two parties seated at the same table back-to-back could merge into one bill if a
  stale/duplicate check were opened concurrently. Mitigated with a load-bearing partial unique
  index: at most one `OPEN` check per `(shop_id, table_label)`.
- **R2** — a POS-local menu/addon picker importing from the customer-facing restaurant feature
  would create cross-feature coupling. Resolved by keeping the picker POS-local, importing menu
  types type-only.
- **R3** — no websocket infrastructure exists yet, so the Floor Board and KDS Board poll every
  15–20s and rely on FCM push to prompt an immediate refetch rather than true real-time push.

Verdict from the architect risk review: **Proceed.**

## Consequences

**Makes easy:**
- Kitchen tickets are provably stable once fired — the KDS can trust that a ticket it has
  already shown will never silently change mid-cook, because "add more" always creates a new
  KOT instead of editing an old one.
- Reuses every guarantee ADR-0002 already built for `Order`/`OrderLine` price snapshotting — no
  second schema, no second set of edge cases to get right, no data migration needed.
- Reuses the cart's add-to-cart validation (item active/available, addon-group linkage,
  required-group satisfaction) for POS-fired lines too — one source of truth for "is this a
  valid order line" regardless of whether it comes from a customer cart or a captain's POS.
- Billing is a simple sum over a Check's KOTs; a Check can be closed/paid without touching any
  individual KOT.

**Makes hard / accepted risk:**
- Cross-KOT operations (moving an item between KOTs, or truly editing a fired item) are not
  supported — the only lever is void-the-whole-KOT-and-refire, which is coarser than line-level
  editing. Accepted because it mirrors how kitchens already operate with paper KOT slips.
- Preventing the two-parties-one-table race needed an explicit DB constraint, not just
  service-layer logic — this pushed a load-bearing partial unique index into the schema rather
  than leaving it to application checks alone.
- The Check/KOT split still needs a separate bill module (GST-compliant, sequential `bill_no`)
  built on top — this decision only delivers record-only payment, not a real bill, in v1.

**Rules out:**
- Mutable `OrderLine` editing (`VOIDED` status / `modification_count`) as a pattern for this
  domain — any future "edit an order after firing" request should be designed as void-and-refire
  against this model, not by reopening the rejected mutable-order approach.
- A KOT existing without an owning Check — `check_id` is set if and only if `order_type=DINE_IN`
  (DB-enforced); takeaway orders explicitly do not go through a Check.

**Deliberately out of scope, queued for later** (not forgotten): bill + QR + GST generation,
split bill, guest QR-to-check, move/merge tables, kitchen station routing, offline KOT queue,
delivery add-to-order.

## Enforced in

- `entity/Order.java` — `order_type`/`check_id`/`kot_number`/`placed_by_staff_id`, the fields
  that make a KOT an `Order` row rather than a separate table.
- `entity/TableCheck.java` — the mutable Check container and its status lifecycle.
- `service/PosOrderService.java` / `service/impl/PosOrderServiceImpl.java` — `fireOrder` appends
  a new KOT; `voidOrder` cancels a whole KOT via `OrderStatus.CANCELLED`.
- `service/TableCheckService.java` / `service/impl/TableCheckServiceImpl.java` — Check
  open/close/payment lifecycle.
- `repository/TableCheckRepository.java` — the open-check-per-table uniqueness lookup and the
  row-locked read used by fire/payment operations.
- `controller/PosOrderController.java` — checks, KOTs, takeaway, and KDS-feed endpoints.
- `src/features/pos/types.ts`, `src/features/pos/services/pos.service.ts` — `checkId`-scoped POS
  DTOs on the frontend.
- `src/features/pos/components/CheckDetailScreen.tsx`, `KotBuilderScreen.tsx` — the
  Check-container / append-KOT UI (view a Check's accumulated KOTs; fire a new KOT into it).

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
