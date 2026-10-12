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
