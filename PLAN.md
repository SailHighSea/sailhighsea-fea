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
Home dashboard (ring, 7-day or month bars, top categories, next bill, goal, recent) · Add expense (manual) · Scan receipt · Budgets (overall and per category) · Insights (bar charts, trends, category breakdown, who spent what) · Savings goals · Recurring bills with reminders · Family and invites · Appearance (System, Light, Dark, Pure black; colour themes Forest, Ocean, Sunset, Graphite; larger text; colour-blind charts; currency) · Export CSV · Google Sheet sync (owner connects a sheet, expenses mirror into it) · App lock.

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
Status is kept current at the end of every phase (and when a phase starts). "Built" means the code and automated tests exist and pass here; "Verified" means it was also run against the real services or on real devices. Details and open items per phase are in `CHANGELOG.md` and `docs/phases/`.

| # | Phase | Result | Status |
|---|---|---|---|
| 1 | Foundations | Project, theme tokens, three themes, adaptive shell on all sizes, first builds in test/ | Built |
| 2 | Core expenses | Local DB, add/edit/list, Home with real data, categories, month navigation | Built |
| 3 | Accounts and household | Sign-in, household, roles, invite codes, RLS | Built. Server tests (`supabase test db`, `deno test`) and a real two-account run still to do |
| 4 | Sync | Realtime sync, offline queue, conflict handling | Built (fake-server tests). Not yet tried on two real devices against Supabase |
| 4b | Google Sheets connection | Owner links a Google Sheet; all household expenses mirror into it automatically (one-way, server-side) | Built (fake-Google tests). Google Cloud setup and a real connect still to do |
| 5 | Budgets and insights | Budgets, charts, goals, bills, reminders | Built. Server tests, Android/iOS/macOS builds with notifications, and Windows pixel goldens still to do |
| 6 | Adaptive layouts and scan | Tablet, desktop, fold half-open polish; receipt scan | Not started |
| 7 | Polish and release | Accessibility, app lock, export, CI for all platforms, store prep | Not started |

## Open decisions (defaults in brackets)
1. Admin vs owner differences [Admin cannot remove owner, delete household or transfer ownership].
2. Can editors change budgets and goals? [No: Admin and Owner only].
3. Show who added each expense? [Yes].
4. Receipt scan engine [on-device ML Kit on mobile; desktop uses file picker or webcam plus a cloud OCR edge function; ask before enabling cloud].
5. Multi-currency [single household currency for v1].
6. Google Sheet: who can connect [Owner only; Admins view status and Sync now].
7. Google Sheet direction [one-way, app to Sheet; Sheet edits are overwritten, never read back].
8. Google Sheet scope [app-created sheet only, `drive.file` + `spreadsheets`; refresh token kept server-side in Supabase Vault].
