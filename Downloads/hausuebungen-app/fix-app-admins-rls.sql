-- Fix infinite recursion on app_admins + broadcast role policies
-- is_hu_admin bleibt SECURITY DEFINER; Policies auf app_admins/app_roles nutzen NUR feste E-Mails (kein is_hu_admin → keine Rekursion)

create or replace function public.is_hu_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    lower(coalesce(auth.jwt()->>'email','')) in (
      'daweed@lukio.site',
      'nico@lukio.site'
    )
    or exists (
      select 1 from public.app_admins a
      where lower(a.email) = lower(coalesce(auth.jwt()->>'email',''))
    );
$$;

-- app_admins: Select für alle, Write nur feste Super/Admins (kein is_hu_admin)
drop policy if exists "app_admins_select" on public.app_admins;
drop policy if exists "app_admins_admin" on public.app_admins;
drop policy if exists "app_admins_write" on public.app_admins;
create policy "app_admins_select" on public.app_admins
  for select to authenticated using (true);
create policy "app_admins_write" on public.app_admins
  for all to authenticated
  using (lower(coalesce(auth.jwt()->>'email','')) in ('daweed@lukio.site','nico@lukio.site'))
  with check (lower(coalesce(auth.jwt()->>'email','')) in ('daweed@lukio.site','nico@lukio.site'));

-- app_roles
create table if not exists public.app_roles (
  email text not null,
  role text not null check (role in ('broadcast')),
  created_at timestamptz not null default now(),
  primary key (email, role)
);
alter table public.app_roles enable row level security;
drop policy if exists "app_roles_select" on public.app_roles;
drop policy if exists "app_roles_admin" on public.app_roles;
drop policy if exists "app_roles_write" on public.app_roles;
create policy "app_roles_select" on public.app_roles
  for select to authenticated using (true);
create policy "app_roles_write" on public.app_roles
  for all to authenticated
  using (lower(coalesce(auth.jwt()->>'email','')) in ('daweed@lukio.site','nico@lukio.site'))
  with check (lower(coalesce(auth.jwt()->>'email','')) in ('daweed@lukio.site','nico@lukio.site'));

create or replace function public.can_broadcast()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_hu_admin() or exists (
    select 1 from public.app_roles r
    where lower(r.email) = lower(coalesce(auth.jwt()->>'email',''))
      and r.role = 'broadcast'
  );
$$;

drop policy if exists "broadcasts_admin" on public.app_broadcasts;
drop policy if exists "broadcasts_write" on public.app_broadcasts;
drop policy if exists "broadcasts_select" on public.app_broadcasts;
create policy "broadcasts_select" on public.app_broadcasts
  for select to authenticated using (true);
create policy "broadcasts_write" on public.app_broadcasts
  for insert to authenticated with check (public.can_broadcast());
create policy "broadcasts_delete" on public.app_broadcasts
  for delete to authenticated using (public.is_hu_admin() or created_by = auth.uid());

grant select, insert, update, delete on public.app_roles to authenticated;
grant select, insert, update, delete on public.app_admins to authenticated;
