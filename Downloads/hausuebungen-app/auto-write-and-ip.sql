-- ============================================================
-- Standard: Schreibrecht für neue User
-- + IP-Logs / IP-Bans (Admin)
-- ============================================================

-- Default-Schreibrecht beim Anlegen eines Auth-Users
create or replace function public.grant_default_class_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.klassen_hu_permissions (user_id, user_email, can_write)
  values (new.id, lower(coalesce(new.email, '')), true)
  on conflict (user_id) do update
    set user_email = excluded.user_email
    -- can_write bei Konflikt NICHT überschreiben (Admin-Entzug bleibt)
    ;
  return new;
end;
$$;

drop trigger if exists on_auth_user_grant_write on auth.users;
create trigger on_auth_user_grant_write
  after insert on auth.users
  for each row execute function public.grant_default_class_write();

-- Bestehende User ohne Eintrag: Schreibrecht setzen
insert into public.klassen_hu_permissions (user_id, user_email, can_write)
select u.id, lower(u.email), true
from auth.users u
where u.email is not null
  and not exists (
    select 1 from public.klassen_hu_permissions p where p.user_id = u.id
  )
on conflict (user_id) do nothing;

-- IP-Logs
create table if not exists public.ip_logs (
  id uuid primary key default gen_random_uuid(),
  ip text not null,
  action text not null default 'login',
  user_id uuid references auth.users(id) on delete set null,
  user_email text,
  user_agent text,
  detail text,
  created_at timestamptz not null default now()
);
create index if not exists ip_logs_ip_idx on public.ip_logs(ip);
create index if not exists ip_logs_created_idx on public.ip_logs(created_at desc);

-- IP-Bans
create table if not exists public.ip_bans (
  id uuid primary key default gen_random_uuid(),
  ip text not null unique,
  reason text not null default '',
  active boolean not null default true,
  banned_by text,
  created_at timestamptz not null default now()
);
create index if not exists ip_bans_active_idx on public.ip_bans(ip) where active = true;

alter table public.ip_logs enable row level security;
alter table public.ip_bans enable row level security;

drop policy if exists "ip_logs_admin" on public.ip_logs;
drop policy if exists "ip_bans_admin_select" on public.ip_bans;
drop policy if exists "ip_bans_admin_all" on public.ip_bans;

-- Nur Admins lesen Logs/Bans über Client; Writes über Service Role (Edge)
create policy "ip_logs_admin" on public.ip_logs
  for select to authenticated using (public.is_hu_admin());

create policy "ip_bans_admin_select" on public.ip_bans
  for select to authenticated using (public.is_hu_admin());

create policy "ip_bans_admin_all" on public.ip_bans
  for all to authenticated
  using (public.is_hu_admin())
  with check (public.is_hu_admin());

-- Helper: IP gebannt?
create or replace function public.is_ip_banned(p_ip text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.ip_bans b
    where b.active = true
      and b.ip = nullif(trim(p_ip), '')
  );
$$;
