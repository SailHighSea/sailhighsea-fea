# Phase 4c: Family overview ("see all") and private members

**Status:** Done and merged (PR #3). Still to do: run `supabase test db`, and try it with a real owner and an own-only member. Item 3 became schema v5 (not v3) because earlier phases had used v3 and v4; item 7 (allowances) is done. See CHANGELOG.md.

Runs after Phase 4 (sync). Until expenses sync, a device only has its own entries, so nobody can see anyone else's spending. Do not start before Phase 4 is done.

## Goal
Everyone keeps their own account and adds their own expenses. The owner (father) sees the whole family at a glance and can drill into each person. Optionally, some members (for example the children) only see their own spending.

## How it fits what exists
A household is already "everyone connected to one owner": each person has their own account, joins with the owner's code, and every expense records `created_by`. So this phase does **not** link separate households. It adds:
1. A per-person view over the shared household data (the overview).
2. A per-member visibility setting (Everyone's spending, or Own only).

Why not separate households joined to a parent: it doubles the sync and RLS surface, makes budgets and categories diverge, and "see all" would need cross-household reads. One household with per-member visibility gives the same result with the rules we already have.

## Do
1. **Migration** `supabase/migrations/…_member_visibility.sql`
   - `members.visibility` enum `household | own`, default `household` (today's behaviour, nothing changes for existing members).
   - Owner and admin always see everything; the setting only applies to editor and viewer.
   - Change `expenses_select`: `is_member(household_id) and (is_manager(household_id) or visibility_of(household_id) = 'household' or created_by = auth.uid())`. Add `visibility_of(h)` helper (security definer, like `role_in`).
   - Only owner and admin may change `members.visibility` (extend the `members_update` policy and the column grant). Nobody changes their own.
   - Budgets, goals and bills stay readable by all members as today.
2. **pgTAP tests** for: own-only editor and viewer cannot read others' expenses; household-visibility members can; owner and admin always can; a member cannot raise their own visibility; sync pulls only what RLS allows.
3. **Drift**: `members.visibility` column (schema v3 migration). Sync pull already respects RLS, so own-only members simply never receive others' rows. Add a test that a local database for an own-only member contains only their rows.
4. **Overview screen "Everyone"** (new, `lib/features/overview`), reached from Home ("See everyone" card, owner and admin, and members with household visibility) and as a tab inside Insights on every size:
   - Month navigator (reuses the existing one).
   - Family total (spent, budget, left) in the hero card style.
   - **Per-person rows**: avatar, name, spent this month, share of the family total (bar), vs their allowance if one is set, top category. Sorted by spend.
   - Tap a person: their month (same Home content filtered to that person, plus their recent list).
   - Stacked bar "who spent what" for the month, colour-blind friendly via the existing palette option.
   - Member filter chips (All, You, each person) on the Expenses list and Home, applied to every number on the page.
   - Home must still look identical in every theme and size; the filter changes data, not layout.
5. **Calculations** in `overview_calculations.dart` (pure, tested): per-person totals, shares, week and today, top category, in integer cents. Rounding of shares sums to 100.
6. **Family screen**: on each member's role sheet add "Can see: Everyone's spending / Only their own" for editor and viewer (owner and admin only). Show a small "Private" tag on those rows. Server stays the authority.
7. **Optional allowance per person** (open decision): `budgets.user_id` nullable so a per-person monthly allowance can be set by owner and admin. Builds on Phase 5 budgets; if Phase 5 is not done yet, skip this item and keep the hook.
8. **Empty and edge states**: a household of one (overview shows only "You"), a member who left (their past expenses stay, shown under their name with "(left)"), a removed member's name from the local members cache.

## Tests
- Calculations: totals, shares, ties, one person, no expenses, member who left, month boundaries.
- Widget: Overview on phone, tablet, desktop; owner sees all rows; own-only member does not get the screen entry and sees only themselves; filter chips change every number; tap-through to a person; large text; 44px targets.
- Permissions: UI hides the visibility control for non-managers; server rejection shown.
- pgTAP: listed above.

## Done when
Father's account shows one overview with every family member's spending for the month and can open each person. A child set to "Only their own" can add expenses and sees only their own on every screen, and the server (not just the app) refuses to return anyone else's expenses.

## Open decisions (defaults in brackets)
1. Default visibility for new members [Everyone's spending, same as today; owner can switch a member to Own only].
2. Who may see the overview [owner and admin always; others only with household visibility].
3. Can an own-only member see household totals (no names) [No].
4. Per-person allowances [owner and admin set them, in Phase 5 budgets; optional here].
5. Can an admin hide a member from the owner [No: the owner always sees everything].
