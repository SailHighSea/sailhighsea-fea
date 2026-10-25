-- pgTAP tests for member visibility and per-person allowances (Phase 4c).
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

-- O owner, A admin, E editor (own only), V viewer (own only), H editor (household), X outsider
insert into auth.users (id, email, aud, role) values
  ('11111111-1111-1111-1111-111111111111', 'o@test.dev', 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', 'a@test.dev', 'authenticated', 'authenticated'),
  ('33333333-3333-3333-3333-333333333333', 'e@test.dev', 'authenticated', 'authenticated'),
  ('44444444-4444-4444-4444-444444444444', 'v@test.dev', 'authenticated', 'authenticated'),
  ('66666666-6666-6666-6666-666666666666', 'h@test.dev', 'authenticated', 'authenticated'),
  ('55555555-5555-5555-5555-555555555555', 'x@test.dev', 'authenticated', 'authenticated');

select tests.act_as('11111111-1111-1111-1111-111111111111');
select set_config('tests.hid', public.create_household('The Tans', 'SGD', 'Olivia')::text, true);
select tests.act_as_postgres();
insert into public.members (household_id, user_id, role, display_name, visibility) values
  (tests.hid(), '22222222-2222-2222-2222-222222222222', 'admin', 'Amir', 'household'),
  (tests.hid(), '33333333-3333-3333-3333-333333333333', 'editor', 'Elena', 'own'),
  (tests.hid(), '44444444-4444-4444-4444-444444444444', 'viewer', 'Vik', 'own'),
  (tests.hid(), '66666666-6666-6666-6666-666666666666', 'editor', 'Hana', 'household');
insert into public.expenses (id, household_id, amount_cents, category_id, spent_on, created_by) values
  ('aaaaaaaa-0000-0000-0000-000000000001', tests.hid(), 1000, 'default-food', '2026-10-01', '11111111-1111-1111-1111-111111111111'),
  ('aaaaaaaa-0000-0000-0000-000000000002', tests.hid(), 2000, 'default-food', '2026-10-02', '22222222-2222-2222-2222-222222222222'),
  ('aaaaaaaa-0000-0000-0000-000000000003', tests.hid(), 3000, 'default-food', '2026-10-03', '33333333-3333-3333-3333-333333333333'),
  ('aaaaaaaa-0000-0000-0000-000000000004', tests.hid(), 4000, 'default-food', '2026-10-04', '66666666-6666-6666-6666-666666666666');

-- Default visibility is what it was before: everyone sees everything.
select is((select visibility::text from public.members where user_id = '66666666-6666-6666-6666-666666666666'),
  'household', 'the default is household visibility');

-- ---------------------------------------------------------------------------
-- Who reads which expenses
-- ---------------------------------------------------------------------------
select tests.act_as('11111111-1111-1111-1111-111111111111');
select is((select count(*)::int from public.expenses), 4, 'owner sees every expense');
select tests.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from public.expenses), 4, 'admin sees every expense');
select tests.act_as('66666666-6666-6666-6666-666666666666');
select is((select count(*)::int from public.expenses), 4, 'a household-visibility editor sees every expense');

select tests.act_as('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from public.expenses), 1, 'an own-only editor sees one expense');
select is((select created_by from public.expenses), '33333333-3333-3333-3333-333333333333'::uuid,
  'and it is their own');
select is((select count(*)::int from public.expenses where created_by <> auth.uid()), 0,
  'an own-only editor cannot read anyone else''s expenses by filtering either');

select tests.act_as('44444444-4444-4444-4444-444444444444');
select is((select count(*)::int from public.expenses), 0, 'an own-only viewer who added nothing sees nothing');

select tests.act_as('55555555-5555-5555-5555-555555555555');
select is((select count(*)::int from public.expenses), 0, 'an outsider sees nothing');

-- An own-only editor can still add and then sees the new one.
select tests.act_as('33333333-3333-3333-3333-333333333333');
insert into public.expenses (id, household_id, amount_cents, category_id, spent_on, created_by)
values ('aaaaaaaa-0000-0000-0000-000000000005', tests.hid(), 500, 'default-food', '2026-10-05',
        '33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from public.expenses), 2, 'an own-only editor sees what they add');
update public.expenses set amount_cents = 600 where id = 'aaaaaaaa-0000-0000-0000-000000000005';
select is((select amount_cents from public.expenses where id = 'aaaaaaaa-0000-0000-0000-000000000005'), 600,
  'and can edit it');
select is_empty($$ update public.expenses set amount_cents = 1 where id = 'aaaaaaaa-0000-0000-0000-000000000001' returning id $$,
  'but cannot touch an expense they cannot see');

-- The owner and admin see the new one too.
select tests.act_as('11111111-1111-1111-1111-111111111111');
select is((select count(*)::int from public.expenses), 5, 'the owner sees the new expense');

-- ---------------------------------------------------------------------------
-- Changing visibility
-- ---------------------------------------------------------------------------
select tests.act_as('11111111-1111-1111-1111-111111111111');
update public.members set visibility = 'own' where user_id = '66666666-6666-6666-6666-666666666666';
select is((select visibility::text from public.members where user_id = '66666666-6666-6666-6666-666666666666'),
  'own', 'the owner sets a member to own only');
select tests.act_as('66666666-6666-6666-6666-666666666666');
select is((select count(*)::int from public.expenses), 1, 'and that member then sees only their own');

select tests.act_as('22222222-2222-2222-2222-222222222222');
update public.members set visibility = 'household' where user_id = '66666666-6666-6666-6666-666666666666';
select is((select visibility::text from public.members where user_id = '66666666-6666-6666-6666-666666666666'),
  'household', 'an admin can switch a member back');

select tests.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok($$ update public.members set visibility = 'household' where user_id = auth.uid() $$,
  '42501', null, 'a member cannot raise their own visibility');
select tests.act_as('66666666-6666-6666-6666-666666666666');
select throws_ok($$ update public.members set visibility = 'own' where user_id = auth.uid() $$,
  '42501', null, 'nor lower it');
select is_empty($$ update public.members set visibility = 'household'
  where user_id = '33333333-3333-3333-3333-333333333333' returning user_id $$,
  'an editor cannot change another member''s visibility');
select tests.act_as('44444444-4444-4444-4444-444444444444');
select is_empty($$ update public.members set visibility = 'household'
  where user_id = '33333333-3333-3333-3333-333333333333' returning user_id $$,
  'a viewer cannot change another member''s visibility');

-- Owner and admin are never own-only: promoting an own-only member resets it.
select tests.act_as('11111111-1111-1111-1111-111111111111');
update public.members set role = 'admin' where user_id = '33333333-3333-3333-3333-333333333333';
select is((select visibility::text from public.members where user_id = '33333333-3333-3333-3333-333333333333'),
  'household', 'a promoted member is back on household visibility');
select tests.act_as('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from public.expenses), 5, 'and now sees everything');

-- ---------------------------------------------------------------------------
-- Allowances (budgets with a user_id)
-- ---------------------------------------------------------------------------
select tests.act_as('11111111-1111-1111-1111-111111111111');
insert into public.budgets (id, household_id, month, user_id, amount_cents) values
  ('b:2026-10:user:44444444-4444-4444-4444-444444444444', tests.hid(), '2026-10-01',
   '44444444-4444-4444-4444-444444444444', 20000),
  ('b:2026-10:user:66666666-6666-6666-6666-666666666666', tests.hid(), '2026-10-01',
   '66666666-6666-6666-6666-666666666666', 30000),
  ('b:2026-10:overall', tests.hid(), '2026-10-01', null, 250000);
select is((select count(*)::int from public.budgets), 3, 'the owner sets allowances');
select throws_ok($$ insert into public.budgets (id, household_id, month, user_id, amount_cents)
  values ('dup', tests.hid(), '2026-10-01', '44444444-4444-4444-4444-444444444444', 1) $$,
  '23505', null, 'one allowance per person and month');

select tests.act_as('44444444-4444-4444-4444-444444444444');
select is((select count(*)::int from public.budgets), 2, 'a member sees the household budget and their own allowance');
select is((select count(*)::int from public.budgets where user_id is not null), 1, 'but not anyone else''s');
select throws_ok($$ insert into public.budgets (id, household_id, month, user_id, amount_cents)
  values ('b:2026-11:user:self', tests.hid(), '2026-11-01', auth.uid(), 999999) $$,
  '42501', null, 'a member cannot set their own allowance');

select tests.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from public.budgets), 3, 'an admin sees every allowance');
select tests.act_as('55555555-5555-5555-5555-555555555555');
select is((select count(*)::int from public.budgets), 0, 'an outsider sees none');

select * from finish();
rollback;
