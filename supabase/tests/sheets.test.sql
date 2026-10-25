-- pgTAP tests for the Google Sheets mirror (Phase 4b): who can see what, the queue trigger,
-- the debounce/claim/ack cycle, and that no client can reach the token.
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

-- O owner, A admin, E editor, V viewer, X outsider
insert into auth.users (id, email, aud, role) values
  ('11111111-1111-1111-1111-111111111111', 'o@test.dev', 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', 'a@test.dev', 'authenticated', 'authenticated'),
  ('33333333-3333-3333-3333-333333333333', 'e@test.dev', 'authenticated', 'authenticated'),
  ('44444444-4444-4444-4444-444444444444', 'v@test.dev', 'authenticated', 'authenticated'),
  ('55555555-5555-5555-5555-555555555555', 'x@test.dev', 'authenticated', 'authenticated');

select tests.act_as('11111111-1111-1111-1111-111111111111');
select set_config('tests.hid', public.create_household('The Tans', 'SGD', 'Olivia')::text, true);
select tests.act_as_postgres();
insert into public.members (household_id, user_id, role, display_name) values
  (tests.hid(), '22222222-2222-2222-2222-222222222222', 'admin', 'Amir'),
  (tests.hid(), '33333333-3333-3333-3333-333333333333', 'editor', 'Elena'),
  (tests.hid(), '44444444-4444-4444-4444-444444444444', 'viewer', 'Vik');

-- The edge function (service role) creates the connection.
insert into public.sheet_connections (household_id, owner_id, spreadsheet_id, spreadsheet_url, status, last_error)
values (tests.hid(), '11111111-1111-1111-1111-111111111111', 'sheet1', 'https://docs.google.com/x', 'active', 'quota');

-- ---------------------------------------------------------------------------
-- Who can read the connection
-- ---------------------------------------------------------------------------
select tests.act_as('11111111-1111-1111-1111-111111111111');
select is((select count(*)::int from public.sheet_connections), 1, 'owner reads the connection');
select throws_ok($$ select vault_secret_id from public.sheet_connections $$, '42501', null,
  'owner cannot read the Vault reference');
select throws_ok($$ insert into public.sheet_connections (household_id, owner_id) values (tests.hid(), auth.uid()) $$,
  '42501', null, 'owner cannot write the connection from a client');
select throws_ok($$ update public.sheet_connections set status = 'active' $$, '42501', null,
  'owner cannot update the connection from a client');
select throws_ok($$ delete from public.sheet_connections $$, '42501', null,
  'owner cannot delete the connection from a client');

select tests.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from public.sheet_connections), 0, 'admin cannot read the connection row');
select throws_ok($$ update public.sheet_connections set status = 'active' $$, '42501', null, 'admin cannot update it');
select tests.act_as('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from public.sheet_connections), 0, 'editor cannot read the connection row');
select tests.act_as('44444444-4444-4444-4444-444444444444');
select is((select count(*)::int from public.sheet_connections), 0, 'viewer cannot read the connection row');
select tests.act_as('55555555-5555-5555-5555-555555555555');
select is((select count(*)::int from public.sheet_connections), 0, 'outsider cannot read the connection row');

-- ---------------------------------------------------------------------------
-- The status view: members see the state, managers also the link and the error
-- ---------------------------------------------------------------------------
select tests.act_as('22222222-2222-2222-2222-222222222222');
select is((select spreadsheet_url from public.sheet_status), 'https://docs.google.com/x', 'admin sees the link');
select is((select last_error from public.sheet_status), 'quota', 'admin sees the error text');
select tests.act_as('44444444-4444-4444-4444-444444444444');
select is((select status from public.sheet_status), 'active', 'viewer sees the status');
select is((select spreadsheet_url from public.sheet_status), null, 'viewer does not get the link');
select is((select last_error from public.sheet_status), null, 'viewer does not get the error text');
select tests.act_as('55555555-5555-5555-5555-555555555555');
select is((select count(*)::int from public.sheet_status), 0, 'outsider sees no status');
select throws_ok($$ select * from public.sheet_status where false and vault_secret_id is null $$, '42703', null,
  'the view has no token reference column');

-- ---------------------------------------------------------------------------
-- No client can reach the queue, the OAuth state, the token functions or the Vault
-- ---------------------------------------------------------------------------
select tests.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok($$ select * from public.sheet_sync_queue $$, '42501', null, 'owner cannot read the queue');
select throws_ok($$ select * from public.sheet_oauth_states $$, '42501', null, 'owner cannot read OAuth states');
select throws_ok($$ select public.sheet_read_token(tests.hid()) $$, '42501', null, 'owner cannot call sheet_read_token');
select throws_ok($$ select public.sheet_store_token(tests.hid(), 'x') $$, '42501', null, 'owner cannot store a token');
select throws_ok($$ select public.sheet_claim_batch(tests.hid(), 10, true) $$, '42501', null, 'owner cannot claim queue rows');
select throws_ok($$ select * from vault.decrypted_secrets $$, '42501', null, 'owner cannot read the Vault');

-- ---------------------------------------------------------------------------
-- Queue trigger: create, edit, delete (one row per expense, newest op wins)
-- ---------------------------------------------------------------------------
select tests.act_as('33333333-3333-3333-3333-333333333333');
insert into public.expenses (id, household_id, amount_cents, category_id, spent_on, created_by)
values ('aaaaaaaa-0000-0000-0000-000000000001', tests.hid(), 1250, 'default-food', '2026-10-01',
        '33333333-3333-3333-3333-333333333333');
select tests.act_as_postgres();
select is((select op from public.sheet_sync_queue where expense_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'upsert', 'create queues an upsert');

select tests.act_as('33333333-3333-3333-3333-333333333333');
update public.expenses set amount_cents = 1300 where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select tests.act_as_postgres();
select is((select count(*)::int from public.sheet_sync_queue where expense_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  1, 'an edit replaces the queued row instead of adding one');

select tests.act_as('33333333-3333-3333-3333-333333333333');
update public.expenses set deleted_at = now() where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select tests.act_as_postgres();
select is((select op from public.sheet_sync_queue where expense_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'delete', 'a soft delete queues a delete');

select tests.act_as('33333333-3333-3333-3333-333333333333');
update public.expenses set deleted_at = null where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select tests.act_as_postgres();
select is((select op from public.sheet_sync_queue where expense_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'upsert', 'undoing the delete queues an upsert again');

-- A viewer's refused write queues nothing.
select tests.act_as('44444444-4444-4444-4444-444444444444');
select throws_ok($$ insert into public.expenses (id, household_id, amount_cents, category_id, spent_on, created_by)
  values ('aaaaaaaa-0000-0000-0000-000000000009', tests.hid(), 1, 'default-food', '2026-10-01',
          '44444444-4444-4444-4444-444444444444') $$, '42501', null, 'viewer insert is refused');
select tests.act_as_postgres();
select is((select count(*)::int from public.sheet_sync_queue where expense_id = 'aaaaaaaa-0000-0000-0000-000000000009'),
  0, 'a refused write is not queued');

-- ---------------------------------------------------------------------------
-- Debounce, claim and ack
-- ---------------------------------------------------------------------------
select is((select count(*)::int from public.sheet_due_households()), 0, 'a fresh change waits out the 30 s debounce');
select is((select count(*)::int from public.sheet_claim_batch(tests.hid(), 10, false)), 0,
  'claim without force skips rows younger than 30 s');
update public.sheet_sync_queue set enqueued_at = now() - interval '1 minute';
select is((select count(*)::int from public.sheet_due_households()), 1, 'after 30 s the household is due');
select is((select count(*)::int from public.sheet_claim_batch(tests.hid(), 10, false)), 1, 'claim returns the due row');
select is((select count(*)::int from public.sheet_claim_batch(tests.hid(), 10, false)), 0,
  'a claimed row is not handed out twice');

-- A change made after the claim keeps the row for the next run.
select set_config('tests.old', (select enqueued_at::text from public.sheet_sync_queue), true);
update public.sheet_sync_queue set enqueued_at = now(), claimed_at = null;
select public.sheet_ack(tests.hid(), jsonb_build_array(jsonb_build_object(
  'expense_id', 'aaaaaaaa-0000-0000-0000-000000000001', 'enqueued_at', current_setting('tests.old'))));
select is((select count(*)::int from public.sheet_sync_queue), 1, 'ack leaves a row that changed meanwhile');
select public.sheet_ack(tests.hid(), (select jsonb_agg(jsonb_build_object(
  'expense_id', expense_id, 'enqueued_at', enqueued_at)) from public.sheet_sync_queue));
select is((select count(*)::int from public.sheet_sync_queue), 0, 'ack removes written rows');

-- Force skips the debounce (Sync now).
select tests.act_as('33333333-3333-3333-3333-333333333333');
update public.expenses set note = 'again' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select tests.act_as_postgres();
select is((select count(*)::int from public.sheet_claim_batch(tests.hid(), 10, true)), 1, 'force claims at once');
select public.sheet_release(tests.hid());
select is((select count(*)::int from public.sheet_claim_batch(tests.hid(), 10, true)), 1, 'release gives claimed rows back');
delete from public.sheet_sync_queue;

-- ---------------------------------------------------------------------------
-- Backfill, revoked connections, status changes
-- ---------------------------------------------------------------------------
insert into public.expenses (id, household_id, amount_cents, category_id, spent_on, created_by) values
  ('aaaaaaaa-0000-0000-0000-000000000002', tests.hid(), 100, 'default-food', '2026-10-02', '33333333-3333-3333-3333-333333333333'),
  ('aaaaaaaa-0000-0000-0000-000000000003', tests.hid(), 200, 'default-food', '2026-10-03', '33333333-3333-3333-3333-333333333333');
delete from public.sheet_sync_queue;
select is(public.sheet_enqueue_backfill(tests.hid()), 3, 'backfill queues every live expense');
select is((select backfill_total from public.sheet_connections), 3, 'backfill remembers the total for the progress bar');
select is((select count(*)::int from public.sheet_due_households()), 1, 'backfill rows are due at once');

select public.sheet_set_status(tests.hid(), 'revoked', 'invalid_grant');
select is((select status from public.sheet_connections), 'revoked', 'status can be set to revoked');
delete from public.sheet_sync_queue;
update public.expenses set note = 'while revoked' where id = 'aaaaaaaa-0000-0000-0000-000000000002';
select is((select count(*)::int from public.sheet_sync_queue), 0, 'a revoked connection queues nothing');
select is((select count(*)::int from public.sheet_due_households()), 0, 'a revoked connection is never due');
select public.sheet_set_status(tests.hid(), 'active', null);
select isnt((select last_synced_at from public.sheet_connections), null, 'active sets the last synced time');

-- ---------------------------------------------------------------------------
-- Vault round trip (service role only)
-- ---------------------------------------------------------------------------
select public.sheet_store_token(tests.hid(), 'refresh-token-1');
select is(public.sheet_read_token(tests.hid()), 'refresh-token-1', 'token round trip through Vault');
select public.sheet_store_token(tests.hid(), 'refresh-token-2');
select is(public.sheet_read_token(tests.hid()), 'refresh-token-2', 'a second store replaces the token');
select is((select count(*)::int from public.sheet_connections where vault_secret_id is not null), 1,
  'the connection points at the secret');
select public.sheet_delete_token(tests.hid());
select is(public.sheet_read_token(tests.hid()), null, 'delete removes the token');

-- ---------------------------------------------------------------------------
-- Deleting the household cleans up
-- ---------------------------------------------------------------------------
select tests.act_as('11111111-1111-1111-1111-111111111111');
select isnt_empty($$ delete from public.households returning id $$, 'the owner deletes the household');
select tests.act_as_postgres();
select is((select count(*)::int from public.sheet_connections), 0, 'the connection goes with the household');

select * from finish();
rollback;
