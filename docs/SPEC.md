# Design and technical spec

Mockup screenshots: `design/screenshots/<Name>.png`. Exact markup and values: `design/mockups/<Name>.dc.html` (inline styles; read for spacing, sizes, radii).

## 1. Screen map (by size)
| Screen | Phone | Tablet 1024x720 | Desktop 1280x800 | Fold half-open |
|---|---|---|---|---|
| Home | Main | Tablet | Desktop | Fold |
| Home dark | HomeDark | TabHomeDark | DeskHomeDark | |
| Home pure black | HomePure | TabHomePure | DeskHomePure | |
| Add expense | Add | TabAdd | DeskAdd | Fold (form below hinge) |
| Budgets | Budgets | TabBudgets | DeskBudgets | |
| Insights | Insights, Dashboard | TabInsights | DeskInsights | |
| Goals | Goals | TabGoals | DeskGoals | |
| Bills | Bills | TabBills | DeskBills | |
| Family and sharing | Family | TabFamily | DeskFamily | |
| Join with code | Join | (same dialog) | (same dialog) | |
| Appearance | Themes | TabAppearance | DeskAppearance | |
| Scan receipt | Scan | (dialog) | (dialog) | |

Phone Appearance is reached from a Settings entry (add it to the phone Home header menu or a Settings tab; the phone header is full, so use an overflow menu). Tablet rail has Settings at the bottom; desktop sidebar has Appearance at the bottom.

## 2. Design tokens
Font: DM Sans (400, 500, 600, 700). Radii: cards 24, small cards 20, buttons pill. Tap target 44.

| Token | Light | Dark | Pure black |
|---|---|---|---|
| background | #F4F6F5 | #0E1512 | #000000 |
| surface | #FFFFFF | #17211C | #0A0F0D |
| border | #E3E8E5 | #26332C | #1F2B26 |
| text | #0F1F1A | #E8F0EC | #F2F7F4 |
| muted text | #55645D | #9DB0A6 | #9DB0A6 |
| primary / accent | #0B6E4F | #4CC38A | #4CC38A |
| hero card | #0B3D2E | #123F31 | #0B2E23 (border #14463A) |
| hero track | #1F5A47 | #2A6150 | #1F5A47 |
| hero muted text | #BFD8CC | #BFD8CC | #BFD8CC |
| neutral bars | #B9D9CB | #2F5B4A | #2A5646 |
| nav background | #FFFFFF (tablet), #0B3D2E (desktop) | #17211C / #123F31 | #000000 |
| nav active | bg #DCEFE6, text #0B3D2E | bg #1F3A30, text #4CC38A | bg #0F2A21, text #4CC38A |
Shared: amber #F2B84B (ring, warnings) / #E0A020 (bars), blue #6FB3D9, purple #8A7FB8, grey #9AA8A1.
Colour themes (Forest default, Ocean, Sunset, Graphite) swap hero and accent; each must define Light, Dark and Pure black variants. Preview colours in Appearance: Forest #0B3D2E, Ocean #0B2F4E (accent #F28C28), Sunset #4A1F1A (accent #F2B84B), Graphite #161B1F (accent #6FB3D9).

## 3. Home content (same in every theme and size)
Month navigator; Add expense; hero card (spent, of budget, left, ring with percent, Today, This week, Safe per day); Top categories stacked bar with legend; Next bill card; Goal card; 7-day bars with dashed "safe per day" line (phone and tablet), or month daily bars coloured under/over pace (desktop); Recent list (note, category, date, who added, amount).

## 4. Adaptive shell
- under 600dp: bottom tabs Home, Budgets, Insights (Goals, Bills, Family from Home cards and menu)
- 600 to 1199dp: rail 96px with Home, Budgets, Insights, Goals, Bills, Family, Settings; list and detail side by side
- 1200dp and up: sidebar 240px, same items plus member avatars
- Fold half-open: use `DisplayFeatureType.hinge/fold`; dashboard above, Add form below
- Every item in the phone's menu exists in the rail and sidebar. Test with a matrix of widths 360, 600, 840, 1024, 1280, 1920.

## 5. Data model (Postgres; mirrored in Drift with `updated_at`, `deleted_at`, `dirty`)
- `households(id, name, currency, owner_id, created_at)`
- `members(household_id, user_id, role enum[owner,admin,editor,viewer], display_name, joined_at)`
- `invites(id, household_id, code_hash, role, created_by, expires_at, used_by, used_at)`
- `categories(id, household_id, name, color, icon, sort)`
- `expenses(id, household_id, amount_cents int, category_id, note, spent_on date, created_by, receipt_path, updated_at, deleted_at)`
- `budgets(id, household_id, month, category_id null, amount_cents)`
- `goals(id, household_id, name, target_cents, saved_cents, monthly_cents, due_on)`
- `bills(id, household_id, name, amount_cents, due_day, repeat, last_paid_on)`
- `settings(user_id, mode, theme, large_text, cb_charts)` (local-only is fine for appearance; syncing is optional)

## 6. Row Level Security
Everything keyed by `household_id`. Read: any member. Insert/update/delete on expenses: editor, admin, owner. Budgets, goals, bills, categories: admin and owner (see open decisions). Members and invites: admin and owner; owner-only for removing the owner, deleting the household, transfer. Write RLS tests (SQL or pgTAP) for every role.

## 7. Invite flow
1. Owner or Admin picks a role and taps Create code. Edge function `create-invite` generates 8 chars from `23456789ABCDEFGHJKLMNPQRSTUVWXYZ`, stores a hash, returns the code once, expires in 24h.
2. Joiner signs in, taps Join with code, enters it. `redeem-invite` verifies (rate-limited per user and IP), creates the member row with the invite's role, marks the invite used.
3. Owner or Admin can revoke unused codes and change or remove members.

## 8. Receipt scan
Mobile: camera + on-device text recognition. Desktop: webcam or file picker. Result opens the Add form pre-filled (amount, date, merchant) for confirmation. Same screen and fields everywhere.
