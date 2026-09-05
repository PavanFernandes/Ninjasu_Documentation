---
id: ""
title: "Architectural Principles, Part 2 — Admin, Real-Time & Type Safety (Principles 8-14)"
summary: "Principles 8-14: web-primary/mobile-minimal admin split, cross-cutting concerns, error-class UX, mutation idempotency, push+polling order updates, force-update mechanism, and frontend/backend type-drift prevention."
type: reference
status: active
apps: [backend, customer, admin]
module: "architecture"
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Architectural Principles, Part 2 — Admin, Real-Time & Type Safety (Principles 8-14)

> Part of [principles.md](principles.md) — see that index for the other parts and how to use this file.

## 8. Admin Plan — Web Is Primary, Mobile Is Minimal [SHARED]

**User decision (2026-05-15):** A separate **web app** is planned for shop owners and admins (used on laptop/desktop with full feature set). The mobile app retains only a **minimal admin** surface for on-the-go use cases. Strict role-based permission enforcement on the backend is on the roadmap.

### [FRONTEND]
- Mobile `(admin)` routes keep **only the bare minimum** features a shop owner would do from a phone. New admin features default to web, not mobile.
- `(admin)` features fully isolated in `src/features/admin/`. **Zero shared business logic** with customer features.
- Admin uses its own services even if hitting the same endpoints.
- Treat the mobile admin surface as a **constrained subset** of the web admin — never the source of truth for admin functionality.

### [BACKEND]
- Admin endpoints separated by path prefix (`/api/admin/...` when needed).
- **All admin endpoints must enforce role and ownership** (see principle 15 — currently missing). This is non-negotiable before production: a `USER`-role JWT must not be able to call admin endpoints.
- Same backend serves both web admin and mobile admin — single source of truth.

---

## 9. Cross-Cutting Concerns That Are NOT Features [FRONTEND]

These flow through the whole app and must not become feature folders:

- **Cart** — global store + domain rules layer
- **User session / auth** — global store
- **Location** — global store (selected delivery address, current coords)
- **Connectivity / app state** — observed globally, screens react

**Rule:** If multiple unrelated screens read or write the same state, it is cross-cutting — not a feature. Put it in `src/store/` with rules in `src/domain/<concept>/`.

---

## 10. Error Categories Need Different UX [SHARED]

Delivery apps surface multiple error classes, each needing different handling:

| Class | Example | UX |
|---|---|---|
| Network | offline, timeout | Retry button |
| Auth | token expired, 401 | Re-login flow |
| Validation | missing field, bad format | Per-field highlight |
| Business | item out of stock, shop closed | In-context message |
| Server | 500 | Generic retry/fallback |

### [BACKEND]
`ApiResponse` envelope is consistent. Error `data` carries field-level info for validation. **Add a `code` field** to error responses for business errors (`"code": "SHOP_CLOSED"`, `"code": "ITEM_OUT_OF_STOCK"`). This is the only way the frontend can distinguish business errors deterministically.

### [FRONTEND]
`fetchFn` throws `ApiError` with `message` + `fieldErrors`. Once backend adds `code`, surface it on `ApiError`. Screens choose the right UX based on code/class — not by parsing the message string.

---

## 11. API Idempotency For Mutations [SHARED]

Users tap "Place Order" twice. Network retries duplicate a payment. This must not create two orders.

### [BACKEND]
When orders/payments are built: accept an `Idempotency-Key` header on mutating endpoints. Duplicate keys within a window return the cached response.

### [FRONTEND]
Generate a UUID per mutation attempt. Include it on retries.

Design this in when orders is built. Retrofitting is a nightmare.

---

## 12. Real-Time Order Updates — Push + Polling [SHARED]

**User decision (2026-05-15): Push notifications + polling.** No WebSocket / live map tracking.

### [BACKEND]
- Fire a push notification on every order status transition (`PLACED → ACCEPTED → PREPARING → READY → OUT_FOR_DELIVERY → DELIVERED`, plus `DECLINED`, `CANCELLED`).
- Expose `GET /api/orders/{id}` and `GET /api/orders/active` so the frontend can poll.
- Push payload carries the order id + new status — enough for the frontend to decide whether to refresh.

### [FRONTEND]
- Use **FCM (Android) + APNs (iOS)** via Expo Notifications.
- On the active-order screen: poll `/api/orders/{id}` every 10–15 seconds while the screen is foregrounded. Stop polling on blur.
- Push notification handler routes the user to the active-order screen.
- Do **not** poll when no order is active — battery cost without value.

---

## 13. App Force-Update Mechanism [SHARED]

Delivery apps need a kill switch. A bug in v1.0.3 that lets users place failing orders = revenue loss until app store approves the fix.

### [BACKEND]
A small endpoint or remote config returning: minimum supported app version, optional "soft update available" version.

### [FRONTEND]
On app launch, check version. Below minimum = blocking update screen. Above min but below latest = optional update prompt.

**Not building now.** But document the placeholder — when the first production bug hits, this is the difference between a 4-hour fix and a 4-day fix waiting on app store approval with broken code live.

---

## 14. Frontend ↔ Backend Type Drift Prevention [SHARED]

Frontend interfaces and backend DTOs diverge silently. Field renamed on backend → frontend still uses old name → no compile error → runtime bug.

- Before adding any frontend interface, check the backend DTO source (`dto/` package).
- A backend DTO field change is incomplete until the frontend interface is updated **in the same task**.
- Future: OpenAPI codegen for frontend types from backend Swagger (already exposed). Not building now.

---
