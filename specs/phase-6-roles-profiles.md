# Phase 6 — Roles and Profiles (Single Company)

## Problem Statement

The app has one company with three kinds of people — admin, employee, customer — but identity today is a bare login with no role, no display names, and no phone. The owner wants the admin to be the only person who can bring new employees and customers into the system, and every later rule (who sees invoices, who reads orders, who may invite) depends on a trustworthy role. Without a single source of truth for role + names + phone, every future phase re-invents access checks and duplicate users appear.

## Solution

Introduce a profiles directory as the source of truth for who everyone is, with the login identity kept deliberately simple: a synthesized email derived from the English name plus a random suffix (phone remains the real-world unique key; phone-OTP is rejected for cost/coverage reasons; optional linking of a real email comes later). The role is stored once in profiles and mirrored once into the auth token metadata as a fast copy for database access rules. The single admin is bootstrapped by a one-time scripted backfill and verified before any invites flow.

## User Stories

1. As the owner, I want exactly three roles (admin, employee, customer), so that permissions stay explainable.
2. As the admin, I want to be the only account that can create new users, so that no stranger can self-register.
3. As the admin, I want to record Arabic name, English name, phone, and role for each invitee, so that staff and customers are identifiable in both languages.
4. As the admin, I want phone numbers to be unique across all users, so that one WhatsApp number never maps to two logins.
5. As the admin, I want a clear error when I retry an already-invited phone ("already invited — use resend"), so that I never create ghost duplicates.
6. As the admin, I want the very first admin account to be created through a verified one-time procedure, so that the chain of trust has a known root.
7. As an employee, I want my Arabic and English names visible wherever my work appears, so that colleagues recognize me.
8. As a customer, I want my business identity (names + phone) recorded once, so that the web app and the Flutter app agree on who I am.
9. As the owner, I want the role check to be fast for every database query, so that access rules do not slow down reads.
10. As the owner, I want names and phones changeable without breaking login identity, so that spelling fixes never orphan accounts.
11. As a logged-out user, I want the app to keep working offline exactly as before, so that identity work never blocks invoicing.
12. As the owner, I want direct public sign-up disabled, so that the invite path is the only door in.

## Implementation Decisions

- Roles are a closed set: admin, employee, customer. No custom roles in this phase.
- New profiles directory with one row per login identity: stable login id, role, name in Arabic, name in English, phone (unique), synthesized email (unique), creation timestamp. This directory is the source of truth for human identity; the auth record is only the credential.
- Login identity stays email/password using the existing authentication module seam (no new auth provider, no SMS/OTP vendor). The synthesized email is formed by a deterministic slug of the English name (lowercase, spaces to dots, strip diacritics/specials) plus a short random suffix that is only regenerated on collision. Real-email linking is deferred, not built here.
- Role mirroring: the authoritative role lives in profiles; a copy is written into the auth token metadata at invite/bootstrap time purely so row-level access rules can read it from the token without extra joins. Any role change must update both in the same operation; on disagreement the token copy is treated as stale and profiles wins at the next refresh.
- Admin bootstrap is a two-step root ceremony: create the login via the dashboard user control, then run a single transactional backfill that upserts the profiles row and the token-metadata role together, then verify with a read-back query. No invites may be issued until that verification passes.
- Uniqueness is enforced at the database level on both phone and synthesized email, not just in app validation, so parallel admin sessions cannot race duplicates.
- The existing offline-first invariants are untouched: login remains optional and never gates local invoicing; logout clears session only, never business data.
- Seam choice: extend the existing authentication module (current-user stream, cached owner id) rather than a new identity abstraction. Repositories keep their current shape; they never import auth directly.

## Testing Decisions

- Good tests assert externally visible identity behavior, not token internals: role of a user, uniqueness rejection message, bootstrap verification result.
- Tested: duplicate phone rejected with the resend hint; duplicate synthesized email impossible (suffix regenerates); role copy matches profiles after invite and after bootstrap; app still fully usable offline and logged out; direct sign-up path is closed.
- Prior art: existing auth-boundary tests using a fake auth client (session restore, logout preserves local rows, offline sign-in surfaces a message) are extended with role/profile fakes at the same seam.

## Out of Scope

- The invite link itself and its delivery (next phase). Rewriting the five business-table access rules for shared-company access (later phase). Password recovery flows (covered with the invite pipe, later phase). Real-email linking UI. Phone-OTP or any SMS vendor. Multi-company support. Conflict UI.

## Further Notes

- Decided: single company, single tenant — no company id is introduced; if a second company ever appears this directory must gain one and every access rule must be revisited.
- Decided: phone-OTP rejected for this build (no free no-credit provider covering the owner's location); revisit only if SMS economics change.
- Decided: deterministic slug plus random suffix keeps fake emails human-readable for support ("which mohammad.ahmad is this?") while guaranteeing uniqueness.
