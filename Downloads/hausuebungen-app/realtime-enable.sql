
do $$
declare t text;
begin
  foreach t in array array[
    'hausuebungen','klassen_huebungen','class_hu_completions','unterlagen',
    'klassen_hu_permissions','hu_files','hu_solutions','hu_comments','hu_links',
    'app_settings','app_broadcasts','app_admins','activity_logs','ip_bans','content_reports'
  ]
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    when undefined_table then null;
    when others then null;
    end;
  end loop;
end $$;
