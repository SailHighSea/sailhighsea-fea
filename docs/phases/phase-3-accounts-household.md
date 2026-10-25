# Phase 3: Accounts and household (weeks 4 to 5)

Ask me for the Supabase project URL and anon key; put them in `.env.json` (gitignored). Never ask for the service key in the app.

## Do
1. `supabase/migrations`: tables from SPEC section 5, enums, indexes.
2. RLS policies per SPEC section 6 and tests for owner, admin, editor, viewer, outsider.
3. Edge functions `create-invite` and `redeem-invite` per SPEC section 7 (hashed codes, expiry, single use, rate limit).
4. Auth: email + magic link or password, plus Sign in with Apple and Google where the platform allows. Sign-in screens adaptive.
5. Create household on first sign-in. Family screens match Family, TabFamily, DeskFamily: members list with role pills, role change sheet, promote to Admin, remove, invite creation with role picker and copy/share code, revoke, Join with code screen.
6. UI hides actions the role cannot do, but the server is the authority. Show "who added" on expenses.
7. Tests for permissions at the UI level and RLS level. Build to `test/` and report.

## Done when
Two accounts can join one household with a code, and a view-only member provably cannot write (server rejects it).
