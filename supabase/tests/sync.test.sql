-- pgTAP tests for server-side sync support (Phase 4): server-stamped time and soft deletes.
-- Run with:  supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

do $$ begin
  execute 'grant all on table __tresults__ to authenticated, anon';
  execute 'grant all on sequence __tresults___numb_seq to authenticated, anon';
exception when others then null;
end $$;

create schema tests;
grant usage on schema tests to authenticated, anon;
create function tests.act_as(u uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', u::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create function tests.act_as_postgres() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
end $$;
create function tests.hid() returns uuid language sql stable as
  $$ select current_setting('tests.hid')::uuid $$;
grant execute on function tests.act_as(uuid), tests.act_as_postgres(), tests.hid() to authenticated;

insert into auth.users (id, email, aud, role) values
  ('11111111-1111-1111-1111-111111111111', 'o@test.dev', 'authenticated', 'authenticated'),
  ('33333333-3333-3333-3333-333333333333', 'e@test.dev', 'authenticated', 'authenticated'),
  ('44444444-4444-4444-4444-444444444444', 'v@test.dev', 'authenticated', 'authenticated');

select tests.act_as('11111111-1111-1111-1111-111111111111');
select set_config('tests.hid', public.create_household('The Tans', 'SGD', 'Olivia')::text, true);
select tests.act_as_postgres();
insert into public.members (household_id, user_id, role, display_name) values
  (tests.hid(), '33333333-3333-3333-3333-333333333333', 'editor', 'Elena'),
  (tests.hid(), '44444444-4444-4444-4444-444444444444', 'viewer', 'Vik');

-- A client with a clock in 2001 cannot choose updated_at: the server stamps it.
select tests.act_as('33333333-3333-3333-3333-333333333333');
insert into public.expenses (id, household_id, amount_cents, category_id, spent_on, created_by, updated_at)
values ('aaaaaaaa-0000-0000-0000-000000000001', tests.hid(), 500, 'default-food', '2026-10-01',
        '33333333-3333-3333-3333-333333333333', '2001-01-01T00:00:00Z');
select cmp_ok((select updated_at from public.expenses), '>', now() - interval '1 minute',
  'insert: updated_at is server time, not the client clock');

-- Updates move updated_at strictly forward, even when the client sends an older value.
select set_config('tests.t1', (select updated_at::text from public.expenses), true);
update public.expenses set amount_cents = 600, updated_at = '2001-01-01T00:00:00Z'
 where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select cmp_ok((select updated_at from public.expenses), '>', current_setting('tests.t1')::timestamptz,
  'update: updated_at only moves forward');

-- Soft delete is stamped with server time and kept on later updates.
update public.expenses set deleted_at = '2001-01-01T00:00:00Z'
 where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select cmp_ok((select deleted_at from public.expenses), '>', now() - interval '1 minute',
  'soft delete: deleted_at is server time');
select is((select deleted_at from public.expenses), (select updated_at from public.expenses),
  'soft delete: deleted_at equals the stamped updated_at');
select set_config('tests.d1', (select deleted_at::text from public.expenses), true);
update public.expenses set note = 'still deleted' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select is((select deleted_at::text from public.expenses), current_setting('tests.d1'),
  'a deleted row keeps its original delete time');

-- Restoring clears the flag.
update public.expenses set deleted_at = null where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select is((select deleted_at from public.expenses), null, 'restore clears deleted_at');

-- The pull query (changes since a cursor) sees the row, deleted or not.
select is((select count(*)::int from public.expenses
            where household_id = tests.hid() and updated_at > now() - interval '1 minute'), 1,
  'a pull since a recent cursor returns the row');

-- A viewer is still rejected by Row Level Security for writes that go through the same trigger.
select tests.act_as('44444444-4444-4444-4444-444444444444');
select is_empty($$ update public.expenses set amount_cents = 1 returning id $$,
  'viewer: update changes nothing');
select throws_ok($$
  insert into public.expenses (id, household_id, amount_cents, category_id, spent_on, created_by)
  values ('aaaaaaaa-0000-0000-0000-000000000002', tests.hid(), 100, 'default-food', '2026-10-02',
          '44444444-4444-4444-4444-444444444444') $$, '42501', null,
  'viewer: insert is rejected');

select * from finish();
rollback;
