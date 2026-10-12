-- Zwei Admins: DaWeed + Nico
create or replace function public.is_hu_admin()
returns boolean language sql stable security definer set search_path = public
as $$
  select lower(coalesce(auth.jwt()->>'email','')) in (
    'daweed@lukio.site',
    'nico@lukio.site'
  )
$$;
