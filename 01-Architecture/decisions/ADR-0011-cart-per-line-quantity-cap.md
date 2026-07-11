---
id: ADR-0011
type: decision
status: accepted
apps: ["backend", "customer"]
module: "cart"
anchors: []
verified_against: ""
updated: 2026-07-02
---

# ADR-0011: Cart Per-Line Quantity Cap = 25

## Context

The cart had no upper bound on line quantity: `increment` was unbounded (floor 0, no ceiling),
the backend `AddToCartRequest` validated only `@Min(1)` on `quantity`, and the `quantity` column
was a plain `Integer`. Some sane per-line ceiling was needed.

The naive fix — a `@Max(25)` constraint on the incoming request DTO — does not actually work,
because `addToCart` *combines* quantities into an existing line rather than replacing them
(`line.setQuantity(line.getQuantity() + request.getQuantity())`). A caller (or a script) that
loops `POST quantity=25` twice would stack the line to 50, sailing past any request-level cap.
The cap has to guard the **resulting** line quantity — in both the "combine into existing line"
branch of `addToCart` and in `updateQuantity` — not just the shape of a single request.

A cap on the number of distinct lines in a cart was also on the table but explicitly deferred;
this decision covers per-line quantity only.

## Decision

- Per-line quantity cap = **25**.
- Scope is **per cart line** (i.e. per unique item + addon-selection combination), not per menu
  item or per cart as a whole. Two customizations of the same item (e.g. "Large" vs "Medium")
  are two independent lines, each capped at 25 independently.
- **No** cap on the number of distinct lines in a cart (v1) — only the per-line quantity.
- The guard belongs on the *resulting* quantity, checked in both the combine branch of
  `addToCart` and in `updateQuantity`, not on the incoming request alone. The request-level
  `@Max(25)` is still worth keeping as a cheap early reject, but it is not sufficient by itself.
- The cap value is intended to live in backend config (`app.cart.max-line-qty`) rather than be
  hardcoded, so it can be tuned without a code change.
- Backend is authoritative. The frontend mirrors the same constant purely for optimistic UX
  (disabling the `+` stepper and toasting "Max 25 per item" at the cap) — the frontend copy does
  not replace the server-side guard.

**Scenarios this decision was checked against:**
- Honest user taps `+` to 25; the next tap is blocked client-side with a toast.
- Abuse: a script loops `POST quantity=25` twice; the second call must be rejected because the
  *combined* result (50) exceeds the cap — this is the reason the guard sits on the result, not
  the request.
- Same item, two customizations (e.g. Large vs Medium burger) produce two cart lines, each capped
  independently at 25.

## Consequences

**This makes easy:**
- Closes the combine-bypass loophole with a single guard placed on the *result* of both mutation
  paths, rather than trying (and failing) to enforce the cap at the request DTO alone.
- Establishes the precedent that quantity ceilings are guarded server-side against post-mutation
  state — the mechanism (not the literal number) carried forward into later cart-limit work.

**This makes hard / rules out:**
- A total-cart-quantity or total-distinct-line-count limit is explicitly out of scope for this
  decision — those remain separate, undecided policies.

**Superseded before implementation:** the same planning pass that locked this flat number of 25
later hardened it further (via a devil's-advocate pass) into a **per-item dynamic ceiling** —
untracked items fall back to a configured default of 10, while stock-tracked items cap at
remaining stock — documented in `agents/arch-notes/stock-and-cap-FINAL.md` in the source repo.
As of this migration, no code path enforces a hardcoded 25; the *mechanism* this ADR describes
(guard the combined result, not just the request) is what carried forward into that dynamic cap,
not the literal value. See the ADR for the dynamic stock-aware cap for the value actually in
force.

## Enforced in

Not enforced in code as of this migration. Verified absence: `AddToCartRequest.java` carries only
`@Min(1)` on `quantity` (no `@Max`), and the combine branch of `CartServiceImpl.addToCart`
(`line.setQuantity(line.getQuantity() + request.getQuantity())`) has no ceiling guard. No
`app.cart.max-line-qty` (or equivalent) property exists in `application.properties`. The flat-25
build order described here was overtaken by the dynamic stock-aware cap before it was built —
see that decision's own "Enforced in" for the actual anchors.

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
