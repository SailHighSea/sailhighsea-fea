# Building and putting outputs in `test/`

Claude Code does the compiling. After each phase run `scripts/build_test.sh` (macOS/Linux/Git Bash) or `scripts/build_test.ps1` (Windows). They build every target the current OS can build and copy results here:

```
test/
  android/   app-release.apk (and app-debug.apk)
  windows-x64/    folder with the .exe and DLLs (zipped as windows-x64.zip)
  windows-arm64/  same, built with --target-platform windows-arm64 when Flutter and the machine support it
  macos/     FamilyExpenses.app (zipped)
  linux/     bundle folder (tar.gz)
  ios/       Runner.app for simulator (Mac only; no signing needed)
  BUILD_REPORT.md   what was built, what was skipped and why, version, date
```

## Rules for Claude Code
- Run `flutter doctor -v` first and record the result in `BUILD_REPORT.md`.
- Build only what this OS supports; never fake an output. If a target is skipped, say why and what is needed.
- Use `--dart-define-from-file=.env.json` for Supabase keys (gitignored). Never copy `.env.json` into `test/`.
- After building, launch the host-OS build once (smoke test) and report what you saw. For Android, install on an emulator if one is available (`flutter emulators`).
- `test/` is for build output only; add it to `.gitignore` except `test/README.md`. Unit tests live in `tests/`.
- If something cannot compile because of a missing SDK or licence, tell the user the exact command to fix it.

## Targets not buildable here
Build them in CI. Phase 7 asks Claude Code to add `.github/workflows/build.yml` with matrix jobs: windows-latest (x64), windows-11-arm (Arm64), macos-latest (macOS + iOS simulator), ubuntu-latest (Linux + Android). Artifacts download into `test/` by hand or with `gh run download`.

## Google Sheets connection (Phase 4b): Google Cloud setup (manual, once)
The owner links a Google Sheet from the Family screen. The OAuth client lives on the server, so this is set up once for the whole project, not per device.

1. In Google Cloud Console create a project, then enable the **Google Sheets API**. (The app also needs the Drive scope `drive.file`, which needs no extra API toggle for files the app creates.)
2. **OAuth consent screen**: External. Add the scopes `.../auth/drive.file` and `.../auth/spreadsheets`. While the app is in **Testing**, only listed test users can connect and refresh tokens expire after 7 days (the app then shows "Google access was removed" and the owner reconnects). Publish the consent screen for real use and check Google's current verification rules for these scopes.
3. **Credentials**: create an OAuth client of type **Web application**. Authorised redirect URI: `https://<project-ref>.supabase.co/functions/v1/sheets-callback`.
4. Set the secrets on Supabase (never commit them):
   ```
   supabase secrets set GOOGLE_CLIENT_ID=... GOOGLE_CLIENT_SECRET=... SHEETS_CRON_SECRET=$(openssl rand -hex 32)
   supabase db push
   supabase functions deploy sheets-connect sheets-callback sheets-sync
   ```
5. Turn on the schedule (Dashboard, Database, Extensions: enable `pg_cron` and `pg_net`; Vault is on by default), then run once in the SQL editor with your values:
   ```sql
   select cron.schedule('sheets-sync', '30 seconds', $$
     select net.http_post(
       url := 'https://<project-ref>.supabase.co/functions/v1/sheets-sync',
       headers := jsonb_build_object('x-cron-secret', '<SHEETS_CRON_SECRET>', 'content-type', 'application/json'),
       body := '{}'::jsonb) $$);
   ```
   Changes then reach the Sheet 30 to 60 seconds after they are made. "Sync now" skips the wait.
6. Tests: `deno test supabase/functions/_shared` (worker, batching, backoff, PKCE, money) and `supabase test db` (who can read what, the queue trigger, Vault).
