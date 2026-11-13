-- ============================================================
-- 20261113_billing_mode_feature.sql  (13 Nov 2026)
--
-- Billing only mode (Settings > Modules) is part of the Growth plan
-- (Arun, 13 Nov 2026: "add this in growth plan"). Growth, and the plans
-- above it (Pro, and Trial which is Pro for 30 days), get the plan
-- feature `billing_mode`; Free and Basic have it written as false, so
-- Super Admin shows the real position on every plan.
--
-- It changes only the features of the five plans. No company, payment
-- or price is touched. Any plan can be switched later in
-- Super Admin > Plans > edit > "Billing only mode".
--
-- Run once in the Supabase SQL editor.
-- ============================================================

begin;

do $pre$
begin
  if (select count(*) from public.subscription_plans
       where code in ('free', 'basic', 'growth', 'pro', 'trial')) <> 5 then
    raise exception 'Expected the five plans free, basic, growth, pro, trial. Stop and check.';
  end if;
  if exists (select 1 from public.subscription_plans
              where features is not null and jsonb_typeof(features) <> 'object') then
    raise exception 'A plan has features that is not a JSON object -- fix that row first.';
  end if;
end $pre$;

update public.subscription_plans
   set features = coalesce(features, '{}'::jsonb)
                  || jsonb_build_object('billing_mode', code in ('growth', 'pro', 'trial'))
 where code in ('free', 'basic', 'growth', 'pro', 'trial');

do $post$
begin
  if exists (select 1 from public.subscription_plans
              where code in ('growth', 'pro', 'trial')
                and (features ->> 'billing_mode') is distinct from 'true')
     or exists (select 1 from public.subscription_plans
              where code in ('free', 'basic')
                and (features ->> 'billing_mode') is distinct from 'false') then
    raise exception 'postflight: billing_mode is not set as expected';
  end if;
end $post$;

commit;
