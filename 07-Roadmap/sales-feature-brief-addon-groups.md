---
id: ""
title: "Shared Addon Groups — Feature Brief"
summary: "Sales feature brief pitching Shared Addon Groups as a time-saving differentiator versus Swiggy/Zomato's per-item-only modifier model, with demo script and pricing positioning."
type: reference
status: active
apps: [backend, customer, admin]
module: "roadmap"
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Shared Addon Groups — Feature Brief

**Document type:** GTM — Sales Feature Brief
**Author:** GTM Agent
**Date:** 2026-05-21
**Audience:** Sales conversations, investor demos, restaurant partner pitches
**Feature:** Shared Addon Groups (SHARED-scoped `addon_groups`)

---

## The One-Line Pitch

> "Update your beverages menu once. Every item that includes it updates automatically — no touching each dish individually."

---

## The Problem We're Solving

### What a restaurant owner experiences on Swiggy/Zomato today:

A restaurant like **Spice Garden** in Bangalore offers beverages alongside most of their dishes. They've listed 40 items, and 35 of them have a "Beverage Add-on" option: Coke (₹60), Sprite (₹60), Lassi (₹80).

Then the supplier raises Lassi prices. The restaurant wants to update it to ₹90.

**On Swiggy's partner portal:**
- Go to item 1 → find Beverage section → update Lassi → save
- Repeat for item 2, 3, 4... all 35 items
- Each save is a separate confirmation
- Total time: 45–90 minutes of manual updates
- Risk: Miss one item → inconsistent pricing → customer complaints

**The hidden cost:** Restaurant operations managers at mid-size QSRs have told us they hire part-time staff specifically to do menu sync work on aggregator portals.

---

## What Food Ninja Does Differently

### Shared Addon Groups — One source of truth for cross-item customizations.

Instead of copying the same "Beverage Add-on" group into 35 items, the restaurant creates it **once** in the Shared Addons section. Then they attach it to whichever items offer beverages.

When the Lassi price changes to ₹90 — they change it **once**. Every item that offers beverages reflects the update **instantly**. No loops. No missed items.

```
Without Shared Groups:         With Shared Groups:
                               
[Item 1] → Beverage Group A   [Shared: Beverage Group] ←── [Item 1]
[Item 2] → Beverage Group B                             ←── [Item 2]  
[Item 3] → Beverage Group C    Price change = 1 edit    ←── [Item 3]
...                                                      ←── [Item N]
Price change = N edits
```

---

## Real Scenarios Where This Wins

| Scenario | Without Shared Groups | With Food Ninja |
|---|---|---|
| Price change on a common add-on | Update every item manually | 1 edit, instant everywhere |
| Seasonal add-on (e.g. summer drinks) | Add to 30 items one by one | Add to Shared Groups → attach to all |
| Roti/bread options across curry dishes | Duplicate group on each dish | One group, linked to all curries |
| "Upgrade to large" across combos | Defined per-item | One "Size" group reused |
| Removing an add-on from all items | Remove from each individually | Unlink from group or delete group |

---

## How It Works for the Restaurant Owner

1. **Go to Shared Addons tab** in the admin panel
2. **Create a group** — name it "Beverages", add options: Coke ₹60, Sprite ₹60, Lassi ₹80
3. **Link it to items** — from any item's edit screen, attach the Shared "Beverages" group
4. **Done.** The group appears on every linked item's customization sheet in the customer app

When prices need updating:
1. **Go back to Shared Addons → find "Beverages" → edit Lassi price → save**
2. All 35 items update. No other steps.

> [!IMPORTANT]
> The admin dashboard **warns the restaurant owner** before they change a shared group price: *"Used by N items — price change affects all of them."* This prevents accidental bulk changes.

---

## The Technical Differentiator (In Plain English)

On Swiggy and Zomato's backend, each item's customization options are stored separately for that item. There is no native concept of a "shared" option set that propagates automatically. When a restaurant partner wants to do a bulk update, they're either doing it manually through the UI or calling account manager support to do it for them.

Food Ninja's data model has `SHARED`-scoped addon groups built into the core schema from day one — it's not a bolt-on feature. This means:
- Changes propagate immediately (no batch job, no sync delay)
- The restaurant's menu is **always consistent** — no partial update states
- Attaching/detaching a shared group from an item is a single action

---

## Comparison vs Swiggy/Zomato

| Feature | Swiggy Partner Portal | Zomato Partner Portal | Food Ninja |
|---|---|---|---|
| Cross-item addon groups | ❌ Per-item only | ❌ Per-item only | ✅ Native SHARED groups |
| Bulk price update | Manual, item by item | Manual, item by item | Single edit, instant propagation |
| Attach same group to new item | Re-create from scratch | Re-create from scratch | Select existing group, attach |
| Warning on shared price change | ❌ | ❌ | ✅ Built in |
| Control over which items share a group | N/A | N/A | ✅ Per-item attachment control |

> [!NOTE]
> Swiggy and Zomato do offer "item-level modifiers" — but these are created per item and not shared across items. Bulk updates require either manual repetition or support escalation.

---

## How to Demo This in 3 Minutes

**Setup:** Have a test restaurant with 5 items, all linked to a Shared "Beverages" group with Lassi at ₹60.

**Script:**
1. *"Here are 5 items on our test restaurant. Every item offers beverages as an add-on."*
2. *"Watch what happens when I change the Lassi price."*
3. Navigate to Shared Addons → edit Lassi → change to ₹80 → save
4. Open any item → show add-on sheet — Lassi shows ₹80
5. Open another item — same. And another.
6. *"One edit. Instant across all items. On Swiggy, you'd be doing this 5 times — or 50 times for a real restaurant menu."*

**Follow-up question to ask the owner:** *"How many items on your current menu share the same add-ons or sides?"*

The answer is almost always "most of them."

---

## Pricing Positioning

This feature is included in the base offering. It is not a premium add-on. The pitch is:
- **For small restaurants:** "Simplicity — set up once, manage once."
- **For mid-size QSRs:** "Operational leverage — your manager doesn't waste time doing menu sync."
- **For chains:** "Consistency — every branch's shared offerings update from one place."

---

## Constraints to Know Before Pitching

> [!WARNING]
> Know these before a demo so you're not caught off guard.

1. **SHARED groups cannot have `is_required = true`** — they are always optional add-ons. If a restaurant needs a mandatory shared option (e.g. "pick a size" that applies to all curries), that must be an ITEM-scoped group on each item.
2. **Discounts do not apply to SHARED group options** — only ITEM-scoped groups can carry discounts. If a restaurant runs a sale on shared add-ons, they'll need to manually reduce prices (which, again, only requires one edit).
3. **Max 4 addon groups per item visible** (SHARED + ITEM combined). A restaurant cannot stack 5 shared add-on groups on one item.
4. **Web admin is not yet built** — the current management UI is mobile-only. For a restaurant with a large team, the full-featured web panel is on the roadmap for a future release.

---

## The Emotional Pitch

Restaurant owners are not software engineers. They opened a restaurant to cook food and serve customers — not to manage a SaaS portal.

When they hear "update once, change everywhere," they don't think about data models. They think about the Saturday afternoon they won't have to spend clicking through Swiggy's portal fixing 40 items because their supplier changed the Roti price.

**That Saturday afternoon is the sale.**

Lead with the time they get back. Close with the consistency they gain.
