-- Admin-Funktionen 1–19 (ein Rang, alle Admins gleich)
-- Im SQL Editor einmal ausführen.

create table if not exists public.app_admins (
  email text primary key,
  created_at timestamptz not null default now()
);

insert into public.app_admins (email) values
  ('daweed@lukio.site'),
  ('nico@lukio.site')
on conflict (email) do nothing;

create table if not exists public.app_settings (
  key text primary key,
  value text not null default '',
  updated_at timestamptz not null default now()
);

insert into public.app_settings (key, value) values
  ('maintenance', 'false'),
  ('banner_text', ''),
  ('last_reminder_at', ''),
  ('last_reminder_sent', '0'),
  ('backup_note', 'Supabase Dashboard → Database → Backups. Regelmäßig prüfen.')
on conflict (key) do nothing;

create table if not exists public.app_broadcasts (
  id uuid primary key default gen_random_uuid(),
  body text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_by_name text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.scheduled_pushes (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  send_at timestamptz not null,
  sent boolean not null default false,
  created_by_name text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.content_reports (
  id uuid primary key default gen_random_uuid(),
  class_hu_id uuid references public.klassen_huebungen(id) on delete cascade,
  title text not null default '',
  reason text not null default '',
  reporter_id uuid references auth.users(id) on delete set null,
  reporter_name text not null default '',
  status text not null default 'open',
  created_at timestamptz not null default now()
);

create or replace function public.is_hu_admin()
returns boolean language sql stable security definer set search_path = public
as $$
  select lower(coalesce(auth.jwt()->>'email','')) in (
    'daweed@lukio.site',
    'nico@lukio.site'
  )
  or exists (
    select 1 from public.app_admins a
    where a.email = lower(coalesce(auth.jwt()->>'email',''))
  );
$$;

alter table public.app_admins enable row level security;
alter table public.app_settings enable row level security;
alter table public.app_broadcasts enable row level security;
alter table public.scheduled_pushes enable row level security;
alter table public.content_reports enable row level security;

drop policy if exists "app_admins_select" on public.app_admins;
drop policy if exists "app_admins_write" on public.app_admins;
create policy "app_admins_select" on public.app_admins for select to authenticated using (true);
create policy "app_admins_write" on public.app_admins for all to authenticated
  using (public.is_hu_admin()) with check (public.is_hu_admin());

drop policy if exists "app_settings_select" on public.app_settings;
drop policy if exists "app_settings_write" on public.app_settings;
create policy "app_settings_select" on public.app_settings for select to authenticated using (true);
create policy "app_settings_write" on public.app_settings for all to authenticated
  using (public.is_hu_admin()) with check (public.is_hu_admin());

drop policy if exists "broadcasts_select" on public.app_broadcasts;
drop policy if exists "broadcasts_insert" on public.app_broadcasts;
drop policy if exists "broadcasts_delete" on public.app_broadcasts;
create policy "broadcasts_select" on public.app_broadcasts for select to authenticated using (true);
create policy "broadcasts_insert" on public.app_broadcasts for insert to authenticated
  with check (public.is_hu_admin() and created_by = auth.uid());
create policy "broadcasts_delete" on public.app_broadcasts for delete to authenticated
  using (public.is_hu_admin());

drop policy if exists "sched_select" on public.scheduled_pushes;
drop policy if exists "sched_write" on public.scheduled_pushes;
create policy "sched_select" on public.scheduled_pushes for select to authenticated using (true);
create policy "sched_write" on public.scheduled_pushes for all to authenticated
  using (public.is_hu_admin()) with check (public.is_hu_admin());

drop policy if exists "reports_select" on public.content_reports;
drop policy if exists "reports_insert" on public.content_reports;
drop policy if exists "reports_update" on public.content_reports;
drop policy if exists "reports_delete" on public.content_reports;
create policy "reports_select" on public.content_reports for select to authenticated
  using (public.is_hu_admin() or reporter_id = auth.uid());
create policy "reports_insert" on public.content_reports for insert to authenticated
  with check (reporter_id = auth.uid());
create policy "reports_update" on public.content_reports for update to authenticated
  using (public.is_hu_admin()) with check (public.is_hu_admin());
create policy "reports_delete" on public.content_reports for delete to authenticated
  using (public.is_hu_admin());
