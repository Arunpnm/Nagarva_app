-- Phase 0 hotfix (NG-BRIEF-rls-remediation.md §2) — staff credential lockdown.
-- Handed over for Arun to review and run — not executed from this session.
-- Wrapped in one transaction so a mid-file failure can't leave the column
-- GRANT applied without set_staff_pin() existing yet (which would strand
-- every PIN-reset with no working path at all).
--
-- Scope, confirmed against the live app before writing this (7 Aug 2026):
--   - Live 30-column staff schema pulled via information_schema.columns.
--   - Every Dart write site to `staff` found: exactly one file,
--     lib/users_page/staff_form_sheet.dart, two calls (StaffTable().update
--     and StaffTable().insert) — nothing else in lib/ writes this table,
--     confirmed by grep (the wider StaffTable() hit list was mostly
--     OrderStaffTable(), a different table, matched as a substring).
--   - For every column below marked "no live writers", grepped the whole
--     app for a Dart write and found none — restricting them costs nothing
--     today.
--   - staff-deactivate Edge Function already covers activate AND
--     deactivate (takes {staff_id, active: boolean}), already owner-gated,
--     already kills live sessions on deactivate, and staff_form_sheet.dart
--     already routes through it rather than writing `active` directly.
--     Nothing needed here for that path.
--   - verify_staff_pin() is already SECURITY DEFINER (confirmed via
--     pg_get_functiondef) — its own writes to failed_pin_attempts/
--     pin_locked_until on login run as the function owner, not the caller,
--     so this migration's column REVOKE does not affect it.
--   - 8 total staff rows live, 2 with a non-null plaintext `pin` — small
--     enough to null out unconditionally below.
--
-- PRECONDITION, checked live and NOT currently met: this migration's
-- set_staff_pin() calls is_org_owner(uuid), which is defined in 60110b4
-- (supabase/20260807_customer_surveys_and_soft_delete_corrections.sql)
-- alongside current_staff_id(). Queried pg_proc directly before writing
-- this: only current_org_ids and is_platform_admin exist live today;
-- is_org_owner and current_staff_id do not. CREATE FUNCTION won't fail
-- without it (plpgsql bodies aren't checked against referenced objects
-- until they actually run), but every call to set_staff_pin() will error
-- at runtime with "function is_org_owner(uuid) does not exist" until
-- 60110b4 has been applied. Run 60110b4 before this file, not after.
--
-- Confirmed live and NOT a concern: trg_staff_hash_pin (the only trigger
-- on staff) is BEFORE INSERT OR UPDATE — it rewrites NEW.pin/NEW.pin_hash
-- before the row is ever written, in the same statement, so 0b(i) below
-- means the plaintext genuinely never hits disk, not even for one write,
-- once this trigger fix is applied. And set_staff_pin() raises a real
-- exception (not a silent no-op) when the owner-or-self check fails —
-- Postgres propagates that as a normal SQL error, which PostgREST turns
-- into an HTTP error response to the caller, not a false "success".
--
-- Deliberately NOT restricted this pass, on Arun's explicit call (his
-- correction to the brief's own minimum list): role, salary,
-- pf_applicable, esic_applicable, permissions. All five have live,
-- legitimate writers in staff_form_sheet.dart's owner-editing-a-staff-
-- member flow, and a column GRANT applies to `authenticated` as a whole —
-- it cannot distinguish "the owner editing a colleague" from "a colleague
-- editing themselves", so restricting these now would break the owner
-- path too, with no Phase 0 replacement. `permissions` carries the same
-- risk as `role` (writing {"payments": true} to your own row is
-- self-escalation past whatever `role` alone would have blocked) and gets
-- the same treatment. All five stay writable by any org member until
-- Tier A ships its row-level owner-vs-staff test — this is a known,
-- documented gap, not an oversight. Do not "fix" this in isolation before
-- Tier A lands; it needs the RLS half, not another column-GRANT patch.

begin;

-- ============================================================================
-- 0a(i). Column-level lockdown on staff.
-- ============================================================================
-- RLS filters rows; it cannot say "may edit their own name but not their
-- own role/pin". This is the column half — see the brief's §1 for why both
-- mechanisms are needed. INSERT privilege is untouched (a brand-new staff
-- row has no prior session to protect, and the new-staff path legitimately
-- sets several of the columns restricted below in one call) — only UPDATE
-- is revoked and re-granted on a narrower column list.
--
-- Restricted (no UPDATE grant): pin, pin_hash, auth_user_id,
-- failed_pin_attempts, pin_locked_until, active, advance, pan,
-- bank_account, bank_ifsc, uan_no, esic_no, pf_enrolled, pf_employee_pct,
-- esic_enrolled, esic_employee_pct, pt_applicable, basic_pct — the literal
-- one-statement exploits (pin/pin_hash/lockout columns), the columns with
-- no legitimate Dart writer at all (auth_user_id, advance, pan,
-- bank_account, bank_ifsc, uan_no, esic_no, pf_enrolled, pf_employee_pct,
-- esic_enrolled, esic_employee_pct, pt_applicable, basic_pct), and `active`
-- (already replaced by the staff-deactivate Edge Function).
--
-- Granted (kept updatable): name, phone, branch, date_of_joining — plain
-- profile fields, never sensitive. role, salary, pf_applicable,
-- esic_applicable, permissions — the deferred-to-Tier-A group above, still
-- writable by any org member for now, by explicit decision, not omission.
-- id/org_id/created_at are excluded from the grant entirely: nothing in
-- the app writes them today, id is the primary key, and org_id is the
-- tenant boundary RLS itself relies on — there is no scenario where
-- `authenticated` should be able to move a staff row between orgs via a
-- plain UPDATE, so this is left closed rather than opened for no need.
--
-- IMPORTANT — deployment order is a hard sequence, not "same time or
-- after": (1) ship the APK with the set_staff_pin() Dart change below,
-- (2) confirm devices have actually picked it up, (3) only then run this
-- SQL. Devices don't all upgrade at once. If this migration lands while
-- any owner is still on the old build, that owner's next PIN reset sends
-- the old direct write to pin/failed_pin_attempts/pin_locked_until,
-- PostgREST rejects the whole request since those columns are no longer
-- grantable, and the owner sees an opaque permission error with no PIN
-- changed — not a deferred inconvenience, a broken feature for whoever
-- hasn't updated yet.

revoke update on staff from authenticated;

grant update (
  name,
  phone,
  branch,
  date_of_joining,
  role,
  salary,
  pf_applicable,
  esic_applicable,
  permissions
) on staff to authenticated;

-- ============================================================================
-- 0a(ii). set_staff_pin() — the legitimate replacement path for PIN writes.
-- ============================================================================
-- SECURITY DEFINER so it can still write pin/failed_pin_attempts/
-- pin_locked_until internally despite the REVOKE above — same pattern as
-- verify_staff_pin(). Permits the call only for the org's real owner
-- (via is_org_owner(), the same helper added for the notifications fix) or
-- the staff member changing their own PIN (auth_user_id = auth.uid()).
-- Writes the plaintext `pin` column, not `pin_hash` directly — the
-- existing staff_hash_pin BEFORE trigger (fixed below, 0b) does the
-- hashing and nulls the plaintext back out, so this function doesn't need
-- its own pgcrypto call and can't drift from the trigger's hashing logic.
create or replace function public.set_staff_pin(p_staff_id uuid, p_new_pin text)
returns void
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_staff record;
begin
  select id, org_id, auth_user_id
    into v_staff
  from public.staff
  where id = p_staff_id;

  if not found then
    raise exception 'staff member not found';
  end if;

  if not (
    public.is_org_owner(v_staff.org_id)
    or v_staff.auth_user_id = auth.uid()
  ) then
    -- Confirmed: this is a real RAISE EXCEPTION, not a silent return. It
    -- aborts the whole function (and any enclosing transaction) and
    -- propagates as a normal Postgres error, which PostgREST surfaces to
    -- the caller as an HTTP error response — a denied caller sees a clear
    -- failure, never a false "success" with nothing actually changed.
    raise exception 'not authorized to set this PIN';
  end if;

  if p_new_pin is null or length(trim(p_new_pin)) = 0 then
    raise exception 'PIN must not be empty';
  end if;

  -- Clearing the lockout on a fresh PIN mirrors what the direct update
  -- used to do (Users Kickoff Step 3.4): verify_staff_pin() only clears
  -- failed_pin_attempts/pin_locked_until on a SUCCESSFUL login, never when
  -- an owner/self sets a brand new PIN here — without this, someone
  -- currently locked out would stay locked despite now holding a valid PIN.
  update public.staff
    set pin = p_new_pin,
        failed_pin_attempts = 0,
        pin_locked_until = null
    where id = p_staff_id;
end;
$function$;

grant execute on function public.set_staff_pin(uuid, text) to authenticated;

-- ============================================================================
-- 0b(i). staff_hash_pin trigger: null the plaintext after hashing.
-- ============================================================================
-- Was hashing `pin` into `pin_hash` but never clearing `pin` back out —
-- unlike org_members_hash_pin, which already does. Every staff PIN set
-- through the normal path (this trigger, still fired by set_staff_pin()'s
-- plain UPDATE above and by the new-staff INSERT path) has been sitting in
-- cleartext in a table every org member could read. Mirrors
-- org_members_hash_pin's null-out line; nothing else about the trigger
-- changes.
create or replace function public.staff_hash_pin()
returns trigger
language plpgsql
set search_path to 'public', 'extensions'
as $function$
begin
  if new.pin is not null and new.pin <> ''
     and (tg_op = 'INSERT' or new.pin is distinct from old.pin) then
    new.pin_hash := extensions.crypt(new.pin, extensions.gen_salt('bf'));
    new.pin := null; -- never store plaintext, not even transiently
  end if;
  return new;
end;
$function$;

-- ============================================================================
-- 0b(ii). One-time cleanup of plaintext already at rest.
-- ============================================================================
-- Confirmed live before writing this: 8 total staff rows, 2 with a
-- non-null pin. pin_hash is untouched by this — only the plaintext
-- column is cleared; existing hashes (and therefore existing PIN logins)
-- are unaffected.
update public.staff set pin = null where pin is not null;

commit;
