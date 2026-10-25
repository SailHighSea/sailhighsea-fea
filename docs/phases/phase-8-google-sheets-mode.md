# Phase 8: Google Sheets mode (no server)

**Status:** Not started. Planned 2026-10-25 from the design agreed in chat. Do not start before the Phase 4c pull request is merged.

## Goal
The app can run entirely on Google Drive and Google Sheets, with no Supabase project. Each family member signs in with their own Google account and keeps their own expense sheet. The father (the household owner) pairs with each member using a code, gets read access to that member's sheet, and the app brings those expenses in. Supabase stays in the code, switched off, so the server mode can come back (see "Switching modes").

## Core idea: one writer per sheet
- A member's app is the only writer of that member's sheet. The father's app only reads it. So there are no sync conflicts.
- Access control is Google Drive sharing: the member shares their sheet read-only with the father's Google account. Nothing else controls access (no server, no Row Level Security).
- The local database stays what the UI reads (rule 5). Sheets are the transport and the backup.
- The father sees every member; members see only themselves and the household sheet. (Other members' spending is never shared with them.)

## Decisions (agreed)
1. **Supabase: keep.** It stays in the code and in the repo, off by default in this mode, and a build flag selects the mode. Nothing is deleted.
2. **Budgets, goals and bills: members can suggest changes.** The father owns them (household sheet). A member writes a suggestion into a `Suggestions` tab of their own sheet (add or change a budget, goal or bill, with a note). The father sees a list of suggestions in the app and approves or declines each one; an approved one is applied to the household sheet. Members read the household sheet but cannot change it.
3. **Other members: father only.** Only the father sees everyone's spending. Members never get each other's sheets.
4. **Father's edits: none for now.** Member expenses are read-only in the father's app. To change one, the member changes it.

## Sheets
- **Member sheet** `Family Expenses - <name>` (created by the member's app): tabs `Expenses` (expense_id, date, amount, currency, category, note, receipt, created, updated, deleted flag), `Categories`, `Suggestions`, `Pairing` (household id, father's email, the random pairing value, date paired). Amounts are written from integer cents with integer maths, as in Phase 4b.
- **Household sheet** `Family Household - <name>` (created by the father's app): tabs `Members` (who is paired), `Budgets`, `Goals`, `Bills`, `Categories`. Shared read-only with each paired member.
- The sheet is a mirror of the app: edits typed into a sheet are overwritten on the next sync, and the sheet says so in its header.

## Pairing (three steps, no server)
1. **Father shows a code**: his Google email, the household sheet id and a random value, as a QR code and as text to copy. Valid 24 hours (checked by the apps, not enforceable by a server).
2. **Member scans or pastes it.** The app shows "Share your expenses with <email> (read only)?". On yes it shares their sheet read-only with the father through the Drive API and writes the `Pairing` tab. It then shows the member's own code: their sheet id, their email, their name and the same random value.
3. **Father scans or pastes the member's code.** The app checks the sheet exists, that its owner matches the email in the code and that the `Pairing` tab holds the random value, then saves the member and starts reading. The app also shares the household sheet read-only with the member's email.
- The member can unpair at any time (removes the father's access); the father can unpair a member (removes the household sheet access and stops reading). Past imported expenses stay unless the father removes them.
- Pairing is one-to-one (member to household). Joining a different household means unpairing first.

## Do
1. **Docs first.** Update `CLAUDE.md`, `PLAN.md` and `docs/SPEC.md` for this mode: no RLS, Drive sharing as access control, roles reduced to owner and member, codes without hashing, tokens on the device. List what does not apply in Sheets mode.
2. **Mode switch.** `--dart-define=BACKEND=sheets|supabase|local`. Supabase mode and local mode behave exactly as today. Sheets mode uses the new code below. One implementation per feature (rule 1): only the data source changes, never the screens.
3. **Google sign-in on every platform** (`lib/core/google`): `google_sign_in` on Android, iOS and macOS, a browser sign-in with a loopback redirect and PKCE on Windows and Linux. Scopes `drive.file` and `spreadsheets`. Tokens in the platform secure store (`flutter_secure_storage`), never in Drift or in logs. Handle a revoked or expired grant with a Reconnect prompt.
4. **Member writer** (`lib/core/sheets_sync`): create the member sheet, push every local change in batches with backoff on 429 and 5xx, idempotent by `expense_id`, soft deletes as a flag. Reuse the layout, money and backoff code from the Phase 4b edge function where possible (port to Dart).
5. **Pairing screens** (`lib/features/pairing`): father "Invite a family member" (code and QR), member "Join with a code" (scan or paste, confirmation of what is shared), father "Add member" (scan or paste the member's code), members list with status and Unpair. Camera or file picker only for the QR (platform code allowed for hardware only).
6. **Father reader**: poll each paired member's sheet (every few minutes, on app open and on pull to refresh) and merge by `expense_id` into Drift with the member as the owner of the rows; read-only in the UI. Detect changes cheaply (sheet revision or a changed-rows range) and read in pages. A sheet that is gone or unshared shows "Access removed" for that member and stops importing.
7. **Household sheet**: the father's app writes budgets, goals, bills and categories to the household sheet; members' apps read it and keep it in Drift read-only.
8. **Suggestions**: member "Suggest a change" for a budget, goal or bill (writes a row to `Suggestions`); father "Suggestions" inbox in the app with Approve and Decline, applying approved ones to the household sheet. Members see the status of their suggestions.
9. **Overview and filter (Phase 4c)** work as they are in this mode, for the father only; members never see the "Everyone" views.
10. **Tests** with a fake Google client (fake Sheets, fake Drive permissions, fake sign-in): pairing happy path and wrong or expired code, share and unshare, member push (batching, idempotent re-run, backoff, revoked token), father import (new, edited, deleted rows, a sheet that vanishes), suggestions flow, mode switch keeps Supabase mode working, no token in logs or Drift. Run `flutter analyze` and `flutter test`; build every target this machine supports.
11. **Docs for the Google Cloud setup**: one OAuth client for the app (installed-app type), consent screen published to "In production" so tokens do not expire after 7 days (unverified-app warning, 100-user limit, enough for a family), scopes, test users while in Testing.

## Switching modes
- A build chooses the mode. Moving an existing install between Supabase and Sheets mode is not part of this phase (data stays in the local database; a later phase can add an export from one mode and an import into the other).

## Limits to say plainly in the app and docs
- Updates reach the father after the next poll (minutes), not live.
- Without a server nothing enforces who may write: a member owns their sheet and could change it by hand; the app overwrites such edits on its next push, and the father should treat a member's sheet as that member's data.
- Google quotas apply (read and write limits per user and per minute); polling and batching are designed to stay far below them for a family.
- The pairing code can be copied by anyone who sees it; sharing only happens after the member confirms it, so a stolen code gives nothing by itself.

## Done when
Two or more people each sign in with their own Google account and add expenses. The father pairs with each using a code, sees every member's expenses in his overview within a few minutes, and a member's suggested budget change appears for his approval. No server is configured and no Google token leaves the device.

## Open decisions (defaults in brackets)
1. Poll interval for the father's reader [every 5 minutes while the app is open, and on open and pull to refresh].
2. What the father sees if a member unpairs [past imported expenses stay, marked "no longer shared"].
3. Whether members can see the household sheet's budgets and goals [yes, read-only].
4. Whether a member can have a sheet shared with a second adult (for example the mother) [no, one household owner for now].
