
alter table public.ip_bans enable row level security;
drop policy if exists "ip_bans_select_active" on public.ip_bans;
create policy "ip_bans_select_active" on public.ip_bans
  for select to authenticated, anon
  using (active = true);

do $$
begin
  begin
    execute 'alter publication supabase_realtime add table public.ip_bans';
  exception when duplicate_object then null;
  when others then null;
  end;
end $$;
