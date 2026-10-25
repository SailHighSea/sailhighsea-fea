# Plan

## Product
A family shares one household and tracks monthly spending together. The owner invites members by code and decides what each can do.

## Roles
| Role | Can do |
|---|---|
| Owner | Everything, including transfer ownership and delete the household |
| Admin | Everything the owner can, except remove the owner, delete the household, or transfer ownership (recommended default) |
| Can edit | Add, edit and delete expenses; manage own entries; view everything |
| View only | See everything, change nothing |

The owner can promote any member to Admin and change roles at any time.

## Feature list (identical on every device)
Family overview (owner sees every member's spending, per-person drill-down) · Home dashboard (ring, 7-day or month bars, top categories, next bill, goal, recent) · Add expense (manual) · Scan receipt · Budgets (overall and per category) · Insights (bar charts, trends, category breakdown, who spent what) · Savings goals · Recurring bills with reminders · Family and invites · Appearance (System, Light, Dark, Pure black; colour themes Forest, Ocean, Sunset, Graphite; larger text; colour-blind charts; currency) · Export CSV · Google Sheet sync (owner connects a sheet, expenses mirror into it) · App lock.

## Architecture
```
lib/
  core/        theme, layout (adaptive shell), routing, db (Drift), sync, supabase client, money
  features/    home, expenses, budgets, insights, goals, bills, family, appearance, scan
  l10n/
supabase/      migrations, RLS policies, edge functions (create-invite, redeem-invite, sheets-connect, sheets-sync)
test/ (project root `test/` is for BUILD OUTPUTS, unit tests live in `tests/`)
```
Note: Flutter normally uses `test/` for unit tests. In this project **`test/` holds compiled builds** as requested, so put automated tests in `tests/` and set the test path accordingly (`flutter test tests/`).

## Phases
Updated 2026-10-25. **Done** = the code and its automated tests are finished and merged into `main`. **Still to verify** = checks that need real services or devices (they cannot be done in the cloud build machine). Details per phase are in `CHANGELOG.md` and `docs/phases/`.

| # | Phase | Done? | Still to verify (not done yet) |
|---|---|---|---|
| 1 | Foundations | Done (merged) | Windows, macOS and Android builds open and run (only Linux was built here) |
| 2 | Core expenses | Done (merged) | |
| 3 | Accounts and household | Done (merged) | `supabase test db` and `deno test` run; two real accounts joining one household with a code |
| 4 | Sync | Done (merged) | Two real devices against a real Supabase project (tested only against a fake server) |
| 4b | Google Sheets connection | Done (merged) | Google Cloud setup and one real connect (tested only against a fake Google) |
| 4c | Family overview | Done (merged, PR #3) | `supabase test db` for the visibility rules; a real owner plus an own-only member |
| 5 | Budgets and insights | Done (merged, PR #2) | `supabase test db`; a real bill reminder on a phone; Windows image tests (`PHASE5_GOLDENS=1`); Android, iOS and macOS builds with notifications. The macOS build failed in CI and two fixes are waiting for the next pull request |
| 6 | Adaptive layouts and scan | Done (this branch, not merged) | `supabase test db` for the receipts bucket; a real phone camera and ML Kit read; a real upload to Supabase Storage; window minimum size on Windows and macOS; fold on a real foldable; Android, iOS and macOS builds (new plugins `image_picker`, `google_mlkit_text_recognition`) |
| 7 | Polish and release | Done (this branch, not merged) | Real biometrics; the Windows Arm64 and iOS CI steps; final icon artwork; publisher name and contact in the privacy policy; every store step in `docs/RELEASE.md` (nothing was published) |
| 8 | Google Sheets mode (no server) | Done (this branch, not merged; plan: `docs/phases/phase-8-google-sheets-mode.md`) | One real Google Cloud project and two real Google accounts pairing (everything was tested against a fake Google); the sign-in flow in a real browser on each platform; QR scan on a phone; the Android, iOS and macOS builds with `flutter_secure_storage` and `mobile_scanner`; Windows and macOS runs |

## Open decisions (defaults in brackets)
1. Admin vs owner differences [Admin cannot remove owner, delete household or transfer ownership].
2. Can editors change budgets and goals? [No: Admin and Owner only].
3. Show who added each expense? [Yes].
4. Receipt scan engine [on-device ML Kit on mobile; desktop uses file picker or webcam plus a cloud OCR edge function; ask before enabling cloud].
5. Multi-currency [single household currency for v1].
6. Google Sheet: who can connect [Owner only; Admins view status and Sync now].
7. Google Sheet direction [one-way, app to Sheet; Sheet edits are overwritten, never read back].
8. Google Sheet scope [app-created sheet only, `drive.file` + `spreadsheets`; refresh token kept server-side in Supabase Vault].
9. Member visibility [everyone sees all spending by default; owner can set a member to "own only"; owner and admin always see everything].
10. Per-person allowances [owner and admin set them; arrives with Phase 5 budgets].
11. Sheets mode and Supabase [Supabase stays in the code and is off in Sheets mode; a build flag picks the mode].
12. Budgets, goals and bills in Sheets mode [the owner owns them; members suggest changes and the owner approves].
13. Visibility in Sheets mode [only the owner sees other members' spending; the owner cannot edit members' expenses].
