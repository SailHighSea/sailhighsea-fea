# Phase 2: Core expenses (weeks 2 to 3)

**Status:** Built (2026-10-25).

## Do
1. Drift schema for categories and expenses (SPEC section 5) with migrations, `updated_at`, `deleted_at`, `dirty`. Money in cents.
2. Default categories (Food, Bills, Transport, Fun, Health, Other) with colours from the mockups.
3. Repositories + Riverpod providers. Home reads real data: month total, today, this week, safe-per-day (remaining budget divided by days left), top categories, last 7 days, recent list.
4. Add and edit expense: amount keypad, category chips, date, note. Phone full screen; tablet and desktop use the pane or dialog shown in TabAdd and DeskAdd; fold half-open puts the form below the hinge. Desktop shortcut Ctrl/Cmd+N.
5. Expense list with search, filter by category and month, swipe or menu delete (soft delete) with undo.
6. Month navigation on Home.
7. Unit tests for money maths and calculations; widget tests for add flow; update goldens.
8. Build to `test/` and report.

## Done when
Everything works offline with no account, identically on all sizes.
