---
id: ""
title: "Schedule member audit: read-only queries before deploying shop-visible Schedule"
summary: "Two read-only checks that prove 'Schedule order = orders.group_id IS NOT NULL' on real data before the shop-visible Schedule build is deployed."
type: how-to
status: active
apps: [backend]
module: "schedule"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/service/schedule/shop/ScheduleMember.java" }
verified_against: "backend feature/schedule; both queries run read-only on 2026-11-02, 0 rows each"
updated: 2026-11-01
---

# Schedule member audit

The dispatch gates, the Eat Now board exclusion and the notification guard all treat an order as a Schedule order when `orders.group_id IS NOT NULL` (`ScheduleMember.is`). Run both queries on a Neon branch of production, or hand them to Samivan, before deploying. Read-only: no DDL, no DML. The one Neon database is production, so do not run them against it without confirming.

## Query 1: grouped orders that are not Schedule
Expect 0 rows. A row means an Eat Now order carries a `group_id` and would be wrongly hidden from the shop board and dispatch.

```sql
SELECT id, cart_type, order_type, status, group_id
FROM orders
WHERE group_id IS NOT NULL
  AND cart_type <> 'SCHEDULE';
```

## Query 2: Schedule orders without a group
Expect 0 rows. A row means a Schedule order the gates would treat as Eat Now (dispatchable, on the board, push sent).

```sql
SELECT id, cart_type, order_type, status
FROM orders
WHERE cart_type = 'SCHEDULE'
  AND group_id IS NULL;
```

## Result (2026-11-02)
Both queries returned 0 rows through the read-only database tool. The table held 94 orders, 0 with a `group_id` and 0 with `cart_type = 'SCHEDULE'`, so the check proves consistency, not behaviour at volume. Run both again after the first Schedule orders exist and before `schedule_enabled` is turned ON for a second shop.

## If a row appears
Stop and report it. Fix the data or move to a stronger discriminator before deploying; do not edit the predicate to fit the data.
