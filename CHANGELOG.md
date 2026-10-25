# Changelog

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
