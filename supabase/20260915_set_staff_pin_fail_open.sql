-- =====================================================================
-- SECURITY: set_staff_pin() fails OPEN. Deny on unknown, and take it
-- away from anon.  (15 Sept 2026)
--
-- HAND-RUN. Read this header before executing.
--
-- THE DEFECT
-- ---------------------------------------------------------------------
-- The guard reads correctly and cannot fire:
--
--     if not (
--       public.is_org_owner(v_staff.org_id)
--       or v_staff.auth_user_id = auth.uid()
--     ) then
--       raise exception 'not authorized to set this PIN';
--     end if;
--
-- `staff.auth_user_id` is NULL on all 5 live rows, and `auth.uid()` is
-- NULL for an unauthenticated caller. So the second operand is NULL, not
-- false:
--
--     is_org_owner(...)            -> false   (exists(), never NULL)
--     auth_user_id = auth.uid()    -> NULL    (NULL = anything is NULL)
--     false or NULL                -> NULL
--     not NULL                     -> NULL
--     if NULL then ...             -> NOT TAKEN
--
-- Execution falls through to the UPDATE. `trg_staff_hash_pin` then
-- bcrypts the value into `pin_hash` and NULLs `pin`, so the call does not
-- merely write a column -- it mints a working login credential.
--
-- OBSERVED, NOT DEDUCED (15 Sept 2026, both probes rolled back by a
-- closing RAISE; `staff` re-counted after each and unchanged at 5 rows /
-- 1 pin_hash):
--
--   PROOF : is_org_owner=f | (auth_user_id = auth.uid())=NULL
--           | guard_expr=NULL | pin_hash before=NULL after=$2a$06$JsZ4f...
--           | PIN_WAS_SET=t
--   PROOF2: called_as=anon  | pin_hash_after=$2a$06$0Rn...
--           | ANON_SET_A_CREDENTIAL=t
--
-- The comment sitting above that raise explains at length that it is a
-- real RAISE EXCEPTION and not a silent return. That is TRUE and it is
-- the wrong reassurance: the question was never what happens when the
-- guard fires, it is that the guard cannot fire. The comment is replaced
-- below so it stops vouching for the wrong property.
--
-- THE FIX IS TWO THINGS, AND NEITHER SUBSTITUTES FOR THE OTHER
-- ---------------------------------------------------------------------
-- 1. `coalesce(<whole condition>, false)` so an UNKNOWN answer denies.
--    The coalesce wraps the WHOLE disjunction, not either operand.
--
--    NOT `is not distinct from` on the uid comparison. That looks like
--    the null-safe operator for the job and is the worse bug: with
--    auth.uid() NULL for anon and auth_user_id NULL on every row,
--    `auth_user_id is not distinct from auth.uid()` is TRUE, so anon
--    would match EVERY staff row and the guard would authorise instead
--    of denying. Do not "simplify" to it later.
--
-- 2. Revoke EXECUTE so nothing unauthenticated reaches a function that
--    sets a credential, whatever the guard says.
--
--    THE REVOKE TARGET IS `PUBLIC`, NOT `anon`. The source migration
--    (20260807_phase0_staff_credential_lockdown.sql:180) granted only
--    `authenticated`. anon's EXECUTE is inherited from the DEFAULT
--    PUBLIC grant every function is created with -- it shows in the ACL
--    as grantee `-`. `revoke ... from anon` alone would leave PUBLIC
--    intact and anon would still execute: a revoke that reports success
--    and changes nothing. Both are revoked below.
--
-- WHAT KEEPS ACCESS: `authenticated` (staff_form_sheet.dart:286 is the
-- app's only caller and runs in a signed-in session), plus postgres and
-- service_role. The in-app PIN flows are unaffected.
--
-- SWEEP FOR THE SAME SHAPE -- `set_staff_pin` IS THE ONLY INSTANCE.
-- Nine functions compare something to auth.uid(); each was READ, not
-- inferred from a flag:
--   check_doc_prefix              `if not exists (...)` -- exists() is
--                                 never NULL, so it fails closed. Safe.
--   current_staff_branch_or_owner `is_org_owner(...) or exists (...)`
--                                 -- both operands boolean. Safe.
--   is_org_owner, is_platform_admin, current_org_ids, current_staff_id
--                                 -- `exists(... = auth.uid())` inside a
--                                 SELECT. Returns false, never NULL. Safe.
--   audit_row                     -- assigns auth.uid() to a column;
--                                 no guard. Safe.
--   revise_quote                  -- `v_actor := auth.uid()::text`;
--                                 no guard. Safe.
-- RLS POLICIES ARE STRUCTURALLY IMMUNE and were not swept: a policy
-- whose USING clause evaluates to NULL denies the row. Only a plpgsql
-- `if not (...)` turns UNKNOWN into permission.
--
-- NOT FIXED HERE, BY INSTRUCTION: nothing else. Any future instance gets
-- its own migration.
--
-- THE REAL REMEDY IS STILL OWED: `staff.auth_user_id` is NULL on all 5
-- rows, which is also why no audit row can name a staff member as its
-- actor (see CLAUDE.md). Populating it is a separate change; this
-- migration makes the guard correct whether or not that ever happens.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- PREFLIGHT. Behavioural, not textual: it CALLS the function and reads
-- what happened, then rolls that call back inside a subtransaction. A
-- string match for "coalesce" over the body could be satisfied by a
-- comment -- including one of the comments this migration adds.
-- ---------------------------------------------------------------------
do $$
declare
  v_id         uuid;
  v_allowed    boolean := false;
begin
  if to_regprocedure('public.set_staff_pin(uuid,text)') is null then
    raise exception
      'PREFLIGHT: public.set_staff_pin(uuid,text) does not exist. Run 20260807_phase0_staff_credential_lockdown.sql first.';
  end if;

  select id into v_id
  from public.staff
  where auth_user_id is null
  order by id
  limit 1;

  if v_id is null then
    raise exception
      'PREFLIGHT: no staff row with a NULL auth_user_id, so the fail-open condition cannot be reproduced here. Verify by hand before applying.';
  end if;

  -- Probe. This runs as the migration's role, where auth.uid() is NULL
  -- and is_org_owner() is false -- the same operands an anon caller
  -- presents. The inner RAISE discards the write either way.
  begin
    perform public.set_staff_pin(v_id, '0000');
    v_allowed := true;
    raise exception 'ccr_probe_rollback';
  exception when others then
    if sqlerrm <> 'ccr_probe_rollback' then
      v_allowed := false;   -- it denied us, as it should
    end if;
  end;

  if not v_allowed then
    raise exception
      'PREFLIGHT: set_staff_pin already DENIES an unauthorised caller. This fix looks applied; nothing to do. (Re-running would be a no-op, so the transaction is rolled back rather than reporting a false success.)';
  end if;

  raise notice 'PREFLIGHT OK: set_staff_pin currently fails open (the probe set a PIN and was rolled back). Applying fix.';
end;
$$;

-- ---------------------------------------------------------------------
-- THE FIX. CREATE OR REPLACE is correct here: the signature and the void
-- return type are unchanged, so no DROP is needed. SECURITY DEFINER and
-- the search_path are RESTATED deliberately -- a replace that omits them
-- silently changes how the function runs.
-- ---------------------------------------------------------------------
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

  -- NULL-SAFE BY CONSTRUCTION. coalesce wraps the WHOLE condition, so an
  -- UNKNOWN answer denies.
  --
  -- Why it has to: `staff.auth_user_id` is nullable and NULL on every
  -- live row, and auth.uid() is NULL for an unauthenticated caller, so
  -- `v_staff.auth_user_id = auth.uid()` is NULL rather than false. The
  -- previous version read `if not (false or NULL)`, which is `if NULL`,
  -- which plpgsql does not take -- so the raise below could never fire
  -- and execution reached the UPDATE. Proven by calling it, 15 Sept 2026.
  --
  -- Do NOT rewrite the comparison as `is not distinct from`: with NULL on
  -- both sides that is TRUE, which would make an anonymous caller match
  -- every staff row. That is worse than the bug it would be replacing.
  if not coalesce(
    public.is_org_owner(v_staff.org_id)
    or v_staff.auth_user_id = auth.uid(),
    false
  ) then
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

-- ---------------------------------------------------------------------
-- GRANTS. PUBLIC first -- that is where anon's EXECUTE actually comes
-- from. Revoking only anon would change nothing and report success.
-- ---------------------------------------------------------------------
revoke execute on function public.set_staff_pin(uuid, text) from public;
revoke execute on function public.set_staff_pin(uuid, text) from anon;
grant  execute on function public.set_staff_pin(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- POSTFLIGHT. Same transaction, so a failed assertion rolls the fix back
-- rather than shipping half of it. Behavioural first, ACL second.
-- ---------------------------------------------------------------------
do $$
declare
  v_id      uuid;
  v_allowed boolean := false;
  v_anon    boolean;
  v_public  boolean;
  v_auth    boolean;
begin
  select id into v_id
  from public.staff
  where auth_user_id is null
  order by id
  limit 1;

  -- Without this, v_id is NULL, set_staff_pin raises 'staff member not
  -- found', the handler reads that as a denial, and the postflight PASSES
  -- having tested nothing -- an always-passes check inside the migration
  -- written to enforce the opposite.
  if v_id is null then
    raise exception
      'POSTFLIGHT FAILED: no staff row with a NULL auth_user_id, so the guard could not be exercised. Refusing to report success on an untested fix.';
  end if;

  -- 1. The guard must now DENY the exact caller it used to admit.
  begin
    perform public.set_staff_pin(v_id, '0000');
    v_allowed := true;
    raise exception 'ccr_probe_rollback';
  exception when others then
    if sqlerrm <> 'ccr_probe_rollback' then
      v_allowed := false;
    end if;
  end;

  if v_allowed then
    raise exception
      'POSTFLIGHT FAILED: set_staff_pin STILL sets a PIN for a caller who is neither the org owner nor the staff member. The guard is still failing open.';
  end if;

  -- 2. anon and PUBLIC must be gone; authenticated must remain, or the
  --    app's own PIN screen breaks.
  select bool_or(a.grantee = 'anon'::regrole),
         bool_or(a.grantee = 0),
         bool_or(a.grantee = 'authenticated'::regrole)
    into v_anon, v_public, v_auth
  from pg_proc p,
       lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
  where p.oid = to_regprocedure('public.set_staff_pin(uuid,text)')
    and a.privilege_type = 'EXECUTE';

  if coalesce(v_anon, false) then
    raise exception 'POSTFLIGHT FAILED: anon still holds EXECUTE on set_staff_pin.';
  end if;
  if coalesce(v_public, false) then
    raise exception 'POSTFLIGHT FAILED: PUBLIC still holds EXECUTE on set_staff_pin — anon inherits it.';
  end if;
  if not coalesce(v_auth, false) then
    raise exception 'POSTFLIGHT FAILED: authenticated LOST EXECUTE on set_staff_pin — the in-app PIN screen would break.';
  end if;

  raise notice 'POSTFLIGHT OK: guard denies an unauthorised caller; anon and PUBLIC revoked; authenticated retained.';
end;
$$;

commit;
