-- ============================================================================
-- ROLLBACK — restore verify_org_pin to its pre-19-Aug-2026 state
--
-- RUN THIS FIRST. It restores PIN login on the org-code path and depends
-- on nothing that the failed migration was supposed to create.
--
-- SITUATION: the 3-argument verify_org_pin is live and queries
-- pin_ip_attempts / org_pin_attempts.pool, neither of which exists. Every
-- call therefore raises 42P01 (relation does not exist), pin-login gets
-- an RPC error and returns "Verification failed". Org-code PIN login is
-- down; invite-bound devices are UNAFFECTED because staff-login uses
-- verify_staff_pin, which was not replaced.
--
-- The 3-arg function MUST be dropped, not just shadowed: its p_client_ip
-- has a DEFAULT, so a 2-argument call would match both signatures and
-- fail with 42725 (ambiguous function call).
--
-- This file is byte-identical to the function created by
-- supabase/20260729_verify_org_pin_collision_guard.sql.
-- ============================================================================

begin;

drop function if exists public.verify_org_pin(uuid, text, text);
drop function if exists public.verify_org_pin(uuid, text);

create or replace function public.verify_org_pin(p_org_id uuid, p_pin text)
returns table (
  ok boolean,
  kind text,           -- 'owner' | 'staff'
  user_id uuid,        -- org_members.user_id (owner) — mint a session for this
  staff_id uuid,       -- staff.id (staff) — feeds the existing staff-login flow
  staff_role text,
  staff_name text,
  staff_auth_user_id uuid,
  locked boolean,
  locked_until timestamptz,
  reason text          -- NEW: 'pin_collision' when >1 row matched
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_attempts record;
  v_max_attempts constant integer := 5;
  v_lock_minutes constant integer := 15;
  v_owner record;
  v_staff record;
  -- Accumulate matches instead of returning on the first one.
  v_match_count integer := 0;
  v_kind text;
  v_user_id uuid;
  v_staff_id uuid;
  v_staff_role text;
  v_staff_name text;
  v_staff_auth uuid;
begin
  select * into v_attempts from public.org_pin_attempts where org_id = p_org_id;

  if v_attempts.locked_until is not null and v_attempts.locked_until > now() then
    return query select false, null::text, null::uuid, null::uuid,
                        null::text, null::text, null::uuid,
                        true, v_attempts.locked_until, 'locked'::text;
    return;
  end if;

  -- ---- Pool 1: owner (org_members.role = 'owner') ----
  -- Table aliased and every selected column re-aliased (m_*) because this
  -- function's OUT parameters are implicitly declared as plpgsql variables
  -- in scope here — a bare `select user_id, ...` is ambiguous the moment a
  -- column name matches an OUT param name (hit live as 42702).
  for v_owner in
    select om.user_id as m_user_id, om.pin_hash as m_pin_hash
    from public.org_members om
    where om.org_id = p_org_id and om.role = 'owner' and om.pin_hash is not null
  loop
    if v_owner.m_pin_hash = extensions.crypt(p_pin, v_owner.m_pin_hash) then
      v_match_count := v_match_count + 1;
      -- First match wins the "which identity" slot, but only matters if
      -- it turns out to be the ONLY match.
      if v_match_count = 1 then
        v_kind := 'owner';
        v_user_id := v_owner.m_user_id;
      end if;
    end if;
  end loop;

  -- ---- Pool 2: staff (active only) ----
  -- NOT skipped when the owner pool already matched — that early exit is
  -- exactly the bug. A staff PIN equal to the owner's must be detected.
  for v_staff in
    select s.id as s_id, s.role as s_role, s.name as s_name,
           s.auth_user_id as s_auth_user_id, s.pin_hash as s_pin_hash
    from public.staff s
    where s.org_id = p_org_id and coalesce(s.active, true) and s.pin_hash is not null
  loop
    if v_staff.s_pin_hash = extensions.crypt(p_pin, v_staff.s_pin_hash) then
      v_match_count := v_match_count + 1;
      if v_match_count = 1 then
        v_kind := 'staff';
        v_staff_id := v_staff.s_id;
        v_staff_role := v_staff.s_role;
        v_staff_name := v_staff.s_name;
        v_staff_auth := v_staff.s_auth_user_id;
      end if;
    end if;
  end loop;

  -- ---- Ambiguous: refuse rather than guess ----
  -- Deliberately NOT counted as a failed attempt and does NOT trip the
  -- lockout. The PIN was correct; the configuration is wrong. Locking the
  -- org out for 15 minutes would punish both users for an admin mistake
  -- and give no clue what to fix. The attempt counter is left untouched,
  -- neither incremented nor reset.
  if v_match_count > 1 then
    return query select false, null::text, null::uuid, null::uuid,
                        null::text, null::text, null::uuid,
                        false, null::timestamptz, 'pin_collision'::text;
    return;
  end if;

  -- ---- Exactly one match: log in ----
  if v_match_count = 1 then
    insert into public.org_pin_attempts (org_id, failed_attempts, locked_until)
      values (p_org_id, 0, null)
      on conflict (org_id) do update set failed_attempts = 0, locked_until = null;
    return query select true, v_kind, v_user_id, v_staff_id,
                        v_staff_role, v_staff_name, v_staff_auth,
                        false, null::timestamptz, null::text;
    return;
  end if;

  -- ---- No match: count one failed org-wide attempt ----
  -- RETURNING stays fully schema-qualified for the same 42702 reason.
  insert into public.org_pin_attempts (org_id, failed_attempts, locked_until)
    values (p_org_id, 1, null)
  on conflict (org_id) do update
    set failed_attempts = case
          when public.org_pin_attempts.failed_attempts + 1 >= v_max_attempts then 0
          else public.org_pin_attempts.failed_attempts + 1
        end,
        locked_until = case
          when public.org_pin_attempts.failed_attempts + 1 >= v_max_attempts
            then now() + (v_lock_minutes || ' minutes')::interval
          else null
        end
  returning public.org_pin_attempts.failed_attempts, public.org_pin_attempts.locked_until
    into v_attempts;

  return query select false, null::text, null::uuid, null::uuid,
                      null::text, null::text, null::uuid,
                      (v_attempts.locked_until is not null),
                      v_attempts.locked_until,
                      case when v_attempts.locked_until is not null
                           then 'locked' else 'wrong_pin' end::text;
end;
$$;

revoke all on function public.verify_org_pin(uuid, text) from public;
revoke all on function public.verify_org_pin(uuid, text) from anon;
revoke all on function public.verify_org_pin(uuid, text) from authenticated;
grant execute on function public.verify_org_pin(uuid, text) to service_role;

commit;

-- ----------------------------------------------------------------------------
-- VERIFY (read-only) — expect exactly one row, args 'p_org_id uuid, p_pin text'
--   select proname, pg_get_function_identity_arguments(oid)
--     from pg_proc where proname = 'verify_org_pin';
-- Then have someone sign in with a PIN on an org-code device.
-- ----------------------------------------------------------------------------
