-- ==========================================================
-- Saturn Browser Database Schema (All tables prefixed with saturn_)
-- ==========================================================

-- 1. Saturn Settings & Preferences
create table if not exists public.saturn_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  device_id text not null,
  default_search_engine text not null default 'Google',
  custom_search_template text default '',
  setup_completed boolean default true,
  theme text default 'dark_glass',
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),
  constraint saturn_settings_device_unique unique (device_id)
);

-- RLS for saturn_settings
alter table public.saturn_settings enable row level security;

drop policy if exists "saturn_settings_select" on public.saturn_settings;
create policy "saturn_settings_select" on public.saturn_settings
  for select using (true);

drop policy if exists "saturn_settings_insert" on public.saturn_settings;
create policy "saturn_settings_insert" on public.saturn_settings
  for insert with check (true);

drop policy if exists "saturn_settings_update" on public.saturn_settings;
create policy "saturn_settings_update" on public.saturn_settings
  for update using (true);

-- 2. Saturn User Profiles (for auth avatars)
create table if not exists public.saturn_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text,
  avatar_url text,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

-- Clean up legacy profiles table/view if migrating to saturn_profiles
drop table if exists public.profiles cascade;
drop view if exists public.profiles cascade;
create view public.profiles as select * from public.saturn_profiles;

-- Auto-create profile on signup
create or replace function public.handle_saturn_new_user()
returns trigger as $$
begin
  insert into public.saturn_profiles (id, username, avatar_url)
  values (new.id, new.email, null)
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_saturn_auth_user_created on auth.users;
create trigger on_saturn_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_saturn_new_user();

-- RLS for saturn_profiles
alter table public.saturn_profiles enable row level security;

drop policy if exists "saturn_profiles_select" on public.saturn_profiles;
create policy "saturn_profiles_select" on public.saturn_profiles
  for select using (true);

drop policy if exists "saturn_profiles_update_own" on public.saturn_profiles;
create policy "saturn_profiles_update_own" on public.saturn_profiles
  for update using (auth.uid() = id);

drop policy if exists "saturn_profiles_insert_own" on public.saturn_profiles;
create policy "saturn_profiles_insert_own" on public.saturn_profiles
  for insert with check (auth.uid() = id);

-- 3. Storage bucket for saturn avatars
insert into storage.buckets (id, name, public)
values ('saturn_avatars', 'saturn_avatars', true)
on conflict (id) do nothing;

drop policy if exists "saturn_avatars_public_read" on storage.objects;
create policy "saturn_avatars_public_read" on storage.objects
  for select using (bucket_id = 'saturn_avatars' or bucket_id = 'avatars');

drop policy if exists "saturn_avatars_user_upload" on storage.objects;
create policy "saturn_avatars_user_upload" on storage.objects
  for insert with check ((bucket_id = 'saturn_avatars' or bucket_id = 'avatars') and auth.role() = 'authenticated');

drop policy if exists "saturn_avatars_user_update" on storage.objects;
create policy "saturn_avatars_user_update" on storage.objects
  for update using ((bucket_id = 'saturn_avatars' or bucket_id = 'avatars') and auth.role() = 'authenticated');

