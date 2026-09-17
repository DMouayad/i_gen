# AGENTS.md — i_gen working standards

## Layout

- **The Flutter app lives in `mobile/`.** Run `flutter` commands with workdir `mobile/`; app paths below are relative to it (`mobile/lib/…`). Repo-level dirs (`specs/`, `supabase/`) stay at root.
- **The distributor web app lives in `web/`** (Next.js 16, Vercel root = `web/`). Run `pnpm` commands with workdir `web/`. Same Supabase project as mobile; `supabase/schema.sql` is the shared server contract for both.

## Web workflow

- **Toolchain:** pnpm via corepack (version resolves per-directory from `web/package.json` `packageManager`, currently 12.4.1 — keep the pin). Registry is slow here; prefer `--prefer-offline`, and approve new build scripts with `pnpm approve-builds <pkg>` (non-interactive) instead of fighting the gate.
- **Verify everything (web):** after any web change run `pnpm exec tsc --noEmit` (0 errors) + `pnpm exec eslint` (0 errors, 0 warnings) + `pnpm build`. No live Supabase needed: pages degrade to the config notice without env vars.
- **Scope:** distributor-only (catalog + cart + own orders). No prices surface anywhere (distributors order blind, `price: 0`); no admin/employee screens. Bilingual EN/AR via `web/lib/i18n.tsx` (hand-rolled dict — no next-intl). Client components + supabase-js browser client only: no `middleware.ts`/SSR auth (avoids the Next 16 proxy migration entirely).
- **Server changes ship with both apps:** any column/policy the web writes must already exist live — add to `supabase/schema.sql` AND the commented live-upgrade block at its bottom, and run the block on the live project before deploying web.

## Workflow

- **Permission first.** No destructive or mutating operations without an explicit user go-ahead: no `git commit`/`push`/`amend`, no history rewrites, no `flutter pub upgrade` beyond what was approved, no deleting files outside the approved scope.
- **Verify everything.** After any code change run `flutter analyze` (must be 0 errors, 0 warnings; pre-existing `info` lints are left alone) and the relevant `flutter test` files. Full `flutter test` before declaring a work unit done.
- **One seam per change.** Prefer existing seams (repository methods, the outbox, `SyncTrigger`) over new abstractions. Parallel agents split by file ownership; overlapping seams get reconciled, not duplicated.

## Architecture invariants (offline-first + Supabase sync)

- **Source of truth for sync schema/constants is `DbConstants` (`mobile/lib/db.dart`).** No mirror contract classes. If two files define the same table/column names, delete one.
- **One-direction dependency: engine/UI → repos.** Repositories never import `mobile/lib/sync/*` or `mobile/lib/auth/*`. They enqueue via `SyncMetadata`/`SyncTrigger` only.
- **Local integer PKs stay; `remote_id` is the shared identity.** Never change a `_id` on conflict paths (`REPLACE` is banned on synced tables — it orphans `remote_id`s). Update-in-place, preserve ids.
- **Deletes are soft (`is_deleted=1` + outbox `delete` op).** Hard delete happens only after server ack (engine) or 30-day tombstone purge (maintenance). No hard deletes from UI paths.
- **Outbox ops are idempotent by `op_id`.** `client_op_id` is UNIQUE server-side; retries must never duplicate.
- **Checkpoints advance only over merged rows.** Skipped rows are counted, logged, and retried — never silently dropped, never wedging the cursor.
- **Login is optional, never blocking.** The app works fully offline and logged out. Logout clears session only, never business data.
- **Server schema and app ship together.** Never push a column the server lacks: unknown-column pushes fail and the op parks (5-strike rule), so run the `supabase/schema.sql` alters before releasing the app version that writes the column. Same for restore: a restored backup replays its outbox, which must match the live server schema.
- **Backup/restore is file-level.** Whole-`.db` copy via `BackupService` (`mobile/lib/repos/backup_service.dart`); post-restore always close → swap → reopen via `DbProvider.open` → re-seat GetIt → `syncNow()`. One `pre-restore` fallback is kept, validation runs before any swap.

## What we don't do

- No drift migration (sqflite stays). No PowerSync / community sync wrappers. Supabase Realtime is orders-only (new-order alerts via the order watcher; the sync domain stays reconnect-pull). No conflict UI — last-write-wins is silent by decision.
- No new dependencies without approval. No speculative generality: build what the specs (`specs/`) ask, nothing more.

## Specs

- `specs/phase-*.md` are the source of truth for sync work. If code and spec disagree, fix the code — or get approval to change the spec, then change both.
