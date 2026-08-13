# Dispatch Visibility — plan

Status: **PLAN / not started.** Written 2026-08-13.
Trigger: a live test where a rider logged in on a new phone, staff marched the order through every
stage, and no notification ever arrived — with no surface anywhere explaining why, or even at what
stage one was supposed to fire.

Related: [[project_rider_dispatch_plan]], [[project_rider_assign_notification_plan]],
`Ninjasu_Documentation/06-Rider-App/rider-dispatch-phase3-plan.md`.

---

## 1. What actually happened — two independent causes, both live

### Cause 1 — the shop cannot broadcast at all (CONFIRMED against production)

| Check | Result |
|---|---|
| Shop "Masala" (`4e929671-…`) `dispatchMode` | **`MANUAL`** — via `GET /api/shops/{id}` |
| Rider "Sami" online? | **Yes** — via `GET /api/shops/{id}/riders/online` |

`DeliveryDispatchListener.java:59-66` returns early unless `dispatchMode == "BROADCAST"`.
**On this shop the broadcast push is structurally impossible.** Walking an order
`PLACED → ACCEPTED → PREPARING → READY` will never notify anyone, regardless of how many riders are
online, how correct the app is, or how many phones are logged in.

The trap is sharper than "it was misconfigured": the web app was showing **"1 rider online"** the
whole time. That indicator reads as dispatch health but has no relationship to whether a broadcast
can or did fire — the exact riders-online-vs-nobody-notified ambiguity flagged as a top unresolved
risk in [[project_rider_dispatch_plan]] §9, now observed for real.

**And branch 2 logs nothing at all** (see §3) — so this cause is invisible even in server logs.

### Cause 2 — a new phone may never register a push token, silently

Independent of Cause 1, and it would equally kill the **manual-assign** `DELIVERY_ASSIGNED` push.
The entire registration flow is 20 lines (`usePushRegistration.ts:36-55`) and has **six silent
failure paths**, every one invisible to both the rider and the backend:

1. `ready` (`useAppReadyStore`) never set → effect never runs (`usePushRegistration.ts:38`).
   `app/index.tsx:36-38` still carries a stale comment saying no push hook exists — that file does
   not know it is now the sole enabler of registration.
2. **Notification permission denied → `usePushRegistration.ts:44` returns silently.** No state, no
   toast, no settings prompt. This returns *before* `getFcmToken()`, so a denied rider **never POSTs
   a token at all** — server-side they are indistinguishable from someone who never installed the
   app. Android stops showing the dialog after two denials, permanently.
3. `getToken()` throws → bare `catch { return null }` with **no logging** (`pushSetup.ts:75-81`) →
   silent return at `usePushRegistration.ts:46`.
4. `POST /api/devices` fails (5xx, timeout, offline) → **empty catch**, no retry, no backoff, no
   queue (`usePushRegistration.ts:49-53`). `registeredRef` is set `true` *before* the async work
   (`:23,39`), making it an **"attempted once per process" latch, not "succeeded once"** — so one
   bad moment right after first login means silence until a full app kill, not just a background/resume.
5. **No `onTokenRefresh` handler exists anywhere.** If FCM rotates the token mid-session the backend
   keeps the dead one until the next cold start.
6. Logout never calls `DELETE /api/devices` (the endpoint exists, `DeviceController.java:34-41`, but
   is never called) → a stale token stays pointed at the previous user.

Worse, the home screen **actively lies**: `app/(rider)/home.tsx:139-150` shows a green
*"You're online — shops can assign you deliveries"* even when notifications are denied and no token
was ever registered. There is **no settings, profile, or debug screen anywhere in the app** — zero
notification/token health UI.

On a fresh install the permission dialog appears unprimed, on the home screen, right after OTP, and
races with `acquireLocation()` on the same startup (`app/index.tsx:33`). The `useAppReadyStore`
comment (`:5-9`) exists precisely because Android silently drops a concurrent second dialog and
**its promise never resolves** — if that ever races, `await requestPushPermission()` hangs forever.

---

## 2. The root problem

Dispatch is **fire-and-forget with zero persistence and zero surfacing.** Six independent gates can
each swallow the notification, and every one produces the *same* externally visible outcome — an
order sitting at READY, silence:

1. `dispatchMode != BROADCAST` → skip ← **this one, confirmed**
2. `orderType != DELIVERY` / status not READY → skip
3. Shop not platform-dispatched → never in scope
4. `resolveDispatchRiders` empty (offline / not `ACTIVE` / not in a covering zone / `deliveryMode = NONE`) — **note this is the NARROW pool, not the wide one behind the "N riders online" badge**
5. No `device_tokens` rows for eligible riders ← **Cause 2 lands here**
6. FCM send fails, or the device drops it (permission, unregistered channel, stale token)

Gate 6 has further teeth: per [[project_rider_assign_notification_plan]] the notification-channel
fix is merged but **not in any distributed build** (no OTA), so a freshly installed app is a suspect
for its own separate reason.

Two notifications exist and fire at completely different moments — itself part of why "which stage?"
is unanswerable today:

| Notification | Fires on | Gate |
|---|---|---|
| Broadcast offer (`DeliveryDispatchListener:53-116`) | order `PREPARING → READY` | BROADCAST shops + DELIVERY orders only |
| `DELIVERY_ASSIGNED` (`DeliveryRiderNotificationListener:60-71`) | a `deliveries` row created by staff assign/reassign | not a status transition at all |

The broadcast deliberately writes **no** `deliveries` row, so `DeliveryTimelineDialog` — the only
delivery-visibility surface that exists — has nothing to render until a rider accepts.
`getDeliveryForOrder` returns `null` for a READY-but-unclaimed order (`delivery.service.ts:49-57`).

---

## 3. What the server logs can and cannot tell you today

| Branch | Lines | Log |
|---|---|---|
| not READY / not DELIVERY | `:55-57` | **nothing** |
| not BROADCAST mode | `:59-66` | **nothing** ← the confirmed cause is untraceable |
| no eligible online riders | `:68-74` | INFO |
| eligible riders have no device tokens | `:76-83` | INFO ← Cause 2 surfaces here, indistinguishable from "never installed" |
| order not found | `:85-89` | WARN |
| success | `:111-112` | INFO, with counts only |

Two hard problems beyond the missing branches:

- **`"broadcast sent"` is logged unconditionally at `:111` even when every single push failed.**
  `pushSender.send(...)` is `void` and never throws (`FcmPushSender.java:71-72` swallows everything),
  so the listener cannot distinguish a delivered broadcast from a total FCM outage.
- Per-token outcomes exist only inside `FcmPushSender` (`:167,:172,:175`) and carry **no orderId,
  shopId, userId or token** — they cannot be correlated to a dispatch. A rider-specific
  non-delivery is untraceable by construction.
- Config hazard: if `app.firebase.enabled` is ever false, `LoggingPushSender` takes over, sends
  nothing, and `:111` **still logs "broadcast sent"**.

---

## 4. Design principle

> **Every silent gate becomes a visible state on the order — on the surface, not behind a click.**

`OrderDeliveryButton` today is click-to-open. That is exactly the failure mode: nobody knew there
was anything to look at. State goes on the ticket; detail goes behind the click.

### The dispatch state to expose

Derived for every DELIVERY order — one state per early-return branch:

| State | Meaning | Staff action |
|---|---|---|
| `AWAITING_READY` | will broadcast when marked ready | — (this is the "at what stage" answer, inline) |
| `MANUAL_MODE` | this shop never auto-notifies | Assign a rider |
| `BROADCAST_SENT` | n riders notified at HH:MM, waiting | wait / re-broadcast |
| `NO_ELIGIBLE_RIDERS` | fired, reached nobody | loud — call someone |
| `PUSH_FAILED` | fan-out attempted, FCM rejected all tokens | escalate |
| `ACCEPTED` | rider took it — existing timeline takes over | — |
| `NOT_APPLICABLE` | takeaway / dine-in | — |

---

## 5. Track A — make it actually fire (root cause)

**A0. Close the diagnosis (no code).** Confirm which flow was run: expecting the broadcast at READY
(→ Cause 1), or a manual staff assign that *also* stayed silent (→ Cause 2). Check whether the new
phone ever created a `device_tokens` row. Flip one test shop to `BROADCAST` — **the broadcast loop
has never been device-verified once in the history of this feature**; right now it isn't even
exercisable.

**A1. Rider-app registration hardening.** Fix the six paths in §1:
- surface permission-denied as real UI state + a "turn on in Settings" action
- log/telemeter the `getToken()` catch instead of swallowing
- retry the POST with backoff; make `registeredRef` a *succeeded*-latch, and re-attempt on foreground
- add `onTokenRefresh`
- call `DELETE /api/devices` on logout
- stop the home card claiming "shops can assign you deliveries" when push is not actually armed

**A2. Notification health row in the rider app** — permission granted?, token registered at?, last
push received at?, plus **"Send me a test notification"**. This is what would have answered "is this
new phone even registered?" in five seconds instead of a whole evening.

⚠️ A1/A2 reach a real device only via a full EAS build (no OTA configured) — **ask before spending
EAS credits** ([[feedback_ask_before_eas_build]]).

**A3. Backend log fixes (cheap, independent).** Log branches 1 and 2. Make `:111` report actual
send results instead of asserting success. Carry `orderId`/`shopId` into the FCM per-token logs.

---

## 6. Track B — make it knowable (visibility)

**B1. Docs only. ✅ DONE 2026-08-13** — [`dispatch-triggers.md`](./dispatch-triggers.md), the canonical
six-gate decision table. Ships independent of everything below.

**B2a. Live-derived visibility — NO SCHEMA CHANGE. ← start here.**
Post-DA restructure: ~80% of the original complaint ("nothing tells me what stage / what will
happen") is answerable *live*, with no table and no migration:

| Surface | Source | Schema |
|---|---|---|
| Header pill shows the real dispatch mode | `shop.dispatchMode` | none |
| PREPARING ticket: "will notify N riders when you mark ready" | live `resolveDispatchRiders()` | none |
| READY on a MANUAL shop: "doesn't auto-notify → Assign" | `shop.dispatchMode` | none |
| READY, 0 eligible: "nobody is online" | live call | none |

One read endpoint + the ticket strip. **N must come from `resolveDispatchRiders`, never from the
"N riders online" badge** — see DA finding F1 below.

**B2b. Persist dispatch attempts (backend) — DA GATE.** Only needed for the *historical* states
("notified 4 riders at 14:32", `PUSH_FAILED`, "was 1 of 4 notified"). FCM per-token results exist
only at send time and cannot be reconstructed later, so these genuinely require a table — but they
are slice two, not a prerequisite for B2a.

### DA outcome (2026-08-13) — `proceed with conditions`

Full findings: memory `followup_dispatch_visibility_da`. The blocking ones:

- **F1 — two rider pools.** `resolveEligibleRiders` (wide, status-unfiltered, `BLOCKED` included) backs
  the "N riders online" badge; `resolveDispatchRiders` (narrow, `ACTIVE`-only, `deliveryMode`-keyed)
  backs the broadcast. The counts can legitimately differ. A "will notify N" UI fed from the badge
  lies. Not covered by ADR-0019, which frames the split differently.
- **F2 — "flip a shop to BROADCAST" silently reverts** unless `deliveryProvider` is changed first
  (documented in ADR-0019 §Decision; see `dispatch-triggers.md` §3 for the correct sequence).
- **F3 — this plan does not achieve the goal for MANUAL shops**, i.e. the shop that actually broke.
  A MANUAL shop only ever fires `DELIVERY_ASSIGNED`, whose outcome stays invisible. Either cover
  both notification types or scope the goal honestly.
- F4 empty history must read "not recorded", never "reached nobody" · F5 ship indexes with the table
  (`order_id`, `shop_id+created_at`) · F6 define NULL vs 0 for counts · F7 don't record gate-1 skips
  (a row per takeaway/dine-in READY) · F8 a "re-broadcast" button is a second writer — share one path.

**Prerequisite for any of it:** the broadcast loop has still never been observed working. Do F2 and
run one real order before building observability for an unverified path.

Research already narrows it — **reuse is off the table**:
- `delivery_events.delivery_id` is `nullable = false` (`DeliveryEvent.java:54`), and a broadcast
  creates no delivery row, so there is nothing to key an event to.
- `DeliveryEventRepository` has exactly one finder and its doc explicitly forbids adding others
  (seq-scan risk). Its enums are delivery-lifecycle-shaped with no dispatch vocabulary.
- **No order-level audit table exists anywhere** — `Order` has a single overwritten `status` column,
  no Envers, and the only two log-ish tables in the whole backend are `delivery_events` and
  `payment_webhook_events`.
- Schema is `ddl-auto=update` with no Flyway/Liquibase, so a new table is a plain new `@Entity`.

So the DA question narrows to: **new `order_dispatch_events` table** (keyed `order_id`, nullable
`delivery_id`) **vs. recompute-live-at-read-time**. Live recompute is cheapest but cannot answer
"what was true at the moment of transition" (riders go offline afterwards) or "notified at 14:32".

⚠️ **Framing constraint:** the original design *deliberately rejected* an offer table (no `OFFERED`
status, no nullable `rider_id`) to avoid the implicit-filter trap. This is **append-only
observability that no dispatch logic ever reads** — same shape as [[feedback_kot_append_not_mutable]].
That distinction must be explicit in the DA and in the table's code comment, or a future session
will mistake it for the thing that was cut.

Record a row for **every** invocation *including the skips* — recording the non-events is the entire
point. Capture per-token FCM results so `PUSH_FAILED` is measured, not assumed.

**B3. API.** `GET /api/shops/{shopId}/orders/{orderId}/dispatch` → attempts + derived current state.
Admin cross-shop variant for debugging.

**B4. Redesign pass, then build the UI.** See §7.

**B5. Deferred (not now).** Unaccepted-order escalation ("nobody accepted in N minutes"), historical
riders-notified analytics.

---

## 7. Reincorporating into the design (`/redesign`)

**This is a starved-data problem, not a styling problem** — precisely the diagnosis the redesign
skill exists to make. The order board looks fine; it has nothing to say. Two consequences:

1. **Data contract first (B3), redesign second.** Designing these panels before the fields exist
   produces beautiful empty boxes.
2. **Intensity = "improvement", not "revamp".** The rose/crimson brand token, the shadcn set, the
   4-column board and the `AgingClock` pattern are decided and shipped — a revamp would churn work
   already accepted.

### Scope — four surfaces only

| Surface | File | Gap |
|---|---|---|
| Order ticket | `features/shop/components/OrderTicket.tsx` | `actionsForStatus` (`:46-64`) has no notion of dispatch; needs an always-visible dispatch line |
| Delivery timeline | `DeliveryTimelineDialog.tsx` | starts at accept — extend *backwards* so one timeline tells the whole story |
| Riders indicator | `RidersIndicator.tsx` / `OnlineRidersPanel.tsx` | global "N online" reads as dispatch health but isn't; make it order-aware |
| Admin dispatch log | new | per-order "which gate stopped it" |

### The real design question to hand to redesign

`OrderTicket` is already dense — ref, aging clock, items, prep progress, address, money, payment,
actions. **Where does a 9th element go without becoming noise?** Specifically:
- strip, inline badge beside the clock, or border treatment? (`border-l` is already spent on `NEW`,
  `OrderTicket.tsx:148`)
- how to render the `NO_ELIGIBLE_RIDERS` alarm without inventing a red that collides with
  `destructive` (`:189`, `:209`)
- should the READY column sub-group into waiting-for-rider vs rider-assigned?

Then `/ui-engineer` builds it (standing rule for Ninjasu_Web), reusing shared components and
defining all props upfront ([[feedback_shared_component_props_upfront]]).

---

## 8. Open questions

- Which flow was actually run on the new phone — broadcast-expected, or manual assign? (decides
  whether Cause 2 is confirmed or merely latent; blocks A0)
- Is `MANUAL` correct for Masala long-term, or was it meant to be `BROADCAST`?
- Track A vs Track B first? A1/A2 need an EAS build to verify; B1 ships in 30 minutes.
