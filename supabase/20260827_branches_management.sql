-- =====================================================================
-- 20260827_branches_management.sql
--
-- Unblocks fresh-tenant onboarding. Today a new org is created with ZERO
-- branches, and New Order / New Lead / the staff form all require at
-- least one active branch row -- so a tenant can sign up, pay, and be
-- unable to create a single order. Ponci Packers And Movers is in that
-- state right now (0 branches, 0 staff, 0 orders).
--
-- Four changes, one subject:
--   1. seed_org_default_branch() + call it from create_org_with_owner()
--   2. Backfill every existing org that has no branch
--   3. branches: split org_isolation FOR ALL into org-scoped SELECT and
--      OWNER-ONLY writes
--   4. number_series.prefix CHECK (NOT VALID -- see section 5 for why)
--
-- Written by a read-only session. NOT RUN. Arun runs it.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- PREFLIGHT
-- ---------------------------------------------------------------------
do $preflight$
begin
  if to_regclass('public.branches') is null then
    raise exception 'PREFLIGHT: public.branches does not exist. Run 20260825_branches_table.sql first.';
  end if;
  if to_regprocedure('public.create_org_with_owner(uuid,text,text,text,text)') is null then
    raise exception 'PREFLIGHT: create_org_with_owner(uuid,text,text,text,text) not found - signature may have changed. Re-read it before running this.';
  end if;
  if to_regprocedure('public.is_org_owner(uuid)') is null then
    raise exception 'PREFLIGHT: is_org_owner(uuid) not found.';
  end if;
  if to_regprocedure('public.seed_org_number_series(uuid)') is null then
    raise exception 'PREFLIGHT: seed_org_number_series(uuid) not found.';
  end if;
end
$preflight$;

-- ---------------------------------------------------------------------
-- 1. Default branch seeding
--
-- Name is 'Head Office' -- deliberately neutral. It is NOT printed on
-- any customer document today: every active number_series row has
-- branch = NULL, so numbering never reads it. It is a filter and
-- assignment label the owner renames in Settings > Branches.
--
-- Guarded on "org has no branch at all" rather than ON CONFLICT, so an
-- org that already has real branches cannot gain a stray one.
-- ---------------------------------------------------------------------
create or replace function public.seed_org_default_branch(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $seed_branch$
begin
  if p_org_id is null then
    raise exception 'p_org_id is required' using errcode = '22004';
  end if;

  insert into public.branches (org_id, name, active)
  select p_org_id, 'Head Office', true
  where not exists (
    select 1 from public.branches b where b.org_id = p_org_id
  );
end;
$seed_branch$;

-- ---------------------------------------------------------------------
-- 2. create_org_with_owner() -- add the seed call
--
-- CREATE OR REPLACE is safe here: the RETURNS TABLE signature is
-- UNCHANGED. (Changing a return type would need DROP first -- see
-- CLAUDE.md's 42P13 convention.) The only edit is the single `perform`
-- line marked ADDED below, alongside the two seeds already present.
-- Body otherwise reproduced verbatim from pg_get_functiondef().
-- ---------------------------------------------------------------------
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
as $create_org$
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
      -- trial_days comes from the plan row.
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
  -- ADDED 27 Aug 2026: without a branch the org cannot create an order,
  -- a lead, or a staff member. See this migration's header.
  perform public.seed_org_default_branch(v_org.id);

  return query
  select true, v_org.id, v_org.name, v_org.slug, v_org.plan_id, v_plan.name,
         v_org.plan_status, coalesce(v_plan.limits, '{}'::jsonb),
         coalesce(v_plan.features, '{}'::jsonb), v_org.trial_ends_at,
         v_org.active, 'owner'::text;
end;
$create_org$;

-- ---------------------------------------------------------------------
-- 3. Backfill -- every org with no branch gets one
-- ---------------------------------------------------------------------
do $backfill$
declare
  r record;
  n int := 0;
begin
  for r in select id, name from public.organizations loop
    if not exists (select 1 from public.branches b where b.org_id = r.id) then
      perform public.seed_org_default_branch(r.id);
      n := n + 1;
      raise notice 'Seeded default branch for org: %', r.name;
    end if;
  end loop;
  raise notice 'Backfill complete: % org(s) seeded.', n;
end
$backfill$;

-- ---------------------------------------------------------------------
-- 4. branches RLS -- org-scoped reads, OWNER-ONLY writes
--
-- Before this, branches carried a single org_isolation policy FOR ALL,
-- so ANY org member -- a driver on a PIN session included -- could
-- create, rename or delete a branch. Branch structure defines the
-- boundary every branch_isolation policy enforces, so reshaping it is an
-- owner concern: the same category as business settings and staff
-- editing, both already owner-only.
--
-- SELECT stays org-scoped. All five consuming screens (New Order, New
-- Lead, staff form, P&L, Reports) read branches under a staff session
-- and would fail closed otherwise.
--
-- is_org_owner() checks org_members.role = 'owner'. Verified live before
-- writing this: 2 owner rows, 4 staff rows -- staff shadow auth users
-- carry role 'staff', so this separates them cleanly.
-- ---------------------------------------------------------------------
drop policy if exists org_isolation on public.branches;
drop policy if exists branches_select on public.branches;
drop policy if exists branches_insert on public.branches;
drop policy if exists branches_update on public.branches;
drop policy if exists branches_delete on public.branches;

create policy branches_select on public.branches
  for select using (
    org_id in (select public.current_org_ids()) or public.is_platform_admin()
  );

create policy branches_insert on public.branches
  for insert with check (
    public.is_org_owner(org_id) or public.is_platform_admin()
  );

create policy branches_update on public.branches
  for update using (
    public.is_org_owner(org_id) or public.is_platform_admin()
  ) with check (
    public.is_org_owner(org_id) or public.is_platform_admin()
  );

create policy branches_delete on public.branches
  for delete using (
    public.is_org_owner(org_id) or public.is_platform_admin()
  );

-- ---------------------------------------------------------------------
-- 5. number_series.prefix validation  (status doc section 9.2)
--
-- next_doc_number does coalesce(prefix,''), so NULL and '' are both
-- silently valid -- which is exactly how the bare-0001 invoices were
-- produced. Rule 46(b) caps a full invoice number at 16 characters, so
-- 10 is a deliberate ceiling once padding (4) and any suffix count
-- against it.
--
-- NOT VALID IS DELIBERATE AND MUST STAY. Five rows on APC carry
-- prefix = '' (fy '2627', active = false). They are the historical
-- record that 6 receipts, 2 invoices and 1 proforma were issued on bare
-- numbers, and resolving them is a CA question, NOT cleanup. A
-- validating constraint would refuse to apply until those rows were
-- altered or deleted -- i.e. it would force destroying the evidence in
-- order to add the guard. NOT VALID enforces on every INSERT and UPDATE
-- from now on and leaves history untouched.
--
-- Do NOT run ALTER TABLE ... VALIDATE CONSTRAINT without first resolving
-- those five rows with the CA.
-- ---------------------------------------------------------------------
alter table public.number_series
  drop constraint if exists number_series_prefix_format;

alter table public.number_series
  add constraint number_series_prefix_format
  check (prefix is not null and prefix ~ '^[A-Za-z0-9/-]{1,10}$')
  not valid;

-- ---------------------------------------------------------------------
-- POSTFLIGHT -- abort and roll back if anything is missing
-- ---------------------------------------------------------------------
do $postflight$
declare
  v_missing int;
  v_orgs_without int;
begin
  if to_regprocedure('public.seed_org_default_branch(uuid)') is null then
    raise exception 'POSTFLIGHT: seed_org_default_branch was not created.';
  end if;

  select count(*) into v_orgs_without
    from public.organizations o
   where not exists (select 1 from public.branches b where b.org_id = o.id);
  if v_orgs_without > 0 then
    raise exception 'POSTFLIGHT: % org(s) still have no branch.', v_orgs_without;
  end if;

  select count(*) into v_missing
    from (values ('branches_select'), ('branches_insert'),
                 ('branches_update'), ('branches_delete')) as want(p)
   where not exists (
     select 1 from pg_policy pol
      where pol.polrelid = 'public.branches'::regclass
        and pol.polname = want.p);
  if v_missing > 0 then
    raise exception 'POSTFLIGHT: % branches policy/policies missing.', v_missing;
  end if;

  if exists (select 1 from pg_policy
              where polrelid = 'public.branches'::regclass
                and polname = 'org_isolation') then
    raise exception 'POSTFLIGHT: old org_isolation policy still present on branches.';
  end if;

  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.number_series'::regclass
                    and conname = 'number_series_prefix_format') then
    raise exception 'POSTFLIGHT: number_series_prefix_format constraint missing.';
  end if;

  raise notice 'POSTFLIGHT OK.';
end
$postflight$;

commit;
