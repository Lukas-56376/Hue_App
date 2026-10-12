-- Admin = DaWeed
create or replace function public.is_hu_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select lower(coalesce(auth.jwt()->>'email','')) = 'daweed@lukio.site' $$;

-- Storage: Unterlagen-Ordner erlauben
drop policy if exists "hu_storage_select" on storage.objects;
drop policy if exists "hu_storage_insert" on storage.objects;
drop policy if exists "hu_storage_update" on storage.objects;
drop policy if exists "hu_storage_delete" on storage.objects;

create policy "hu_storage_select" on storage.objects for select to authenticated using (
  bucket_id = 'hu-files' and (
    ((storage.foldername(name))[1] = 'personal' and (storage.foldername(name))[2] = (select auth.uid()::text))
    or ((storage.foldername(name))[1] = 'class')
    or ((storage.foldername(name))[1] = 'unterlagen')
  )
);
create policy "hu_storage_insert" on storage.objects for insert to authenticated with check (
  bucket_id = 'hu-files' and (
    ((storage.foldername(name))[1] = 'personal' and (storage.foldername(name))[2] = (select auth.uid()::text))
    or ((storage.foldername(name))[1] in ('class','unterlagen') and public.can_write_class_hu())
  )
);
create policy "hu_storage_update" on storage.objects for update to authenticated using (
  bucket_id = 'hu-files' and (
    ((storage.foldername(name))[1] = 'personal' and (storage.foldername(name))[2] = (select auth.uid()::text))
    or ((storage.foldername(name))[1] in ('class','unterlagen') and public.can_write_class_hu())
  )
);
create policy "hu_storage_delete" on storage.objects for delete to authenticated using (
  bucket_id = 'hu-files' and (owner = (select auth.uid()) or public.is_hu_admin())
);
