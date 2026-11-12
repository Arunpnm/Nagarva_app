-- ============================================================
-- 20261112_trial_autopay.sql  (12 Nov 2026)
--
-- Autopay turned on DURING a trial (Arun: "after trial end it auto move
-- to pro"). plan-billing now creates the Razorpay subscription with
-- start_at = trial end, so the vendor approves UPI Autopay today, Razorpay
-- takes a Rs 5 check and refunds it, and the first real charge is on the
-- day the trial ends.
--
-- Two gaps that start_at opens, closed here:
--
-- 1. org_effective_plan: the trial ends at a moment; Razorpay's charge
--    lands some time that day (UPI Autopay sends a pre-debit notice and
--    the bank may take hours). Without a bridge the company drops to the
--    Free plan in between. Now: while Autopay is approved and waiting for
--    its first charge (status authenticated / pending, or active), the
--    trial plan continues for up to 3 days after the trial end. After
--    that the normal fallback applies, so a mandate that never charges
--    cannot keep Pro forever.
--
-- 2. billing_record_charge: a payment smaller than half the plan amount
--    is not a plan payment (the Rs 5 check, or anything else odd). It is
--    refused with 'not_a_plan_charge' instead of turning the company into
--    a paid Pro customer with a Rs 5 invoice.
--
-- Run in the Supabase SQL editor as one script. Raises and rolls back on
-- any failed check.
-- ============================================================

begin;

-- ---------- preflight ------------------------------------------------
do $pre$
begin
  if to_regprocedure('public.org_effective_plan(uuid)') is null then
    raise exception 'org_effective_plan(uuid) is missing. Run 20261111_plan_autopay.sql first.';
  end if;
  if to_regprocedure('public.billing_record_charge(text,text,bigint,timestamptz,timestamptz,timestamptz)') is null then
    raise exception 'billing_record_charge is missing. Run 20261111_plan_autopay.sql first.';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'platform_gateway_plans'
                    and column_name = 'amount_paise') then
    raise exception 'platform_gateway_plans.amount_paise is missing. Run 20261111_plan_autopay.sql first.';
  end if;
end $pre$;

-- ---------- 1. trial continues while the first charge is on its way ---
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
  -- 12 Nov 2026: Autopay approved during the trial bridges up to 3 days
  -- after the trial end while the first charge arrives.
  with o as (
    select o.*,
           (o.plan_status = 'trial'
              and o.trial_ends_at is not null
              and o.trial_ends_at + interval '3 days' > now()
              and exists (select 1 from org_subscriptions s
                           where s.org_id = o.id
                             and s.status in ('authenticated', 'pending', 'active'))
           ) as awaiting_first_charge
      from organizations o
     where o.id = p_org_id
  ),
  f as (
    select o.*,
           (o.plan_status in ('trial', 'grace')
              and o.trial_ends_at is not null
              and o.trial_ends_at < now()
              and o.trial_fallback_plan_id is not null
              and not o.awaiting_first_charge) as fell_back
      from o
  )
  select
    sp.code,
    coalesce(sp.limits, '{}'::jsonb),
    coalesce(sp.features, '{}'::jsonb),
    (not f.fell_back
       and not f.awaiting_first_charge
       and f.plan_status in ('trial', 'grace')
       and f.trial_ends_at is not null
       and f.trial_ends_at + make_interval(days => coalesce(sp.grace_days, 0)) < now())
      or not coalesce(f.active, true)
  from f
  left join subscription_plans sp
    on sp.id = case when f.fell_back then f.trial_fallback_plan_id else f.plan_id end
$function$;

-- ---------- 2. the Rs 5 check is not a plan payment -----------------
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

  -- 12 Nov 2026: Autopay set up during a trial takes a Rs 5 check that
  -- Razorpay refunds. Anything under half the plan amount is not a plan
  -- payment: no invoice, no change to the company.
  if gp.amount_paise is not null and p_amount_paise * 2 < gp.amount_paise then
    insert into billing_events (org_id, event_type, detail)
    values (s.org_id, 'payment_ignored',
            jsonb_build_object('amount_inr', round(p_amount_paise / 100.0, 2),
                               'payment', p_payment_id,
                               'subscription', p_gateway_sub_id,
                               'reason', 'not_a_plan_charge', 'source', 'razorpay'));
    return 'not_a_plan_charge';
  end if;

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

-- create or replace keeps grants, but restate them: these must never be
-- callable from the app.
revoke all on function public.billing_record_charge(text, text, bigint, timestamptz, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function public.billing_record_charge(text, text, bigint, timestamptz, timestamptz, timestamptz) to service_role;

-- ---------- postflight ------------------------------------------------
do $post$
declare
  v_plan text;
  v_rec  text;
begin
  -- Code markers that exist only after this script (comments stripped).
  select string_agg(l, E'\n') into v_plan
    from regexp_split_to_table(pg_get_functiondef('public.org_effective_plan(uuid)'::regprocedure), E'\n') l
   where l !~ '^\s*--';
  select string_agg(l, E'\n') into v_rec
    from regexp_split_to_table(pg_get_functiondef(
           'public.billing_record_charge(text,text,bigint,timestamptz,timestamptz,timestamptz)'::regprocedure), E'\n') l
   where l !~ '^\s*--';
  if v_plan !~ '\yawaiting_first_charge\y' then
    raise exception 'postflight: org_effective_plan was not replaced';
  end if;
  if v_rec !~ 'not_a_plan_charge' then
    raise exception 'postflight: billing_record_charge was not replaced';
  end if;
  if has_function_privilege('authenticated',
       'public.billing_record_charge(text,text,bigint,timestamptz,timestamptz,timestamptz)', 'execute')
     or has_function_privilege('anon',
       'public.billing_record_charge(text,text,bigint,timestamptz,timestamptz,timestamptz)', 'execute') then
    raise exception 'postflight: billing_record_charge is callable from the app';
  end if;
  -- Behaviour on today's data: every company still gets exactly one row.
  if exists (select 1 from organizations o
              where (select count(*) from org_effective_plan(o.id)) <> 1) then
    raise exception 'postflight: org_effective_plan does not return one row per company';
  end if;
end $post$;

commit;
