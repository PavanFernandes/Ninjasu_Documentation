---
id: ""
title: "Food Ninja — Business Scale Concerns"
summary: "Rates each open technical conflict and hardening gap (OTP, DB credentials, ownership checks, JWT secret, ddl-auto, rate limiting) by business impact rather than technical complexity."
type: reference
status: active
apps: [backend, customer, admin]
module: "roadmap"
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Food Ninja — Business Scale Concerns

**Document type:** GTM — Scale Check
**Author:** GTM Agent
**Date:** 2026-05-21
**Source:** Context Keeper C1–C6 + [Architectural Principles](../01-Architecture/principles.md) 13, 17, 18, 19, 20

> This document rates each technical conflict for **business impact** — not technical complexity. The question is: what does this cost us in revenue, trust, or growth if it ships as-is?

---

## Conflict Business Impact Ratings

### C5 — Production Hardening Items (All 6 Open) | Business Impact: 🔴 EXISTENTIAL

> **This is the most important section in this document. Read it first.**

All six hardening items from Principle 15 are unresolved. From a sales and business perspective, each carries a distinct threat:

---

#### C5a — OTP Hardcoded to "1234"

**What this means in plain English:**
Anyone who knows the OTP is `1234` can "verify" any phone number in India. They don't need access to the target's phone.

**Business impact if shipped:**
- A competitor, a bad actor, or a curious tester can create accounts on behalf of restaurant owners or customers without consent
- Fraudulent orders placed with hijacked accounts → chargebacks, lost revenue, support burden
- **Regulatory risk:** India's IT Act and DPDP (Digital Personal Data Protection) Act 2023 require reasonable security measures. Hardcoded OTPs are a demonstrable failure of due care.
- If a restaurant owner's account is hijacked and their menu is altered or their earnings are accessed, **they will go to the press, not customer support.**

**What we tell a restaurant owner if this ships and is exploited:**
We cannot. There is no good answer. This is a liability issue, not a UX issue.

**Fix before launch: YES — non-negotiable.**

---

#### C5b — DB Credentials in `application.properties` (Plaintext, in Git)

**What this means in plain English:**
The database username and password for the production Neon PostgreSQL database are stored in a config file that is almost certainly committed to the git repository. Anyone with repository access — current or former — can read the entire database: all shop data, all user phone numbers, all order history.

**Business impact if shipped:**
- **Full data breach.** Every restaurant owner's menu, contact info. Every customer's phone number and order history.
- Under DPDP Act 2023, a breach involving personal data (phone numbers constitute personal data) requires notification to the Data Protection Board of India.
- Public breach = press coverage = zero new restaurant signups.
- Even if credentials are rotated now, the git history retains them unless explicitly scrubbed.

**What we tell a restaurant owner whose data is exposed:**
- "Your customers' phone numbers were accessible due to a configuration error."
- The resulting trust damage cannot be un-done by a feature update.

**Fix before launch: YES — plus scrub git history. Immediate action required.**

---

#### C5c — No Shop Ownership Enforcement

**What this means in plain English:**
Any logged-in user with a valid JWT can call `PUT /api/shops/{any-shopId}` and edit **any restaurant's menu, prices, or shop details** — including a competitor's shop. The API does not check that the user making the request is the owner of the shop being modified.

**Business impact if shipped:**
- A restaurant owner using Food Ninja can edit a competitor's menu — change their prices, mark items unavailable, alter descriptions
- A customer (not a restaurant owner) can edit any shop's data
- A disgruntled ex-employee with a valid JWT can destroy any shop's menu
- **This directly threatens marketplace integrity** — the foundational trust between the platform and its restaurant partners

**What we tell a restaurant owner if a competitor edits their menu:**
We cannot tell them this is a backend architecture issue. They will leave the platform immediately and tell every other restaurant owner they know.

**Fix before launch: YES — `@PreAuthorize` or in-service ownership check on every admin endpoint.**

---

#### C5d — JWT Secret is Default Base64

**What this means in plain English:**
The JWT secret used to sign authentication tokens is a known default value. If an attacker knows (or guesses) this secret, they can forge valid JWTs for any user, including admins.

**Business impact if shipped:**
- Any attacker who identifies the default secret can impersonate any user on the platform
- Combined with C5c (no ownership checks), this means they can edit any shop's data as a forged admin
- **Full platform compromise** from a single piece of knowledge

**Fix before launch: YES.**

---

#### C5e — `ddl-auto=update` in Production

**What this means in plain English:**
The backend is configured to auto-apply database schema changes on startup. In production, a bad migration or a code change could silently alter or drop tables.

**Business impact if shipped:**
- A bad deploy could corrupt or destroy the menu, order, or user database
- **Data loss risk.** No migration history = no audit trail = no rollback.
- If this happens after 50 restaurants have onboarded, recovery is catastrophic for trust

**Fix before launch: YES — Flyway/Liquibase migrations.**

---

#### C5f — No Rate Limiting on `/auth/send-otp`

**What this means in plain English:**
The OTP endpoint accepts unlimited requests. An attacker can send millions of OTP SMS messages from our account to any phone number.

**Business impact if shipped:**
- **Direct financial cost:** SMS providers charge per message. An attack could generate thousands of dollars in unexpected bills in hours.
- Targeted harassment: attacker spams a competitor's phone number with OTPs, making it unusable
- SMS provider may blacklist our sender ID, making OTP delivery unreliable for legitimate users

**Fix before launch: YES — rate limit per phone number (e.g. 3 OTPs per 15 minutes).**

---

### C1 — Two Cart Stores Coexisting | Business Impact: 🟡 HIGH

**Plain English:** There are two cart implementations. The old one (`useCartStore.ts`) uses a price field that doesn't exist in the database. If it's still in use anywhere, customers see wrong prices.

**Business impact:**
- Wrong prices displayed to customers → wrong prices charged → customer disputes
- Restaurant owners see correct prices on their end; customers see different prices → platform trust collapse
- Hard to diagnose: looks like a "display bug" but is actually a data model violation

**Resolution urgency:** Determine if `useCartStore.ts` is still active. If yes, every customer-facing price is wrong. This is a revenue integrity issue.

**Business impact rating:** 🟡 HIGH — potentially 🔴 if old store is in active use.

---

### C2 — Hardcoded Promo Data on Home Screen | Business Impact: 🟠 MEDIUM

**Plain English:** The promotional carousel on the home screen shows hardcoded slides — the same ones forever, regardless of what deals or restaurants we want to highlight.

**Business impact:**
- Cannot run promotional campaigns without a code deploy and app update
- Cannot highlight new restaurant partners or feature deals for seasonal events
- **Revenue model impact:** If Food Ninja's revenue includes promoted listings (standard for Swiggy/Zomato), this feature cannot be monetized until the home screen is API-driven
- App store approval delays mean a campaign planned for Diwali misses by 2 weeks

**Resolution urgency:** Must be API-driven before launch if we plan any promotional revenue stream.

---

### C3 — Navigation Passes Objects (Not IDs) | Business Impact: 🟢 LOW (now) / 🟡 MEDIUM (at scale)

**Plain English:** When a customer taps a restaurant, the app passes the entire restaurant object as URL parameters instead of just the restaurant ID.

**Business impact now:**
- Deep-linking to a specific restaurant doesn't work reliably
- Push notification "Tap to view your order's restaurant" cannot link to a restaurant screen correctly
- Analytics tracking of restaurant views is unreliable

**Business impact at scale:**
- Every share link for a restaurant ("Share this restaurant") is broken
- Partner restaurant links for social media campaigns don't work

**Resolution urgency:** Medium — fix before any marketing campaign involving restaurant-specific links.

---

### C4 — DeliveryConfig JPA Coupling | Business Impact: 🟢 LOW

**Plain English:** One database relationship is structured differently from all others, creating a tight technical dependency.

**Business impact:** Minimal in isolation. If delivery config management becomes a frequent operation (dynamic per-order delivery fees, surge pricing, etc.), this coupling could slow down feature development. No immediate revenue impact.

**Resolution urgency:** Low — address when delivery config functionality is extended.

---

### C6 — Cart Domain Rules in Store (Not Domain Layer) | Business Impact: 🟢 LOW (now)

**Plain English:** The "one restaurant per cart" rule is baked into the cart storage layer instead of a separate rules layer. When grocery launches, this becomes a problem.

**Business impact:**
- Low now — restaurant-only is acceptable
- High when grocery launches in 6–12 months: if this isn't refactored first, the grocery cart will be built on a broken foundation
- Grocery launch delay = 6–12 months of missed grocery revenue

**Resolution urgency:** Plan the refactor as part of Phase 1E (orders), not as a last-minute grocery pre-launch scramble.

---

## Summary Table — Business Impact by Conflict

| Conflict | Description | Business Impact | Fix Before Launch? |
|---|---|---|---|
| C5a | OTP hardcoded | 🔴 Existential | ✅ Yes |
| C5b | DB credentials in plaintext | 🔴 Existential | ✅ Yes + git scrub |
| C5c | No shop ownership enforcement | 🔴 Existential | ✅ Yes |
| C5d | Default JWT secret | 🔴 Existential | ✅ Yes |
| C5e | ddl-auto=update | 🔴 Existential | ✅ Yes |
| C5f | No OTP rate limiting | 🔴 High cost risk | ✅ Yes |
| C1 | Two cart stores | 🟡 High (if old store active) | ✅ Audit immediately |
| C2 | Hardcoded promos | 🟠 Medium | ⚠️ Before revenue campaigns |
| C3 | Navigation objects | 🟢 Low → 🟡 Medium | ⚠️ Before marketing links |
| C4 | DeliveryConfig coupling | 🟢 Low | ❌ Not blocking |
| C6 | Cart rules in store | 🟢 Low → 🟡 Medium | ⚠️ Before grocery launch |

---

## Scale Considerations Beyond the Conflicts

### Principle 13 — No App Force-Update Mechanism
**Business impact:** When a critical production bug ships (and one will), the only remedy is a hotfix + app store submission (2–7 day approval wait). During this window, the bug is live for all users. For a delivery app, a pricing bug or checkout failure for even 48 hours is significant revenue loss. **This must be on the roadmap for v1.1.**

### Principle 17 — Availability as Backend Decision
**Business impact (positive):** This principle is correctly designed. Kitchen hours, delivery range, item stock are all backend-controlled. This means restaurants can toggle availability without an app update, and customers always see current state. **This is a selling point — emphasize in demos.**

### Principle 18 — Orders as Future Cart Sources
**Business impact:** Reorder is one of the highest-value features for retention in delivery apps (Swiggy's "reorder in 2 taps" drives massive repeat revenue). The architecture is designed to support this — order snapshots are required. **Sell this as a retention driver in partner pitches:** "Your regulars can reorder their usual in 2 taps."

### Principle 20 — Early Stage Architecture
**Business impact (positive):** The team is correctly avoiding premature complexity. This keeps development velocity high. The risk is that growth-stage decisions (feature flags, observability, role/permission enforcement) get deferred too long. Permission enforcement (C5c) is the critical one that cannot wait.

---

## Investor / Partner Talking Points on Scale

**Do say:**
- "We've designed for multi-vertical from day one — grocery is 6–12 months out and the architecture is already prepared."
- "Real-time order updates are push-first, no WebSocket infrastructure cost."
- "Backend availability decisions mean restaurants can manage their menu in real-time without app updates."
- "Reorder architecture is designed in — order history doubles as a retention engine."

**Don't say (yet):**
- "Our platform is fully secure" — it isn't until C5 is resolved
- "Onboarding takes 20 minutes" — it doesn't yet
- "Our admin panel has full feature set" — web admin isn't built
