---
id: ""
title: "Captain Ordering — GTM / Sales Brief"
summary: "Sales brief for the dine-in POS + Kitchen Display feature: pitch, demo script, onboarding impact, likely objections, and internal red flags to know before demoing."
type: reference
status: active
apps: [backend, customer, admin]
module: "roadmap"
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Captain Ordering — GTM / Sales Brief

**Document type:** GTM — sales brief (Market skill)
**Date:** 2026-07-10
**Feature:** Dine-in POS + Kitchen Display (`feature/captain-ordering`)
**Full plan:** [ADR-0012 — Captain Ordering (Dine-In POS + KDS)](../01-Architecture/decisions/ADR-0012-captain-ordering-dine-in-pos-kds.md)

---

**WHAT IT IS:** The waiter takes the order at the table on the Food Ninja app; it lands on the
kitchen screen instantly, and every round of the meal stays on one running bill the waiter
settles in a tap.

**PROBLEM IT SOLVES:** Handwritten KOTs get lost, misread, or walked to the kitchen late;
the kitchen doesn't know a second round belongs to the same table; the bill is added up by hand.
This removes the paper, the walking, and the mis-add.

**HOW TO EXPLAIN (owner's language, no jargon):** *"Your waiter punches the order at the table —
the kitchen sees it before he walks back. The guest can keep adding through the meal, and it all
stays on one bill. When they're done, the waiter marks how they paid and closes the table."*

**2-MIN DEMO SCRIPT:**
1. Open the **floor board** — a grid of your tables, green = free, colored = seated. *(point at the timer + running total on each tile)*
2. Tap a free table → set 2 guests → tap 3 items → **Fire KOT**. *(point: "that's already on the kitchen screen")*
3. Flip to the **kitchen screen** → tap **Start**, then **Ready**. *(point: "the waiter's phone just buzzed — food's up")*
4. Back on the table → **＋ Add items** → fire a second round → *"same bill, second ticket to the kitchen."*
5. **Record payment** → Cash → table closes. *(point: "dine-in sales stay separate from your delivery numbers")*

**ONBOARDING IMPACT:** +one-time table setup (name your tables, ~2–5 min) + one owner toggle to
enable. No per-order setup. Does not touch the existing <20-min menu-onboarding path (it's a
separate, opt-in surface in the shop panel).

**LIKELY OBJECTION:** *"We already scribble KOTs, why change?"* → *"Because the scribble gets
lost and the kitchen can't tell round 2 is your table. This is faster to punch than to write, and
the bill adds itself."*

**RED FLAGS (internal — fix before demo):**
- No hard table assignment in v1 — for a restaurant that runs strict sections, sell the **"My
  Tables"** filter as the answer, not a limitation.
- Payment is **record-only** in v1 (no money moves, no printed GST bill yet) — set that
  expectation; the QR bill + GST is a later module (backlog).
- Void = cancel a **whole KOT** in v1 (not a single line) — mention it so it isn't a surprise.
- Needs connectivity to fire a KOT in v1 (offline queue is backlog) — don't demo on flaky wifi.

**THE WEDGE (why we beat Petpooja here):** because the guest app runs on the same order model,
a QR on the table can let **guests add to the same running check** — Petpooja sells "captain app"
and "scan-to-order" as two products; we can ship both from one Check. Design for it now, build
later. (Tracked in the innovation backlog notes, not yet migrated into this vault.)
