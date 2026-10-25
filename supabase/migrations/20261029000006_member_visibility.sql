-- Phase 4c: family overview and private members.
--
-- A household is everyone connected to one owner. Each member can be set to see the spending of
-- everyone ('household', today's behaviour) or only their own ('own'). Owner and admin always see
-- everything; the setting only matters for editors and viewers. It is enforced here, in the
-- select policy of expenses, so an own-only member's device never receives anyone else's rows.

create type public.member_visibility as enum ('household', 'own');

alter table public.members
  add column visibility public.member_visibility not null default 'household';

-- Only owner and admin change it (the update policy already limits who may change other
-- members); the guard below stops anyone changing their own.
grant update (visibility) on public.members to authenticated;

create function public.visibility_of(h uuid)
returns public.member_visibility
language sql stable security definer set search_path = ''
as $$
  select m.visibility from public.members m
  where m.household_id = h and m.user_id = (select auth.uid())
$$;
revoke all on function public.visibility_of(uuid) from public, anon;
grant execute on function public.visibility_of(uuid) to authenticated, service_role;

drop policy expenses_select on public.expenses;
create policy expenses_select on public.expenses
  for select to authenticated
  using (
    public.is_member(household_id)
    and (
      public.is_manager(household_id)
      or public.visibility_of(household_id) = 'household'
      or created_by = (select auth.uid())
    )
  );

-- Nobody changes their own visibility, and it only applies below admin: a member who becomes
-- admin or owner is back on 'household'.
create or replace function public.members_guard()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.display_name is distinct from old.display_name
     and (select auth.uid()) is not null
     and old.user_id <> (select auth.uid()) then
    raise exception 'only the member can change their own name' using errcode = '42501';
  end if;
  if new.visibility is distinct from old.visibility
     and (select auth.uid()) is not null
     and old.user_id = (select auth.uid()) then
    raise exception 'nobody can change their own visibility' using errcode = '42501';
  end if;
  if new.role in ('owner', 'admin') then
    new.visibility := 'household';
  end if;
  return new;
end $$;

-- Per-person allowance: a budget row with a user_id is that person's monthly allowance. Owner
-- and admin set them (the budget policies already say so). A person sees their own allowance;
-- owner and admin see everyone's; the household-wide budgets stay readable by all members.
alter table public.budgets
  add column user_id uuid references auth.users (id) on delete cascade;

drop index public.budgets_unique_idx;
create unique index budgets_unique_idx
  on public.budgets (household_id, month, coalesce(category_id, ''), coalesce(user_id::text, ''))
  where deleted_at is null;

drop policy budgets_select on public.budgets;
create policy budgets_select on public.budgets
  for select to authenticated
  using (
    public.is_member(household_id)
    and (
      user_id is null
      or user_id = (select auth.uid())
      or public.is_manager(household_id)
    )
  );
