# i_gen — invoicing (mobile) + distributor ordering (web)

Monorepo. One Supabase project serves both apps (`supabase/schema.sql`
is the shared server contract — fresh install plus a commented live-upgrade
block at the bottom).

## Layout

- `mobile/` — Flutter staff app (offline-first invoicing, read-only orders
  browser, invite pipe). See `mobile/pubspec.yaml`.
- `web/` — Next.js 16 distributor app (Vercel): catalog + cart, order
  history, pending-order edit. Distributor-only, EN/AR, no prices surface.
- `supabase/` — `schema.sql` + the `invite-user` Edge Function.
- `specs/` — phase specs, source of truth for behavior.

## Distributor web quickstart

```sh
cd web
cp .env.example .env.local   # NEXT_PUBLIC_SUPABASE_URL + ANON_KEY
pnpm install
pnpm dev
```

Deploy: Vercel project with root directory `web/`, same two env vars.
Then set the invite function's `WEB_WELCOME_URL` to
`https://<vercel-domain>/welcome` so distributor invite/recovery links land
on password setup. Run the Phase 12 live-upgrade block from
`supabase/schema.sql` on the live project before first deploy
(distributor catalog read, pending-order edit policies, `phone_to_email`
RPC, `order_items.size`).

## Mobile quickstart

```sh
cd mobile
flutter pub get
flutter run
```
