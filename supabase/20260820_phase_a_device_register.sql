-- ============================================================================
-- Nagarva — Phase A: device register + offboarding (20 Aug 2026)
--
-- Phase A BUILDS THE RAILS AND ENFORCES NOTHING. Every device that works
-- today keeps working after this runs. No login path becomes stricter,
-- no PIN pool narrows, no staff member is cut off. That is deliberate:
-- the numbers say 4 invites have ever been redeemed across 3 devices,
-- so enforcement before the rails exist would strand nearly every phone
-- in the field.
--
-- WHY THE REGISTER IS WRITTEN AT LOGIN, NOT AT BIND
-- -------------------------------------------------
-- Binding an org-code device never touches the server: it is
-- `resolve_org_by_slug` (anon) followed by a local SharedPreferences
-- write. So bind time is INVISIBLE for roughly every device currently in
-- the field, and cannot be the write point. Login can be: `pin-login`
-- and `staff-login` both mint a session inside an Edge Function, and
-- both binding paths pass through one of them, so a single chokepoint
-- covers everyone with no new client plumbing.
--
-- WHAT THIS BUYS THAT DOES NOT EXIST TODAY: REMOTE REVOCATION
-- -----------------------------------------------------------
-- `DeviceOrgBinding.unbind()` is a local call — it can only be triggered
-- from the device you are trying to cut off, which is useless for a
-- phone that has left the building. With this register both verify paths
-- refuse a revoked device_id, and Revoke becomes a real button.
--
-- THE HONEST LIMIT, WHICH THE UI MUST ALSO STATE
-- ----------------------------------------------
-- `device_id` is client-generated and not attested. Reinstalling the app
-- yields a new one. So revoke stops THAT INSTALL, not that person. The
-- person-level boundary is still `staff.active`, which is why
-- `offboard_staff()` below exists and why it ships in the same phase.
-- This register is an operational tool and an audit trail. It is not a
-- security boundary and nothing in the interface may imply it is.
--
-- ON last_client_ip
-- -----------------
-- Recorded because it is already in hand — `pin-login` forwards it for
-- the per-IP limiter, and the 19 Aug XFF probe proved it is the real
-- egress IP rather than an attacker-supplied header.
--
-- FORENSIC, NOT AN ALARM. Crews work on mobile data behind CGNAT, where
-- the address changes between job sites, between cell handovers and on
-- every reconnect; a supervisor crossing Chennai produces several "new
-- locations" before lunch. Alerting on IP change would be muted long
-- before the one real event. It answers "where did this device log in
-- from, and when" while investigating — a question that cannot be
-- answered later if the value was never stored.
--
-- The low-noise re-binding signal is `is_new_device` below: a device_id
-- never seen before for a staff_id that already had one. That is the
-- literal shape of "they came back on another phone", and it is rare
-- enough in normal operation to carry a notification.
--
-- DPDP: latest value per device, never an append-only history, and rows
-- are pruned on offboard. This must not become a movement log of every
-- employee.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0. PREFLIGHT — assert every DEPENDENCY this migration consumes
-- ---------------------------------------------------------------------------
-- Checks what is NEEDED, never what is being replaced. A guard satisfied
-- by the thing you are about to overwrite protects nothing — see
-- 20260819_pin_rate_limit_hardening.sql's header for the incident that
-- taught this.
do $preflight$
declare
  v_missing text[] := '{}';
begin
  if to_regclass('public.organizations') is null then v_missing := v_missing || 'table organizations'; end if;
  if to_regclass('public.staff')         is null then v_missing := v_missing || 'table staff'; end if;
  if to_regclass('public.org_members')   is null then v_missing := v_missing || 'table org_members'; end if;
  if to_regclass('public.staff_invites') is null then v_missing := v_missing || 'table staff_invites'; end if;

  if not exists (select 1 from pg_proc where proname = 'current_org_ids') then
    v_missing := v_missing || 'function current_org_ids()'; end if;
  if not exists (select 1 from pg_proc where proname = 'is_org_owner') then
    v_missing := v_missing || 'function is_org_owner()'; end if;
  if not exists (select 1 from pg_proc where proname = 'is_org_manager') then
    v_missing := v_missing || 'function is_org_manager()'; end if;
  if not exists (select 1 from pg_proc where proname = 'gen_random_uuid') then
    v_missing := v_missing || 'function gen_random_uuid()'; end if;

  -- staff.active is the actual security boundary offboard_staff() sets.
  if not exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='staff' and column_name='active'
  ) then v_missing := v_missing || 'column staff.active'; end if;

  if array_length(v_missing, 1) is not null then
    raise exception 'PREFLIGHT FAILED — missing dependencies: %',
      array_to_string(v_missing, ', ');
  end if;
end
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. The register
-- ---------------------------------------------------------------------------
create table if not exists public.device_bindings (
  org_id          uuid        not null references public.organizations(id) on delete cascade,
  device_id       text        not null,
  staff_id        uuid        references public.staff(id) on delete cascade,
  kind            text        not null check (kind in ('owner', 'staff')),
  label           text,
  first_seen      timestamptz not null default now(),
  last_seen       timestamptz not null default now(),
  -- Latest value only. Deliberately not a history table — see header.
  last_client_ip  text,
  revoked_at      timestamptz,
  revoked_by      uuid,
  primary key (org_id, device_id)
);

comment on table public.device_bindings is
  'One row per (org, device install) seen at login. Operational tool and '
  'audit trail, NOT a security boundary: device_id is client-generated '
  'and a reinstall produces a new one, so revoking stops that install, '
  'not that person. staff.active remains the person-level boundary.';

comment on column public.device_bindings.last_client_ip is
  'Latest login IP. Forensic only — never alert on a change. Mobile '
  'CGNAT reassigns addresses constantly, so "new location" would fire on '
  'a normal working day and be muted before it mattered.';

create index if not exists device_bindings_org_staff_idx
  on public.device_bindings (org_id, staff_id);

create index if not exists device_bindings_active_idx
  on public.device_bindings (org_id, last_seen desc)
  where revoked_at is null;

alter table public.device_bindings enable row level security;

-- Owner and managers read their own org's devices. All writes go through
-- the SECURITY DEFINER functions below, so there is no write policy.
drop policy if exists device_bindings_read on public.device_bindings;
create policy device_bindings_read
  on public.device_bindings
  for select
  to authenticated
  using (
    org_id in (select public.current_org_ids())
    and (public.is_org_owner(org_id) or public.is_org_manager(org_id))
  );

-- ---------------------------------------------------------------------------
-- 2. record_device_login() — called by pin-login / staff-login
-- ---------------------------------------------------------------------------
-- Upserts the row and reports back two things the caller acts on:
--   revoked        -> the Edge Function must REFUSE the login
--   is_new_device  -> a device_id never seen for a staff member who
--                     already had one; the re-binding signal
--
-- Fails OPEN on everything except revocation: a device with no row is
-- simply new, never blocked. Phase A must not lock anybody out, and a
-- register that started rejecting unknown devices would do exactly that
-- to every phone in the field.
create or replace function public.record_device_login(
  p_org_id    uuid,
  p_device_id text,
  p_kind      text,
  p_staff_id  uuid    default null,
  p_client_ip text    default null,
  p_label     text    default null
)
returns table (revoked boolean, is_new_device boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing   public.device_bindings%rowtype;
  v_had_device boolean := false;
  v_dev        text := nullif(btrim(coalesce(p_device_id, '')), '');
begin
  -- No device id (an older client that does not send one yet) — nothing
  -- to record, and definitely nothing to block.
  if v_dev is null then
    return query select false, false;
    return;
  end if;

  select * into v_existing
    from public.device_bindings
   where org_id = p_org_id and device_id = v_dev
     for update;

  if found and v_existing.revoked_at is not null then
    -- Revoked: do NOT refresh last_seen. A revoked device must not be
    -- able to keep its row looking alive by retrying.
    return query select true, false;
    return;
  end if;

  if not found and p_staff_id is not null then
    select exists (
      select 1 from public.device_bindings d
       where d.org_id = p_org_id and d.staff_id = p_staff_id
         and d.revoked_at is null
    ) into v_had_device;
  end if;

  insert into public.device_bindings as d
    (org_id, device_id, staff_id, kind, label, last_client_ip,
     first_seen, last_seen)
  values
    (p_org_id, v_dev, p_staff_id, p_kind, nullif(btrim(coalesce(p_label,'')),''),
     nullif(btrim(coalesce(p_client_ip,'')),''), now(), now())
  on conflict (org_id, device_id) do update
     set last_seen      = now(),
         last_client_ip = coalesce(
           nullif(btrim(coalesce(p_client_ip,'')),''), d.last_client_ip),
         -- A device that changes hands re-points at the new person.
         staff_id       = coalesce(p_staff_id, d.staff_id),
         kind           = p_kind,
         label          = coalesce(
           nullif(btrim(coalesce(p_label,'')),''), d.label);

  return query select false, v_had_device;
end;
$$;

revoke all on function public.record_device_login(uuid, text, text, uuid, text, text) from public;
revoke all on function public.record_device_login(uuid, text, text, uuid, text, text) from anon;
revoke all on function public.record_device_login(uuid, text, text, uuid, text, text) from authenticated;
grant execute on function public.record_device_login(uuid, text, text, uuid, text, text) to service_role;

-- ---------------------------------------------------------------------------
-- 3. revoke_device() — the button the owner presses
-- ---------------------------------------------------------------------------
-- Owner or manager, own org only. Idempotent.
create or replace function public.revoke_device(
  p_org_id    uuid,
  p_device_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null
     or not (public.is_org_owner(p_org_id) or public.is_org_manager(p_org_id))
  then
    raise exception 'Not permitted' using errcode = 'P0001';
  end if;

  update public.device_bindings
     set revoked_at = now(), revoked_by = v_actor
   where org_id = p_org_id and device_id = p_device_id
     and revoked_at is null;

  return found;
end;
$$;

revoke all on function public.revoke_device(uuid, text) from public;
revoke all on function public.revoke_device(uuid, text) from anon;
grant execute on function public.revoke_device(uuid, text) to authenticated;
grant execute on function public.revoke_device(uuid, text) to service_role;

-- ---------------------------------------------------------------------------
-- 4. offboard_staff() — one action, not four
-- ---------------------------------------------------------------------------
-- Deactivation is the ONLY control that actually stops a departed
-- employee, and today it is a manual step nothing prompts for. This
-- makes it one deliberate action that also clears everything trailing
-- behind the person, so an owner cannot half-finish it.
--
-- Session revocation is NOT here: auth.admin.signOut() is a GoTrue admin
-- call and cannot be made from SQL. The `staff-deactivate` Edge Function
-- already does it and stays the caller — this function is what that
-- function invokes, so the two do not drift into two different
-- definitions of "offboarded".
--
-- Returns a summary so the UI can tell the owner exactly what happened
-- rather than claiming success generically.
create or replace function public.offboard_staff(
  p_staff_id uuid,
  p_reason   text default null
)
returns table (
  devices_revoked  integer,
  invites_revoked  integer,
  open_orders      integer,
  open_leads       integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org   uuid;
  v_actor uuid := auth.uid();
  v_dev   integer := 0;
  v_inv   integer := 0;
  v_ord   integer := 0;
  v_led   integer := 0;
begin
  select s.org_id into v_org from public.staff s where s.id = p_staff_id;
  if v_org is null then
    raise exception 'Staff member not found' using errcode = 'P0001';
  end if;
  if v_actor is null or not public.is_org_owner(v_org) then
    raise exception 'Only the owner can offboard a staff member'
      using errcode = 'P0001';
  end if;

  -- 1. The actual boundary.
  update public.staff
     set active = false
   where id = p_staff_id;

  -- 2. Their devices. Pruned rather than kept: DPDP, and a revoked row
  --    for a departed person has no operational use.
  with gone as (
    delete from public.device_bindings
     where org_id = v_org and staff_id = p_staff_id
    returning 1
  ) select count(*) into v_dev from gone;

  -- 3. Any invite they could still redeem.
  with gone as (
    update public.staff_invites
       set revoked_at = now()
     where staff_id = p_staff_id and used_at is null and revoked_at is null
    returning 1
  ) select count(*) into v_inv from gone;

  -- 4. Work still pointing at them. NOT reassigned automatically —
  --    silently moving somebody's jobs is worse than telling the owner
  --    there are jobs to move. The UI offers reassignment; this only
  --    reports the counts.
  select count(*) into v_ord
    from public.orders o
   where o.org_id = v_org
     and o.supervisor_id = p_staff_id
     and coalesce(o.status,'') not in ('closed','cancelled','delivered');

  begin
    select count(*) into v_led
      from public.leads l
     where l.org_id = v_org
       and l.assigned_staff_id = p_staff_id
       and coalesce(l.status,'') not in ('won','lost','confirmed');
  exception when undefined_column then
    -- leads has no assignment column yet (see the "own records only"
    -- scope). Report zero rather than failing the whole offboard.
    v_led := 0;
  end;

  return query select v_dev, v_inv, v_ord, v_led;
end;
$$;

revoke all on function public.offboard_staff(uuid, text) from public;
revoke all on function public.offboard_staff(uuid, text) from anon;
grant execute on function public.offboard_staff(uuid, text) to authenticated;
grant execute on function public.offboard_staff(uuid, text) to service_role;

-- ---------------------------------------------------------------------------
-- 5. POSTFLIGHT — assert what this migration was supposed to produce
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_missing text[] := '{}';
begin
  if to_regclass('public.device_bindings') is null then
    v_missing := v_missing || 'table device_bindings'; end if;
  if not exists (select 1 from pg_proc where proname = 'record_device_login') then
    v_missing := v_missing || 'function record_device_login()'; end if;
  if not exists (select 1 from pg_proc where proname = 'revoke_device') then
    v_missing := v_missing || 'function revoke_device()'; end if;
  if not exists (select 1 from pg_proc where proname = 'offboard_staff') then
    v_missing := v_missing || 'function offboard_staff()'; end if;
  if not exists (
    select 1 from pg_policies
     where tablename = 'device_bindings' and policyname = 'device_bindings_read'
  ) then v_missing := v_missing || 'policy device_bindings_read'; end if;

  if array_length(v_missing, 1) is not null then
    raise exception 'POSTFLIGHT FAILED — rolling back, nothing applied. Missing: %',
      array_to_string(v_missing, ', ');
  end if;

  raise notice 'POSTFLIGHT OK — Phase A device register in place. Nothing is enforced yet.';
end
$postflight$;

commit;

-- ============================================================================
-- AFTER RUNNING (read-only verify)
--   select 'device_bindings' as o, to_regclass('public.device_bindings') is not null
--   union all select 'record_device_login', exists (select 1 from pg_proc where proname='record_device_login')
--   union all select 'revoke_device',       exists (select 1 from pg_proc where proname='revoke_device')
--   union all select 'offboard_staff',      exists (select 1 from pg_proc where proname='offboard_staff');
--
-- THEN deploy pin-login / staff-login with the record_device_login call.
-- Until they are deployed this table simply stays empty — nothing breaks,
-- because Phase A enforces nothing.
-- ============================================================================
