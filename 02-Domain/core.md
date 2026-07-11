---
id: ""
type: domain
status: active
apps: [backend, customer, admin, rider]
module: "core"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/config/SecurityConfig.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/util/PriceCalculator.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/OrderLine.java" }
  - { repo: customer, path: "src/lib/fetchFn.ts" }
  - { repo: customer, path: "src/utils/auth.ts" }
  - { repo: customer, path: "src/store/useCartStore.ts" }
  - { repo: customer, path: "src/utils/idempotency.ts" }
verified_against: "backend@ff5ade334891238d16b8010e372fdbbc502c193e customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-07-11
---

# Core — Cross-Cutting Business Rules

Rules that apply across every module (menu, cart, orders, payments, etc.). When a feature module is silent on something, default to this file. Not backend code and not any one app's code — product rules every app (backend, customer, admin, rider) enforces.

## Rules

### API Response Envelope

Every API response follows this shape — both success and error.

**Success**
```json
{
  "status": "SUCCESS",
  "success": true,
  "message": "...",
  "data": <T>
}
```

**Error**
```json
{
  "status": "ERROR",
  "success": false,
  "message": "...",
  "data": { "field": "error message" }
}
```

- `data` on errors is a **field-error map** from backend validation. May be empty `{}` for non-validation errors.
- `message` is always present and is the human-facing summary.
- Frontend renders `data` field-by-field next to inputs; renders `message` as the toast/banner.

### Authentication

- Every authenticated request carries a **JWT Bearer token** in the `Authorization` header.
- JWT claims include at minimum: `userId`, `role`, `shopId` (if user is shop staff).
- **Ownership checks are server-side**: a user can only read or mutate resources whose owner (`userId` or `shopId`) matches their JWT claim. Frontend MUST NOT rely on hiding UI to enforce ownership.
- JWT is stored in `expo-secure-store` on mobile (NOT `AsyncStorage`) — see the frontend repo's `skills/security_review.md`.

### Identifiers

- All primary keys are **UUIDs**.
- UUIDs are **strings** on the frontend, always. Never `number`.
- Backend `entity/` uses `UUID` type; backend `dto/` serialises to JSON string.
- See [Architecture Principles](../01-Architecture/principles.md) ("Frontend ↔ Backend Type Drift Prevention") for entity-vs-DTO type alignment rules.

### Money

- All monetary amounts are stored and transported as **integer paise** (or smallest currency unit) — never floats.
- Frontend formats for display only (`₹X.XX`).
- See [menu.md](menu.md) for discount rules (override, not additive; COALESCE precedence).
- See [cart.md](cart.md) for snapshot pricing rules (price captured at add-to-cart, never recomputed at checkout).

### Discount Rule (Cross-Cutting Precedence)

```
effective_discount = COALESCE(addon.discount_percent, item.discount_percent, 0)
```

- **Override, never additive.** Discounts at a more-specific level fully replace, not stack.
- SHARED addon group options ALWAYS have `effective_discount = 0`, regardless of any field value (see [menu.md](menu.md)).
- Negative discount percentages are invalid (service-layer range check 0–100).

### Snapshot Pricing

When an item enters a cart line or order line, its price fields (`mrp`, `sellingPrice`, `discountPercent`) are **snapshotted** at that moment and never recomputed.

- Protects against menu price changes between add-to-cart and checkout.
- Protects against discount expiry between add-to-cart and checkout.
- `OrderLine` columns store the snapshot; cart store stores the snapshot per line.

### Validation Boundaries

- **Frontend validation = UX only.** Never authoritative.
- **Backend validation = authoritative.** Every business rule must be enforced server-side, even if the frontend already validated.
- Frontend re-displays backend field errors verbatim from the response `data` map (see API Response Envelope above).

### Time

- All timestamps are **UTC** in storage and transport (ISO-8601).
- Frontend displays in user's local timezone.
- Business windows (e.g. shop open hours) are stored in shop-local timezone with the IANA zone name alongside.

### Soft Delete

- Records that have history (orders, payments, audit trail) are never hard-deleted.
- Records with no downstream history (draft menu items not yet ordered) may be hard-deleted at the team's discretion.
- Decision per entity should be filed in the frontend repo's `agents/arch-notes/decisions.md`.

### Idempotency

Mutating endpoints that may be retried by the client (place order, capture payment) MUST accept an `Idempotency-Key` header and dedupe by it for at least 24 hours.

## Related decisions

- [ADR-0002: Order/OrderLine Snapshot Pricing Schema](../01-Architecture/decisions/ADR-0002-order-orderline-snapshot-pricing-schema.md) — the entity-level implementation of the Snapshot Pricing rule above.
- [ADR-0003: Order Placement Idempotency](../01-Architecture/decisions/ADR-0003-order-placement-idempotency.md) — the endpoint-level implementation of the Idempotency rule above.

## Where it's enforced

- **Backend** — Spring Security filter chain + per-controller `@PreAuthorize` (auth, ownership); global response advice (envelope shape); `PriceCalculator` (discount rule, single source of truth); `OrderLine` entity columns (snapshot pricing); service layer per endpoint (idempotency dedup).
- **Frontend** — `fetchFn` (`src/lib/fetchFn.ts`) parses the envelope, injects the Bearer token, and clears auth on 401/403; `src/utils/auth.ts` owns token storage; `useCartStore` (`src/store/useCartStore.ts`) carries the snapshot fields (`mrp`, `sellingPrice`, `discountPercent`) per line; `src/utils/idempotency.ts` generates the `Idempotency-Key` for at-risk mutations.

## How to extend this file

This file is for **cross-cutting** rules. If a rule only applies inside one feature domain, it belongs in that domain's module file ([menu.md](menu.md), [cart.md](cart.md), etc.) instead.

When adding a rule here, keep this folder's [README.md](README.md) contents table in sync.

## Cross-references

- [menu.md](menu.md), [cart.md](cart.md) — feature-specific rules
- [Architecture Principles](../01-Architecture/principles.md) — long-horizon principles, the "why" behind several rules above
- Frontend repo's `skills/self_improvement.md` → Known Traps section — historical violations of these rules
