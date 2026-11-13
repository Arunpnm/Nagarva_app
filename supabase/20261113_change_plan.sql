-- ============================================================
-- 20261113_change_plan.sql  (13 Nov 2026)
--
-- Change plan (Arun: "every upgrade or downgrade will apply at the end
-- of the month, not in between").
--
-- Razorpay cannot change the plan of a UPI Autopay, so the plan-billing
-- function makes a NEW Autopay for the new plan whose first charge is
-- the day the paid month ends, and tells the old one to stop that day.
-- For a while a company therefore has two live Autopays: the current
-- one, and one waiting to take over. This script lets the table hold
-- that, and nothing more:
--
-- 1. org_subscriptions.replaces_id  the Autopay this one takes over from
--    org_subscriptions.is_next      true while it is still waiting
-- 2. "one live Autopay per company" becomes "one current + one waiting".
-- 3. billing_set_status:
--    - when the old Autopay stops, the waiting one becomes the current;
--    - a waiting Autopay that was never approved ('created') no longer
--      keeps the company on its plan after the old one stops: the
--      company goes to grace on the day it was paid up to, as with Stop;
--    - a take-over Autopay that stops before it was ever paid, with the
--      old one already gone, also sends the company to grace.
--
-- Run once in the Supabase SQL editor. Safe to read first: it changes
-- no company and no payment. Then deploy the function:
--   npx supabase functions deploy plan-billing --project-ref hqqcapifefsaqvotqvlt
-- ============================================================

begin;

-- ---------- preflight -------------------------------------------------
do $pre$
begin
  if to_regclass('public.org_subscriptions') is null then
    raise exception 'org_subscriptions is missing. Stop and check.';
  end if;
  if to_regclass('public.org_subscriptions_one_live_per_org') is null then
    raise exception 'index org_subscriptions_one_live_per_org is missing: run 20261111_plan_autopay.sql first.';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'org_subscriptions'
                and column_name in ('replaces_id', 'is_next')) then
    raise exception 'replaces_id / is_next already exist: this script has been run.';
  end if;
  if to_regprocedure('public.billing_set_status(text,text,timestamptz)') is null then
    raise exception 'billing_set_status is missing: run 20261111_plan_autopay.sql first.';
  end if;
end $pre$;

-- ---------- 1. the two new columns ------------------------------------
alter table public.org_subscriptions
  add column replaces_id uuid references public.org_subscriptions(id),
  add column is_next     boolean not null default false;

-- ---------- 2. one current + one waiting ------------------------------
drop index public.org_subscriptions_one_live_per_org;
-- One current Autopay per company: a second one would charge twice.
create unique index org_subscriptions_one_live_per_org
  on public.org_subscriptions (org_id)
  where status in ('created', 'authenticated', 'active', 'pending', 'paused')
    and not is_next;
-- And at most one waiting to take over.
create unique index org_subscriptions_one_next_per_org
  on public.org_subscriptions (org_id)
  where status in ('created', 'authenticated', 'active', 'pending', 'paused')
    and is_next;

-- ---------- 3. Autopay status changes ---------------------------------
create or replace function public.billing_set_status(
  p_gateway_sub_id text,
  p_status         text,
  p_period_end     timestamptz
) returns text
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  s          org_subscriptions%rowtype;
  o          organizations%rowtype;
  v_end      timestamptz;
  v_old_end  timestamptz;
  v_paid     boolean;
  v_takeover boolean;
begin
  if p_status not in ('created', 'authenticated', 'active', 'pending',
                      'halted', 'paused', 'cancelled', 'completed', 'expired') then
    raise exception 'billing_set_status: unknown status %', p_status;
  end if;

  select * into s from org_subscriptions
   where gateway = 'razorpay' and gateway_sub_id = p_gateway_sub_id
   for update;
  if not found then
    return 'unknown_subscription';
  end if;

  update org_subscriptions
     set status             = p_status,
         current_period_end = greatest(current_period_end, p_period_end),
         cancelled_at       = case when p_status = 'cancelled'
                                   then coalesce(cancelled_at, now())
                                   else cancelled_at end,
         short_url          = case when p_status = 'created' then short_url end,
         last_synced_at     = now(),
         updated_at         = now()
   where id = s.id
  returning current_period_end into v_end;

  -- 13 Nov 2026: this Autopay is over for good, so the one waiting to
  -- take over from it (a plan change) is now the company's current one.
  -- Not on 'paused': a paused Autopay is still the current one.
  if p_status in ('halted', 'cancelled', 'completed', 'expired') then
    update org_subscriptions
       set is_next = false, updated_at = now()
     where replaces_id = s.id and is_next;
  end if;

  -- Only a stop changes the company, and only if no other Autopay that
  -- can still charge is live for it. A company a platform admin moved
  -- by hand is left alone.
  if p_status in ('halted', 'paused', 'cancelled', 'completed', 'expired') then
    select * into o from organizations where id = s.org_id for update;
    v_paid := exists (select 1 from platform_invoices i where i.subscription_id = s.id);
    -- A take-over Autopay (plan change) that stops before it was ever
    -- paid: the company was last paid for through the one it replaced.
    select r.current_period_end into v_old_end
      from org_subscriptions r
     where r.id = s.replaces_id
       and exists (select 1 from platform_invoices i where i.subscription_id = r.id);
    v_takeover := s.replaces_id is not null and not v_paid and v_old_end is not null;

    if o.plan_status = 'active'
       -- 13 Nov 2026: 'created' (approval never finished) no longer
       -- counts: it cannot charge, so it must not hold the plan.
       and not exists (select 1 from org_subscriptions x
                        where x.org_id = s.org_id and x.id <> s.id
                          and x.status in ('authenticated', 'active', 'pending'))
       and ((o.plan_id is not distinct from s.plan_id and v_paid) or v_takeover) then
      update organizations
         set plan_status   = 'grace',
             trial_ends_at = case when v_takeover
                                  then coalesce(v_old_end, now())
                                  else coalesce(v_end, now()) end
       where id = s.org_id;
      insert into billing_events (org_id, event_type, detail)
      values (s.org_id, 'plan_status_changed',
              jsonb_build_object('from', 'active', 'to', 'grace',
                                 'paid_until', case when v_takeover
                                                    then coalesce(v_old_end, now())
                                                    else coalesce(v_end, now()) end,
                                 'autopay', p_status,
                                 'plan_change_not_paid', v_takeover,
                                 'source', 'razorpay', 'subscription', p_gateway_sub_id));
      return 'company_to_grace';
    end if;
  end if;
  return 'updated';
end $$;

-- create or replace keeps grants, but restate them: this must never be
-- callable from the app.
revoke all on function public.billing_set_status(text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.billing_set_status(text, text, timestamptz) to service_role;

-- ---------- postflight ------------------------------------------------
do $post$
declare
  v_def text;
begin
  select string_agg(l, E'\n') into v_def
    from regexp_split_to_table(pg_get_functiondef(
           'public.billing_set_status(text,text,timestamptz)'::regprocedure), E'\n') l
   where l !~ '^\s*--';
  if v_def !~ '\yv_takeover\y' then
    raise exception 'postflight: billing_set_status was not replaced';
  end if;
  if has_function_privilege('authenticated',
       'public.billing_set_status(text,text,timestamptz)', 'execute')
     or has_function_privilege('anon',
       'public.billing_set_status(text,text,timestamptz)', 'execute') then
    raise exception 'postflight: billing_set_status is callable from the app';
  end if;
  if to_regclass('public.org_subscriptions_one_live_per_org') is null
     or to_regclass('public.org_subscriptions_one_next_per_org') is null then
    raise exception 'postflight: the two Autopay indexes are not both there';
  end if;
  -- Nothing existing was marked as waiting.
  if exists (select 1 from org_subscriptions where is_next or replaces_id is not null) then
    raise exception 'postflight: an existing Autopay was marked as a plan change';
  end if;
end $post$;

commit;
