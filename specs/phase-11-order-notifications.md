# Phase 11 — New-Order Alerts for Staff (Realtime + Poll)

## Problem Statement

Distributors place orders in the web app, but staff only learn about them by
opening the orders screen and pulling to refresh. The owner wants staff phones
to buzz when a new distributor order lands — instantly while the app is alive,
shortly after otherwise — without building push infrastructure yet.

## Solution

An order watcher, active only for signed-in staff (admin/employee, never
distributors): a Supabase Realtime INSERT subscription on `orders` for the
instant path, plus a 60-second `OrdersRepo` poll as the gap fallback, both
feeding one dedupe gate that fires a single OS tray notification per order.
This is the repo's single scoped Realtime exception (AGENTS.md): the sync
domain stays reconnect-pull; only new-order alerts use Realtime.

## User Stories

1. As staff with the app open, I want a buzz within seconds of a distributor
   placing an order, so that I can confirm it without staring at the screen.
2. As staff returning after a signal gap, I want the missed orders to notify
   on the next poll, so that reconnects never silently skip an order.
3. As staff restarting the app, I want no flood of old orders, so that only
   orders newer than my last seen one ever notify.
4. As a distributor, I want no watcher, no subscription, and no notification
   permission prompts, so that my path stays exactly as today.
5. As a signed-out user, I want zero watcher activity, so that login stays
   optional and the app behaves exactly as today.
6. As the owner, I want each order to buzz once per phone even when both the
   Realtime event and the poll see it, so that staff trust the alert.

## Implementation Decisions

- Server: `orders` is added to the `supabase_realtime` publication (dashboard
  SQL, done once). INSERT payloads carry the full row under default replica
  identity — no migration, no RLS change (`orders_staff_read` already covers
  staff; distributors only ever see their own rows).
- Seams: `OrdersRepo.getOrders` is reused for the poll (no new query; volume
  is low). New seams are `OrderEvents` (Realtime channel wrapper with a fake
  for tests) and `OrderNotifier` (tray-notification wrapper with a fake).
  The coordinator lives lib-side (`lib/orders/order_watcher.dart`, same
  pattern as `SyncBootstrap`): repos never import auth or sync.
- Role gating: subscribe and poll only while signed in as admin/employee with
  Supabase configured. Unsubscribe and stop the timer on logout, on role
  change away from staff, and when unconfigured. Fail-open never: a missing
  role copy means no watcher.
- Dedupe: a persisted seen-id set in `shared_preferences` (capped at 200,
  pruned oldest-mark-first). Every alerted id is stored **before** notifying.
  First run baselines silently (current orders become seen, no flood). Notify
  only `status == pending`. Crash between persist and notify loses at most one
  alert; crash before persist re-notifies at most once — both accepted over a
  flood. An evicted id still inside the 200-row poll window could re-buzz;
  accepted as negligible.
- Copy: notification title/body resolve context-free via
  `AppLocalizations.delegate.load()` for the current `LocaleController`
  locale (en/ar). Tapping the notification opens the app (no deep link to
  the orders tab — nav plumbing stays untouched).
- Desktop (Windows/Linux): the watcher runs the poll for future in-app use
  but never initializes the tray plugin — tray notifications are mobile-only.
- Dependency: `flutter_local_notifications` (approved with this phase).
  Android declares `POST_NOTIFICATIONS`; the channel is created in code.

## Testing Decisions

- Good tests assert alert behavior, not transport internals: who gets
  subscribed, what notifies exactly once, what stays silent.
- Tested (fakes for events, notifier, fetch; no widget tests): staff login
  subscribes + baselines without notifying; Realtime INSERT of a pending
  order notifies once; the same order arriving via poll afterwards does not
  re-notify; non-pending inserts stay silent; restart with persisted cursor
  notifies only newer orders; logout/distributor/unconfigured never
  subscribes and stops the timer.
- Realtime itself is not unit-tested (transport); the poll fallback is the
  covered path and the production safety net.

## Out of Scope

- Killed-app delivery (needs FCM: firebase deps, token registry, Edge
  Function — a later phase if staff routinely kill the app).
- Guaranteed background-suspended delivery (OS throttles timers and sockets;
  without FCM the background path is best-effort — documented, not promised).
- Order deep-link on tap, quiet hours, per-distributor muting, status-change
  alerts (only new pending orders notify), web-app changes.
