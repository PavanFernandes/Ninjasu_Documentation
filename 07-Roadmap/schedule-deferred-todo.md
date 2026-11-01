---
id: ""
title: "Schedule: deferred TODO (gaps after the first cut)"
summary: "Work deliberately deferred by Samivan on 2026-10-30 so the first Schedule cut ships small; each item names why it matters and where its design lives."
type: how-to
status: active
apps: [backend, web, customer]
module: "schedule"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/service/schedule/cancel/ScheduleCancelServiceImpl.java" }
verified_against: "backend feature/schedule 156fbc9; nothing below is built"
updated: 2026-10-30
---

# Schedule: deferred TODO

Deferred on 2026-10-30 (Samivan: "lets get the first cut of this schedule thing, later we can cover the gaps"). Design and findings: [schedule-shop-visible-slice-plan.md](schedule-shop-visible-slice-plan.md) PRs 4 to 6 and the "Second pass" in [schedule-2b8-2b10-plan.md](schedule-2b8-2b10-plan.md).

- [ ] **STATE-4 bulk slot delivery.** Admin or shop bulk-marks a slot's READY orders OUT_FOR_DELIVERY then DELIVERED. Without it Schedule orders stall at READY (no per-order dispatch), the customer never sees delivered, and 2c settlement inputs keyed on DELIVERED never fire. Build with the bulk dispatch flow (Samivan will say when). Needs CAS per member, all-or-nothing per shop, audit rows.
- [ ] **Whole-group cancel on partial fulfilment (STATE-3, STATE-5).** When one shop declines, offer the customer "cancel the whole group", behind an on/off switch (default ON, location decided in that PR's `/gcp`). A DECLINED member must keep its status and never be cancelled or refunded twice (`cancelGroup` transitions every member today). Accepted-member cancel only before READY; restaurant unpaid unless the contract says otherwise (add a row to `02-Domain/restaurant-schedule-terms.md`). Today the first-cut rule stays: any non SCHEDULED/PLACED member blocks whole-group cancel.
- [ ] **Customer group history and tracking (PR 5).** History and active-order reads exclude every group member; a customer cannot find a past group or see the new statuses. Needed before the pilot.
- [ ] **Admin unaccepted-orders list (PR 6, TIME-1).** Admin watches unaccepted Schedule orders and can manually decline (decline already exists and refunds). The list view is missing; until then the admin finds them through existing admin reads.
- [ ] **Accept deadline or alert (TIME-1).** Nothing handles a paid order nobody accepts; revisit in 2d.
- [ ] **Socket push for the tab badge (API-1).** First cut refetches on focus plus a slow interval; a socket needs in-process fan-out that breaks past one backend instance. Revisit with 2d notifications.
- [ ] **Tab query index (PERF-1).** `EXPLAIN ANALYZE` on a branch with sample data before adding any index.
- [ ] **Unverified readers (Codex gap).** Every POS and KDS reader, invoice path, scheduled job scanning READY orders, every status writer and historical rows; PR 1's audit and `/judge deep` cover them.
- [ ] **2b.11 release job** stays parked until tomorrow-ordering exists; lifting `SCHEDULE_SAME_DAY_ONLY` in `ServiceAreaValidator` reopens the shop-visible decision.
- [ ] **Per-slot prep ticket (original phase 5).** "12:30: 14 biryani, 6 thali" with one accept and one ready per slot and live per-dish counts; the first cut lists orders by slot and the shop accepts and readies order by order. Needs the 2d ticket work.
- [ ] **Shop terminal-status view (judge F1, 2026-11-01).** The Schedule tab lists only SCHEDULED, ACCEPTED and READY and the ordinary board excludes every group member, so a shop cannot reopen a DECLINED or CANCELLED member for a refund or dispute conversation. Trigger: before `schedule_enabled` is turned ON for any shop; add a `history` filter with a date range to `ScheduleShopOrderService.list`.
- [ ] **Schedule tab indexes (judge F2).** `idx_orders_schedule_shop_status ON orders (shop_id, status, group_id) WHERE group_id IS NOT NULL` and `idx_order_groups_service_date ON order_groups (service_date, slot_id)`, then `EXPLAIN (ANALYZE, BUFFERS)` on a branch copy. DO NOT RUN NOW; trigger: before `schedule_enabled` is ON.
- [ ] **Real-database tests for the Schedule tab (judge F18).** DataJpaTest on a Postgres container: two shops, two dates, mixed statuses, plus a two-thread READY versus cancel race. Trigger: a safe test database exists (not Neon production), and before `schedule_enabled` is ON.
- [ ] **Judge follow-ups, schedule when next touched.** F3 move the Schedule guard in `DeliveryDispatchListener` ahead of the shop and rider lookups; F8 extract `lockedMember` and give `audit()` an action parameter in `ScheduleCancelServiceImpl`; F10 name `ScheduleShopOrderService` a read model (done in its Javadoc) and revisit its five repositories when the shop, slot or service-area tables change; F11 carry a Schedule flag on `OrderPlacedEvent` / `OrderStatusChangedEvent` instead of the extra order read in `OrderNotificationListener`; F12 move Schedule controllers and repositories into `controller/schedule` and `repository/schedule` the next time one is added.
