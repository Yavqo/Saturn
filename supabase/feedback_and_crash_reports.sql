-- ==========================================================
-- Saturn: user feedback + crash reports
-- Run this once in the Supabase SQL editor (or as a migration).
--
-- The app can INSERT rows with the public anon key, but it can never read them back:
-- there is no select policy, and select is revoked. Read the data from the dashboard
-- (or with the service role key). Length limits keep junk submissions small.
-- ==========================================================

create table if not exists public.saturn_feedback (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  kind text not null default 'other' check (kind in ('bug', 'idea', 'other')),
  message text not null check (char_length(message) between 1 and 5000),
  email text check (email is null or char_length(email) <= 200),
  user_id uuid,
  app_version text check (app_version is null or char_length(app_version) <= 40),
  os_version text check (os_version is null or char_length(os_version) <= 120),
  device text check (device is null or char_length(device) <= 80)
);

create table if not exists public.saturn_crash_reports (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  crashed_at timestamptz,
  summary text check (summary is null or char_length(summary) <= 2000),
  exception text check (exception is null or char_length(exception) <= 400),
  details text check (details is null or char_length(details) <= 60000),
  note text check (note is null or char_length(note) <= 3000),
  user_id uuid,
  app_version text check (app_version is null or char_length(app_version) <= 40),
  os_version text check (os_version is null or char_length(os_version) <= 120),
  device text check (device is null or char_length(device) <= 80)
);

alter table public.saturn_feedback enable row level security;
alter table public.saturn_crash_reports enable row level security;

drop policy if exists "saturn_feedback_insert" on public.saturn_feedback;
create policy "saturn_feedback_insert" on public.saturn_feedback
  for insert to anon, authenticated with check (true);

drop policy if exists "saturn_crash_reports_insert" on public.saturn_crash_reports;
create policy "saturn_crash_reports_insert" on public.saturn_crash_reports
  for insert to anon, authenticated with check (true);

-- Insert-only, even if a select policy is added by mistake later
revoke all on public.saturn_feedback from anon, authenticated;
revoke all on public.saturn_crash_reports from anon, authenticated;
grant insert on public.saturn_feedback to anon, authenticated;
grant insert on public.saturn_crash_reports to anon, authenticated;
