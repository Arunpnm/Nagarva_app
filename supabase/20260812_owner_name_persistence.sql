-- Owner name persistence (NG-BRIEF-vendor-auth-flow.md §3, follow-up).
-- Handed over for Arun to review and run — not executed from this session.
--
-- ============================================================================
-- DEPLOY ORDER — READ BEFORE DOING ANYTHING. This is a hard sequence, not
-- "same time or after," and reversing it is the actual break case:
--
--   1. Run THIS migration first.
--   2. THEN deploy the updated create-org Edge Function
--      (supabase/functions/create-org/index.ts, already edited in this
--      pass to send owner_name — see that file's own header comment).
--   3. THEN confirm: a real signup through the app, followed by
--        select signatory_name from organizations where slug = '<new org>';
--
-- Why this order and not the other way: the Edge Function change adds
-- `p_owner_name` to its RPC call. If that ships BEFORE this migration
-- runs, every signup calls create_org_with_owner(uuid, text, text, text,
-- text) against a live function that still only has the 4-argument
-- signature — Postgres has no matching overload, the RPC call fails
-- outright, and signup breaks completely for every vendor until the
-- migration catches up. This migration landing first, with the Edge
-- Function still on the old 4-argument call for however long the gap
-- is, is harmless: the old signature keeps working exactly as before
-- (owner_name just isn't captured yet). The dangerous direction is
-- Edge-Function-before-migration, not migration-before-Edge-Function.
-- ============================================================================
--
-- WHERE OWNER NAME LIVES: organizations.signatory_name, not a new column
-- on org_members. Reasoning:
--   - org_members has no name column at all today (confirmed live this
--     session: id, org_id, user_id, role, created_at, pin, pin_hash) —
--     using it would mean adding a column, where organizations.signatory_name
--     already exists and already has zero writers anywhere in the app
--     (flagged as deferred Settings UI work in an earlier session's
--     changelog entry — "Settings UI for the new organizations columns...
--     signatory_name... deliberately deferred"). This migration is the
--     first thing to ever populate it.
--   - create_org_with_owner() only ever creates ONE org_members row with
--     role='owner' per org, at creation time — no later flow adds a
--     second owner to an existing org (staff invites always write
--     role='staff'). So "the owner's name" is, in current practice, a
--     genuine 1:1 org-level attribute, matching organizations-table
--     storage rather than needing a per-membership-row home.
--   - signatory_name's own existing purpose (per the PDF/document work
--     that added the column) is "whoever's name appears as the
--     authorized signatory on invoices/documents" — for a business this
--     size, that's the same person as "the owner," so one column serves
--     both the dashboard-greeting use and the documents use the brief
--     asked for, rather than needing two.
--   - Known, accepted simplification: if a tenant ever delegates
--     document-signing to someone other than the owner, this conflates
--     two things that could diverge. Not a concern today (no such tenant,
--     no such UI), flagged here so it isn't rediscovered as a mystery
--     later.
--
-- NOT included in this migration: nothing reads signatory_name back into
-- AppSession or HomePage's dashboard greeting yet — that's client-side
-- wiring, not requested this pass, and there's no client change needed
-- for THIS migration to be safe to run (it only adds an optional,
-- default-null parameter and a column write; nothing existing changes
-- shape).
--
-- SIGNATURE CHANGE, NOT JUST A BODY CHANGE — DROP FIRST. Adding a new
-- parameter to a function's argument list is a different signature to
-- Postgres, the same way a different return type is (see this project's
-- own standing rule after the 42P16/42P13 incidents). `CREATE OR REPLACE
-- FUNCTION create_org_with_owner(uuid, text, text, text, text)` on its
-- own, without dropping the existing 4-argument version first, does NOT
-- replace it — Postgres function overloading means it would CREATE A
-- SECOND, PARALLEL function, leaving the old 4-argument one still live
-- and still callable. The explicit DROP below is load-bearing, not
-- defensive boilerplate.

begin;

drop function if exists public.create_org_with_owner(uuid, text, text, text);

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
  -- Unchanged from the original — including on the idempotent path,
  -- p_owner_name is deliberately NOT written to an existing org here. A
  -- retry of an already-completed signup, or a staff/manager account
  -- hitting this endpoint, must not silently overwrite an org's existing
  -- signatory_name (which by now may have been set or changed via
  -- Settings, once that UI exists).
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

      -- signatory_name added to the column/value list, same
      -- nullif(trim(coalesce(...)), '') pattern already used for
      -- phone/gstin — an empty/whitespace-only owner name stores as NULL,
      -- not an empty string.
      insert into public.organizations
        (name, slug, phone, gstin, signatory_name, plan_id, plan_status, trial_ends_at, active)
      values
        (trim(p_org_name), v_slug,
         nullif(trim(coalesce(p_phone, '')), ''),
         nullif(trim(coalesce(p_gstin, '')), ''),
         nullif(trim(coalesce(p_owner_name, '')), ''),
         v_plan.id, 'trial', now() + interval '7 days', true)
      returning id, name, slug, plan_id, plan_status, trial_ends_at, active
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
  on conflict (org_id) do nothing;

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

-- ============================================================================
-- Verify after running (step 1, before touching the Edge Function):
--
--   select proname, pg_get_function_identity_arguments(oid)
--     from pg_proc where proname = 'create_org_with_owner';
--   -- expect exactly ONE row, 5 arguments (uuid, text, text, text, text) —
--   -- if the old 4-argument overload is still listed too, the DROP above
--   -- didn't run or didn't match; do not proceed to the Edge Function
--   -- until this shows only the new signature.
--
--   select * from public.create_org_with_owner(
--     gen_random_uuid(), 'Test Movers Pvt Ltd', '9876543210', null, 'Test Owner');
--   -- expect success, same shape as before this migration (owner_name
--   -- isn't in the return table). Then:
--   select signatory_name from organizations where slug = '<the slug just returned>';
--   -- expect 'Test Owner'.
--
--   -- old-style 4-argument call must now fail (confirms the OLD Dart
--   -- build, if any is still out there, would fail loudly rather than
--   -- silently succeed without an owner name — acceptable, since step 2
--   -- of the deploy order means this is only ever hit by an old client
--   -- calling the RPC directly, not through create-org, which always
--   -- sends 5 args once redeployed):
--   -- select * from public.create_org_with_owner(gen_random_uuid(), 'X', null, null);
--   -- expect: function create_org_with_owner(uuid, unknown, unknown, unknown) does not exist
-- ============================================================================
