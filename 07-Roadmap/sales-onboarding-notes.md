---
id: ""
title: "Food Ninja — Restaurant Owner Onboarding Audit"
summary: "GTM audit of the download-to-first-item-live onboarding flow, finding the 20-minute target unachievable (actual 45-75 min) and ranking friction points by severity with fix effort."
type: reference
status: active
apps: [backend, customer, admin]
module: "roadmap"
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Food Ninja — Restaurant Owner Onboarding Audit

**Document type:** GTM — Onboarding Experience Audit
**Author:** GTM Agent
**Date:** 2026-05-21
**Scope:** What a restaurant owner experiences from app download → first menu item live on the platform

---

## Target vs Reality

| Metric | Target | Honest Assessment |
|---|---|---|
| Onboarding time (full) | 20 minutes | **45–75 minutes (first attempt)** |
| Onboarding time (tech-savvy user) | — | ~35 minutes |
| Onboarding time (non-tech user, e.g. street vendor) | — | Likely abandoned or requires handholding |

> [!CAUTION]
> The 20-minute target is **not achievable** with the current UX. The addon group model, while technically elegant, adds significant cognitive load for a restaurant owner who just wants to list "Butter Chicken – ₹280."

---

## Step-by-Step Journey (Current State)

### Step 1 — Download & Signup
- User downloads the app
- OTP sent to phone → enters OTP → account created
- **Friction:** OTP is hardcoded to `1234` (dev placeholder). If this ships, any bad actor can verify any phone number. No SMS provider integrated.
- **Time estimate:** 2–3 min (once OTP works correctly in production)

### Step 2 — Create a Shop
- User navigates to admin panel
- Fills in: shop name, address, cuisine type, opening/closing time, delivery radius, coordinates, shop image
- **Friction points:**
  - Coordinates input — most restaurant owners have no idea what lat/long means. No map picker built yet.
  - Delivery radius — requires knowledge of km. No visual representation.
  - Cuisine type is a lookup — the dropdown works, but there's no search.
  - Shop image requires S3 presigned URL upload — if this breaks or is slow, first impression is a failure.
  - Shop status defaults to `DRAFT` — the owner may not understand they need to explicitly go `LIVE`.
- **Time estimate:** 8–12 min

### Step 3 — Create Menu Categories
- User must create at least one category before adding items
- Categories support 2 levels (e.g. "Main Course → Biryani")
- **Friction points:**
  - The 2-level category rule is not explained to the user
  - Attempting to add a sub-category to a category that already has items (or vice versa) throws an error — but the error message is backend-generated and may not be user-friendly
  - No suggested/starter categories offered
- **Time estimate:** 3–5 min

### Step 4 — Create Menu Items (THE BIGGEST FRICTION POINT)
- Owner opens ItemFormModal.tsx (59KB — the largest frontend file)
- They must:
  1. Enter item name, description, food type (veg/non-veg/egg), prep time
  2. Upload an item image
  3. **Create at least one ITEM-scoped Addon Group with `is_required = true`** — this is what defines the price
  4. Add at least 2 options to that addon group (e.g. "Regular – ₹280", "Large – ₹350")
  5. Assign the item to a category
- **Friction points:**
  - The concept of "addon group = price" is **completely non-intuitive** for a restaurant owner. They expect a price field. There is none.
  - The error message "Add at least one item-specific required option to define this item's base price" will confuse most first-time users
  - For a simple item with a single price (e.g. "Lassi – ₹60"), the owner still has to create an addon group named something like "Size" with one option "Regular – ₹60" marked as required
  - Image upload adds latency and potential failure points
  - The form is on mobile — 59KB of logic on a small screen is a UX risk
- **Time estimate per item:** 4–7 min
- **For a restaurant with 20 items:** 80–140 minutes just for item entry

### Step 5 — Shared Addon Groups (Optional but Valuable)
- Owner goes to SharedAddons tab to create reusable groups (e.g. "Beverages", "Roti Options")
- **Friction points:**
  - The distinction between ITEM-scoped and SHARED-scoped addon groups is a technical concept, not a restaurant concept
  - There is no onboarding tooltip or wizard explaining when to use each
  - Most owners will skip this entirely on first use and miss the most powerful feature on the platform
- **Time estimate:** 0–10 min (most will skip)

### Step 6 — Go Live
- Owner must toggle shop status from `DRAFT` to `LIVE`
- **Friction:** This toggle is not prominent. No completion checklist ("You've added 5 items! Ready to go live?")

---

## Friction Point Summary

| # | Friction Point | Severity | Fix Effort |
|---|---|---|---|
| F1 | No price field — addon group required to set price | 🔴 Critical | High (UX abstraction layer needed) |
| F2 | Coordinates input for shop location (no map picker) | 🔴 Critical | Medium |
| F3 | No onboarding wizard / guided setup flow | 🔴 Critical | Medium |
| F4 | OTP hardcoded — not production-ready | 🔴 Critical | Medium (SMS provider integration) |
| F5 | ITEM vs SHARED addon group concept unexplained | 🟡 High | Low (tooltips/copy) |
| F6 | "Go live" step is easy to miss | 🟡 High | Low (checklist UI) |
| F7 | No starter category suggestions | 🟠 Medium | Low |
| F8 | Item creation form is mobile-only and complex (59KB) | 🟠 Medium | High (web admin planned) |
| F9 | No progress indicator during setup | 🟠 Medium | Low |
| F10 | Cuisine lookup has no search | 🟢 Low | Low |

---

## 20-Minute Target Assessment

**Verdict: Not achievable today.**

The primary blocker is the addon-group-as-price model. A restaurant owner adding their first item will spend 5–10 minutes just trying to understand why there is no price field, what an "addon group" is, and why they must add two options before saving.

**What would get us to 20 minutes:**

1. A **setup wizard** (4–5 screens): Shop details → Upload logo → Add first category → Add first item (with a simplified "just set a price" mode that auto-creates the addon group behind the scenes) → Go live.
2. A **"Quick Price" shortcut** in ItemFormModal that auto-creates a required addon group named "Price" with one option at the price the owner types — hiding the complexity for simple items.
3. A **map picker** for shop coordinates.
4. A **completion checklist** on the admin home screen.

---

## Benchmark Comparison

| Platform | Estimated Time to First Item Live |
|---|---|
| Swiggy Partner | ~25–35 min (web, guided) |
| Zomato Partner | ~20–30 min (web, guided) |
| Food Ninja (current) | ~45–75 min (mobile, unguided) |

> [!NOTE]
> Swiggy and Zomato have dedicated web onboarding portals with step-by-step wizards, phone support, and field agent assistance for larger restaurants. Food Ninja's web admin is planned but not started — until it launches, we are asking owners to do a complex setup on mobile.

---

## Recommendations for Next Sprint

1. **Build the "Quick Price" shortcut** into ItemFormModal — single input, auto-generates addon group. This alone cuts item creation time by 60%.
2. **Map picker** for shop location — eliminates the most confusing field.
3. **Onboarding checklist** (4-step progress bar) on admin home — Shop → Category → Item → Go Live.
4. **Tooltip copy** for addon group concepts — "This is where you set your item's price and customization options."
5. **Plan the web admin launch date** — mobile-only onboarding for a restaurant with 50+ items is a churn risk.
