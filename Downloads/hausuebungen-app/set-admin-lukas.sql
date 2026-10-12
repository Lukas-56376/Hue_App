-- Admin auf lukas@lukio.site umstellen
create or replace function public.is_hu_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select lower(coalesce(auth.jwt()->>'email','')) = 'lukas@lukio.site' $$;

-- alten Admin-Account entfernen (Auth)
delete from auth.users where lower(email) = 'admin@lukio.site';
