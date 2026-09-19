# Phase 7 — Admin Invite Pipe (WhatsApp Link, No Email)

## Problem Statement

The synthesized login emails cannot receive mail, so the built-in "send invitation email" flow dead-ends: the message would go to an inbox that does not exist. The admin still needs a way to hand a new employee or customer their account over WhatsApp, and the invitee needs to set their own password without any secret living forever in chat history. Temporary passwords dictated in chat are the easy answer and the wrong one.

## Solution

Use the auth platform's native link generator in invite mode, which creates the login (if needed) and returns a one-time accept link without sending any email. A thin trusted server function, callable only by admins, wraps that generator: it validates the request, writes the profiles row and role metadata, picks the destination per role, and hands the link back for the admin to forward via WhatsApp. The same pipe is reused for lockout recovery and for resending expired links. No custom token table is introduced.

## User Stories

1. As the admin, I want to enter Arabic name, English name, phone, and role and get back a single invite link, so that I can forward it over WhatsApp in seconds.
2. As the admin, I want the invite call rejected unless I am an admin, so that a leaked app session cannot mint users.
3. As an employee invitee, I want my link to open the Flutter app's invite-accept flow, so that I set my password where I will work.
4. As a customer invitee, I want my link to open the web app's welcome page, so that I set my password where I will order.
5. As an invitee, I want to choose my own password on first open, so that no secret is ever stored in chat history.
6. As the admin, I want a duplicate-phone attempt to fail with "already invited — use resend", so that I resend instead of duplicating.
7. As the admin, I want a one-click resend for the same login that issues a fresh link without new data entry, so that expired or lost links cost seconds.
8. As an invitee opening an expired or already-used link, I want a plain message ("link expired — ask the admin for a new one"), so that I never stare at a cryptic error.
9. As a locked-out user, I want the admin to issue me a fresh recovery link through the same WhatsApp pipe, so that forgotten passwords do not need email.
10. As the owner, I want invite links to be short-lived and single-use, so that forwarded screenshots decay quickly.
11. As the owner, I want no email-sending path for these logins anywhere in the flow, so that fake addresses never touch a mail queue.
12. As the admin working offline, I want a clear offline message instead of a hang, so that I know to retry when connected.

## Implementation Decisions

- Native invite-link generation (invite mode) is used; the email-sending invite variant is explicitly not used because the addresses are not real inboxes.
- The secret-key admin call never runs on-device. One trusted server function owns it, with this contract: input is names + phone + role; it authenticates the caller, asserts the caller role is admin, enforces phone/email uniqueness, creates or reuses the login, writes profiles plus token-metadata role atomically, generates the link with the per-role destination baked in, and returns the link plus the synthesized email. All validation failures return human-readable reasons the app can show verbatim.
- Destination is chosen per role at creation time: employees resolve to the Flutter app deep-link callback; customers resolve to the web app welcome URL. Both destinations are pre-registered in the auth redirect allow-list; unlisted destinations are never honored. No runtime device sniffing and no shared router page.
- Recovery reuses the same function family with recovery/magic-link mode for the same login identity — no separate credential-reset infrastructure, no emailed recovery in this phase.
- Resend is generation again for the existing login, never a second user. Expired/used links fail loud in the app and on the web with the exact "ask the admin" wording.
- The function stamps creation metadata so support can tell "never opened" from "expired after opening".
- Seam choice: the Flutter app calls the server function through the existing authentication module seam (same online-check and error-mapping behavior as sign-in); repositories are untouched — inviting creates identity, never business rows.

## Testing Decisions

- Good tests assert the externally visible contract: link returned for valid admin input, rejection for non-admin caller, duplicate-phone hint, per-role destination, expired-link message.
- Tested: non-admin call rejected; duplicate phone returns resend hint and creates nothing; employee link targets the app callback and customer link targets the web URL; resend for the same login yields a working link without duplicating identity; recovery link for a known login works and for an unknown login fails cleanly; offline attempt surfaces a message instead of hanging.
- Prior art: auth-boundary fakes (fake auth client, fake connectivity) are reused; the server function is tested against a preview project with two roles, never against production.

## Out of Scope

- The Flutter invite/resend screens themselves (next phase). The shared-company rewrite of business-table access rules (later phase). Real-email linking. Custom SMS/OTP vendors. A custom invitations/token table or expiry cron — expiry is the platform default plus resend. Multi-company routing.

## Further Notes

- Decided: invite-by-email-sending rejected — verified against platform docs that it sends to the address, which cannot work for synthesized addresses; generation-without-sending is the only native fit for WhatsApp delivery.
- Decided: link expiry uses the platform default email-link lifetime; if support load shows users routinely open links late, the lever is a longer platform expiry plus resend, not a homegrown token store.
- Decided: no secret ever travels in WhatsApp — only the one-time link; whoever holds chat history after redemption holds nothing reusable.
