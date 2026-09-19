# Phase 8 — Shared-Company Access Rules (Role RLS)

## Problem Statement

The shipped server access rules isolate every user to rows they personally created. That was correct for single-user sync, and it breaks on the second employee: a newly invited employee opens the app and sees zero invoices, zero products, zero prices — not because data is missing but because the rules hide everyone else's rows. With one company, staff must share one dataset with least-privilege boundaries, and customers must see nothing of the invoicing domain from this app.

## Solution

Replace per-user ownership isolation on the five business tables with role-based shared-company rules. The creator stamp stays on each row as audit only; visibility and writability come from the caller's role. Admins keep full access, employees write invoices and invoice lines but only read products, prices, and price categories, and customers get no access to these tables from this app (they order through the web app). The change ships as one small migration rewriting the policies, verified by a role matrix before any client code relies on it.

## User Stories

1. As an employee signing in on a new device, I want to see the company's existing invoices and products, so that I can work on day one.
2. As an employee, I want to create and edit invoices and invoice lines, so that I can bill customers.
3. As an employee, I want products, prices, and price categories to be read-only for me, so that I cannot accidentally reprice the catalog.
4. As the admin, I want full read and write on all five tables, so that I can fix anything.
5. As a customer opening this Flutter app, I want no access to invoices, products, or prices here, so that I am guided to the web app instead.
6. As the owner, I want the creator stamp preserved on every row for audit, so that shared visibility never loses accountability.
7. As the owner, I want a forged creator id in an upload to be rejected, so that audit cannot be spoofed.
8. As a signed-out or offline user, I want local invoicing to behave exactly as today, so that the rule change never blocks offline work.
9. As the owner, I want the whole rule change in one reviewable migration, so that access can be audited in one place.
10. As support, I want a documented two-user check (admin row visible to employee, employee invoice visible to admin, customer sees nothing), so that regressions are caught in minutes.

## Implementation Decisions

- The five business tables (products, price categories, invoices, invoice lines, prices) move from "caller sees only rows they own" to "caller sees company rows per their role". The per-row creator stamp is retained purely for audit and last-write-wins lineage; it no longer gates reads.
- Permission matrix enforced in the database, not just the UI: admin gets full read/write on all five; employee gets read/write on invoices and invoice lines and read-only on products, prices, and price categories; customer gets no read and no write on any of the five from this app's credentials. Write of a forged creator id is rejected.
- Soft-delete propagation, server timestamps, idempotency keys, and last-write-wins merging are unchanged — only the visibility/write predicates change.
- The existing sync engine seam is untouched in shape: uploads keep stamping the cached owner id as the audit value; the engine treats access-denied responses as terminal for that row (count, log, park per existing dead-letter policy) rather than wedging the queue.
- Repository layer keeps its one-direction dependency (engine/UI into repositories; repositories never import auth or sync). Role gating in the UI mirrors the database rules but never replaces them.
- Verification seam: a scripted role-matrix check against a preview project (admin seeds one row per table; employee reads all five, writes only invoices/lines, and is rejected writing prices; customer reads zero) must pass before client work depending on sharing begins.

## Testing Decisions

- Good tests assert externally visible isolation from the matrix, never trigger or policy internals: row counts per role, write-accept vs write-reject per role.
- Tested: employee sees admin-seeded rows; employee invoice write accepted; employee price write rejected; customer reads zero and writes rejected; forged creator id rejected; signed-out local use unaffected.
- Prior art: the existing two-user isolation check script is extended into the role matrix and run against a preview project, not in the unit suite; unit tests stay at the repository/outbox boundary with fakes.

## Out of Scope

- Orders tables and their rules (dedicated phase). The invite pipe and profiles directory (adjacent phases). Any client UI for roles or admin screens. Realtime. Conflict UI (still silent last-write-wins). Multi-company partitioning.

## Further Notes

- Decided: shared-company role rules over per-user isolation — the per-user shape cannot serve a second employee and there is exactly one company, so no tenant id is added.
- Decided: least-privilege for employees (invoices writable, catalog read-only) over the simpler "employee equals admin" — matches the owner's original boundary at the cost of three extra write predicates.
- Decided: customers are fully excluded from these five tables in this app; their data surface is orders plus a customer-visible product read served by the web app's rules, defined in the orders phase.
