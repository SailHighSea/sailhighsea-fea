-- Phase 3: Row Level Security (docs/SPEC.md section 6), helper functions and grants.
-- The server is the authority. The app hides actions a role cannot do, but never relies on that.
--
-- Roles (PLAN.md):
--   owner   everything, including transfer ownership and delete household
--   admin   everything except remove the owner, delete the household, transfer ownership
--   editor  add, edit and delete expenses; read everything
--   viewer  read everything, write nothing

-- ---------------------------------------------------------------------------
-- Helpers. SECURITY DEFINER so policies on `members` do not recurse into themselves.
-- ---------------------------------------------------------------------------
create function public.role_in(h uuid)
returns public.member_role
language sql stable security definer set search_path = ''
as $$
  select m.role from public.members m
  where m.household_id = h and m.user_id = (select auth.uid())
$$;

create function public.is_member(h uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$ select public.role_in(h) is not null $$;

-- owner, admin, editor
create function public.can_edit_expenses(h uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$ select coalesce(public.role_in(h) in ('owner', 'admin', 'editor'), false) $$;

-- owner, admin: budgets, goals, bills, categories, members, invites (PLAN.md open decision 2)
create function public.is_manager(h uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$ select coalesce(public.role_in(h) in ('owner', 'admin'), false) $$;

revoke all on function public.role_in(uuid), public.is_member(uuid),
  public.can_edit_expenses(uuid), public.is_manager(uuid) from public, anon;
grant execute on function public.role_in(uuid), public.is_member(uuid),
  public.can_edit_expenses(uuid), public.is_manager(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Table privileges. Supabase grants everything by default; take it all back, then give
-- only what each table needs. Columns that must never change (ids, owner, created_by)
-- are left out of the UPDATE grants.
-- ---------------------------------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;

grant select on public.households, public.members, public.categories, public.expenses,
  public.budgets, public.goals, public.bills to authenticated;

grant update (name, currency) on public.households to authenticated;
grant delete on public.households to authenticated;

grant update (role, display_name) on public.members to authenticated;
grant delete on public.members to authenticated;

-- code_hash is never readable by clients.
grant select (id, household_id, role, created_by, created_at, expires_at, used_by, used_at)
  on public.invites to authenticated;
grant delete on public.invites to authenticated;

grant insert, delete on public.categories, public.budgets, public.goals, public.bills to authenticated;
grant update (name, color, icon, sort, updated_at, deleted_at) on public.categories to authenticated;
grant update (month, category_id, amount_cents, updated_at, deleted_at) on public.budgets to authenticated;
grant update (name, target_cents, saved_cents, monthly_cents, due_on, updated_at, deleted_at)
  on public.goals to authenticated;
grant update (name, amount_cents, due_day, repeat, last_paid_on, updated_at, deleted_at)
  on public.bills to authenticated;

grant insert, delete on public.expenses to authenticated;
grant update (amount_cents, category_id, note, spent_on, receipt_path, updated_at, deleted_at)
  on public.expenses to authenticated;

grant all on all tables in schema public to service_role;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.households enable row level security;
alter table public.members enable row level security;
alter table public.invites enable row level security;
alter table public.invite_attempts enable row level security; -- no policies: service role only
alter table public.categories enable row level security;
alter table public.expenses enable row level security;
alter table public.budgets enable row level security;
alter table public.goals enable row level security;
alter table public.bills enable row level security;

-- households: created through create_household() only (no INSERT policy).
create policy households_select on public.households
  for select to authenticated using (public.is_member(id));
create policy households_update on public.households
  for update to authenticated
  using (public.is_manager(id)) with check (public.is_manager(id));
create policy households_delete on public.households
  for delete to authenticated using (public.role_in(id) = 'owner');

-- members: rows are created by create_household() and redeem_invite() only (no INSERT policy).
create policy members_select on public.members
  for select to authenticated using (public.is_member(household_id));

-- One policy on purpose: permissive policies are OR-ed, so two separate UPDATE policies would let
-- the check of one admit the rows of the other (an editor could promote themself).
--   Others: owner and admin change roles of anyone but the owner, never to owner.
--   Self:   anyone may rename themself but the role must stay what it is.
create policy members_update on public.members
  for update to authenticated
  using (
    user_id = (select auth.uid())
    or (public.is_manager(household_id) and role <> 'owner')
  )
  with check (
    (user_id = (select auth.uid()) and role = public.role_in(household_id))
    or (
      user_id <> (select auth.uid())
      and public.is_manager(household_id)
      and role in ('admin', 'editor', 'viewer')
    )
  );

-- Owner and admin remove anyone but the owner and themselves; anyone but the owner may leave.
create policy members_delete on public.members
  for delete to authenticated
  using (
    role <> 'owner'
    and (
      user_id = (select auth.uid())
      or (public.is_manager(household_id))
    )
  );

-- Only the person themself may change a display name.
create function public.members_guard()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.display_name is distinct from old.display_name
     and (select auth.uid()) is not null
     and old.user_id <> (select auth.uid()) then
    raise exception 'only the member can change their own name' using errcode = '42501';
  end if;
  return new;
end $$;

create trigger members_guard before update on public.members
  for each row execute function public.members_guard();

-- invites: created and redeemed by the edge functions (service role). Managers see and revoke.
create policy invites_select on public.invites
  for select to authenticated using (public.is_manager(household_id));
create policy invites_delete on public.invites
  for delete to authenticated using (public.is_manager(household_id) and used_at is null);

-- categories, budgets, goals, bills: everyone reads, owner and admin write.
create policy categories_select on public.categories
  for select to authenticated using (public.is_member(household_id));
create policy categories_insert on public.categories
  for insert to authenticated with check (public.is_manager(household_id));
create policy categories_update on public.categories
  for update to authenticated
  using (public.is_manager(household_id)) with check (public.is_manager(household_id));
create policy categories_delete on public.categories
  for delete to authenticated using (public.is_manager(household_id));

create policy budgets_select on public.budgets
  for select to authenticated using (public.is_member(household_id));
create policy budgets_insert on public.budgets
  for insert to authenticated with check (public.is_manager(household_id));
create policy budgets_update on public.budgets
  for update to authenticated
  using (public.is_manager(household_id)) with check (public.is_manager(household_id));
create policy budgets_delete on public.budgets
  for delete to authenticated using (public.is_manager(household_id));

create policy goals_select on public.goals
  for select to authenticated using (public.is_member(household_id));
create policy goals_insert on public.goals
  for insert to authenticated with check (public.is_manager(household_id));
create policy goals_update on public.goals
  for update to authenticated
  using (public.is_manager(household_id)) with check (public.is_manager(household_id));
create policy goals_delete on public.goals
  for delete to authenticated using (public.is_manager(household_id));

create policy bills_select on public.bills
  for select to authenticated using (public.is_member(household_id));
create policy bills_insert on public.bills
  for insert to authenticated with check (public.is_manager(household_id));
create policy bills_update on public.bills
  for update to authenticated
  using (public.is_manager(household_id)) with check (public.is_manager(household_id));
create policy bills_delete on public.bills
  for delete to authenticated using (public.is_manager(household_id));

-- expenses: everyone reads; owner, admin and editor write. created_by must be the caller
-- and can never be changed (it is not in the UPDATE grant).
create policy expenses_select on public.expenses
  for select to authenticated using (public.is_member(household_id));
create policy expenses_insert on public.expenses
  for insert to authenticated
  with check (public.can_edit_expenses(household_id) and created_by = (select auth.uid()));
create policy expenses_update on public.expenses
  for update to authenticated
  using (public.can_edit_expenses(household_id))
  with check (public.can_edit_expenses(household_id));
create policy expenses_delete on public.expenses
  for delete to authenticated using (public.can_edit_expenses(household_id));

-- ---------------------------------------------------------------------------
-- RPCs called by the app (authenticated)
-- ---------------------------------------------------------------------------

-- First sign-in: create the household, make the caller its owner, seed default categories.
create function public.create_household(p_name text, p_currency text, p_display_name text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  hid uuid;
begin
  if uid is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;
  if exists (select 1 from public.members where user_id = uid) then
    raise exception 'already in a household' using errcode = '23505';
  end if;
  insert into public.households (name, currency, owner_id)
    values (btrim(p_name), coalesce(nullif(btrim(p_currency), ''), 'SGD'), uid)
    returning id into hid;
  insert into public.members (household_id, user_id, role, display_name)
    values (hid, uid, 'owner', btrim(p_display_name));
  insert into public.categories (household_id, id, name, color, icon, sort) values
    (hid, 'default-food', 'Food', 'food', 'restaurant', 0),
    (hid, 'default-bills', 'Bills', 'bills', 'receipt', 1),
    (hid, 'default-transport', 'Transport', 'transport', 'directions_bus', 2),
    (hid, 'default-fun', 'Fun', 'fun', 'celebration', 3),
    (hid, 'default-health', 'Health', 'health', 'favorite', 4),
    (hid, 'default-other', 'Other', 'other', 'category', 5);
  return hid;
end $$;

-- Owner only: hand the household to another member. The old owner becomes an admin.
create function public.transfer_ownership(p_household uuid, p_new_owner uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare uid uuid := (select auth.uid());
begin
  if public.role_in(p_household) is distinct from 'owner' then
    raise exception 'only the owner can transfer ownership' using errcode = '42501';
  end if;
  if p_new_owner = uid or not exists (
    select 1 from public.members where household_id = p_household and user_id = p_new_owner
  ) then
    raise exception 'new owner must be another member' using errcode = '22023';
  end if;
  update public.members set role = 'admin' where household_id = p_household and user_id = uid;
  update public.members set role = 'owner' where household_id = p_household and user_id = p_new_owner;
  update public.households set owner_id = p_new_owner where id = p_household;
end $$;

revoke all on function public.create_household(text, text, text),
  public.transfer_ownership(uuid, uuid) from public, anon;
grant execute on function public.create_household(text, text, text),
  public.transfer_ownership(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Invite functions, called only by the edge functions with the service role.
-- Codes arrive already hashed; the plain code never reaches the database.
-- ---------------------------------------------------------------------------

-- Returns {status: ok | forbidden | bad_role | rate_limited, expires_at?}.
create function public.create_invite_record(
  p_household uuid, p_user_id uuid, p_role public.member_role, p_code_hash text
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  caller public.member_role;
  expires timestamptz := now() + interval '24 hours';
begin
  if p_role not in ('editor', 'viewer') then
    return jsonb_build_object('status', 'bad_role');
  end if;
  select role into caller from public.members
    where household_id = p_household and user_id = p_user_id;
  if caller is null or caller not in ('owner', 'admin') then
    return jsonb_build_object('status', 'forbidden');
  end if;
  if (select count(*) from public.invites
        where created_by = p_user_id and created_at > now() - interval '1 hour') >= 10 then
    return jsonb_build_object('status', 'rate_limited');
  end if;
  insert into public.invites (household_id, code_hash, role, created_by, expires_at)
    values (p_household, p_code_hash, p_role, p_user_id, expires);
  return jsonb_build_object('status', 'ok', 'expires_at', expires);
end $$;

-- Returns {status: ok | invalid | already_member | rate_limited, household_id?, role?}.
-- Expired, used and unknown codes all answer "invalid" so nothing leaks about them.
-- Five wrong tries per user or twenty per IP in 15 minutes lock redeeming for a while.
create function public.redeem_invite(
  p_code_hash text, p_user_id uuid, p_display_name text, p_ip text
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  inv public.invites%rowtype;
  v_name text := coalesce(nullif(left(btrim(p_display_name), 60), ''), 'Member');
begin
  delete from public.invite_attempts where attempted_at < now() - interval '1 day';

  if (select count(*) from public.invite_attempts
        where user_id = p_user_id and not success
          and attempted_at > now() - interval '15 minutes') >= 5
     or (p_ip is not null and (select count(*) from public.invite_attempts
        where ip = p_ip and not success
          and attempted_at > now() - interval '15 minutes') >= 20) then
    return jsonb_build_object('status', 'rate_limited');
  end if;

  if exists (select 1 from public.members where user_id = p_user_id) then
    return jsonb_build_object('status', 'already_member');
  end if;

  select * into inv from public.invites where code_hash = p_code_hash for update;
  if not found or inv.used_at is not null or inv.expires_at <= now() then
    insert into public.invite_attempts (user_id, ip, success) values (p_user_id, p_ip, false);
    return jsonb_build_object('status', 'invalid');
  end if;

  insert into public.members (household_id, user_id, role, display_name)
    values (inv.household_id, p_user_id, inv.role, v_name);
  update public.invites set used_by = p_user_id, used_at = now() where id = inv.id;
  insert into public.invite_attempts (user_id, ip, success) values (p_user_id, p_ip, true);
  return jsonb_build_object('status', 'ok', 'household_id', inv.household_id, 'role', inv.role);
end $$;

revoke all on function public.create_invite_record(uuid, uuid, public.member_role, text),
  public.redeem_invite(text, uuid, text, text) from public, anon, authenticated;
grant execute on function public.create_invite_record(uuid, uuid, public.member_role, text),
  public.redeem_invite(text, uuid, text, text) to service_role;
