-- Phase 3: tables from docs/SPEC.md section 5, enums and indexes.
-- Row Level Security, functions and grants are in the next migration.
-- Money is integer cents. Synced tables carry updated_at and deleted_at (soft delete).

create type public.member_role as enum ('owner', 'admin', 'editor', 'viewer');

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 80),
  currency text not null default 'SGD' check (currency ~ '^[A-Z]{3}$'),
  owner_id uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.members (
  household_id uuid not null references public.households (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role public.member_role not null,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 60),
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id)
);
-- One household per person in v1 (the app has one active household).
create unique index members_one_household_per_user on public.members (user_id);
-- Exactly one owner per household.
create unique index members_one_owner on public.members (household_id) where role = 'owner';

create table public.invites (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  -- HMAC-SHA256 (hex) of the normalised code with a server-side secret. The code itself is never stored.
  code_hash text not null unique,
  role public.member_role not null check (role in ('editor', 'viewer')),
  created_by uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_by uuid references auth.users (id) on delete set null,
  used_at timestamptz
);
create index invites_household_idx on public.invites (household_id, created_at desc);

-- Failed and successful redeem attempts, used only for rate limiting.
create table public.invite_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  ip text,
  success boolean not null,
  attempted_at timestamptz not null default now()
);
create index invite_attempts_user_idx on public.invite_attempts (user_id, attempted_at desc);
create index invite_attempts_ip_idx on public.invite_attempts (ip, attempted_at desc);

-- Category ids are text so the fixed default ids ('default-food', ...) match on every device.
create table public.categories (
  household_id uuid not null references public.households (id) on delete cascade,
  id text not null,
  name text not null check (char_length(btrim(name)) between 1 and 40),
  color text not null,
  icon text,
  sort int not null default 0,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (household_id, id)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  amount_cents int not null check (amount_cents > 0),
  category_id text not null,
  note text not null default '' check (char_length(note) <= 200),
  spent_on date not null,
  created_by uuid not null references auth.users (id) on delete restrict,
  receipt_path text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  foreign key (household_id, category_id) references public.categories (household_id, id)
    deferrable initially deferred
);
create index expenses_household_spent_idx on public.expenses (household_id, spent_on desc);
create index expenses_household_updated_idx on public.expenses (household_id, updated_at);
create index expenses_category_idx on public.expenses (household_id, category_id);

create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  month date not null check (extract(day from month) = 1),
  category_id text,
  amount_cents int not null check (amount_cents >= 0),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create unique index budgets_unique_idx
  on public.budgets (household_id, month, coalesce(category_id, ''))
  where deleted_at is null;

create table public.goals (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  target_cents int not null check (target_cents > 0),
  saved_cents int not null default 0 check (saved_cents >= 0),
  monthly_cents int not null default 0 check (monthly_cents >= 0),
  due_on date,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index goals_household_idx on public.goals (household_id);

create table public.bills (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  amount_cents int not null check (amount_cents > 0),
  due_day int not null check (due_day between 1 and 31),
  repeat text not null default 'monthly' check (repeat in ('monthly', 'weekly', 'yearly', 'once')),
  last_paid_on date,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index bills_household_idx on public.bills (household_id);
