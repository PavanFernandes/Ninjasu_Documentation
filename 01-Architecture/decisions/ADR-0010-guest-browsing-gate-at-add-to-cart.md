---
id: ADR-0010
title: "ADR-0010: Guest Browsing (\"Skip for Now\") with Gate at Add-to-Cart (Option A)"
summary: "Chose to let guests browse the full storefront freely and gate only at the moment of add-to-cart or wishlist (Option A), avoiding a second client-side guest cart that would need merging into the real cart on login."
type: decision
status: accepted
apps: ["backend", "customer"]
module: "auth"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/config/SecurityConfig.java" }
  - { repo: customer, path: "app/_layout.tsx" }
  - { repo: customer, path: "src/features/cart/hooks/useCartMutations.ts" }
  - { repo: customer, path: "src/features/wishlist/hooks/useWishlistToggle.ts" }
  - { repo: customer, path: "src/features/location/acquireLocation.ts" }
verified_against:
  backend: ff5ade334891238d16b8010e372fdbbc502c193e
  customer: 49f04f81d4853953686a33f7e644ed7944749951
updated: 2026-06-23
---

# ADR-0010: Guest Browsing ("Skip for Now") with Gate at Add-to-Cart (Option A)

## Context

Signup needed a "Skip for now" path that lands the user on home as a guest, gating to login
only when they try to act (add to cart, wishlist, etc.). An architect pass was run first, which
surfaced two load-bearing couplings before any option could be chosen between:

- **Public storefront reads (high severity).** Only the home feed endpoint was public — every
  other read was authenticated. A guest tapping into a restaurant would hit the menu endpoint,
  get a 401, and have their auth state cleared by the fetch layer. Guest browsing was not
  possible without opening specific backend reads.
- **Cart ownership (medium severity).** The cart is server/JWT-bound — the client store mirrors
  a server-authoritative cart response, including server-computed prices. A local, unauthenticated
  guest cart would mean a second cart representation that has to be merged/replayed into the real
  cart on login, with conflict handling to match. That's ongoing drift risk for as long as the
  feature exists.

Two options were on the table for where guest browsing stops: gate the entire storefront behind
a lightweight guest identity that mirrors a cart locally, or let guests browse freely and only
gate the moment they try to mutate state (add to cart / wishlist). The team picked **Option A —
gate at Add** — specifically to avoid standing up a second, client-side cart representation.

## Decision

- **Backend:** open three GET reads to unauthenticated traffic — shop detail, shop menu, and the
  cuisines list — scoped narrowly enough that mutating endpoints and shop-owner endpoints (e.g.
  `/api/shops/my`) stay gated.
- **Frontend:** the route guard allows tokenless users into the storefront areas only (home tabs
  and restaurant detail, plus a couple of always-public utility screens); every other area still
  bounces to login. Actions inside the storefront (add to cart, wishlist toggle) each gate
  individually at the point of the action rather than at the route level.
- Signup gained a "Skip for now" link that sends the user straight to guest home instead of
  requiring OTP verification first.
- Location acquisition was extracted into a single reusable helper so it is called consistently
  from splash, post-OTP login, and the new guest-skip path — this also closed a pre-existing gap
  where a normal (non-guest) login never triggered a location request.

A pleasant find during implementation: the gate-at-add behavior already existed. The add-to-cart
mutation already redirected unauthenticated users to login before hitting the API, and the
wishlist-toggle hook already mirrored the same pattern — so Option A required no new gate logic,
only wiring the guest route access and the public reads around it.

## Consequences

**This makes easy:**
- Guests can browse the full storefront (home, restaurants, menus) with zero backend risk of a
  second cart representation to keep in sync.
- The add/wishlist gates were already in place, so the guest-browsing feature was primarily a
  routing and endpoint-visibility change, not new state-management surface.
- Location acquisition is now a single call site instead of duplicated logic per entry point.

**This makes hard / rules out:**
- Any future local "guest cart" (e.g. add-before-login with items preserved) is explicitly ruled
  out by this decision — Option A's entire value is *not* carrying cart state for unauthenticated
  users. Reversing that would mean revisiting RISK 2 from the Context above.
- Opening the three GET reads publicly means shop detail responses are now reachable without
  auth. A follow-up security review found this returns more of the shop record than a public
  caller needs (internal fields such as the owning user's id are included, alongside delivery
  fields) — severity was assessed low (the id is an opaque UUID with no attached name/email, and
  any authenticated user could already read it), but a trimmed public-facing shop DTO was flagged
  as a deferred follow-up rather than blocking this decision.

## Enforced in

- **Backend** — `SecurityConfig` permits unauthenticated `GET` on the shop-detail, shop-menu, and
  cuisines endpoints specifically, while shop-owner and mutating routes under the same paths stay
  authenticated.
- **Frontend** — the root layout's auth guard allows tokenless navigation only into the storefront
  route groups, redirecting everything else to login.
- **Frontend** — the cart-mutations hook's `add` entry point checks for a logged-in user before
  issuing any request, prompting login instead.
- **Frontend** — the wishlist-toggle hook mirrors the same check before calling the wishlist API.
- **Frontend** — the location-acquire helper is the single call site used by splash, post-login,
  and guest-skip, so guest and authenticated flows request location the same way.

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
