-- ============================================================================
-- 20260731_org_members_role_check.sql
--
-- Separate from 20260731_create_org_with_owner.sql on purpose - this
-- constrains EXISTING data and behaviour app-wide, not just the new
-- function. Reviewable and runnable independently.
--
-- THE GAP: org_members.role is plain text with no CHECK constraint.
-- Nothing in the database restricts its values or its casing. The new
-- caller_role gate in create_org_with_owner() (and whatever step 3's
-- client code does with it) is an exact-string comparison against
-- 'owner' - a row holding 'Owner' or 'OWNER' would fail that gate and
-- bounce a real owner to staff login. Read-side normalisation (lower() in
-- create_org_with_owner's SELECT, and again defensively in the Edge
-- Function) covers every CURRENT read path, but a constraint is the only
-- thing that stops a bad value being WRITTEN in the first place - by this
-- function, by a future admin tool, or by hand in the Supabase dashboard.
--
-- ALLOWED VALUES - grepped, not assumed:
--   'owner'   - the only value ANY Dart file or SQL migration in this repo
--               currently writes or compares for org_members.role.
--   'manager' - writes nowhere in code today, but nagarva_auth_plan_REVISED.md
--               names it explicitly as a real near-term role for this exact
--               table ("Manager | Email + password, then device-bound PIN"
--               - the auth plan's own role table puts Manager on the same
--               email/password + org_members track as Owner, distinct from
--               PIN-only staff). Included now so implementing it later is
--               an app-code change, not an app-code change PLUS a schema
--               migration to widen a constraint that blocked it.
--
-- If you'd rather be strict and only allow what's live today, drop
-- 'manager' from the CHECK below and add it back in its own migration
-- when that feature actually gets built. Either is defensible; I picked
-- the version that doesn't need a follow-up migration for a role the auth
-- plan already committed to in writing.
--
-- CASING: the constraint requires role = lower(role) AS WELL AS
-- role in (...) - not just a case-insensitive check. A constraint that
-- only verified lower(role) IN (...) would still let 'Owner' be stored
-- (it passes case-insensitively) and quietly put the casing bug right
-- back - every future reader would still need to remember to lower().
-- Requiring the STORED value to already be canonical lowercase closes
-- that permanently: after this runs, org_members.role literally cannot
-- hold anything but 'owner' or 'manager', in exactly that casing, ever
-- again - not "every reader happens to normalise", a guarantee.
--
-- ---------------------------------------------------------------------------
-- RUN THIS QUERY FIRST. If it returns anything other than 'owner' (or
-- 'owner' rows with unexpected casing), the ALTER below will fail with a
-- constraint violation naming the offending row, and that row needs
-- fixing (almost certainly just a casing typo - `update org_members set
-- role = lower(role) where role <> lower(role)` - or, if it's a value
-- outside owner/manager entirely, a decision about what it should be)
-- before this migration can run.
--
--   select role, count(*) from public.org_members group by role order by 2 desc;
--
-- ---------------------------------------------------------------------------

begin;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'org_members_role_check'
  ) then
    alter table public.org_members
      add constraint org_members_role_check
      check (role = lower(role) and role in ('owner', 'manager'));
  end if;
end $$;

commit;

-- Verify after running:
--   select conname, pg_get_constraintdef(oid)
--     from pg_constraint
--    where conrelid = 'public.org_members'::regclass
--      and conname = 'org_members_role_check';
--
--   -- confirm it actually rejects bad casing:
--   -- insert into org_members (org_id, user_id, role)
--   --   values ('<any real org_id>', gen_random_uuid(), 'Owner');
--   -- expect: ERROR - new row for relation "org_members" violates check
--   -- constraint "org_members_role_check". Then delete nothing - the
--   -- insert never committed.
