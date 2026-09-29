-- EVĀRA / Eco Surfer Supabase setup
-- Run this once in Supabase SQL Editor.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  real_name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.player_stats (
  user_id uuid primary key references auth.users(id) on delete cascade,
  high_score integer not null default 0,
  games_played integer not null default 0,
  total_distance bigint not null default 0,
  total_clothes bigint not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.leaderboard (
  user_id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  score integer not null default 0,
  clothes integer not null default 0,
  distance integer not null default 0,
  grade text not null default 'F',
  reason text not null default 'landfill',
  timestamp timestamptz not null default now()
);

-- Automatically create the public profile + stats row when a Supabase Auth user is created.
create or replace function public.handle_new_evara_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, real_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', 'player'),
    coalesce(new.raw_user_meta_data->>'real_name', 'Eco Surfer')
  )
  on conflict (id) do update set
    username = excluded.username,
    real_name = excluded.real_name;

  insert into public.player_stats (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_evara on auth.users;
create trigger on_auth_user_created_evara
after insert on auth.users
for each row execute procedure public.handle_new_evara_user();

-- RLS
alter table public.profiles enable row level security;
alter table public.player_stats enable row level security;
alter table public.leaderboard enable row level security;

-- Profiles: public read is needed for username availability; users may only change their own profile.
drop policy if exists "profiles_public_read" on public.profiles;
create policy "profiles_public_read"
on public.profiles for select
using (true);

drop policy if exists "profiles_own_update" on public.profiles;
create policy "profiles_own_update"
on public.profiles for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

-- Stats: users can read/update only their own stats.
drop policy if exists "stats_own_read" on public.player_stats;
create policy "stats_own_read"
on public.player_stats for select
 to authenticated
using (auth.uid() = user_id);

drop policy if exists "stats_own_update" on public.player_stats;
create policy "stats_own_update"
on public.player_stats for update
 to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- Leaderboard: everyone can read; a logged-in player can only insert/update their own row.
drop policy if exists "leaderboard_public_read" on public.leaderboard;
create policy "leaderboard_public_read"
on public.leaderboard for select
using (true);

drop policy if exists "leaderboard_own_insert" on public.leaderboard;
create policy "leaderboard_own_insert"
on public.leaderboard for insert
 to authenticated
with check (auth.uid() = user_id);

drop policy if exists "leaderboard_own_update" on public.leaderboard;
create policy "leaderboard_own_update"
on public.leaderboard for update
 to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- Helpful indexes
create index if not exists leaderboard_score_idx on public.leaderboard (score desc);
create index if not exists leaderboard_timestamp_idx on public.leaderboard (timestamp desc);
create index if not exists profiles_username_lower_idx on public.profiles (lower(username));

-- Explicit least-privilege Data API grants.
grant select on public.profiles to anon, authenticated;
grant select on public.player_stats to authenticated;
grant update on public.player_stats to authenticated;
grant select on public.leaderboard to anon, authenticated;
grant insert, update on public.leaderboard to authenticated;
