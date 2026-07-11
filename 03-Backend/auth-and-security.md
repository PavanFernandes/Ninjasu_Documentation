---
id: ""
type: reference
status: active
apps: [backend, customer]
module: "auth"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/controller/AuthController.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/AuthServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/config/SecurityConfig.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/exception/GlobalExceptionHandler.java" }
  - { repo: customer, path: "src/utils/auth.ts" }
verified_against:
  backend: ff5ade334891238d16b8010e372fdbbc502c193e
  customer: 49f04f81d4853953686a33f7e644ed7944749951
updated: 2026-07-11
---

# Auth & Security

Living record of backend security review findings for the auth surface: the Firebase OTP token
exchange and the guest-browsing public reads. Update in place as findings are fixed or new
reviews are run — this is not a changelog, it's the current state of what's been checked, what's
open, and what's accepted as a trade-off.

## Firebase OTP token exchange (reviewed 2026-06-22)

Scope: the two public auth endpoints for the pluggable Firebase OTP flow. See
[ADR-0009](../01-Architecture/decisions/ADR-0009-pluggable-otp-auth.md) for the pluggable-provider
decision this flow implements.

### `POST /auth/firebase-login`

| Check | Result |
|---|---|
| Auth required | N/A — login endpoint, public by design (no JWT yet) |
| Ownership verified | Pass — phone is read from the Firebase-**verified** token claims (`verifyIdToken` checks signature/exp/aud==our project), never from client input. Client cannot assert an arbitrary phone. |
| Input validation | Pass — `idToken` is `@NotBlank`; the token itself is cryptographically validated |
| Rate limited | Fail — none. Mitigated: brute-force happens against Firebase (6-digit code + Play Integrity + Firebase abuse limits) *before* this endpoint runs |
| Response minimal | Pass — returns only the caller's own user + JWT; no other users' data/secrets |

Specific risks:
- **[FIXED] Cross-country phone collision** — `normalizePhone` used to take the last 10 digits of
  any input, so a foreign E.164 number whose last 10 digits matched an Indian user's phone could
  log in as that user. Now requires `91XXXXXXXXXX` (or a bare 10-digit number), else throws
  `OtpValidationException`.
- **[LOW, accepted] No revocation check** — `verifyIdToken(idToken)` does not check token
  revocation. Accepted because tokens are fresh from `confirm()` and short-lived. Optional
  hardening: `verifyIdToken(idToken, true)`.

Recommended fix (open): add basic rate limiting to `/auth/**` as defense-in-depth (see the
enumeration note below — same fix covers both).

### `GET /auth/exists?phone=`

| Check | Result |
|---|---|
| Auth required | N/A — pre-login existence check, public by design |
| Ownership verified | N/A |
| Input validation | Pass **[FIXED]** — `@RequestParam` now `@Pattern ^[+]?[0-9]{10,15}$`, class is `@Validated`. A `ConstraintViolationException` handler was added to `GlobalExceptionHandler` (param/path validation used to 500, now returns 400) |
| Rate limited | Fail — none |
| Response minimal | Pass — returns only `{ exists: boolean }` |

Specific risk:
- **[MED, accepted trade-off] User enumeration** — anyone can probe which phone numbers are
  registered. Not newly introduced: `/auth/send-otp` already reveals existence via
  `UserNotFoundException` → "please signup". This endpoint just makes it an explicit GET. This is
  a conscious UX trade-off — the app intentionally routes unknown numbers to signup.

Recommended fix (**open, pre-launch**): rate-limit `/auth/**` per-IP to prevent bulk enumeration /
harvesting. Deferred — not required for the test phase. The deploy is serverless, so an in-memory
limiter is per-instance-scoped; needs a scope decision (per-IP vs per-phone, shared store) before
building.

### Verdict (2026-06-22)

Proceed. The one genuine vulnerability (phone collision) is fixed. Remaining items are
defense-in-depth (rate limiting) and a pre-existing storage concern (below) — none block shipping
the Firebase OTP flow. Recommend adding `/auth/**` rate limiting before a public launch.

## Guest browsing / public storefront reads (reviewed 2026-06-23)

Scope: the `SecurityConfig` change opening `GET /api/shops/*`, `GET /api/shops/*/menu`, and
`GET /api/cuisines` to unauthenticated guests. This is the backend half of
[ADR-0010](../01-Architecture/decisions/ADR-0010-guest-browsing-gate-at-add-to-cart.md) (guest
browsing, Option A — gate at add-to-cart).

Change: 3 GET endpoints made `permitAll` so guests can browse the storefront without a token.

| Check | Result |
|---|---|
| Scoping | Pass — GET-only; mutations (POST/PUT/DELETE) stay authenticated. `/api/shops/my` and `/api/shops/*/orders/**` match **earlier** in the security filter chain, so they stay shop-owner-gated. `/api/shops` (the bare list, no segment) stays authenticated. |
| Cart/orders/etc. | Pass — cart, wishlist, orders, addresses, delivers-to all remain JWT-gated. Add-to-cart and wishlist actions gate to login in their own hooks (`useCartMutations.add` / `useWishlistToggle`), per ADR-0010's gate-at-action pattern. |
| Data exposure | **Finding (LOW)** — `GET /api/shops/{id}` returns the full `ShopDto` to the public, including `ownerId` (internal user UUID) plus internal delivery economics (`deliveryProvider`, `deliveryRadiusKm`, raw `baseFee`/`perKmFee`) and `status` (DRAFT/ACTIVE). Severity assessed LOW: `ownerId` is an opaque UUID with no owner name/email/phone attached, and this DTO was already readable by *any authenticated user* before this change — opening the endpoint only drops the login requirement, it doesn't expose a new class of data. |

Recommended fix (**open, follow-up, not blocking**): return a trimmed public
`RestaurantDetailDto` (id, name, imageUrl, rating, cuisines, delivery time/fee, address,
isPureVeg) instead of the raw `ShopDto`. Proportionate to ship now; trim before public launch.

### Verdict (2026-06-23)

Proceed. Scoping is correct — no mutation or owner-only endpoint is exposed. The one finding
(public `ShopDto` over-exposure) is LOW severity and pre-existing to all authenticated users;
tracked as a pre-launch follow-up alongside the rate-limiting item above and the secure-storage
item below.

## Cross-cutting, open items

These are pre-existing concerns, not introduced by either review above, tracked here so they
aren't lost between reviews:

- **Unrated-limited `/auth/**`** — see both endpoints above. Needs a per-IP vs per-phone / shared
  vs per-instance store decision before building (serverless deploy makes in-memory limiting
  instance-scoped only). **Open, pre-launch.**
- **Public `ShopDto` over-exposure** — trim to a public-facing `RestaurantDetailDto`. **Open,
  follow-up, not blocking.**
- **JWT stored unencrypted in `AsyncStorage`** (`src/utils/auth.ts`, customer app) — unencrypted
  on Android. Whole-app concern, independent of either change above. Fix: migrate to
  `expo-secure-store`. **Open.**

## Related decisions

- [ADR-0009](../01-Architecture/decisions/ADR-0009-pluggable-otp-auth.md) — pluggable OTP provider
  architecture (the Firebase flow reviewed above is one provider under this design).
- [ADR-0010](../01-Architecture/decisions/ADR-0010-guest-browsing-gate-at-add-to-cart.md) — guest
  browsing, Option A (gate at add-to-cart), the decision the guest-mode review above validated.

## Where it's enforced

- `controller/AuthController.java` — `/auth/firebase-login`, `/auth/exists`, `/auth/send-otp`.
- `service/impl/AuthServiceImpl.java` — `normalizePhone` and the Firebase token verification path.
- `config/SecurityConfig.java` — the permit-all scoping for the three guest-browsing GET routes
  and the shop-owner/mutation routes that stay gated.
- `exception/GlobalExceptionHandler.java` — the `ConstraintViolationException` handler for
  request-param validation.
- `src/utils/auth.ts` (customer app) — current (unencrypted) JWT storage.
