-- ============================================================================
-- Nagarva — PIN rate-limit hardening (19 Aug 2026, MERGED + GUARDED)
--
-- Supersedes and replaces BOTH:
--   supabase/20260819_pin_rate_limit_hardening.sql   (main)
--   supabase/20260819b_pin_org_pool_lock_cap.sql     (cap)
-- Do not run either of those again. This file is the whole change, in
-- ONE transaction.
--
-- WHY IT IS MERGED
-- ----------------
-- Splitting it in two produced a half-applied security migration. The
-- main file was correctly wrapped in begin/commit and DID roll back
-- cleanly. The cap file then ran on top of nothing and succeeded,
-- because it creates two functions plus a 3-argument verify_org_pin and
-- creates no tables at all — leaving a live function querying
-- pin_ip_attempts, which did not exist. Org-code PIN login went down
-- with 42P01 on every call.
--
-- The cap's precondition guard was:
--     if not exists (select 1 from pg_proc where proname='verify_org_pin')
-- which the pre-existing 2-argument version satisfied, so it could never
-- fire. IT CHECKED THE TARGET IT WAS REPLACING, NOT THE DEPENDENCY IT
-- NEEDED. That is the same defect shape as the is_platform_admin()
-- deadlock in delete_org(): a guard that reads true for the wrong
-- reason, and therefore protects nothing.
--
-- Both lessons are applied below:
--   * one file, one transaction — nothing can be half-applied
--   * a PREFLIGHT guard that asserts every DEPENDENCY this migration
--     consumes, and a POSTFLIGHT guard that asserts every OBJECT it is
--     supposed to produce. If either fails, the whole thing rolls back
--     and the database is exactly as it was.
--
-- WHAT IT DOES (unchanged from the two files it replaces)
-- ------------------------------------------------------
-- org_pin_attempts was keyed on org_id alone, so five wrong PINs locked
-- out the owner and every active staff member for 15 minutes. The slug
-- is public and resolve_org_by_slug is anon-callable, so a stranger
-- could take a tenant offline for five HTTP requests, repeatedly. The
-- lockout throttled the victim, never the attacker.
--
--   1. pin_ip_attempts (org_id, client_ip) becomes the primary limiter
--      at 10 failures — deliberately looser than the old per-org 5,
--      because a crew on one warehouse hotspot shares a public IP, and
--      any success from that IP clears the bucket.
--   2. Escalating backoff via pin_lock_duration(): 15 min, 1 hour,
--      24 hours, decaying after a clean day. Replaces reset-to-zero on
--      both the org path and the staff path.
--   3. org_pin_attempts is split by pool (owner/staff, composite PK) and
--      retuned to 200 as a distributed-attack backstop only. Its lock is
--      CAPPED at a flat 15 minutes by pin_org_pool_lock_duration() and
--      never escalates: it is the only org-wide lock left, so an
--      outsider must not be able to grow it into a multi-hour outage.
--   4. pin_lockout_events records every lockout, readable by owner and
--      managers under RLS.
--
-- THE IP MUST BE FORWARDED BY THE EDGE FUNCTION
-- ---------------------------------------------
-- verify_org_pin reads PostgREST's request.headers GUC only as a
-- fallback. It is called by pin-login under service_role, so that GUC
-- carries the EDGE FUNCTION's IP — every tenant sharing one bucket, a
-- limiter that reports success while enforcing nothing. p_client_ip
-- defaults to null so this migration is safe to run BEFORE pin-login is
-- redeployed; the exact Edge Function diff is at the bottom of this file.
--
-- Unverified and deliberately capped for: x-forwarded-for is
-- client-settable. If Supabase's proxy appends rather than replaces, the
-- per-IP limiter is advisory. Probe it after deploy (see bottom).
--
-- SAFE TO RE-RUN.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0. PREFLIGHT — assert every DEPENDENCY, not the target
-- ---------------------------------------------------------------------------
-- Checks the things this migration CONSUMES. A guard that checks whether
-- the object being replaced exists is worthless: it is satisfied by the
-- very thing you are about to overwrite.
do $preflight$
declare
  v_missing text[] := '{}';
begin
  if to_regclass('public.organizations')    is null then v_missing := v_missing || 'table organizations'; end if;
  if to_regclass('public.staff')            is null then v_missing := v_missing || 'table staff'; end if;
  if to_regclass('public.org_members')      is null then v_missing := v_missing || 'table org_members'; end if;
  if to_regclass('public.org_pin_attempts') is null then v_missing := v_missing || 'table org_pin_attempts'; end if;

  if not exists (select 1 from pg_proc where proname = 'current_org_ids') then
    v_missing := v_missing || 'function current_org_ids()'; end if;
  if not exists (select 1 from pg_proc where proname = 'is_org_owner') then
    v_missing := v_missing || 'function is_org_owner()'; end if;
  if not exists (select 1 from pg_proc where proname = 'is_org_manager') then
    v_missing := v_missing || 'function is_org_manager()'; end if;

  -- The PIN comparison itself. pgcrypto lives in the `extensions`
  -- schema on Supabase; without it every bcrypt check below is dead.
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where p.proname = 'crypt' and n.nspname = 'extensions'
  ) then v_missing := v_missing || 'extensions.crypt() (pgcrypto)'; end if;

  if not exists (select 1 from pg_proc where proname = 'gen_random_uuid') then
    v_missing := v_missing || 'function gen_random_uuid()'; end if;

  if array_length(v_missing, 1) is not null then
    raise exception
      'PREFLIGHT FAILED — this migration depends on objects that do not exist: %',
      array_to_string(v_missing, ', ');
  end if;
end
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Shared escalation ladders
-- ---------------------------------------------------------------------------
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

-- Only the org-pool branches differ from the main migration; everything
-- else (IP gate, pool gates, collision guard, success path) is
-- byte-identical and re-stated here only because a function body cannot
-- be patched in place.
-- Drop BOTH existing signatures before creating the new one.
--
-- Without this the 2-argument version (restored by the rollback) would
-- survive alongside the new 3-argument one, and because p_client_ip has
-- a DEFAULT, every 2-argument call would match both candidates and fail
-- with 42725, ambiguous function call. That is exactly the state the
-- rollback initially left behind.
--
-- This omission was inherited from the cap file, which had no drop
-- because it assumed the 3-arg function already existed. It was caught
-- by the POSTFLIGHT guard at the end of this file asserting "exactly one
-- verify_org_pin signature" — which is precisely the job that guard
-- exists to do.
drop function if exists public.verify_org_pin(uuid, text);
drop function if exists public.verify_org_pin(uuid, text, text);

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
grant execute on function public.verify_org_pin(uuid, text, text) to service_role;-- ---------------------------------------------------------------------------
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
-- ---------------------------------------------------------------------------
-- 7. POSTFLIGHT — assert every object this migration was supposed to create
-- ---------------------------------------------------------------------------
-- The half-applied state that took org-code login down would have been
-- caught here and rolled back. Everything is still inside the same
-- transaction, so a failure leaves the database exactly as it was.
do $postflight$
declare
  v_missing text[] := '{}';
begin
  -- 1
  if to_regclass('public.pin_ip_attempts') is null then
    v_missing := v_missing || 'table pin_ip_attempts'; end if;
  -- 2
  if to_regclass('public.pin_lockout_events') is null then
    v_missing := v_missing || 'table pin_lockout_events'; end if;
  -- 3
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'org_pin_attempts'
       and column_name = 'pool'
  ) then v_missing := v_missing || 'column org_pin_attempts.pool'; end if;
  -- 4
  if not exists (
    select 1 from pg_proc
     where proname = 'verify_org_pin'
       and pg_get_function_identity_arguments(oid)
           = 'p_org_id uuid, p_pin text, p_client_ip text'
  ) then v_missing := v_missing || 'function verify_org_pin(uuid,text,text)'; end if;
  -- 5
  if not exists (select 1 from pg_proc where proname = 'pin_org_pool_lock_duration') then
    v_missing := v_missing || 'function pin_org_pool_lock_duration()'; end if;

  -- supporting objects, asserted for the same reason
  if not exists (select 1 from pg_proc where proname = 'pin_lock_duration') then
    v_missing := v_missing || 'function pin_lock_duration()'; end if;
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'staff'
       and column_name = 'pin_lock_level'
  ) then v_missing := v_missing || 'column staff.pin_lock_level'; end if;

  -- The old single-column PK must be gone, or the pool split is a lie.
  if (select coalesce(array_length(conkey, 1), 0)
        from pg_constraint
       where conrelid = 'public.org_pin_attempts'::regclass and contype = 'p') <> 2
  then v_missing := v_missing || 'composite PK on org_pin_attempts(org_id, pool)'; end if;

  -- Exactly one verify_org_pin signature. Two would make every
  -- 2-argument call ambiguous (42725), which is how the rollback
  -- initially left things.
  if (select count(*) from pg_proc where proname = 'verify_org_pin') <> 1 then
    v_missing := v_missing || 'exactly one verify_org_pin signature';
  end if;

  if array_length(v_missing, 1) is not null then
    raise exception
      'POSTFLIGHT FAILED — rolling back, nothing applied. Missing: %',
      array_to_string(v_missing, ', ');
  end if;

  raise notice 'POSTFLIGHT OK — all objects present.';
end
$postflight$;

commit;

-- ============================================================================
-- VERIFY AFTER RUNNING (read-only) — expect 5 rows, all present = true
-- ============================================================================
-- select 'pin_ip_attempts'                 as object, to_regclass('public.pin_ip_attempts')    is not null as present
-- union all select 'pin_lockout_events',        to_regclass('public.pin_lockout_events') is not null
-- union all select 'org_pin_attempts.pool',     exists (select 1 from information_schema.columns
--                                                 where table_name='org_pin_attempts' and column_name='pool')
-- union all select 'verify_org_pin(3-arg)',     exists (select 1 from pg_proc where proname='verify_org_pin'
--                                                 and pg_get_function_identity_arguments(oid)
--                                                     ='p_org_id uuid, p_pin text, p_client_ip text')
-- union all select 'pin_org_pool_lock_duration', exists (select 1 from pg_proc
--                                                 where proname='pin_org_pool_lock_duration');
--
-- ============================================================================
-- THEN, and only then — deploy pin-login (already committed, not deployed):
--   const clientIp =
--     (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || null;
--   ... admin.rpc("verify_org_pin", { p_org_id, p_pin, p_client_ip: clientIp })
--
-- THEN the XFF probe, BEFORE any lockout test: one failed attempt with
--   x-forwarded-for: 203.0.113.99
-- then  select client_ip from pin_ip_attempts order by last_failed_at desc limit 1;
-- If 203.0.113.99 landed, the header is attacker-controlled and the
-- per-IP limiter is advisory only — stop and rethink before testing the
-- ladder. If the real IP landed, proceed to the 11-failure test.
-- ============================================================================
