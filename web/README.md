# Distributor web app (Next.js 16)

Distributor-only: catalog + cart, order history, pending-order edit. EN/AR,
no prices surface. See the root `README.md` and
`specs/phase-12-distributor-web.md`.

```sh
cp .env.example .env.local  # Supabase URL + anon key
pnpm install
pnpm dev                    # pnpm exec tsc --noEmit && pnpm exec eslint && pnpm build
```

Vercel: project root = `web/`.
