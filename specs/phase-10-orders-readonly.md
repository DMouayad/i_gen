# Phase 10 — Orders Read-Only in This App (Web App Writes)

## Problem Statement

Customers need to submit and follow orders, and staff need to see those orders and who placed them — but building full offline order-taking into the Flutter app now would drag an entire second sync domain (queues, conflicts, caches) into this phase. The owner runs two surfaces: this Flutter app for staff and a separate web app where customers work. Staff need visibility without edit power; customers need a writer that lives elsewhere.

## Solution

Introduce the shared orders domain on the server once, used by both apps, and expose it in this Flutter app as read-only and online-first: staff browse orders, order lines, and the customer directory live from the server, with no local cache and no create/edit path here. All order writes happen in the web app under the same role rules. Employees read orders and customers; admins read and manage them; customer credentials read only their own orders (exercised from the web app, not this UI).

## User Stories

1. As the admin, I want to browse all orders with their lines and placing customer, so that I can answer "where is my order?" in seconds.
2. As an employee, I want to read orders and the customer directory but never create or edit an order here, so that I cannot promise stock by accident.
3. As a customer, I want to submit and view my orders in the web app, so that I have one writer that always works.
4. As the admin, I want every order stamped with its customer and creator for audit, so that shared visibility never loses who asked for what.
5. As an employee on a stale connection, I want a clear loading/offline/empty state on orders screens, so that I never mistake "no signal" for "no orders".
6. As the owner, I want order reads in this app to be live server reads with no offline queue, so that staff never act on a cached phantom order.
7. As the owner, I want order writes from this app's credentials to be rejected by the database, so that a modified client cannot sneak an order in.
8. As support, I want order status and totals to read the same in both apps, so that phone disputes end fast.
9. As the admin, I want to find orders by customer, date, and status, so that follow-ups are quick.
10. As the owner, I want customer personal data in this app limited to what staff need (names, phone, business link to orders), so that exposure stays minimal.
11. As a signed-out user, I want the existing invoicing app to behave exactly as today, so that orders work never gates offline billing.

## Implementation Decisions

- One shared server domain for orders (orders plus order lines) serves both apps; this phase adds no second definition and no local orders tables. The Flutter app reads through the existing repository seam in a read-only specialization: list, detail, and customer directory as live queries, no outbox entries, no checkpoints, no tombstones for orders.
- Role rules for the orders domain: admin reads and manages all orders; employee reads all orders and the customer directory but writes nothing; customer reads only orders they placed (their web-app path also writes under the same rules). This app's credentials are never granted order-write; the web app holds the only writer.
- Customer directory in this app is a narrow projection of profiles (identity plus order linkage), not a full user-management surface — invite/resend/recover stay in the admin invite area.
- Screens are deliberately thin and online-first: loading, offline-retry, empty, and error states are first-class; no silent caching, no background order sync, no conflict handling here because there are no local order writes to conflict.
- Existing invariants are preserved: the five invoicing tables keep their offline-first sync, outbox idempotency, and soft-delete behavior untouched; login stays optional and non-blocking; repositories keep their one-direction dependency and never import auth or sync.
- Seam choice: reuse the repository-method seam for reads (new read methods, no new abstractions) and the reconnect-pull freshness mechanism already used elsewhere — no Realtime subscription is added in this phase.
- Order-to-invoice prefill (later addition): the details dialog offers "Create invoice", which opens the existing invoice editor prefilled from the order (customer as invoice customer, lines matched by product model, prices stay 0 in the custom category). This creates an invoice, never an order — the orders domain stays read-only. The link is a nullable `invoice.order_id`, synced like any invoice column; the orders list marks linked orders "Invoiced".

## Testing Decisions

- Good tests assert visible read behavior and write rejection, not query internals: who sees which orders, what the offline state says, that no local order write path exists.
- Tested: admin sees all orders; employee sees all orders and customers but has no create/edit affordance and any forged write is rejected server-side; customer credential reads only its own orders; offline orders screen shows retry rather than stale data or a hang; signed-out invoicing still works fully offline.
- Prior art: repository-pattern fakes for reads and the auth-boundary fakes for role switching are reused; server rules are verified with a scripted matrix against a preview project (admin/employee/customer reads plus forged-write rejection), not in the unit suite.

## Out of Scope

- Any order create/edit UI in this Flutter app. Offline order queue, order sync engine work, or local order caching. Web-app order-writing UI (separate surface, same server rules). Order status workflows beyond read (approvals, fulfillment transitions). Realtime order updates. Real-email linking. Multi-company partitioning.

## Further Notes

- Decided: read-only here / write-in-web-app split keeps this phase to auth plus two read screens and defers the entire offline-orders conflict domain until real customer volume demands it.
- Decided: live reads over cached reads for orders — staff must never quote a phantom cached total; the cost is an explicit offline state, which is cheaper than a wrong promise.
- Decided: customer PII in this app stays minimal (names, phone, order linkage); anything richer lives behind the web app's own access rules.
