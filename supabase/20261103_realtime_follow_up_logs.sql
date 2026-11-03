-- 3 Nov 2026 — follow-up calls show live on other phones.
--
-- The quote stage now keeps a follow-up log (every call with its notes)
-- until the customer confirms or says no. Broadcasting follow_up_logs lets
-- a call logged by one staff member appear on another's screen at once.
-- Row Level Security still limits each session to its own company.
-- Safe to re-run.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'follow_up_logs'
  ) then
    alter publication supabase_realtime add table public.follow_up_logs;
  end if;
end $$;

select tablename from pg_publication_tables
 where pubname = 'supabase_realtime' order by 1;
