-- ============================================================================
-- 20260729_verify_org_pin_collision_guard.sql
--
-- SECURITY FIX. Nothing else is bundled in.
--
-- THE BUG: verify_org_pin() checks the owner pool, then the staff pool, and
-- RETURNS ON FIRST MATCH. So a staff member whose 4-digit PIN happens to
-- equal the owner's gets `kind = 'owner'` and a session minted against the
-- owner's real Supabase Auth account — full financial access, the whole
-- app. With 4 digits and an org-wide pool, that is a 1-in-10,000 collision
-- per staff member per org, which is not a hypothetical at any real
-- headcount. This is live on every supervisor phone today.
--
-- THE FIX: count matches across BOTH pools before deciding. Exactly one
-- match logs in. Two or more returns ok = false — it refuses rather than
-- guessing which identity the person is.
--
-- IF A COLLISION EXISTS RIGHT NOW, this guard will refuse BOTH parties at
-- the PIN screen until one of them changes their PIN. That is the correct
-- direction to fail — a staff member currently holding owner access is
-- worse than a refused owner, and the owner can still get in via the
-- email/password LoginPage, which does not go through this function at
-- all. See the note at the end of the file on finding collisions.
--
-- ---------------------------------------------------------------------------
-- RETURN SHAPE CHANGES: adds `reason text`. Hence the unconditional DROP
-- below (a RETURNS TABLE shape change under CREATE OR REPLACE raises
-- 42P13 — this exact function hit that before).
--
-- The deployed pin-login Edge Function reads only ok / kind / user_id /
-- staff_id / staff_role / staff_name / staff_auth_user_id / locked /
-- locked_until. An extra key on a JSON row is ignored, so it keeps working
-- unchanged and simply shows its generic "Wrong PIN" message on a
-- collision. That is safe — access is denied either way. Surfacing the
-- real message ("PIN clashes with another user") needs an Edge Function
-- redeploy reading `reason`, which is a follow-up, not a blocker.
--
-- PERFORMANCE, worth knowing before you run it: detecting a collision
-- means bcrypt-comparing against EVERY candidate row, so the early exit is
-- gone. Login cost is now proportional to (owners + active staff) in the
-- org, at roughly 50-100ms per bcrypt. A 20-person org lands around
-- 1-2 seconds. That is the price of the check and there is no way around
-- it while PINs are hashed. It also disappears entirely once staff are
-- bound to a specific staff_id and use staff-login instead of this
-- org-wide pool — the structural fix already on your list, which this
-- guard is holding the line for in the meantime.
-- ============================================================================

begin;

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

-- ============================================================================
-- FINDING EXISTING COLLISIONS
--
-- Read this before reaching for a query: bcrypt salts every row, so two
-- identical PINs produce DIFFERENT hashes. There is no way to find
-- collisions by grouping on pin_hash. The only way is to recover each
-- plaintext PIN by brute-forcing the 4-digit space against each hash, and
-- that costs one bcrypt per candidate.
--
-- RECOMMENDED: don't. Apply the guard and let collisions surface as
-- refused logins. A colliding user gets ok = false and calls you; the
-- owner resets that person's PIN in Settings and they are fine. Zero cost,
-- and it self-resolves as people actually try to log in.
--
-- The owner is never stranded by this: the email/password LoginPage is
-- still there and does not go through verify_org_pin at all.
--
-- IF YOU WANT THE SWEEP ANYWAY, the helper below recovers PINs so they can
-- be grouped. Understand the cost first: it short-circuits on match, so it
-- averages ~5,000 bcrypt calls per hash. At pgcrypto's default bf cost
-- that is roughly 30-60 seconds PER PIN. Ten staff is several minutes; a
-- hundred is an hour. Run it once, off-hours, not casually — and drop the
-- helper afterwards, because a function that reverses PINs is not
-- something to leave sitting in the schema.
--
--   create or replace function public.pg_temp_recover_pin(p_hash text)
--   returns text language sql stable as $fn$
--     select lpad(g::text, 4, '0')
--       from generate_series(0, 9999) g
--      where p_hash = extensions.crypt(lpad(g::text, 4, '0'), p_hash)
--      limit 1;
--   $fn$;
--
--   -- everyone in one org who shares a PIN with anyone else
--   with pins as (
--     select s.org_id, s.id, s.name, 'staff' as kind,
--            public.pg_temp_recover_pin(s.pin_hash) as pin
--       from public.staff s
--      where s.pin_hash is not null and coalesce(s.active, true)
--     union all
--     select om.org_id, om.user_id, '(owner)', 'owner',
--            public.pg_temp_recover_pin(om.pin_hash)
--       from public.org_members om
--      where om.role = 'owner' and om.pin_hash is not null
--   )
--   select o.name as org, p.pin, count(*) as holders,
--          string_agg(p.kind || ':' || p.name, ', ') as who
--     from pins p join public.organizations o on o.id = p.org_id
--    group by o.name, p.pin
--   having count(*) > 1
--    order by o.name;
--
--   drop function public.pg_temp_recover_pin(text);
--
-- Verify the function afterwards:
--   select proname, pg_get_function_result(oid)
--     from pg_proc where proname = 'verify_org_pin';
--   -- the result list must now end with `reason text`
