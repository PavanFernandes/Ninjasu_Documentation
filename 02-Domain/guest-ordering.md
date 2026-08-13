---
id: ""
type: domain
status: active
apps: [backend, web]
module: "guest-ordering"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/GuestSessionServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/GuestOrderServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/TableCheck.java" }
  - { repo: web, path: "src/features/guest/components/GuestOrderPage.tsx" }
  - { repo: web, path: "src/features/guest/services/guestApiClient.ts" }
  - { repo: web, path: "src/features/guest/components/CheckStatusView.tsx" }
  - { repo: web, path: "src/features/shop/components/pos/TableCard.tsx" }
  - { repo: web, path: "src/features/shop/components/pos/CheckPanel.tsx" }
verified_against: "backend@f37e43fd42a12050cd21253c7d4ebe929faa1373 web@b60fa4e3fddb20d2984f13c5af6b278f0024718e"
updated: 2026-08-05
---

# Guest QR ordering — table-session approval

A customer scans a table's QR code, lands on `Ninjasu_Web`'s `(guest)` route
(`GuestOrderPage.tsx`), and can browse/order without any phone-OTP or account login. This
supersedes the earlier per-order-OTP design (`ADR`/backlog references calling this feature
"backlog, not built" are stale — it shipped 2026-08-03).

## Mechanism

- **Approval is per-table-session, not per-order.** The first guest to scan an empty table opens
  a `TableCheck` in `guestApprovalStatus=PENDING`; staff approve/reject the whole table once
  (`GuestOrderApprovalController` → `/api/shops/{shopId}/guest-checks`, web:
  `GuestOrderRequestsQueue.tsx`). Browsing/cart-building is never blocked — only submitting an
  order is gated on approval, which hides the latency.
- **No OTP.** Phone ownership doesn't prove physical presence at the table; the trust gate is the
  one-time staff approval instead. `phone` on `GuestSession` is optional and never verified.
- **A 4-digit `guestJoinCode`** (`GuestSessionServiceImpl#generateJoinCode`) is generated per
  table-session so a second phone at the same table can attach to the already-open check
  (`POST /api/guest/join`) instead of starting a duplicate one. Not unique across tables — it's
  only ever compared against the one open check for the table it was scanned at.
- Session identity is an opaque token in the guest's browser `sessionStorage`
  (`guestApiClient.ts`, key `ninjasu_guest_session`), sent as the `X-Guest-Session` header —
  deliberately a separate axios instance from the staff client so a guest's expired session never
  gets redirected into the staff `/login` page.

## Where the join code is visible

- **Guest side:** `CheckStatusView.tsx` ("My order" tab) — always shown to anyone seated on the
  check.
- **Staff side (added 2026-08-05):** previously nowhere, despite `TableCheckResponse` already
  carrying `guestJoinCode` — staff had no way to look up and hand a customer their code back if
  lost. Now surfaced in two places, gated on `check.status === "OPEN"` (a closed check's code is
  moot):
  - `TableCard.tsx` — small pill badge on the Floor board tile, so staff can read it at a glance
    without opening the table.
  - `CheckPanel.tsx` — inline next to the covers count in the open-check detail panel (same
    component used live on Floor and, harmlessly, from the History tab — the `OPEN`-only gate
    means it never shows on a closed/historical check there).

Don't confuse the join code with the table's QR `qrToken` (`TableQrDialog` in
`TablesManager.tsx`) — the token opens a table's guest page from scratch; the join code attaches
a second device to an *already-open* session on that table. Neither substitutes for the other.

## Reconnect behavior (fixed 2026-08-05)

The guest session is persisted (`sessionStorage`, not memory-only) and `GuestOrderPage.tsx` has
explicit rehydration logic (`rehydrateQuery`) to restore it on a same-tab reload — e.g. after a
mobile browser discards and reloads a backgrounded tab (normal OS memory-pressure behavior when a
guest switches apps, such as opening phone Settings, and isn't something this app controls).

**Bug, now fixed:** the rehydrate call used to treat *any* failure — a confirmed-invalid session
(backend 403, `resolveActiveSession`'s three throw sites: bad/expired token, revoked, check
closed) **or** a one-off transient error (BFF-proxy 502 on a network hiccup, a raw connection
error while the phone's radio was reassociating) — identically: clear the token and boot the
guest back to the scan screen, losing their session and join code for no real reason.

Fixed by making `GuestOrderPage.tsx` status-aware: only a confirmed 403 clears the session now;
anything else retries (up to 2 attempts) and, if still failing, shows a "Couldn't reconnect — try
again" state with a manual retry instead of silently discarding the session.

## Known gaps (unchanged — see original DA pass)

Per `project_guest_qr_gate_redesign` (project memory, not duplicated here in full): no per-line
quantity cap on guest orders, and no floor-board "pause guest ordering" kill switch for a slammed
kitchen short of disabling `guestOrderingEnabled` shop-wide. Neither is built.
