# Schedule app: device checklist (Phase 5, round B2)

For Samivan, on a real Android phone with one EAS development build (it also covers the OTP SMS auto-read from PR #42). Slices 4.1 to 4.4 are merged into `feature/schedule`; none of them has been device-tested. Tick a line only after you saw it happen. Anything that fails goes into a numbered list at the bottom with the screen and what you saw.

## Before you start (needs you or Lane 1)

- [ ] A seeded service area with at least one restaurant on a Schedule menu, and a second restaurant for the two-restaurant cases. The area has `schedule_enabled` on.
- [ ] A test customer (dev phone `9999999001`, dev OTP `1234`), signed in on the phone. A second device or the web admin to change a cart from "another device".
- [ ] Razorpay: confirm whether the keys are test or live **before** the first payment (live keys charge real money).
- [ ] The late-cancel part needs `schedule.late-cancel.enabled=true` on the server and an order whose delivery time plus the grace (default 15 minutes) has passed.
- [ ] The build is made with EAS (spends credits: ask first).

## A. Mode switch and first run

- [ ] Home shows the Eat Now / Schedule toggle; tapping Schedule shows the intro once, never again after "Got it".
- [ ] Outside a Schedule area, or with Schedule off, the Schedule state says so (no menu, no crash).
- [ ] Delivery times show "Delivery around 12:30 PM", an "Order by" time and a countdown that does not freeze.

## B. Browse and add

- [ ] A plain dish: ADD, quantity stepper, the cart bar appears and totals update.
- [ ] A customisable dish opens the add-on sheet; the line keeps its choices.
- [ ] A sold-out dish is greyed with a reason and cannot be added.
- [ ] Adding for a different delivery time asks before it replaces the cart.
- [ ] Signed out: browsing works, ADD asks you to sign in.

## C. Cart

- [ ] One card per restaurant, quantity steppers and remove work; the bill shows only server numbers (subtotal, fees, tax, round-off, total).
- [ ] A changed price shows "Check new price" and no bill until you accept it.
- [ ] A closed delivery time shows the banner with "Clear cart" / "Browse times"; an address outside the area shows "Change address".

## D. Pay (the money path)

- [ ] Happy path: Pay, UPI succeeds, you land on the order with "Paid ... Your lunch is booked."
- [ ] Close the Razorpay sheet without paying: "Checking your payment" for up to 20 s, then back on the cart, cart unchanged, nothing charged.
- [ ] Price change before paying: the dialog shows the server's new total, "Back to cart" and the pay button both work.
- [ ] Remove or sell out a dish from another device, then Pay: the refusal message names it and nothing is charged. Change the cart from another device after opening the cart: "Your cart changed ... nothing has been charged."
- [ ] **Kill the app while the Razorpay sheet is open** and reopen: the prompt "You have an unfinished payment" with the hold time; Pay now resumes the same payment (no second charge); Cancel order cancels it; Not now leaves it.
- [ ] **Pay in the UPI app, then kill this app before it returns**, reopen: "Your order is placed" (or "We're confirming your payment") with View order, and it appears only once.
- [ ] The Android back button does nothing while "Checking your payment" is showing.
- [ ] Record: how long the Razorpay sheet really stays open before it closes itself (the `timeout` behaviour on Android).

## E. Order screen: cancel and late cancel

- [ ] While cancellable the "Need to cancel?" card shows with "Until hh:mm AM/PM" in the delivery area's time, not the phone's: change the phone's time zone and check the deadline does not move.
- [ ] Cancel lunch: confirm dialog (no amount), then "Lunch cancelled", each restaurant "Cancelled", a Refunds card with the server's amount and status. No "money has arrived" wording.
- [ ] With the card gone after the window closes (server decides, not the phone clock): set the phone clock ahead and back, the card follows the server only.
- [ ] Late cancel (flag on, after delivery time plus grace): the per-restaurant button shows only on orders not yet delivered; confirm says the order has not arrived yet; after it, that order shows Cancelled with a refund row.
- [ ] While one cancel runs every cancel button is dimmed and says "Cancelling..." only on the active one. With the font scale at 1.5x the buttons stay at least 48 dp tall and a long restaurant name wraps instead of clipping.

## F. Eat Now still works

- [ ] Toggle back to Eat Now: its cart is unchanged by anything you did in Schedule; order and pay one Eat Now order end to end.
- [ ] Sign out and sign in as someone else: no Schedule cart, no stored payment prompt from the first account.

## Result

Failures (screen, what you saw):

1.
