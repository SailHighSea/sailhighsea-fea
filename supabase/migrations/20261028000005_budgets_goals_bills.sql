-- Phase 5: budgets, goals (with contributions) and bills get what the app needs to sync them.
-- Writes stay owner and admin only (PLAN.md open decision 2); everyone in the household reads.

-- Budgets: one row per (month, category or overall). The app gives each a fixed id such as
-- 'b:2026-10:overall' or 'b:2026-10:default-food' so two devices that set the same budget
-- offline end up with one row, not two (like the default category ids). Ids are therefore text
-- and unique per household, not globally.
alter table public.budgets drop constraint budgets_pkey;
alter table public.budgets alter column id drop default;
alter table public.budgets alter column id type text using id::text;
alter table public.budgets add primary key (household_id, id);

-- Bills carry the date they are next due. "Mark paid" moves it forward by one period and
-- records last_paid_on. due_day stays the day of the month (monthly and yearly bills clamp it
-- to short months).
alter table public.bills add column next_due_on date not null default current_date;
alter table public.bills alter column next_due_on drop default;
grant update (next_due_on) on public.bills to authenticated;

-- Goals: saved_cents is the amount the goal started with. Money added later is a row in
-- goal_contributions, so two people adding money at the same time never overwrite each other.
comment on column public.goals.saved_cents is
  'Opening balance. The saved amount is saved_cents plus the sum of live goal_contributions.';

create table public.goal_contributions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  goal_id uuid not null references public.goals (id) on delete cascade,
  amount_cents int not null check (amount_cents > 0),
  contributed_on date not null,
  added_by uuid not null references auth.users (id) on delete restrict,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index goal_contributions_goal_idx on public.goal_contributions (household_id, goal_id);
create index goal_contributions_household_updated_idx on public.goal_contributions (household_id, updated_at);

alter table public.goal_contributions enable row level security;
revoke all on public.goal_contributions from public, anon, authenticated;
grant select, insert, delete on public.goal_contributions to authenticated;
grant update (amount_cents, contributed_on, updated_at, deleted_at) on public.goal_contributions to authenticated;
grant all on public.goal_contributions to service_role;

create policy goal_contributions_select on public.goal_contributions
  for select to authenticated using (public.is_member(household_id));
create policy goal_contributions_insert on public.goal_contributions
  for insert to authenticated
  with check (public.is_manager(household_id) and added_by = (select auth.uid()));
create policy goal_contributions_update on public.goal_contributions
  for update to authenticated
  using (public.is_manager(household_id)) with check (public.is_manager(household_id));
create policy goal_contributions_delete on public.goal_contributions
  for delete to authenticated using (public.is_manager(household_id));

create trigger goal_contributions_stamp before insert or update on public.goal_contributions
  for each row execute function public.stamp_server_time();

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'goal_contributions'
     ) then
    alter publication supabase_realtime add table public.goal_contributions;
  end if;
end $$;
