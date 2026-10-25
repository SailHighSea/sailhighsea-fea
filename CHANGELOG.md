# Changelog

## Phase 4: Sync (2026-10-26)
- Sync engine (`lib/core/sync`): pushes dirty rows (categories first, then expenses), then pulls everything changed since a saved cursor per household and table. Runs while a person is signed in with a household; local-only mode has no engine and no indicator. The UI still only reads Drift (rule 5).
- Server time decides (`supabase/migrations/20261026000003_sync.sql`): a trigger stamps `updated_at` on every insert and update (strictly increasing per row) and stamps soft deletes with server time, so a device with a wrong clock cannot win a conflict. Devices take the server's timestamp back after each push. Last write wins by the order writes reach the server; a local change that is still waiting is never overwritten by a pull.
- Live updates: Supabase Realtime on `expenses`, `categories` and `members` (added to the `supabase_realtime` publication, filtered by household, Row Level Security applies). A signal only triggers a pull, so the data path is the same as the periodic one. A reconnect pulls what was missed. A one-minute safety pull runs while idle.
- Offline queue and backoff: unreachable server keeps the queue, retries after 2, 4, 8 ... up to 300 seconds, and also on any local edit (300 ms debounce), live signal or "Sync now". An edit made while a push is running is not marked as sent.
- First join: the first pull downloads everything and reports progress ("Getting 120 items").
- Sync status indicator in the shell on every size (strip above the page on phones, in the 96px rail as one word, in the 240px sidebar in full): Synced, Syncing, Offline (N waiting), Sync problem, Not all saved. Tap for details, "Sync now" and the list of refused changes with Dismiss.
- Role changes mid-session: a write the server refuses (Row Level Security, 42501) is taken out of the queue, the row goes back to the server's version (or is removed if the server never had it), a `sync_issues` row remembers what was lost, the indicator says "Not all saved" and the sheet lists it. The member list and role are reloaded so buttons match the new role. Realtime changes to `members` do the same.
- Local database v3 (`sync_state`, `sync_issues`) with a migration from v2.
- Phase 4b contract: `expenses.updated_at` is server-stamped and strictly increasing per row, `deleted_at` is the soft-delete flag set by the server, and the app never hard deletes, so an AFTER trigger on `expenses` sees every create, edit and delete.
- Server tests: `supabase/tests/sync.test.sql` (server time, soft delete, viewer refused). **Not run**: no Docker or Supabase CLI here; run `supabase test db`.
- Tests: 28 new in `tests/` with a fake server that stamps time and refuses viewers: first sync and progress, push/pull, two devices, conflicts, deletes and undo, wrong device clocks, offline edits and reconnect, edits during a push, backoff, view-only refused, demoted while offline, removed from household, live signal and auto push, empty household, v2 to v3 migration, indicator at phone, tablet and desktop widths, refused-changes sheet, real provider wiring.

### Decisions and deviations (change here if you disagree)
- Conflict rule: last write wins by arrival at the server (server time), not by the time on the device that made the edit. A phone that was offline for a week and then pushes an old edit overwrites a newer edit made by someone else on the same expense. Only the pushed fields are overwritten. Field-level merging is not done.
- A refused offline change is not kept for retry: the row returns to the server's version and the lost change is only listed by its summary (note and amount) until dismissed.
- Updates go through "update, then insert if no row matched" instead of upsert, because an editor editing another member's expense must not hit the insert policy (`created_by` must be you).
- Pull overlap of 5 seconds before the cursor catches rows whose transaction committed late; applying a row twice is harmless.
- Budgets, goals and bills have tables, triggers and indexes on the server but are not synced by the app until Phase 5 gives them screens.
- Not synced: appearance settings (local-only by design).

## Phase 3: Accounts and household (2026-10-25)
- Server (`supabase/`): migrations with every table from SPEC section 5 (enums, indexes, soft delete columns), Row Level Security for owner, admin, editor, viewer and outsiders, `create_household`, `transfer_ownership`, `create_invite_record` and `redeem_invite` functions. Edge functions `create-invite` and `redeem-invite`: 8 characters from `23456789ABCDEFGHJKLMNPQRSTUVWXYZ`, stored as an HMAC-SHA256 hash (secret `INVITE_PEPPER`), single use, 24 hours, role carried by the code, rate limited (5 wrong tries per person or 20 per IP in 15 minutes; 10 new codes per person per hour). Clients cannot insert households, members or invites, and cannot read `code_hash`.
- Tests for the server: pgTAP file `supabase/tests/rls.test.sql` (98 checks across all roles, outsider, anonymous, invites, rate limits, leaving, transfer) and Deno tests for code generation and hashing. **Not run yet**: this machine has no Docker, Supabase CLI or Deno. Run them with `supabase test db` and `deno test supabase/functions/_shared` (see `supabase/README.md`).
- App: Supabase is optional. Without `SUPABASE_URL` and `SUPABASE_ANON_KEY` (`--dart-define-from-file=.env.json`) the app runs local-only exactly as in Phase 2 (one person, owner rights, no sign-in).
- Sign-in (`lib/features/auth`): email and password, create account, emailed one-time code (works on every platform without deep links), Google (Android, iOS, macOS) and Apple (iOS, macOS). One centred screen for every width. Sign-in returns you to the page you were heading to.
- First sign-in: "Set up your household" (name, your name) makes you the owner and seeds the default categories; or "Have a code? Join a household". Anything entered before signing in moves into a household you create.
- Family (`lib/features/family`, matches Family, TabFamily, DeskFamily, Join): members with role pills, role sheet (Admin, Can edit, View only; promoting to Admin is choosing Admin), remove with confirmation, leave household, invite card (role switch, code shown once, Copy, Share, Generate a new code, list of open codes with Revoke), Join with code screen (capitals and dash as you type, button enabled at 8 characters), sign out.
- Roles in the UI: view-only members get no Add button, no Ctrl/Cmd+N, no edit or delete on Home and the list, and `/add` and `/edit` routes send them back to Home; "+ New" category only for owner and admin; role and invite controls only for owner and admin. `lib/features/family/domain/permissions.dart` mirrors the SQL policies and exists only to hide buttons; the server decides. If the server says no, the screen shows "Your role does not allow that."
- "Who added" shows the member's name (or "You") on Home and the expense list, from the local copy of the members.
- Local database v2 (`households`, `members` tables, migration from v1). Expenses and categories are read and written per household.
- Platform setup: Android INTERNET permission and `app.familyexpenses://login-callback` link, iOS and macOS URL scheme, macOS network client entitlement.
- Fixes to earlier phases found while running the whole suite: Home only loaded the last 7 days instead of the whole month (totals were wrong from the second week on); the side rail overflowed in short windows (half-open fold, large text) and now scrolls; the sidebar footer overflowed with four members and now shows at most five circles and "N members" ellipsised; four Phase 2 tests were failing (stale expectations and one test that opened two apps at once) and are repaired.
- Tests: 208 in total (69 new): permissions matrix, invite code input, household repository (including migration of local data), Family screen as owner, admin, editor and view only on phone, tablet and desktop, server rejection shown to the user, sign-in flows, first household, joining (valid, wrong and reused codes), view-only expense restrictions, large text and tap-target sizes.

### Decisions and deviations (change here if you disagree)
- One household per person in v1 (unique index on `members.user_id`). Joining while in a household says to leave first.
- Invite codes carry Can edit or View only, as in the mockups. Admin is given afterwards from the role sheet.
- Admin can change roles of and remove any member except the owner (PLAN open decision 1 default). Nobody changes their own role. To stop admins touching other admins, change `members_update` and `members_delete` in `20261025000002_rls_and_functions.sql`.
- Editors can edit and delete any expense in the household (SPEC section 6), not only their own; the PLAN wording "manage own entries" can be enforced by adding `created_by = auth.uid()` to the editor branch of `expenses_update` and `expenses_delete`.
- Categories are owner and admin only (SPEC section 6). Budgets, goals and bills follow in Phase 5 with the same rule.
- Transfer ownership and delete household exist on the server and are tested, but have no screen yet.
- Joining a household leaves local entries on the device under the local household (hidden, not deleted); only the default categories move across.
- Magic link is delivered as an emailed 6-digit code (needs `{{ .Token }}` in the Supabase "Magic link" email template) because deep links are unreliable on Windows and Linux.
- Members and household are refreshed from the server on sign-in and when Family opens; live updates arrive with Phase 4.

## Phase 2: Core expenses (2026-10-25)
- Local database (Drift/SQLite) in `lib/core/db`: `categories` and `expenses` tables from SPEC section 5 with `updated_at`, `deleted_at` (soft delete) and `dirty`; money is integer cents; `spent_on` is a `yyyy-MM-dd` day so time zones never move an expense; migration scaffold (`schemaVersion` 1, `onUpgrade` ready); foreign keys on.
- Default categories Food, Bills, Transport, Fun, Health, Other with fixed ids (`default-*`) so devices that seed offline do not duplicate after sync. Categories store a colour key resolved by the theme, so they stay readable in every mode and in the colour-blind palette. People can add their own with "+ New".
- Repositories and Riverpod providers in `lib/features/expenses`; the UI never touches Drift directly.
- Home now reads the database: month total, today, this week (last 7 days), safe per day (remaining budget over days left), pace line (budget over days in the month), top categories (the smallest fold into "Other", which always sits last like the mockups), last 7 days and daily bars, recent list. Logic is in `home_calculations.dart` (pure, tested). Month navigation works on Home and the expense list.
- Add and edit expense: amount keypad (also hardware keyboard digits, point and backspace), category tiles, note, date picker, Save. Phone is full screen with Save pinned; tablet and desktop use the two-column layout from TabAdd and DeskAdd. Ctrl/Cmd+N opens Add from anywhere, Ctrl/Cmd+Enter saves, Esc closes.
- Expense list (`/expenses`): month navigation, search (note, category, who added), category filter, swipe or row menu delete (soft delete) with Undo, tap to edit.
- Foldable half-open: Home above the hinge and a quick-add panel (amount, categories, keypad, Save) below it.
- Phone: Add, Expenses and Appearance open full screen without the bottom tabs.
- Tests: amount entry, Home calculations, repositories, add/edit/list/delete/undo flows on phone, tablet and desktop widths, shortcuts, fold layout, tap-target sizes, large text; Phase 1 goldens kept (sample data) and Appearance goldens.

### Decisions and deviations (change here if you disagree)
- Monthly budget is a stored setting defaulting to S$2,500 with no screen to change it yet; Phase 5 replaces it with real budgets. (`lib/features/budgets/budget_providers.dart`)
- Next bill and goal cards show their empty states ("Nothing due", "No goal yet") until Phase 5; goldens use the sample numbers from the mockups.
- The Add mockups also show "Paid with", "Repeats monthly" and "Scan a receipt". They are not in the Phase 2 spec or data model: repeating belongs to Recurring bills (Phase 5) and scanning to Phase 6, so they are left out.
- Anyone can add a category for now; restricting it to Admin and Owner comes with roles in Phase 3.
- Everything added on this device is "You" until accounts exist (Phase 3).

## Phase 1: Foundations (2026-10-25)
- Flutter project (org `app.familyexpenses`; android, ios, windows, macos, linux). `test/` is reserved for build outputs; automated tests live in `tests/` (`flutter test tests/`).
- Dependencies: Riverpod, go_router, Drift (+ drift_flutter), Supabase, fl_chart, local_auth, intl, freezed/json_serializable, shared_preferences. Strict `analysis_options.yaml`.
- `lib/core/theme`: SPEC section 2 tokens as a `ThemeExtension`; modes System, Light, Dark, Pure black; colour themes Forest, Ocean, Sunset, Graphite, each with Light, Dark and Pure variants; colour-blind chart palette; choices persisted with shared_preferences. DM Sans bundled (SIL OFL).
- `lib/core/layout`: one adaptive shell. Under 600dp bottom tabs, 600 to 1199dp 96px rail, 1200dp and up 240px sidebar; phone overflow menu for Family, Goals, Bills, Appearance; hinge-aware `HingeSplit`; `DashboardLayout` arranges Home sections by window width so features never read the width.
- `lib/core/money`: integer-cents formatting with intl, currency list (SGD default).
- Home page (SPEC section 3) with sample data, matching the Main, Tablet and Desktop mockups in Light, Dark and Pure black.
- Appearance page wired to the live theme switch (mode, colour theme, larger text, colour-blind charts, currency).
- Placeholder pages for Budgets, Insights, Goals, Bills, Family.
- Tests: 72 (tokens match SPEC, contrast, persistence, layout matrix 360 to 1920, destinations reachable on every size, hinge, appearance flows, Home identical across themes, goldens for Home x 3 modes x 3 widths and Appearance x 3 widths).
- Open-decision defaults used: colour values for Ocean, Sunset and Graphite primary and neutral tokens (SPEC only gives their hero and accent swatches); all are in `lib/core/theme/color_themes.dart`.
