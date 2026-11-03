-- =============================================================================
-- 20261031_crew_checkin.sql — crew check-in by the supervisor's site code
-- =============================================================================
-- HANDED OVER, NOT RUN. One transaction; preflight refuses, postflight
-- asserts the constructs and probes the behaviour (all undone).
--
-- Design handoff (role-02 My team, role-03 Attendance, money-01b
-- Approvals › Check-ins to review), Arun 31 Oct 2026: QR + GPS as designed.
--
--   * The supervisor's phone shows a QR for the job that changes every 30
--     seconds. A crew member scans it from their own phone to check in, so
--     a check-in proves they stood next to the supervisor at that moment.
--     The code is an HMAC of (order, 30-second window) under a per-order
--     secret only the server holds (job_checkin_keys, no client access);
--     the current and previous window are accepted, so a scan at the
--     boundary still works, and nothing older does.
--   * The supervisor checks in with their phone's GPS and a selfie. The
--     distance from the site is recorded when the order has site
--     coordinates (orders.site_lat/site_lng, new, nullable): nothing sets
--     them until the map picker exists, and until then the check-in says
--     the site has no location rather than inventing a distance.
--   * The supervisor can mark someone present who has no working phone,
--     with a reason.
--   * Supervisor check-ins and manual marks wait for the owner's review
--     (Approvals › Check-ins to review: OK or Flag). Code check-ins do not:
--     the code already proves presence.
--   * Every check-in also writes the day's attendance row (status present)
--     if there is none, so Salary and the existing attendance screens see
--     it without changes.
--   * "Late" = checked in after the order's move_date + move_time, India
--     time. No grace minutes are invented; a vendor who wants one is a
--     policy for later.
-- =============================================================================

begin;

set local search_path = public, extensions;

do $preflight$
begin
  if to_regclass('public.attendance') is null or to_regclass('public.order_staff') is null
     or to_regprocedure('public.current_staff_id()') is null
     or to_regprocedure('public.is_org_manager(uuid)') is null then
    raise exception 'PREFLIGHT FAILED: attendance / order_staff / current_staff_id() / is_org_manager() missing';
  end if;
  if to_regclass('public.crew_checkins') is not null then
    raise exception 'PREFLIGHT FAILED: crew_checkins already exists; this migration has run before';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'orders' and column_name = 'supervisor_id')
     or not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'orders' and column_name = 'move_time') then
    raise exception 'PREFLIGHT FAILED: orders.supervisor_id or orders.move_time missing';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'orders' and column_name in ('site_lat','site_lng')) then
    raise exception 'PREFLIGHT FAILED: orders.site_lat/site_lng already exist';
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where p.proname = 'hmac' and n.nspname = 'extensions') then
    raise exception 'PREFLIGHT FAILED: pgcrypto hmac() not found in schema extensions';
  end if;
end
$preflight$;

alter table public.orders
  add column site_lat double precision check (site_lat between -90 and 90),
  add column site_lng double precision check (site_lng between -180 and 180);

-- Per-order secret for the rotating code. Server only.
create table public.job_checkin_keys (
  order_id   text primary key,
  org_id     uuid not null,
  secret     bytea not null default extensions.gen_random_bytes(32),
  created_at timestamptz not null default now()
);
alter table public.job_checkin_keys enable row level security;
revoke all on public.job_checkin_keys from public, anon, authenticated;

create table public.crew_checkins (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null,
  order_id      text not null,
  staff_id      uuid not null references public.staff(id) on delete cascade,
  day           date not null default (now() at time zone 'Asia/Kolkata')::date,
  method        text not null check (method in ('code','supervisor_gps','manual')),
  checked_in_at timestamptz not null default now(),
  late          boolean not null default false,
  lat           double precision,
  lng           double precision,
  accuracy_m    numeric,
  distance_m    numeric,
  selfie_path   text,
  reason        text,
  marked_by     uuid,
  review_status text check (review_status in ('ok','flagged')),
  reviewed_by   uuid,
  reviewed_at   timestamptz,
  unique (order_id, staff_id, day),
  check (method <> 'manual' or length(btrim(coalesce(reason, ''))) >= 3),
  check (method <> 'supervisor_gps' or (lat is not null and lng is not null and selfie_path is not null))
);
create index crew_checkins_org_day_idx on public.crew_checkins (org_id, day desc);

alter table public.crew_checkins enable row level security;
create policy crew_checkins_read on public.crew_checkins
  for select to authenticated using (org_id in (select public.current_org_ids()));
revoke all on public.crew_checkins from public, anon, authenticated;
grant select on public.crew_checkins to authenticated;
-- All writes go through the functions below.

-- The caller is this order's supervisor, or a manager/owner of its org.
create function public.checkin_can_run(p_order text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from orders o
     where o.id = p_order
       and (o.supervisor_id in (select public.current_staff_id())
            or public.is_org_manager(o.org_id)))
$$;

create function public.checkin_code_for(p_order text, p_window bigint)
returns text
language sql stable security definer set search_path = public, extensions
as $$
  select upper(substr(encode(extensions.hmac(convert_to(p_order || ':' || p_window, 'UTF8'), k.secret, 'sha256'), 'hex'), 1, 10))
    from job_checkin_keys k where k.order_id = p_order
$$;

-- Writes today's attendance row for a staff member if there is none.
create function public.checkin_mark_attendance(p_org uuid, p_staff uuid, p_branch text, p_by text, p_note text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_day date := (now() at time zone 'Asia/Kolkata')::date;
begin
  if not exists (select 1 from attendance
                  where org_id = p_org and staff_id = p_staff::text and attendance_date = v_day) then
    insert into attendance (org_id, staff_id, attendance_date, status, branch, marked_by, note)
    values (p_org, p_staff::text, v_day, 'present', p_branch, p_by, p_note);
  end if;
end
$$;

create function public.checkin_is_late(p_order text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(now() > ((o.move_date + o.move_time) at time zone 'Asia/Kolkata'), false)
    from orders o where o.id = p_order
$$;

-- The QR payload to show now, and how long it stays valid.
create function public.checkin_code(p_order text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  o orders;
  v_window bigint := floor(extract(epoch from now()) / 30);
begin
  select * into o from orders where id = p_order;
  if o.id is null or not public.checkin_can_run(p_order) then
    raise exception 'Only this job''s supervisor or a manager can show its check-in code.';
  end if;
  if o.status in ('closed','cancelled') then
    raise exception 'This job is %; there is nothing to check in to.', o.status;
  end if;
  insert into job_checkin_keys (order_id, org_id) values (o.id, o.org_id)
  on conflict (order_id) do nothing;
  return jsonb_build_object(
    'payload', 'NGV1|' || o.id || '|' || v_window || '|' || public.checkin_code_for(o.id, v_window),
    'seconds_left', 30 - (floor(extract(epoch from now()))::bigint % 30));
end
$$;

-- A crew member checks in with a scanned payload.
create function public.crew_check_in(p_payload text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  parts text[] := string_to_array(coalesce(p_payload, ''), '|');
  v_now bigint := floor(extract(epoch from now()) / 30);
  v_window bigint;
  v_staff uuid;
  o orders;
  v_late boolean;
  v_id uuid;
begin
  if array_length(parts, 1) <> 4 or parts[1] <> 'NGV1' or parts[3] !~ '^[0-9]+$' then
    return jsonb_build_object('ok', false, 'reason', 'not_a_code');
  end if;
  v_window := parts[3]::bigint;
  if v_window not in (v_now, v_now - 1) then
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;
  select * into o from orders where id = parts[2];
  if o.id is null or public.checkin_code_for(o.id, v_window) is distinct from parts[4] then
    return jsonb_build_object('ok', false, 'reason', 'not_a_code');
  end if;
  select id into v_staff from staff
   where id in (select public.current_staff_id()) and org_id = o.org_id limit 1;
  if v_staff is null then
    return jsonb_build_object('ok', false, 'reason', 'not_staff');
  end if;
  if not exists (select 1 from order_staff where order_id = o.id and staff_id = v_staff) then
    return jsonb_build_object('ok', false, 'reason', 'not_on_crew', 'order', o.id);
  end if;
  v_late := public.checkin_is_late(o.id);
  insert into crew_checkins (org_id, order_id, staff_id, method, late, marked_by)
  values (o.org_id, o.id, v_staff, 'code', v_late, v_staff)
  on conflict (order_id, staff_id, day) do nothing
  returning id into v_id;
  perform public.checkin_mark_attendance(o.org_id, v_staff, o.branch, 'site code', 'Checked in at ' || o.id);
  return jsonb_build_object('ok', true, 'order', o.id, 'customer', o.customer,
                            'late', v_late, 'already', v_id is null);
end
$$;

-- The supervisor checks in with GPS and a selfie (already uploaded to
-- job-photos/<org>/checkins/...).
create function public.supervisor_check_in(p_order text, p_lat double precision, p_lng double precision,
                                           p_accuracy numeric, p_selfie_path text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  o orders;
  v_staff uuid;
  v_dist numeric;
  v_late boolean;
begin
  select * into o from orders where id = p_order;
  select id into v_staff from staff where id in (select public.current_staff_id()) and id = o.supervisor_id;
  if o.id is null or v_staff is null then
    raise exception 'Only this job''s supervisor can check in to it here.';
  end if;
  if p_lat is null or p_lng is null or abs(p_lat) > 90 or abs(p_lng) > 180 then
    raise exception 'Your location could not be read. Turn on location and try again.';
  end if;
  if nullif(btrim(p_selfie_path), '') is null
     or split_part(p_selfie_path, '/', 1) <> o.org_id::text then
    raise exception 'Take the selfie first.';
  end if;
  if o.site_lat is not null and o.site_lng is not null then
    v_dist := round((2 * 6371000 * asin(sqrt(
        power(sin(radians(p_lat - o.site_lat) / 2), 2)
      + cos(radians(o.site_lat)) * cos(radians(p_lat))
        * power(sin(radians(p_lng - o.site_lng) / 2), 2))))::numeric);
  end if;
  v_late := public.checkin_is_late(o.id);
  insert into crew_checkins (org_id, order_id, staff_id, method, late, lat, lng, accuracy_m,
                             distance_m, selfie_path, marked_by)
  values (o.org_id, o.id, v_staff, 'supervisor_gps', v_late, p_lat, p_lng, p_accuracy,
          v_dist, p_selfie_path, v_staff)
  on conflict (order_id, staff_id, day) do update
     set lat = excluded.lat, lng = excluded.lng, accuracy_m = excluded.accuracy_m,
         distance_m = excluded.distance_m, selfie_path = excluded.selfie_path,
         checked_in_at = now(), review_status = null, reviewed_by = null, reviewed_at = null;
  perform public.checkin_mark_attendance(o.org_id, v_staff, o.branch, 'GPS + selfie', 'Checked in at ' || o.id);
  return jsonb_build_object('ok', true, 'distance_m', v_dist, 'late', v_late);
end
$$;

-- The supervisor marks a crew member present who cannot scan.
create function public.mark_crew_present(p_order text, p_staff uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  o orders;
  v_by uuid;
begin
  select * into o from orders where id = p_order;
  if o.id is null or not public.checkin_can_run(p_order) then
    raise exception 'Only this job''s supervisor or a manager can mark the crew.';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 3 then
    raise exception 'Say why they could not check in themselves.';
  end if;
  if not exists (select 1 from order_staff where order_id = o.id and staff_id = p_staff) then
    raise exception 'That person is not on this job''s crew.';
  end if;
  select id into v_by from staff where id in (select public.current_staff_id()) limit 1;
  insert into crew_checkins (org_id, order_id, staff_id, method, late, reason, marked_by)
  values (o.org_id, o.id, p_staff, 'manual', public.checkin_is_late(o.id), btrim(p_reason),
          coalesce(v_by, auth.uid()))
  on conflict (order_id, staff_id, day) do nothing;
  if not found then
    raise exception 'Already checked in today.';
  end if;
  perform public.checkin_mark_attendance(o.org_id, p_staff, o.branch, 'marked by supervisor', btrim(p_reason));
end
$$;

-- The owner or a manager reviews a supervisor or manual check-in.
create function public.review_checkin(p_id uuid, p_status text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  c crew_checkins;
begin
  if p_status not in ('ok','flagged') then
    raise exception 'Unknown review %.', p_status;
  end if;
  select * into c from crew_checkins where id = p_id;
  if c.id is null or not public.is_org_manager(c.org_id) then
    raise exception 'Only the owner or a manager can review check-ins.';
  end if;
  if c.method = 'code' then
    raise exception 'Code check-ins do not need review.';
  end if;
  update crew_checkins set review_status = p_status, reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_id;
end
$$;

-- Grants: Supabase grants new functions to anon and authenticated by name.
do $grants$
declare
  f text;
begin
  foreach f in array array[
    'public.checkin_can_run(text)', 'public.checkin_code_for(text,bigint)',
    'public.checkin_mark_attendance(uuid,uuid,text,text,text)', 'public.checkin_is_late(text)',
    'public.checkin_code(text)', 'public.crew_check_in(text)',
    'public.supervisor_check_in(text,double precision,double precision,numeric,text)',
    'public.mark_crew_present(text,uuid,text)', 'public.review_checkin(uuid,text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array[
    'public.checkin_code(text)', 'public.crew_check_in(text)',
    'public.supervisor_check_in(text,double precision,double precision,numeric,text)',
    'public.mark_crew_present(text,uuid,text)', 'public.review_checkin(uuid,text)'] loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$grants$;

do $postflight$
declare
  v_bad int;
  o     orders;
  v_sup uuid;
  v_crew uuid;
  v_q   jsonb;
  v_r   jsonb;
  parts text[];
begin
  if not (select relrowsecurity from pg_class where oid = 'public.crew_checkins'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'public.job_checkin_keys'::regclass) then
    raise exception 'POSTFLIGHT: RLS off on a check-in table';
  end if;
  if has_table_privilege('authenticated', 'public.job_checkin_keys', 'select')
     or has_table_privilege('anon', 'public.job_checkin_keys', 'select') then
    raise exception 'POSTFLIGHT: a client can read the check-in secrets';
  end if;
  if has_table_privilege('authenticated', 'public.crew_checkins', 'insert')
     or has_table_privilege('authenticated', 'public.crew_checkins', 'update')
     or has_table_privilege('anon', 'public.crew_checkins', 'select') then
    raise exception 'POSTFLIGHT: crew_checkins is writable from the app or readable by anon';
  end if;
  select count(*) into v_bad
    from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('checkin_can_run','checkin_code_for','checkin_mark_attendance','checkin_is_late',
                       'checkin_code','crew_check_in','supervisor_check_in','mark_crew_present','review_checkin')
     and a.privilege_type = 'EXECUTE'
     and (a.grantee in (0, 'anon'::regrole)
          or (a.grantee = 'authenticated'::regrole
              and p.proname in ('checkin_can_run','checkin_code_for','checkin_mark_attendance','checkin_is_late')));
  if v_bad > 0 then
    raise exception 'POSTFLIGHT: a check-in function is callable by a role that should not call it';
  end if;

  -- Behaviour, undone below: a fresh code checks a crew member in, the
  -- same code from a stranger or a tampered code is refused.
  select o2.* into o from orders o2
   where o2.supervisor_id is not null and o2.status not in ('closed','cancelled')
     and exists (select 1 from order_staff s where s.order_id = o2.id and s.staff_id <> o2.supervisor_id)
   limit 1;
  if o.id is null then
    raise notice 'POSTFLIGHT: no open order with a supervisor and crew; behaviour probe skipped';
    return;
  end if;
  v_sup := o.supervisor_id;
  select staff_id into v_crew from order_staff where order_id = o.id and staff_id <> v_sup limit 1;
  insert into job_checkin_keys (order_id, org_id) values (o.id, o.org_id) on conflict do nothing;
  parts := array['NGV1', o.id, floor(extract(epoch from now()) / 30)::bigint::text, ''];
  parts[4] := public.checkin_code_for(o.id, parts[3]::bigint);

  -- Pretend to be the crew member: current_staff_id() reads staff.auth_user_id.
  update staff set auth_user_id = '00000000-0000-0000-0000-00000000c0de' where id = v_crew;
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000c0de"}', true);
  v_r := public.crew_check_in(array_to_string(parts, '|'));
  if (v_r->>'ok')::boolean is not true then
    raise exception 'POSTFLIGHT: a fresh code was refused: %', v_r;
  end if;
  if not exists (select 1 from attendance where staff_id = v_crew::text
                    and attendance_date = (now() at time zone 'Asia/Kolkata')::date) then
    raise exception 'POSTFLIGHT: check-in did not mark attendance';
  end if;
  v_r := public.crew_check_in(array_to_string(array['NGV1', o.id, parts[3], 'AAAAAAAAAA'], '|'));
  if v_r->>'reason' is distinct from 'not_a_code' then
    raise exception 'POSTFLIGHT: a tampered code was accepted: %', v_r;
  end if;
  v_r := public.crew_check_in(array_to_string(array['NGV1', o.id, (parts[3]::bigint - 5)::text,
                                public.checkin_code_for(o.id, parts[3]::bigint - 5)], '|'));
  if v_r->>'reason' is distinct from 'expired' then
    raise exception 'POSTFLIGHT: a 2.5-minute-old code was accepted: %', v_r;
  end if;
  raise exception using errcode = 'P0002', message = 'probe done';
exception
  when sqlstate 'P0002' then
    null;  -- the probe's writes are rolled back with this block
end
$postflight$;

commit;
