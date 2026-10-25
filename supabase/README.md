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

## Model in short
- One household per person. `create_household()` makes the caller the owner and seeds the default categories.
- Clients cannot insert into `households`, `members` or `invites`; only `create_household`, `create-invite` and `redeem-invite` do.
- Roles are enforced by RLS only; the Flutter app mirrors them in `lib/features/family/domain/permissions.dart` to hide buttons.
- Codes: 8 characters from `23456789ABCDEFGHJKLMNPQRSTUVWXYZ`, stored as HMAC-SHA256 with `INVITE_PEPPER`, single use, 24 hours. Five wrong tries per person or twenty per IP in 15 minutes lock redeeming; ten new codes per person per hour.
