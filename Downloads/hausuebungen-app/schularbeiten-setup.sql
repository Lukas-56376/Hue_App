-- Tests & Schularbeiten (RLS ueber is_hu_admin)
create table if not exists public.schularbeiten (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  subject text,
  kind text not null default 'test' check (kind in ('test', 'schularbeit')),
  exam_date date not null,
  stoff text,
  links jsonb not null default '[]'::jsonb,
  files jsonb not null default '[]'::jsonb,
  created_by uuid references auth.users (id) on delete set null,
  created_by_email text,
  created_by_name text,
  created_at timestamptz not null default now()
);

create index if not exists schularbeiten_exam_date_idx on public.schularbeiten (exam_date);

alter table public.schularbeiten enable row level security;

drop policy if exists "schularbeiten_select_auth" on public.schularbeiten;
create policy "schularbeiten_select_auth"
  on public.schularbeiten for select
  to authenticated
  using (true);

drop policy if exists "schularbeiten_insert_admin" on public.schularbeiten;
create policy "schularbeiten_insert_admin"
  on public.schularbeiten for insert
  to authenticated
  with check (public.is_hu_admin());

drop policy if exists "schularbeiten_update_admin" on public.schularbeiten;
create policy "schularbeiten_update_admin"
  on public.schularbeiten for update
  to authenticated
  using (public.is_hu_admin())
  with check (public.is_hu_admin());

drop policy if exists "schularbeiten_delete_admin" on public.schularbeiten;
create policy "schularbeiten_delete_admin"
  on public.schularbeiten for delete
  to authenticated
  using (public.is_hu_admin());

do $$
begin
  alter publication supabase_realtime add table public.schularbeiten;
exception when duplicate_object then null;
end $$;
