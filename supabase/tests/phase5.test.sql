-- pgTAP tests for budgets, goals, goal contributions and bills (Phase 5).
-- Everyone in the household reads; only owner and admin write; outsiders see nothing.
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

-- ---------------------------------------------------------------------------
-- Budgets: fixed text ids, owner and admin write
-- ---------------------------------------------------------------------------
select tests.act_as('22222222-2222-2222-2222-222222222222');
insert into public.budgets (id, household_id, month, category_id, amount_cents)
values ('b:2026-10:overall', tests.hid(), '2026-10-01', null, 250000),
       ('b:2026-10:default-food', tests.hid(), '2026-10-01', 'default-food', 80000);
select is((select count(*)::int from public.budgets), 2, 'admin creates budgets with fixed text ids');
select throws_ok($$ insert into public.budgets (id, household_id, month, category_id, amount_cents)
  values ('b:2026-10:overall', tests.hid(), '2026-10-01', null, 1) $$, '23505', null,
  'the same budget id cannot exist twice in a household');
update public.budgets set amount_cents = 260000 where id = 'b:2026-10:overall';
select is((select amount_cents from public.budgets where id = 'b:2026-10:overall'), 260000, 'admin edits a budget');
select cmp_ok((select updated_at from public.budgets where id = 'b:2026-10:overall'), '>',
  now() - interval '1 minute', 'budget updated_at is server time');

select tests.act_as('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from public.budgets), 2, 'editor reads budgets');
select throws_ok($$ insert into public.budgets (id, household_id, month, amount_cents)
  values ('b:2026-11:overall', tests.hid(), '2026-11-01', 1) $$, '42501', null, 'editor cannot create a budget');
select is_empty($$ update public.budgets set amount_cents = 1 returning id $$, 'editor cannot edit a budget');
select is_empty($$ delete from public.budgets returning id $$, 'editor cannot delete a budget');

select tests.act_as('44444444-4444-4444-4444-444444444444');
select is((select count(*)::int from public.budgets), 2, 'viewer reads budgets');
select throws_ok($$ insert into public.budgets (id, household_id, month, amount_cents)
  values ('b:2026-11:overall', tests.hid(), '2026-11-01', 1) $$, '42501', null, 'viewer cannot create a budget');

select tests.act_as('55555555-5555-5555-5555-555555555555');
select is((select count(*)::int from public.budgets), 0, 'outsider sees no budgets');

-- ---------------------------------------------------------------------------
-- Goals and contributions
-- ---------------------------------------------------------------------------
select tests.act_as('11111111-1111-1111-1111-111111111111');
insert into public.goals (id, household_id, name, target_cents, saved_cents, monthly_cents, due_on)
values ('99999999-0000-0000-0000-000000000001', tests.hid(), 'Holiday trip', 300000, 100000, 15000, '2027-10-01');
insert into public.goal_contributions (id, household_id, goal_id, amount_cents, contributed_on, added_by)
values ('88888888-0000-0000-0000-000000000001', tests.hid(), '99999999-0000-0000-0000-000000000001',
        15000, '2026-10-15', '11111111-1111-1111-1111-111111111111');
select is((select count(*)::int from public.goal_contributions), 1, 'owner adds money to a goal');
select throws_ok($$ insert into public.goal_contributions (household_id, goal_id, amount_cents, contributed_on, added_by)
  values (tests.hid(), '99999999-0000-0000-0000-000000000001', 100, '2026-10-16', '22222222-2222-2222-2222-222222222222') $$,
  '42501', null, 'a contribution must be added by the caller');
select throws_ok($$ insert into public.goal_contributions (household_id, goal_id, amount_cents, contributed_on, added_by)
  values (tests.hid(), '99999999-0000-0000-0000-000000000001', 0, '2026-10-16', '11111111-1111-1111-1111-111111111111') $$,
  '23514', null, 'a contribution must be more than zero');

select tests.act_as('22222222-2222-2222-2222-222222222222');
update public.goal_contributions set deleted_at = now() where id = '88888888-0000-0000-0000-000000000001';
select isnt((select deleted_at from public.goal_contributions), null, 'admin soft deletes a contribution');
update public.goal_contributions set deleted_at = null where id = '88888888-0000-0000-0000-000000000001';

select tests.act_as('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from public.goals), 1, 'editor reads goals');
select is((select count(*)::int from public.goal_contributions), 1, 'editor reads contributions');
select throws_ok($$ insert into public.goals (household_id, name, target_cents) values (tests.hid(), 'x', 1) $$,
  '42501', null, 'editor cannot create a goal');
select throws_ok($$ insert into public.goal_contributions (household_id, goal_id, amount_cents, contributed_on, added_by)
  values (tests.hid(), '99999999-0000-0000-0000-000000000001', 100, '2026-10-16', '33333333-3333-3333-3333-333333333333') $$,
  '42501', null, 'editor cannot add money to a goal');
select is_empty($$ update public.goal_contributions set amount_cents = 1 returning id $$, 'editor cannot edit a contribution');

select tests.act_as('44444444-4444-4444-4444-444444444444');
select throws_ok($$ insert into public.goal_contributions (household_id, goal_id, amount_cents, contributed_on, added_by)
  values (tests.hid(), '99999999-0000-0000-0000-000000000001', 100, '2026-10-16', '44444444-4444-4444-4444-444444444444') $$,
  '42501', null, 'viewer cannot add money to a goal');

select tests.act_as('55555555-5555-5555-5555-555555555555');
select is((select count(*)::int from public.goals), 0, 'outsider sees no goals');
select is((select count(*)::int from public.goal_contributions), 0, 'outsider sees no contributions');

-- ---------------------------------------------------------------------------
-- Bills
-- ---------------------------------------------------------------------------
select tests.act_as('22222222-2222-2222-2222-222222222222');
insert into public.bills (id, household_id, name, amount_cents, due_day, repeat, next_due_on)
values ('77777777-0000-0000-0000-000000000001', tests.hid(), 'Electricity', 9640, 28, 'monthly', '2026-10-28');
select is((select next_due_on from public.bills), '2026-10-28'::date, 'admin creates a bill with its next due date');
update public.bills set next_due_on = '2026-11-28', last_paid_on = '2026-10-25'
 where id = '77777777-0000-0000-0000-000000000001';
select is((select next_due_on from public.bills), '2026-11-28'::date, 'marking paid moves the due date');
select throws_ok($$ insert into public.bills (household_id, name, amount_cents, due_day, repeat)
  values (tests.hid(), 'No date', 100, 1, 'monthly') $$, '23502', null, 'a bill needs a next due date');

select tests.act_as('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from public.bills), 1, 'editor reads bills');
select is_empty($$ update public.bills set next_due_on = '2030-01-01' returning id $$, 'editor cannot mark a bill paid');
select throws_ok($$ insert into public.bills (household_id, name, amount_cents, due_day, repeat, next_due_on)
  values (tests.hid(), 'x', 100, 1, 'monthly', '2026-11-01') $$, '42501', null, 'editor cannot create a bill');

select tests.act_as('44444444-4444-4444-4444-444444444444');
select is_empty($$ delete from public.bills returning id $$, 'viewer cannot delete a bill');

select tests.act_as('55555555-5555-5555-5555-555555555555');
select is((select count(*)::int from public.bills), 0, 'outsider sees no bills');

select * from finish();
rollback;
