---
id: ""
title: "Raw-Material Inventory — Vision"
summary: "Design for a purchase-capture inventory module: record supplier bills, never count stock, the grocery list as the input loop, food-cost % from Ninjasu's own sales data, and cross-restaurant price benchmarking — with devil's-advocate conditions and phases."
type: how-to
status: designing
apps: [backend, web, customer]
module: "roadmap"
anchors: []
verified_against: ""
updated: 2026-09-06
---

# Raw-Material Inventory — Design

> **Status `designing` since 2026-09-06.** Full plan with data model, devil's-advocate findings,
> lenses, phases and open decisions was produced as an artifact (link in *Related*). This doc is the
> canonical copy of the decisions. **Build is still gated on a restaurant cohort existing** — see
> *Sequencing*.
>
> **Phase 0 schema layer BUILT and MIGRATION RUN — 2026-09-07.**
> - 11 Java files: entities `RawMaterial` / `MaterialUnit` / `PurchaseSupplier` / `Purchase` /
>   `PurchaseLine`, their repositories, and `config/PurchasingMigrationRunner.java`.
> - Migration applied to **Neon by Samivan** from
>   [`attachments/purchasing-migration.sql`](../attachments/purchasing-migration.sql).
> - **Verified by Spring context load** (`mvnw test -Dtest=NinjaDeliveryServiceApplicationTests`,
>   BUILD SUCCESS): every derived query name resolved, every JPQL string parsed, the migration runner
>   executed against Neon as an idempotent no-op, and `ddl-auto` found **no schema drift** between the
>   entities and the hand-run SQL.
> - **NOT yet verified:** the five *native* queries are registered but never executed — Postgres only
>   parses those on first call. `spendByCategory`, `unitPriceHistory`, `monthlySpendSeries` and the
>   `List<LocalDate>` return mapping stay unproven until the service layer exercises them.
> - **Not built:** service layer, DTOs, controller, the `SecurityConfig` matcher (**D19** — until that
>   exists, any authenticated JWT would reach these endpoints), and the `purchases` upload folder.

## ⚠️ This is NOT the stock ledger

Do not conflate this with [stock-ledger-design.md](stock-ledger-design.md). Two different things
that share vocabulary:

| | This doc | [Stock ledger](stock-ledger-design.md) |
|---|---|---|
| Tracks | **Raw materials** (onions, paneer, oil) | **Sellable menu items** (per-dish quantity) |
| Purpose | What the restaurant *spent* | What a customer can *order* |
| Drives | Spend insight, food cost % | Cart cap, sold-out display |
| Audience | Owner / auditor | Diner |

They are independent. Neither depends on the other.

## Problem

A restaurant owner wants to know what they are spending on raw materials, and where it is going.
They do **not** want to do inventory work. The observed constraint, in the owner's own words:

> "I don't want to sit and track kg and sacks. That is boring. It should be: we purchased a lot of
> material and now we want to record it. It should be easy. People love insights — manual entries
> demotivate."

Every documented failure of restaurant inventory software is a *maintenance-cost* failure, not a
capability failure: counts recorded then ignored, recipes going stale, invoice-entry burden. The
design constraint therefore is **minimise what the restaurant must do**, not maximise what the
system can compute.

## The three models, and why we chose the simplest

| Level | Model | Requires | Gives |
|---|---|---|---|
| **0 — Purchase capture** | Record purchases only | A bill entry | Spend, price trends, food cost % |
| 1 — Periodic | `Opening + Purchases − Closing` | **Weekly physical count** | Actual consumption, variance |
| 2 — Perpetual | Recipe/BOM auto-deduction on sale | Recipe mapping per dish, kept current | Theoretical stock, pilferage detection |

**Decision: build Level 0.** Levels 1 and 2 both demand ongoing manual work the owner has
explicitly rejected, and Level 2 additionally requires seeing *every* sale — which we cannot,
for restaurants also selling via other aggregators or walk-in.

### Why Level 0 is sufficient here, not a compromise

Purchase data alone answers the owner's real questions: what am I spending, on what, is it rising,
am I overpaying for onions versus last month. Counting is only needed for *consumption accuracy and
theft detection*, which is out of scope.

**The multiplier: we already own the sales data.** So one input (the purchase bill) plus data
Ninjasu already holds yields the headline metric every restaurant lives by:

> **Food cost % = purchases ÷ sales** — computed automatically, monthly, with nobody counting anything.

A standalone inventory product cannot do this; it has no sales side. This is a platform advantage,
not a feature.

## Design

### Entry must be near-zero effort

Minimum viable purchase entry is four fields: **date, supplier, total amount, photo of the bill.**
Ten seconds. That alone delivers spend tracking, monthly trend, and food cost %.

**Line-item detail is optional depth, never a requirement.** Most products force line items; that
is the adoption killer. An owner who wants per-material insight adds lines to a bill; one who
doesn't still gets value.

- **No master-list setup step.** Materials are created inline as they are typed on a bill. The
  master builds itself from what the restaurant actually buys. No pre-seeded catalogue — a large
  catalogue is its own search burden.
- **No unit conversion.** Because we record rupees, quantity is optional metadata. Where a
  restaurant *does* want quantity, the rule is **one material = one user-defined unit** ("sack",
  "tin", "kg"), used consistently. No measure classes, no conversion table, no yield %.
- **Store the unit as a record on the material, not a free-text string per row.** Same simplicity
  for the user; leaves the door open if quantities ever need converting.

### The loop — the grocery list is the input mechanism (added 2026-09-06)

Nobody "enters a purchase." The flow is:

1. **System suggests a list** from purchase cadence (median days between purchases per material).
2. **CHEF / MANAGER reviews and edits** — add, remove, adjust; optionally records on-hand for the
   items about to be ordered (a *pre-order check*, not a stock-take — it has a payoff at the end).
3. **Order** happens outside the system (WhatsApp, call, visit).
4. **OWNER / MANAGER receives** — ticks what arrived, fixes quantities, adds prices →
   **this creates the purchase record.** The only place money enters.
5. **Insights** from purchases + net sales (orders domain) feed the next suggestion.

Two entities, never one: `grocery_list` (mutable container) → on receive **creates** an immutable
`purchase` with nullable `source_list_id`. Many purchases per list (partial delivery is normal).
Same container-plus-fired-ticket pattern as KOTs. **List lines carry quantity only, never price** —
that is how cost stays away from CHEF/STAFF structurally.

### Data model (conceptual)

| Entity | Key decision |
|---|---|
| `raw_material` | inline-created from a bill line; `track_quantity` NOT NULL DEFAULT false (explicit flag); `expected_frequency` nullable — **cold-start seed only**, derived cadence wins at ≥3 purchases [D15]; `canonical_material_id` nullable, reserved for benchmarking |
| `unit` | a record per shop, not a string per row; create screen nudges kg / L / piece |
| `supplier` | inline-created, fuzzy-matched; **name only** in v1 |
| `purchase` | `total` NOT NULL and **authoritative**; photo ref; `source_list_id` nullable; immutable once received |
| `purchase_line` | `amount` NOT NULL; `quantity` nullable (NULL ⇔ material untracked at entry); **`unit_id` on the line** so history never rewrites |
| `buy_list` | the **To Buy** surface; status draft · ordered · received · partially received |
| `buy_list_line` | nullable quantity (blank ⇔ *unspecified*, never zero [D17]) + `unit_id` + `observed_on_hand` + `observed_at`; **no price column exists** |
| `bill_photo` | private object key, presigned reads, compressed, no auto-expiry |

Naming: `raw_material_*`, `purchase_*`, `grocery_list_*`. **The word "stock" never appears in this
domain's tables.** Separate package; no shared code with the item stock ledger.

### Grouping

- **Category** (veg, dairy, spices, packaging, gas) — drives the spend breakdown, the headline report.
- **Supplier** — drives price trends and any future reorder/grocery list.
- *Storage location* matters only if periodic counting is ever added (counting is a physical walk,
  and ordering the count by walking route is the single biggest UX win there). Not needed for Level 0.

### What each party gets

- **Restaurant** — spend by month and category; supplier creep; **price-per-material over time**
  (*"onions were ₹31/kg in June, ₹38 now"*); food cost % with no effort.
- **Auditor** — a photographed, dated, supplier-tagged **bill archive**. Restaurants lose supplier
  bills and the CA chases them every year-end. This is real value for the P&L and for substantiating
  a GST audit, and it does **not** depend on the ITC question below.
- **Platform** — see below.

### The platform play: purchase price benchmarking

> *"You're paying ₹38/kg for onions. Restaurants near you average ₹31."*

A single restaurant can never know this. A software vendor cannot produce it either — they sell
tools, they don't aggregate a neighbourhood. Ninjasu can, because it is a platform concentrated in
one area. It costs the owner nothing extra (the bill is already captured) and it compounds with
every restaurant added.

**Constraints to design in from the start:**
- Needs a minimum cohort size before any figure is meaningful.
- One restaurant's supplier prices must **never** be identifiable to another. Aggregate and
  anonymous, or not at all.

## Honest limitations — do not oversell

- **This cannot detect pilferage.** Traditional Indian restaurant inventory is bought precisely for
  theft detection, and that requires counting. The pitch is **spend clarity, not shrinkage control**.
  If a customer specifically wants theft detection, counting is the price and they must opt into it.
- Food cost % at monthly granularity is sound; at weekly granularity, stock-swing noise (a week
  spent building or drawing down stock) makes it misleading.

## ITC — killed, with reasoning

Input Tax Credit was an original motivation. It is **not viable for this audience**:

- Standalone restaurants charge **5% GST with no ITC** on their own sales.
- Under **Section 9(5)**, for orders through an ECO the ECO is the supplier of record — so the
  restaurant cannot claim credit on inputs attributable to those supplies either.
- 18%-with-ITC applies only to "specified premises" (hotel-attached, high room tariff) — a small
  slice of the target market.

Consistent with this, no researched Indian restaurant POS ships ITC; all hand off to accounting
software. Related open question on the sales side: see the GST/FSSAI billing work — both need the
same CA conversation before anything is designed on them.

**Preferred direction instead of a Tally integration:** produce clean **export sheets an auditor
can file GST returns from or import into whatever accounting software they use**. An integration
locks you to one product; an export works for every CA. Route through the `ca-cs-pm` skill for
return-format correctness when it is picked up.

## Sequencing — three different gates, not one "cohort"

**Correction 2026-09-06:** earlier drafts said "gated on a restaurant cohort" as if that were a single
condition. It is three, with very different thresholds, and conflating them made Phase 0's exit
criterion read as circular (it required restaurants using a thing that hadn't been built).

| Gate | Needs | Blocks |
|---|---|---|
| **Somewhere to land** | ~3 live POS restaurants willing to try it | Phase 0 shipping at all |
| **Sales history** | a shop with ≥1 month of orders (≥3 for the trailing-3 headline) | the food-cost-% number only, not the module |
| **Benchmarking cohort** | ≥5 shops tracking overlapping materials in one area | Phase 3 only |

Only the third is the "cannot function without multiple restaurants" case — price benchmarking is the
differentiated feature and it is genuinely impossible early. The first is a much lower bar. **Phase 0
is buildable as soon as there are a few restaurants to put it in front of.**

## ⚠️ Open: what counts as a sale? (D20 — blocks the food-cost panel only)

Codebase recon 2026-09-06 found **no aggregate money query anywhere** and **no single definition of a
sale**. The food-cost denominator therefore needs a product decision before that one panel is built.
Everything else in Phase 0 is unblocked.

Three candidate sources, each wrong differently:

| Source | Covers | Why it's wrong alone |
|---|---|---|
| `orders` | all 3 channels | dine-in rows are **KOT fragments**, not bills; ADR-0012 mandatory `orderType=DELIVERY` filter |
| `table_checks` | dine-in | `status=CLOSED` **includes write-offs** — comped/walked-out revenue counts as sales unless `paymentMode IS NOT NULL` |
| `bills` | dine-in only | right semantics (`WRITTEN_OFF`/`VOIDED`, `businessDate`, indexed on `(shop_id, business_date)`) but **not backfilled** — has a start date, incomplete history |

Two further traps for whatever is chosen:
- **Refunds are on a separate axis.** `paymentStatus` (`REFUND_PENDING`…) is orthogonal to `status`, so
  a `DELIVERED` order can be refunded. The query must filter **both**; no existing code does.
- **No business-day-aware period helper for orders.** `orders.placedOn` and `table_checks.paidAt` are
  raw epoch millis; only `bills` has `businessDate`. `util/BusinessDayResolver` exists (shop-configurable
  start hour, IST) but is not applied to either. A "month" boundary needs deciding.

Whatever is chosen becomes **one read-model owned by the orders domain**. The 5 copy-pasted
`status != CANCELLED` sums are left alone in v1 — consolidating them is separate work.

### Before writing any code — the concierge test (new, 2026-09-06)

A2 ("owners will record bills if entry takes ~10 seconds") is the module's fatal assumption and it
does **not** need software to test:

> Ask 3 partner restaurants to WhatsApp a photo of every supplier bill for two weeks.

- If they won't, **A2 is dead** and no amount of UI fixes it — the module should not be built.
- If they will, you have real Indian supplier bills to design the entry screen against (handwritten
  challans, missing GSTINs, multi-page), plus a head start on actual data.

Concierge beats automation before validation. This costs a WhatsApp group and two weeks, and it is
strictly more informative than shipping Phase 0 blind.

### Food cost % before there is history

A new shop has no trailing 3 months. Fallback ladder, so the panel is never blank or misleading:
< 1 month → "we'll show this once you have a month of sales"; 1–2 months → the monthly figure,
labelled as such; ≥ 3 months → the trailing-3 headline with monthly bars beneath.

## Devil's-advocate findings (2026-09-06)

Eighteen proposals critiqued pre-build across two passes (D1–D14 on the core model, **D15–D18** on the
frequency / filename / naming decisions). **Zero `stop`**, sixteen `proceed with conditions`. The
conditions *are* the design; a build session must not relax them without re-running the critique.

| # | Proposal | Failure scenario | Condition | Verdict |
|---|---|---|---|---|
| D1 | Food cost % = purchases ÷ sales | Free date-range picker: a month of rice bought on the 1st → week 1 reads 80%, week 2 reads 5%; owner distrusts the module | Monthly / trailing-30 only in v1; no free ranges; one UI line explaining why | conditions |
| D2 | Materials & suppliers inline-created | "Onion / onions / Onion (red) / pyaz" → fragmentation kills trends, cadence, benchmarking | Fuzzy match + "did you mean"; **merge** re-points lines and hard-deletes (no `merged_into` implicit filter); reserve `canonical_material_id` | conditions |
| D3 | One user-defined unit per material | Supplier switches 25→20 kg sacks, "sack" silently shrinks; oil in tins *and* bottles inexpressible | Nudge base units at create; **`unit_id` on each purchase line**; accept multi-pack limit in v1, document it | conditions |
| D4 | Quantity optional; two tiers on one model | NULL undefined → cadence engine averages 3 of 8 lines → "you usually buy 2 sacks" when they buy 6 | `track_quantity` NOT NULL DEFAULT false; `quantity IS NULL` ⇔ untracked at entry; engines use non-null only; **never blend tracked/untracked in one figure** | conditions |
| D5 | Bill total + optional lines | Two sources of truth: lines ≠ total, two screens show two numbers | `purchase.total` NOT NULL authoritative; lines are detail; gap shown as "unitemised" | conditions |
| D6 | "The list becomes the purchase" | Partial delivery (Mon + Wed) breaks a single row changing state; editing a received list rewrites a purchase | **Two entities**: `grocery_list` mutable → receive **creates** immutable `purchase` (`source_list_id`); many per list; KOT container/ticket pattern | conditions — biggest |
| D7 | Pre-order on-hand check | Stored on material = the stock ledger we swore off; stale for 45/60; someone builds "current stock" off it | `observed_on_hand` + `observed_at` on the **list line**; no quantity attribute on material; any "remaining" carries its date | conditions |
| D8 | Net sales for the denominator | Inventory calls OrderService (forbidden coupling) and re-defines "sale" | Orders domain exposes one read-model *net sales by shop by period* (excl. cancelled/refunded); inventory consumes. ⚠️ **Unverified** — that such a query exists was asserted, not checked. **First implementation task**: confirm it, and if absent scope it as orders-domain work *before* any inventory code | conditions |
| D9 | Cost must not reach STAFF/CHEF | List shows last price → chef sees cost; or two DTOs drift | **No price column on list lines**; cost exists only on `purchase*`; audience DTOs enforce again | conditions |
| D10 | Benchmarking | k=2 "near you" tells A what B pays; no canonical id = nothing to compare | Not v1; reserve `canonical_material_id`; hard k ≥ 5 constant before any UI; store no cross-shop aggregates in v1 | deferred · conditions |
| D11 | Bill photos | Reusing the public menu-image path exposes GSTINs/prices on a public URL | Private prefix, presigned GET, compress, **no auto-expiry** (tax docs). ⚠️ **SCOPE CORRECTION 2026-09-06:** recon shows **no presigned-GET path exists anywhere** — `S3ServiceImpl.buildFullUrl()` just concatenates a public base URL, and every existing image is served publicly. Presigned reads are **net-new infrastructure**, not a config flag. Also `UploadController.SHOP_FOLDERS` is a closed allowlist (`shops, menu-items, menu-categories, addons`) — an unknown folder throws; `purchases` must be added there *and* to the web `UploadFolder` union | conditions — **bigger than estimated** |
| D12 | Separation from item stock ledger | Both say "stock"; wrong one gets wired; "share the ledger primitive" proposal | Table names `raw_material_*` / `purchase_*` / `buy_list_*`; "stock" banned in this domain; no shared code. ⚠️ **CORRECTED 2026-09-06:** the backend has **no domain packages at all** — it is flat-by-layer (`controller/`, `service/`, `service/impl/`, `repository/`, `entity/`, `dto/<sub>/`). A `purchasing` package would be the first of its kind. **Follow the existing convention**: classes in the flat layers, DTOs in `dto/purchasing/`. Separation enforced by *naming*, not package boundary | conditions |
| D13 | Shop by `shared_id`, no FK | Orphans on soft-delete, as everywhere | Query shop → inventory, never inventory → all | proceed |
| D14 | Greenfield migration | Only sequencing can hurt | ~~Migration → backend → web; no boot-time DDL runner~~ **CORRECTED 2026-09-06 after codebase recon:** this repo has **no Flyway/Liquibase**. The mechanism is `spring.jpa.hibernate.ddl-auto=update` (creates bare tables/columns from entities) **plus a `CommandLineRunner` in `config/`** for everything ddl-auto cannot express — constraints, indexes, backfills. There are 11 such runners. So a boot-time runner is *mandatory*, not forbidden. Copy `config/DineInBillMigrationRunner.java`: `@Slf4j @Component`, `JdbcTemplate`, whole body in try/catch so a failure is **non-fatal**, every statement idempotent (`DROP CONSTRAINT IF EXISTS` → `ADD`, `CREATE INDEX IF NOT EXISTS`) | conditions |
| D15 | Optional declared purchase frequency on a material | **Two sources of truth**: owner declares "weekly", history says every 18 days; engine silently picks one. Declaration goes stale after a menu change and degrades suggestions *permanently* — a derived cadence self-corrects | `expected_frequency` is a **cold-start seed, never an override**: derived cadence wins at ≥3 purchases; declared used only below that. UI names the basis. Never blended. **Never asked at material-create** — lives on the material detail screen. Sole consumer: the suggestion engine below the threshold | conditions |
| D16 | Purchase id in the photo filename, not just the folder | Re-upload writes a second object under the same prefix; orphans that later cleanup can't attribute — two files, same id | Replacing a photo **deletes the previous object**. One photo ref per purchase in v1; multi-page bills deferred, and become an *ordered list* when added, never overwrites | conditions |
| D17 | Untracked materials may appear on a To Buy list | Blank quantity → receive pre-fills `0` → purchase line records zero instead of "unknown", poisoning D4's tracked/untracked distinction | Blank ⇔ **unspecified**, identical to D4's NULL semantics; receive never coerces to 0; purchase line inherits NULL. "You're due for onions" is useful without a number | conditions |
| D18 | Two paths create a purchase (direct entry, receive-a-list) | Second writer skipping the first's validation. A rule later added to direct entry silently doesn't run for list-originated purchases. **This codebase already had this exact bug** — `recordPayment` force-setting KOT `SERVED`, bypassing the stepwise validator and its waiter ping | Receive calls the **same purchase-creation service**, passing `source_list_id`. One writer, one validator | conditions |
| D19 | New endpoints under `/api/shops/{shopId}/purchases/**` | **Any authenticated JWT reaches them.** `SecurityConfig` falls through to `anyRequest().authenticated()` — a *customer* token would pass. The config's own comment flags this as a real past bug | Add an explicit `.requestMatchers("/api/shops/*/purchases/**").hasAnyRole("SHOP","ADMIN")` matcher **and** gate every service method with `verifyRole(shopId, callerId, ShopRoles.MANAGERS_AND_ABOVE)` — never `POS_VIEWERS`, which includes CHEF and STAFF (D9) | conditions |
| D20 | Defining "net sales" for the food-cost denominator | **Far bigger than D8 assumed.** Recon found *no* aggregate money query anywhere, and no single definition of a sale — the `status != CANCELLED` sum is copy-pasted in 5 places. Three candidate sources, each wrong in a different way: `orders` mixes DELIVERY rows with dine-in **KOT fragments** (ADR-0012 mandatory filter); `table_checks.status=CLOSED` **includes write-offs** (comped/walked-out revenue — only `paymentMode IS NULL` discriminates); `bills` has the right semantics (`WRITTEN_OFF`/`VOIDED`, `businessDate`) but is **DINE_IN-only and deliberately not backfilled**. Refunds are on a *separate axis* (`paymentStatus`), so a `DELIVERED` order can be `REFUND_PENDING` — no existing code joins both | **Stop — needs a product decision** (see *Open: what counts as a sale*). Whatever is chosen, it becomes **one** read-model owned by the orders domain, and the 5 copy-pasted sums are left alone in v1 | <span>stop — ask</span> |

### Decide now vs defer safely

**Now (expensive once rows exist):** D6 two entities · D3 unit on the line · D4 explicit flag +
NULL meaning · D5 total authoritative · D7 no `current_qty` · D9 no price on list · D8 sales
read-model owned by orders · D11 private photos · D12 naming/package · reserved slots
`canonical_material_id`, `source_list_id`.

**Later (additive):** unit conversion / multi-pack · fuzzy-match sophistication · bill OCR ·
benchmarking engine + k UI · auditor export (after `/ca-cs-pm`) · reorder thresholds · mobile polish ·
merge UI (capability designed now).

## Phases

| Phase | Ships | Exit criterion |
|---|---|---|
| **−1 Concierge** | *No code.* 3 restaurants WhatsApp their supplier bills for 2 weeks | They actually send them. If not, **A2 is dead and Phase 0 is not built** |
| **0 Capture** | material · unit · supplier · purchase · line · photo; purchases list; 4-field entry + optional lines; materials w/ merge; monthly spend; food cost % (with the history fallback ladder) | **3 restaurants ≥ 1 bill/week for 4 weeks unprompted** (A2). Fewer → stop, interview |
| **1 Loop** | grocery_list + lines; cadence suggestion as draft; CHEF/MANAGER build (web, then mobile); OWNER/MANAGER receive → purchase; partial receive | ≥ 50% of purchases originate from a list; < 50% of suggested lines deleted (A11) |
| **2 Insight** | price-per-material trends; supplier creep; "unitemised" nudges; monthly summary that *arrives* | Owners open it the week it lands, 2 months running |
| **3 Platform** | benchmarking (canonical, k ≥ 5, anonymous); auditor export after `/ca-cs-pm` | First benchmark only when ≥ 5 shops track overlapping materials in one area (A7). **Gated on cohort, not calendar** |

## Assumptions (with kill criteria)

| # | Assumption | Fatal? | Kill criterion |
|---|---|---|---|
| A2 | Owners record bills if entry ≈ 10 s | **yes** | < 3 Phase-0 restaurants at ≥ 1 bill/week after 4 weeks |
| A10 | "Total spend" alone is worth something (not already known from the bank) | for Phase 0 as scoped | Exit interviews say "I already knew that" → Phase 0 must ship lines + food cost % together |
| A11 | Cadence suggestion is a usable draft | suggestion only | > 50% of suggested lines deleted → fall back to "last list as template" |
| A7 | Enough shops track overlapping materials for benchmarking | Phase 3 only | < 5 qualifying shops 6 months after Phase 1 → benchmarking doesn't ship |
| A12 | Fuzzy match keeps fragmentation occasional | no | materials/shop > ~2× what a manager names → matching not working |

Killed, kept for the record: A1 weekly counting · A4 ITC.

## Decisions resolved 2026-09-06

0. **Item frequency — optional, and a seed only.** `expected_frequency` (weekly · fortnightly ·
   monthly · quarterly · yearly), nullable. It earns its place on **cold start**: a quarterly staple
   needs three purchases across nine months before a derived cadence means anything, and the owner
   knows the answer on day one. **Never an override** — see D15 for the precedence rule and the
   never-ask-at-create condition.
1. **Surface names — `Purchases` and `To Buy`.** Nav labels short; page subtitle *"What you buy for
   the kitchen"* carries the description. Rejected "Inventory Purchase" (stacked nouns) and
   "Inventory Purchase Management" (over-promises management this module deliberately doesn't do);
   rejected "Grocery List" as consumer-shaped. **To Buy** pairs with **Purchases** as future and past
   of the same verb and reads as a task, not a category. *Alternative if the customer base skews
   hotel-trained:* **Indent**, the real Indian F&B term — jargon to a small restaurant.
2. **Photo optional**, nudged. Mandatory kills the 10-second entry when the "bill" was a WhatsApp
   message or a slip already thrown away.
3. **Supplier fields v1 — name + phone, both optional.** Phone is a third party's personal data;
   optional-not-required is the safer position. GSTIN deferred.
4. **Storage key** — `shop/<shopId>/inventory-purchase/<purchaseId>/<purchaseId>-<random>.<ext>`.
   The id appears in the **filename as well as the folder**, so a downloaded bill is identifiable on
   its own. **`purchaseId` must be a UUID** (sequential ids make keys enumerable). Private prefix +
   presigned GET as per D11; replacing a photo deletes the old object [D16].
5. **Food cost % — supersedes D1's "monthly only".** Random/bulk purchasing (rice once a quarter)
   distorts any single period; without counting, no period can separate *bought* from *consumed*.
   So: **headline = trailing 3 months**; **monthly bars underneath** so lumpiness is visible rather
   than hidden; **outlier called out in words** (*"March is high because of a ₹42,000 purchase on the
   3rd"*). Still no free date picker.
6. **One module, two nav items, split by task — not by restaurant size.** `Purchases` (everyone) and
   `To Buy` (only restaurants that want the loop). **No mode selector, no size self-classification** —
   that is a decision forced on the owner before they understand the product, and it is where
   adoption dies. A small restaurant simply never opens `To Buy`, exactly as a delivery-only shop
   never opens the Floor tab. Quantity columns appear only for materials marked `track_quantity`.
7. **Merge duplicates — re-point lines, hard-delete the loser.** No `merged_into` pointer: it would
   force `WHERE merged_into IS NULL` on every future query and someone will forget, resurfacing the
   duplicate months later. Admin-only, confirm screen states the effect (*"18 purchase lines move
   from 'onions' to 'Onion'"*), merge is logged, not undoable.

### Deferred to the permission module

**Who builds / receives a list**, and **whether MANAGER sees cost**, are deferred until the
permission module exists.

> ⚠️ **Do not defer D9 with them.** "No price column on `grocery_list_line`" is a *schema* decision,
> not a permission decision. It is what makes cost-isolation structural instead of something the
> permission module must remember to enforce. Defer *who may see what*; keep *what exists where*.

## Related

- **Full plan artifact (2026-09-06):** https://claude.ai/code/artifact/ba50d061-813a-473c-937b-5611909ee3bc

- [stock-ledger-design.md](stock-ledger-design.md) — the *other* thing called stock; unrelated
- [pricing-and-positioning.md](pricing-and-positioning.md) — where this fits commercially
- [vision-spatial-table-view.md](vision-spatial-table-view.md) — the other current vision item
- [../02-Domain/captain-ordering.md](../02-Domain/captain-ordering.md) — the POS this attaches to
