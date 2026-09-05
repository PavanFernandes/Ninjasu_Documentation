---
id: ""
title: "Captain Ordering, Part 3 — Frontend Spec, Delivery Plan & Risks"
summary: "The Floor Board / Check Detail / KOT Builder / KDS / Table Setup UI spec, the phased delivery plan with build status, the devil's-advocate risk register, and open items/appendix."
type: domain
status: active
apps: [backend, customer]
module: "captain-ordering"
anchors:
  - { repo: customer, path: "src/features/pos/components/PosLauncherScreen.tsx" }
  - { repo: customer, path: "src/features/pos/services/pos.service.ts" }
verified_against: "customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-07-11
---

# Captain Ordering, Part 3 — Frontend Spec, Delivery Plan & Risks

> Part of [captain-ordering.md](captain-ordering.md) — see that index for the other parts and the executive summary.

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
