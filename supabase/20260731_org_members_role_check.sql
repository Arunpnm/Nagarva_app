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
-- ---------------------------------------------------------------------------
-- ALLOWED VALUES - v2, after the first draft was caught by live data
-- before it shipped.
--
-- The first draft of this file allowed only ('owner', 'manager'), grepped
-- from Dart + SQL migrations only. `select role, count(*) from
-- org_members group by role` came back:
--     owner  3
--     staff  2
-- The ALTER would have failed outright on the 2 'staff' rows - or worse,
-- if run with a data-fixing UPDATE first, would have quietly broken
-- something that was never actually broken.
--
-- Re-grepped INCLUDING supabase/functions/**/*.ts (TypeScript, outside
-- the original search) and found the real source, by reading the running
-- code, not inferring it: BOTH pin-login/index.ts and staff-login/index.ts
-- insert `role: "staff"` into org_members, unconditionally, on a staff
-- member's FIRST-EVER PIN login (only when no org_members row for that
-- org+user already exists) - this is what anchors RLS's
-- current_org_ids() for a staff PIN session, exactly the same way an
-- owner's org_members row anchors theirs. It is not legacy data, not an
-- APC-era leftover, not dead code - it is the live bootstrap mechanism
-- for every staff PIN login going forward. The 2 existing 'staff' rows
-- are 2 staff members who have already logged in once.
--
-- Grepped for anything ELSE while in there (specifically checked for
-- 'supervisor', since that is a real value in the UNRELATED staff.role
-- column and the two are easy to confuse): nothing else writes or
-- compares a value for org_members.role anywhere in
-- supabase/functions/**/*.ts. staff-invite-redeem/index.ts's `role` hits
-- are staff.role (the field-crew column - supervisor/driver/helper/
-- packer/admin/manager per staff_form_sheet.dart's role list), a
-- different table, correctly not included here.
--
-- Final list:
--   'owner'   - written by create_org_with_owner() and (until step 3
--               retires it) signup_page_widget.dart; compared by
--               staff-deactivate and staff-invite for authorisation.
--   'staff'   - written by pin-login/index.ts and staff-login/index.ts
--               on a staff member's first PIN login. LIVE, ACTIVE, not
--               historical - excluding it breaks every future staff
--               login the moment their org_members row needs creating.
--   'manager' - writes nowhere in code today, but nagarva_auth_plan_REVISED.md
--               names it explicitly as a real near-term role for this
--               exact table (its role table puts Manager on the same
--               email/password + org_members track as Owner, distinct
--               from PIN-only staff). Kept per instruction: a constraint
--               that's slightly permissive costs nothing; one that's too
--               strict costs a migration under pressure the day the
--               feature lands - and this file already proved that isn't
--               hypothetical.
--
-- NOT included: nothing else turned up in the re-grep. If a future role
-- needs adding, this constraint is the one place to widen - see the
-- ALTER below, drop-and-recreate the same way any other checked function/
-- constraint in this repo changes shape.
--
-- CALLER_ROLE GATE - re-confirmed against this finding, not just assumed
-- still valid: staff PIN sessions authenticate via a synthetic
-- staff-<uuid>@staff.nagarva.in shadow email that only pin-login/
-- staff-login ever create (see staffEmail() in both files) - never a
-- real person's own email/password Supabase Auth account. A real vendor
-- registering through create-org always gets a brand-new auth.users.id
-- distinct from any staff shadow user's id, so a real registration can
-- never land on a 'staff'-role membership via that path. Adding 'staff'
-- to this constraint does not create a loophole in step 3's
-- caller_role == 'owner' gate.
-- ---------------------------------------------------------------------------
--
-- CASING: the constraint requires role = lower(role) AS WELL AS
-- role in (...) - not just a case-insensitive check. A constraint that
-- only verified lower(role) IN (...) would still let 'Owner' be stored
-- (it passes case-insensitively) and quietly put the casing bug right
-- back - every future reader would still need to remember to lower().
-- Requiring the STORED value to already be canonical lowercase closes
-- that permanently: after this runs, org_members.role literally cannot
-- hold anything but 'owner', 'staff' or 'manager', in exactly that
-- casing, ever again - not "every reader happens to normalise", a
-- guarantee. Confirmed live casing is already clean (both 'owner' and
-- 'staff' rows are lowercase today), so this is closing the door, not
-- fixing existing dirty data.
--
-- ---------------------------------------------------------------------------
-- RUN THIS QUERY FIRST, again, even though it's already been run once for
-- this file. If it returns anything other than owner/staff/manager, or
-- any of those with unexpected casing, the ALTER below will fail with a
-- constraint violation naming the offending row.
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
      check (role = lower(role) and role in ('owner', 'staff', 'manager'));
  end if;
end $$;

commit;

-- Verify after running:
--   select conname, pg_get_constraintdef(oid)
--     from pg_constraint
--    where conrelid = 'public.org_members'::regclass
--      and conname = 'org_members_role_check';
--   -- expect: CHECK (((role = lower(role)) AND (role = ANY
--   --   (ARRAY['owner'::text, 'staff'::text, 'manager'::text]))))
--
--   -- confirm it actually rejects bad casing:
--   -- insert into org_members (org_id, user_id, role)
--   --   values ('<any real org_id>', gen_random_uuid(), 'Owner');
--   -- expect: ERROR - new row for relation "org_members" violates check
--   -- constraint "org_members_role_check". Nothing commits.
--
--   -- confirm a genuinely new staff member can still log in after this
--   -- runs: PIN-login a staff member with no existing org_members row
--   -- and confirm the insert of role='staff' still succeeds (it should -
--   -- 'staff' is now an explicitly allowed value, this isn't blocking
--   -- anything that worked before).
