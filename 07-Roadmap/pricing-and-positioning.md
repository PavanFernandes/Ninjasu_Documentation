---
id: ""
title: "POS Pricing & Positioning — Working Notes"
summary: "The ₹15k/yr pricing verdict and the reasoning behind it, Ninjasu's positioning as a service-time product and a platform rather than a vendor, and the deferred feature directions with the reasons they were deferred."
type: how-to
status: vision
apps: [backend, web, customer]
module: "roadmap"
anchors: []
verified_against: ""
updated: 2026-09-05
---

# POS Pricing & Positioning — Working Notes

Working notes from a product-advisory session, recorded so the reasoning isn't re-derived. Nothing
here is a locked decision except where marked.

## Company identity — read this before any pricing or roadmap reasoning

**Ninjasu is an online delivery company, not a SaaS company.** That is the identity goal, and it
governs everything below.

- **The intended revenue engine is delivery commission (15%)**, thinner still after rider cost.
  Not live yet — blocked on GSTIN registration (planned Oct 2026, which begins a filing obligation)
  and on the rider app finishing testing. Delivery expands to **groceries** later.
- **The POS is a real secondary business, not an instrument of the delivery one.** Its job right now
  is early cash while delivery is blocked, plus a growth track record and an investor exhibit.
- **POS is not required for delivery partnership.** Any policy- and FSSAI-compliant restaurant is
  onboarded, POS or not — many small restaurants will never need one. The two products share
  customers but neither gates the other.
- A cheaper light tier (₹200–400/month, non-POS features) is an idea for later. **Not open for
  design discussion.**

**Consequence for the feature test below:** judge POS features on whether they serve the POS customer
well. Do **not** justify a POS feature by claiming it locks a restaurant into delivery — it can't,
because delivery is open to everyone. Stickiness is a secondary effect, never the design rationale.

## Pricing — current and the verdict

**Current:** ₹15,000/year (≈ ₹1,250/month effective), or ₹2,000/month monthly.
The ~37% annual discount is deliberate — restaurants churn, and annual commitment buys cash upfront
and lower churn. That structure is sound.

**Verdict: decent and genuinely generous — arguably under-priced — and correct to keep for now.**

### Why it looks low

Restaurant technology spend benchmarks at roughly **1–2% of revenue**. At ₹1,250/month a restaurant
doing ₹3 lakh/month pays ~0.4%; at ₹6 lakh/month, ~0.2%. Well below the normal band.

Risks of under-pricing: cheap reads as *toy* to an owner who has been quoted far more elsewhere, and
increases are hard to land later because annual customers resist and end up grandfathered.

### The reframe that actually matters

> **The real question the price answers is: how many restaurants can you serve before support
> consumes all your build time?**

POS is support-heavy — when billing breaks on a Saturday night, someone calls. Twenty restaurants at
₹1,250 is ₹25,000/month, which does not fund a support person. So the binding constraint is *hours*,
not margin. **Track support hours per restaurant, not revenue** — that number tells you when the
price stops working long before the bank balance does.

*(Noted: the intended model is premium support and onboarding at a higher price point for larger
restaurants. Not designed yet.)*

### What to do now

1. **Call it a founding / introductory rate explicitly.** Lock it for early partners but make clear
   it is not the list price. Costs nothing today; preserves the right to raise later.
2. **Don't discount below it.** There is far more room to be generous in onboarding and
   responsiveness — and that is what a small restaurant actually experiences as generosity. No setup
   fee, no per-terminal charge, unlimited staff logins, mobile app included: cheap to give, feels
   substantial. Sell those loudly.
3. **Keep flat pricing while small.** A 6-table and a 40-table venue paying the same is imperfect,
   but "everything included, one price" is a cleaner offer. **Outlet count** is the natural axis when
   tiering eventually happens.

## Positioning

### The identity already exists in what was built

Everything built well is on the **service-time surface**: the dine-in flow, the captain mobile app a
waiter pulls from his pocket mid-service, guest QR scan-and-order. Everything that felt uncertain
(inventory, bulk reports, accounting integrations) is back-office.

That is a point of view, not a feature list:

> **The POS that is good to actually use during service.**

**The test this gives for any proposed feature:** *does a person touch this while the restaurant is
busy?* If yes, it is core to the identity. If no, it is a checklist item and can wait until a
customer actually blocks on it. This is a better reason to deprioritise something than "a competitor
has it."

### Platform, not vendor — where differentiation must come from

Ninjasu is an ECO operating its own delivery in its area. That makes a category of things possible
that a software vendor structurally cannot copy:

- **Cross-restaurant aggregate data** — e.g. purchase price benchmarking
  ([vision-inventory-module.md](vision-inventory-module.md)).
- **Diner identity across channels** — Ninjasu owns customer identity, order history and repeat
  behaviour across delivery *and* dine-in. A vendor never sees a diner. Loyalty spanning both
  channels, or driving existing nearby delivery users toward a partner's dine-in room, is available
  only to a platform.
- **Bringing restaurants demand, not just software.**

> **Rule of thumb: anything a software company could also build, Ninjasu will be building at parity.
> Anything requiring cross-restaurant data or diner identity, Ninjasu owns alone.**

## Deferred directions, with the reason for deferral

| Direction | Status | Reason |
|---|---|---|
| **Analytics (prep forecasting)** | Wanted, deferred pending data | From order history, tell the kitchen what to prepare more/less. Genuinely uncontested — researched vendors' "AI forecasting" is par-level threshold alerts. Demands **nothing** of the restaurant, which is why it can succeed where inventory adoption fails. |
| **80+ style report suites** | Explicitly rejected | Reports answer questions you already had; insights tell you something you didn't know to ask. Owners don't browse reports. Build insight, not volume. |
| **Tally integration** | Rejected | Locks to one accounting product. Preference is a clean **auditor-usable export** instead — see [vision-inventory-module.md](vision-inventory-module.md). |
| **Local partnerships (bank / institution tie-ups)** | Idea, unscoped | Bank dining programmes want scale (hundreds of outlets), so leverage is low today. Same win-win works at current size with **local counterparties** — office park, college, gym, housing society, co-operative bank. The instinct behind it (bring restaurants customers, not features) is the platform advantage expressed as a growth motion. |
| **Inventory module** | Vision, deferred deliberately | [vision-inventory-module.md](vision-inventory-module.md) — its best feature needs a restaurant cohort to exist first. |
| **Spatial table view** | Vision, agreed as next quick win | [vision-spatial-table-view.md](vision-spatial-table-view.md) |

### How prep forecasting should ship, when it does

- **As tomorrow's prep list, not a chart.** *"Saturday: expect ~120 covers, peak 8–9:30. Biryani 45,
  Paneer 30."* A chef uses that at 9am; a dashboard gets visited twice.
- **Lead with what to stop making** — waste is emotional in a way upside is not.
- **Menu engineering falls out free** — stars vs. dead weight, from order data alone.
- **It should arrive, not wait** — a morning summary landing on the existing mobile app is a
  different product from the same numbers behind a menu item.
- **Two known biases:** cold start (use day-of-week / time-of-day averages, show *ranges* not point
  estimates), and channel blindness (orders on other aggregators are invisible, so forecasts skew
  low — tolerable for directional guidance, not for accounting figures).
- **Cheapest possible test, no code:** run the forecast by hand in a spreadsheet against existing
  order history and see whether it tells a restaurant something it didn't already know.

## Market context — floor-setting only, not a benchmark

> Recorded because it corrects an earlier misreading and cost real research effort. **Petpooja is
> not currently a competitor in Ninjasu's operating area** — this is context for what an owner may
> have seen elsewhere, *not* a roadmap input.

Petpooja's published tier table splits into two blocks:

- **Basic Features** (all tiers): Cloud Billing · **Inventory Module** · 80+ Reports · Third-party
  Integrations · In-built CRM · Unlimited Users & Terminals
- **Market Place Services** (Core ✗ / Growth: *pick any 5* / Scale ✓): **Captain App** ·
  **Scan & QR Order** · Table Reservation · Token Management · Zomato-Swiggy Reconciliation ·
  Website · Online Ordering Widget · Tally · CRM+Loyalty · Virtual Wallet · QR Feedback · Kiosk ·
  Dynamic Reports

Two things follow:

1. **Inventory is a commodity** — it sits in the lowest tier everywhere. Building it closes a hole;
   it never wins a deal. (Reinforces the sequencing in the inventory vision.)
2. Captain app and QR ordering are **upsell-tier** features, not baseline ones.

Reported pricing (Petpooja publishes none; all figures third-party and unreliable): Core ~₹10k,
Growth ~₹20k, Scale ~₹40k.

**Reading the split as a general signal:** a *Basic* block is the checklist a buyer uses to
disqualify; a *Market Place* block is what is desirable enough to charge for.

## Related

- [vision-inventory-module.md](vision-inventory-module.md)
- [vision-spatial-table-view.md](vision-spatial-table-view.md)
- [sales-captain-ordering.md](sales-captain-ordering.md) — existing GTM brief
- [../02-Domain/captain-ordering.md](../02-Domain/captain-ordering.md)
