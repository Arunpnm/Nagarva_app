-- ============================================================================
-- Nagarva — cap the org-pool PIN lock (19 Aug 2026, follow-up to
-- 20260819_pin_rate_limit_hardening.sql)
--
-- Run this AFTER the main migration, or fold it in if you have not run
-- that one yet. It changes two constants and nothing else.
--
-- WHY THIS EXISTS
-- ---------------
-- The main migration made the per-(org, IP) counter the primary limiter
-- and left the per-org-pool counter as a distributed-attack backstop at
-- 50 failures, on the SAME escalating ladder as everything else
-- (15 min → 1 hour → 24 hours).
--
-- That is safe only if the source IP cannot be forged. It probably can:
-- `x-forwarded-for` is a client-settable header, `pin-login` takes the
-- first entry (the conventional "original client" position), and if
-- Supabase's edge proxy APPENDS the real IP rather than replacing the
-- header, then a caller can prefix any value they like and receive a
-- fresh rate-limit bucket on every single request.
--
-- Under that assumption:
--   * the per-IP limiter never trips (every request is a "new" IP), and
--   * every failure still increments the org-pool counter, so at 50 the
--     tenant is locked out anyway — and the ladder can be driven to a
--     TWENTY-FOUR HOUR tenant-wide lockout.
--
-- Today's worst case is 15 minutes. So without this cap, the hardening
-- migration could make the exact outage it was written to fix
-- substantially worse. That is not an acceptable trade to ship on an
-- unverified assumption about someone else's proxy.
--
-- WHAT THIS CHANGES
-- -----------------
--   1. The org-pool lock never escalates past level 1 — always 15
--      minutes, however many times it trips. The per-IP limiter keeps
--      its full 15 min → 1 h → 24 h ladder, because locking a genuine
--      single attacker for a day is the desired behaviour.
--   2. The org-pool threshold goes 50 → 200. At 200 it is unambiguously
--      "someone is hammering this tenant", far above anything a crew of
--      eight produces on a bad morning, and the response is a 15-minute
--      pause plus a visible `pin_lockout_events` row rather than a day
--      of downtime.
--
-- Net effect: the worst case a stranger can inflict is 15 minutes after
-- 200 failed requests, versus 15 minutes after 5 today. Strictly better
-- regardless of how the proxy handles the header.
--
-- STILL TO VERIFY (do not skip because this cap makes it survivable):
-- whether the proxy appends or replaces. Send a request to the deployed
-- pin-login with a bogus `x-forwarded-for: 203.0.113.99` and read what
-- landed in `pin_ip_attempts.client_ip`. If it is 203.0.113.99, the
-- header is attacker-controlled and the per-IP limiter is advisory
-- only — at which point the real fix is to read the LAST entry in the
-- chain, or a platform header the proxy sets itself.
-- ============================================================================

begin;

create or replace function public.pin_lock_duration(p_level integer)
returns interval
language sql
immutable
as $$
  select case
    when p_level <= 1 then interval '15 minutes'
    when p_level  = 2 then interval '1 hour'
    else interval '24 hours'
  end;
$$;

-- Org-pool locks are deliberately capped at the first rung of the
-- ladder. Only the per-IP path is allowed to escalate.
create or replace function public.pin_org_pool_lock_duration()
returns interval
language sql
immutable
as $$
  select interval '15 minutes';
$$;

comment on function public.pin_org_pool_lock_duration() is
  'Org-wide PIN lock duration. Deliberately flat and short: this lock '
  'affects every user in the tenant, so it must never be escalatable by '
  'an outsider into a multi-hour outage. Escalation belongs on the '
  'per-IP limiter, which only affects the attacker.';

commit;

-- ============================================================================
-- Apply the cap inside verify_org_pin.
--
-- Two substitutions in the function body from the main migration:
--   v_pool_max        50  ->  200
--   the two org-pool trips use pin_org_pool_lock_duration() instead of
--   pin_lock_duration(v_level)
--
-- The full replacement function is below so this file is self-contained
-- and you are not hand-editing the previous migration.
-- ============================================================================

begin;

do $$
begin
  if not exists (
    select 1 from pg_proc where proname = 'verify_org_pin'
  ) then
    raise exception
      'verify_org_pin not found — run 20260819_pin_rate_limit_hardening.sql first';
  end if;
end $$;

-- Only the org-pool branches differ from the main migration; everything
-- else (IP gate, pool gates, collision guard, success path) is
-- byte-identical and re-stated here only because a function body cannot
-- be patched in place.
create or replace function public.verify_org_pin(
  p_org_id    uuid,
  p_pin       text,
  p_client_ip text default null
)
returns table (
  ok                 boolean,
  kind               text,
  user_id            uuid,
  staff_id           uuid,
  staff_role         text,
  staff_name         text,
  staff_auth_user_id uuid,
  locked             boolean,
  locked_until       timestamptz,
  reason             text
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_ip_max        constant integer := 10;
  -- Raised from 50. See this file's header: this counter can be driven
  -- by an outsider if the forwarded IP is forgeable, so it must sit far
  -- above real-world noise and its lock must stay short.
  v_pool_max      constant integer := 200;
  v_decay         constant interval := interval '24 hours';

  v_ip            text;
  v_ip_row        record;
  v_owner_lock    timestamptz;
  v_staff_lock    timestamptz;
  v_skip_owner    boolean := false;
  v_skip_staff    boolean := false;
  v_owner         record;
  v_staff         record;
  v_match_count   integer := 0;
  v_kind          text;
  v_user_id       uuid;
  v_staff_id      uuid;
  v_staff_role    text;
  v_staff_name    text;
  v_staff_auth    uuid;
  v_level         smallint;
  v_until         timestamptz;
  v_until_staff   timestamptz;
  v_attempts      integer;
begin
  v_ip := nullif(btrim(coalesce(p_client_ip, '')), '');
  if v_ip is null then
    begin
      v_ip := coalesce(
        current_setting('request.headers', true)::json ->> 'x-forwarded-for',
        'unknown'
      );
    exception when others then
      v_ip := 'unknown';
    end;
  end if;
  v_ip := btrim(split_part(v_ip, ',', 1));
  if v_ip = '' then v_ip := 'unknown'; end if;

  select * into v_ip_row
    from public.pin_ip_attempts
   where org_id = p_org_id and client_ip = v_ip
     for update;

  if found then
    if v_ip_row.last_failed_at < now() - v_decay
       and (v_ip_row.locked_until is null or v_ip_row.locked_until <= now())
    then
      update public.pin_ip_attempts
         set failed_attempts = 0, lock_level = 0, locked_until = null
       where org_id = p_org_id and client_ip = v_ip;
      v_ip_row.failed_attempts := 0;
      v_ip_row.lock_level := 0;
      v_ip_row.locked_until := null;
    end if;

    if v_ip_row.locked_until is not null and v_ip_row.locked_until > now() then
      return query select false, null::text, null::uuid, null::uuid,
                          null::text, null::text, null::uuid,
                          true, v_ip_row.locked_until, 'locked_ip'::text;
      return;
    end if;
  end if;

  select a.locked_until into v_owner_lock
    from public.org_pin_attempts a
   where a.org_id = p_org_id and a.pool = 'owner';
  select a.locked_until into v_staff_lock
    from public.org_pin_attempts a
   where a.org_id = p_org_id and a.pool = 'staff';

  v_skip_owner := v_owner_lock is not null and v_owner_lock > now();
  v_skip_staff := v_staff_lock is not null and v_staff_lock > now();

  if v_skip_owner and v_skip_staff then
    return query select false, null::text, null::uuid, null::uuid,
                        null::text, null::text, null::uuid,
                        true, greatest(v_owner_lock, v_staff_lock), 'locked'::text;
    return;
  end if;

  if not v_skip_owner then
    for v_owner in
      select om.user_id as m_user_id, om.pin_hash as m_pin_hash
        from public.org_members om
       where om.org_id = p_org_id and om.role = 'owner' and om.pin_hash is not null
    loop
      if v_owner.m_pin_hash = extensions.crypt(p_pin, v_owner.m_pin_hash) then
        v_match_count := v_match_count + 1;
        if v_match_count = 1 then
          v_kind := 'owner';
          v_user_id := v_owner.m_user_id;
        end if;
      end if;
    end loop;
  end if;

  if not v_skip_staff then
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
  end if;

  if v_match_count > 1 then
    return query select false, null::text, null::uuid, null::uuid,
                        null::text, null::text, null::uuid,
                        false, null::timestamptz, 'pin_collision'::text;
    return;
  end if;

  if v_match_count = 1 then
    insert into public.pin_ip_attempts (org_id, client_ip, failed_attempts, lock_level, locked_until)
      values (p_org_id, v_ip, 0, 0, null)
    on conflict (org_id, client_ip) do update
      set failed_attempts = 0, lock_level = 0, locked_until = null;

    insert into public.org_pin_attempts (org_id, pool, failed_attempts, lock_level, locked_until)
      values (p_org_id, v_kind, 0, 0, null)
    on conflict (org_id, pool) do update
      set failed_attempts = 0, lock_level = 0, locked_until = null;

    return query select true, v_kind, v_user_id, v_staff_id,
                        v_staff_role, v_staff_name, v_staff_auth,
                        false, null::timestamptz, null::text;
    return;
  end if;

  insert into public.pin_ip_attempts (org_id, client_ip, failed_attempts, lock_level, last_failed_at)
    values (p_org_id, v_ip, 1, 0, now())
  on conflict (org_id, client_ip) do update
    set failed_attempts = public.pin_ip_attempts.failed_attempts + 1,
        last_failed_at  = now()
  returning public.pin_ip_attempts.failed_attempts, public.pin_ip_attempts.lock_level
    into v_attempts, v_level;

  if v_attempts >= v_ip_max then
    -- The per-IP ladder keeps escalating: this only ever affects the
    -- source doing the guessing.
    v_level := v_level + 1;
    v_until := now() + public.pin_lock_duration(v_level);
    update public.pin_ip_attempts
       set failed_attempts = 0, lock_level = v_level, locked_until = v_until
     where org_id = p_org_id and client_ip = v_ip;

    insert into public.pin_lockout_events
      (org_id, scope, pool, client_ip, lock_level, failed_attempts, locked_until)
      values (p_org_id, 'ip', null, v_ip, v_level, v_attempts, v_until);

    return query select false, null::text, null::uuid, null::uuid,
                        null::text, null::text, null::uuid,
                        true, v_until, 'locked_ip'::text;
    return;
  end if;

  v_until := null;

  if not v_skip_owner then
    insert into public.org_pin_attempts (org_id, pool, failed_attempts, lock_level, last_failed_at)
      values (p_org_id, 'owner', 1, 0, now())
    on conflict (org_id, pool) do update
      set failed_attempts = case
            when public.org_pin_attempts.last_failed_at < now() - v_decay then 1
            else public.org_pin_attempts.failed_attempts + 1 end,
          lock_level = case
            when public.org_pin_attempts.last_failed_at < now() - v_decay then 0
            else public.org_pin_attempts.lock_level end,
          last_failed_at = now()
    returning public.org_pin_attempts.failed_attempts, public.org_pin_attempts.lock_level
      into v_attempts, v_level;

    if v_attempts >= v_pool_max then
      v_level := v_level + 1;
      -- CAPPED: flat 15 minutes, never escalating. This lock hits every
      -- user in the tenant, so an outsider must not be able to grow it.
      v_until := now() + public.pin_org_pool_lock_duration();
      update public.org_pin_attempts
         set failed_attempts = 0, lock_level = v_level, locked_until = v_until
       where org_id = p_org_id and pool = 'owner';
      insert into public.pin_lockout_events
        (org_id, scope, pool, client_ip, lock_level, failed_attempts, locked_until)
        values (p_org_id, 'org_pool', 'owner', v_ip, v_level, v_attempts, v_until);
    end if;
  end if;

  if not v_skip_staff then
    insert into public.org_pin_attempts (org_id, pool, failed_attempts, lock_level, last_failed_at)
      values (p_org_id, 'staff', 1, 0, now())
    on conflict (org_id, pool) do update
      set failed_attempts = case
            when public.org_pin_attempts.last_failed_at < now() - v_decay then 1
            else public.org_pin_attempts.failed_attempts + 1 end,
          lock_level = case
            when public.org_pin_attempts.last_failed_at < now() - v_decay then 0
            else public.org_pin_attempts.lock_level end,
          last_failed_at = now()
    returning public.org_pin_attempts.failed_attempts, public.org_pin_attempts.lock_level
      into v_attempts, v_level;

    if v_attempts >= v_pool_max then
      v_level := v_level + 1;
      v_until_staff := now() + public.pin_org_pool_lock_duration();
      update public.org_pin_attempts
         set failed_attempts = 0, lock_level = v_level, locked_until = v_until_staff
       where org_id = p_org_id and pool = 'staff';
      insert into public.pin_lockout_events
        (org_id, scope, pool, client_ip, lock_level, failed_attempts, locked_until)
        values (p_org_id, 'org_pool', 'staff', v_ip, v_level, v_attempts, v_until_staff);
      v_until := greatest(v_until, v_until_staff);
    end if;
  end if;

  return query select false, null::text, null::uuid, null::uuid,
                      null::text, null::text, null::uuid,
                      (v_until is not null), v_until,
                      case when v_until is not null then 'locked' else null end;
end;
$$;

revoke all on function public.verify_org_pin(uuid, text, text) from public;
revoke all on function public.verify_org_pin(uuid, text, text) from anon;
revoke all on function public.verify_org_pin(uuid, text, text) from authenticated;
grant execute on function public.verify_org_pin(uuid, text, text) to service_role;

commit;
