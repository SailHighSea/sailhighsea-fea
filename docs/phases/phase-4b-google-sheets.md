# Phase 4b: Google Sheets connection (after Phase 4, about 1 week)

**Status:** Done and merged. Built (2026-10-27) against a fake Google. Still to do: Google Cloud setup (docs/BUILD_AND_TEST.md) and a real connect.

The household owner (the main admin) links one Google Sheet. Every expense in the household is mirrored into it automatically. Supabase stays the source of truth.

## Decisions (defaults, see PLAN.md "Open decisions")
- Who can connect: Owner only. Admins can see the status and press Sync now, but cannot connect, change or disconnect the sheet.
- Direction: one-way, app to Sheet. Edits typed into the Sheet are not read back and are overwritten on the next sync. The Sheet header says so.
- Google access: scope `drive.file` plus `spreadsheets`, so the app only touches the sheet it created or the owner picked. No access to the rest of Drive.
- Sheet: the app creates "Family Expenses - <household name>" by default. Linking an existing sheet is a later option.

## Do
1. **Data model** (Supabase migration): `sheet_connections` (household_id unique, owner_id, spreadsheet_id, status `active|error|revoked`, last_synced_at, last_error, created_at, updated_at) and `sheet_sync_queue` (household_id, expense_id, op `upsert|delete`, enqueued_at). RLS: only the household owner can select, insert, update or delete `sheet_connections`; Admins get read-only status through a view that hides token references. No client can read `sheet_sync_queue`.
2. **Google OAuth on the server, not the device.** Edge function `sheets-connect` runs the OAuth code flow (PKCE) for the owner. The refresh token is stored in Supabase Vault, never in Drift, never sent to any client, never committed. Client ID and secret come from Supabase secrets. Handle revoked or expired tokens by setting status `revoked` and showing a Reconnect banner to the owner.
3. **Sync worker.** Edge function `sheets-sync` triggered by a database trigger that writes to `sheet_sync_queue` on expense insert, update and soft delete, drained on a short debounce (about 30 seconds) and by a Sync now button. It batches with `values.batchUpdate` to stay under Google's write limits, uses exponential backoff on 429 and 5xx, and is idempotent.
4. **Sheet layout.**
   - `Expenses` tab: Date, Amount, Currency, Category, Merchant/Note, Added by, Account, Receipt link, Created, Updated, plus a protected hidden column `expense_id` used to find the row to update or delete.
   - `Summary` tab: formulas only (monthly totals, totals by category, totals by member) so the owner can build on it without breaking sync.
   - Amounts written as numbers in major units (cents divided by 100, done with integer math and formatted as a decimal string, never a float calculation). Soft-deleted expenses are removed from the sheet.
5. **First connect.** Backfill all existing expenses in chunks with a progress indicator. Re-running is safe because rows are keyed by `expense_id`.
6. **UI** in `lib/features/family` or a new `lib/features/integrations`: Settings row "Google Sheet" with states Not connected, Connecting, Connected (last synced time, Open sheet, Sync now, Disconnect), Error (Reconnect). One implementation, identical on every size (rule 1). Non-owners see the state read-only. Disconnect revokes the token at Google and deletes the Vault secret; the sheet itself is left in the owner's Drive.
7. **Privacy copy.** Before connecting, show plainly what is sent to Google: expense details of all members, including who added each. The owner confirms.
8. **Tests** (in `tests/`): queue enqueue on create, edit, delete; batching and idempotent re-run; amount formatting from cents with no float drift; RLS (editor, viewer and admin cannot connect or read tokens); revoked-token handling; backfill resume after failure. Use a fake Google client.
9. Build to `test/` and report, as in every phase.

## Done when
The owner connects Google once. A new, edited or deleted expense from any family member shows up in the Sheet within about a minute, a revoked connection is reported clearly in the app, and no Google token ever reaches a client device.

## Things to know before building
- **Google verification.** While the OAuth app is in "Testing" in Google Cloud, only listed test users can connect and refresh tokens expire after 7 days. Production use needs the consent screen published; `drive.file` is a lower-friction scope than full Drive but still check Google's current verification requirements.
- **Google Cloud setup is manual** (project, OAuth client, enabled Sheets API). Document the steps in `docs/BUILD_AND_TEST.md`.
- **Quota.** Sheets API write limits are per user and per minute, which is why writes are batched and debounced.
