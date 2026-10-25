-- pgTAP tests for receipt storage policies (Phase 6).
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

-- O owner, E editor (own only), V viewer (own only), X outsider
insert into auth.users (id, email, aud, role) values
  ('11111111-1111-1111-1111-111111111111', 'o@test.dev', 'authenticated', 'authenticated'),
  ('33333333-3333-3333-3333-333333333333', 'e@test.dev', 'authenticated', 'authenticated'),
  ('44444444-4444-4444-4444-444444444444', 'v@test.dev', 'authenticated', 'authenticated'),
  ('55555555-5555-5555-5555-555555555555', 'x@test.dev', 'authenticated', 'authenticated');

select tests.act_as('11111111-1111-1111-1111-111111111111');
select set_config('tests.hid', public.create_household('The Tans', 'SGD', 'Olivia')::text, true);
select tests.act_as_postgres();
insert into public.members (household_id, user_id, role, display_name, visibility) values
  (tests.hid(), '33333333-3333-3333-3333-333333333333', 'editor', 'Elena', 'own'),
  (tests.hid(), '44444444-4444-4444-4444-444444444444', 'viewer', 'Vik', 'own');

select is((select public from storage.buckets where id = 'receipts'), false, 'the bucket is private');

-- Editors upload into their own household folder.
select tests.act_as('33333333-3333-3333-3333-333333333333');
select lives_ok(
  format($f$insert into storage.objects (bucket_id, name, owner) values ('receipts', '%s/e1.jpg', auth.uid())$f$, tests.hid()),
  'an editor can upload a receipt for the household');
select throws_ok(
  $f$insert into storage.objects (bucket_id, name, owner) values ('receipts', '99999999-9999-9999-9999-999999999999/e1.jpg', auth.uid())$f$,
  null, null, 'an editor cannot upload into another household');

select tests.act_as('44444444-4444-4444-4444-444444444444');
select throws_ok(
  format($f$insert into storage.objects (bucket_id, name, owner) values ('receipts', '%s/v1.jpg', auth.uid())$f$, tests.hid()),
  null, null, 'a viewer cannot upload');

select tests.act_as('55555555-5555-5555-5555-555555555555');
select throws_ok(
  format($f$insert into storage.objects (bucket_id, name, owner) values ('receipts', '%s/x1.jpg', auth.uid())$f$, tests.hid()),
  null, null, 'an outsider cannot upload');

-- Reads follow the expense that points at the file.
select tests.act_as_postgres();
insert into public.expenses (id, household_id, amount_cents, category_id, spent_on, created_by, receipt_path) values
  ('aaaaaaaa-0000-0000-0000-000000000001', tests.hid(), 1000, 'default-food', '2026-10-01',
   '33333333-3333-3333-3333-333333333333', tests.hid()::text || '/e1.jpg');

select tests.act_as('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from storage.objects where bucket_id = 'receipts' and name like '%/e1.jpg'), 1,
  'the author sees the receipt');
select tests.act_as('11111111-1111-1111-1111-111111111111');
select is((select count(*)::int from storage.objects where bucket_id = 'receipts' and name like '%/e1.jpg'), 1,
  'the owner sees the receipt');
select tests.act_as('44444444-4444-4444-4444-444444444444');
select is((select count(*)::int from storage.objects where bucket_id = 'receipts' and name like '%/e1.jpg'), 0,
  'a member who cannot see the expense cannot see the receipt');
select tests.act_as('55555555-5555-5555-5555-555555555555');
select is((select count(*)::int from storage.objects where bucket_id = 'receipts'), 0,
  'an outsider sees nothing');

select * from finish();
rollback;
