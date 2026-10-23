
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
