-- pgTAP tests for Row Level Security and the invite functions (docs/SPEC.md sections 6 and 7).
-- Run with:  supabase test db        (needs `supabase start`, Docker)
-- Roles tested: owner (O), admin (A), editor (E), viewer (V), outsider (X), anonymous.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- pgTAP keeps results in temp tables; let the roles we switch to write to them.
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

create function tests.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role', 'anon', true);
end $$;

create function tests.act_as_postgres() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
end $$;

create function tests.hid() returns uuid language sql stable as
  $$ select current_setting('tests.hid')::uuid $$;
grant execute on function tests.act_as(uuid), tests.act_as_anon(),
  tests.act_as_postgres(), tests.hid() to authenticated, anon;

-- Fixed ids so the statements below stay readable.
-- O 1111..., A 2222..., E 3333..., V 4444..., X 5555..., N 6666... (newcomer), M 7777... (second newcomer)
insert into auth.users (id, email, aud, role) values
  ('11111111-1111-1111-1111-111111111111', 'o@test.dev', 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', 'a@test.dev', 'authenticated', 'authenticated'),
  ('33333333-3333-3333-3333-333333333333', 'e@test.dev', 'authenticated', 'authenticated'),
  ('44444444-4444-4444-4444-444444444444', 'v@test.dev', 'authenticated', 'authenticated'),
  ('55555555-5555-5555-5555-555555555555', 'x@test.dev', 'authenticated', 'authenticated'),
  ('66666666-6666-6666-6666-666666666666', 'n@test.dev', 'authenticated', 'authenticated'),
  ('77777777-7777-7777-7777-777777777777', 'm@test.dev', 'authenticated', 'authenticated');

-- ---------------------------------------------------------------------------
-- create_household: first sign-in makes the caller the owner and seeds categories
-- ---------------------------------------------------------------------------
select tests.act_as('11111111-1111-1111-1111-111111111111');
select set_config('tests.hid', public.create_household('The Tans', 'SGD', 'Olivia')::text, true);
select is((select role::text from public.members where user_id = '11111111-1111-1111-1111-111111111111'),
  'owner', 'create_household makes the caller the owner');
select is((select count(*)::int from public.categories where household_id = tests.hid()),
  6, 'create_household seeds the six default categories');
select throws_ok($$ select public.create_household('Second', 'SGD', 'Olivia') $$, '23505',
  null, 'a person can only be in one household');

select tests.act_as_postgres();
insert into public.members (household_id, user_id, role, display_name) values
  (tests.hid(), '22222222-2222-2222-2222-222222222222', 'admin', 'Amir'),
  (tests.hid(), '33333333-3333-3333-3333-333333333333', 'editor', 'Elena'),
  (tests.hid(), '44444444-4444-4444-4444-444444444444', 'viewer', 'Vik');
insert into public.expenses (id, household_id, amount_cents, category_id, spent_on, created_by) values
  ('aaaaaaaa-0000-0000-0000-000000000001', tests.hid(), 1250, 'default-food', '2026-10-01',
   '11111111-1111-1111-1111-111111111111');

-- ---------------------------------------------------------------------------
-- Reading: members see everything, outsiders and anonymous see nothing
-- ---------------------------------------------------------------------------
select tests.act_as('44444444-4444-4444-4444-444444444444');
select is((select count(*)::int from public.households), 1, 'viewer reads the household');
select is((select count(*)::int from public.members), 4, 'viewer reads all members');
select is((select count(*)::int from public.expenses), 1, 'viewer reads expenses');
select is((select count(*)::int from public.categories), 6, 'viewer reads categories');

select tests.act_as('55555555-5555-5555-5555-555555555555');
select is((select count(*)::int from public.households), 0, 'outsider sees no household');
select is((select count(*)::int from public.members), 0, 'outsider sees no members');
select is((select count(*)::int from public.expenses), 0, 'outsider sees no expenses');
select is((select count(*)::int from public.categories), 0, 'outsider sees no categories');

select tests.act_as_anon();
select throws_ok($$ select * from public.expenses $$, '42501', null, 'anonymous cannot read expenses');
select throws_ok($$ select * from public.households $$, '42501', null, 'anonymous cannot read households');

-- ---------------------------------------------------------------------------
-- Expenses: owner, admin, editor write; viewer and outsider cannot (server rejects)
-- ---------------------------------------------------------------------------
select tests.act_as('33333333-3333-3333-3333-333333333333');
select lives_ok($$ insert into public.expenses (household_id, amount_cents, category_id, spent_on, created_by)
  values (tests.hid(), 500, 'default-food', '2026-10-02', '33333333-3333-3333-3333-333333333333') $$,
  'editor adds an expense');
select throws_ok($$ insert into public.expenses (household_id, amount_cents, category_id, spent_on, created_by)
  values (tests.hid(), 500, 'default-food', '2026-10-02', '11111111-1111-1111-1111-111111111111') $$,
  '42501', null, 'editor cannot add an expense in someone else''s name');
select isnt_empty($$ update public.expenses set note = 'edited' where id = 'aaaaaaaa-0000-0000-0000-000000000001' returning id $$,
  'editor edits an expense');
select throws_ok($$ update public.expenses set created_by = '33333333-3333-3333-3333-333333333333'
  where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$, '42501', null, 'created_by can never be changed');
select isnt_empty($$ update public.expenses set deleted_at = now() where id = 'aaaaaaaa-0000-0000-0000-000000000001' returning id $$,
  'editor soft-deletes an expense');

select tests.act_as('22222222-2222-2222-2222-222222222222');
select lives_ok($$ insert into public.expenses (household_id, amount_cents, category_id, spent_on, created_by)
  values (tests.hid(), 700, 'default-bills', '2026-10-03', '22222222-2222-2222-2222-222222222222') $$,
  'admin adds an expense');

select tests.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok($$ insert into public.expenses (household_id, amount_cents, category_id, spent_on, created_by)
  values (tests.hid(), 900, 'default-fun', '2026-10-04', '11111111-1111-1111-1111-111111111111') $$,
  'owner adds an expense');

select tests.act_as('44444444-4444-4444-4444-444444444444');
select throws_ok($$ insert into public.expenses (household_id, amount_cents, category_id, spent_on, created_by)
  values (tests.hid(), 500, 'default-food', '2026-10-02', '44444444-4444-4444-4444-444444444444') $$,
  '42501', null, 'viewer cannot add an expense');
select is_empty($$ update public.expenses set note = 'hacked' returning id $$, 'viewer cannot edit expenses');
select is_empty($$ delete from public.expenses returning id $$, 'viewer cannot delete expenses');

select tests.act_as('55555555-5555-5555-5555-555555555555');
select throws_ok($$ insert into public.expenses (household_id, amount_cents, category_id, spent_on, created_by)
  values (tests.hid(), 500, 'default-food', '2026-10-02', '55555555-5555-5555-5555-555555555555') $$,
  '42501', null, 'outsider cannot add an expense');
select is_empty($$ update public.expenses set note = 'hacked' returning id $$, 'outsider cannot edit expenses');
select is_empty($$ delete from public.expenses returning id $$, 'outsider cannot delete expenses');

select tests.act_as_postgres();
select is((select count(*)::int from public.expenses where note = 'hacked'), 0, 'nothing was changed by viewer or outsider');

-- ---------------------------------------------------------------------------
-- Categories, budgets, goals, bills: owner and admin write, everyone else cannot
-- ---------------------------------------------------------------------------
select tests.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok($$ insert into public.categories (household_id, id, name, color) values (tests.hid(), 'c1', 'Pets', 'teal') $$,
  '42501', null, 'editor cannot add a category');
select throws_ok($$ insert into public.budgets (household_id, month, amount_cents) values (tests.hid(), '2026-10-01', 250000) $$,
  '42501', null, 'editor cannot set a budget');
select throws_ok($$ insert into public.goals (household_id, name, target_cents) values (tests.hid(), 'Trip', 100000) $$,
  '42501', null, 'editor cannot add a goal');
select throws_ok($$ insert into public.bills (household_id, name, amount_cents, due_day) values (tests.hid(), 'Rent', 100000, 1) $$,
  '42501', null, 'editor cannot add a bill');
select is_empty($$ update public.categories set name = 'x' returning id $$, 'editor cannot rename a category');

select tests.act_as('44444444-4444-4444-4444-444444444444');
select throws_ok($$ insert into public.budgets (household_id, month, amount_cents) values (tests.hid(), '2026-10-01', 250000) $$,
  '42501', null, 'viewer cannot set a budget');

select tests.act_as('22222222-2222-2222-2222-222222222222');
select lives_ok($$ insert into public.categories (household_id, id, name, color) values (tests.hid(), 'c1', 'Pets', 'teal') $$,
  'admin adds a category');
select lives_ok($$ insert into public.bills (household_id, name, amount_cents, due_day) values (tests.hid(), 'Rent', 100000, 1) $$,
  'admin adds a bill');

select tests.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok($$ insert into public.budgets (household_id, month, amount_cents) values (tests.hid(), '2026-10-01', 250000) $$,
  'owner sets a budget');
select lives_ok($$ insert into public.goals (household_id, name, target_cents) values (tests.hid(), 'Trip', 100000) $$,
  'owner adds a goal');

select tests.act_as('55555555-5555-5555-5555-555555555555');
select throws_ok($$ insert into public.budgets (household_id, month, amount_cents) values (tests.hid(), '2026-11-01', 1) $$,
  '42501', null, 'outsider cannot set a budget');

-- ---------------------------------------------------------------------------
-- Households and members
-- ---------------------------------------------------------------------------
select tests.act_as('33333333-3333-3333-3333-333333333333');
select is_empty($$ update public.households set name = 'Hijack' returning id $$, 'editor cannot rename the household');
select is_empty($$ delete from public.households returning id $$, 'editor cannot delete the household');

select tests.act_as('22222222-2222-2222-2222-222222222222');
select isnt_empty($$ update public.households set name = 'The Tan Family' returning id $$, 'admin renames the household');
select throws_ok($$ update public.households set owner_id = '22222222-2222-2222-2222-222222222222' $$,
  '42501', null, 'admin cannot take ownership by editing owner_id');
select is_empty($$ delete from public.households returning id $$, 'admin cannot delete the household');
select throws_ok($$ select public.transfer_ownership(tests.hid(), '22222222-2222-2222-2222-222222222222') $$,
  '42501', null, 'admin cannot transfer ownership');

select tests.act_as('55555555-5555-5555-5555-555555555555');
select is_empty($$ delete from public.households returning id $$, 'outsider cannot delete the household');
select throws_ok($$ insert into public.households (name, owner_id) values ('Mine', '55555555-5555-5555-5555-555555555555') $$,
  '42501', null, 'clients cannot insert households directly');
select throws_ok($$ insert into public.members (household_id, user_id, role, display_name)
  values (tests.hid(), '55555555-5555-5555-5555-555555555555', 'owner', 'Mallory') $$,
  '42501', null, 'outsider cannot add themself as a member');

select tests.act_as('44444444-4444-4444-4444-444444444444');
select throws_ok($$ insert into public.members (household_id, user_id, role, display_name)
  values (tests.hid(), '55555555-5555-5555-5555-555555555555', 'viewer', 'Friend') $$,
  '42501', null, 'viewer cannot add a member');
select throws_ok($$ update public.members set role = 'admin' where user_id = '44444444-4444-4444-4444-444444444444' $$,
  '42501', null, 'viewer cannot promote themself');

select tests.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok($$ update public.members set role = 'admin' where user_id = '33333333-3333-3333-3333-333333333333' $$,
  '42501', null, 'editor cannot promote themself');
select is_empty($$ update public.members set role = 'viewer' where user_id = '44444444-4444-4444-4444-444444444444' returning user_id $$,
  'editor cannot change another member''s role');
select is_empty($$ delete from public.members where user_id = '44444444-4444-4444-4444-444444444444' returning user_id $$,
  'editor cannot remove a member');
select lives_ok($$ update public.members set display_name = 'Elena T' where user_id = '33333333-3333-3333-3333-333333333333' $$,
  'a member can rename themself');

select tests.act_as('22222222-2222-2222-2222-222222222222');
select isnt_empty($$ update public.members set role = 'viewer' where user_id = '33333333-3333-3333-3333-333333333333' returning user_id $$,
  'admin changes an editor to view only');
select isnt_empty($$ update public.members set role = 'editor' where user_id = '33333333-3333-3333-3333-333333333333' returning user_id $$,
  'admin changes the role back');
select throws_ok($$ update public.members set role = 'owner' where user_id = '33333333-3333-3333-3333-333333333333' $$,
  '42501', null, 'admin cannot make anyone owner');
select is_empty($$ update public.members set role = 'viewer' where user_id = '11111111-1111-1111-1111-111111111111' returning user_id $$,
  'admin cannot change the owner''s role');
select throws_ok($$ update public.members set role = 'viewer' where user_id = '22222222-2222-2222-2222-222222222222' $$,
  '42501', null, 'admin cannot change their own role');
select throws_ok($$ update public.members set display_name = 'Renamed' where user_id = '44444444-4444-4444-4444-444444444444' $$,
  '42501', null, 'admin cannot rename someone else');
select is_empty($$ delete from public.members where user_id = '11111111-1111-1111-1111-111111111111' returning user_id $$,
  'admin cannot remove the owner');

select tests.act_as('11111111-1111-1111-1111-111111111111');
select isnt_empty($$ update public.members set role = 'admin' where user_id = '33333333-3333-3333-3333-333333333333' returning user_id $$,
  'owner promotes a member to admin');
select isnt_empty($$ update public.members set role = 'editor' where user_id = '33333333-3333-3333-3333-333333333333' returning user_id $$,
  'owner changes the role back');
select is_empty($$ delete from public.members where user_id = '11111111-1111-1111-1111-111111111111' returning user_id $$,
  'the owner cannot leave without transferring ownership');
select throws_ok($$ insert into public.members (household_id, user_id, role, display_name)
  values (tests.hid(), '55555555-5555-5555-5555-555555555555', 'owner', 'Second owner') $$,
  '42501', null, 'the owner cannot add members by direct insert either');

-- ---------------------------------------------------------------------------
-- Invites: created and redeemed through the service-role functions only
-- ---------------------------------------------------------------------------
select tests.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok($$ select public.create_invite_record(tests.hid(), '33333333-3333-3333-3333-333333333333', 'viewer', 'h-x') $$,
  '42501', null, 'clients cannot call create_invite_record');
select throws_ok($$ select public.redeem_invite('h-x', '33333333-3333-3333-3333-333333333333', 'E', null) $$,
  '42501', null, 'clients cannot call redeem_invite');
select throws_ok($$ insert into public.invites (household_id, code_hash, role, created_by, expires_at)
  values (tests.hid(), 'h-y', 'editor', '33333333-3333-3333-3333-333333333333', now() + interval '1 day') $$,
  '42501', null, 'clients cannot insert invites');

select tests.act_as_postgres();
select is(public.create_invite_record(tests.hid(), '33333333-3333-3333-3333-333333333333', 'viewer', 'h-e')->>'status',
  'forbidden', 'an editor cannot create invites');
select is(public.create_invite_record(tests.hid(), '55555555-5555-5555-5555-555555555555', 'viewer', 'h-x')->>'status',
  'forbidden', 'an outsider cannot create invites');
select is(public.create_invite_record(tests.hid(), '22222222-2222-2222-2222-222222222222', 'admin', 'h-a')->>'status',
  'bad_role', 'invites cannot carry the admin or owner role');
select is(public.create_invite_record(tests.hid(), '22222222-2222-2222-2222-222222222222', 'viewer', 'h-1')->>'status',
  'ok', 'an admin creates an invite');
select is(public.create_invite_record(tests.hid(), '11111111-1111-1111-1111-111111111111', 'editor', 'h-2')->>'status',
  'ok', 'the owner creates an invite');
select is((select (expires_at - created_at) from public.invites where code_hash = 'h-2'),
  interval '24 hours', 'invites expire in 24 hours');

select tests.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from public.invites), 2, 'admin sees the household''s invites');
select throws_ok($$ select code_hash from public.invites $$, '42501', null, 'code hashes are never readable');
select tests.act_as('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from public.invites), 0, 'editor cannot see invites');
select tests.act_as('22222222-2222-2222-2222-222222222222');
select isnt_empty($$ delete from public.invites i
  where id = (select id from public.invites order by created_at limit 1) returning id $$,
  'admin revokes an unused invite');

select tests.act_as_postgres();
-- h-2 (editor) is still open. Newcomer redeems it.
select is(public.redeem_invite('h-2', '66666666-6666-6666-6666-666666666666', 'Nina', '1.2.3.4')->>'status',
  'ok', 'a valid code joins the household');
select is((select role::text from public.members where user_id = '66666666-6666-6666-6666-666666666666'),
  'editor', 'the new member gets the invite''s role');
select is((select used_by from public.invites where code_hash = 'h-2'),
  '66666666-6666-6666-6666-666666666666'::uuid, 'the invite is marked used');
select is(public.redeem_invite('h-2', '77777777-7777-7777-7777-777777777777', 'Max', '1.2.3.5')->>'status',
  'invalid', 'a code works only once');
select is(public.redeem_invite('h-2', '66666666-6666-6666-6666-666666666666', 'Nina', '1.2.3.4')->>'status',
  'already_member', 'a member cannot join again');

insert into public.invites (household_id, code_hash, role, created_by, created_at, expires_at)
  values (tests.hid(), 'h-old', 'viewer', '11111111-1111-1111-1111-111111111111',
          now() - interval '25 hours', now() - interval '1 hour');
select is(public.redeem_invite('h-old', '77777777-7777-7777-7777-777777777777', 'Max', '1.2.3.5')->>'status',
  'invalid', 'an expired code is rejected');
select is((select count(*)::int from public.members where user_id = '77777777-7777-7777-7777-777777777777'),
  0, 'an expired code adds nobody');

-- Rate limit: 5 wrong tries lock the user even when the next code is valid.
select public.create_invite_record(tests.hid(), '11111111-1111-1111-1111-111111111111', 'editor', 'h-3');
select public.redeem_invite('wrong-' || g, '77777777-7777-7777-7777-777777777777', 'Max', '1.2.3.5')
  from generate_series(1, 2) g;
select is(public.redeem_invite('wrong-3', '77777777-7777-7777-7777-777777777777', 'Max', '1.2.3.5')->>'status',
  'invalid', 'the fifth wrong code is still just invalid');
select is(public.redeem_invite('h-3', '77777777-7777-7777-7777-777777777777', 'Max', '1.2.3.5')->>'status',
  'rate_limited', 'after five wrong codes even a valid code is locked out');

-- Rate limit per IP.
select public.redeem_invite('ip-' || g, ('88888888-8888-8888-8888-' || lpad(g::text, 12, '0'))::uuid, 'Bot', '9.9.9.9')
  from generate_series(1, 20) g;
select is(public.redeem_invite('h-1', '88888888-8888-8888-8888-999999999999', 'Fresh', '9.9.9.9')->>'status',
  'rate_limited', 'twenty wrong codes from one IP lock that IP');

-- Creating invites is limited too: ten per hour.
select public.create_invite_record(tests.hid(), '11111111-1111-1111-1111-111111111111', 'viewer', 'bulk-' || g)
  from generate_series(1, 8) g;
select is(public.create_invite_record(tests.hid(), '11111111-1111-1111-1111-111111111111', 'viewer', 'bulk-x')->>'status',
  'rate_limited', 'invite creation is rate limited');

-- ---------------------------------------------------------------------------
-- Leaving, removing and transferring ownership (last, they change the roster)
-- ---------------------------------------------------------------------------
select tests.act_as('44444444-4444-4444-4444-444444444444');
select isnt_empty($$ delete from public.members where user_id = '44444444-4444-4444-4444-444444444444' returning user_id $$,
  'a member can leave');

select tests.act_as('22222222-2222-2222-2222-222222222222');
select isnt_empty($$ delete from public.members where user_id = '66666666-6666-6666-6666-666666666666' returning user_id $$,
  'admin removes a member');

select tests.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok($$ select public.transfer_ownership(tests.hid(), '55555555-5555-5555-5555-555555555555') $$,
  '22023', null, 'ownership can only go to a member');
select lives_ok($$ select public.transfer_ownership(tests.hid(), '22222222-2222-2222-2222-222222222222') $$,
  'the owner transfers ownership');
select is((select role::text from public.members where user_id = '22222222-2222-2222-2222-222222222222'),
  'owner', 'the new owner is owner');
select is((select role::text from public.members where user_id = '11111111-1111-1111-1111-111111111111'),
  'admin', 'the old owner becomes admin');
select is((select owner_id from public.households), '22222222-2222-2222-2222-222222222222'::uuid,
  'households.owner_id follows');
select is_empty($$ delete from public.households returning id $$, 'the old owner can no longer delete the household');

select tests.act_as('22222222-2222-2222-2222-222222222222');
select isnt_empty($$ delete from public.households returning id $$, 'the owner deletes the household');
select tests.act_as_postgres();
select is((select count(*)::int from public.expenses), 0, 'deleting the household removes its data');

select * from finish();
rollback;
