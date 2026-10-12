-- ============================================================
-- Hausübungen – KOMPLETTES SQL (einmal im SQL Editor ausführen)
-- Admins: daweed@lukio.site + nico@lukio.site
-- Idempotent: create if not exists / drop policy if exists
-- ============================================================

create extension if not exists pgcrypto;

-- Persönliche Hausübungen
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
-- Migration falls Tabelle schon existiert
alter table public.hausuebungen add column if not exists important boolean not null default false;
alter table public.hausuebungen add column if not exists sort_order integer not null default 0;

alter table public.hausuebungen enable row level security;
drop policy if exists "eigene_hausuebungen" on public.hausuebungen;
create policy "eigene_hausuebungen" on public.hausuebungen for all to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- Schreibrechte für Klassen-HÜ
create table if not exists public.klassen_hu_permissions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  user_email text not null unique,
  can_write boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.klassen_hu_permissions enable row level security;

create or replace function public.is_hu_admin()
returns boolean language sql stable security definer set search_path = public
as $$
  select lower(coalesce(auth.jwt()->>'email','')) in (
    'daweed@lukio.site',
    'nico@lukio.site'
  )
$$;

create or replace function public.can_write_class_hu()
returns boolean language sql stable security definer set search_path = public
as $$ select public.is_hu_admin() or exists (
  select 1 from public.klassen_hu_permissions p
  where p.user_id = auth.uid() and p.can_write = true
) $$;

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

-- Klassen-Hausübungen
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

-- Persönliche Erledigungen für Klassen-HÜ
create table if not exists public.class_hu_completions (
  class_hu_id uuid not null references public.klassen_huebungen(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  done boolean not null default true,
  done_at timestamptz,
  primary key (class_hu_id, user_id)
);
alter table public.class_hu_completions enable row level security;
drop policy if exists "class_completion_own" on public.class_hu_completions;
create policy "class_completion_own" on public.class_hu_completions for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create index if not exists class_completion_user_idx on public.class_hu_completions(user_id, class_hu_id);

-- Dateien
create table if not exists public.hu_files (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  hausuebung_id uuid references public.hausuebungen(id) on delete cascade,
  class_hu_id uuid references public.klassen_huebungen(id) on delete cascade,
  name text not null,
  size bigint not null default 0,
  mime_type text not null default 'application/octet-stream',
  path text not null unique,
  created_at timestamptz not null default now(),
  constraint hu_files_one_parent check (
    (hausuebung_id is not null and class_hu_id is null)
    or (hausuebung_id is null and class_hu_id is not null)
  )
);
alter table public.hu_files enable row level security;
drop policy if exists "hu_files_select" on public.hu_files;
drop policy if exists "hu_files_insert" on public.hu_files;
drop policy if exists "hu_files_delete" on public.hu_files;
create policy "hu_files_select" on public.hu_files for select to authenticated using (
  (hausuebung_id is not null and owner_id = auth.uid())
  or class_hu_id is not null
);
create policy "hu_files_insert" on public.hu_files for insert to authenticated with check (
  owner_id = auth.uid()
  and (
    (hausuebung_id is not null and exists(
      select 1 from public.hausuebungen h where h.id = hausuebung_id and h.user_id = auth.uid()
    ))
    or
    (class_hu_id is not null and public.can_write_class_hu())
  )
);
create policy "hu_files_delete" on public.hu_files for delete to authenticated using (
  owner_id = auth.uid() or public.is_hu_admin()
);

-- Storage Bucket (10 GB)
insert into storage.buckets (id, name, public, file_size_limit)
values ('hu-files', 'hu-files', false, 10737418240)
on conflict (id) do update set file_size_limit = excluded.file_size_limit, public = false;

drop policy if exists "hu_storage_select" on storage.objects;
drop policy if exists "hu_storage_insert" on storage.objects;
drop policy if exists "hu_storage_update" on storage.objects;
drop policy if exists "hu_storage_delete" on storage.objects;
create policy "hu_storage_select" on storage.objects for select to authenticated using (
  bucket_id = 'hu-files' and (
    ((storage.foldername(name))[1] = 'personal' and (storage.foldername(name))[2] = (select auth.uid()::text))
    or ((storage.foldername(name))[1] = 'class')
  )
);
create policy "hu_storage_insert" on storage.objects for insert to authenticated with check (
  bucket_id = 'hu-files' and (
    ((storage.foldername(name))[1] = 'personal' and (storage.foldername(name))[2] = (select auth.uid()::text))
    or ((storage.foldername(name))[1] = 'class' and public.can_write_class_hu())
  )
);
create policy "hu_storage_update" on storage.objects for update to authenticated using (
  bucket_id = 'hu-files' and (
    ((storage.foldername(name))[1] = 'personal' and (storage.foldername(name))[2] = (select auth.uid()::text))
    or ((storage.foldername(name))[1] = 'class' and public.can_write_class_hu())
  )
);
create policy "hu_storage_delete" on storage.objects for delete to authenticated using (
  bucket_id = 'hu-files' and (owner = (select auth.uid()) or public.is_hu_admin())
);

-- Push
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique,
  subscription jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.push_subscriptions enable row level security;
drop policy if exists "push_own_select" on public.push_subscriptions;
drop policy if exists "push_own_insert" on public.push_subscriptions;
drop policy if exists "push_own_update" on public.push_subscriptions;
drop policy if exists "push_own_delete" on public.push_subscriptions;
create policy "push_own_select" on public.push_subscriptions for select to authenticated using (user_id = auth.uid());
create policy "push_own_insert" on public.push_subscriptions for insert to authenticated with check (user_id = auth.uid());
create policy "push_own_update" on public.push_subscriptions for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "push_own_delete" on public.push_subscriptions for delete to authenticated using (user_id = auth.uid());

-- Aktivitäts-Log
create table if not exists public.activity_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  user_name text not null default '',
  action text not null,
  detail text not null default '',
  created_at timestamptz not null default now()
);
alter table public.activity_logs enable row level security;
drop policy if exists "activity_select" on public.activity_logs;
drop policy if exists "activity_insert" on public.activity_logs;
create policy "activity_select" on public.activity_logs for select to authenticated using (true);
create policy "activity_insert" on public.activity_logs for insert to authenticated with check (user_id = auth.uid());
create index if not exists activity_logs_created_idx on public.activity_logs(created_at desc);

-- Admin: Schreibrecht per E-Mail
create or replace function public.set_class_hu_permission(p_email text, p_can_write boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid;
begin
  if not public.is_hu_admin() then raise exception 'not allowed'; end if;
  select id into v_uid from auth.users where lower(email) = lower(p_email);
  if v_uid is null then raise exception 'Benutzer % hat sich noch nie angemeldet', p_email; end if;
  insert into public.klassen_hu_permissions (user_id, user_email, can_write)
  values (v_uid, lower(p_email), p_can_write)
  on conflict (user_id) do update set can_write = excluded.can_write, user_email = excluded.user_email;
end;
$$;
grant execute on function public.set_class_hu_permission(text, boolean) to authenticated;

-- Indexes
create index if not exists hausuebungen_user_idx on public.hausuebungen(user_id, due);
create index if not exists hausuebungen_sort_idx on public.hausuebungen(user_id, sort_order);
create index if not exists class_hu_due_idx on public.klassen_huebungen(due);
create index if not exists hu_files_personal_idx on public.hu_files(hausuebung_id);
create index if not exists hu_files_class_idx on public.hu_files(class_hu_id);
create index if not exists push_user_idx on public.push_subscriptions(user_id);

-- Realtime
do $$ begin alter publication supabase_realtime add table public.hausuebungen; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.klassen_huebungen; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.klassen_hu_permissions; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.class_hu_completions; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.activity_logs; exception when duplicate_object then null; end $$;


-- Unterlagen / Schulübungen (SÜ)
-- Gleiche Schreibrechte wie Klassen-HÜ (can_write_class_hu / Admin)

create table if not exists public.unterlagen (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  subject text not null default '',
  lesson_date date,
  note text not null default '',
  created_by uuid not null references auth.users(id) on delete restrict,
  created_by_email text not null,
  created_by_name text not null,
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

alter table public.hu_files add column if not exists unterlage_id uuid references public.unterlagen(id) on delete cascade;
alter table public.hu_files drop constraint if exists hu_files_one_parent;
alter table public.hu_files add constraint hu_files_one_parent check (
  ((hausuebung_id is not null)::int + (class_hu_id is not null)::int + (unterlage_id is not null)::int) = 1
);

drop policy if exists "hu_files_select" on public.hu_files;
drop policy if exists "hu_files_insert" on public.hu_files;
create policy "hu_files_select" on public.hu_files for select to authenticated using (
  (hausuebung_id is not null and owner_id = auth.uid())
  or class_hu_id is not null
  or unterlage_id is not null
);
create policy "hu_files_insert" on public.hu_files for insert to authenticated with check (
  owner_id = auth.uid()
  and (
    (hausuebung_id is not null and exists(
      select 1 from public.hausuebungen h where h.id = hausuebung_id and h.user_id = auth.uid()
    ))
    or (class_hu_id is not null and public.can_write_class_hu())
    or (unterlage_id is not null and public.can_write_class_hu())
  )
);

do $$ begin
  alter publication supabase_realtime add table public.unterlagen;
exception when duplicate_object then null;
end $$;



-- ===== password_resets =====

-- Codes für Passwort-Reset (nur Service Role / Edge Functions)
create table if not exists public.password_resets (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  code text not null,
  expires_at timestamptz not null,
  used boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists password_resets_email_idx on public.password_resets(email);
create index if not exists password_resets_open_idx on public.password_resets(used, expires_at);

alter table public.password_resets enable row level security;
-- Keine Policies für authenticated: nur Service Role (Edge Function) greift zu



-- ===== solutions =====

-- Lösungen zu Klassen-HÜ: jeder darf hochladen, alle sehen von wem
create table if not exists public.hu_solutions (
  id uuid primary key default gen_random_uuid(),
  class_hu_id uuid not null references public.klassen_huebungen(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  owner_name text not null default '',
  owner_email text not null default '',
  name text not null,
  size bigint not null default 0,
  mime_type text not null default 'application/octet-stream',
  path text not null unique,
  created_at timestamptz not null default now()
);
create index if not exists hu_solutions_class_idx on public.hu_solutions(class_hu_id);
create index if not exists hu_solutions_owner_idx on public.hu_solutions(owner_id);

alter table public.hu_solutions enable row level security;
drop policy if exists "hu_solutions_select" on public.hu_solutions;
drop policy if exists "hu_solutions_insert" on public.hu_solutions;
drop policy if exists "hu_solutions_delete" on public.hu_solutions;
create policy "hu_solutions_select" on public.hu_solutions for select to authenticated using (true);
create policy "hu_solutions_insert" on public.hu_solutions for insert to authenticated
  with check (owner_id = auth.uid());
create policy "hu_solutions_delete" on public.hu_solutions for delete to authenticated
  using (owner_id = auth.uid() or public.is_hu_admin());

-- Storage: Lösungen unter solutions/
drop policy if exists "hu_storage_solutions_insert" on storage.objects;
create policy "hu_storage_solutions_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'hu-files' and (storage.foldername(name))[1] = 'solutions');

do $$ begin
  alter publication supabase_realtime add table public.hu_solutions;
exception when duplicate_object then null;
end $$;



-- ===== storage preview (final policies) =====

-- Vorschau/Download für alle Dateien im Bucket hu-files
-- (class, personal, unterlagen, solutions)

drop policy if exists "hu_storage_select" on storage.objects;
drop policy if exists "hu_storage_insert" on storage.objects;
drop policy if exists "hu_storage_update" on storage.objects;
drop policy if exists "hu_storage_delete" on storage.objects;
drop policy if exists "hu_storage_solutions_insert" on storage.objects;

-- Lesen: jeder eingeloggte User (Signed URL / Vorschau)
create policy "hu_storage_select" on storage.objects
for select to authenticated
using (bucket_id = 'hu-files');

-- Hochladen
create policy "hu_storage_insert" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'hu-files' and (
    ((storage.foldername(name))[1] = 'personal' and (storage.foldername(name))[2] = (select auth.uid()::text))
    or ((storage.foldername(name))[1] = 'class' and public.can_write_class_hu())
    or ((storage.foldername(name))[1] = 'unterlagen' and public.can_write_class_hu())
    or ((storage.foldername(name))[1] = 'solutions')
  )
);

create policy "hu_storage_update" on storage.objects
for update to authenticated
using (
  bucket_id = 'hu-files' and (
    ((storage.foldername(name))[1] = 'personal' and (storage.foldername(name))[2] = (select auth.uid()::text))
    or ((storage.foldername(name))[1] = 'class' and public.can_write_class_hu())
    or ((storage.foldername(name))[1] = 'unterlagen' and public.can_write_class_hu())
    or ((storage.foldername(name))[1] = 'solutions' and owner = (select auth.uid()))
  )
);

create policy "hu_storage_delete" on storage.objects
for delete to authenticated
using (
  bucket_id = 'hu-files'
  and (owner = (select auth.uid()) or public.is_hu_admin())
);
