-- Phase 4: sync support. The server owns time.
--
-- Clients send their edits, but `updated_at` (and the moment of a soft delete) is always set
-- here, so a phone with a wrong clock cannot win or lose a conflict. Last write wins by the
-- order the server receives the writes. `updated_at` only ever moves forward for a row, which
-- is what the clients' "changes since cursor" pull and the Phase 4b Google Sheets trigger rely on.

create function public.stamp_server_time()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  stamp timestamptz := clock_timestamp();
begin
  if tg_op = 'UPDATE' then
    -- Strictly increasing per row, even if two writes land in the same microsecond.
    stamp := greatest(stamp, old.updated_at + interval '1 microsecond');
  end if;
  new.updated_at := stamp;
  -- A delete is stamped with server time too (and an existing delete time is kept).
  if new.deleted_at is not null then
    if tg_op = 'UPDATE' and old.deleted_at is not null then
      new.deleted_at := old.deleted_at;
    else
      new.deleted_at := stamp;
    end if;
  end if;
  return new;
end $$;

create trigger expenses_stamp before insert or update on public.expenses
  for each row execute function public.stamp_server_time();
create trigger categories_stamp before insert or update on public.categories
  for each row execute function public.stamp_server_time();
create trigger budgets_stamp before insert or update on public.budgets
  for each row execute function public.stamp_server_time();
create trigger goals_stamp before insert or update on public.goals
  for each row execute function public.stamp_server_time();
create trigger bills_stamp before insert or update on public.bills
  for each row execute function public.stamp_server_time();

-- "Rows changed since the cursor" for the tables the app pulls.
create index categories_household_updated_idx on public.categories (household_id, updated_at);
create index budgets_household_updated_idx on public.budgets (household_id, updated_at);
create index goals_household_updated_idx on public.goals (household_id, updated_at);
create index bills_household_updated_idx on public.bills (household_id, updated_at);

-- Phase 4b contract: an AFTER trigger on `expenses` can read `updated_at` (server time, strictly
-- increasing per row) and `deleted_at` (null = live, set = soft deleted) to feed the Google Sheets
-- queue. Rows are never hard deleted by the app, so a delete always arrives as an UPDATE.
comment on column public.expenses.updated_at is
  'Server time of the last write. Set by stamp_server_time(); clients cannot choose it.';
comment on column public.expenses.deleted_at is
  'Soft delete. Null = live. Set by the server at the time the delete was received.';

-- Realtime: clients subscribe to changes of their household and pull what changed. Row Level
-- Security applies to what Realtime delivers, so outsiders receive nothing.
do $$
declare
  t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['expenses', 'categories', 'members', 'budgets', 'goals', 'bills'] loop
      if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
      ) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;
