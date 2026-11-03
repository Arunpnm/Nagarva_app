-- 3 Nov 2026 — link existing quotes to their lead's survey.
--
-- Quotes opened from the lead (not from its survey) were saved with
-- survey_id NULL. The app now links the lead's latest SUBMITTED survey
-- when it creates a quote; this fills in the ones already saved.
--
-- Only touches quotes whose survey_id is NULL and whose lead has a
-- submitted survey. Never overwrites an existing link. Safe to re-run.
-- On 3 Nov this matched 1 of 11 quotes (4 more have a survey link that
-- the customer never filled in, so there is nothing to link).

begin;

with latest as (
  select distinct on (s.lead_id)
         s.lead_id, s.id as survey_id
    from public.customer_surveys s
   where s.lead_id is not null
     and s.submitted_at is not null
   order by s.lead_id, s.submitted_at desc
)
update public.quotations q
   set survey_id = l.survey_id
  from latest l
 where q.survey_id is null
   and q.lead_id = l.lead_id;

-- Check: how many quotes now have a survey link.
select count(*) as quotes, count(survey_id) as linked_to_survey
  from public.quotations;

commit;
