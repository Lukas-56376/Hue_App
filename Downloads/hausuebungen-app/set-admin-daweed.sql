-- Admin auf daweed@lukio.site (Login: DaWeed)
create or replace function public.is_hu_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select lower(coalesce(auth.jwt()->>'email','')) = 'daweed@lukio.site' $$;
