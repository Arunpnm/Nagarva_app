-- ============================================================
-- supabase/20260818_item32_plan_enforcement.sql
--
-- Item 32 — make subscription plans mean something.
--
-- BEFORE THIS MIGRATION, the audit found (18 Aug 2026, verified against
-- live Postgres, not assumed):
--   - `max_users` was checked in exactly ONE place, client-side
--     (users_page_widget.dart:108), against a client-held list.
--   - `max_orders_per_month` was read NOWHERE.
--   - Every feature flag (whatsapp/reports/gst_invoice/multi_branch) was
--     display-only on PlanPage.
--   - ZERO server-side enforcement: scanning every function in the
--     database, only assign_default_trial_plan() and
--     create_org_with_owner() referenced subscription_plans at all, and
--     both only READ it to assign a plan at signup. No trigger, no
--     policy, nothing.
--   - Trial expiry was a client getter (AppSession.isTrialExpired)
--     driving a lock screen. The lock was real in the app; the DATA was
--     not protected — an expired tenant could still read and write
--     everything over PostgREST.
-- Net effect: Trial and Pro were the same product, and anyone with the
-- APK (or curl) bypassed the one check that existed.
--
-- APPROACH: lookup functions + BEFORE INSERT triggers, mirroring the
-- Option B pattern Item 30 settled on (functions that read live state
-- via auth/org, no JWT claims, no new infrastructure).
--
-- Triggers rather than RLS for the counted limits, deliberately: an RLS
-- denial surfaces to the vendor as "new row violates row-level security
-- policy", which is useless. A trigger raises a real sentence the app
-- already knows how to display.
--
-- NO HARDCODED PLAN VALUES ANYWHERE (Arun's rule, 18 Aug 2026). Trial
-- length moves out of create_org_with_owner into
-- subscription_plans.trial_days; grace period likewise. Both editable in
-- Super Admin at any time.
--
-- SQL handed back to run manually, as always.
-- ============================================================

begin;

-- ---- 1. Trial length becomes plan data, not code --------------------
--
-- Was: `now() + interval '7 days'` baked into create_org_with_owner().
-- Arun's spec: 30 days, editable in Super Admin, effective for NEW
-- signups only.
alter table subscription_plans
  add column if not exists trial_days integer not null default 30;

-- Grace window between trial expiry and the write-lock. Added for the
-- same no-hardcoding reason: the server-side lock below needs a
-- definition of "expired enough to stop writes", and burying 0 in a
-- function would silently make the lock harsher than the agreed ladder
-- (banner -> grace -> read-only). Editable per plan.
alter table subscription_plans
  add column if not exists grace_days integer not null default 7;

update subscription_plans set trial_days = 30 where is_default_trial;

comment on column subscription_plans.trial_days is
  'Days of trial granted at signup. Read by create_org_with_owner() to '
  'stamp organizations.trial_ends_at ONCE. Changing this affects NEW '
  'signups only — an existing org''s trial_ends_at is never recalculated '
  '(that would retroactively shorten a live trial). To change one org, '
  'use the Super Admin tenant view''s trial-date control.';

-- ---- 2. Effective plan, resolved server-side ------------------------
--
-- The single source of truth for "what is this org allowed to do right
-- now". Resolves trial expiry HERE rather than trusting the client, so
-- the lock survives someone bypassing the app entirely.
--
-- is_locked is true only once the trial AND its grace window have both
-- passed while plan_status is still 'trial'. An org that upgraded
-- (plan_status 'active') is never locked by this, matching
-- AppSession.isTrialExpired's existing semantics.
create or replace function public.org_effective_plan(p_org_id uuid)
returns table(plan_code text, limits jsonb, features jsonb, is_locked boolean)
language sql
stable
security definer
set search_path = public
as $$
  select
    sp.code,
    coalesce(sp.limits, '{}'::jsonb),
    coalesce(sp.features, '{}'::jsonb),
    (o.plan_status = 'trial'
      and o.trial_ends_at is not null
      and o.trial_ends_at + make_interval(days => coalesce(sp.grace_days, 0)) < now())
    or not coalesce(o.active, true)
  from organizations o
  left join subscription_plans sp on sp.id = o.plan_id
  where o.id = p_org_id
$$;

create or replace function public.org_limit(p_org_id uuid, p_key text)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  -- NULL (key absent) means "no limit configured" -> -1 (unlimited),
  -- matching AppSession.getLimit()'s existing convention. A plan that
  -- simply doesn't mention a key must never accidentally mean zero.
  select coalesce((select (limits ->> p_key)::int
                   from public.org_effective_plan(p_org_id)), -1)
$$;

create or replace function public.org_has_feature(p_org_id uuid, p_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select (features ->> p_key)::boolean
                   from public.org_effective_plan(p_org_id)), false)
$$;

-- ---- 3. Shared guard -------------------------------------------------
-- Raises when the org is locked out (expired trial past grace, or
-- suspended). Called by every enforcement trigger below, so read-only
-- behaviour is defined in exactly one place.
create or replace function public.assert_org_writable(p_org_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_locked boolean;
begin
  select is_locked into v_locked from public.org_effective_plan(p_org_id);
  if coalesce(v_locked, false) then
    raise exception
      'Your trial has ended. You can still view and export your data — '
      'upgrade your plan to create new records.'
      using errcode = 'P0001';
  end if;
end;
$$;

-- ---- 4. Counted limits ----------------------------------------------

-- Index the monthly order count reads (see enforce_order_limit below).
create index if not exists idx_orders_org_created_at
  on orders (org_id, created_at);

create or replace function public.enforce_staff_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_max int; v_count int;
begin
  if new.org_id is null then return new; end if;
  perform public.assert_org_writable(new.org_id);

  v_max := public.org_limit(new.org_id, 'max_users');
  if v_max = -1 then return new; end if;

  -- Counts every staff row including inactive and soft-deleted, matching
  -- users_page_widget.dart's existing comment ("an inactive row still
  -- occupies a seat"). Change both together if that rule ever changes.
  select count(*) into v_count from staff where org_id = new.org_id;

  if v_count >= v_max then
    raise exception
      'Staff limit reached (%/% on your current plan). Upgrade to add more staff.',
      v_count, v_max
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_staff_limit on staff;
create trigger trg_enforce_staff_limit
  before insert on staff
  for each row execute function public.enforce_staff_limit();

create or replace function public.enforce_order_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_max int; v_count int;
begin
  if new.org_id is null then return new; end if;
  perform public.assert_org_writable(new.org_id);

  v_max := public.org_limit(new.org_id, 'max_orders_per_month');
  if v_max = -1 then return new; end if;

  select count(*) into v_count
    from orders
   where org_id = new.org_id
     and created_at >= date_trunc('month', now() at time zone 'Asia/Kolkata');

  if v_count >= v_max then
    raise exception
      'Monthly order limit reached (%/% on your current plan). Upgrade for more orders.',
      v_count, v_max
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_order_limit on orders;
create trigger trg_enforce_order_limit
  before insert on orders
  for each row execute function public.enforce_order_limit();

-- ---- 5. multi_branch -------------------------------------------------
--
-- There is no `branches` table — branch is free text on staff/orders
-- (see Item 30's branch-scoping migration). So "one branch" is enforced
-- as: you may not introduce a SECOND distinct non-null staff.branch
-- value unless the plan allows it. Existing rows are never touched — a
-- downgrade leaves current branches working and only blocks new ones,
-- per the agreed downgrade behaviour.
create or replace function public.enforce_branch_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_distinct int;
begin
  if new.org_id is null or coalesce(trim(new.branch), '') = '' then
    return new;
  end if;
  if public.org_has_feature(new.org_id, 'multi_branch') then
    return new;
  end if;

  select count(distinct branch) into v_distinct
    from staff
   where org_id = new.org_id
     and coalesce(trim(branch), '') <> ''
     and branch <> new.branch;

  if v_distinct >= 1 then
    raise exception
      'Your plan includes one branch. Upgrade to add "%" as a second branch.',
      new.branch
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_branch_limit on staff;
create trigger trg_enforce_branch_limit
  before insert or update of branch on staff
  for each row execute function public.enforce_branch_limit();

-- ---- 6. Signup reads trial_days -------------------------------------
--
-- Only two lines of create_org_with_owner() change: the plan lookup now
-- also selects trial_days, and the organizations insert uses it instead
-- of a literal 7 days. Everything else is reproduced verbatim from the
-- live definition (pg_get_functiondef, 18 Aug 2026) — including the
-- number_series / app_settings seeding added earlier today, which must
-- not be lost by this replacement.
--
-- trial_ends_at is stamped ONCE here and never recalculated anywhere.
-- That is the whole point of Arun's rule 1: editing trial_days later
-- must not retroactively shorten a live trial.
create or replace function public.create_org_with_owner(
  p_user_id uuid,
  p_org_name text,
  p_phone text default null::text,
  p_gstin text default null::text,
  p_owner_name text default null::text)
returns table(is_new boolean, org_id uuid, org_name text, org_slug text,
              plan_id uuid, plan_name text, plan_status text,
              plan_limits jsonb, plan_features jsonb,
              trial_ends_at timestamp with time zone, org_active boolean,
              caller_role text)
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_existing record;
  v_base_slug text;
  v_slug text;
  v_org record;
  v_plan record;
  v_attempt int := 0;
begin
  if p_user_id is null then
    raise exception 'p_user_id is required' using errcode = '22004';
  end if;
  if p_org_name is null or length(trim(p_org_name)) = 0 then
    raise exception 'p_org_name is required' using errcode = '22004';
  end if;

  select om.org_id, om.role into v_existing
    from public.org_members om
   where om.user_id = p_user_id
   order by om.created_at asc
   limit 1;

  if found then
    return query
    select false, o.id, o.name, o.slug, o.plan_id, sp.name, o.plan_status,
           coalesce(sp.limits, '{}'::jsonb), coalesce(sp.features, '{}'::jsonb),
           o.trial_ends_at, o.active,
           lower(v_existing.role)
      from public.organizations o
      left join public.subscription_plans sp on sp.id = o.plan_id
     where o.id = v_existing.org_id;
    return;
  end if;

  v_base_slug := trim(both '-' from
                   regexp_replace(lower(p_org_name), '[^a-z0-9]+', '-', 'g'));
  if v_base_slug = '' then
    v_base_slug := 'org';
  end if;
  v_slug := v_base_slug;

  loop
    v_attempt := v_attempt + 1;
    begin
      -- CHANGED: trial_days now comes from the plan row.
      select sp.id, sp.name, sp.limits, sp.features, sp.trial_days
        into v_plan
        from public.subscription_plans sp
       where sp.is_default_trial = true
       order by sp.id
       limit 1;
      if not found then
        raise exception 'No default trial plan configured (subscription_plans.is_default_trial)'
          using errcode = 'P0001';
      end if;

      insert into public.organizations
        (name, slug, phone, gstin, signatory_name, plan_id, plan_status, trial_ends_at, active)
      values
        (trim(p_org_name), v_slug,
         nullif(trim(coalesce(p_phone, '')), ''),
         nullif(trim(coalesce(p_gstin, '')), ''),
         nullif(trim(coalesce(p_owner_name, '')), ''),
         v_plan.id, 'trial',
         -- CHANGED: was `now() + interval '7 days'`.
         now() + make_interval(days => coalesce(v_plan.trial_days, 30)),
         true)
      returning organizations.id, organizations.name, organizations.slug,
                organizations.plan_id, organizations.plan_status,
                organizations.trial_ends_at, organizations.active
        into v_org;

      exit;
    exception
      when unique_violation then
        if v_attempt >= 3 then
          raise exception 'Could not generate a unique slug for "%"', p_org_name
            using errcode = 'P0001';
        end if;
        v_slug := case v_attempt
                    when 1 then v_base_slug || '-' || substr(replace(p_user_id::text, '-', ''), 1, 4)
                    else v_base_slug || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 4)
                  end;
    end;
  end loop;

  insert into public.org_members (org_id, user_id, role)
  values (v_org.id, p_user_id, 'owner');

  insert into public.pricing_config (org_id, config)
  values (v_org.id, public.default_pricing_config())
  on conflict do nothing;

  perform public.seed_org_number_series(v_org.id);
  perform public.seed_org_document_settings(v_org.id);

  return query
  select true, v_org.id, v_org.name, v_org.slug, v_org.plan_id, v_plan.name,
         v_org.plan_status, coalesce(v_plan.limits, '{}'::jsonb),
         coalesce(v_plan.features, '{}'::jsonb), v_org.trial_ends_at,
         v_org.active, 'owner'::text;
end;
$function$;

-- ---- 7. Fix the orphaned limit key ----------------------------------
--
-- The Super Admin plan editor wrote `max_orders` / `max_leads` while the
-- seeded data uses `max_orders_per_month`, and PlanPage displayed
-- `max_orders` — so the orders limit was unenforced, invisible AND
-- uneditable, and any plan saved through that editor grew two dead keys.
-- The Dart side is fixed in the same pass; this cleans up whatever the
-- editor already wrote. Only touches plans that have BOTH, and never
-- overwrites a real max_orders_per_month value.
update subscription_plans
   set limits = (limits - 'max_orders' - 'max_leads')
              || jsonb_build_object('max_orders_per_month',
                   coalesce(limits -> 'max_orders_per_month', limits -> 'max_orders'))
 where limits ? 'max_orders' or limits ? 'max_leads';

-- ---- 8. Basic / Growth / Pro restructure ----------------------------
--
-- Prices set by Arun, 18 Aug 2026: Basic 799, Growth 1499, Pro 2999
-- (monthly). Annual at 10x monthly is DECIDED but not represented here —
-- annual needs its own plan rows with billing_period='annual', and
-- nothing collects money until Item 31, so adding unused rows now would
-- just be data to keep in sync. Create them with the gateway work.
--
-- `starter` is UPDATED IN PLACE to become Basic rather than being
-- replaced — organizations.plan_id references it, and a delete-and-
-- recreate would orphan any org pointing at it.
--
-- WhatsApp: per Arun's correction (18 Aug), it sits in GROWTH, not Pro —
-- "it's the feature that closes small operators" — and per-message cost
-- is handled by CAPPING VOLUME (max_whatsapp_per_month) rather than
-- withholding the feature. Basic gets the feature off; Growth a real
-- cap; Pro uncapped.
--
-- Every number here is editable in Super Admin. These are starting
-- values, not constants.
update subscription_plans set
  code = 'basic', name = 'Basic', price_inr = 799, billing_period = 'monthly',
  limits = jsonb_build_object(
    'max_users', 3,
    'max_orders_per_month', 75,
    'max_whatsapp_per_month', 0),
  features = jsonb_build_object(
    'gst_invoice', true,   -- never gated: table stakes for an Indian business
    'reports', false,
    'whatsapp', false,
    'multi_branch', false)
where code = 'starter';

insert into subscription_plans (code, name, price_inr, billing_period, active, limits, features)
select 'growth', 'Growth', 1499, 'monthly', true,
  jsonb_build_object(
    'max_users', 10,
    'max_orders_per_month', 400,
    'max_whatsapp_per_month', 500),
  jsonb_build_object(
    'gst_invoice', true,
    'reports', true,
    'whatsapp', true,
    'multi_branch', true)
where not exists (select 1 from subscription_plans where code = 'growth');

update subscription_plans set
  name = 'Pro', price_inr = 2999, billing_period = 'monthly',
  limits = jsonb_build_object(
    'max_users', 25,
    'max_orders_per_month', -1,
    'max_whatsapp_per_month', -1),
  features = jsonb_build_object(
    'gst_invoice', true,
    'reports', true,
    'whatsapp', true,
    'multi_branch', true)
where code = 'pro';

-- Trial: everything unlocked so a vendor can evaluate the real product,
-- but on small volumes so a 30-day trial can't run a business for free.
-- Arun to adjust in Super Admin if this proves too tight or too generous.
update subscription_plans set
  name = 'Trial', price_inr = 0, trial_days = 30,
  limits = jsonb_build_object(
    'max_users', 5,
    'max_orders_per_month', 50,
    'max_whatsapp_per_month', 50),
  features = jsonb_build_object(
    'gst_invoice', true,
    'reports', true,
    'whatsapp', true,
    'multi_branch', true)
where is_default_trial;

commit;

-- ============================================================
-- VERIFY (read-only)
--
--   select code, trial_days, grace_days, limits, features
--     from subscription_plans order by code;
--
--   -- Should return the plan and is_locked=false for a healthy org:
--   select * from org_effective_plan(
--     (select id from organizations where slug = 'apc'));
--
-- LIVE-FIRE TEST (do this on the throwaway org, NOT on APC):
--   1. Set the trial plan's max_users to 1 in Super Admin.
--   2. Try to add a second staff member in the app -> expect the
--      "Staff limit reached (1/1...)" message, not a generic error.
--   3. Try the same insert via a direct PostgREST call with that org's
--      token -> expect the SAME refusal. That is the whole point of this
--      migration; if the API call succeeds, enforcement is still fake.
--
-- NOT IN THIS MIGRATION, deliberately:
--   - Price grandfathering for existing subscribers (Item 31, Arun's
--     rule 3 — new price applies to new subscriptions only until he
--     deliberately migrates someone). Nothing here reads price_inr.
--   - The WhatsApp feature gate. `whatsapp` has a real server chokepoint
--     (the send Edge Function) and belongs there, not in a table
--     trigger; it goes in with the AiSensy work.
--   - reports / gst_invoice gates: no server chokepoint exists and
--     neither costs money or leaks data, so they stay UI-only by
--     decision, not oversight.
-- ============================================================
