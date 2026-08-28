-- =====================================================================
-- 28 Aug 2026 — org creation bootstrap: LR series + own trial window
--
-- Two defects, both found by creating a sandbox org and looking at what
-- a real vendor actually gets.
--
-- 1. lr_series is NEVER seeded. create_org_with_owner() calls
--    seed_org_number_series / seed_org_document_settings /
--    seed_org_default_branch, and nothing seeds lr_series. So
--    next_lr_number() — which reads lr_series and ONLY lr_series —
--    raises P0001 on the first consignment note for every org ever
--    created. Confirmed live: 0 rows in lr_series for every org.
--
--    The trap that hid it: seed_org_number_series DOES insert an 'lr'
--    row into number_series (prefix 'LR'). That row is the migration-007
--    MIRROR, kept so a future consolidation of the two tables is a
--    no-op. No allocator reads it. So the counter looks configured, in
--    the table you would naturally check, and is unreachable.
--
-- 2. An additional org inherits the parent's trial_ends_at VERBATIM.
--    Cosmetic today (a sandbox lost 17 minutes); a live hazard later —
--    an org created after the parent's trial lapses is born ALREADY
--    EXPIRED, and Item 32b's enforce_org_writable() then blocks every
--    insert on it. The vendor creates a company they cannot use, with
--    no error explaining why.
--
-- AUDITED BEFORE WRITING THIS: only one org carried an inherited
-- trial_ends_at (the sandbox being deleted). APC's is correct at
-- exactly 30 days from creation. **No backfill of organizations is
-- included, deliberately** — there is nothing to fix.
--
-- Return type of create_org_with_owner is UNCHANGED, so CREATE OR
-- REPLACE is safe here and no DROP is needed. If a later edit changes
-- the return TABLE(...), add an explicit DROP FUNCTION first — see
-- CLAUDE.md on 42P13.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- PREFLIGHT
-- ---------------------------------------------------------------------
do $$
begin
  if to_regclass('public.lr_series') is null then
    raise exception 'PREFLIGHT: lr_series does not exist';
  end if;
  if to_regprocedure('public.current_fy_ist()') is null then
    raise exception 'PREFLIGHT: current_fy_ist() does not exist';
  end if;
  if to_regprocedure('public.create_org_with_owner(uuid,text,text,text,text,text)') is null then
    raise exception 'PREFLIGHT: create_org_with_owner(6 args) does not exist';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. seed_org_lr_series — mirrors seed_org_number_series' shape
--
-- branch = null: one org-wide series per FY, per the 12 Aug 2026
-- numbering decision. Every next_lr_number() call site passes
-- p_branch => null, and the function matches on
-- coalesce(branch,'') = coalesce(p_branch,''), so a branch-scoped row
-- would match nobody.
--
-- prefix 'LR': next_lr_number returns
--   coalesce(prefix,'LR') || lpad(n::text, 4, '0')
-- with NO separator, so this yields LR0001. Deliberately NOT the
-- calendar '2026/' style the money documents use — that would render an
-- LR indistinguishable from an invoice.
-- ---------------------------------------------------------------------
create or replace function public.seed_org_lr_series(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_fy text := public.current_fy_ist();
begin
  insert into public.lr_series (org_id, branch, fy, prefix, last_number, active)
  values (p_org_id, null, v_fy, 'LR', 0, true)
  on conflict (org_id, coalesce(branch, ''), fy) do nothing;
end;
$function$;

-- ---------------------------------------------------------------------
-- 2. Backfill EXISTING orgs. Without this, every org created before
--    today stays unable to issue an LR.
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select id from public.organizations loop
    perform public.seed_org_lr_series(r.id);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 3. Mark the number_series 'lr' row as the dead mirror it is, so the
--    next person to check "is LR numbering configured?" does not get
--    the same false yes. Comment only — the row is left in place for
--    the eventual consolidation.
-- ---------------------------------------------------------------------
comment on table public.lr_series is
  'THE allocator source for next_lr_number(). Seeded by '
  'seed_org_lr_series() at org creation. NOTE: number_series also holds '
  'a doc_type=''lr'' row per org — that is a DEAD MIRROR kept by '
  'migration 007 for a future consolidation, and no allocator reads it. '
  'Change LR numbering HERE, not there.';

-- ---------------------------------------------------------------------
-- 4. create_org_with_owner — two changes only:
--      (a) seeds lr_series alongside the other three seeders
--      (b) an additional org computes its OWN trial window
--    Everything else is byte-for-byte the live definition.
-- ---------------------------------------------------------------------
create or replace function public.create_org_with_owner(
  p_user_id uuid,
  p_org_name text,
  p_phone text default null::text,
  p_gstin text default null::text,
  p_owner_name text default null::text,
  p_intent text default 'recover'::text
)
returns table(is_new boolean, org_id uuid, org_name text, org_slug text,
              plan_id uuid, plan_name text, plan_status text,
              plan_limits jsonb, plan_features jsonb,
              trial_ends_at timestamp with time zone,
              org_active boolean, caller_role text)
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

  insert into public.pricing_config (org_id, config)
  values (v_org.id, public.default_pricing_config())
  on conflict do nothing;

  perform public.seed_org_number_series(v_org.id);
  perform public.seed_org_document_settings(v_org.id);
  -- ADDED 27 Aug 2026 by 20260827_branches_management.sql: without a
  -- branch the org cannot create an order, a lead, or a staff member.
  perform public.seed_org_default_branch(v_org.id);
  -- ADDED 28 Aug 2026: without this next_lr_number() raises P0001 on
  -- the first consignment note. The number_series 'lr' row seeded above
  -- is a dead mirror and does NOT cover this.
  perform public.seed_org_lr_series(v_org.id);

  return query
  select true, v_org.id, v_org.name, v_org.slug, v_org.plan_id, v_plan_name,
         v_org.plan_status, v_limits, v_features, v_org.trial_ends_at,
         v_org.active, 'owner'::text;
end;
$function$;

-- ---------------------------------------------------------------------
-- POSTFLIGHT — abort and roll back if the fix did not land.
-- ---------------------------------------------------------------------
do $$
declare v_missing int;
begin
  if to_regprocedure('public.seed_org_lr_series(uuid)') is null then
    raise exception 'POSTFLIGHT: seed_org_lr_series was not created';
  end if;

  select count(*) into v_missing
    from public.organizations o
   where not exists (select 1 from public.lr_series l where l.org_id = o.id);
  if v_missing > 0 then
    raise exception 'POSTFLIGHT: % org(s) still have no lr_series row', v_missing;
  end if;

  if not exists (
    select 1 from pg_proc
     where proname = 'create_org_with_owner'
       and pg_get_functiondef(oid) like '%seed_org_lr_series%'
  ) then
    raise exception 'POSTFLIGHT: create_org_with_owner does not call seed_org_lr_series';
  end if;
end $$;

commit;

-- =====================================================================
-- VERIFY AFTER RUNNING (expect one lr_series row per org, all at 0):
--
--   select o.slug, l.prefix, l.fy, l.branch, l.last_number, l.active
--     from organizations o
--     left join lr_series l on l.org_id = o.id
--    order by o.created_at;
-- =====================================================================
