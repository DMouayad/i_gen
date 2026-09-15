# AGENTS.md — i_gen working standards

## Workflow

- **Permission first.** No destructive or mutating operations without an explicit user go-ahead: no `git commit`/`push`/`amend`, no history rewrites, no `flutter pub upgrade` beyond what was approved, no deleting files outside the approved scope.
- **Verify everything.** After any code change run `flutter analyze` (must be 0 errors, 0 warnings; pre-existing `info` lints are left alone) and the relevant `flutter test` files. Full `flutter test` before declaring a work unit done.
- **One seam per change.** Prefer existing seams (repository methods, the outbox, `SyncTrigger`) over new abstractions. Parallel agents split by file ownership; overlapping seams get reconciled, not duplicated.

## Architecture invariants (offline-first + Supabase sync)

- **Source of truth for sync schema/constants is `DbConstants` (`lib/db.dart`).** No mirror contract classes. If two files define the same table/column names, delete one.
- **One-direction dependency: engine/UI → repos.** Repositories never import `lib/sync/*` or `lib/auth/*`. They enqueue via `SyncMetadata`/`SyncTrigger` only.
- **Local integer PKs stay; `remote_id` is the shared identity.** Never change a `_id` on conflict paths (`REPLACE` is banned on synced tables — it orphans `remote_id`s). Update-in-place, preserve ids.
- **Deletes are soft (`is_deleted=1` + outbox `delete` op).** Hard delete happens only after server ack (engine) or 30-day tombstone purge (maintenance). No hard deletes from UI paths.
- **Outbox ops are idempotent by `op_id`.** `client_op_id` is UNIQUE server-side; retries must never duplicate.
- **Checkpoints advance only over merged rows.** Skipped rows are counted, logged, and retried — never silently dropped, never wedging the cursor.
- **Login is optional, never blocking.** The app works fully offline and logged out. Logout clears session only, never business data.

## What we don't do

- No drift migration (sqflite stays). No PowerSync / community sync wrappers. No Supabase Realtime yet (reconnect-pull is the freshness mechanism). No conflict UI — last-write-wins is silent by decision.
- No new dependencies without approval. No speculative generality: build what the specs (`specs/`) ask, nothing more.

## Specs

- `specs/phase-*.md` are the source of truth for sync work. If code and spec disagree, fix the code — or get approval to change the spec, then change both.
