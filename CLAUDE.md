# Project rules (read every session)

You are building the Family Expense Tracker described in PLAN.md and docs/SPEC.md. Mockups are in design/screenshots (look at them) and design/mockups (HTML for exact values).

## Stack
Flutter (stable) + Dart, Riverpod, go_router, Drift (SQLite, local-first), Supabase (Postgres, Auth, Realtime, RLS), fl_chart, local_auth, intl, freezed/json_serializable.

## Non-negotiable rules
1. **One feature, one implementation.** Features live in `lib/features/<name>` and must behave identically on every device. Only `lib/core/layout` may depend on window width. Platform-specific code is allowed only for hardware: receipt capture (camera vs webcam or file picker), app lock, notifications, keyboard shortcuts.
2. **Layout by window width, not device type:** under 600dp bottom tabs; 600 to 1199dp side rail (96px); 1200dp and up full sidebar (240px); foldable half-open: content above the hinge, form below. Use `MediaQuery`/`LayoutBuilder` and `DisplayFeature` for hinge.
3. **Home must look the same in every theme** (Light, Dark, Pure black) and on every size. Only tokens change (docs/SPEC.md section 2). No hard-coded colours outside `lib/core/theme`.
4. **Money is integer cents.** Never use double for money. Format with intl.
5. **Local-first.** UI reads from Drift. Sync pushes and pulls in the background. Soft delete + `updated_at`, last-write-wins.
6. **Permissions enforced on the server** with Supabase RLS, never only in the UI.
7. **Invite codes:** 8 characters, alphabet without 0 O 1 I, stored hashed, single use, expire in 24 hours, carry a role, rate-limited.
8. Tap targets at least 44px. Support large text. Charts must be colour-blind friendly (option in Appearance).
9. Write tests with each feature. Run `flutter analyze` and `flutter test` before saying a phase is done.
10. Never commit secrets. Supabase URL and anon key come from `--dart-define` or `.env` (gitignored).

## Backend modes (Phase 8)
`--dart-define=BACKEND=sheets|supabase|local` picks the data source; without it the app uses Supabase when it is configured, otherwise local only. **Supabase and local modes behave exactly as above.** In `sheets` mode there is no server, so some rules above do not apply:
- Rule 6 (RLS) and rule 7 (hashed, rate-limited invite codes) do not apply: Google Drive sharing is the only access control, roles are reduced to organiser (owner) and member (editor who may suggest changes), and pairing codes are checked by the apps (24-hour expiry, single use) and are not hashed.
- Rule 5 still holds: the UI reads Drift; Google Sheets are the transport and the backup. One writer per sheet, so no conflicts.
- Tokens live in the platform secure store (`flutter_secure_storage`), never in Drift, prefs or logs.
- One implementation per feature still holds: only the data source changes (`lib/core/google`, `lib/core/sheets_sync`, `lib/features/pairing`); no screen forks by mode except the Family page.

## Working style
- Work one phase at a time from docs/phases. Do not start the next phase unprompted.
- At the end of each phase: run analyze and tests, build every target this machine supports using `scripts/build_test.sh` (or `.ps1` on Windows), put outputs in `test/`, and report what was built, what was skipped and why, and how to run each build.
- If a decision is listed under "Open decisions" in PLAN.md, use the recommended default, note it in your report, and keep it easy to change.
- Keep a `CHANGELOG.md`; update it each phase.
