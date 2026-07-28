-- ============================================================================
-- 20260728_lead_status_canonical.sql — live-test fix brief #2, item 5
--
-- Canonicalises `leads.status` to the pipeline the app now uses:
--
--     new -> follow_up -> survey_done -> quoted -> confirmed   (+ lost)
--
-- WHY THIS IS NEEDED (a real bug, not just tidying): the app had two
-- different spellings for the same state and they never met.
--   * leads_page_widget.dart's "Won" tab queried  status = 'converted'
--   * lead_detail_page_widget.dart's Convert to Order wrote 'confirmed'
--   * PLReportPage's lead-source conversion rate also reads 'confirmed'
-- So converting a lead wrote 'confirmed' and the Won tab, looking for
-- 'converted', stayed empty forever. Likewise the leads list used
-- 'contacted' where the pipeline calls the stage 'follow_up'.
--
-- Idempotent — re-running is a no-op once the values are canonical.
--
-- NOTE ON SAFETY: this only rewrites values this app itself is known to
-- have written. Before running, it is worth eyeballing what is actually in
-- there (the app tolerates un-backfilled rows either way — see
-- canonicalLeadStatus() in lib/backend/lead_status.dart, which normalises
-- legacy spellings on read, so this migration is a cleanup rather than a
-- prerequisite):
--
--     select status, count(*) from public.leads group by status order by 2 desc;
--
-- If that turns up a spelling not handled below, add it to the mapping
-- here AND to _kLegacyAliases in lib/backend/lead_status.dart.
--
-- No RLS changes: `leads` already carries org_id and whatever policy it
-- has today is unaffected by a value rewrite.
-- ============================================================================

begin;

-- 'contacted' was the leads list's name for what the pipeline calls the
-- follow-up stage.
update public.leads
   set status = 'follow_up'
 where lower(trim(status)) in ('contacted', 'followup', 'follow up');

-- 'converted' / 'won' / 'booked' all meant "became an order" = confirmed.
update public.leads
   set status = 'confirmed'
 where lower(trim(status)) in ('converted', 'won', 'booked');

-- Assorted spellings of the two middle stages.
update public.leads
   set status = 'survey_done'
 where lower(trim(status)) in ('survey', 'surveydone');

update public.leads
   set status = 'quoted'
 where lower(trim(status)) in ('quote_sent', 'quotation_sent');

-- Anything null/blank starts at the top of the pipeline.
update public.leads
   set status = 'new'
 where status is null or trim(status) = '';

-- Normalise case/whitespace on already-correct values.
update public.leads
   set status = lower(trim(status))
 where status <> lower(trim(status));

commit;

-- ---------------------------------------------------------------------------
-- OPTIONAL — only run this once the SELECT below returns zero rows.
-- A CHECK constraint stops a new stray spelling from being written again.
-- Deliberately left commented out rather than applied blind: if any row
-- still holds an unmapped value the ALTER fails, and there is no reason to
-- risk that on a live table without looking first.
--
--   select status, count(*) from public.leads
--    where status not in ('new','follow_up','survey_done','quoted','confirmed','lost')
--    group by status;
--
-- alter table public.leads drop constraint if exists leads_status_check;
-- alter table public.leads add constraint leads_status_check
--   check (status in ('new','follow_up','survey_done','quoted','confirmed','lost'));
-- ---------------------------------------------------------------------------

-- Verify after running:
--   select status, count(*) from public.leads group by status order by 2 desc;
-- Expect only: new / follow_up / survey_done / quoted / confirmed / lost
