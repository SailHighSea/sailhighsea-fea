# Supabase backend

```
migrations/  schema, RLS policies, RPCs (apply in order)
functions/   create-invite, redeem-invite (Deno edge functions), _shared helpers
tests/       pgTAP tests for RLS and the invite functions
config.toml  local stack settings
```

## Set up a project
1. Create a project at supabase.com. Copy the **Project URL** and the **anon key** (never the service key) into `.env.json` at the repo root (gitignored, see `.env.example.json`).
2. Link and push the schema:
   ```
   supabase link --project-ref <ref>
   supabase db push
   ```
3. Secrets for the edge functions (`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided by Supabase). The pepper keys the invite-code hash; generate it once and keep it:
   ```
   supabase secrets set INVITE_PEPPER=$(openssl rand -hex 32)
   supabase functions deploy create-invite redeem-invite
   ```
4. Auth settings (Dashboard, Authentication):
   - Providers: Email on. Apple and Google if you want those buttons (Google and Apple need their own client ids).
   - URL configuration: add `app.familyexpenses://login-callback` to the redirect URLs.
   - Email template "Magic link": include `{{ .Token }}` so people can type the 6-digit code (works on every platform, including Windows and Linux where deep links are unreliable).

## Tests
```
supabase start
supabase test db                      # RLS + invite function tests (pgTAP)
deno test supabase/functions/_shared  # code generation and hashing
```

## Sync (Phase 4)
- `20261026000003_sync.sql`: a trigger stamps `updated_at` (and the moment of a soft delete) with server time on expenses, categories, budgets, goals and bills. Clients cannot choose it. Realtime is switched on for `expenses`, `categories` and `members`.
- The app pulls rows with `updated_at >= cursor` per table and pushes with update-then-insert. A role that may not write gets `42501` and the app shows the refused change.
- For Phase 4b: build the Google Sheets queue trigger on `public.expenses` AFTER INSERT OR UPDATE; `deleted_at is not null` means the row was deleted.

## Google Sheets mirror (Phase 4b)
Functions `sheets-connect` (owner: start and disconnect), `sheets-callback` (Google's redirect), `sheets-sync` (scheduled worker and Sync now). Tables `sheet_connections`, `sheet_oauth_states`, `sheet_sync_queue` and view `sheet_status` are in `20261027000004_google_sheets.sql`. The refresh token lives in Vault and is read only by edge functions. Setup steps: `docs/BUILD_AND_TEST.md`.

## Budgets, goals, bills (Phase 5)
`20261028000005_budgets_goals_bills.sql`: budgets use fixed text ids (`b:2026-10:overall`, `b:2026-10:<category>`) so two devices setting the same budget end up with one row; bills carry `next_due_on`; `goal_contributions` holds money added to goals (a goal's saved amount is `saved_cents`, its opening balance, plus the live contributions). Owner and admin write, every member reads. Tests: `supabase/tests/phase5.test.sql`.

## Member visibility (Phase 4c)
`20261029000006_member_visibility.sql`: `members.visibility` is `household` (default) or `own`. The `expenses_select` policy lets owner and admin read everything, household-visibility members read everything, and own-only members read only rows where `created_by` is them. Only owner and admin can change it, never their own. Budget rows with a `user_id` are per-person allowances (visible to that person and to owner and admin). Tests: `supabase/tests/visibility.test.sql`.

## Model in short
- One household per person. `create_household()` makes the caller the owner and seeds the default categories.
- Clients cannot insert into `households`, `members` or `invites`; only `create_household`, `create-invite` and `redeem-invite` do.
- Roles are enforced by RLS only; the Flutter app mirrors them in `lib/features/family/domain/permissions.dart` to hide buttons.
- Codes: 8 characters from `23456789ABCDEFGHJKLMNPQRSTUVWXYZ`, stored as HMAC-SHA256 with `INVITE_PEPPER`, single use, 24 hours. Five wrong tries per person or twenty per IP in 15 minutes lock redeeming; ten new codes per person per hour.
