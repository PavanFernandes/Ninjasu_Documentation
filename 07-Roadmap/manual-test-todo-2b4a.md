---
id: ""
title: "Manual test TODO — 2b.4a Eat Now GST on top, partial checkout, key safety"
summary: "Everything 2b.4a built but could not prove from code: the hand-run SQL, real-database behaviour of the tax identity and the net-sales query, COD and online checkout with GST on a device, partial checkout (ticked items only), the route-split transfer, idempotency keys for customers and staff, and the app and web screens that still have to change."
type: how-to
status: active
apps: [backend, customer-app, web]
module: "schedule"
anchors:
  - { repo: backend, path: "db_manual/order-tax-snapshot-migration.sql" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/tax/OnlineOrderQuote.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/OrderAssembler.java" }
verified_against: "backend branch feature/schedule-2b4a, uncommitted (2026-10-25); nothing below has been run on a device or a database"
updated: 2026-10-25
---

# Manual test TODO: 2b.4a (2026-10-25)

Owner: **S** = Samivan, **C** = Claude. What IS verified in code: the backend suite with the context test excluded (`./mvnw test -Dtest='!NinjaDeliveryServiceApplicationTests'`) passes, and seven deliberate code breakages were each caught by a test. Plan: `schedule-2b4-order-group-plan.md` (handoff 2b.4a). Group tests for 2b.4b onward are in `schedule-acceptance-tests.md` (T2b-16*).

**Write only against a Neon branch, never prod.** The backend's default datasource is production. Confirm the host and database with `select current_database(), current_setting('neon.endpoint_id', true);` before any write.

## A. Setup
- [ ] **S** Create a Neon branch of prod (`test-2b4a`); run the backend locally with `DB_URL`, `DB_USERNAME`, `DB_PASSWORD` pointing at the branch; confirm the host.
- [ ] **C** Test users on the branch: customer 9999999001 (dev OTP 1234), a FOOD shop with a menu and a required price group, a shop whose GST regime is UNREGISTERED and one COMPOSITION, a rider account, a shop on settlement mode ROUTE_SPLIT (hand-set `settlement_mode` and a Razorpay test linked account) if Route test mode is available.
- [ ] **C** Razorpay in test mode; test from branch `feature/schedule-2b4a`.

## B. SQL `order-tax-snapshot-migration.sql` (on the branch, one block at a time)
- [x] **S** (ran 2026-10-25, per Samivan; target database and the verify output not yet recorded here) Block 1 (columns) runs; verify 1 shows both columns NOT NULL, default 0.
- [x] **S** (ran 2026-10-25, per Samivan; verify output not yet recorded) Block 2 (preflight + `NOT VALID` check) runs with no error; verify 2 after block 3 shows `convalidated = true`.
- [ ] **S** Run the whole file a SECOND time: no error, same results.
- [ ] **C** Negative test on the branch only: insert or update an order so `grand_total <> subtotal + delivery_fee + platform_fee`, then run block 2: it must raise "existing order(s) violate the payable identity". Then fix the row and rerun.
- [ ] **C** With the check in place, `UPDATE orders SET grand_total = grand_total + 1` on one row is rejected.
- [ ] **C** Old backend build against the migrated branch (N-1): a COD order still inserts (the new columns default to 0).
- [ ] **S** Boot the new backend against a branch where the SQL was NOT run: it must refuse to start and name the missing columns and check (boot guard). Then run the SQL and boot again.

## C. Eat Now GST on top (customer app on a device, or Postman against the branch)
- [ ] **C** COD order, FOOD cart, 3 items: DB row has `tax_total` = 5% of the item subtotal (CGST + SGST halves), whole-rupee `grand_total`, `round_off` = the difference; `grand_total = subtotal + delivery_fee + platform_fee + tax_total + round_off`.
- [ ] **C** Round-off both directions: prices that give .49 and .50 after tax; a delivery fee with paise; a free-delivery order; a discounted item.
- [ ] **C** Online order (Razorpay test card/UPI): Razorpay order amount in paise = `grand_total` x 100; the checkout response shows subtotal, delivery fee, tax total and round-off that add up to `amount / 100`.
- [ ] **C** Cancel an online order after payment: the refund equals the full captured amount (tax included); `REFUND_PENDING` retry still works.
- [ ] **C** Shops with UNREGISTERED and COMPOSITION regimes are still taxed (platform-liable, section 9(5)).
- [ ] **C** A GROCERY or PRODUCT cart (if a vertical exists): totals unchanged, no tax, no round-off.
- [ ] **C** A FOOD item whose tax class is tax-inclusive or missing: checkout is refused with a clear error; the cart screen still opens and shows no tax row (the preview degrades).
- [ ] **C** Rider cash: a COD delivery assigned to a rider expects `grand_total` (tax included); completing with the exact cash raises no short-pay flag.
- [ ] **C** Cart preview shows `taxTotal` and the CGST/SGST rows for the ticked items only; with everything ticked the tax equals the order's `tax_total`.

## D. Partial checkout (ticked items only)
- [ ] **C** Untick one of three items: preview excludes it; place a COD order: the order has only the two ticked lines, subtotal, tax and commission cover only them; the cart session is ACTIVE, holds the unticked item, and its tick is true again.
- [ ] **C** Same with online payment: after pay-confirm the session is ACTIVE with the leftover item; after a dismissed payment sheet or a failed payment the session is ACTIVE with ALL items and the ticks unchanged.
- [ ] **C** Everything ticked: the session becomes COMPLETED and keeps its rows (as before); the next add-to-cart creates a fresh session.
- [ ] **C** Nothing ticked: checkout is refused with "Select at least one item to check out".
- [ ] **C** An unticked item that has become unavailable or channel-blocked does not block checkout of the ticked ones.
- [ ] **C** Stock sells out at confirm with a partial selection: order cancelled and refund pending; session ACTIVE with all items.
- [ ] **C** While the payment sheet is open (session LOCKED) changing a tick is rejected with 409 SESSION_LOCKED.
- [ ] **C** Real-database check of the completion (unit tests mock the repository): after a partial checkout the ticked `cart_items` and their `cart_item_addons` rows are really deleted, the survivors remain with `selected_for_checkout = true`, the session row is ACTIVE; after an all-ticked checkout the rows stay and the status is COMPLETED.
- [ ] **C** Edit while paying: tap Pay and, in the same second, untick or remove a line from a second device. Expect 409 or a consistent result; note anything odd. Known limit (plan follow-ups): the session row is not locked, so an edit that started just before the lock can slip in.
- [ ] **C** Webhook and verify both confirm the same online order: the cart is completed once (survivors not removed twice).

## E. Money paths
- [ ] **S/C** ROUTE_SPLIT shop (Razorpay Route test mode): the transfer to the restaurant equals `grand_total - tax_total - round_off`; a full refund reverses it.
- [ ] **C** Net sales: for one business day on the branch, `sumNetSalesForPeriod` (purchasing food-cost %) excludes tax and round-off; compare with a hand total of delivered, non-refunded orders (the query is only parse-validated in tests).
- [ ] **C** `OrderResponse` for the customer and the shop carries `taxTotal` and `roundOff`; the shop screens still have to show the item subtotal (see H).
- [ ] **C** Reports that read bills (dine-in) are unchanged: a dine-in check bill total is the same before and after.

## F. Idempotency keys
- [ ] **C** Customer COD: the same key twice returns the same order, one row. User B sending user A's key is refused with a generic message and sees no order data; the same for online checkout (a PENDING_PAYMENT order of another user is never resumed).
- [ ] **C** Staff fire KOT: the same key twice on the same check fires one KOT. The same key on a DIFFERENT check, a different shop, or after a counter sale returns 409 and fires nothing (before this fix the new KOT was silently suppressed).
- [ ] **C** Counter sale replay still works for its own key and is refused for another shop's key.
- [ ] **C** Guest table ordering is unaffected (it uses a fresh random key per fire).
- [ ] **C** Two simultaneous fire requests with one key on one check: one KOT, the second returns the first.
- [ ] **C** A customer sends a key that equals a staff KOT's key: refused with the generic message, no data. A staff request sends a key that equals a customer's order key: 400 conflict, no KOT suppressed.
- [ ] **C** Known gaps to observe and note (plan follow-ups): the same client key sent to COD checkout and to a staff fire at the same instant may return a 500 (no shared key lock yet); the same staff key with a different basket replays the first order (no request hash yet).

## G. Platform fee
- [ ] **C** `GET /api/cart` returns `platformFee` 0 and the setting `app.cart.platform-fee` is gone from `application.properties`; an order never had a platform fee.

## H2. Device checks (built 2026-10-25, type-checked only, NOT seen on a device)
- [ ] **C** Eat Now FOOD cart on a real phone: cart bill shows CGST/SGST rows (or "Taxes"), no Platform Fee row, grand total and the checkout button total match, and the "rounded to the nearest rupee" note appears.
- [ ] **C** Place an order: the Razorpay amount equals the cart total rounded to the whole rupee; order summary shows Taxes and a signed Round off row, and Total equals what was paid.
- [ ] **C** GROCERY/PRODUCT cart and an old pre-2b.4a order: no tax or round-off rows, totals unchanged.
- [ ] **W** Shop board ticket shows the item subtotal (not the customer total); order history column reads "Items total".

## H. Still to build (not testable yet; the customer app and web rows below are BUILT, see H2)
- [ ] **C** Customer app (`Food-Ninja-Frontend`): cart bill shows the tax row from `taxTotal`/`taxLines`, hides the platform-fee row when 0, stops adding the platform fee itself (`BillDetails.tsx:23`, `CartScreen.tsx:145` compute the total locally today), and shows the final payable and round-off from the checkout response; order summary shows tax and round-off.
- [ ] **C** Ninjasu_Web shop and KDS order views show the item subtotal, not the customer's total; the order ticket and board do not show tax.
- [ ] **C** Ninjasu_Rider_App needs no change for 2b.4a (cash expected still comes from the order total).

## I. Later slices (kept here so they are not lost)
- 2b.4b: `order_groups`, the two `service_area` cancel settings, `group_id` filters on the two sweep queries, the legacy-guard test matrix (TRACE-2).
- 2b.10: late-cancel and no-delivery-after-cancel matrix (T2b-16a to T2b-16s).
- Plan items still open: CA confirmation of 5% on top, GST on commission, tax on delivery and packaging fees, IGST.
