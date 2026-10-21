-- Nagarva: make a brand-new org come out of signup COMPLETE.
--
-- BLOCKER for the friends beta (22 Sep 2026): testers each register a new
-- company through create_org_with_owner, not the owner's own login. That
-- function calls four seeders (number_series, document_settings,
-- default_branch, lr_series) and trg_assign_default_trial_plan attaches the
-- plan. It does NOT set up three things the job flow depends on:
--
--   cft_catalogue      seed_cft_catalogue_for_org() already exists but is
--                       never called by create_org_with_owner (no trigger
--                       calls it either).
--   rate_card_rules     no seeder exists. The 20260909 slab migration
--                       backfilled the 3 existing orgs (and their one
--                       default rate_cards row each) by hand.
--   pricing_config       an insert already lives inline in
--                       create_org_with_owner, using default_pricing_config()
--                       — so survey_cats is NOT actually missing for a new
--                       org (verified against the live function before
--                       writing this migration). But default_pricing_config()
--                       bakes in real numbers (porter_rates 16/19, GST
--                       default_pct 5) that violate the product rule: no
--                       price, rate, wage or charge is ever pre-filled for a
--                       vendor. That's what this migration actually fixes
--                       here, plus turning the inline insert into a named,
--                       idempotent seeder like its siblings.
--
-- Fix: two new seeders (seed_rate_card_rules_for_org,
-- seed_pricing_config_for_org — cft_catalogue's seeder already existed),
-- all three wired into create_org_with_owner, and a postflight that creates
-- a REAL org through create_org_with_owner inside this transaction, asserts
-- all seven dependencies exist for it, then rolls back — never trusting
-- that the function body merely names the right seeders.
--
-- §52: catalogue CFT and slab bands/vehicle/crew are operational data and
-- ARE seeded. Every money column on those rows opens at zero.
-- pricing_config seeds no prices.
--
-- No explicit BEGIN/COMMIT here: apply_migration already runs this file in
-- its own transaction, and the postflight below relies on that -- it uses
-- PL/pgSQL's implicit-savepoint EXCEPTION trick to undo only the probe
-- org's writes while leaving this migration's DDL to commit normally.
--
-- Applied to the live project (hqqcapifefsaqvotqvlt) on 2026-09-22 as
-- migration version 20260922033222; the postflight below ran for real
-- against a probe org and passed before this file was written to disk.

-- =====================================================================
-- 1. seed_rate_card_rules_for_org
--    Recreates, per org, exactly what the 20260909 slab migration put in
--    by hand for the 3 existing orgs: one default "Standard CFT slabs"
--    rate card, and its 14 CFT-band rows. house_type / vehicle_class /
--    suggested_crew are operational (seeded); every money column
--    (base_amount, per_km_rate, per_cft_rate, min_charge) is 0 — the
--    vendor sets their own rates. Idempotent: safe to call twice.
-- =====================================================================

create or replace function public.seed_rate_card_rules_for_org(p_org_id uuid)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare
  v_card_id uuid;
  v_n integer;
begin
  if p_org_id is null then
    raise exception 'seed_rate_card_rules_for_org: p_org_id is null.';
  end if;
  if not exists (select 1 from organizations where id = p_org_id) then
    raise exception 'seed_rate_card_rules_for_org: org % does not exist.', p_org_id;
  end if;

  -- rate_card_rules.card_id -> rate_cards(id) on delete cascade: the rows
  -- below cannot exist without a card. One default standard card per org,
  -- matching the 3 hand-backfilled orgs exactly (name/code/notes).
  select id into v_card_id
    from rate_cards
   where org_id = p_org_id
     and is_default = true
     and card_type = 'standard'
   limit 1;

  if v_card_id is null then
    insert into rate_cards
      (org_id, name, code, card_type, is_default, active, valid_from, notes)
    values
      (p_org_id, 'Standard CFT slabs', 'STD-CFT', 'standard', true, true, current_date,
       'Seeded at signup. CFT band -> house type, vehicle class, crew. No pricing on these rows; the vendor sets their own rates.')
    returning id into v_card_id;
  end if;

  insert into rate_card_rules
    (org_id, card_id, service, order_type, min_km, max_km, min_cft, max_cft,
     base_amount, per_km_rate, per_cft_rate, min_charge, vehicle_type,
     suggested_crew, house_type, vehicle_class, active)
  select p_org_id, v_card_id, 'home_shifting', 'local', 0, null,
         d.min_cft, d.max_cft, 0, 0, 0, 0, null, d.suggested_crew, d.house_type, d.vehicle_class, true
    from (values
      (0::numeric,    100::numeric,   'Micro Shifting'::text, 'Tata Ace'::text, 2),
      (101::numeric,  180::numeric,   '1 RK/Studio',           'Tata Ace',       2),
      (181::numeric,  240::numeric,   '1 BHK Small',           'Bolero',         3),
      (241::numeric,  330::numeric,   '1 BHK Medium',          '407',            3),
      (331::numeric,  450::numeric,   '1 BHK Big',             '14 ft',          4),
      (451::numeric,  520::numeric,   '2 BHK Small',           '14 ft',          4),
      (521::numeric,  650::numeric,   '2 BHK Medium',          '17 ft',          5),
      (651::numeric,  720::numeric,   '2 BHK Big',             '17 ft',          5),
      (721::numeric,  820::numeric,   '3 BHK Small',           '19 ft',          6),
      (821::numeric,  1000::numeric,  '3 BHK Medium',          '19 ft',          6),
      (1001::numeric, 1150::numeric,  '3 BHK Big',             '22 ft',          7),
      (1151::numeric, 1300::numeric,  '4 BHK Small',           '32 ft',          8),
      (1301::numeric, 1500::numeric,  '4 BHK Medium',          '32 ft',          8),
      (1501::numeric, null::numeric,  '4 BHK Big',             '32 ft',          10)
    ) as d(min_cft, max_cft, house_type, vehicle_class, suggested_crew)
  on conflict on constraint rate_card_rules_no_overlap do nothing;

  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

-- =====================================================================
-- 2. default_pricing_config_for_new_org / seed_pricing_config_for_org
--    default_pricing_config() itself is left untouched (other code may
--    reference it as APC's own structure). This wrapper takes the same
--    structural defaults (survey_cats, cft_ranges, packages, field
--    labels, gst sac/rates options) but zeroes every actual money value
--    -- porter_rates and gst.default_pct -- before a new tenant ever sees
--    it, per the product rule that no price/rate/wage/charge is ever
--    pre-filled for a vendor.
-- =====================================================================

create or replace function public.default_pricing_config_for_new_org()
returns jsonb
language sql
immutable
as $function$
  select jsonb_set(
           jsonb_set(
             public.default_pricing_config(),
             '{porter_rates}', '{"local": 0, "outstation": 0}'::jsonb
           ),
           '{gst,default_pct}', '0'::jsonb
         );
$function$;

create or replace function public.seed_pricing_config_for_org(p_org_id uuid)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare
  v_n integer;
begin
  if p_org_id is null then
    raise exception 'seed_pricing_config_for_org: p_org_id is null.';
  end if;
  if not exists (select 1 from organizations where id = p_org_id) then
    raise exception 'seed_pricing_config_for_org: org % does not exist.', p_org_id;
  end if;

  insert into pricing_config (org_id, config)
  values (p_org_id, public.default_pricing_config_for_new_org())
  on conflict (org_id) do nothing;

  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

-- =====================================================================
-- 3. create_org_with_owner: call all seven seeders. Same signature, same
--    return type -- CREATE OR REPLACE is safe (no DROP needed).
-- =====================================================================

create or replace function public.create_org_with_owner(p_user_id uuid, p_org_name text, p_phone text DEFAULT NULL::text, p_gstin text DEFAULT NULL::text, p_owner_name text DEFAULT NULL::text, p_intent text DEFAULT 'recover'::text)
 returns TABLE(is_new boolean, org_id uuid, org_name text, org_slug text, plan_id uuid, plan_name text, plan_status text, plan_limits jsonb, plan_features jsonb, trial_ends_at timestamp with time zone, org_active boolean, caller_role text)
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
  v_has_membership boolean := false;
  -- What the new row will carry. Set from the default trial plan for a
  -- first org, or inherited from the parent for an additional one.
  v_plan_id uuid;
  v_plan_status text;
  v_trial_ends timestamptz;
  v_plan_name text;
  v_limits jsonb;
  v_features jsonb;
  -- ADDED 28 Aug 2026: the parent plan's own trial_days, so an
  -- additional org can compute its window instead of copying a date.
  v_trial_days int;
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
           sp.name, coalesce(sp.limits, '{}'::jsonb), coalesce(sp.features, '{}'::jsonb),
           sp.trial_days
      into v_plan_id, v_plan_status, v_trial_ends, v_plan_name, v_limits,
           v_features, v_trial_days
      from public.organizations o
      left join public.subscription_plans sp on sp.id = o.plan_id
     where o.id = v_existing.org_id;
    if v_plan_id is null then
      raise exception 'Parent organization has no plan to inherit' using errcode = 'P0001';
    end if;

    -- CHANGED 28 Aug 2026. The plan, its limits and its status are still
    -- inherited — an additional org must NOT get a second free trial.
    -- But the DATE is computed, not copied.
    --
    -- Copying it verbatim meant an org created after the parent's trial
    -- lapsed was born already expired, and Item 32b's
    -- enforce_org_writable() then blocked every insert on it. The
    -- vendor makes a company they cannot use.
    --
    -- Only touched while the parent is on 'trial'; for an active/paid
    -- parent trial_ends_at is irrelevant and passes through unchanged,
    -- which keeps assign_default_trial_plan's gate behaviour intact.
    if v_plan_status = 'trial' then
      v_trial_ends := now() + make_interval(days => coalesce(v_trial_days, 30));
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

  perform public.seed_org_number_series(v_org.id);
  perform public.seed_org_document_settings(v_org.id);
  -- ADDED 27 Aug 2026 by 20260827_branches_management.sql: without a
  -- branch the org cannot create an order, a lead, or a staff member.
  perform public.seed_org_default_branch(v_org.id);
  -- ADDED 28 Aug 2026: without this next_lr_number() raises P0001 on
  -- the first consignment note. The number_series 'lr' row seeded above
  -- is a dead mirror and does NOT cover this.
  perform public.seed_org_lr_series(v_org.id);
  -- ADDED 22 Sep 2026 (friends-beta blocker, §52): a new tenant's
  -- customer must be able to run a survey and staff must be able to
  -- price a job from day one.
  perform public.seed_cft_catalogue_for_org(v_org.id);
  perform public.seed_rate_card_rules_for_org(v_org.id);
  perform public.seed_pricing_config_for_org(v_org.id);

  return query
  select true, v_org.id, v_org.name, v_org.slug, v_org.plan_id, v_plan_name,
         v_org.plan_status, v_limits, v_features, v_org.trial_ends_at,
         v_org.active, 'owner'::text;
end;
$function$;

-- =====================================================================
-- 4. Postflight: create a REAL org through create_org_with_owner inside
--    this transaction, assert all seven dependencies exist for it, then
--    roll back. This does NOT trust that the function body above merely
--    names the right seeders -- it runs it and checks the tables.
--
--    Both create_org_with_owner intents ('recover' for a truly new
--    user, 'create_additional' for an existing one) fall through to the
--    identical, unconditional seeding block above -- so probing with
--    'create_additional' against any existing auth user exercises
--    exactly the same seeding path a brand-new friend's signup takes.
--
--    The probe org's writes are always undone: PL/pgSQL's EXCEPTION
--    clause rolls back to an implicit savepoint the moment an exception
--    propagates out of the block, so raising a sentinel unconditionally
--    at the end (success or failure) is what actually discards the
--    probe row -- an explicit ROLLBACK statement cannot be used here,
--    it would abort this migration's own DDL along with it.
-- =====================================================================

do $$
declare
  v_user_id uuid;
  v_org_id uuid;
  v_ns   int;  -- number_series
  v_ds   int;  -- document_settings (app_settings, category='documents')
  v_br   int;  -- default_branch (branches)
  v_lr   int;  -- lr_series
  v_cft  int;  -- cft_catalogue
  v_rcr  int;  -- rate_card_rules
  v_rc   int;  -- rate_cards (the card rate_card_rules attaches to)
  v_pc   int;  -- pricing_config
  v_errors text[] := '{}';
begin
  select id into v_user_id from auth.users order by created_at limit 1;
  if v_user_id is null then
    raise notice 'seed_org_postflight: no auth.users row available to probe with; skipping (nothing to verify create_org_with_owner against).';
    return;
  end if;

  begin
    select coa.org_id into v_org_id
      from public.create_org_with_owner(
             p_user_id  => v_user_id,
             p_org_name => '__seed_postflight_probe__',
             p_intent   => 'create_additional'
           ) coa;

    select count(*) into v_ns  from public.number_series r where r.org_id = v_org_id;
    select count(*) into v_ds  from public.app_settings r where r.org_id = v_org_id and r.category = 'documents';
    select count(*) into v_br  from public.branches r where r.org_id = v_org_id;
    select count(*) into v_lr  from public.lr_series r where r.org_id = v_org_id;
    select count(*) into v_cft from public.cft_catalogue r where r.org_id = v_org_id;
    select count(*) into v_rcr from public.rate_card_rules r where r.org_id = v_org_id;
    select count(*) into v_rc  from public.rate_cards r where r.org_id = v_org_id;
    select count(*) into v_pc  from public.pricing_config r where r.org_id = v_org_id;

    if v_ns = 0  then v_errors := v_errors || 'number_series: 0 rows'; end if;
    if v_ds = 0  then v_errors := v_errors || 'document_settings (app_settings): 0 rows'; end if;
    if v_br = 0  then v_errors := v_errors || 'default_branch (branches): 0 rows'; end if;
    if v_lr = 0  then v_errors := v_errors || 'lr_series: 0 rows'; end if;
    if v_cft = 0 then v_errors := v_errors || 'cft_catalogue: 0 rows'; end if;
    if v_rcr = 0 then v_errors := v_errors || 'rate_card_rules: 0 rows'; end if;
    if v_rc = 0  then v_errors := v_errors || 'rate_cards (default card): 0 rows'; end if;
    if v_pc = 0  then v_errors := v_errors || 'pricing_config: 0 rows'; end if;
    if v_rcr > 0 and exists (
         select 1 from public.rate_card_rules r
          where r.org_id = v_org_id
            and (r.base_amount <> 0 or r.per_km_rate <> 0 or r.per_cft_rate <> 0 or r.min_charge <> 0)
       ) then
      v_errors := v_errors || 'rate_card_rules: a seeded row has a non-zero money column';
    end if;
    if v_pc > 0 and exists (
         select 1 from public.pricing_config pc
          where pc.org_id = v_org_id
            and (
              (pc.config #>> '{porter_rates,local}')::numeric <> 0
              or (pc.config #>> '{porter_rates,outstation}')::numeric <> 0
              or (pc.config #>> '{gst,default_pct}')::numeric <> 0
            )
       ) then
      v_errors := v_errors || 'pricing_config: a seeded money value is non-zero';
    end if;

    if array_length(v_errors, 1) is not null then
      raise exception 'ASSERT_FAIL: %', array_to_string(v_errors, '; ');
    end if;

    raise exception 'PROBE_OK';
  exception when others then
    if sqlerrm = 'PROBE_OK' then
      raise notice 'seed_org_postflight OK: create_org_with_owner produced a complete org (number_series=%, document_settings=%, default_branch=%, lr_series=%, cft_catalogue=%, rate_card_rules=%, rate_cards=%, pricing_config=%, all money columns zero); probe org rolled back.',
        v_ns, v_ds, v_br, v_lr, v_cft, v_rcr, v_rc, v_pc;
    elsif sqlerrm like 'ASSERT_FAIL:%' then
      raise exception 'seed_org_postflight FAILED -- a new org from create_org_with_owner is incomplete: %', sqlerrm;
    else
      raise exception 'seed_org_postflight: unexpected error while probing create_org_with_owner: % (%)', sqlerrm, sqlstate;
    end if;
  end;
end $$;
