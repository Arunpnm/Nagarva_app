-- 20261110_ai_survey_pro_only.sql  (10 Nov 2026)  -- AI photo survey: Pro + Trial, monthly allowance
--
-- Two decisions by Arun, 10 Nov 2026:
--
-- 1. AI photo survey is for PRO vendors only -- "this is for pro user
--    only, not for all vendors".
-- 2. TRIAL IS PRO FOR 30 DAYS -- "trial version is nothing but a pro
--    version, which we offer for a certain days". Until today the Trial
--    row was 5 users / 50 orders / 50 WhatsApp, which matched neither Pro
--    nor what the signup page promises (it prints the PRO plan's own
--    numbers as the trial offer).
--
-- So after this file:
--
--   plan     ai_survey   AI checks/month   users   orders/month   WhatsApp/month
--   trial    ON          100               25      unlimited      500
--   pro      ON          1000              (unchanged)
--   free     off         0                 (unchanged)
--   basic    off         0                 (unchanged)
--   growth   off         0                 (unchanged)
--
-- Trial takes Pro's users and orders (they cost nothing). The two things
-- that cost money per use are CAPPED on Trial rather than unlimited:
-- WhatsApp at 500 and AI photo checks at 100. A free signup can never run
-- up a bill.
--
-- The survey-ai Edge Function reads both, for every request, customer
-- link and staff alike:
--   org_has_feature(org, 'ai_survey')            -- missing = false = off
--   org_limit(org, 'max_ai_survey_per_month')    -- missing = -1 = no limit
-- A trial that has ended falls back to its fallback plan (Free), so the
-- photo survey switches off by itself with the trial.
--
-- All of these are editable afterwards in Super Admin > Plans.
--
-- Existing trial companies get the new limits at once (limits are read
-- live from the plan row). Nobody loses anything: every number goes up.
--
-- Run the WHOLE file. One transaction; a failed check rolls it all back.
-- Safe to run twice (it sets values, it does not add rows).

begin;

-- ---------- preflight -------------------------------------------------
do $$
begin
  if to_regclass('public.subscription_plans') is null then
    raise exception 'public.subscription_plans is missing -- wrong database?';
  end if;
  if to_regprocedure('public.org_has_feature(uuid,text)') is null
     or to_regprocedure('public.org_limit(uuid,text)') is null then
    raise exception 'org_has_feature / org_limit are missing -- the plan helpers (Item 32) must exist first.';
  end if;
  if (select count(*) from public.subscription_plans where code = 'pro') <> 1 then
    raise exception 'Expected exactly one plan with code ''pro''. Check the plan codes first.';
  end if;
  if (select count(*) from public.subscription_plans where code = 'trial') <> 1 then
    raise exception 'Expected exactly one plan with code ''trial''. Check the plan codes first.';
  end if;
  if exists (select 1 from public.subscription_plans
              where (features is not null and jsonb_typeof(features) <> 'object')
                 or (limits   is not null and jsonb_typeof(limits)   <> 'object')) then
    raise exception 'A plan has features or limits that is not a JSON object -- fix that row first.';
  end if;
  -- Trial copies Pro's users and orders; refuse if Pro does not state them.
  if exists (select 1 from public.subscription_plans
              where code = 'pro'
                and (not (limits ? 'max_users') or not (limits ? 'max_orders_per_month'))) then
    raise exception 'The Pro plan does not state max_users / max_orders_per_month -- nothing to copy to Trial.';
  end if;
end $$;

-- ---------- the change ------------------------------------------------
-- Every plan: the feature switch and the monthly allowance, written out
-- (not left missing) so Super Admin shows the real position on each plan.
update public.subscription_plans
   set features = coalesce(features, '{}'::jsonb)
                  || jsonb_build_object('ai_survey', code in ('pro', 'trial')),
       limits   = coalesce(limits, '{}'::jsonb)
                  || jsonb_build_object(
                       'max_ai_survey_per_month',
                       case code when 'pro' then 1000 when 'trial' then 100 else 0 end);

-- Trial = Pro for 30 days: Pro's own users and orders, WhatsApp capped.
update public.subscription_plans t
   set limits = t.limits
                || jsonb_build_object(
                     'max_users',            p.limits -> 'max_users',
                     'max_orders_per_month', p.limits -> 'max_orders_per_month',
                     'max_whatsapp_per_month', 500),
       features = t.features
                  || (p.features - 'ai_survey')   -- every Pro feature, as Pro has it
  from public.subscription_plans p
 where t.code = 'trial' and p.code = 'pro';

-- ---------- postflight ------------------------------------------------
do $$
declare
  v_all integer;
  v_bad integer;
  t record;
  p record;
begin
  select count(*) into v_all from public.subscription_plans;

  select count(*) into v_bad from public.subscription_plans
   where not (features ? 'ai_survey') or not (limits ? 'max_ai_survey_per_month');
  if v_bad <> 0 then
    raise exception '% of % plans are missing ai_survey or max_ai_survey_per_month', v_bad, v_all;
  end if;

  if exists (select 1 from public.subscription_plans
              where (features ->> 'ai_survey')::boolean is distinct from (code in ('pro', 'trial'))) then
    raise exception 'ai_survey must be on for pro and trial and off for every other plan';
  end if;

  select * into p from public.subscription_plans where code = 'pro';
  select * into t from public.subscription_plans where code = 'trial';

  if (p.limits ->> 'max_ai_survey_per_month')::int <> 1000
     or (t.limits ->> 'max_ai_survey_per_month')::int <> 100 then
    raise exception 'AI check allowance is wrong: pro %, trial %',
      p.limits ->> 'max_ai_survey_per_month', t.limits ->> 'max_ai_survey_per_month';
  end if;
  if exists (select 1 from public.subscription_plans
              where code not in ('pro', 'trial')
                and (limits ->> 'max_ai_survey_per_month')::int <> 0) then
    raise exception 'A plan without the feature has an AI check allowance';
  end if;

  if (t.limits -> 'max_users') is distinct from (p.limits -> 'max_users')
     or (t.limits -> 'max_orders_per_month') is distinct from (p.limits -> 'max_orders_per_month') then
    raise exception 'Trial users/orders do not match Pro';
  end if;
  if (t.limits ->> 'max_whatsapp_per_month')::int <> 500 then
    raise exception 'Trial WhatsApp cap should be 500, is %', t.limits ->> 'max_whatsapp_per_month';
  end if;
  -- Every feature Pro has switched on, Trial has switched on.
  if exists (select 1 from jsonb_each(p.features) f
              where f.value = 'true'::jsonb
                and (t.features -> f.key) is distinct from 'true'::jsonb) then
    raise exception 'Trial is missing a feature that Pro has';
  end if;

  -- Behaviour, not just stored values: ask what the function asks.
  -- (a) no company on Free/Basic/Growth reads as having the feature;
  if exists (select 1 from public.organizations o
              where public.org_has_feature(o.id, 'ai_survey')
                and (select plan_code from public.org_effective_plan(o.id)) not in ('pro', 'trial')) then
    raise exception 'A company that is not on Pro or Trial reads as having ai_survey';
  end if;
  -- (b) every company whose effective plan is Pro or Trial reads as having it.
  if exists (select 1 from public.organizations o
              where (select plan_code from public.org_effective_plan(o.id)) in ('pro', 'trial')
                and not public.org_has_feature(o.id, 'ai_survey')) then
    raise exception 'A company on Pro or Trial reads as NOT having ai_survey';
  end if;
  -- (c) and their monthly allowance is the plan's, not "no limit".
  if exists (select 1 from public.organizations o
              where (select plan_code from public.org_effective_plan(o.id)) in ('pro', 'trial')
                and public.org_limit(o.id, 'max_ai_survey_per_month') not in (100, 1000)) then
    raise exception 'A company on Pro or Trial has an unexpected AI check allowance';
  end if;
end $$;

commit;
