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
