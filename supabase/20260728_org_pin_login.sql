-- ============================================================================
-- 20260728_org_pin_login.sql — Part 7 (login screen rearchitecture)
--
-- Unifies owner + staff login behind a single 4-digit PIN, entered on a
-- device already bound to one org (no name/phone/email typed at the PIN
-- screen — see nagarva_part7_login.md for the full spec). Idempotent, safe
-- to re-run.
--
-- Design decision (confirmed with the owner before writing this): the
-- owner's PIN does NOT create a shadow auth user the way staff PINs do.
-- It verifies against a hash on the owner's own `org_members` row and, on
-- match, the pin-login Edge Function mints a session for the owner's REAL,
-- pre-existing Supabase Auth account (org_members.user_id) — so every
-- existing owner-only permission check in the app (AppSession.
-- currentStaffId == null, the nav filtering, Lock/logout logic, RLS
-- policies keyed on auth.uid()) keeps working completely unchanged. This
-- was the explicit alternative to making the owner a `staff` row, which
-- would have required auditing every currentStaffId==null check in the
-- app to also allow an owner-flavoured staff session.
--
-- Because the PIN screen doesn't know in advance whether the 4 digits
-- belong to the owner or to a staff member (no name/phone entered first),
-- verify_org_pin() below checks BOTH pools (org_members role='owner', then
-- staff) in one call. Rate limiting is therefore tracked per-ORG (new
-- org_pin_attempts table) rather than per-row like the existing
-- verify_staff_pin() — until a matching row is found there's no single
-- row to attribute a failed attempt to. This is IN ADDITION to (not a
-- replacement for) verify_staff_pin()'s existing per-staff lockout, which
-- still protects the staff-login Edge Function's other call path (kept
-- for any code that already resolves a specific staff_id).
--
-- Same trigger-based bcrypt pattern as staff.pin -> staff.pin_hash
-- (20260723_staff_auth_link_v2.sql): `pin` is a write-only plaintext
-- conduit, never read back, hashed into `pin_hash` by a BEFORE INSERT OR
-- UPDATE trigger.
-- ============================================================================

-- ---- org_members: add the owner's PIN alongside the existing role ----
alter table public.org_members add column if not exists pin text;
alter table public.org_members add column if not exists pin_hash text;

create or replace function public.org_members_hash_pin()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.pin is not null and new.pin <> '' then
    new.pin_hash := extensions.crypt(new.pin, extensions.gen_salt('bf'));
    new.pin := null; -- never store plaintext, not even transiently
  end if;
  return new;
end;
$$;

drop trigger if exists org_members_hash_pin_trigger on public.org_members;
create trigger org_members_hash_pin_trigger
  before insert or update on public.org_members
  for each row execute function public.org_members_hash_pin();

-- ---- Org-wide PIN-login rate limiting (see header for why per-org, not
-- per-row) ----
create table if not exists public.org_pin_attempts (
  org_id uuid primary key references public.organizations(id) on delete cascade,
  failed_attempts integer not null default 0,
  locked_until timestamptz
);

-- ---- The unified verify RPC ----
drop function if exists public.verify_org_pin(uuid, text);

create or replace function public.verify_org_pin(p_org_id uuid, p_pin text)
returns table (
  ok boolean,
  kind text,           -- 'owner' | 'staff'
  user_id uuid,         -- org_members.user_id (owner) — mint a session for this
  staff_id uuid,        -- staff.id (staff) — feeds the existing staff-login flow
  staff_role text,
  staff_name text,
  staff_auth_user_id uuid,
  locked boolean,
  locked_until timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_attempts record;
  v_max_attempts constant integer := 5;
  v_lock_minutes constant integer := 15;
  v_new_lock_until timestamptz;
  v_owner record;
  v_staff record;
begin
  select * into v_attempts from public.org_pin_attempts where org_id = p_org_id;

  if v_attempts.locked_until is not null and v_attempts.locked_until > now() then
    return query select false, null::text, null::uuid, null::uuid,
                        null::text, null::text, null::uuid,
                        true, v_attempts.locked_until;
    return;
  end if;

  -- ---- Pool 1: owner (org_members.role = 'owner') ----
  -- Table aliased and every selected column re-aliased (m_*) because this
  -- function's OUT parameters (user_id, staff_id, staff_role, staff_name,
  -- staff_auth_user_id, locked_until, ...) are implicitly declared as
  -- plpgsql variables in scope here. A bare `select user_id, ... from
  -- org_members` is ambiguous the moment a column name exactly matches an
  -- OUT param name (hit live: 42702 on `user_id`) — qualifying the table
  -- and renaming the output columns sidesteps it for good, including for
  -- OUT params that don't collide with a real column name.
  for v_owner in
    select om.user_id as m_user_id, om.pin_hash as m_pin_hash
    from public.org_members om
    where om.org_id = p_org_id and om.role = 'owner' and om.pin_hash is not null
  loop
    if v_owner.m_pin_hash = extensions.crypt(p_pin, v_owner.m_pin_hash) then
      insert into public.org_pin_attempts (org_id, failed_attempts, locked_until)
        values (p_org_id, 0, null)
        on conflict (org_id) do update set failed_attempts = 0, locked_until = null;
      return query select true, 'owner'::text, v_owner.m_user_id, null::uuid,
                          null::text, null::text, null::uuid,
                          false, null::timestamptz;
      return;
    end if;
  end loop;

  -- ---- Pool 2: staff (active only) ----
  for v_staff in
    select s.id as s_id, s.role as s_role, s.name as s_name,
           s.auth_user_id as s_auth_user_id, s.pin_hash as s_pin_hash
    from public.staff s
    where s.org_id = p_org_id and coalesce(s.active, true) and s.pin_hash is not null
  loop
    if v_staff.s_pin_hash = extensions.crypt(p_pin, v_staff.s_pin_hash) then
      insert into public.org_pin_attempts (org_id, failed_attempts, locked_until)
        values (p_org_id, 0, null)
        on conflict (org_id) do update set failed_attempts = 0, locked_until = null;
      return query select true, 'staff'::text, null::uuid, v_staff.s_id,
                          v_staff.s_role, v_staff.s_name, v_staff.s_auth_user_id,
                          false, null::timestamptz;
      return;
    end if;
  end loop;

  -- ---- No match in either pool: count as one failed org-wide attempt ----
  -- RETURNING must stay fully schema-qualified too (same reason as the two
  -- loops above) — a bare `returning failed_attempts, locked_until` would
  -- hit the identical 42702 against the `locked_until` OUT param; it just
  -- hadn't been reached yet because the owner-loop bug aborted first.
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
                      (v_attempts.locked_until is not null), v_attempts.locked_until;
end;
$$;

revoke all on function public.verify_org_pin(uuid, text) from public;
revoke all on function public.verify_org_pin(uuid, text) from anon;
revoke all on function public.verify_org_pin(uuid, text) from authenticated;
grant execute on function public.verify_org_pin(uuid, text) to service_role;

-- org_pin_attempts and org_members.pin_hash are only ever touched by
-- security-definer functions running as service_role from the Edge
-- Function — no direct client access needed, same posture as
-- staff.pin_hash / staff.failed_pin_attempts.

-- ---- Device org-binding lookup (Part 7's one-time org selection) ----
-- Needed pre-auth (device isn't bound to an org yet, so no session and no
-- RLS-scoped read of `organizations` is possible) — returns only the
-- minimal, non-sensitive fields a binding screen needs to show a match.
drop function if exists public.resolve_org_by_slug(text);

create or replace function public.resolve_org_by_slug(p_slug text)
returns table (id uuid, name text, slug text)
language sql
security definer
set search_path = public
stable
as $$
  select o.id, o.name, o.slug
  from public.organizations o
  where o.slug = lower(trim(p_slug)) and coalesce(o.active, true)
  limit 1;
$$;

revoke all on function public.resolve_org_by_slug(text) from public;
grant execute on function public.resolve_org_by_slug(text) to anon;
grant execute on function public.resolve_org_by_slug(text) to authenticated;

-- Verify after running:
--   select proname from pg_proc where proname = 'verify_org_pin';
--   \d org_members   -- confirm pin, pin_hash columns present
--   \d org_pin_attempts
