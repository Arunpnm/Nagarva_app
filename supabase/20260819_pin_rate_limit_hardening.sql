-- ============================================================================
-- Nagarva — PIN rate-limit hardening (19 Aug 2026)
--
-- Standalone. Ships BEFORE any binding-model change, because the problem
-- it fixes is live right now.
--
-- THE OUTAGE THIS FIXES
-- ---------------------
-- `org_pin_attempts` is keyed on `org_id` alone, so the failure counter
-- is per TENANT. Five wrong PINs lock out the owner AND every active
-- staff member for 15 minutes. The org slug is public and
-- `resolve_org_by_slug` is anon-callable, so any stranger can do this
-- for the cost of five HTTP requests, repeatedly, indefinitely.
--
-- Arun, 19 Aug 2026: "my whole crew locked out on a moving day for five
-- HTTP requests. That's an outage I can be given by a stranger."
--
-- The lockout throttled the VICTIM, never the attacker. That inversion
-- is the actual bug; the 5/15 numbers were never the problem.
--
-- Second defect: the counter RESET TO ZERO when it tripped
--     failed_attempts = case when +1 >= 5 then 0 else +1 end
-- so lockouts never compounded. Sustained guessing ran at a flat
-- 5 per 15 min = 480/day forever. Against the org-code path each guess
-- is tested against every PIN in the org at once (APC today: 8 staff +
-- 1 owner = 9), so expected guesses to hit SOME account is about
-- 10,000/9 ≈ 1,111 → roughly 2.3 days of unattended traffic.
--
-- WHAT CHANGES
-- ------------
--   1. A per-(org, IP) counter becomes the primary limiter. It locks the
--      SOURCE, so one attacker cannot take a tenant offline.
--   2. Escalating backoff (15 min → 1 hour → 24 hours) replaces
--      reset-to-zero, with decay after a clean 24 hours.
--   3. The per-org counter survives but is SPLIT BY POOL (owner vs
--      staff) and re-tuned as a distributed-attack backstop only, at a
--      threshold a fat-fingered packer can never reach. A packer
--      mistyping five times can no longer lock the owner out.
--   4. Every lockout writes a `pin_lockout_events` row the owner can
--      read, so a sustained attack stops being invisible.
--
-- ############################################################################
-- ## READ THIS BEFORE DEPLOYING — the GUC alone does NOT work here.        ##
-- ############################################################################
--
-- `is_invite_code_valid` reads the caller's IP from PostgREST's
-- `request.headers` GUC, and that is correct THERE because the Dart
-- client calls it directly over PostgREST.
--
-- `verify_org_pin` is different: it is called by the `pin-login` Edge
-- Function under service_role. The GUC would therefore carry the EDGE
-- FUNCTION's outbound request headers, not the end user's — every
-- vendor on earth would share one bucket, and the limiter would look
-- like it worked while enforcing nothing.
--
-- So the function takes `p_client_ip`, which the Edge Function must
-- pass from its own `req.headers`. The GUC remains as a fallback for
-- any direct PostgREST caller.
--
-- DEPLOY ORDER
--   1. Run this migration. `p_client_ip` defaults to null, so the
--      currently deployed 2-argument call keeps working — it simply
--      falls back to the GUC/shared bucket until step 2.
--   2. Deploy `pin-login` with the IP forwarded (see the companion note
--      at the bottom of this file for the exact change).
--   Doing it in this order means there is no window where login breaks.
--
-- SAFE TO RE-RUN: every DDL statement is IF NOT EXISTS / idempotent, and
-- the function bodies are CREATE OR REPLACE after an explicit DROP.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Shared escalation ladder
-- ---------------------------------------------------------------------------
-- One place defines how long each successive lockout lasts, so the org
-- path and the staff path cannot drift apart.
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

comment on function public.pin_lock_duration(integer) is
  'Escalating PIN lockout ladder: 15 min, then 1 hour, then 24 hours. '
  'Replaces the old flat 15-minute lock that reset its counter on every '
  'trip and so never compounded.';

-- ---------------------------------------------------------------------------
-- 2. Per-(org, IP) counter — the primary limiter
-- ---------------------------------------------------------------------------
create table if not exists public.pin_ip_attempts (
  org_id          uuid        not null references public.organizations(id) on delete cascade,
  client_ip       text        not null,
  failed_attempts integer     not null default 0,
  lock_level      smallint    not null default 0,
  locked_until    timestamptz,
  last_failed_at  timestamptz not null default now(),
  primary key (org_id, client_ip)
);

comment on table public.pin_ip_attempts is
  'Per-(org, source IP) PIN failure counter. This is the limiter that '
  'actually defends the tenant: it throttles the attacker rather than '
  'the company being attacked.';

create index if not exists pin_ip_attempts_locked_idx
  on public.pin_ip_attempts (org_id, locked_until)
  where locked_until is not null;

alter table public.pin_ip_attempts enable row level security;
-- No policies: only SECURITY DEFINER functions touch this table.

-- ---------------------------------------------------------------------------
-- 3. Split the per-org counter by pool, and give it a level
-- ---------------------------------------------------------------------------
-- `pool` distinguishes the owner PIN pool from the staff PIN pool so a
-- staff member repeatedly mistyping cannot lock the owner out of their
-- own tenant.
alter table public.org_pin_attempts
  add column if not exists pool           text        not null default 'staff';
alter table public.org_pin_attempts
  add column if not exists lock_level     smallint    not null default 0;
alter table public.org_pin_attempts
  add column if not exists last_failed_at timestamptz not null default now();

-- Repoint the primary key at (org_id, pool). Done by discovering the
-- existing constraint name rather than assuming `org_pin_attempts_pkey`.
do $$
declare
  v_pk text;
begin
  select conname into v_pk
  from pg_constraint
  where conrelid = 'public.org_pin_attempts'::regclass and contype = 'p';

  if v_pk is not null then
    -- Already migrated? Then the PK covers two columns and we leave it.
    if (select coalesce(array_length(conkey, 1), 0)
          from pg_constraint
         where conname = v_pk
           and conrelid = 'public.org_pin_attempts'::regclass) = 1
    then
      execute format('alter table public.org_pin_attempts drop constraint %I', v_pk);
      alter table public.org_pin_attempts add primary key (org_id, pool);
    end if;
  else
    alter table public.org_pin_attempts add primary key (org_id, pool);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.org_pin_attempts'::regclass
      and conname = 'org_pin_attempts_pool_chk'
  ) then
    alter table public.org_pin_attempts
      add constraint org_pin_attempts_pool_chk check (pool in ('owner', 'staff'));
  end if;
end $$;

-- Any pre-existing row predates the split. Clear it rather than
-- guessing which pool its failures belonged to — carrying an
-- unattributable count forward could lock somebody out on day one for
-- attempts made under the old rules.
update public.org_pin_attempts
   set failed_attempts = 0, lock_level = 0, locked_until = null
 where locked_until is not null or failed_attempts > 0;

-- ---------------------------------------------------------------------------
-- 4. Lockout events the owner can actually see
-- ---------------------------------------------------------------------------
create table if not exists public.pin_lockout_events (
  id              uuid        primary key default gen_random_uuid(),
  org_id          uuid        not null references public.organizations(id) on delete cascade,
  scope           text        not null check (scope in ('ip', 'org_pool', 'staff')),
  pool            text        check (pool in ('owner', 'staff')),
  staff_id        uuid        references public.staff(id) on delete set null,
  client_ip       text,
  lock_level      smallint    not null,
  failed_attempts integer     not null,
  locked_until    timestamptz not null,
  created_at      timestamptz not null default now()
);

comment on table public.pin_lockout_events is
  'One row per PIN lockout. Exists so a sustained guessing attack is '
  'visible to the vendor instead of silently throttling in the dark.';

create index if not exists pin_lockout_events_org_time_idx
  on public.pin_lockout_events (org_id, created_at desc);

alter table public.pin_lockout_events enable row level security;

-- Readable by the org's owner and managers (managers keep org-code
-- access per Arun's 19 Aug 2026 decision, so they are also the people
-- who will be told "I can't log in"). Insert happens only inside
-- SECURITY DEFINER functions, so there is no INSERT policy.
drop policy if exists pin_lockout_events_read on public.pin_lockout_events;
create policy pin_lockout_events_read
  on public.pin_lockout_events
  for select
  to authenticated
  using (
    org_id in (select public.current_org_ids())
    and (public.is_org_owner(org_id) or public.is_org_manager(org_id))
  );

-- ---------------------------------------------------------------------------
-- 5. verify_org_pin — IP-first, escalating, pool-split
-- ---------------------------------------------------------------------------
-- Signature changes (new p_client_ip argument), so an explicit DROP is
-- required first: CREATE OR REPLACE cannot do it and would raise 42P13.
-- See CLAUDE.md, "Conventions for Claude Code sessions".
drop function if exists public.verify_org_pin(uuid, text);
drop function if exists public.verify_org_pin(uuid, text, text);

create or replace function public.verify_org_pin(
  p_org_id    uuid,
  p_pin       text,
  p_client_ip text default null
)
returns table (
  ok                 boolean,
  kind               text,        -- 'owner' | 'staff'
  user_id            uuid,
  staff_id           uuid,
  staff_role         text,
  staff_name         text,
  staff_auth_user_id uuid,
  locked             boolean,
  locked_until       timestamptz,
  reason             text         -- 'locked' | 'locked_ip' | 'pin_collision'
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  -- Per-IP: deliberately more forgiving than the old per-org 5, because
  -- a whole crew on one warehouse hotspot shares a public IP. A single
  -- success from that IP clears the bucket, which is what makes the
  -- shared-NAT case self-healing.
  v_ip_max        constant integer := 10;
  -- Per-org-pool: a distributed-attack backstop ONLY. Set far above
  -- anything human error produces, so five fat-fingered attempts by a
  -- packer can never lock the owner out.
  v_pool_max      constant integer := 50;
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
  -- ---- Resolve the caller's IP -------------------------------------------
  -- Parameter first (the Edge Function forwards the real client IP);
  -- the PostgREST GUC second, for a direct caller; 'unknown' last, which
  -- is a single shared bucket and is meant to be conservative.
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

  -- ---- IP gate, checked before any bcrypt work ---------------------------
  select * into v_ip_row
    from public.pin_ip_attempts
   where org_id = p_org_id and client_ip = v_ip
     for update;

  if found then
    -- Decay a stale bucket so an honest user who failed twice last week
    -- doesn't start today part-way up the ladder.
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

  -- ---- Per-pool gates ----------------------------------------------------
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

  -- ---- Pool 1: owner -----------------------------------------------------
  -- Column aliasing (m_*) is load-bearing: this function's OUT parameters
  -- are in scope as plpgsql variables, and a bare column reference that
  -- matches one raises 42702. Hit live; do not "simplify" it away.
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

  -- ---- Pool 2: staff (active only) --------------------------------------
  -- Still NOT skipped just because the owner pool matched — that early
  -- exit was the original privilege-escalation bug (20260729).
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

  -- ---- Ambiguous: refuse, and touch no counter --------------------------
  -- Unchanged from 20260729. The PIN was correct; the configuration is
  -- wrong. Counting it would punish two users for an admin mistake.
  if v_match_count > 1 then
    return query select false, null::text, null::uuid, null::uuid,
                        null::text, null::text, null::uuid,
                        false, null::timestamptz, 'pin_collision'::text;
    return;
  end if;

  -- ---- Success: clear this IP and the pool that matched ------------------
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

  -- ---- Failure: charge the IP first --------------------------------------
  insert into public.pin_ip_attempts (org_id, client_ip, failed_attempts, lock_level, last_failed_at)
    values (p_org_id, v_ip, 1, 0, now())
  on conflict (org_id, client_ip) do update
    set failed_attempts = public.pin_ip_attempts.failed_attempts + 1,
        last_failed_at  = now()
  returning public.pin_ip_attempts.failed_attempts, public.pin_ip_attempts.lock_level
    into v_attempts, v_level;

  if v_attempts >= v_ip_max then
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

  -- ---- Then the distributed backstop, on the pools actually searched -----
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
      v_until := now() + public.pin_lock_duration(v_level);
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
      -- Its OWN duration. Using greatest() here would let an owner-pool
      -- trip silently extend the staff lock, which is exactly the
      -- cross-contamination this split exists to prevent.
      v_until_staff := now() + public.pin_lock_duration(v_level);
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

-- ---------------------------------------------------------------------------
-- 6. verify_staff_pin — same escalation ladder
-- ---------------------------------------------------------------------------
-- This path is per-staff-row and so was never a tenant-wide DoS, which is
-- why it is not the headline. But it carried the identical
-- reset-to-zero flaw, and leaving a known-identical defect in the
-- sibling function is how it comes back later. Signature is UNCHANGED,
-- so `staff-login` needs no redeploy for this part.
alter table public.staff
  add column if not exists pin_lock_level smallint not null default 0;

drop function if exists public.verify_staff_pin(uuid, text);

create or replace function public.verify_staff_pin(p_staff_id uuid, p_pin text)
returns table (
  ok           boolean,
  org_id       uuid,
  role         text,
  name         text,
  auth_user_id uuid,
  locked       boolean,
  locked_until timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_staff       record;
  v_ok          boolean;
  v_max         constant integer := 5;
  v_decay       constant interval := interval '24 hours';
  v_level       smallint;
  v_until       timestamptz;
begin
  select s.pin_hash, s.org_id, s.role, s.name, s.auth_user_id,
         s.failed_pin_attempts, s.pin_locked_until, s.pin_lock_level, s.active
    into v_staff
  from public.staff s
  where s.id = p_staff_id;

  if not found or coalesce(v_staff.active, false) = false then
    return query select false, null::uuid, null::text, null::text,
                        null::uuid, false, null::timestamptz;
    return;
  end if;

  -- Inside an existing lockout: don't check the PIN at all, so behaviour
  -- and timing leak nothing to a locked-out attacker.
  if v_staff.pin_locked_until is not null and v_staff.pin_locked_until > now() then
    return query select false, v_staff.org_id, v_staff.role, v_staff.name,
                        v_staff.auth_user_id, true, v_staff.pin_locked_until;
    return;
  end if;

  v_ok := v_staff.pin_hash is not null
      and v_staff.pin_hash = extensions.crypt(p_pin, v_staff.pin_hash);

  if v_ok then
    update public.staff
       set failed_pin_attempts = 0, pin_locked_until = null, pin_lock_level = 0
     where id = p_staff_id;
    return query select true, v_staff.org_id, v_staff.role, v_staff.name,
                        v_staff.auth_user_id, false, null::timestamptz;
    return;
  end if;

  -- Decay a stale ladder before counting this failure.
  v_level := v_staff.pin_lock_level;
  if v_staff.pin_locked_until is not null
     and v_staff.pin_locked_until < now() - v_decay then
    v_level := 0;
  end if;

  if v_staff.failed_pin_attempts + 1 >= v_max then
    v_level := v_level + 1;
    v_until := now() + public.pin_lock_duration(v_level);
    update public.staff
       set failed_pin_attempts = 0,
           pin_locked_until    = v_until,
           pin_lock_level      = v_level
     where id = p_staff_id;

    insert into public.pin_lockout_events
      (org_id, scope, pool, staff_id, client_ip, lock_level, failed_attempts, locked_until)
      values (v_staff.org_id, 'staff', 'staff', p_staff_id, null, v_level, v_max, v_until);

    return query select false, v_staff.org_id, v_staff.role, v_staff.name,
                        v_staff.auth_user_id, true, v_until;
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

commit;

-- ============================================================================
-- STEP 2 — the pin-login Edge Function change (deploy AFTER this migration)
-- ============================================================================
-- Without this the limiter still runs, but every caller shares the
-- 'unknown' bucket because the GUC sees the Edge Function's own IP.
--
--   const clientIp = (req.headers.get("x-forwarded-for") ?? "")
--     .split(",")[0].trim() || null;
--
--   const { data: rows, error: vErr } = await admin.rpc("verify_org_pin", {
--     p_org_id: org_id,
--     p_pin: String(pin),
--     p_client_ip: clientIp,          // <-- add this
--   });
--
-- The function already returns reason = 'locked_ip' for a source lock
-- versus 'locked' for a pool lock; both set `locked` true and carry
-- `locked_until`, so the existing user-facing message keeps working with
-- no change. Differentiating the copy ("too many attempts from this
-- device/network") is a nicety, not a requirement.
--
-- VERIFY AFTER DEPLOY (read-only):
--   select scope, pool, client_ip, lock_level, locked_until, created_at
--     from pin_lockout_events order by created_at desc limit 20;
--   select * from pin_ip_attempts where locked_until > now();
-- ============================================================================
