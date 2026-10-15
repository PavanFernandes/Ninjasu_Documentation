---
id: ""
title: "Captain Ordering mobile — permission gating, device test checklist"
summary: "Phone test plan for Food-Ninja-Frontend PR #26 (permission-based gating of the mobile POS). Expected buttons per role, edge cases, and what to do if a row fails. Not yet run."
type: how-to
status: pending-device-test
apps: [customer]
module: "pos"
anchors: []
verified_against: "Food-Ninja-Frontend PR #26 @ cec9eaa; backend main @ b428324 (PermissionTemplates)"
updated: 2026-10-08
---

# Captain Ordering mobile — device test checklist

**Status:** not run. PR #26 was reviewed three times by reading code; nothing has been executed on a phone.
Run this when a device is connected, before relying on the mobile POS in a live shop.

**Fact established 2026-10-08:** the "staff no longer settles bills" script (`db_manual/remove-staff-settle-bill.sql`)
**has been run in production**. Existing Staff roles lack `floor.settle_bill` unless a role was given it
explicitly. The mobile app now matches: Staff sees no Settle button. This is intended.

## Setup

One test shop with POS enabled, 2+ tables, a few menu items, all four payment types active. Create one
member per row below (web → Staff & Roles). Log in on the phone as each in turn, and **log out fully**
between members (the app clears POS access on logout).

## Expected result per role

Template permissions are from `PermissionTemplates.DEFAULT` (backend). Manager is the legacy admin set;
verify it rather than trust this table.

| Role | Tabs | Free table tap | Add items | Serve READY | Cancel round | Settle | Write-off | Kitchen Start/Ready | History icon | Table setup gear |
|---|---|---|---|---|---|---|---|---|---|---|
| **Owner** | Floor + Kitchen | opens | yes | yes | yes | yes | yes | yes | yes | yes |
| **Manager** | Floor + Kitchen | opens | yes | yes | yes | yes | yes | yes | yes | yes |
| **Staff** (new-shop default) | Floor only | opens | yes | yes | **no** | **no** | no | n/a | **no** | no |
| **Cashier** | Floor only | **"View only"** | **no** | yes | no | **yes** | no | n/a | no | no |
| **Chef** (new-shop default) | Kitchen only | n/a | n/a | n/a | n/a | n/a | n/a | **yes** | **no** | no |
| **Accountant** | none | n/a | n/a | n/a | n/a | n/a | n/a | n/a | **yes** | no |

- Accountant opens Captain Ordering to the **"Your role doesn't include floor or kitchen access"** message, with only the History icon.
- Cashier: no "Invite guest to order" row (needs `floor.open_table`).
- Staff on an **older-style shop** (role granted the full legacy Staff set): same as Owner minus table setup and write-off. Test one if such a shop exists.

## Edge cases

1. **Custom role with only `floor.void_bill`** (no settle): check screen footer shows **Write off** (not Settle Bill); modal opens straight to write-off; button reads Cancel, not Back.
2. **Kitchen tablet:** log in as Manager, switch to Kitchen, close the app, reopen. It should come back on **Kitchen** (remembered tab kept).
3. **Chef whose remembered tab is Floor** (from earlier use): lands on Kitchen, no Floor tab shown.
4. **Settle on two phones:** phone A opens Settle and idles; phone B settles the same table. A should show "Table already closed" and open the bill within ~20 s (poll). Then repeat but settle on A itself: **no** "already closed" alert, one navigation to the bill.
5. **Rejected payment:** on the web disable a payment type, then on the phone pick it and Confirm. Expect an error, the method list reloads (skeleton), and the disabled method is gone.
6. **No payment types:** disable all on web. Settle shows "No payment methods are turned on…"; "Check again" works.
7. **Cancel a round:** pick a reason from the list; verify the reason appears in the web Activity page (not "Cancelled by staff").
8. **Large quantity:** a line of 20+ asks for confirmation before firing.
9. **Floor tile total:** with GST on, tile total equals the check screen "Total payable" (tax-inclusive).
10. **Tax rows:** a bill with two taxable groups shows two CGST and two SGST lines, no duplicate-key warning in the Metro log.
11. **Item edit in admin with tax classes endpoint failing** (airplane-mode the call, or point to a bad URL): Save still works.
12. **Logout / login as another member** without killing the app: capabilities are the new member's, not the previous member's.
13. **Empty floor, non-manager:** shows "Ask a manager to set up tables"; manager sees "Set up tables".
14. **Old backend / no permission list** (if a staging backend predates permissions): falls back to role names; Owner/Manager/Staff/Chef behave as before.

## If a row fails

Gating lives in one place: `src/features/pos/utils/roles.ts` (`posCapabilities`) — compare with web
`Ninjasu_Web/src/features/shop/hooks/useShopRole.ts`. Backend 403s are the real boundary; a mismatch in
the UI is a missing/extra button, never a security hole.

## Known gaps (not bugs in PR #26, parity work)

Counter sale, guest-approval queue, waiter-call acknowledge, receipt printing, shop switcher, a Collect
action for ready counter-sale tickets on the mobile kitchen screen.
