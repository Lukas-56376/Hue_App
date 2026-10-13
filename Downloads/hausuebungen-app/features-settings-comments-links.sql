-- ============================================================
-- Settings, Kommentare, Links, Reminder-Stufen, Geräte-Meta
-- ============================================================

-- User-Einstellungen
create table if not exists public.user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  notify_enabled boolean not null default true,
  notify_class boolean not null default true,
  notify_personal boolean not null default true,
  remind_time time not null default '10:00',
  stage_2d boolean not null default false,
  stage_1d boolean not null default true,
  stage_0d boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.user_settings enable row level security;
drop policy if exists "user_settings_own" on public.user_settings;
create policy "user_settings_own" on public.user_settings
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Idempotente Reminder-Versand-Logik
create table if not exists public.reminder_sent (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  item_key text not null,
  stage text not null,
  sent_on date not null default (timezone('Europe/Vienna', now()))::date,
  created_at timestamptz not null default now(),
  unique (user_id, item_key, stage, sent_on)
);
create index if not exists reminder_sent_user_day on public.reminder_sent(user_id, sent_on);
alter table public.reminder_sent enable row level security;
drop policy if exists "reminder_sent_own" on public.reminder_sent;
create policy "reminder_sent_own" on public.reminder_sent
  for select to authenticated using (user_id = auth.uid());

-- Kommentare (Klassen-HÜ)
create table if not exists public.hu_comments (
  id uuid primary key default gen_random_uuid(),
  class_hu_id uuid not null references public.klassen_huebungen(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  user_name text not null default '',
  user_email text not null default '',
  body text not null,
  created_at timestamptz not null default now()
);
create index if not exists hu_comments_class_idx on public.hu_comments(class_hu_id, created_at);
alter table public.hu_comments enable row level security;
drop policy if exists "hu_comments_select" on public.hu_comments;
drop policy if exists "hu_comments_insert" on public.hu_comments;
drop policy if exists "hu_comments_delete" on public.hu_comments;
create policy "hu_comments_select" on public.hu_comments
  for select to authenticated using (true);
create policy "hu_comments_insert" on public.hu_comments
  for insert to authenticated with check (user_id = auth.uid());
create policy "hu_comments_delete" on public.hu_comments
  for delete to authenticated
  using (user_id = auth.uid() or public.is_hu_admin());

-- Link-Anhänge
create table if not exists public.hu_links (
  id uuid primary key default gen_random_uuid(),
  hausuebung_id uuid references public.hausuebungen(id) on delete cascade,
  class_hu_id uuid references public.klassen_huebungen(id) on delete cascade,
  unterlage_id uuid references public.unterlagen(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null default '',
  url text not null,
  created_at timestamptz not null default now(),
  constraint hu_links_one_parent check (
    (hausuebung_id is not null)::int +
    (class_hu_id is not null)::int +
    (unterlage_id is not null)::int = 1
  )
);
create index if not exists hu_links_personal on public.hu_links(hausuebung_id);
create index if not exists hu_links_class on public.hu_links(class_hu_id);
create index if not exists hu_links_su on public.hu_links(unterlage_id);
alter table public.hu_links enable row level security;
drop policy if exists "hu_links_select" on public.hu_links;
drop policy if exists "hu_links_insert" on public.hu_links;
drop policy if exists "hu_links_delete" on public.hu_links;
create policy "hu_links_select" on public.hu_links
  for select to authenticated using (
    (hausuebung_id is not null and owner_id = auth.uid())
    or class_hu_id is not null
    or unterlage_id is not null
  );
create policy "hu_links_insert" on public.hu_links
  for insert to authenticated with check (owner_id = auth.uid());
create policy "hu_links_delete" on public.hu_links
  for delete to authenticated
  using (owner_id = auth.uid() or public.is_hu_admin());

-- Geräte-Label an Push-Subscriptions (falls Spalte fehlt)
alter table public.push_subscriptions
  add column if not exists device_label text not null default '',
  add column if not exists user_agent text not null default '',
  add column if not exists last_seen timestamptz not null default now();
