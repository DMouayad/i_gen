# Phase 9 — Flutter Admin Invite Screens and Link Handling

## Problem Statement

The invite pipe and access rules are useless without an admin surface in the app the owner actually uses: today there is nowhere to invite an employee, nowhere to resend a lost WhatsApp link, nowhere to recover a locked-out user, and no handling when an employee taps the link and lands in the app. Employees also need the app to honestly reflect their narrower permissions instead of letting them tap into a server rejection.

## Solution

Add a small admin-only area to the existing settings/login surface for inviting, resending, and recovering users, plus link-accept handling for employees and role-aware gating of the existing invoicing UI. The admin fills four fields, gets back a link with a copy-for-WhatsApp action, and sees the same one-click path for resend and lockout recovery. Employees open their link in the app, set their password, and land signed in; everyone else sees loud, plain recovery guidance. Catalog edit controls disappear for employees rather than failing on tap.

## User Stories

1. As the admin, I want an invite form (Arabic name, English name, phone, role) visible only to me, so that inviting takes under a minute.
2. As the admin, I want the result to show the synthesized login plus a copy-for-WhatsApp action, so that forwarding is one tap.
3. As the admin, I want inline errors for duplicate phones and offline state, so that I know whether to resend or retry.
4. As the admin, I want a resend action on each person that issues a fresh link without retyping, so that expired links cost seconds.
5. As the admin, I want a recover action for a locked-out user that issues a fresh set-password link, so that no email is ever needed.
6. As an employee, I want to tap my WhatsApp link, open the app, set my password, and land signed in, so that onboarding just works.
7. As an invitee opening an expired or reused link, I want "link expired — ask the admin for a new one", so that I know exactly what to do.
8. As an employee, I want catalog edit buttons hidden or disabled with a read-only explanation, so that I never hit a surprise rejection.
9. As a distributor opening this app, I want guidance toward the web app rather than invoicing screens, so that I do not work in the wrong place.
10. As any user, I want sign-in to accept my (possibly synthesized) email and password with the same offline messaging as today, so that login feels unchanged.
11. As a signed-in user, I want to see who I am signed in as and my role, so that shared devices stay unambiguous.
12. As the owner, I want non-admins to never see the invite controls even if they navigate directly, so that hiding buttons is not the only defense.

## Implementation Decisions

- The invite surface lives in the existing settings/login area as an admin-only section (one entry point, consistent with the "login never blocks" rule), reusing the authentication module seam for session, role, online-check, and error mapping. No new navigation root, no new auth provider.
- Screens are thin: they collect four fields, call the trusted invite/resend/recover operations, and render link + copy action or human-readable error. Phone formatting and English-name slugging preview happen client-side for typo-catching, but uniqueness is enforced server-side.
- Link handling: the app registers its invite-callback deep link; opening it completes verification, prompts for the new password, and signs the user in through the standard session path (persisted session, cached owner id for the sync engine). The web destination is never handled here.
- Role gating mirrors the database matrix: admin sees everything; employee sees invoices fully but products, prices, and categories read-only (edit affordances hidden/disabled with explanation); distributor credentials see guidance toward the web app. Gating is UI convenience only — the database remains the enforcer.
- Copy is bilingual where names are involved (Arabic + English shown together); status and error strings reuse the existing localization mechanism.
- Existing invariants hold: everything works offline and logged out except the network-dependent invite/resend/recover/accept calls, which fail fast with a friendly offline message; logout clears session only, never business data; no new dependencies.

## Testing Decisions

- Good tests assert behavior at the module boundary (which controls are visible per role, which message appears per failure), not platform deep-link or mailer internals.
- Tested: invite form hidden for employee and distributor roles; successful invite shows link plus copy action; duplicate phone shows the resend hint; resend reuses identity without new entry; expired-link open shows the ask-admin message; employee catalog controls are read-only while invoice controls remain writable; offline invite attempt surfaces a message instead of hanging; logout still preserves local rows.
- Prior art: existing widget tests with the tester harness for rendering and taps, plus auth-boundary tests with a fake auth client, are extended at the same seams; deep-link verification itself is exercised manually once per platform rather than mocked.

## Out of Scope

- The server function and database rules themselves (adjacent phases). Orders and distributor-list screens (dedicated phase). Real-email linking UI. Password-strength meters beyond the platform default. Multi-device session management. Any sync-engine changes beyond consuming the already-cached owner id.

## Further Notes

- Decided: admin section inside settings rather than a new top-level destination — one entry point keeps the offline-first "never lock the app behind login" promise visible.
- Decided: hide/disable over tap-then-reject for employee catalog controls — fewer dead ends, and the database still rejects any forged write.
- Decided: exact expired-link wording is part of the contract ("ask the admin for a new one") so that support, app, and web app all say the same sentence.
