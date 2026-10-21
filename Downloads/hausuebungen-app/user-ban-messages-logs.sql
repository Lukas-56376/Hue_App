-- User bans, Admin messages, Super-Admin logs
create table if not exists public.user_bans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  user_email text not null,
  reason text,
  banned_by text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists user_bans_email_idx on public.user_bans (lower(user_email));
create index if not exists user_bans_active_idx on public.user_bans (active) where active = true;

alter table public.user_bans enable row level security;
drop policy if exists "user_bans_select" on public.user_bans;
drop policy if exists "user_bans_admin_all" on public.user_bans;
create policy "user_bans_select" on public.user_bans for select to authenticated using (true);
create policy "user_bans_admin_all" on public.user_bans for all to authenticated
  using (public.is_hu_admin()) with check (public.is_hu_admin());

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
  );
create policy "admin_messages_update" on public.admin_messages for update to authenticated
  using (
    lower(to_email) = lower(coalesce(auth.jwt()->>'email',''))
    or lower(coalesce(auth.jwt()->>'email','')) = 'daweed@lukio.site'
  );

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

grant select, insert, update, delete on public.user_bans to authenticated;
grant select, insert, update on public.admin_messages to authenticated;
grant select, insert on public.super_admin_logs to authenticated;

-- Ensure any authenticated user can read active bans (needed for self-check)
drop policy if exists "user_bans_select" on public.user_bans;
create policy "user_bans_select" on public.user_bans for select to authenticated using (true);

-- Admin messages: allow recipient by email match more reliably
drop policy if exists "admin_messages_select" on public.admin_messages;
create policy "admin_messages_select" on public.admin_messages for select to authenticated
  using (
    lower(to_email) = lower(coalesce(auth.jwt()->>'email',''))
    or public.is_hu_admin()
  );
