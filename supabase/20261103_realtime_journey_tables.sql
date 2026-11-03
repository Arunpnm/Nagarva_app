-- 3 Nov 2026 — live screens (pending UX list item 2).
--
-- Lead Details and the order journey now reload by themselves when the
-- records they show change (lib/backend/live_refresh.dart): the customer
-- submits the survey, signs the quote, the office confirms the order,
-- a payment lands. For that the database has to broadcast changes on
-- these tables. Only `notifications` was broadcast before.
--
-- Row Level Security still decides who hears what: a logged-in session
-- only receives its own company's rows. Nothing is exposed to the public.
-- Safe to re-run (skips tables already added).

do $$
declare
  t text;
begin
  foreach t in array array[
    'leads',
    'customer_surveys',
    'quotations',
    'orders',
    'document_signatures',
    'payment_entries',
    'pod_records'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

select tablename from pg_publication_tables
 where pubname = 'supabase_realtime' order by 1;
