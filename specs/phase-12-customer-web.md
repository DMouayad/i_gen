# Phase 12 — Customer Web App (Next.js, Vercel)

## Problem Statement

Customers need to submit and follow orders, and the server domain for
that already exists (orders + order_items, Phase 10) — but there is no
writer UI: the Flutter app is read-only by design and customers never
touch it. The owner wants a hosted web app, cheap to run (Vercel), that a
customer opens from their invite link and uses for exactly two things:
placing orders and viewing order history.

## Solution

A customer-only Next.js 16 app in `web/` (Vercel root = `web/`), talking
to the same Supabase project under the same role rules. Phone+password
login (phone resolves to the synthesized login email via the
`phone_to_email` RPC, so the mobile app can reuse the same login later),
catalog with per-size quantities, cart persisted in localStorage, pending
orders editable until staff confirm them. No prices surface anywhere:
customers order blind (`price: 0`, priced on the invoice by staff).

## User Stories

1. As a customer with a welcome link, I want to set my own password on
   first open, so that no secret ever lives in chat history.
2. As a customer, I want to sign in with my phone number + password, so
   that I never see the synthesized login email.
3. As a customer, I want to browse products and add per-size quantities
   to a cart, so that one order covers all sizes I need.
4. As a customer, I want to submit the cart as a pending order and land
   on its detail page, so that I know it went through.
5. As a customer, I want to browse my order history with statuses, so
   that I can answer "where is my order?" myself.
6. As a customer, I want to edit quantities / remove lines
   while my order is still pending, so that mistakes are cheap.
7. As a customer, I want the app in Arabic or English, so that language
   never blocks ordering.
8. As the owner, I want customers to never see prices, so that pricing
   stays a staff decision made on the invoice.
9. As the owner, I want completed history to be read-only for
   customers, so that staff records are never rewritten.
10. As support, I want an expired invite link to say exactly
    "link expired — ask the admin for a new one", so that failures end in
    one WhatsApp message.
11. As the owner, I want the web app to need zero server of its own, so
    that Vercel + the existing Supabase project is the whole bill.

## Implementation Decisions

- One Supabase project for both apps; `supabase/schema.sql` is the shared
  contract. Phase 12 delta (all additive): `products_customer_read`
  (catalog visible, `is_deleted = false` only, still no `prices` access),
   `orders_customer_own_update` (pending row → pending only, so
   a customer can edit lines but never complete/reassign),
  `items_customer_own_insert` tightened to pending parents plus new
  `items_customer_own_update`/`_delete` gated on the parent being the
  caller's own pending order, `phone_to_email(p_phone)` SECURITY DEFINER
  RPC (anon-executable, NULL for unknown phones), and `order_items.size`
  (`''` default, mirrors `invoice_lines.size`).
- The Flutter read models ignore the new `size` key (pattern-match parsing),
  so no mobile change ships in this phase; staff-side size display is a
  later mobile item.
- Web auth is client-only (supabase-js browser client, localStorage
  session): catalog/history/edit pages are client components behind the
  auth provider. No `middleware.ts`/SSR auth — one less Next 16 migration
  surface, and SEO is irrelevant behind login. Non-customer logins are
  signed straight back out with a "not a customer" message.
- i18n is a hand-rolled `web/lib/i18n.tsx` dict (EN/AR, `dir` flipped on
  `documentElement`, `lang` cookie) — no next-intl dependency for ~50
  strings. Wording reuses the mobile ARB terms where they exist.
- Order create writes `{customer_id}` only (status/total/currency ride
  schema defaults) then the lines (`price: 0`, per-line `size`). Totals
  render as "Priced on invoice" while 0.
- Order statuses are pending/completed only (no cancel flow; a pending
  order stays editable instead of being cancelled). Nothing sets completed
  yet — staff completion (mobile button + staff update policy) is a later
  item; until then completed is dashboard/SQL-only.
- `WEB_WELCOME_URL` (invite function env) must point at the deployed
  `/welcome`; `/welcome?code=…` exchanges the code then shows the
  set-password form.

## Testing Decisions

- Good tests assert visible customer behavior, not query internals: who
  sees which catalog/orders, what a pending order allows, what a completed
  one refuses.
- Verified: `tsc --noEmit` 0 errors, `eslint` 0 errors/warnings, `next
  build` green with no env vars (pages show the config notice). Server
  rules carry a commented verify block in `schema.sql` (catalog read works,
  `prices` reads 0 rows, `phone_to_email` resolves, own pending order
  editable) to run as a customer login before first deploy.
- Prior art: RLS matrix habit from Phase 8 (preview-project check, not in
  any unit suite); no web unit suite in this phase — the build + the SQL
  verify block are the gates.

## Out of Scope

- Any staff/admin screens in web (Flutter covers staff). Prices in web.
  Customer registration (invite-only, admin pipe stays). Order drafts
  beyond cart-in-localStorage. Adding new products from the order-detail
  page (catalog → new order covers it). Realtime updates (poll/refresh by
  navigation). Mobile display of order line sizes (noted follow-up).
  FCM/push for customers.

## Further Notes

- Decided: client-only auth over SSR cookie auth — the app is fully
  login-walled, so SSR buys nothing and `middleware.ts` would drag in the
  Next 16 proxy migration.
- Decided: hand-rolled i18n over next-intl — ~50 strings, zero new-API
  risk, same ARB wording.
- Decided: `price: 0` + total-0-means-unpriced over hiding totals — staff
  price on the invoice; the web never pretends otherwise.
- Decided: pnpm pinned via `packageManager` (`pnpm@12.4.1`) — this box's
  pnpm is a corepack shim and resolves per-directory, so the pin is what
  keeps shells agreeing.
