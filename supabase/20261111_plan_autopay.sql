-- 20261111_plan_autopay.sql  (11 Nov 2026)
--
-- Arun, 11 Nov 2026: vendors pay Nagarva for their plan through Razorpay
-- UPI Autopay (Razorpay Subscriptions), GST charged ON TOP of the plan
-- price (Pro Rs 2,999 + 18% = Rs 3,538.82 a month).
--
-- WHAT THIS ADDS
--   platform_gateway_plans   our plan + price + GST -> Razorpay plan id.
--                            A price change makes a NEW row (and a new
--                            Razorpay plan), so existing subscribers keep
--                            the price they signed up at (Item 31 rule:
--                            grandfather until migrated on purpose).
--                            Test and live keys keep separate rows.
--   razorpay_webhook_events  one row per webhook delivery, keyed by
--                            Razorpay's event id, so a retry is not
--                            applied twice.
--   org_subscriptions        + gateway_mode, gateway_plan_ref, short_url,
--                            created_by, last_synced_at; status check;
--                            at most ONE live subscription per company.
--   platform_invoices        + gateway_mode; a payment id is recorded once.
--   billing_record_charge()  a successful monthly charge: invoice row,
--                            subscription period, company -> that plan,
--                            Paid ('active').
--   billing_set_status()     Autopay stopped (halted / cancelled /
--                            completed / expired): company -> 'grace',
--                            with trial_ends_at = the date it is paid up to.
--   org_effective_plan()     'grace' now follows the same rule as 'trial'
--                            once that date passes: a company with a
--                            fallback plan (every self-signup has Free)
--                            moves to it, data kept; one without becomes
--                            view-only after the plan's grace days. Before
--                            this, 'grace' never ended at all.
--
-- WHO CAN CALL THE TWO billing_* FUNCTIONS: the service role only (the
-- plan-billing and razorpay-webhook edge functions). Not the app, not anon.
--
-- NOT HERE, ON PURPOSE
--   * invoice numbers and CGST/SGST vs IGST on platform_invoices: they
--     depend on which company bills vendors (CA to confirm). Rows are
--     written with invoice_no and gst_mode left empty, amounts filled.
--   * changing plan while Autopay is running: cancel, then subscribe again.
--
-- Run the WHOLE file. One transaction; a failed check rolls it all back.

begin;

-- ---------- preflight -------------------------------------------------
do $pre$
begin
  if to_regclass('public.platform_gateway_plans') is not null then
    raise exception 'platform_gateway_plans already exists -- this file has been run.';
  end if;
  if to_regclass('public.org_subscriptions') is null
     or to_regclass('public.platform_invoices') is null
     or to_regclass('public.billing_events') is null then
    raise exception 'org_subscriptions, platform_invoices or billing_events is missing. Stop and check.';
  end if;
  -- The status check and the one-live-per-company index below must not
  -- trip over rows written before this file. Today the table is empty.
  if exists (select 1 from public.org_subscriptions) then
    raise exception 'org_subscriptions already has rows -- check them before adding the status rules.';
  end if;
  if exists (select 1 from public.platform_invoices where gateway_payment_id is not null
              group by gateway_payment_id having count(*) > 1) then
    raise exception 'platform_invoices has a payment id twice -- cannot add the once-only rule.';
  end if;
  -- org_effective_plan is replaced below from a known body; refuse if it
  -- has changed since this file was written (11 Nov 2026).
  if (select md5(prosrc) from pg_proc
       where oid = 'public.org_effective_plan(uuid)'::regprocedure)
     <> '20a12a65fda6b041f45e292aa07777e0' then
    raise exception 'org_effective_plan has changed since this file was written. Stop and check.';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    raise exception 'service_role is missing.';
  end if;
end $pre$;

-- ---------- tables ----------------------------------------------------
create table public.platform_gateway_plans (
  id              uuid primary key default gen_random_uuid(),
  plan_id         uuid not null references public.subscription_plans(id),
  billing_period  text not null check (billing_period in ('monthly', 'annual')),
  price_inr       numeric(12,2) not null check (price_inr > 0),
  gst_pct         numeric(5,2)  not null check (gst_pct >= 0 and gst_pct <= 28),
  amount_paise    bigint not null check (amount_paise >= 100),
  gateway         text not null default 'razorpay',
  gateway_mode    text not null check (gateway_mode in ('test', 'live')),
  gateway_plan_id text not null unique,
  created_at      timestamptz not null default now(),
  unique (plan_id, billing_period, price_inr, gst_pct, gateway, gateway_mode)
);
alter table public.platform_gateway_plans enable row level security;
revoke all on public.platform_gateway_plans from public, anon, authenticated;

create table public.razorpay_webhook_events (
  event_id     text primary key,
  event        text not null,
  received_at  timestamptz not null default now(),
  outcome      text
);
alter table public.razorpay_webhook_events enable row level security;
revoke all on public.razorpay_webhook_events from public, anon, authenticated;

alter table public.org_subscriptions
  add column gateway_mode     text check (gateway_mode in ('test', 'live')),
  add column gateway_plan_ref uuid references public.platform_gateway_plans(id),
  add column short_url        text,
  add column created_by       uuid,
  add column last_synced_at   timestamptz,
  add constraint org_subscriptions_status_check check (status in
    ('trialing', 'created', 'authenticated', 'active', 'pending',
     'halted', 'paused', 'cancelled', 'completed', 'expired'));

create unique index org_subscriptions_gateway_sub_uniq
  on public.org_subscriptions (gateway, gateway_sub_id)
  where gateway_sub_id is not null;
-- One live Autopay per company: a second one would charge twice.
create unique index org_subscriptions_one_live_per_org
  on public.org_subscriptions (org_id)
  where status in ('created', 'authenticated', 'active', 'pending', 'paused');

alter table public.platform_invoices
  add column gateway_mode text check (gateway_mode in ('test', 'live'));
create unique index platform_invoices_payment_uniq
  on public.platform_invoices (gateway_payment_id)
  where gateway_payment_id is not null;

-- ---------- a successful charge -------------------------------------
create or replace function public.billing_record_charge(
  p_gateway_sub_id text,
  p_payment_id     text,
  p_amount_paise   bigint,
  p_period_start   timestamptz,
  p_period_end     timestamptz,
  p_paid_at        timestamptz
) returns text
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  s        org_subscriptions%rowtype;
  gp       platform_gateway_plans%rowtype;
  o        organizations%rowtype;
  v_total  numeric(12,2);
  v_tax    numeric(12,2);
  v_new    integer;
begin
  if p_payment_id is null or p_amount_paise is null or p_amount_paise <= 0 then
    raise exception 'billing_record_charge: payment id and a positive amount are required';
  end if;

  select * into s from org_subscriptions
   where gateway = 'razorpay' and gateway_sub_id = p_gateway_sub_id
   for update;
  if not found then
    return 'unknown_subscription';
  end if;
  select * into gp from platform_gateway_plans where id = s.gateway_plan_ref;

  -- GST on top: the amount paid is price + GST, so the taxable part is
  -- worked back from what was actually paid, not from today's price.
  v_total := round(p_amount_paise / 100.0, 2);
  v_tax   := round(v_total / (1 + coalesce(gp.gst_pct, 18) / 100.0), 2);

  insert into platform_invoices
    (org_id, subscription_id, invoice_date, period_start, period_end,
     taxable_amount, gst_mode, gst_pct, gst_amount, total_amount,
     status, paid_at, gateway_payment_id, gateway_mode)
  values
    (s.org_id, s.id,
     (coalesce(p_paid_at, now()) at time zone 'Asia/Kolkata')::date,
     (p_period_start at time zone 'Asia/Kolkata')::date,
     (p_period_end   at time zone 'Asia/Kolkata')::date,
     v_tax, null, coalesce(gp.gst_pct, 18), v_total - v_tax, v_total,
     'paid', coalesce(p_paid_at, now()), p_payment_id, s.gateway_mode)
  on conflict (gateway_payment_id) where gateway_payment_id is not null
  do nothing;
  get diagnostics v_new = row_count;

  update org_subscriptions
     set status               = 'active',
         amount_inr           = v_total,
         current_period_start = coalesce(p_period_start, current_period_start),
         current_period_end   = greatest(current_period_end, p_period_end),
         last_synced_at       = now(),
         updated_at           = now()
   where id = s.id;

  select * into o from organizations where id = s.org_id for update;
  if o.plan_id is distinct from s.plan_id then
    insert into billing_events (org_id, event_type, detail)
    values (s.org_id, 'plan_changed',
            jsonb_build_object('from', o.plan_id, 'to', s.plan_id,
                               'source', 'razorpay', 'subscription', p_gateway_sub_id));
  end if;
  if o.plan_status is distinct from 'active' then
    insert into billing_events (org_id, event_type, detail)
    values (s.org_id, 'plan_status_changed',
            jsonb_build_object('from', o.plan_status, 'to', 'active',
                               'source', 'razorpay', 'subscription', p_gateway_sub_id));
  end if;
  update organizations
     set plan_id = s.plan_id, plan_status = 'active'
   where id = s.org_id
     and (plan_id is distinct from s.plan_id or plan_status is distinct from 'active');

  if v_new > 0 then
    insert into billing_events (org_id, event_type, detail)
    values (s.org_id, 'payment_received',
            jsonb_build_object('amount_inr', v_total, 'payment', p_payment_id,
                               'subscription', p_gateway_sub_id,
                               'mode', s.gateway_mode, 'source', 'razorpay'));
    return 'recorded';
  end if;
  return 'duplicate';
end $$;

-- ---------- Autopay status changes ----------------------------------
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
  s     org_subscriptions%rowtype;
  o     organizations%rowtype;
  v_end timestamptz;
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

  -- Only a stop changes the company, and only if no other Autopay is
  -- live for it and it is still on the plan this Autopay paid for. A
  -- company a platform admin moved by hand is left alone.
  if p_status in ('halted', 'paused', 'cancelled', 'completed', 'expired') then
    select * into o from organizations where id = s.org_id for update;
    if o.plan_status = 'active'
       and o.plan_id is not distinct from s.plan_id
       and not exists (select 1 from org_subscriptions x
                        where x.org_id = s.org_id and x.id <> s.id
                          and x.status in ('created', 'authenticated', 'active', 'pending'))
       and exists (select 1 from platform_invoices i where i.subscription_id = s.id) then
      update organizations
         set plan_status   = 'grace',
             trial_ends_at = coalesce(v_end, now())
       where id = s.org_id;
      insert into billing_events (org_id, event_type, detail)
      values (s.org_id, 'plan_status_changed',
              jsonb_build_object('from', 'active', 'to', 'grace',
                                 'paid_until', coalesce(v_end, now()),
                                 'autopay', p_status,
                                 'source', 'razorpay', 'subscription', p_gateway_sub_id));
      return 'company_to_grace';
    end if;
  end if;
  return 'updated';
end $$;

revoke all on function public.billing_record_charge(text, text, bigint, timestamptz, timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.billing_set_status(text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.billing_record_charge(text, text, bigint, timestamptz, timestamptz, timestamptz) to service_role;
grant execute on function public.billing_set_status(text, text, timestamptz) to service_role;

-- ---------- 'grace' ends the way 'trial' does ------------------------
create or replace function public.org_effective_plan(p_org_id uuid)
returns table(plan_code text, limits jsonb, features jsonb, is_locked boolean)
language sql
stable security definer
set search_path to 'public'
as $function$
  -- A trial (or, since 11 Nov 2026, a 'grace' period after Autopay
  -- stopped -- trial_ends_at then holds the date it was paid up to) that
  -- has ended and names a fallback plan reports the fallback, unlocked:
  -- "you move to the Free plan automatically. Your data stays." Without a
  -- fallback it locks (view-only) after the plan's grace days.
  with o as (
    select o.*,
           (o.plan_status in ('trial', 'grace')
              and o.trial_ends_at is not null
              and o.trial_ends_at < now()
              and o.trial_fallback_plan_id is not null) as fell_back
      from organizations o
     where o.id = p_org_id
  )
  select
    sp.code,
    coalesce(sp.limits, '{}'::jsonb),
    coalesce(sp.features, '{}'::jsonb),
    (not o.fell_back
       and o.plan_status in ('trial', 'grace')
       and o.trial_ends_at is not null
       and o.trial_ends_at + make_interval(days => coalesce(sp.grace_days, 0)) < now())
      or not coalesce(o.active, true)
  from o
  left join subscription_plans sp
    on sp.id = case when o.fell_back then o.trial_fallback_plan_id else o.plan_id end
$function$;

-- ---------- postflight ------------------------------------------------
do $post$
declare
  v_org   uuid;
  v_sub   uuid;
  v_gp    uuid;
  v_pro   uuid;
  v_r     text;
  v_cnt   int;
  e       record;
begin
  -- Grants: only service_role may run the two billing functions.
  if has_function_privilege('anon', 'public.billing_record_charge(text,text,bigint,timestamptz,timestamptz,timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.billing_record_charge(text,text,bigint,timestamptz,timestamptz,timestamptz)', 'execute')
     or has_function_privilege('anon', 'public.billing_set_status(text,text,timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.billing_set_status(text,text,timestamptz)', 'execute') then
    raise exception 'POSTFLIGHT: the app or anon can run a billing function.';
  end if;
  if not has_function_privilege('service_role', 'public.billing_record_charge(text,text,bigint,timestamptz,timestamptz,timestamptz)', 'execute') then
    raise exception 'POSTFLIGHT: service_role cannot run billing_record_charge.';
  end if;
  if has_table_privilege('authenticated', 'public.platform_gateway_plans', 'select')
     or has_table_privilege('anon', 'public.razorpay_webhook_events', 'select') then
    raise exception 'POSTFLIGHT: a gateway table is readable by the app.';
  end if;

  -- Behaviour, on a real company, inside a savepoint that is rolled back.
  select id into v_org from organizations
   where plan_status = 'trial' and active
     and trial_fallback_plan_id is not null
   order by created_at limit 1;
  select id into v_pro from subscription_plans where code = 'pro';
  if v_org is null or v_pro is null then
    raise exception 'POSTFLIGHT: no trial company with a fallback plan (or no Pro plan) to test on.';
  end if;

  begin
    insert into platform_gateway_plans
      (plan_id, billing_period, price_inr, gst_pct, amount_paise, gateway_mode, gateway_plan_id)
    values (v_pro, 'monthly', 2999, 18, 353882, 'test', 'plan_PROBE')
    returning id into v_gp;
    insert into org_subscriptions
      (org_id, plan_id, status, billing_period, gateway, gateway_sub_id, gateway_mode, gateway_plan_ref)
    values (v_org, v_pro, 'created', 'monthly', 'razorpay', 'sub_PROBE', 'test', v_gp)
    returning id into v_sub;

    -- second live Autopay for the same company is refused
    begin
      insert into org_subscriptions (org_id, plan_id, status, gateway, gateway_sub_id)
      values (v_org, v_pro, 'created', 'razorpay', 'sub_PROBE2');
      raise exception 'POSTFLIGHT: a second live Autopay was allowed.';
    exception when unique_violation then null;
    end;

    v_r := billing_record_charge('sub_PROBE', 'pay_PROBE', 353882,
                                 now(), now() + interval '1 month', now());
    if v_r <> 'recorded' then raise exception 'POSTFLIGHT: first charge gave %', v_r; end if;
    v_r := billing_record_charge('sub_PROBE', 'pay_PROBE', 353882,
                                 now(), now() + interval '1 month', now());
    if v_r <> 'duplicate' then raise exception 'POSTFLIGHT: repeated charge gave %', v_r; end if;
    select count(*) into v_cnt from platform_invoices where gateway_payment_id = 'pay_PROBE';
    if v_cnt <> 1 then raise exception 'POSTFLIGHT: % invoice rows for one payment', v_cnt; end if;
    if (select taxable_amount from platform_invoices where gateway_payment_id = 'pay_PROBE') <> 2999
       or (select gst_amount from platform_invoices where gateway_payment_id = 'pay_PROBE') <> 539.82 then
      raise exception 'POSTFLIGHT: GST split of 3538.82 is not 2999 + 539.82';
    end if;
    select * into e from org_effective_plan(v_org);
    if e.plan_code <> 'pro' or e.is_locked
       or (select plan_status from organizations where id = v_org) <> 'active' then
      raise exception 'POSTFLIGHT: after a charge the company is not Pro, Paid and open.';
    end if;

    v_r := billing_set_status('sub_PROBE', 'halted', now() - interval '40 days');
    if v_r <> 'company_to_grace' then raise exception 'POSTFLIGHT: halt gave %', v_r; end if;
    -- paid up to a month ahead: still Pro and open
    select * into e from org_effective_plan(v_org);
    if e.plan_code <> 'pro' or e.is_locked then
      raise exception 'POSTFLIGHT: a halted Autopay that is paid ahead lost Pro early.';
    end if;
    -- once the paid-up date is past: falls back to Free, open, data kept
    update organizations set trial_ends_at = now() - interval '1 day' where id = v_org;
    select * into e from org_effective_plan(v_org);
    if e.plan_code <> 'free' or e.is_locked then
      raise exception 'POSTFLIGHT: lapsed company with a fallback did not move to Free (got %, locked %).',
        e.plan_code, e.is_locked;
    end if;
    -- without a fallback: view-only after the grace days
    update organizations set trial_fallback_plan_id = null,
                             trial_ends_at = now() - interval '60 days' where id = v_org;
    select * into e from org_effective_plan(v_org);
    if not e.is_locked then
      raise exception 'POSTFLIGHT: lapsed company without a fallback is not view-only.';
    end if;
    update organizations set trial_ends_at = now() - interval '1 day' where id = v_org;
    select * into e from org_effective_plan(v_org);
    if e.is_locked then
      raise exception 'POSTFLIGHT: lapsed company locked before its grace days ran out.';
    end if;

    raise exception 'PROBE-ROLLBACK';
  exception when others then
    if sqlerrm <> 'PROBE-ROLLBACK' then raise; end if;
  end;

  -- the probe left nothing behind
  if exists (select 1 from org_subscriptions where gateway_sub_id like 'sub_PROBE%')
     or exists (select 1 from platform_invoices where gateway_payment_id = 'pay_PROBE')
     or exists (select 1 from platform_gateway_plans where gateway_plan_id = 'plan_PROBE') then
    raise exception 'POSTFLIGHT: probe rows were left behind.';
  end if;

  -- a trial company is still read exactly as before
  select * into e from org_effective_plan(v_org);
  if e.plan_code is null then
    raise exception 'POSTFLIGHT: org_effective_plan returns nothing for a trial company.';
  end if;
end $post$;

commit;
