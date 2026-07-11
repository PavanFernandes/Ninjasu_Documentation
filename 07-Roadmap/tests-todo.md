---
id: ""
type: reference
status: active
apps: [backend, customer, admin, rider]
module: "roadmap"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/MenuCategoryServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/MenuItemServiceImpl.java" }
  - { repo: customer, path: "src/features/admin/components/CategoryFormModal.tsx" }
  - { repo: customer, path: "src/features/admin/components/ItemFormModal.tsx" }
  - { repo: customer, path: "app/(admin)/shop-view.tsx" }
verified_against: "backend@ff5ade334891238d16b8010e372fdbbc502c193e customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-07-11
---

# Tests Todo — Menu Category & Item Business Rules

These tests must be written to lock in the category/item business logic so it cannot silently regress.

## Where to write tests

**Backend (Spring Boot — JUnit + Mockito or `@SpringBootTest` slice tests)**

This is where the business rules actually live. Every rule below has a corresponding `throw` in a service.
Write unit tests in `MenuCategoryServiceImpl` and `MenuItemServiceImpl` — mock the repositories, test the service logic directly.
Write at least one integration test per rule using `@SpringBootTest` + a real test DB (H2 or Testcontainers) to confirm the repository queries work end-to-end.

**Frontend (Jest + React Native Testing Library)**

The frontend enforces these rules only as UX guards (filtering pickers, hiding buttons). These are secondary — if the backend test passes, the system is safe. Write frontend tests only for the picker filtering logic in `CategoryFormModal` and the FAB visibility logic in `shop-view`.

---

## Backend test cases — `MenuCategoryServiceImpl`

### createCategory

| # | Scenario | Expected |
|---|---|---|
| 1 | Create a top-level category (no parentCategoryId) | Succeeds |
| 2 | Create a sub-category under a valid parent with no items | Succeeds |
| 3 | Create a sub-category under a parent that **already has items** | Throws `BusinessRuleViolationException`: "Cannot add a sub-category to a category that already has items." |
| 4 | Create a sub-category under a parent that is itself a sub-category (depth > 1) | Throws `BusinessRuleViolationException`: "Sub-categories cannot be nested more than one level." |
| 5 | Create a sub-category with a parentCategoryId from a different shop | Throws `BusinessRuleViolationException` |
| 6 | Create a sub-category with a non-existent parentCategoryId | Throws `ResourceNotFoundException` |

### deleteCategory

| # | Scenario | Expected |
|---|---|---|
| 7 | Delete a leaf category with no items | Succeeds (soft delete) |
| 8 | Delete a category that has sub-categories | Throws `BusinessRuleViolationException` |
| 9 | Delete a category that has items | Throws `BusinessRuleViolationException` |

---

## Backend test cases — `MenuItemServiceImpl`

### createItem / reassignCategories

| # | Scenario | Expected |
|---|---|---|
| 10 | Assign item to a leaf category (no children) | Succeeds |
| 11 | Assign item to a category that **has sub-categories** (parent) | Throws `BusinessRuleViolationException`: "Items must be assigned to a sub-category, not a parent category that has children." |
| 12 | Reassign item — same rule applies to `reassignCategories` | Throws same exception if target is a parent |
| 13 | Assign item to a category from a different shop | Throws `ResourceNotFoundException` |

---

## Frontend test cases — `CategoryFormModal`

| # | Scenario | Expected |
|---|---|---|
| 14 | Parent picker renders a category that has no items | Category appears as a selectable pill |
| 15 | Parent picker renders a category that is in `categoriesWithItems` | Category is **filtered out** (not shown) |

## Frontend test cases — `shop-view` (MenuTab FAB)

| # | Scenario | Expected |
|---|---|---|
| 16 | Selected category is a leaf (no subCategories) | "Add Item" FAB is visible |
| 17 | Selected category has subCategories | "Add Item" FAB is hidden |

## Frontend test cases — `ItemFormModal` (category picker)

| # | Scenario | Expected |
|---|---|---|
| 18 | Category with subCategories | Shows parent label + sub-category chips (selectable) |
| 19 | Category with no subCategories (leaf top-level) | Shows directly as a selectable chip (no parent label above it) |
| 20 | Category that is a sub-category | Appears as selectable chip under its parent label |
