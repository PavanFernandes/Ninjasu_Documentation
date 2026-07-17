---
id: ADR-0016
type: decision
status: accepted
apps: [backend, web, rider, customer]
module: architecture
anchors: []
verified_against: ""
updated: 2026-07-17
---

# ADR-0016: Multi-client backend — code by domain, API surface by audience

## Context

One Spring backend now serves 3+ clients: the customer mobile app (`Food-Ninja-Frontend`), the
rider app (`Ninjasu_Rider_App`), and the web app (`Ninjasu_Web`, itself spanning Ninjasu-team admin
+ shop/restaurant dashboard + later guest QR-ordering). The question this ADR settles: how is the
backend organized so these clients don't tangle into an unmaintainable mess as endpoints pile on?

The tempting-but-wrong answer is to split code **by client** (a customer module, a rider module, an
admin module). That duplicates the same domain logic across modules and it drifts — directly
violating principle 14 ("business logic in two places = drift") and the backend coupling guard. It
also can't model reality: a rider marking an order `DELIVERED` and a customer viewing that order's
status act on the **same** Order aggregate. Clients cannot own separate copies of it.

## Decision

**Two independent axes. Code is organized by DOMAIN; the API surface is split by AUDIENCE.**

1. **Code by domain — one service per aggregate is the single source of truth.**
   `OrderService`, `MenuService`, `ShopService`, `DeliveryService` — exactly one of each. All clients
   call into them. The service layer is **audience-agnostic**: methods are parameterized by *domain*
   identity (`getOrdersForShop(shopId)`, `getOrdersForRider(riderId)`), never by audience. **Ban:** any
   `audience`/`role` enum in a service signature — that is the tell that audience awareness has leaked
   into the domain layer.

2. **API surface by audience — thin adapter controllers with path prefixes.**
   The same domain service is exposed through per-client adapters, each enforcing that audience's
   auth/role/ownership and returning that audience's DTO:

   | Audience | Prefix | Controller | Auth |
   |---|---|---|---|
   | Customer app | `/api/...` | `OrderController` | USER |
   | Rider app | `/api/rider/...` | `RiderOrderController` | RIDER |
   | Web admin | `/api/admin/...` | `AdminOrderController` | ADMIN |
   | Web shop / POS | `/api/pos/...` | `PosOrderController` | shop membership |

   The path prefix makes "what is this API for" readable at a glance. The **DTO** is where audiences
   diverge and is a **security boundary**, not just tidiness: `AdminShopDto` (verification docs, owner
   PII, internal status) must never leak onto a public endpoint that should return `ShopDto`.

3. **Adopt as a convention now — not a package refactor.** The current flat layer layout
   (`controller/`, `service/`, `dto/`) stays. New controllers follow the audience-prefix + `Admin*`/
   `Rider*` naming; DTOs diverge per audience; role/ownership is enforced per prefix. A package-by-
   feature (modular-monolith) migration is deferred until the flat layout actually hurts.

## Consequences

Sound, but it carries five guardrails (from the pre-build devil's-advocate pass, 2026-07-17) — all
mandatory, all cheap now and expensive to retrofit:

1. **Order status race** (rider vs customer writing the same Order): add `@Version` optimistic lock +
   one `OrderStatusService.transition()` owning the legal-transition table. No controller mutates
   `order.status` directly. (Same family as the POS `recordPayment` second-writer trap.)
2. **Services stay audience-agnostic:** no `audience`/`role` params in service signatures.
3. **DTO leak:** admin DTOs in a `dto/admin/` package + an ArchUnit/reflection CI test asserting no
   non-`/api/admin` controller references `dto.admin`.
4. **Role ≠ ownership** (principle 15, currently missing — production blocker): SecurityConfig prefix =
   coarse role gate; PLUS a reusable method-layer ownership guard (`assertMember(userId, shopId)` /
   `@PreAuthorize`) on every shop/rider-scoped op. Designed once before the first admin/shop endpoint
   ships — not re-remembered per controller.
5. **Cross-shop admin queries** need their own composite indexes with a unique tiebreaker
   (e.g. `(status, created_at, id)`) — per-shop indexes don't cover platform-wide oversight lists.

## Enforced in

Principles §8 (admin `/api/admin/...` prefix + role/ownership), §14 (single source of truth), §15
(role/ownership enforcement — the home for guardrail #4). Existing analog:
[[ADR-0006-shop-role-app-area]] (the in-mobile seller area this web dashboard extends),
[[ADR-0012-captain-ordering-dine-in-pos-kds]] (`/api/pos/...` already follows this shape). Web stack
that sits on this boundary: [[ADR-0017-ninjasu-web-stack-and-auth]]. Memory:
`project_multi_client_backend`, `project_rider_app_plan`.

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
