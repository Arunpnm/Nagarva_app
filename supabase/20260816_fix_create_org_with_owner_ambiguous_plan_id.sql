-- Fix create_org_with_owner(): "column reference plan_id is ambiguous"
-- on EVERY new-org signup. Confirmed in Supabase function logs.
--
-- ROOT CAUSE: the function's RETURNS TABLE declares OUT parameters named
-- plan_id, plan_status and trial_ends_at (20260812_owner_name_persistence.sql).
-- plpgsql treats OUT parameters as variables in scope for the entire
-- function body. The new-org INSERT's `returning ... into v_org` clause
-- (added in an earlier pass, unchanged by the owner-name migration)
-- referenced plan_id/plan_status/trial_ends_at UNQUALIFIED — each one is
-- ambiguous between the OUT-param variable and the organizations column
-- of the same name, and Postgres can't resolve it. id/name/slug/active
-- happen to be safe (no OUT param shares those exact names) but are
-- qualified too here anyway, for the same reason the fix below qualifies
-- everything rather than cherry-picking just the three broken ones — if
-- an OUT param is ever renamed to collide with one of these later, this
-- statement doesn't quietly break again.
--
-- NOT using `#variable_conflict use_column`: it would change name
-- resolution for org_id/plan_status/trial_ends_at (and any future OUT
-- param that happens to collide with a column) across the WHOLE function
-- body, not just this one statement — wider blast radius than this bug,
-- and it would silently make a real future ambiguity (e.g. a variable
-- that SHOULD win) resolve to the column instead with no error at all.
-- Explicit table-qualification of exactly the one broken statement is
-- the narrow fix.
--
-- SECOND BUG, FOUND BY ACTUALLY VERIFYING, NOT BY THE STATIC SCAN BELOW:
-- the static read of `insert into pricing_config (org_id, config) ...
-- on conflict (org_id) do nothing` judged the ON CONFLICT target list
-- safe on the theory that it's a grammatically-required table-column
-- position, same as an INSERT target-column-list. That theory was WRONG
-- — a live call against the first version of this migration threw the
-- identical error one level down: `column reference "org_id" is
-- ambiguous ... QUERY: insert into public.pricing_config (org_id,
-- config) ... on conflict (org_id) do nothing`. Unlike an INSERT
-- target-column-list, plpgsql's ON CONFLICT target list DOES get
-- resolved against the function's own variable namespace (org_id is an
-- OUT param here too), and — unlike the RETURNING fix above — a
-- table-qualified name (`pricing_config.org_id`) is not valid syntax
-- inside `ON CONFLICT (...)` at all, so the same qualification trick
-- doesn't apply here. Fixed by dropping the explicit conflict target
-- entirely: `on conflict do nothing` (no column list) needs no
-- identifier resolution, so there's nothing for it to be ambiguous
-- about. Confirmed safe to broaden like this — pricing_config has
-- exactly two constraints (checked live): a UNIQUE on org_id (the one
-- this clause is actually for) and a PRIMARY KEY on id, which isn't in
-- this INSERT's column list at all (so it takes its default and a
-- collision is a random-UUID coincidence, not a real case) — no other
-- constraint exists that a bare DO NOTHING could wrongly swallow.
--
-- SCANNED THE REST OF THE FUNCTION BODY for the same class of bug
-- against all 12 OUT param names (is_new, org_id, org_name, org_slug,
-- plan_id, plan_name, plan_status, plan_limits, plan_features,
-- trial_ends_at, org_active, caller_role), and — given the ON CONFLICT
-- miss above — VERIFIED the whole function end to end afterward rather
-- than trusting this read alone:
--   - The idempotent branch's RETURN QUERY (existing org_members row)
--     already qualifies everything with o./sp./v_existing. — confirmed
--     safe, matches what was already known.
--   - The final RETURN QUERY (new-org success path) qualifies everything
--     with v_org./v_plan. — record-field access is never ambiguous with
--     an OUT param of the same base name (v_org.plan_id is a different
--     syntactic form from a bare plan_id), confirmed safe.
--   - insert into org_members (org_id, user_id, role) — org_id appears
--     only in the INSERT target-column-list, which (unlike ON CONFLICT)
--     genuinely is unambiguous by grammar — this one really is safe, now
--     confirmed by the end-to-end live run below succeeding past it.
--   - Every other unqualified reference (v_base_slug, v_slug, p_org_name,
--     p_user_id, sp.* in the plan lookup) has no OUT-param name
--     collision at all.
--
-- RETURN TYPE UNCHANGED — CREATE OR REPLACE is correct, no DROP FUNCTION
-- needed. This is a body-only change; the signature (uuid, text, text,
-- text, text) -> the same 12-column table is identical to what
-- 20260812_owner_name_persistence.sql already left live.

begin;

create or replace function public.create_org_with_owner(
  p_user_id uuid,
  p_org_name text,
  p_phone text default null,
  p_gstin text default null,
  p_owner_name text default null
)
returns table (
  is_new boolean,
  org_id uuid,
  org_name text,
  org_slug text,
  plan_id uuid,
  plan_name text,
  plan_status text,
  plan_limits jsonb,
  plan_features jsonb,
  trial_ends_at timestamptz,
  org_active boolean,
  caller_role text
)
language plpgsql
security definer
set search_path = public, extensions
as $$
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

  -- ---- Idempotency check: does this identity already belong to an org? ----
  -- Unchanged — including on the idempotent path, p_owner_name is
  -- deliberately NOT written to an existing org here.
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

  -- ---- Slug generation with a bounded retry on collision. ---- (unchanged)
  v_base_slug := trim(both '-' from
                   regexp_replace(lower(p_org_name), '[^a-z0-9]+', '-', 'g'));
  if v_base_slug = '' then
    v_base_slug := 'org';
  end if;
  v_slug := v_base_slug;

  loop
    v_attempt := v_attempt + 1;
    begin
      select sp.id, sp.name, sp.limits, sp.features
        into v_plan
        from public.subscription_plans sp
       where sp.is_default_trial = true
       order by sp.id
       limit 1;
      if not found then
        raise exception 'No default trial plan configured (subscription_plans.is_default_trial)'
          using errcode = 'P0001';
      end if;

      -- THE FIX: every RETURNING column explicitly table-qualified.
      -- plan_id/plan_status/trial_ends_at were unqualified before and
      -- collided with this function's own OUT parameters of the same
      -- name — that's the "column reference plan_id is ambiguous" error.
      insert into public.organizations
        (name, slug, phone, gstin, signatory_name, plan_id, plan_status, trial_ends_at, active)
      values
        (trim(p_org_name), v_slug,
         nullif(trim(coalesce(p_phone, '')), ''),
         nullif(trim(coalesce(p_gstin, '')), ''),
         nullif(trim(coalesce(p_owner_name, '')), ''),
         v_plan.id, 'trial', now() + interval '7 days', true)
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

  return query
  select true, v_org.id, v_org.name, v_org.slug, v_org.plan_id, v_plan.name,
         v_org.plan_status, coalesce(v_plan.limits, '{}'::jsonb),
         coalesce(v_plan.features, '{}'::jsonb), v_org.trial_ends_at,
         v_org.active, 'owner'::text;
end;
$$;

revoke all on function public.create_org_with_owner(uuid, text, text, text, text) from public;
revoke all on function public.create_org_with_owner(uuid, text, text, text, text) from anon;
revoke all on function public.create_org_with_owner(uuid, text, text, text, text) from authenticated;
grant execute on function public.create_org_with_owner(uuid, text, text, text, text) to service_role;

commit;
