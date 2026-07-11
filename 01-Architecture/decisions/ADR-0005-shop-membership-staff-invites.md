---
id: ADR-0005
type: decision
status: accepted
apps: ["backend", "customer"]
module: "shop-membership"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/UserShop.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/ShopInvite.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/repository/UserShopRepository.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/repository/ShopInviteRepository.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/ShopRoles.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/ShopMembershipService.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/ShopMembershipServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/ShopServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/AuthServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/config/MembershipBackfillRunner.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/config/SecurityConfig.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/controller/ShopController.java" }
  - { repo: customer, path: "src/features/admin/services/shop.service.ts" }
  - { repo: customer, path: "src/features/admin/components/ShopTeamTab.tsx" }
  - { repo: customer, path: "src/features/admin/components/ShopDetailView.tsx" }
verified_against: "ff5ade334891238d16b8010e372fdbbc502c193e"
updated: 2026-07-11
---

# ADR-0005: Shop Membership (user_shops) + Staff Invites (shop_invites)

## Context

`Shop.ownerId` (a single UUID) could not model real seller-side org structure: (a) staff — many
people operate one outlet, (b) chains — one owner, many outlets (future), (c) per-person roles,
(d) revocation, (e) audit. A restaurant has an owner plus manager plus cashiers plus kitchen
staff; they cannot all share one phone number/OTP login.

The open question was what replaces `ownerId` as the access authority, and how a second person
gets access to a shop without the platform creating an account on their behalf without consent.

## Decision

A membership table becomes the access authority — the same shape used industry-wide
(Swiggy/Zomato-style seller apps):

```
user_shops ( user_id, shop_id, role )   role ∈ {OWNER, MANAGER, STAFF}, PK(user_id, shop_id)
```

- Many staff per shop = many rows with the same `shop_id`. Each person logs in with their **own**
  OTP — no shared credentials.
- One owner, many shops = many rows with the same `user_id` (chains, future — not built yet).
- `Shop.ownerId` is kept only as a "primary owner" display field; it is no longer the authority.
  Access checks read `user_shops`, not `ownerId`.

**Two role layers, not conflated:**
- `User.roles` (`text[]`) containing `"SHOP"` is the coarse gate — `SecurityConfig.hasRole("SHOP")`
  answers "may this token touch seller endpoints at all?"
- `user_shops.role` is the fine-grained layer — "at THIS shop, is this person owner, manager, or
  staff?" — and governs action-level permissions (e.g. only OWNER/MANAGER can invite).

A staff member therefore ends up with `roles = ["USER", "SHOP"]` plus a `user_shops` row with
`role = STAFF`.

**Consent model — no account is ever created without the person's own consent, with one
deliberate exception for the owner:**

- **OWNER** — a consented exception. The account is created via admin onboarding, because that
  onboarding follows an offline business deal (out-of-band consent already given). The account
  stays `PENDING_VERIFICATION` and inert until the owner OTP-logs-in themselves, at which point it
  flips to `ACTIVE`. `createShop` inserts the `user_shops(OWNER)` row at creation time.
- **STAFF** — explicit consent via a pending invite, never an account created out from under
  someone. The owner invites by phone number, which creates a `shop_invites` row in `PENDING`
  status — **no `User` row is created at invite time.** Delivery is a WhatsApp deep link
  (`wa.me/<number>?text=...`); there is no SMS gateway budgeted for invites and the platform has no
  email capability, so email invites were not an option. The invitee installs the app and logs in
  with **their own** OTP — their `User` is created through the normal, consented signup path, and
  `verifyOtp` then consumes any `PENDING` invites matching that phone, inserting the
  `user_shops` row and adding the `"SHOP"` role.

```
shop_invites ( id, phone, shop_id, role, invited_by, status, created_at, expires_at )
    status ∈ {PENDING, ACCEPTED, EXPIRED}
```

One `PENDING` invite per `(phone, shop)`; `expires_at` guards against a stale grant being consumed
long after it was issued. Invites are **phone-keyed**, not code/deep-link-keyed — the OTP-verified
phone number itself is the credential, so there is no separate secret token to generate, store, or
leak.

## Consequences

**Makes easy:**
- Multiple people can operate one shop under their own identity/audit trail, with revocation as a
  plain row delete from `user_shops` — no shared-credential problem to solve later.
- Chains (one owner, many shops) are representable without a schema change — just more rows — even
  though the UI only supports a single shop today.
- Inviting staff costs nothing per-invite (WhatsApp deep link, no SMS gateway spend) and requires
  no email infrastructure the platform doesn't have.

**Makes hard / accepted risk:**
- `getMyShop` previously resolved via `findByOwnerId`, which would return nothing for a staff
  member (only the owner has that field set). Mitigated by reading `user_shops` (any membership)
  instead of `ownerId`; it still returns a single shop today — a multi-shop picker is deferred to
  a later phase, not built.
- "Add staff after they install" is manual and racy without a durable record. Mitigated by the
  `PENDING` `shop_invites` row plus consume-on-login: the invite is created once and completes
  automatically whenever the invitee next logs in, whether that's minutes or days later.
- A stale invite could silently grant access months later if never expired. Mitigated by
  `expires_at` (default +14 days); `verifyOtp` skips or marks `EXPIRED` invites past that point.
- Pre-existing shops had no membership rows once `ownerId` stopped being the authority. Mitigated
  by `MembershipBackfillRunner`, an idempotent `CommandLineRunner` that backfills
  `user_shops(owner_id, id, OWNER)` for every shop with a non-null `owner_id`, skipping rows that
  already exist — safe to run on every boot.

**Rules out:**
- Any access check reading `Shop.ownerId` directly to decide who can operate a shop — `ownerId` is
  display-only now; `user_shops` is the sole authority.
- Creating a `User` row for an invitee before they themselves OTP-verify — an invite is never more
  than an intention record until the invitee consents by logging in.

Tables affected: `+ user_shops`, `+ shop_invites` (additive, `ddl-auto=update` auto-creates).
Migration cost: low — additive tables, `owner_id` retained, backfill idempotent. Risk: medium —
touches the `verifyOtp` auth path, mitigated by leaving the existing owner login flow intact.

## Enforced in

- `entity/UserShop.java`, `entity/ShopInvite.java` — the two new tables.
- `repository/UserShopRepository.java` (`findByUserId`, `findByShopId`, `existsByUserIdAndShopId`),
  `repository/ShopInviteRepository.java` (`findByPhoneAndStatus`, `findByShopIdAndStatus`).
- `service/ShopRoles.java` — the `OWNER`/`MANAGER`/`STAFF` constants and role-set groupings
  (`ANY_MEMBER`, `MANAGERS_AND_ABOVE`, `OWNER_ONLY`) used across the membership/invite services.
- `service/ShopMembershipService.java` / `service/impl/ShopMembershipServiceImpl.java` — invite
  creation/cancellation, member listing/removal.
- `service/impl/ShopServiceImpl.java` — `createShop` (inserts the owner's `user_shops` row),
  `getMyShop` (reads `user_shops`, not `ownerId`).
- `service/impl/AuthServiceImpl.java` — `verifyOtp` consumes matching `PENDING` invites on login.
- `config/MembershipBackfillRunner.java` — one-time idempotent backfill for pre-existing shops.
- `config/SecurityConfig.java` — `/api/shops/*/invites/**` and `/api/shops/*/members/**` gated
  `hasRole("SHOP")`, with owner/manager-level enforcement done in the service layer.
- `controller/ShopController.java` — `POST /api/shops/{id}/invites`, `GET /invites`,
  `GET /members`, `DELETE` on both.
- `src/features/admin/services/shop.service.ts` — `inviteMember`, `getShopMembers`,
  `getPendingInvites`, `cancelInvite`, `removeMember`.
- `src/features/admin/components/ShopTeamTab.tsx` — the team-management UI, including the
  WhatsApp-deep-link invite send.
- `src/features/admin/components/ShopDetailView.tsx` — renders `ShopTeamTab` as its "team" tab.

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
