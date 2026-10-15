---
id: ADR-0020
type: decision
status: accepted
apps: [web]
module: "guest-ordering"
anchors:
  - { repo: web, path: "src/features/shop/hooks/useStaffAttentionAlerts.ts" }
  - { repo: web, path: "src/features/shop/components/pos/FloorWorkspace.tsx" }
verified_against: ""
updated: 2026-09-19
---

# ADR-0020: Detect staff-attention alerts in the web dashboard

## Context

Guest `Call staff` requests already persist as `TableCheck.attentionRequestedAt` until a floor
actor acknowledges them, but the web dashboard only showed a small pulsing badge. The requested
scope is `Ninjasu_Web` only: exact `STAFF` members need an audible/actionable alert, and the calling
table must stay above ordinary table-state priorities. A backend FCM event would also reach a
fully closed browser, but adding that event is outside this change.

## Decision

Mount one STAFF-gated attention observer in the shop layout. It reuses the existing open-check
React Query key and polling cadence, continues polling while the dashboard tab is in the
background, and produces one ring, one persistent toast, and (when already permitted) one browser
notification for each new `checkId + attentionRequestedAt` pair. Acknowledgment dismisses those
surfaces. The Floor card sorter treats outstanding attention as the highest priority, then keeps
the existing table-state and age ordering.

`OWNER`, `MANAGER`, and `CHEF` do not receive this ring. Existing order/KDS push registration is
unchanged.

## Consequences

The alert works from any shop-dashboard page and does not duplicate the Floor board's API request
when both are mounted. Browsers may block sound until the staff member has interacted with the
site, so the persistent toast is the guaranteed in-app fallback. A background tab remains covered,
subject to browser timer throttling; a fully closed browser is not covered until a future backend
push event is introduced.

## Enforced in

- `Ninjasu_Web/src/features/shop/hooks/useStaffAttentionAlerts.ts`
- `Ninjasu_Web/src/app/(shop)/layout.tsx`
- `Ninjasu_Web/src/features/shop/components/pos/FloorWorkspace.tsx`

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
