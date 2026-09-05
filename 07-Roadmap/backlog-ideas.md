---
id: ""
title: "Backlog Ideas — Food Ninja"
summary: "Ten prioritized feature ideas (promos, scheduled orders, nested modifiers, reorder diff, discount tagging, subscriptions, etc.) grounded in competitor analysis, plus a priority matrix."
type: reference
status: active
apps: [backend, customer, admin]
module: "roadmap"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/Shop.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/FoodItemDetails.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/DeliveryConfig.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/TableCheck.java" }
  - { repo: customer, path: "src/features/restaurant/components/AddonSheet.tsx" }
verified_against: "backend@ff5ade334891238d16b8010e372fdbbc502c193e, customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-07-11
---

# Backlog Ideas — Food Ninja
**Maintained by:** Innovation Scout
**Created:** 2026-05-21
**Basis:** Competitor analysis (Swiggy, Zomato, Deliveroo, DoorDash), current Food Ninja architecture, loopholes identified, [principles.md](../01-Architecture/principles.md).

> These are ideas grounded in real competitor patterns. They are NOT premature abstractions — each is a concrete, scoped feature that has proven value on at least one major platform.

---

## Idea 1 — Cart-Level Promo Code System
**What it is:** A promo code field at checkout that applies a restaurant-funded or platform-funded discount to the cart total. Supports: flat amount off (₹50 off), percentage off (20% off, max ₹100), minimum order threshold.

**Who does it:** Swiggy, Zomato, Deliveroo, DoorDash — all of them. It is table stakes for any food delivery platform.

**Why it matters for Food Ninja specifically:**
- Without promo codes, there is zero mechanism to run a user-acquisition campaign. "Download and get ₹100 off your first order" is the single most effective new-user funnel in Indian food delivery.
- Food Ninja currently has discount infrastructure at the addon-option level (a genuine differentiator) but nothing at the cart level. These two systems are complementary, not redundant.
- The order model snapshot (Principle 18) must include `promo_code_applied`, `discount_amount`, and `promo_source` (restaurant-funded vs platform-funded) from day one of the orders module. Adding this later means a schema migration on a live order history table.

**Suggested Phase:** Phase 1E (Orders module) — design the promo field into the order entity now. The promo redemption UI is Phase 2.

**Architecture note:** Per Principle 2 (Food is a vertical, not the app), the promo system must be cart-agnostic. A promo on a restaurant order and a promo on a grocery order should resolve through the same promo engine, dispatched by vertical.

---

## Idea 2 — Scheduled / Advance Orders
**What it is:** Customer picks a future delivery slot (e.g., "Tomorrow, 1:00 PM") at checkout. The order is placed immediately but the restaurant is notified and starts prep at the right time. Advance window: 2 hours to 2 days.

**Who does it:** Swiggy (Scheduled delivery), Zomato (Schedule for later). Both support 2h–2d advance window. Cancellation allowed up to ~3 hours before slot.

**Why it matters for Food Ninja specifically:**
- Office lunch pre-orders are a high-frequency, high-value use case in the Indian market. A user ordering lunch at 9 AM for 1 PM delivery is a premium, loyal customer.
- `Shop.opening_time` / `closing_time` already exists in the schema. Adding `scheduled_for` (a nullable timestamp) to the order entity is a small schema change with large GTM value.
- Catering use cases (parties, office events) become possible, unlocking a higher-AOV order segment.
- This requires no new infrastructure — it is a `scheduled_for` field on the order, a UI date-time picker at checkout, and a kitchen notification trigger offset by prep_time_mins (which already exists in `food_item_details`).

**Suggested Phase:** Phase 2. Design the `scheduled_for` field into the order entity during Phase 1E, ship the UI and kitchen notification in Phase 2.

---

## Idea 3 — Nested / Conditional Modifier Groups (Progressive Disclosure)
**What it is:** A modifier option can trigger a child modifier group. Example: a burger item has a "Choose your side" group; if the customer picks "Salad", a second group "Choose your dressing" appears. The child group only renders after the parent option is selected.

**Who does it:** Deliveroo (1 level of nesting), DoorDash (up to 5 levels). Industry standard is 2 levels max for good UX.

**Why it matters for Food Ninja specifically:**
- Food Ninja is targeting restaurants. Burger chains, pizza customizers, and build-your-own bowl restaurants depend on this for accurate ordering.
- The current flat model (max 4 groups) forces restaurants to create ugly workarounds like "Ranch Salad", "Vinaigrette Salad" as separate options instead of a clean nested flow.
- The data model would need a new `parent_addon_id` or `child_group_id` on `Addon` or a new join table. This is a schema change — design it carefully before any restaurant with complex menus onboards.
- `AddonSheet.tsx` would need progressive disclosure rendering — child groups appear/animate in after parent option is selected.

**Suggested Phase:** Phase 3. Not needed for launch. Flag to design team before any complex-menu restaurant (chain burger, pizza) is onboarded. The current 4-group flat model is intentional simplicity — do not add nesting unless a real merchant demands it.

---

## Idea 4 — Reorder with Diff Notification
**What it is:** Customer taps "Reorder" on a past order. The app reconstructs the cart, revalidates against current menu (Principle 6 / 18), and shows a diff: "2 items changed since your last order — Large Chicken Burger is now ₹189 (was ₹169). Masala Chai is no longer available." Customer confirms and proceeds.

**Who does it:** Swiggy (Reorder), Zomato (Repeat Order), DoorDash (Reorder). All do basic reorder. **None do the diff notification well** — they typically just silently drop unavailable items. This is the gap.

**Why it matters for Food Ninja specifically:**
- Architecture Principle 18 already mandates that orders snapshot item names, images, descriptions, exact pricing, and all selected addons at time of order. This data is the foundation for a perfect reorder flow.
- Principle 6 mandates cart revalidation at checkout. A reorder that shows a diff before checkout is simply Principle 6 applied with context ("what changed since your last order").
- Swiggy/Zomato silently drop items — users hate this. Food Ninja can be explicitly better: "Here's exactly what changed" is a trust-building UX moment.
- This is achievable as soon as the order model (Phase 1E) and cart revalidation endpoint (Principle 6) are built.

**Suggested Phase:** Phase 2 — immediately after orders and cart revalidation are in place.

---

## Idea 5 — Platform-Funded vs. Restaurant-Funded Discount Tagging
**What it is:** Every discount (promo code, item discount, addon discount) is tagged at the DB level as `RESTAURANT_FUNDED`, `PLATFORM_FUNDED`, or `SHARED`. Settlement reports to restaurants show only what they are responsible for. Platform analytics can see true subsidy cost.

**Who does it:** Zomato (Salt = restaurant-funded, Pepper = platform-funded, Salt+Pepper = shared). Swiggy has a similar internal split. This is how platforms control margin on discounts.

**Why it matters for Food Ninja specifically:**
- Food Ninja's current discount model has no funding-source concept. Every discount on an addon option reduces the restaurant's revenue without any record of whether the platform agreed to share the cost.
- At scale, undifferentiated discounts become an accounting nightmare and a restaurant-relations problem ("you're discounting my food but I'm paying for it").
- The `discount_percent` on `Addon` and `Item` already stores the discount rate. Adding a `discount_funded_by` enum (`RESTAURANT` / `PLATFORM` / `SHARED`) and a `platform_subsidy_percent` field is a schema extension that costs little now and saves enormous pain later.
- This doesn't need a UI at launch — just the schema field. The admin UI and settlement reports are Phase 3.

**Suggested Phase:** Phase 2 schema, Phase 3 admin UI and settlement reports.

---

## Idea 6 — Shop-Level Busy Mode / Prep Time Surge
**What it is:** When a restaurant is overwhelmed with orders, the kitchen can flip a "Busy Mode" toggle. This increases displayed prep time by a configurable amount (e.g., +15 min) without going fully offline. Customers see "Slightly delayed today" instead of finding the shop closed or getting a surprise 45-minute wait.

**Who does it:** Swiggy (Busy Mode, recently added). DoorDash (Busy indicator). Zomato has a variant where prep time is updated dynamically.

**Why it matters for Food Ninja specifically:**
- `food_item_details.prep_time_mins` exists per item. `Shop` has `opening_time` / `closing_time` and `status (DRAFT/LIVE)`.
- There is no middle ground between LIVE and DRAFT. A busy restaurant either shows normally or goes offline.
- A `busy_until` timestamp or `surge_prep_addon_mins` field on `Shop` allows the restaurant to stay visible with realistic expectations, reducing order cancellations from surprised customers.
- This is directly relevant to Principle 17 (availability is a backend decision) — the backend tells the frontend "this shop is busy," the frontend renders "Slightly delayed." The frontend never infers this.

**Suggested Phase:** Phase 2, alongside orders and kitchen management.

---

## Idea 7 — Saved Customisations ("My Usual")
**What it is:** After ordering, the customer can save a customisation as a named preset: "My Usual Biryani" = Full Plate, Extra Raita, No Egg. Next time they visit that item, a "My Usual" quick-add button appears below the item card.

**Who does it:** DoorDash (saved orders), Swiggy (repeat preference surfacing). None do it as an explicit per-item saved customisation — this is a gap in all competitors.

**Why it matters for Food Ninja specifically:**
- Cart key in `useRestaurantCartStore` is already `itemId::sortedAddonIds`. This is the exact data structure for a saved preset — just persist it with a user-given name.
- Principle 18 (orders as future cart sources) already mandates snapshotting all selected addons. Saved customisations are the logical evolution of this — "I liked what I ordered last time; save it as a named option."
- This is a retention feature. Users who save presets have a dramatically lower friction path to reordering — making Food Ninja stickier than competitors without a loyalty program.
- Backend: a `saved_customisations` table with `user_id`, `item_id`, `addon_selection (JSONB)`, `name`. Small, localizable.

**Suggested Phase:** Phase 2 or Phase 3. Low implementation cost, high retention value.

---

## Idea 8 — Admin Analytics: Addon Conversion Rate
**What it is:** In the web admin panel, show restaurants which addon options customers most frequently select, which they skip, and the average order value contribution per addon group. "Customers who add Extra Cheese spend ₹47 more per order on average."

**Who does it:** DoorDash Merchant Portal (modifier performance analytics), Swiggy's partner analytics (partially). Zomato's merchant data is less granular but item-level conversion exists.

**Why it matters for Food Ninja specifically:**
- Food Ninja's addon model is more sophisticated than competitors (per-option discounts, ITEM vs SHARED scope, cascade logic). The admin analytics should be equally sophisticated.
- Restaurants that understand which addons drive AOV will optimize their menus — which improves Food Ninja's GMV without any platform investment.
- The order snapshot (Principle 18) stores all selected addons per order. Once order volume exists, this data is already captured — it just needs an aggregation query and a chart in the web admin.
- This is a web admin feature (Principle 8 — web is primary for admin). The mobile admin does not need it.

**Suggested Phase:** Phase 3 (web admin build).

---

## Idea 9 — Subscription / Free Delivery Pass
**What it is:** A monthly/annual subscription (e.g., ₹99/month) that gives unlimited free delivery on orders above a threshold (e.g., ₹149). Can be stacked with item-level discounts.

**Who does it:** Swiggy One, Zomato Gold, Deliveroo Plus, DoorDash DashPass. This is the retention moat on every major platform.

**Why it matters for Food Ninja specifically:**
- Delivery fee is the #1 reason users abandon carts in food delivery. A subscription removes this friction entirely for frequent users.
- In the Indian market, ₹99–₹149/month feels negligible to users who order 2-3x/week, but adds up to significant platform revenue.
- The `delivery_config` table already has `base_fee`, `per_km_fee`, `free_delivery_above` per shop. A subscription layer simply overrides `effective_delivery_fee = 0` for subscribed users on eligible orders.
- Architecture consideration: subscriptions need a `user_subscriptions` table, a subscription check at cart validation (Principle 6), and integration with the payment system. Do not build until the payment infrastructure is stable.

**Suggested Phase:** Phase 3. Design the subscription check hook in the cart validation endpoint (Principle 6) from day one — retrofitting is painful (Principle 11 / idempotency lesson).

---

## Idea 10 — API-Driven Home Personalization Sections
**What it is:** Home API already has the typed sections design (`PROMO_CAROUSEL`, `RESTAURANT_LIST`, `CUISINE_FILTERS`). Extend it with: `REORDER_SUGGESTIONS` (user's top-3 recent orders), `TRENDING_NEAR_YOU` (orders in the user's area in the last 2 hours), and `RECOMMENDED_FOR_YOU` (collaborative filtering, Phase 3+).

**Who does it:** Swiggy (Minis, Collections, Trending, For You), Zomato (Trending, Recommended). Both move section order and content based on time of day, location, and order history.

**Why it matters for Food Ninja specifically:**
- Principle 3 explicitly mandates that home sections be API-driven and reorderable without an app update. The foundation is already designed — it just needs content types.
- `REORDER_SUGGESTIONS` is purely derivative of the order history endpoint. No ML needed — just "last 3 distinct restaurants ordered from."
- `TRENDING_NEAR_YOU` requires order volume data but the query is simple: count orders from restaurants within the user's delivery radius in the last 2 hours.
- `RECOMMENDED_FOR_YOU` is the Phase 3+ ML feature. Do NOT build it early — Principle 20 (no recommendation engine on frontend, backend concern). When built, it surfaces as just another section type.
- This is the single change that makes the home screen feel alive and personalized vs. a static restaurant list.

**Suggested Phase:** `REORDER_SUGGESTIONS` in Phase 2. `TRENDING_NEAR_YOU` in Phase 2 (requires order volume). `RECOMMENDED_FOR_YOU` in Phase 4+.

---

## Priority Matrix

| Idea | Phase | Impact | Effort | Competitor Parity Gap |
|---|---|---|---|---|
| 1 — Cart-Level Promos | 1E / 2 | 🔴 Critical | Medium | All competitors |
| 2 — Scheduled Orders | 2 | 🟠 High | Low | Swiggy, Zomato |
| 4 — Reorder with Diff | 2 | 🟠 High | Low | No competitor does it well |
| 6 — Busy Mode | 2 | 🟠 High | Low | Swiggy, DoorDash |
| 10 — API Home Sections | 2 | 🟠 High | Medium | All competitors |
| 5 — Discount Tagging | 2 schema | 🟡 Medium | Very Low | Zomato, Swiggy |
| 7 — Saved Customisations | 2–3 | 🟡 Medium | Low | None (differentiator) |
| 3 — Nested Modifiers | 3 | 🟡 Medium | High | Deliveroo, DoorDash |
| 8 — Addon Analytics | 3 | 🟡 Medium | Medium | DoorDash |
| 9 — Subscription Pass | 3 | 🔴 Critical (at scale) | High | All competitors |

---

## Idea — Guest QR-to-Check (unify captain ordering + scan-to-order)  [from Captain Ordering scout, 2026-07-10]

**✅ SHIPPED 2026-08-03** — see [`02-Domain/guest-ordering.md`](../02-Domain/guest-ordering.md).
The mechanism landed as per-table-session staff approval rather than making the Check fully
source-agnostic as originally sketched below; description kept for historical context.

**What it is:** A QR sticker on the dine-in table that opens the *same* `table_checks` row the
waiter is using. A guest adds "one more naan" from their own phone → it drops in as another KOT
on the waiter's check + the kitchen queue, no waiter retype.

**Who does it:** Petpooja (Captain App) and Eat App / sunday sell "captain ordering" and
"scan-to-order at table" as **two separate paid modules**. On our architecture they're the
**same Check with two input sources** — because the customer app already runs on the shared
`Order` model, the second source is nearly free.

**Why it matters:** genuine wedge vs the incumbent, not a me-too. Design the Check as
**source-agnostic now** (an order joins a check regardless of who placed it) to keep the door
open at zero cost. Build later.

**Suggested phase:** after Captain Ordering Phase 2 ships. Depends on `table_checks` +
staff-attribution fields already in the schema.

## Idea — Delivery "Add to Order" (Blinkit parity)  [from Captain Ordering scout, 2026-07-10]

**What it is:** Customer adds a forgotten item to an in-flight *delivery* order (before it's
packed/dispatched), no second order / no extra delivery fee. Blinkit shipped this; users want
the window open "until the rider departs."

**Why it's separate from Captain Ordering:** it's a delivery, customer-side feature with no
KOT-coursing. Do NOT fold it into captain ordering (scouted ideas queue, never inject
into the current sprint). When built, evaluate **mutable order vs a small linked order stapled
to the same delivery trip** — the packer/rider manifest shouldn't mutate under them either
(same fired-ticket principle, one layer out). Needs optimistic-concurrency (customer edits while
shop accepts) we don't have today.

## Deferred sub-features (Captain Ordering backlog)  [2026-07-10]

bill + QR pay-at-table + **GST breakup** (dine-in bills are legally GST-itemized in India — our
orders carry no tax fields today) · split bill · move/merge tables · kitchen-station routing ·
offline KOT queue (Petpooja works offline) · covers / turn-time analytics · discounts & comps.
