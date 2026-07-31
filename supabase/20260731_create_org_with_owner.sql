-- ============================================================================
-- 20260731_create_org_with_owner.sql
--
-- Registration brief, step 2. The SQL body behind the create-org Edge
-- Function.
--
-- COLUMN LIST PROVENANCE — READ BEFORE RUNNING.
-- Parts A-D of introspect_before_create_org.sql were never returned this
-- session — only Part E (RLS) came back, confirmed and closed separately.
-- The organizations/org_members column list below is NOT fresh
-- introspection. It is copied from CLAUDE.md's 13 Jul 2026 changelog
-- entry, itself a direct owner-confirmed field-by-field schema check from
-- that session ("The owner handed back the actual field-by-field live
-- schema... organizations(id, name, slug, gstin, phone, plan_id,
-- plan_status, trial_ends_at, active, created_at)"), and matches exactly
-- what lib/signup_page/signup_page_widget.dart inserts today (read
-- directly from the file this session, not memory) — that code was itself
-- written against that same owner-confirmed check.
--
-- Two independent sources agreeing is reassuring, not proof. Eighteen
-- days have passed. Before running this: either (a) run Parts A-B of
-- introspect_before_create_org.sql and confirm the column list still
-- matches, or (b) confirm from memory that nothing on organizations or
-- org_members has changed since 13 Jul. Either is fine — just don't run
-- this file on the assumption that this comment block is itself the
-- verification.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Helper: the APC default pricing_config payload, extracted verbatim from
-- 20260728_pricing_config_survey_seed.sql (copy-pasted from that file via
-- direct read, not retyped) so create_org_with_owner and the original seed
-- migration share ONE copy of an 8KB literal instead of two. A future
-- catalogue default change only needs to happen here.
--
-- 20260728's own cross-join seed can be re-pointed at this function in a
-- follow-up if you want full de-duplication; not done here to keep this
-- migration additive-only and not touch a file that already ran live.
-- ---------------------------------------------------------------------------
create or replace function public.default_pricing_config()
returns jsonb
language sql
immutable
as $$
  select '{
    "survey_cats": {
      "Bedrooms": [
        {"name":"Bed","subs":[{"label":"Single","cft":30},{"label":"Double","cft":45},{"label":"Queen Size","cft":55},{"label":"King Size","cft":65}]},
        {"name":"Mattress","subs":[{"label":"Single","cft":12},{"label":"Double","cft":15},{"label":"Queen","cft":18},{"label":"King","cft":20}]},
        {"name":"Wardrobe / Almirah","subs":[{"label":"2 Door","cft":40},{"label":"3 Door","cft":55},{"label":"4 Door","cft":70},{"label":"Sliding","cft":60}]},
        {"name":"Table","subs":[{"label":"Study Table","cft":15},{"label":"Dressing Table","cft":20},{"label":"Bedside Table","cft":8}]},
        {"name":"Chair","subs":[{"label":"1 Chair","cft":5},{"label":"2 Chairs","cft":10},{"label":"Recliner","cft":18}]},
        {"name":"Television","subs":[{"label":"Up to 32\"","cft":8},{"label":"32\"–50\"","cft":12},{"label":"50\"+ LED","cft":16}]},
        {"name":"Air Conditioner","subs":[{"label":"Window AC","cft":15},{"label":"Split AC 1T","cft":10},{"label":"Split AC 1.5T","cft":12},{"label":"Split AC 2T","cft":14}]},
        {"name":"Cabinet & Storage","subs":[{"label":"Small","cft":15},{"label":"Medium","cft":25},{"label":"Large","cft":35}]},
        {"name":"Other Appliances","subs":[{"label":"Item","cft":10}]}
      ],
      "Living Room": [
        {"name":"Sofa","subs":[{"label":"1 Seater","cft":15},{"label":"2 Seater","cft":25},{"label":"3 Seater","cft":35},{"label":"L-Shape","cft":60},{"label":"5 Seater","cft":70}]},
        {"name":"Dining Table","subs":[{"label":"2 Seater","cft":15},{"label":"4 Seater","cft":25},{"label":"6 Seater","cft":35},{"label":"8 Seater","cft":50}]},
        {"name":"Television","subs":[{"label":"Up to 32\"","cft":8},{"label":"32\"–50\"","cft":12},{"label":"50\"+ LED","cft":16}]},
        {"name":"Center Table","subs":[{"label":"Small","cft":8},{"label":"Medium","cft":12},{"label":"Large","cft":18}]},
        {"name":"Chair","subs":[{"label":"1","cft":5},{"label":"2","cft":10},{"label":"4","cft":20}]},
        {"name":"Air Conditioner","subs":[{"label":"Window AC","cft":15},{"label":"Split AC","cft":12}]},
        {"name":"Cabinet / TV Unit","subs":[{"label":"Small","cft":15},{"label":"Medium","cft":25},{"label":"Large","cft":35}]},
        {"name":"Bookshelf","subs":[{"label":"Small","cft":12},{"label":"Medium","cft":20},{"label":"Large","cft":30}]},
        {"name":"Appliances","subs":[{"label":"Item","cft":8}]},
        {"name":"Bar Furniture","subs":[{"label":"Bar Cabinet","cft":25},{"label":"Wine Rack","cft":15}]}
      ],
      "Kitchen": [
        {"name":"Refrigerator","subs":[{"label":"Single Door","cft":15},{"label":"Double Door","cft":20},{"label":"Triple Door","cft":28},{"label":"Side by Side","cft":35}]},
        {"name":"Utensils & Crockery","subs":[{"label":"1 Box","cft":6},{"label":"2 Boxes","cft":12},{"label":"3+ Boxes","cft":18}]},
        {"name":"Gas Stove / Chimney","subs":[{"label":"Gas Stove","cft":6},{"label":"Chimney","cft":10},{"label":"Both","cft":16}]},
        {"name":"Microwave","subs":[{"label":"Small","cft":6},{"label":"Large","cft":10}]},
        {"name":"Mixer / Grinder","subs":[{"label":"1","cft":4},{"label":"2+","cft":8}]},
        {"name":"Kitchen Appliances","subs":[{"label":"Item","cft":5}]},
        {"name":"Kitchen Furniture","subs":[{"label":"Cabinet","cft":20},{"label":"Island","cft":30},{"label":"Dining","cft":25}]}
      ],
      "Miscellaneous": [
        {"name":"Washing Machine","subs":[{"label":"Top Load","cft":15},{"label":"Front Load","cft":18}]},
        {"name":"Decorative Items","subs":[{"label":"Small","cft":5},{"label":"Medium","cft":10},{"label":"Large","cft":20}]},
        {"name":"Suitcases & Bags","subs":[{"label":"1–2","cft":8},{"label":"3–5","cft":16},{"label":"6+","cft":28}]},
        {"name":"Bicycle","subs":[{"label":"Kids","cft":12},{"label":"Adult","cft":18},{"label":"Electric","cft":22}]},
        {"name":"Bike / Two Wheeler","subs":[{"label":"Scooter","cft":25},{"label":"Standard Bike","cft":30},{"label":"Sports Bike","cft":35},{"label":"Electric Bike","cft":28}]},
        {"name":"Musical Instruments","subs":[{"label":"Item","cft":15}]},
        {"name":"Kids Vehicle","subs":[{"label":"Cycle","cft":12},{"label":"Scooter","cft":18},{"label":"Toy Car","cft":10}]},
        {"name":"Gym Equipment","subs":[{"label":"Treadmill","cft":40},{"label":"Weights Set","cft":20},{"label":"Exercise Bike","cft":25},{"label":"Others","cft":15}]},
        {"name":"Home Appliances","subs":[{"label":"Geyser","cft":8},{"label":"Fan","cft":6},{"label":"Iron","cft":3},{"label":"Vacuum Cleaner","cft":8}]},
        {"name":"Plants & Pots","subs":[{"label":"Small (<5)","cft":5},{"label":"Medium (5-10)","cft":12},{"label":"Large (10+)","cft":25}]}
      ],
      "Cartons & Packing": [
        {"name":"Self Carton Large","subs":[{"label":"Qty","cft":6}]},
        {"name":"Self Carton Medium","subs":[{"label":"Qty","cft":4}]},
        {"name":"Self Carton Small","subs":[{"label":"Qty","cft":3}]},
        {"name":"Gunny Bag","subs":[{"label":"Qty","cft":5}]}
      ]
    },
    "cft_ranges": [
      {"max":80,"pkg":"Micro Shifting"},
      {"max":155,"pkg":"1 RK / Studio"},
      {"max":180,"pkg":"1 BHK Small"},
      {"max":250,"pkg":"1 BHK Medium"},
      {"max":275,"pkg":"1 BHK Big"},
      {"max":400,"pkg":"2 BHK Small"},
      {"max":550,"pkg":"2 BHK Medium"},
      {"max":700,"pkg":"2 BHK Big"},
      {"max":900,"pkg":"3 BHK Small"},
      {"max":1050,"pkg":"3 BHK Medium"},
      {"max":1200,"pkg":"3 BHK Big"},
      {"max":1400,"pkg":"4 BHK Small"},
      {"max":1600,"pkg":"4 BHK Medium"},
      {"max":null,"pkg":"4 BHK Big"}
    ],
    "packages": [
      {"type":"Micro Shifting","crew":2,"vehicle":"7 Ft","vehicleCft":161},
      {"type":"1 RK / Studio","crew":2,"vehicle":"7 Ft","vehicleCft":161},
      {"type":"1 BHK Small","crew":3,"vehicle":"8 Ft","vehicleCft":184},
      {"type":"1 BHK Medium","crew":4,"vehicle":"10 Ft","vehicleCft":275},
      {"type":"1 BHK Big","crew":4,"vehicle":"10 Ft","vehicleCft":275},
      {"type":"2 BHK Small","crew":4,"vehicle":"14 Ft","vehicleCft":546},
      {"type":"2 BHK Medium","crew":5,"vehicle":"17 Ft","vehicleCft":714},
      {"type":"2 BHK Big","crew":5,"vehicle":"17 Ft","vehicleCft":714},
      {"type":"3 BHK Small","crew":6,"vehicle":"19 Ft","vehicleCft":931},
      {"type":"3 BHK Medium","crew":6,"vehicle":"19 Ft + 7 Ft","vehicleCft":1092},
      {"type":"3 BHK Big","crew":8,"vehicle":"19 Ft + 10 Ft","vehicleCft":1206},
      {"type":"4 BHK Small","crew":8,"vehicle":"19 Ft + 14 Ft","vehicleCft":1477},
      {"type":"4 BHK Medium","crew":10,"vehicle":"19 Ft + 17 Ft","vehicleCft":1645},
      {"type":"4 BHK Big","crew":10,"vehicle":"19 Ft + 19 Ft","vehicleCft":1862}
    ],
    "porter_rates": {"local":16,"outstation":19},
    "charge_defaults": {
      "billing_mode_keys": ["packing","unpacking","loading","unloading","materials"],
      "default_billing_mode": "included",
      "fields": [
        {"key":"transport","label":"Freight / Transport"},
        {"key":"packing","label":"Packing Charge","billable":true},
        {"key":"unpacking","label":"Un Packing Charge","billable":true},
        {"key":"loading","label":"Loading Charge","billable":true},
        {"key":"unloading","label":"Un Loading Charge","billable":true},
        {"key":"materials","label":"Packing Material Charge","billable":true},
        {"key":"storage","label":"Storage"},
        {"key":"carTransport","label":"Car Transport"},
        {"key":"misc","label":"Miscellaneous"},
        {"key":"stCharge","label":"S.T. Charge"},
        {"key":"otherCharges","label":"Other Charges"},
        {"key":"acUninstall","label":"AC Uninstall"},
        {"key":"acInstall","label":"AC Install"},
        {"key":"tvUninstall","label":"TV Uninstall"},
        {"key":"tvInstall","label":"TV Install"},
        {"key":"wardrobe","label":"Wardrobe Dismantle/Assemble"},
        {"key":"carpenter","label":"Carpenter Charges"},
        {"key":"electrician","label":"Electrician Charges"},
        {"key":"bikeTransport","label":"Bike Transport"},
        {"key":"discount","label":"Discount"},
        {"key":"advanceOnQuote","label":"Advance Paid"}
      ]
    },
    "gst": {"sac":"996719","default_pct":5,"rates":[0,5,12,18]}
  }'::jsonb;
$$;

-- ---------------------------------------------------------------------------
-- create_org_with_owner — the atomic write.
--
-- ATOMICITY: a single PL/pgSQL function body is one transaction from the
-- caller's perspective by construction — no explicit BEGIN/COMMIT needed
-- inside it. If any statement raises, every write in this invocation rolls
-- back, including the organizations insert. That is what makes it
-- impossible to produce an orphan org with zero members: either both rows
-- exist or neither does. Two separate supabase-js calls from the Edge
-- Function could never guarantee that; this can.
--
-- IDEMPOTENCY / CONFLICT BEHAVIOUR — decided, not left binary:
-- If p_user_id already has ANY org_members row (any role, any org), this
-- function does NOT create a second org and does NOT raise a conflict
-- error. It returns the org from that EXISTING membership (earliest
-- created_at if somehow more than one), with is_new = false.
--
-- Why not a hard 409: the brief's own idempotency requirement is "if the
-- vendor's connection drops after signUp() and they retry, the result
-- must be one org, not two" — that describes a SUCCESSFUL retry, not an
-- error condition. This function is only ever called once, immediately
-- after the caller obtains a fresh authenticated session (whether that
-- session came from signUp() returning one directly with email
-- confirmation off, or from clicking the verification link with it on —
-- both cases hand the client a valid JWT the moment the org doesn't exist
-- yet). The only realistic way this user_id already has a membership is a
-- retried request. Erroring on that would break exactly the flaky-network
-- scenario the brief calls out.
--
-- Why not "any role" -> only check owner rows: the brief's literal wording
-- is "if an org_members row already exists for that user" with no role
-- qualifier. Honoured as written — a person invited as staff/manager into
-- someone else's org who then hits the public signup screen with the same
-- email gets handed that existing membership's org, not a second one. If
-- multi-org ownership becomes a real feature later, it needs its own
-- authenticated "create another org" action reached from inside the app,
-- not this pre-org bootstrap endpoint.
--
-- CALLER_ROLE and the multi-membership determinism rule (added after
-- review): the idempotent-return path exposed a real gap — the client
-- needs to know WHAT role p_user_id holds in the org being returned,
-- because a staff/manager at Org A hitting the public signup screen must
-- NOT be handed a session there. is_new alone can't carry that: a
-- first-time signup is is_new=true/role=owner, a genuine retry of that
-- same signup is is_new=false/role=owner, and a staff member at someone
-- else's org is ALSO is_new=false — indistinguishable from a retry by
-- is_new alone. So this now also returns caller_role, and the client
-- (step 3, not yet built) must branch on caller_role = 'owner' as a
-- standalone check, not on any combination involving is_new.
--
-- If p_user_id somehow holds memberships in more than one org (invited
-- as staff somewhere, later becomes an owner elsewhere, or any other
-- path that isn't this function, since this function itself only ever
-- creates one membership per user), the pick is DETERMINISTIC: the
-- membership with the earliest org_members.created_at — i.e. the first
-- org this identity ever joined, by membership creation time, regardless
-- of role. Enforced by `order by created_at asc limit 1` below, not an
-- unordered `limit 1` — an unordered pick over a table with no default
-- ordering is not guaranteed stable across calls or Postgres versions,
-- which would mean the same user could get handed a different org (and
-- a different caller_role) on different requests. That nondeterminism is
-- itself a bug class worth naming, not just avoiding by accident.
-- ---------------------------------------------------------------------------

drop function if exists public.create_org_with_owner(uuid, text, text, text);

create or replace function public.create_org_with_owner(
  p_user_id uuid,
  p_org_name text,
  p_phone text default null,
  p_gstin text default null
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
  -- p_user_id's role in the returned org_id. 'owner' on every freshly
  -- created org (this function is the only writer of that first
  -- membership, and it always writes 'owner'). On the idempotent path,
  -- whatever org_members.role the picked existing membership actually
  -- holds — may or may not be 'owner'. The client must check this before
  -- treating the caller as the org's owner.
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
  -- Deterministic pick: earliest membership by created_at. See the
  -- CALLER_ROLE header note above for why this must be ordered, not an
  -- unordered `limit 1`.
  select om.org_id, om.role into v_existing
    from public.org_members om
   where om.user_id = p_user_id
   order by om.created_at asc
   limit 1;

  if found then
    return query
    select false, o.id, o.name, o.slug, o.plan_id, sp.name, o.plan_status,
           coalesce(sp.limits, '{}'::jsonb), coalesce(sp.features, '{}'::jsonb),
           o.trial_ends_at, o.active, v_existing.role
      from public.organizations o
      left join public.subscription_plans sp on sp.id = o.plan_id
     where o.id = v_existing.org_id;
    return;
  end if;

  -- ---- Slug generation with a bounded retry on collision. ----
  v_base_slug := trim(both '-' from
                   regexp_replace(lower(p_org_name), '[^a-z0-9]+', '-', 'g'));
  if v_base_slug = '' then
    v_base_slug := 'org';
  end if;
  v_slug := v_base_slug;

  loop
    v_attempt := v_attempt + 1;
    begin
      -- ---- The default trial plan. ----
      select sp.id, sp.name, sp.limits, sp.features
        into v_plan
        from public.subscription_plans sp
       where sp.is_default_trial = true
       order by sp.id
       limit 1;
      -- No plan row is a configuration problem, not a per-signup error —
      -- surfaced clearly rather than silently leaving plan_id null the way
      -- the client-side insert did before (see CLAUDE.md's "signup plan_id
      -- fix" entry — this is the same bug class, closed here at the source
      -- instead of relying on the client to sequence it correctly).
      if not found then
        raise exception 'No default trial plan configured (subscription_plans.is_default_trial)'
          using errcode = 'P0001';
      end if;

      insert into public.organizations
        (name, slug, phone, gstin, plan_id, plan_status, trial_ends_at, active)
      values
        (trim(p_org_name), v_slug,
         nullif(trim(coalesce(p_phone, '')), ''),
         nullif(trim(coalesce(p_gstin, '')), ''),
         v_plan.id, 'trial', now() + interval '7 days', true)
      returning id, name, slug, plan_id, plan_status, trial_ends_at, active
        into v_org;

      exit; -- insert succeeded, break the retry loop
    exception
      when unique_violation then
        if v_attempt >= 3 then
          raise exception 'Could not generate a unique slug for "%"', p_org_name
            using errcode = 'P0001';
        end if;
        -- Attempt 2: disambiguate with 4 chars of the user id (deterministic,
        -- so a genuine retry of the SAME signup lands on the same slug
        -- rather than burning a new one every time). Attempt 3: fall back
        -- to random, for the near-impossible case attempt 2 also collides.
        v_slug := case v_attempt
                    when 1 then v_base_slug || '-' || substr(replace(p_user_id::text, '-', ''), 1, 4)
                    else v_base_slug || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 4)
                  end;
    end;
  end loop;

  -- ---- Owner membership. Same function body, same transaction: if this
  -- fails, the organizations insert above rolls back too. ----
  insert into public.org_members (org_id, user_id, role)
  values (v_org.id, p_user_id, 'owner');

  -- ---- Seed pricing_config from the APC defaults. Not named in the
  -- "hard requirement" sentence about atomicity, but still happens inside
  -- the same function body, so it is still covered by the same rollback —
  -- a pricing_config failure undoes the org and membership too, rather
  -- than leaving a usable-looking org with no catalogue.
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

revoke all on function public.create_org_with_owner(uuid, text, text, text) from public;
revoke all on function public.create_org_with_owner(uuid, text, text, text) from anon;
revoke all on function public.create_org_with_owner(uuid, text, text, text) from authenticated;
grant execute on function public.create_org_with_owner(uuid, text, text, text) to service_role;

revoke all on function public.default_pricing_config() from public;
grant execute on function public.default_pricing_config() to service_role;

commit;

-- ============================================================================
-- Verify after running:
--
--   select proname, pg_get_function_identity_arguments(oid)
--     from pg_proc where proname in ('create_org_with_owner', 'default_pricing_config');
--
--   -- fresh org
--   select * from public.create_org_with_owner(
--     gen_random_uuid(), 'Test Movers Pvt Ltd', '9876543210', null);
--   -- expect is_new = true, caller_role = 'owner', a real slug, plan_name
--   -- populated, trial_ends_at ~7 days out. Then check the three rows
--   -- landed:
--   --   select * from organizations where slug = '<the slug just returned>';
--   --   select * from org_members where org_id = '<that id>';
--   --   select config->'cft_ranges' from pricing_config where org_id = '<that id>';
--
--   -- idempotency: call AGAIN with the SAME p_user_id used above
--   -- (grab it from org_members.user_id, not a new gen_random_uuid())
--   -- expect is_new = false, caller_role = 'owner', same org_id as the
--   -- first call, no new row in organizations.
--
--   -- caller_role for a non-owner: insert a scratch org_members row with
--   -- role = 'manager' for a throwaway user_id, then call the function
--   -- with that SAME p_user_id and any org_name. Expect is_new = false,
--   -- caller_role = 'manager', org_id = the org from that scratch row —
--   -- this is the exact case the client (step 3) must refuse to hand a
--   -- vendor session for.
--
--   -- rollback check: temporarily rename pricing_config.org_id to force
--   -- the last insert to fail, call the function, confirm NEITHER the
--   -- organizations nor org_members row was left behind. Rename the
--   -- column back afterwards. (Manual check, not scripted — deliberately
--   -- destructive to run against anything but a scratch org.)
-- ============================================================================
