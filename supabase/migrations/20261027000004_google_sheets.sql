-- Phase 4b: mirror household expenses into a Google Sheet (one way, app to Sheet).
--
-- The Google refresh token lives in Supabase Vault and is only ever read by edge functions
-- (service role). No client can read the token, its Vault id, the OAuth state or the queue.
-- Owner connects; admins see status and can press Sync now (through the edge function).

-- The Sheet has a "Created" column; expenses only had updated_at until now. Existing rows get
-- the time of this migration, new rows the time they were first stored.
alter table public.expenses add column created_at timestamptz not null default now();

create table public.sheet_connections (
  household_id uuid primary key references public.households (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  spreadsheet_id text,
  spreadsheet_url text,
  -- pending: connected, first copy not finished. active: working. error: last run failed,
  -- will retry. revoked: Google no longer accepts the token; the owner must reconnect.
  status text not null default 'pending' check (status in ('pending', 'active', 'error', 'revoked')),
  -- Id of the Vault secret holding the refresh token. Clients cannot select this column.
  vault_secret_id uuid,
  last_synced_at timestamptz,
  last_error text,
  -- How many expenses the first copy (or a reconnect) had to send, for the progress bar.
  backfill_total int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- One row per connect attempt in flight. Holds the PKCE verifier on the server only.
create table public.sheet_oauth_states (
  state text primary key,
  household_id uuid not null references public.households (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  code_verifier text not null,
  created_at timestamptz not null default now()
);
create index sheet_oauth_states_user_idx on public.sheet_oauth_states (user_id, created_at desc);

-- Expenses waiting to be written to the Sheet. One row per expense; a newer change replaces
-- the older one (the Sheet only needs the latest state).
create table public.sheet_sync_queue (
  household_id uuid not null references public.households (id) on delete cascade,
  expense_id uuid not null,
  op text not null check (op in ('upsert', 'delete')),
  enqueued_at timestamptz not null default now(),
  claimed_at timestamptz,
  attempts int not null default 0,
  primary key (household_id, expense_id)
);
create index sheet_sync_queue_due_idx on public.sheet_sync_queue (household_id, enqueued_at);

alter table public.sheet_connections enable row level security;
alter table public.sheet_oauth_states enable row level security;
alter table public.sheet_sync_queue enable row level security;

revoke all on public.sheet_connections, public.sheet_oauth_states, public.sheet_sync_queue
  from public, anon, authenticated;
grant all on public.sheet_connections, public.sheet_oauth_states, public.sheet_sync_queue
  to service_role;

-- Only the owner reads the connection row, and never the Vault reference. Nobody writes it
-- from a client: connecting and disconnecting go through edge functions (service role), so
-- there is no INSERT, UPDATE or DELETE grant or policy for any client role.
grant select (household_id, owner_id, spreadsheet_id, spreadsheet_url, status, last_synced_at,
              last_error, backfill_total, created_at, updated_at)
  on public.sheet_connections to authenticated;
create policy sheet_connections_select on public.sheet_connections
  for select to authenticated using (public.role_in(household_id) = 'owner');

-- What every member may see: the state of the connection. Owner and admins also get the link
-- and the error text. No token, no Vault id. `pending` counts expenses not yet in the Sheet.
create view public.sheet_status with (security_barrier = true) as
select
  c.household_id,
  c.status,
  case when public.is_manager(c.household_id) then c.spreadsheet_url end as spreadsheet_url,
  c.last_synced_at,
  case when public.is_manager(c.household_id) then c.last_error end as last_error,
  c.backfill_total,
  (select count(*)::int from public.sheet_sync_queue q where q.household_id = c.household_id) as pending,
  c.updated_at
from public.sheet_connections c
where public.is_member(c.household_id);
revoke all on public.sheet_status from public, anon;
grant select on public.sheet_status to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Queue: every expense insert, edit and soft delete lands here (after Phase 4's server
-- stamped updated_at / deleted_at). Revoked connections queue nothing; reconnecting copies
-- everything again.
-- ---------------------------------------------------------------------------
create function public.sheet_enqueue()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if exists (
    select 1 from public.sheet_connections c
    where c.household_id = new.household_id and c.status in ('pending', 'active', 'error')
  ) then
    insert into public.sheet_sync_queue (household_id, expense_id, op, enqueued_at)
    values (new.household_id, new.id,
            case when new.deleted_at is null then 'upsert' else 'delete' end, now())
    on conflict (household_id, expense_id) do update
      set op = excluded.op, enqueued_at = excluded.enqueued_at, claimed_at = null;
  end if;
  return new;
end $$;

create trigger expenses_sheet_enqueue after insert or update on public.expenses
  for each row execute function public.sheet_enqueue();

-- Copies every expense into the queue (first connect, reconnect, "copy everything again").
-- Due immediately. Returns how many were queued.
create function public.sheet_enqueue_backfill(p_household uuid, p_include_deleted boolean default false)
returns int
language plpgsql security definer set search_path = ''
as $$
declare
  n int;
begin
  insert into public.sheet_sync_queue (household_id, expense_id, op, enqueued_at)
  select e.household_id, e.id,
         case when e.deleted_at is null then 'upsert' else 'delete' end,
         now() - interval '1 minute'
  from public.expenses e
  where e.household_id = p_household and (p_include_deleted or e.deleted_at is null)
  on conflict (household_id, expense_id) do update
    set op = excluded.op, enqueued_at = excluded.enqueued_at, claimed_at = null;
  get diagnostics n = row_count;
  update public.sheet_connections set backfill_total = n, updated_at = now()
    where household_id = p_household;
  return n;
end $$;

-- Households with rows that have waited out the debounce (30 s) and a connection that works.
create function public.sheet_due_households(p_debounce interval default interval '30 seconds')
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select distinct q.household_id
  from public.sheet_sync_queue q
  join public.sheet_connections c on c.household_id = q.household_id
  where c.status in ('pending', 'active', 'error')
    and q.enqueued_at <= now() - p_debounce
    and (q.claimed_at is null or q.claimed_at < now() - interval '5 minutes')
$$;

-- Takes up to p_limit due rows for one run. `p_force` skips the debounce (Sync now). Rows
-- claimed by a run that died are taken again after 5 minutes.
create function public.sheet_claim_batch(p_household uuid, p_limit int, p_force boolean default false)
returns table (expense_id uuid, op text, enqueued_at timestamptz)
language plpgsql security definer set search_path = ''
as $$
begin
  return query
  with picked as (
    select q.household_id, q.expense_id
    from public.sheet_sync_queue q
    where q.household_id = p_household
      and (q.claimed_at is null or q.claimed_at < now() - interval '5 minutes')
      and (p_force or q.enqueued_at <= now() - interval '30 seconds')
    order by q.enqueued_at
    limit p_limit
    for update skip locked
  )
  update public.sheet_sync_queue q
     set claimed_at = now(), attempts = q.attempts + 1
    from picked
   where q.household_id = picked.household_id and q.expense_id = picked.expense_id
  returning q.expense_id, q.op, q.enqueued_at;
end $$;

-- Removes rows that were written. A row changed again while the run was going has a newer
-- enqueued_at and stays for the next run.
create function public.sheet_ack(p_household uuid, p_items jsonb)
returns void
language sql security definer set search_path = ''
as $$
  delete from public.sheet_sync_queue q
  using jsonb_to_recordset(p_items) as i (expense_id uuid, enqueued_at timestamptz)
  where q.household_id = p_household and q.expense_id = i.expense_id and q.enqueued_at = i.enqueued_at
$$;

-- Gives claimed rows back (the run failed).
create function public.sheet_release(p_household uuid)
returns void
language sql security definer set search_path = ''
as $$
  update public.sheet_sync_queue set claimed_at = null where household_id = p_household
$$;

create function public.sheet_set_status(p_household uuid, p_status text, p_error text default null)
returns void
language sql security definer set search_path = ''
as $$
  update public.sheet_connections
     set status = p_status,
         last_error = p_error,
         last_synced_at = case when p_status = 'active' then now() else last_synced_at end,
         updated_at = now()
   where household_id = p_household
$$;

-- ---------------------------------------------------------------------------
-- Vault: the refresh token never leaves the database except into an edge function.
-- ---------------------------------------------------------------------------
create function public.sheet_store_token(p_household uuid, p_token text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  sid uuid;
begin
  select vault_secret_id into sid from public.sheet_connections where household_id = p_household;
  if sid is not null then
    perform vault.update_secret(sid, p_token);
  else
    sid := vault.create_secret(p_token, 'sheets-' || p_household::text, 'Google refresh token');
    update public.sheet_connections set vault_secret_id = sid where household_id = p_household;
  end if;
end $$;

create function public.sheet_read_token(p_household uuid)
returns text
language sql stable security definer set search_path = ''
as $$
  select s.decrypted_secret
  from public.sheet_connections c
  join vault.decrypted_secrets s on s.id = c.vault_secret_id
  where c.household_id = p_household
$$;

create function public.sheet_delete_token(p_household uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  sid uuid;
begin
  select vault_secret_id into sid from public.sheet_connections where household_id = p_household;
  if sid is not null then
    delete from vault.secrets where id = sid;
    update public.sheet_connections set vault_secret_id = null where household_id = p_household;
  end if;
end $$;

revoke all on function
  public.sheet_enqueue_backfill(uuid, boolean), public.sheet_due_households(interval),
  public.sheet_claim_batch(uuid, int, boolean), public.sheet_ack(uuid, jsonb),
  public.sheet_release(uuid), public.sheet_set_status(uuid, text, text),
  public.sheet_store_token(uuid, text), public.sheet_read_token(uuid),
  public.sheet_delete_token(uuid), public.sheet_enqueue()
  from public, anon, authenticated;
grant execute on function
  public.sheet_enqueue_backfill(uuid, boolean), public.sheet_due_households(interval),
  public.sheet_claim_batch(uuid, int, boolean), public.sheet_ack(uuid, jsonb),
  public.sheet_release(uuid), public.sheet_set_status(uuid, text, text),
  public.sheet_store_token(uuid, text), public.sheet_read_token(uuid),
  public.sheet_delete_token(uuid)
  to service_role;
