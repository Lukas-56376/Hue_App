-- ============================================================
-- Hausübungen – ALLES IN EINEM SQL
-- Einmal im Supabase SQL Editor ausführen (idempotent)
-- Admins: daweed@lukio.site, nico@lukio.site (+ app_admins)
-- ============================================================

create extension if not exists pgcrypto;

-- ─── Helpers ───
create or replace function public.is_hu_admin()
returns boolean language sql stable security definer set search_path = public
as $$
  select
    lower(coalesce(auth.jwt()->>'email','')) in (
      'daweed@lukio.site',
      'nico@lukio.site'
    )
    or exists (
      select 1 from public.app_admins a
      where lower(a.email) = lower(coalesce(auth.jwt()->>'email',''))
    )
$$;

-- app_admins muss vor is_hu_admin-Referenz existieren → Tabelle zuerst, Function danach erneut
create table if not exists public.app_admins (
  email text primary key,
  created_at timestamptz not null default now()
);
alter table public.app_admins enable row level security;
drop policy if exists "app_admins_select" on public.app_admins;
drop policy if exists "app_admins_admin" on public.app_admins;
create policy "app_admins_select" on public.app_admins for select to authenticated using (true);
create policy "app_admins_admin" on public.app_admins for all to authenticated
  using (lower(coalesce(auth.jwt()->>'email','')) in ('daweed@lukio.site','nico@lukio.site')
         or exists (select 1 from public.app_admins x where lower(x.email)=lower(coalesce(auth.jwt()->>'email',''))))
  with check (lower(coalesce(auth.jwt()->>'email','')) in ('daweed@lukio.site','nico@lukio.site')
         or exists (select 1 from public.app_admins x where lower(x.email)=lower(coalesce(auth.jwt()->>'email',''))));

create or replace function public.is_hu_admin()
returns boolean language sql stable security definer set search_path = public
as $$
  select
    lower(coalesce(auth.jwt()->>'email','')) in (
      'daweed@lukio.site',
      'nico@lukio.site'
    )
    or exists (
      select 1 from public.app_admins a
      where lower(a.email) = lower(coalesce(auth.jwt()->>'email',''))
    )
$$;

create or replace function public.can_write_class_hu()
returns boolean language sql stable security definer set search_path = public
as $$ select public.is_hu_admin() or exists (
  select 1 from public.klassen_hu_permissions p
  where p.user_id = auth.uid() and p.can_write = true
) $$;

-- ─── Persönliche HÜ ───
create table if not exists public.hausuebungen (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null,
  subject text not null default '',
  due date,
  note text not null default '',
  done boolean not null default false,
  done_at timestamptz,
  important boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);
alter table public.hausuebungen add column if not exists important boolean not null default false;
alter table public.hausuebungen add column if not exists sort_order integer not null default 0;
alter table public.hausuebungen enable row level security;
drop policy if exists "eigene_hausuebungen" on public.hausuebungen;
create policy "eigene_hausuebungen" on public.hausuebungen for all to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- ─── Klassen-Schreibrechte ───
create table if not exists public.klassen_hu_permissions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  user_email text not null unique,
  can_write boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.klassen_hu_permissions enable row level security;
drop policy if exists "permissions_admin_select" on public.klassen_hu_permissions;
drop policy if exists "permissions_admin_insert" on public.klassen_hu_permissions;
drop policy if exists "permissions_admin_update" on public.klassen_hu_permissions;
drop policy if exists "permissions_admin_delete" on public.klassen_hu_permissions;
create policy "permissions_admin_select" on public.klassen_hu_permissions for select to authenticated
  using (public.is_hu_admin() or user_id = auth.uid());
create policy "permissions_admin_insert" on public.klassen_hu_permissions for insert to authenticated
  with check (public.is_hu_admin());
create policy "permissions_admin_update" on public.klassen_hu_permissions for update to authenticated
  using (public.is_hu_admin()) with check (public.is_hu_admin());
create policy "permissions_admin_delete" on public.klassen_hu_permissions for delete to authenticated
  using (public.is_hu_admin());

-- ─── Klassen-HÜ ───
create table if not exists public.klassen_huebungen (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  subject text not null default '',
  due date,
  note text not null default '',
  done boolean not null default false,
  done_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_by_email text not null,
  created_by_name text not null,
  created_at timestamptz not null default now()
);
alter table public.klassen_huebungen enable row level security;
drop policy if exists "class_hu_select" on public.klassen_huebungen;
drop policy if exists "class_hu_insert" on public.klassen_huebungen;
drop policy if exists "class_hu_update" on public.klassen_huebungen;
drop policy if exists "class_hu_delete" on public.klassen_huebungen;
create policy "class_hu_select" on public.klassen_huebungen for select to authenticated using (true);
create policy "class_hu_insert" on public.klassen_huebungen for insert to authenticated
  with check (public.can_write_class_hu() and created_by = auth.uid());
create policy "class_hu_update" on public.klassen_huebungen for update to authenticated
  using (public.is_hu_admin() or created_by = auth.uid())
  with check (public.is_hu_admin() or created_by = auth.uid());
create policy "class_hu_delete" on public.klassen_huebungen for delete to authenticated
  using (public.is_hu_admin() or created_by = auth.uid());

-- ─── Klassen-HÜ Erledigungen ───
create table if not exists public.class_hu_completions (
  class_hu_id uuid not null references public.klassen_huebungen(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  done boolean not null default true,
  done_at timestamptz,
  primary key (class_hu_id, user_id)
);
alter table public.class_hu_completions enable row level security;
drop policy if exists "completions_select" on public.class_hu_completions;
drop policy if exists "completions_own" on public.class_hu_completions;
create policy "completions_select" on public.class_hu_completions for select to authenticated using (true);
create policy "completions_own" on public.class_hu_completions for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ─── Unterlagen ───
create table if not exists public.unterlagen (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  subject text not null default '',
  note text not null default '',
  created_by uuid not null references auth.users(id) on delete restrict,
  created_by_email text,
  created_by_name text,
  created_at timestamptz not null default now()
);
alter table public.unterlagen enable row level security;
drop policy if exists "unterlagen_select" on public.unterlagen;
drop policy if exists "unterlagen_insert" on public.unterlagen;
drop policy if exists "unterlagen_update" on public.unterlagen;
drop policy if exists "unterlagen_delete" on public.unterlagen;
create policy "unterlagen_select" on public.unterlagen for select to authenticated using (true);
create policy "unterlagen_insert" on public.unterlagen for insert to authenticated
  with check (public.can_write_class_hu() and created_by = auth.uid());
create policy "unterlagen_update" on public.unterlagen for update to authenticated
  using (public.is_hu_admin() or created_by = auth.uid())
  with check (public.is_hu_admin() or created_by = auth.uid());
create policy "unterlagen_delete" on public.unterlagen for delete to authenticated
  using (public.is_hu_admin() or created_by = auth.uid());

-- ─── Dateien ───
create table if not exists public.hu_files (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  personal_id uuid references public.hausuebungen(id) on delete cascade,
  class_id uuid references public.klassen_huebungen(id) on delete cascade,
  unterlage_id uuid references public.unterlagen(id) on delete cascade,
  path text not null,
  name text not null,
  mime text,
  size bigint,
  created_at timestamptz not null default now()
);
alter table public.hu_files add column if not exists unterlage_id uuid references public.unterlagen(id) on delete cascade;
alter table public.hu_files enable row level security;
drop policy if exists "hu_files_select" on public.hu_files;
drop policy if exists "hu_files_insert" on public.hu_files;
drop policy if exists "hu_files_delete" on public.hu_files;
create policy "hu_files_select" on public.hu_files for select to authenticated using (true);
create policy "hu_files_insert" on public.hu_files for insert to authenticated
  with check (owner_id = auth.uid());
create policy "hu_files_delete" on public.hu_files for delete to authenticated
  using (owner_id = auth.uid() or public.is_hu_admin());

-- ─── Lösungen ───
create table if not exists public.hu_solutions (
  id uuid primary key default gen_random_uuid(),
  class_hu_id uuid not null references public.klassen_huebungen(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  owner_name text,
  path text not null,
  name text not null,
  mime text,
  size bigint,
  created_at timestamptz not null default now()
);
alter table public.hu_solutions enable row level security;
drop policy if exists "hu_solutions_select" on public.hu_solutions;
drop policy if exists "hu_solutions_insert" on public.hu_solutions;
drop policy if exists "hu_solutions_delete" on public.hu_solutions;
create policy "hu_solutions_select" on public.hu_solutions for select to authenticated using (true);
create policy "hu_solutions_insert" on public.hu_solutions for insert to authenticated
  with check (owner_id = auth.uid());
create policy "hu_solutions_delete" on public.hu_solutions for delete to authenticated
  using (owner_id = auth.uid() or public.is_hu_admin());

-- ─── Kommentare & Links ───
create table if not exists public.hu_comments (
  id uuid primary key default gen_random_uuid(),
  personal_id uuid references public.hausuebungen(id) on delete cascade,
  class_id uuid references public.klassen_huebungen(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  author_name text,
  body text not null,
  created_at timestamptz not null default now()
);
alter table public.hu_comments enable row level security;
drop policy if exists "hu_comments_select" on public.hu_comments;
drop policy if exists "hu_comments_insert" on public.hu_comments;
drop policy if exists "hu_comments_delete" on public.hu_comments;
create policy "hu_comments_select" on public.hu_comments for select to authenticated using (true);
create policy "hu_comments_insert" on public.hu_comments for insert to authenticated
  with check (user_id = auth.uid());
create policy "hu_comments_delete" on public.hu_comments for delete to authenticated
  using (user_id = auth.uid() or public.is_hu_admin());

create table if not exists public.hu_links (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  personal_id uuid references public.hausuebungen(id) on delete cascade,
  class_id uuid references public.klassen_huebungen(id) on delete cascade,
  title text not null default '',
  url text not null,
  created_at timestamptz not null default now()
);
alter table public.hu_links enable row level security;
drop policy if exists "hu_links_select" on public.hu_links;
drop policy if exists "hu_links_insert" on public.hu_links;
drop policy if exists "hu_links_delete" on public.hu_links;
create policy "hu_links_select" on public.hu_links for select to authenticated using (true);
create policy "hu_links_insert" on public.hu_links for insert to authenticated
  with check (owner_id = auth.uid());
create policy "hu_links_delete" on public.hu_links for delete to authenticated
  using (owner_id = auth.uid() or public.is_hu_admin());

-- ─── Push ───
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null,
  subscription jsonb not null,
  created_at timestamptz not null default now(),
  unique (user_id, endpoint)
);
alter table public.push_subscriptions enable row level security;
drop policy if exists "push_own" on public.push_subscriptions;
create policy "push_own" on public.push_subscriptions for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ─── Aktivität ───
create table if not exists public.activity_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  action text not null,
  detail text,
  created_at timestamptz not null default now()
);
create index if not exists activity_logs_created_idx on public.activity_logs(created_at desc);
alter table public.activity_logs enable row level security;
drop policy if exists "activity_select" on public.activity_logs;
drop policy if exists "activity_insert" on public.activity_logs;
create policy "activity_select" on public.activity_logs for select to authenticated using (true);
create policy "activity_insert" on public.activity_logs for insert to authenticated
  with check (user_id = auth.uid());

-- ─── Password resets ───
create table if not exists public.password_resets (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  code text not null,
  used boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists password_resets_email_idx on public.password_resets(lower(email));
alter table public.password_resets enable row level security;
-- Zugriff nur über Edge Function (service_role)

-- ─── IP Logs & Bans ───
create table if not exists public.ip_logs (
  id uuid primary key default gen_random_uuid(),
  ip text not null,
  action text not null,
  user_id uuid,
  user_email text,
  user_agent text,
  detail text,
  created_at timestamptz not null default now()
);
create index if not exists ip_logs_created_idx on public.ip_logs(created_at desc);
create index if not exists ip_logs_ip_idx on public.ip_logs(ip);
alter table public.ip_logs enable row level security;
drop policy if exists "ip_logs_admin_select" on public.ip_logs;
create policy "ip_logs_admin_select" on public.ip_logs for select to authenticated
  using (public.is_hu_admin());

create table if not exists public.ip_bans (
  ip text primary key,
  reason text,
  active boolean not null default true,
  banned_by text,
  created_at timestamptz not null default now()
);
alter table public.ip_bans enable row level security;
drop policy if exists "ip_bans_select" on public.ip_bans;
drop policy if exists "ip_bans_admin" on public.ip_bans;
create policy "ip_bans_select" on public.ip_bans for select to authenticated using (true);
create policy "ip_bans_admin" on public.ip_bans for all to authenticated
  using (public.is_hu_admin()) with check (public.is_hu_admin());

-- ─── User bans (Account) ───
create table if not exists public.user_bans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  user_email text not null,
  reason text,
  banned_by text,
  active boolean not null default true,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.user_bans add column if not exists expires_at timestamptz;
create index if not exists user_bans_email_idx on public.user_bans (lower(user_email));
create index if not exists user_bans_active_idx on public.user_bans (active) where active = true;
alter table public.user_bans enable row level security;
drop policy if exists "user_bans_select" on public.user_bans;
drop policy if exists "user_bans_admin_all" on public.user_bans;
create policy "user_bans_select" on public.user_bans for select to authenticated using (true);
create policy "user_bans_admin_all" on public.user_bans for all to authenticated
  using (public.is_hu_admin()) with check (public.is_hu_admin());

-- ─── Admin messages ───
create table if not exists public.admin_messages (
  id uuid primary key default gen_random_uuid(),
  to_user_id uuid references auth.users(id) on delete cascade,
  to_email text not null,
  from_email text not null,
  body text not null,
  reply text,
  replied_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists admin_messages_to_idx on public.admin_messages (to_user_id, created_at desc);
create index if not exists admin_messages_email_idx on public.admin_messages (lower(to_email));
alter table public.admin_messages enable row level security;
drop policy if exists "admin_messages_select" on public.admin_messages;
drop policy if exists "admin_messages_insert" on public.admin_messages;
drop policy if exists "admin_messages_update" on public.admin_messages;
create policy "admin_messages_select" on public.admin_messages for select to authenticated
  using (
    lower(to_email) = lower(coalesce(auth.jwt()->>'email',''))
    or public.is_hu_admin()
  );
create policy "admin_messages_insert" on public.admin_messages for insert to authenticated
  with check (
    lower(coalesce(auth.jwt()->>'email','')) = 'daweed@lukio.site'
    or public.is_hu_admin()
  );
create policy "admin_messages_update" on public.admin_messages for update to authenticated
  using (
    lower(to_email) = lower(coalesce(auth.jwt()->>'email',''))
    or public.is_hu_admin()
  );

-- ─── Super admin logs ───
create table if not exists public.super_admin_logs (
  id uuid primary key default gen_random_uuid(),
  actor_email text,
  action text not null,
  detail text,
  meta jsonb default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists super_admin_logs_created_idx on public.super_admin_logs (created_at desc);
alter table public.super_admin_logs enable row level security;
drop policy if exists "super_logs_select" on public.super_admin_logs;
drop policy if exists "super_logs_insert" on public.super_admin_logs;
create policy "super_logs_select" on public.super_admin_logs for select to authenticated
  using (lower(coalesce(auth.jwt()->>'email','')) = 'daweed@lukio.site');
create policy "super_logs_insert" on public.super_admin_logs for insert to authenticated
  with check (lower(coalesce(auth.jwt()->>'email','')) = 'daweed@lukio.site');

-- ─── App settings / Banner / Wartung ───
create table if not exists public.app_settings (
  key text primary key,
  value text,
  updated_at timestamptz not null default now()
);
alter table public.app_settings enable row level security;
drop policy if exists "app_settings_select" on public.app_settings;
drop policy if exists "app_settings_admin" on public.app_settings;
create policy "app_settings_select" on public.app_settings for select to authenticated using (true);
create policy "app_settings_admin" on public.app_settings for all to authenticated
  using (public.is_hu_admin()) with check (public.is_hu_admin());

-- ─── User settings (Erinnerungen) ───
create table if not exists public.user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  remind_time text default '10:00:00',
  stage_2d boolean default false,
  stage_1d boolean default true,
  stage_0d boolean default false,
  updated_at timestamptz default now()
);
alter table public.user_settings enable row level security;
drop policy if exists "user_settings_own" on public.user_settings;
create policy "user_settings_own" on public.user_settings for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ─── Broadcasts ───
create table if not exists public.app_broadcasts (
  id uuid primary key default gen_random_uuid(),
  body text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_by_name text,
  created_at timestamptz not null default now()
);
alter table public.app_broadcasts enable row level security;
drop policy if exists "broadcasts_select" on public.app_broadcasts;
drop policy if exists "broadcasts_admin" on public.app_broadcasts;
create policy "broadcasts_select" on public.app_broadcasts for select to authenticated using (true);
create policy "broadcasts_admin" on public.app_broadcasts for all to authenticated
  using (public.is_hu_admin()) with check (public.is_hu_admin());

-- ─── Geplante Pushes ───
create table if not exists public.scheduled_pushes (
  id uuid primary key default gen_random_uuid(),
  title text,
  body text not null,
  send_at timestamptz not null,
  sent boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.scheduled_pushes enable row level security;
drop policy if exists "sched_select" on public.scheduled_pushes;
drop policy if exists "sched_admin" on public.scheduled_pushes;
create policy "sched_select" on public.scheduled_pushes for select to authenticated
  using (public.is_hu_admin());
create policy "sched_admin" on public.scheduled_pushes for all to authenticated
  using (public.is_hu_admin()) with check (public.is_hu_admin());

-- ─── Reminder dedupe ───
create table if not exists public.reminder_sent (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  item_key text not null,
  stage text not null,
  sent_on date not null,
  created_at timestamptz not null default now(),
  unique (user_id, item_key, stage, sent_on)
);
alter table public.reminder_sent enable row level security;
-- nur service_role schreibt

-- ─── Content reports ───
create table if not exists public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid references auth.users(id) on delete set null,
  target_type text,
  target_id text,
  reason text,
  status text not null default 'open',
  created_at timestamptz not null default now()
);
alter table public.content_reports enable row level security;
drop policy if exists "reports_insert" on public.content_reports;
drop policy if exists "reports_admin" on public.content_reports;
create policy "reports_insert" on public.content_reports for insert to authenticated
  with check (reporter_id = auth.uid());
create policy "reports_admin" on public.content_reports for all to authenticated
  using (public.is_hu_admin()) with check (public.is_hu_admin());

-- ─── Tests & Schularbeiten ───
create table if not exists public.schularbeiten (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  subject text,
  kind text not null default 'test' check (kind in ('test', 'schularbeit')),
  exam_date date not null,
  stoff text,
  links jsonb not null default '[]'::jsonb,
  files jsonb not null default '[]'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_by_email text,
  created_by_name text,
  created_at timestamptz not null default now()
);
create index if not exists schularbeiten_exam_date_idx on public.schularbeiten (exam_date);
alter table public.schularbeiten enable row level security;
drop policy if exists "schularbeiten_select_auth" on public.schularbeiten;
drop policy if exists "schularbeiten_insert_admin" on public.schularbeiten;
drop policy if exists "schularbeiten_update_admin" on public.schularbeiten;
drop policy if exists "schularbeiten_delete_admin" on public.schularbeiten;
create policy "schularbeiten_select_auth" on public.schularbeiten for select to authenticated using (true);
create policy "schularbeiten_insert_admin" on public.schularbeiten for insert to authenticated
  with check (public.is_hu_admin());
create policy "schularbeiten_update_admin" on public.schularbeiten for update to authenticated
  using (public.is_hu_admin()) with check (public.is_hu_admin());
create policy "schularbeiten_delete_admin" on public.schularbeiten for delete to authenticated
  using (public.is_hu_admin());

-- ─── Storage bucket ───
insert into storage.buckets (id, name, public, file_size_limit)
values ('hu-files', 'hu-files', false, 10737418240)
on conflict (id) do update set file_size_limit = excluded.file_size_limit;

drop policy if exists "hu_storage_select" on storage.objects;
drop policy if exists "hu_storage_insert" on storage.objects;
drop policy if exists "hu_storage_update" on storage.objects;
drop policy if exists "hu_storage_delete" on storage.objects;
drop policy if exists "hu_storage_solutions_insert" on storage.objects;

create policy "hu_storage_select" on storage.objects
for select to authenticated using (bucket_id = 'hu-files');

create policy "hu_storage_insert" on storage.objects
for insert to authenticated with check (
  bucket_id = 'hu-files' and (
    ((storage.foldername(name))[1] = 'personal' and (storage.foldername(name))[2] = (select auth.uid()::text))
    or ((storage.foldername(name))[1] = 'class' and public.can_write_class_hu())
    or ((storage.foldername(name))[1] = 'unterlagen' and public.can_write_class_hu())
    or ((storage.foldername(name))[1] = 'solutions')
    or ((storage.foldername(name))[1] = 'tests' and public.is_hu_admin())
  )
);

create policy "hu_storage_update" on storage.objects
for update to authenticated using (
  bucket_id = 'hu-files' and (
    ((storage.foldername(name))[1] = 'personal' and (storage.foldername(name))[2] = (select auth.uid()::text))
    or ((storage.foldername(name))[1] = 'class' and public.can_write_class_hu())
    or ((storage.foldername(name))[1] = 'unterlagen' and public.can_write_class_hu())
    or ((storage.foldername(name))[1] = 'solutions' and owner = (select auth.uid()))
    or ((storage.foldername(name))[1] = 'tests' and public.is_hu_admin())
  )
);

create policy "hu_storage_delete" on storage.objects
for delete to authenticated using (
  bucket_id = 'hu-files'
  and (owner = (select auth.uid()) or public.is_hu_admin())
);

-- ─── Grants ───
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- ─── Realtime ───
do $$ begin
  alter publication supabase_realtime add table public.hausuebungen;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.klassen_huebungen;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.class_hu_completions;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.unterlagen;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.hu_files;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.hu_solutions;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.activity_logs;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.app_settings;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.app_broadcasts;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.app_admins;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.ip_bans;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.user_bans;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.admin_messages;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.schularbeiten;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.content_reports;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.klassen_hu_permissions;
exception when duplicate_object then null; end $$;

-- Fertig

-- Rolle: nur Klassen-Broadcast
create table if not exists public.app_roles (
  email text not null,
  role text not null check (role in ('broadcast')),
  created_at timestamptz not null default now(),
  primary key (email, role)
);
alter table public.app_roles enable row level security;
drop policy if exists "app_roles_select" on public.app_roles;
drop policy if exists "app_roles_admin" on public.app_roles;
create policy "app_roles_select" on public.app_roles for select to authenticated using (true);
create policy "app_roles_admin" on public.app_roles for all to authenticated
  using (public.is_hu_admin()) with check (public.is_hu_admin());

create or replace function public.can_broadcast()
returns boolean language sql stable security definer set search_path = public
as $$
  select public.is_hu_admin() or exists (
    select 1 from public.app_roles r
    where lower(r.email) = lower(coalesce(auth.jwt()->>'email',''))
      and r.role = 'broadcast'
  )
$$;

drop policy if exists "broadcasts_admin" on public.app_broadcasts;
drop policy if exists "broadcasts_write" on public.app_broadcasts;
create policy "broadcasts_write" on public.app_broadcasts for all to authenticated
  using (public.can_broadcast()) with check (public.can_broadcast());

grant select, insert, update, delete on public.app_roles to authenticated;

select 'HAUSUEBUNGEN-ALLES.sql OK' as status;
