---
id: ""
title: "Context Keeper Brief, Part 3 — Open Items & Project Structure"
summary: "2026-05-21 snapshot: unresolved open questions (OQ1-OQ10), the resolved decisions log, and the full project folder-structure diagram at that time."
type: reference
status: active
apps: [backend, customer, admin, rider]
module: "meta"
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Context Keeper Brief, Part 3 — Open Items & Project Structure

> Part of [context-keeper-brief.md](context-keeper-brief.md) — a point-in-time (2026-05-21) snapshot; see that index for the other parts and the migration note on current relevance.

## 9. Open Items and Unresolved Questions

| # | Item | Source |
|---|---|---|
| OQ1 | What delivery provider will be integrated (Phase 1E)? Field exists on `shops.delivery_provider` but no value is set. | `project_pending_flags.md`, `Shop.java` |
| OQ2 | Is `useCartStore.ts` dead code or actively used? (See C1) | Scan required |
| OQ3 | Has the `/restaurant` object-passing navigation pattern been fixed? (See C3) | Scan required |
| OQ4 | When does the web admin project start? What framework? | `ARCHITECTURE.md` Principle 8 |
| OQ5 | Will push notifications (FCM/APNs) be set up during Phase 1E orders, or as a separate phase? | `ARCHITECTURE.md` Principle 12 |
| OQ6 | The `implementation_plan_md/custom_domain_mail_performance_analysis.md` doc — was this actioned? What decision was made? | `implementation_plan_md/` |
| OQ7 | `Restaurant.java` entity exists in `entity/` but appears unused (no controller references found). Is this a leftover stub or planned? | `entity/Restaurant.java` |
| OQ8 | `app/cart.tsx` at 27KB is very large for a route file. Per CLAUDE.md: route files must be thin. Was this intentional or does it need refactoring? | Frontend CLAUDE.md |
| OQ9 | No `src/domain/` folder exists yet. When will cart rules be extracted out of the store? (See C6) | Principle 1, 9 |
| OQ10 | `ARCHITECTURE.md` "Open Questions" section says "None outstanding" but the hardening items (Principle 15) and combo TODO are open. This section should be kept current. | `ARCHITECTURE.md` line 384 |

---

## 10. Resolved Decisions Log (from ARCHITECTURE.md, 2026-05-15)

| Decision | Detail |
|---|---|
| Cart model | Per-vertical: restaurant = one-shop-only; grocery = multi-shop. "One shop only" is NOT a core cart rule. |
| Grocery timeline | 6-12 months after restaurant launch. Build food concretely now. |
| Real-time orders | Push + polling (no WebSocket, no live map tracking). FCM/APNs + foreground polling every 10-15s. |
| Admin app | Web is primary, mobile is minimal subset. Backend enforces strict role/ownership. |

---

## 11. Project File Structure at a Glance

```
Food Ninja/                              <- Project root
├── ARCHITECTURE.md                      <- 20 architectural principles (read this first always)
├── CLAUDE.md                            <- Root guide: structure, coupling guard, team rules
├── Modules/
│   ├── README.md                        <- How to use Modules/
│   └── menu.md                          <- Business rules for menu (the only module so far)
├── agents/
│   └── context-keeper-brief.md          <- THIS FILE (original location — since migrated to the vault)
├── project_pending_flags.md             <- Phase checklist (done vs pending)
├── tests-todo.md                        <- 20 specified test cases (backend + frontend)
├── implementation_plan_md/
│   └── custom_domain_mail_performance_analysis.md
├── Food-Ninja-Frontend/                 <- React Native / Expo frontend
│   ├── CLAUDE.md                        <- Frontend-specific rules
│   ├── app/                             <- Expo Router routes (thin wrappers only)
│   │   ├── (admin)/                     <- Seller panel routes
│   │   ├── (auth)/                      <- Login, signup, OTP verify
│   │   ├── (onboarding)/               <- Splash
│   │   ├── (tabs)/                      <- Customer home, search, orders, profile
│   │   ├── restaurant.tsx               <- Restaurant detail entry point
│   │   ├── cart.tsx                     <- Cart modal (27KB — large for a route file)
│   │   └── select-location.tsx          <- Location modal
│   ├── src/
│   │   ├── features/
│   │   │   ├── admin/                   <- CategoryFormModal, ItemFormModal, SharedAddonsTab
│   │   │   ├── auth/
│   │   │   ├── home/
│   │   │   ├── profile/
│   │   │   └── restaurant/              <- RestaurantScreen, AddonSheet, CategorySidebar, etc.
│   │   ├── shared/                      <- Generic UI components (no feature knowledge)
│   │   ├── lib/fetchFn.ts               <- The one HTTP client
│   │   ├── store/
│   │   │   ├── useRestaurantCartStore.ts <- Active cart (addon-aware, use this)
│   │   │   ├── useCartStore.ts           <- Older store (CONFLICT with schema S1)
│   │   │   ├── useUserStore.ts
│   │   │   ├── useLocationStore.ts
│   │   │   └── useSelectedRestaurantStore.ts
│   │   └── utils/
│   └── constants/
│       ├── brand.ts                     <- Color token system (single source of truth)
│       └── config.ts                    <- API base URL
└── ninja delivery service java/         <- Spring Boot backend
    ├── CLAUDE.md                        <- Backend-specific rules
    ├── pom.xml                          <- Dependencies
    └── src/main/java/com/example/ninja/
        ├── controller/                  <- REST endpoints (12 controllers)
        ├── service/impl/                <- Business logic (8 service implementations)
        ├── repository/                  <- JPA queries
        ├── entity/                      <- DB table mappings (14 entities + 2 lookup)
        ├── dto/                         <- Request/response shapes
        ├── security/                    <- JWT filter + util
        ├── exception/                   <- GlobalExceptionHandler
        ├── config/                      <- SecurityConfig
        └── util/PriceCalculator.java    <- Authoritative price calculation utility
```

> **Note (migration):** This brief is a point-in-time snapshot (created 2026-05-21) of the Food Ninja
> project as it existed then — phase status, file sizes, and the structure diagram above describe that
> moment, not necessarily the current state. It has been moved here from `agents/context-keeper-brief.md`
> as part of the Ninjasu_Documentation vault migration. Treat the snapshot content as historical
> orientation; for current shape/status, follow the `anchors:` pattern in newer vault docs and check the
> live code/`Modules/` docs.
