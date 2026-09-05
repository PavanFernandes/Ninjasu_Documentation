---
id: ""
title: "Food Ninja — Context Keeper Onboarding Brief"
summary: "Point-in-time (2026-05-21) onboarding snapshot — what was built, tech stack, locked schema decisions, key files, and known contradictions — split into 3 parts, kept as historical orientation."
type: reference
status: active
apps: [backend, customer, admin, rider]
module: "meta"
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Food Ninja — Context Keeper Onboarding Brief

**Maintained by:** Context Keeper Agent  
**Created:** 2026-05-21  
**Last updated:** 2026-05-21  
**Source files read:** CLAUDE.md, ARCHITECTURE.md, Modules/menu.md, Modules/README.md, project_pending_flags.md, tests-todo.md, all entity classes, all CLAUDE.md files, pom.xml, package.json, store files, feature structures.

> This brief is the first thing every agent should read. It replaces the need to scan the whole project for orientation. After reading this, read only the FILE MAP section to know which additional files your specific role requires.

---

## 1. What Is Food Ninja?

Food Ninja is a **multi-vertical food/delivery platform** modelled on the Swiggy/Zomato pattern. It is in early-stage active development. Currently only the **restaurant vertical** is being built; grocery is targeted 6–12 months post-restaurant launch.

### The Three Platforms

| Platform | Status | Primary Surface | Notes |
|---|---|---|---|
| **Customer App** | In development | React Native (mobile) | Home feed, browse restaurants, cart, checkout, orders, profile |
| **Admin / Seller Panel** | In development (minimal) | React Native (mobile) `(admin)` routes | Shop CRUD, menu management, addon groups. Mobile = minimal on-the-go subset only |
| **Web Admin** | Planned (not started) | Separate web project | Full feature set for shop owners; mobile admin is a constrained subset of this |
| **Delivery** | Not started | TBD | Order lifecycle tracked; delivery provider field exists on `shops` table |

### The Funnel Mental Model
```
Discover → Browse store → Build cart → Checkout → Place order → Track → Reorder
```
The cart **becomes** the order. The order **becomes** the reorder source. This is the single most important architectural insight: cart/checkout/orders are **ONE domain**, not three separate features.

---

## 2. Tech Stack

### Backend
| Layer | Technology |
|---|---|
| Framework | Spring Boot 4.0.3 |
| Language | Java 21 |
| Database | PostgreSQL (Neon serverless) |
| ORM | Spring Data JPA / Hibernate |
| Auth | JWT (JJWT 0.12.6) via Bearer token |
| API Docs | Springdoc OpenAPI 2.8.6 (Swagger UI at `/swagger-ui/index.html`) |
| Image Storage | AWS S3 (SDK 2.25.6) |
| Validation | Spring Boot Starter Validation |
| Logging | SLF4J |
| Build | Maven |
| Boilerplate reduction | Lombok |

### Frontend
| Layer | Technology |
|---|---|
| Framework | React Native 0.81.5 |
| Build toolchain | Expo ~54.0.33 |
| Routing | Expo Router ~6.0.23 (file-based) |
| Language | TypeScript ~5.9.2 |
| State management | Zustand ^5.0.11 |
| Server state | TanStack Query (React Query) ^5.100.10 |
| HTTP client | Custom `fetchFn.ts` wrapper (single source) |
| Maps | react-native-maps 1.20.1 |
| Location | expo-location |
| Image picking | expo-image-picker |
| Animations | react-native-reanimated ~4.1.1 |
| Gestures | react-native-gesture-handler |
| Color system | `constants/brand.ts` -> `BRAND.colors` (single source of truth) |

---

This brief is split into 3 parts (each under ~400 lines) plus this index/overview (What Is Food
Ninja + Tech Stack):

| Part | Covers |
|---|---|
| [Part 1](context-keeper-brief-part1-built-and-schema.md) | §3-5 — what was built so far (by phase), the 20 architectural principles recap, and the locked schema decisions (S1-S15) |
| [Part 2](context-keeper-brief-part2-files-and-conflicts.md) | §6-8 — key backend/frontend files, the per-role file map, and the 6 known contradictions (C1-C6) |
| [Part 3](context-keeper-brief-part3-open-items-and-structure.md) | §9-11 — open questions (OQ1-OQ10), the resolved decisions log, and the project folder-structure diagram |
