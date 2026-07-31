-- ============================================================================
-- introspect_before_create_org.sql — READ-ONLY. Nothing here writes.
--
-- Blocks create-org until this comes back. The generated Dart mirror has
-- been wrong before (branch_kpis_view and trips_view column lists, both
-- caught only because they were diffed against the original SQL before
-- running) and registration is the wrong place to find out it's wrong
-- again — a bad INSERT here doesn't just mis-render a screen, it can
-- create a broken tenant or double-charge a signup on retry.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- PART A — organizations: exact columns, defaults, constraints
-- ---------------------------------------------------------------------------

select column_name, data_type, is_nullable, column_default
  from information_schema.columns
 where table_schema = 'public' and table_name = 'organizations'
 order by ordinal_position;

-- Constraints — specifically whether `slug` is actually UNIQUE. create-org
-- generates a slug from the business name; if two vendors pick similar
-- names and there's no constraint, nothing stops a silent collision.
select conname, contype, pg_get_constraintdef(oid) as definition
  from pg_constraint
 where conrelid = 'public.organizations'::regclass
 order by contype, conname;

-- Row shape sanity — is there already broken test data from the existing
-- client-side signup path? CLAUDE.md's changelog records at least one org
-- created with plan_id NULL. create-org needs to know if that pattern is
-- still out there.
select id, name, slug, plan_id, plan_status, trial_ends_at, active,
       created_at
  from public.organizations
 order by created_at desc
 limit 20;

select count(*) as total_orgs,
       count(*) filter (where plan_id is null)      as null_plan_id,
       count(*) filter (where trial_ends_at is null) as null_trial_end,
       count(*) filter (where slug is null)          as null_slug,
       count(distinct slug)                          as distinct_slugs,
       count(*)                                      as all_rows
  from public.organizations;
-- distinct_slugs should equal all_rows (minus any null_slug rows). If not,
-- slugs are already colliding and the generator needs a fix before this
-- goes self-serve.


-- ---------------------------------------------------------------------------
-- PART B — org_members: exact columns, and the idempotency key
-- ---------------------------------------------------------------------------

select column_name, data_type, is_nullable, column_default
  from information_schema.columns
 where table_schema = 'public' and table_name = 'org_members'
 order by ordinal_position;

-- The brief's idempotency rule is "key off user_id: if an org_members row
-- already exists for that user, return the existing org". That only works
-- safely if user_id can't appear twice with different roles/orgs in a way
-- that makes "the" existing org ambiguous. Confirms whether a uniqueness
-- constraint already enforces one membership per user, or whether
-- create-org has to defensively pick (e.g. oldest row, owner role first).
select conname, contype, pg_get_constraintdef(oid) as definition
  from pg_constraint
 where conrelid = 'public.org_members'::regclass
 order by contype, conname;

-- What roles actually exist right now (asked before, re-checking in this
-- context because create-org hardcodes 'owner' — confirms that spelling
-- matches what verify_org_pin() and the RLS policies actually compare
-- against).
select role, count(*) from public.org_members group by role order by 2 desc;

-- Any user already a member of more than one org — tells create-org
-- whether "one membership per user" can be assumed or must be handled.
select user_id, count(*) as memberships
  from public.org_members
 group by user_id
having count(*) > 1;


-- ---------------------------------------------------------------------------
-- PART C — pricing_config: confirm the seed target
-- ---------------------------------------------------------------------------

select column_name, data_type, is_nullable, column_default
  from information_schema.columns
 where table_schema = 'public' and table_name = 'pricing_config'
 order by ordinal_position;

-- 20260728_pricing_config_survey_seed.sql added a unique constraint on
-- org_id so a cross-join seed could upsert one row per org. Confirms it's
-- actually there before create-org's insert relies on
-- ON CONFLICT (org_id) working.
select conname, contype, pg_get_constraintdef(oid) as definition
  from pg_constraint
 where conrelid = 'public.pricing_config'::regclass
 order by contype, conname;

-- Does every existing org already have a pricing_config row (the seed
-- migration should have back-filled this)? If any org is missing one,
-- that's either pre-seed-migration data or a gap create-org needs to
-- independently cover, not just assume "runs once at signup".
select o.id, o.name
  from public.organizations o
  left join public.pricing_config pc on pc.org_id = o.id
 where pc.id is null;


-- ---------------------------------------------------------------------------
-- PART D — subscription_plans: which one is "the trial plan"
-- ---------------------------------------------------------------------------

select id, code, name, is_default_trial, active, price_inr, billing_period
  from public.subscription_plans
 order by is_default_trial desc, id;
-- Expect exactly ONE row with is_default_trial = true. Zero means
-- create-org has nothing to stamp; more than one means "the" trial plan
-- is ambiguous and the existing signup_page_widget.dart client-side
-- insert (see PART E) may already be picking one arbitrarily.


-- ---------------------------------------------------------------------------
-- PART E — RLS on all four tables. THIS IS THE ONE THAT MATTERS MOST.
--
-- lib/signup_page/signup_page_widget.dart ALREADY inserts into
-- organizations and org_members directly from the client today — found
-- while writing this file, not something I was told to look for. The
-- brief's rule ("the org must not be created client-side... the client
-- cannot be trusted to set org_id or role") describes exactly what that
-- code does. Whether it's currently exploitable — i.e. whether anyone
-- with the anon key could insert an organizations/org_members row of
-- their choosing right now — depends entirely on RLS, and no migration
-- file in this repo defines a policy on either table. So its state is
-- unknown until this query runs, not assumed either way.
-- ---------------------------------------------------------------------------

select c.relname             as table_name,
       c.relrowsecurity      as rls_enabled,
       c.relforcerowsecurity as rls_forced,
       count(p.polname)      as policy_count,
       coalesce(string_agg(distinct p.polname || ':' ||
                 coalesce(array_to_string(
                   (select array_agg(r.rolname)
                      from unnest(p.polroles) pr(oid)
                      join pg_roles r on r.oid = pr.oid), ','), '(public)'),
                 '; '), '(no policies)') as policies
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  left join pg_policy p on p.polrelid = c.oid
 where n.nspname = 'public'
   and c.relname in ('organizations', 'org_members', 'pricing_config',
                     'subscription_plans')
 group by c.relname, c.relrowsecurity, c.relforcerowsecurity
 order by c.relname;
-- If organizations or org_members shows rls_enabled = false, or a policy
-- that admits 'authenticated' to INSERT with no check tying it to an
-- existing org — that is a live gap the current client-side signup code
-- can already walk through, independent of anything built for this
-- brief. Worth confirming even though registration is currently gated by
-- "Allow new users to sign up" = OFF, since that setting only blocks
-- NEW auth users, not what an already-authenticated one can insert.

-- Nothing in this file writes. No begin/commit needed.
