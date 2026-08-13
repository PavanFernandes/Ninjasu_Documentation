# When does a rider get notified?

**The canonical answer.** If you are debugging "the rider got nothing", start here and walk §3
top-down — it is ordered to match the actual code path, so the first row that fails is your cause.

Verified against code 2026-08-13. Companion: [`dispatch-visibility-plan.md`](./dispatch-visibility-plan.md)
(the plan to make all of this visible in-product instead of only in this file).

---

## 1. There are three rider notifications, and they fire at completely different moments

| # | Notification | Fires when | Source |
|---|---|---|---|
| 1 | **Broadcast offer** ("new delivery available") | an **order** transitions `PREPARING → READY` | `DeliveryDispatchListener.java:53-116` |
| 2 | **`DELIVERY_ASSIGNED`** | a **`deliveries` row is created** by staff assign/reassign | `DeliveryRiderNotificationListener.java:60-71` |
| 3 | **`DELIVERY_REVOKED`** | a delivery goes `FAILED`/`CANCELLED` while it still has a rider | `DeliveryRiderNotificationListener.java:75-98` |

**These are not variants of one thing.** #1 is keyed to an *order status transition*. #2 and #3 are
keyed to *delivery-row lifecycle* and are not status transitions at all. Most "which stage does it
fire?" confusion comes from assuming a single trigger exists.

Two consequences worth internalising:

- **#2 is never fired by `acceptDelivery`.** A rider who accepts a broadcast already knows they took
  it; sending them an "assigned" push would be noise.
- **#1 writes no `deliveries` row** (`DeliveryDispatchListener.java:31-32` — "this is a pure
  notification"). So `DeliveryTimelineDialog` in Ninjasu_Web has nothing to show until someone
  accepts; `getDeliveryForOrder` returns `null` for a READY-but-unclaimed order
  (`delivery.service.ts:49-57`). The broadcast leaves **no trace in the product at all** today.

### Naming trap

There is **no `READY_FOR_PICKUP` status in this codebase.** The enum value is `READY`. Docs and
older notes that say `READY_FOR_PICKUP` mean `READY`.

---

## 2. What triggers the broadcast, exactly

The `PREPARING → READY` transition, published from the seller status endpoint:

- `ShopOrderController.java:62` → `OrderServiceImpl.updateOrderStatus(...)` (`:281-328`)
- Legality enforced at `OrderServiceImpl.java:354` — `case PREPARING -> next == OrderStatus.READY`
  (transitions are strictly linear; you cannot jump `ACCEPTED → READY`)
- Event published at `OrderServiceImpl.java:323-325`
- Consumed `AFTER_COMMIT` in `REQUIRES_NEW` — a dispatch failure can never roll back the order
  status change

In the web order tab this is the **"Mark ready"** button on a `PREPARING` ticket
(`OrderTicket.tsx:56`).

---

## 3. The six gates — walk these in order

Every gate fails into the *same* visible outcome: an order sitting at `READY`, silence.

| # | Gate | If it fails | Log today |
|---|---|---|---|
| 1 | `newStatus == READY` **and** `orderType == DELIVERY` | returns, `:55-57` | **nothing** |
| 2 | shop `dispatchMode == "BROADCAST"` | returns, `:59-66` | **nothing** |
| 3 | `resolveDispatchRiders(shopId)` non-empty | returns, `:68-74` | INFO |
| 4 | those riders have `device_tokens` rows | returns, `:76-83` | INFO |
| 5 | order row still exists | returns, `:85-89` | WARN |
| 6 | FCM actually delivers | **no branch exists** | — see §5 |

### Gate 2 is the most common cause and the least visible

`dispatchMode` is per-shop, `MANUAL` or `BROADCAST`. **`MANUAL` shops never auto-notify anyone,
ever.** Staff assign riders by hand (notification #2 in §1). No amount of riders being online
changes this, and nothing is written to the log.

Check it with:

```
GET /api/shops/{shopId}          → dispatchMode
```

**⚠️ Trap when making a shop broadcast-capable.** Setting `dispatchMode = BROADCAST` alone can
silently revert to `MANUAL`. `ShopServiceImpl#normalizeDispatchMode` forces `MANUAL` whenever
`deliveryMode` resolves to `NONE` (`:117` on create, `:413` on update) — `NONE`+`BROADCAST` is not a
reachable stored state. And `deliveryMode` is **derived from `deliveryProvider`**, never settable
directly (`:116`, `:409`). Correct order:

1. set `deliveryProvider` so `deliveryMode` becomes `SELF` or `PLATFORM`
2. *then* set `dispatchMode = BROADCAST`
3. read the shop back and confirm both stuck

Rationale for the whole two-field design: [ADR-0019](../01-Architecture/decisions/ADR-0019-dispatch-mode-vs-delivery-mode.md).

> Confirmed real-world instance, 2026-08-13: shop "Masala" was `MANUAL`. A full order walk to `READY`
> produced no notification, correctly. Meanwhile Ninjasu_Web displayed **"1 rider online"** the whole
> time — that indicator reflects rider duty status only and says nothing about whether a broadcast
> can fire. Do not read it as dispatch health.
>
> **Masala has since been set to `BROADCAST`** (same day) so the loop is exercisable — it had never
> been run end-to-end even once. Revert with `PUT /api/shops/{id}` `{"dispatchMode":"MANUAL"}`.

### Gate 3 — who counts as eligible (⚠️ two different pools exist)

The broadcast uses **`resolveDispatchRiders(shopId)`** (`RiderServiceImpl.java:180-208`) — the
**narrow** pool. It branches on `deliveryMode`:

| `deliveryMode` | Broadcast pool |
|---|---|
| `SELF` | the shop's own `RESTAURANT` riders, online **and `ACTIVE`** |
| `PLATFORM` | own fleet ∪ zoned platform riders, online **and `ACTIVE`** |
| `NONE` (or null) | **empty — no dispatch pool at all** |

**Do not confuse it with `resolveEligibleRiders`** (`:163-177`), the **wide** pool: status-unfiltered
(a `BLOCKED` rider still appears), `deliveryMode`-agnostic. That one backs the staff "see & call"
list and Ninjasu_Web's **"N riders online"** badge. Both javadocs explicitly forbid merging them.

**Consequence:** the badge's number and the number actually notified can legitimately differ — a
`BLOCKED`-but-online rider inflates the badge and never receives a broadcast. Any UI that says
"will notify N riders" must compute N from the *dispatch* pool.

A `PLATFORM` shop belonging to no zone, and any shop on `deliveryMode = NONE`, both resolve to an
empty set and are totally silent no-ops.

Design rationale for the split: [ADR-0019](../01-Architecture/decisions/ADR-0019-dispatch-mode-vs-delivery-mode.md).

### Gate 4 — no device token

Reads in the log as `"eligible riders have no device tokens"`, which is **indistinguishable from
"the rider has never opened the app"**. See §4 — this is where a fresh-install failure surfaces.

---

## 4. Why a rider's phone may have no token (six silent paths)

All in the rider app. Every one is invisible to both the rider and the backend.
Registration is 20 lines: `usePushRegistration.ts:36-55`.

| # | Path | Where |
|---|---|---|
| 1 | `ready` never set → the effect never runs | `usePushRegistration.ts:38` |
| 2 | **notification permission denied** → returns *before* fetching a token, so nothing is ever POSTed | `:44` |
| 3 | `getToken()` throws → bare catch, no logging | `pushSetup.ts:75-81` |
| 4 | `POST /api/devices` fails → empty catch, no retry, no backoff | `:49-53` |
| 5 | FCM rotates the token → no `onTokenRefresh` handler exists anywhere | — |
| 6 | logout never calls `DELETE /api/devices` → stale token stays pointed at the previous user | `DeviceController.java:34-41` (endpoint exists, never called) |

Two aggravating details:

- `registeredRef` is set `true` **before** the async work (`:23,39`), making it an *attempted-once
  per process* latch, not *succeeded-once*. One bad moment right after first login means silence
  until a full app kill — backgrounding and resuming is not enough.
- Path 2 is sticky: Android stops showing the permission dialog after two denials, permanently.
- `home.tsx:139-150` shows a green **"You're online — shops can assign you deliveries"** regardless
  of any of the above. There is no settings, profile, or debug screen in the app, so a rider has no
  way to check.

### Multi-device: two phones both ring

`device_tokens` is keyed on `token` (unique), **not** `user_id` (no uniqueness constraint) —
`DeviceToken.java:20-54`. Upsert is by token (`DeviceServiceImpl.java:22-37`). So the same rider
logged in on two phones has two rows and **both are included in the multicast**; both ring. The only
overwrite case is the *same physical device* being reused by a different account, which
deliberately re-points that one row.

---

## 5. What the logs can and cannot tell you

**`"broadcast sent"` at `DeliveryDispatchListener.java:111` is logged unconditionally — even when
every single push failed.** `pushSender.send(...)` is `void` and never throws; `FcmPushSender`
swallows everything at `:71-72`. The listener cannot distinguish a delivered broadcast from a total
FCM outage.

Per-token outcomes exist only inside `FcmPushSender` (`:167`, `:172`, `:175`) and carry **no
orderId, shopId, userId or token**, so they cannot be correlated to a dispatch. A rider-specific
non-delivery is untraceable by construction.

**Config hazard:** `FcmPushSender` is `@ConditionalOnProperty(app.firebase.enabled=true)`
(`:33-34`). If that is ever false, `LoggingPushSender` (`:19-28`) takes over, sends nothing, logs
`"[PUSH STUB] would send to N token(s)"` — and `:111` **still logs "broadcast sent"**.

---

## 6. Fast triage checklist

1. Is the order `orderType == DELIVERY` and did it actually reach `READY`? → gate 1
2. `GET /api/shops/{shopId}` → is `dispatchMode == BROADCAST`? → **gate 2, the usual culprit**
3. Is the rider online, and (if `PLATFORM`) in a zone covering this shop? → gate 3
4. Does the rider have a `device_tokens` row at all? → gate 4, then §4
5. Server log: `"broadcast sent … eligibleRiders=N tokens=M"` — remember this proves *attempted*,
   not *delivered*
6. On-device: `adb shell dumpsys notification` shows which channel it landed on and its real
   importance; `adb logcat` filtered to `FirebaseMessaging|ReactNativeJS` shows the raw payload

---

## 7. Known gaps (tracked in the plan, not fixed here)

- Gates 1 and 2 emit no log — the two most common causes are the two least traceable
- Gate 6 is unmeasured; success is asserted, not observed
- Nothing in Ninjasu_Web communicates dispatch state at any stage
- The broadcast → accept loop has **never been device-verified**, across the whole history of the feature
