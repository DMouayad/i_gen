# Phase 12 — Distributor Web App (Next.js, Vercel)

## Problem Statement

Distributors need to submit and follow orders, and the server domain for
that already exists (orders + order_items, Phase 10) — but there is no
writer UI: the Flutter app is read-only by design and distributors never
touch it. The owner wants a hosted web app, cheap to run (Vercel), that a
distributor opens from their invite link and uses for exactly two things:
placing orders and viewing order history.

## Solution

A distributor-only Next.js 16 app in `web/` (Vercel root = `web/`), talking
to the same Supabase project under the same role rules. Phone+password
login (phone resolves to the synthesized login email via the
`phone_to_email` RPC, so the mobile app can reuse the same login later),
catalog with per-size quantities, cart persisted in localStorage, pending
orders editable until staff confirm them. No prices surface anywhere:
distributors order blind (`price: 0`, priced on the invoice by staff).

## User Stories

1. As a distributor with a welcome link, I want to set my own password on
   first open, so that no secret ever lives in chat history.
2. As a distributor, I want to sign in with my phone number + password, so
   that I never see the synthesized login email.
3. As a distributor, I want to browse products and add per-size quantities
   to a cart, so that one order covers all sizes I need.
4. As a distributor, I want to submit the cart as a pending order and land
   on its detail page, so that I know it went through.
5. As a distributor, I want to browse my order history with statuses, so
   that I can answer "where is my order?" myself.
6. As a distributor, I want to edit quantities / remove lines / cancel
   while my order is still pending, so that mistakes are cheap.
7. As a distributor, I want the app in Arabic or English, so that language
   never blocks ordering.
8. As the owner, I want distributors to never see prices, so that pricing
   stays a staff decision made on the invoice.
9. As the owner, I want confirmed/delivered history to be read-only for
   distributors, so that staff records are never rewritten.
10. As support, I want an expired invite link to say exactly
    "link expired — ask the admin for a new one", so that failures end in
    one WhatsApp message.
11. As the owner, I want the web app to need zero server of its own, so
    that Vercel + the existing Supabase project is the whole bill.

## Implementation Decisions

- One Supabase project for both apps; `supabase/schema.sql` is the shared
  contract. Phase 12 delta (all additive): `products_distributor_read`
  (catalog visible, `is_deleted = false` only, still no `prices` access),
  `orders_distributor_own_update` (pending row → pending/cancelled only, so
  a distributor can cancel but never confirm/deliver/reassign),
  `items_distributor_own_insert` tightened to pending parents plus new
  `items_distributor_own_update`/`_delete` gated on the parent being the
  caller's own pending order, `phone_to_email(p_phone)` SECURITY DEFINER
  RPC (anon-executable, NULL for unknown phones), and `order_items.size`
  (`''` default, mirrors `invoice_lines.size`).
- The Flutter read models ignore the new `size` key (pattern-match parsing),
  so no mobile change ships in this phase; staff-side size display is a
  later mobile item.
- Web auth is client-only (supabase-js browser client, localStorage
  session): catalog/history/edit pages are client components behind the
  auth provider. No `middleware.ts`/SSR auth — one less Next 16 migration
  surface, and SEO is irrelevant behind login. Non-distributor logins are
  signed straight back out with a "not a distributor" message.
- i18n is a hand-rolled `web/lib/i18n.tsx` dict (EN/AR, `dir` flipped on
  `documentElement`, `lang` cookie) — no next-intl dependency for ~50
  strings. Wording reuses the mobile ARB terms where they exist.
- Order create writes `{distributor_id}` only (status/total/currency ride
  schema defaults) then the lines (`price: 0`, per-line `size`). Totals
  render as "Priced on invoice" while 0.
- Cancel is a status update to `cancelled`, never a delete (matches the
  soft-delete invariant; server has no distributor delete policy).
- `WEB_WELCOME_URL` (invite function env) must point at the deployed
  `/welcome`; `/welcome?code=…` exchanges the code then shows the
  set-password form.

## Testing Decisions

- Good tests assert visible distributor behavior, not query internals: who
  sees which catalog/orders, what a pending order allows, what a confirmed
  one refuses.
- Verified: `tsc --noEmit` 0 errors, `eslint` 0 errors/warnings, `next
  build` green with no env vars (pages show the config notice). Server
  rules carry a commented verify block in `schema.sql` (catalog read works,
  `prices` reads 0 rows, `phone_to_email` resolves, own pending order
  editable) to run as a distributor login before first deploy.
- Prior art: RLS matrix habit from Phase 8 (preview-project check, not in
  any unit suite); no web unit suite in this phase — the build + the SQL
  verify block are the gates.

## Out of Scope

- Any staff/admin screens in web (Flutter covers staff). Prices in web.
  Distributor registration (invite-only, admin pipe stays). Order drafts
  beyond cart-in-localStorage. Adding new products from the order-detail
  page (catalog → new order covers it). Realtime updates (poll/refresh by
  navigation). Mobile display of order line sizes (noted follow-up).
  FCM/push for distributors.

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
