-- ============================================================================
-- 20260725_staff_pin_rate_limit.sql
-- Item 6 (NAGARVA_STATUS.md THIS WEEK): PIN rate limiting.
--
-- Idempotent — safe to re-run.
--
-- CORRECTION (27 Jul 2026): the original failed with 42P13 "cannot change
-- return type of existing function". 20260723_staff_auth_link_v2.sql created
-- verify_staff_pin() returning 5 columns; this version returns 7 (adds
-- `locked` / `locked_until`), and CREATE OR REPLACE FUNCTION cannot change a
-- return type in place. Added an explicit DROP FUNCTION first — same lesson
-- as the DROP VIEW IF EXISTS requirement in views_dashboard_and_ops.sql.
--
-- The staff-login Edge Function (supabase/functions/staff-login/index.ts)
-- had no lockout at all: verify_staff_pin() just did a bcrypt compare and
-- returned ok/not-ok, so a PIN is only 4 digits and nothing stopped an
-- unlimited brute-force loop against it. This adds a lockout counter to
-- verify_staff_pin() itself (security definer, service_role only, same
-- function name/signature the Edge Function already calls) rather than
-- tracking attempts in the Edge Function, so the counter is atomic and
-- can't be raced by concurrent requests.
--
-- Policy: 5 failed attempts -> 15 minute lockout, then the counter resets.
-- A correct PIN always resets the counter immediately. Adjust
-- v_max_attempts / v_lock_minutes below if a different policy is wanted.
--
-- NOTE: the DROP + CREATE run inside one transaction in the Supabase SQL
-- editor, so there is no window where verify_staff_pin does not exist.
-- ============================================================================

alter table public.staff add column if not exists failed_pin_attempts integer not null default 0;
alter table public.staff add column if not exists pin_locked_until timestamptz;

-- Required: the return type changes from 5 columns to 7 (see header).
drop function if exists public.verify_staff_pin(uuid, text);

create or replace function public.verify_staff_pin(p_staff_id uuid, p_pin text)
returns table (
  ok boolean,
  org_id uuid,
  role text,
  name text,
  auth_user_id uuid,
  locked boolean,
  locked_until timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_staff record;
  v_ok boolean;
  v_max_attempts constant integer := 5;
  v_lock_minutes constant integer := 15;
  v_new_lock_until timestamptz;
begin
  select s.pin_hash, s.org_id, s.role, s.name, s.auth_user_id,
         s.failed_pin_attempts, s.pin_locked_until, s.active
    into v_staff
  from public.staff s
  where s.id = p_staff_id;

  if not found or coalesce(v_staff.active, false) = false then
    return query select false, null::uuid, null::text, null::text,
                        null::uuid, false, null::timestamptz;
    return;
  end if;

  -- Still inside an existing lockout window — don't even check the PIN,
  -- so a locked-out attacker can't use response timing/behaviour to learn
  -- anything, and legitimate staff get a clear "try again at HH:MM".
  if v_staff.pin_locked_until is not null and v_staff.pin_locked_until > now() then
    return query select false, v_staff.org_id, v_staff.role, v_staff.name,
                        v_staff.auth_user_id, true, v_staff.pin_locked_until;
    return;
  end if;

  v_ok := v_staff.pin_hash is not null
      and v_staff.pin_hash = extensions.crypt(p_pin, v_staff.pin_hash);

  if v_ok then
    update public.staff
      set failed_pin_attempts = 0, pin_locked_until = null
      where id = p_staff_id;
    return query select true, v_staff.org_id, v_staff.role, v_staff.name,
                        v_staff.auth_user_id, false, null::timestamptz;
    return;
  end if;

  if v_staff.failed_pin_attempts + 1 >= v_max_attempts then
    v_new_lock_until := now() + (v_lock_minutes || ' minutes')::interval;
    update public.staff
      set failed_pin_attempts = 0, pin_locked_until = v_new_lock_until
      where id = p_staff_id;
    return query select false, v_staff.org_id, v_staff.role, v_staff.name,
                        v_staff.auth_user_id, true, v_new_lock_until;
  else
    update public.staff
      set failed_pin_attempts = failed_pin_attempts + 1
      where id = p_staff_id;
    return query select false, v_staff.org_id, v_staff.role, v_staff.name,
                        v_staff.auth_user_id, false, null::timestamptz;
  end if;
end;
$$;

revoke all on function public.verify_staff_pin(uuid, text) from public;
revoke all on function public.verify_staff_pin(uuid, text) from anon;
revoke all on function public.verify_staff_pin(uuid, text) from authenticated;
grant execute on function public.verify_staff_pin(uuid, text) to service_role;

-- ============================================================================
-- CLEANUP — DO NOT RUN NOW, separate step, only after BOTH:
--   (a) the app fix in lib/users_page/staff_form_sheet.dart (never
--       pre-fills/reads staff.pin for display) is deployed, AND
--   (b) a real staff PIN login has been tested successfully against the
--       rewritten function above — this is what catches a stale deployed
--       Edge Function expecting the old 5-column return type.
-- Nulls the plaintext PIN column now that nothing in the app reads it. The
-- pin_hash trigger from 20260723_staff_auth_link_v2.sql is untouched by this
-- migration and keeps working exactly as before (it only fires on INSERT or
-- when a new non-empty pin is written).
--   update public.staff set pin = null;
--
-- Verified safe to run when this returns unhashed = 0:
--   select count(*) filter (where pin is not null and pin_hash is null) as unhashed
--   from public.staff;
-- (Confirmed 0 across all 8 staff rows on 27 Jul 2026.)
-- ============================================================================
