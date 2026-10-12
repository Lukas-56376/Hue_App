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
