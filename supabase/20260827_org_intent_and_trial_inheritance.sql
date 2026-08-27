-- =====================================================================
-- 20260827_org_intent_and_trial_inheritance.sql
--
-- Step 3 of the wipe sequence (NAGARVA_MODULE_STATUS.md section 11).
-- Unblocks creating a SECOND and THIRD org for one owner, which signup
-- cannot do today, and fixes the trigger that silently defeats trial
-- inheritance.
--
-- Written AFTER 20260827_branches_management.sql was run, against the
-- live function body read back with pg_get_functiondef — so the
-- `perform public.seed_org_default_branch(v_org.id)` line that
-- migration added is preserved below. Do not regenerate this from an
-- older copy.
--
-- =====================================================================
-- READ THIS BEFORE EDITING: DROP DISCARDS THE ACL
-- =====================================================================
-- Adding p_intent CHANGES THE SIGNATURE, so CREATE OR REPLACE cannot be
-- used — it would create a second, overloaded function and leave the
-- old 5-arg one in place for existing callers. This migration therefore
-- DROPs and CREATEs.
--
-- `DROP FUNCTION` discards the function's grants, and a newly created
-- function defaults to EXECUTE for **PUBLIC**. Live grants today are
-- postgres + service_role ONLY — deliberately not `authenticated`, so
-- no vendor can call this over PostgREST. Recreating without
-- re-granting would hand every authenticated user the ability to call
-- it with p_intent => 'create_additional' and mint themselves orgs,
-- which is exactly what section 10.4a says must wait for billing.
--
-- The REVOKE/GRANT below restores that, and POSTFLIGHT asserts it.
-- Same class as the security_invoker hazard in CLAUDE.md: DROP silently
-- drops properties that are not part of the body.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- PREFLIGHT
-- ---------------------------------------------------------------------
do $preflight$
begin
  if to_regprocedure('public.create_org_with_owner(uuid,text,text,text,text)') is null then
    raise exception 'PREFLIGHT: the 5-arg create_org_with_owner is not present — signature may already have changed. Re-read pg_get_functiondef before running this.';
  end if;
  if to_regprocedure('public.seed_org_default_branch(uuid)') is null then
    raise exception 'PREFLIGHT: seed_org_default_branch missing. Run 20260827_branches_management.sql first.';
  end if;
  if to_regprocedure('public.seed_org_number_series(uuid)') is null
     or to_regprocedure('public.seed_org_document_settings(uuid)') is null then
    raise exception 'PREFLIGHT: seeding functions missing.';
  end if;
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.organizations'::regclass
                    and tgname = 'trg_assign_default_trial_plan') then
    raise exception 'PREFLIGHT: trg_assign_default_trial_plan not found.';
  end if;
end
$preflight$;

-- ---------------------------------------------------------------------
-- 1. assign_default_trial_plan — stop defeating inheritance
--
-- Old body:
--     if new.trial_ends_at is null then
--       new.trial_ends_at := now() + interval '14 days';
--     end if;
--
-- TWO defects, found 27 Aug 2026 when an org created by inheriting a
-- parent's NULL trial_ends_at came out with a bogus 14-day trial:
--
--   a) `is null` cannot distinguish "deliberately no trial" from
--      "caller did not supply one". Inheriting a NULL is
--      indistinguishable from omitting the field, so ANY
--      inherit-the-parent design is defeated by default-on-null logic.
--      Same class as the copyWith(x: null) bug in CLAUDE.md.
--      FIX: gate on plan_status = 'trial'. A trial end date is only
--      meaningful for a trial, so an inherited 'active' org is never
--      stamped. Signup is unaffected — it sets plan_status = 'trial'
--      AND trial_ends_at explicitly, so the guard is skipped either way.
--
--   b) It hardcoded 14 days while subscription_plans.trial_days says
--      30. They disagreed. Signup escaped it only because
--      create_org_with_owner sets trial_ends_at itself; any other
--      insert silently got 14, quietly defeating Item 32's "no
--      hardcoded plan values, editable in Super Admin" rule.
--      FIX: read trial_days from the plan.
--
-- Signature is unchanged (returns trigger), so CREATE OR REPLACE is
-- correct here — no DROP needed and the trigger keeps pointing at it.
-- ---------------------------------------------------------------------
create or replace function public.assign_default_trial_plan()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $trial_plan$
declare
  v_trial_plan_id uuid;
  v_trial_days int;
begin
  if new.plan_id is null then
    select id into v_trial_plan_id
      from public.subscription_plans
     where is_default_trial = true
     limit 1;
    new.plan_id := v_trial_plan_id;
  end if;

  -- Only a TRIAL gets a trial end date. An org inheriting an active
  -- parent's plan keeps its NULL.
  if new.trial_ends_at is null and new.plan_status = 'trial' then
    select sp.trial_days into v_trial_days
      from public.subscription_plans sp
     where sp.id = new.plan_id;
    new.trial_ends_at := now() + make_interval(days => coalesce(v_trial_days, 30));
  end if;

  return new;
end;
$trial_plan$;

-- ---------------------------------------------------------------------
-- 2. create_org_with_owner — add p_intent
--
-- 'recover' (DEFAULT, so no existing caller changes): unchanged
--     behaviour. If the user already belongs to an org, return it with
--     is_new = false. This is the confirmation-gap repair path
--     vendor_org_resolver.dart depends on — a user confirms their email
--     in a different app instance than the one that called signUp(), so
--     create-org never ran and this finishes the job. It must stay
--     idempotent; without it every retry would mint a duplicate org.
--
-- 'create_additional': deliberately creating another org for an owner
--     who already has one. REJECTED if the caller has NO membership —
--     that inversion is the point: recover is for people with no org,
--     create_additional is for people who have one, and each guards
--     against being mistaken for the other.
--
--     Inherits plan_id, plan_status AND trial_ends_at from the parent
--     (the caller's OLDEST membership). Settled policy, not a per-org
--     choice: the owner is ONE customer and his locations all sit on
--     the same tier. A trial belongs only to a genuinely new customer.
-- ---------------------------------------------------------------------
drop function if exists public.create_org_with_owner(uuid,text,text,text,text);

create function public.create_org_with_owner(
  p_user_id uuid,
  p_org_name text,
  p_phone text default null::text,
  p_gstin text default null::text,
  p_owner_name text default null::text,
  p_intent text default 'recover')
returns table(is_new boolean, org_id uuid, org_name text, org_slug text,
              plan_id uuid, plan_name text, plan_status text,
              plan_limits jsonb, plan_features jsonb,
              trial_ends_at timestamp with time zone, org_active boolean,
              caller_role text)
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $create_org$
declare
  v_existing record;
  v_base_slug text;
  v_slug text;
  v_org record;
  v_plan record;
  v_attempt int := 0;
  v_has_membership boolean := false;
  -- What the new row will carry. Set from the default trial plan for a
  -- first org, or inherited from the parent for an additional one.
  v_plan_id uuid;
  v_plan_status text;
  v_trial_ends timestamptz;
  v_plan_name text;
  v_limits jsonb;
  v_features jsonb;
begin
  if p_user_id is null then
    raise exception 'p_user_id is required' using errcode = '22004';
  end if;
  if p_org_name is null or length(trim(p_org_name)) = 0 then
    raise exception 'p_org_name is required' using errcode = '22004';
  end if;
  if p_intent is null or p_intent not in ('recover', 'create_additional') then
    raise exception 'p_intent must be ''recover'' or ''create_additional'', got %', p_intent
      using errcode = '22023';
  end if;

  select om.org_id, om.role into v_existing
    from public.org_members om
   where om.user_id = p_user_id
   order by om.created_at asc
   limit 1;
  v_has_membership := found;

  -- RECOVER: hand back the org they already have. Unchanged.
  if v_has_membership and p_intent = 'recover' then
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

  -- CREATE_ADDITIONAL requires an existing membership. Refusing here is
  -- what stops this intent from silently becoming a duplicate-org bug
  -- for a brand-new user whose caller passed the wrong intent.
  if p_intent = 'create_additional' and not v_has_membership then
    raise exception
      'create_additional requires an existing organization; this account has none. Use the normal signup flow.'
      using errcode = 'P0001';
  end if;

  if p_intent = 'create_additional' then
    -- Inherit from the parent org. NOT a fresh trial.
    select o.plan_id, o.plan_status, o.trial_ends_at,
           sp.name, coalesce(sp.limits, '{}'::jsonb), coalesce(sp.features, '{}'::jsonb)
      into v_plan_id, v_plan_status, v_trial_ends, v_plan_name, v_limits, v_features
      from public.organizations o
      left join public.subscription_plans sp on sp.id = o.plan_id
     where o.id = v_existing.org_id;
    if v_plan_id is null then
      raise exception 'Parent organization has no plan to inherit' using errcode = 'P0001';
    end if;
  else
    -- First org for this user: the default trial plan.
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
    v_plan_id := v_plan.id;
    v_plan_name := v_plan.name;
    v_limits := coalesce(v_plan.limits, '{}'::jsonb);
    v_features := coalesce(v_plan.features, '{}'::jsonb);
    v_plan_status := 'trial';
    v_trial_ends := now() + make_interval(days => coalesce(v_plan.trial_days, 30));
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
      insert into public.organizations
        (name, slug, phone, gstin, signatory_name, plan_id, plan_status, trial_ends_at, active)
      values
        (trim(p_org_name), v_slug,
         nullif(trim(coalesce(p_phone, '')), ''),
         nullif(trim(coalesce(p_gstin, '')), ''),
         nullif(trim(coalesce(p_owner_name, '')), ''),
         v_plan_id, v_plan_status, v_trial_ends, true)
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
  -- ADDED 27 Aug 2026 by 20260827_branches_management.sql: without a
  -- branch the org cannot create an order, a lead, or a staff member.
  perform public.seed_org_default_branch(v_org.id);

  return query
  select true, v_org.id, v_org.name, v_org.slug, v_org.plan_id, v_plan_name,
         v_org.plan_status, v_limits, v_features, v_org.trial_ends_at,
         v_org.active, 'owner'::text;
end;
$create_org$;

-- ---------------------------------------------------------------------
-- 3. Restore the ACL the DROP discarded. See this file's header.
-- ---------------------------------------------------------------------
revoke all on function public.create_org_with_owner(uuid,text,text,text,text,text) from public;
revoke all on function public.create_org_with_owner(uuid,text,text,text,text,text) from anon;
revoke all on function public.create_org_with_owner(uuid,text,text,text,text,text) from authenticated;
grant execute on function public.create_org_with_owner(uuid,text,text,text,text,text) to service_role;

-- ---------------------------------------------------------------------
-- POSTFLIGHT — abort and roll back on anything unexpected
-- ---------------------------------------------------------------------
do $postflight$
declare
  v_def text;
  v_acl text;
begin
  if to_regprocedure('public.create_org_with_owner(uuid,text,text,text,text,text)') is null then
    raise exception 'POSTFLIGHT: 6-arg create_org_with_owner was not created.';
  end if;
  if to_regprocedure('public.create_org_with_owner(uuid,text,text,text,text)') is not null then
    raise exception 'POSTFLIGHT: the old 5-arg overload still exists — callers would split between two functions.';
  end if;

  -- The seeding call must have survived the rewrite.
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'create_org_with_owner';
  if position('seed_org_default_branch' in v_def) = 0 then
    raise exception 'POSTFLIGHT: seed_org_default_branch call is missing — this migration was written against a stale body.';
  end if;

  -- ACL: service_role yes, authenticated/anon/PUBLIC no.
  select coalesce(array_to_string(p.proacl, ' | '), '') into v_acl
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'create_org_with_owner';
  if position('service_role=X' in v_acl) = 0 then
    raise exception 'POSTFLIGHT: service_role cannot execute create_org_with_owner — the create-org Edge Function would break.';
  end if;
  if position('authenticated=X' in v_acl) > 0 or position('anon=X' in v_acl) > 0 then
    raise exception 'POSTFLIGHT: create_org_with_owner is executable by authenticated/anon — a vendor could mint their own orgs.';
  end if;

  -- The trigger fix must be in place.
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'assign_default_trial_plan';
  if position('plan_status' in v_def) = 0 then
    raise exception 'POSTFLIGHT: assign_default_trial_plan is not gated on plan_status.';
  end if;
  if position('14 days' in v_def) > 0 then
    raise exception 'POSTFLIGHT: assign_default_trial_plan still hardcodes 14 days.';
  end if;

  raise notice 'POSTFLIGHT OK.';
end
$postflight$;

commit;
