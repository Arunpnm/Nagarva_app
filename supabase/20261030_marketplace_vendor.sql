-- =============================================================================
-- 20261030_marketplace_vendor.sql — Nagarva marketplace, vendor side
-- =============================================================================
-- HANDED OVER, NOT RUN. Run in the Supabase SQL editor (project
-- hqqcapifefsaqvotqvlt) as one transaction; it refuses rather than skips
-- (preflight) and asserts what it built (postflight), per CLAUDE.md.
--
-- What it is (design handoff README, "Marketplace (Nagarva sells moves
-- direct)"): customers book a move with NAGARVA, Nagarva prices it and
-- broadcasts the job to vendors city by city, Gold tier first, then
-- Silver, then Bronze; the first vendor to accept gets it. The vendor
-- moves it through Accepted → On the way → Arrived → Loading → In transit
-- → Delivered (customer OTP). On delivery the vendor wallet is credited
-- with the advance the customer paid Nagarva and debited the commission
-- (on the ex-GST value).
--
-- What it is NOT: a payment integration. Wallet TOP-UP and WITHDRAWAL need
-- a gateway and a decision on which entity collects (CLAUDE.md Item 31,
-- on hold with the CA). Here a top-up or withdrawal is only a REQUEST row
-- (status pending) that a Nagarva admin marks done after the money has
-- actually moved. No function in this file moves money.
--
-- Platform rules (windows, wallet minimum, commission, advance) are
-- NAGARVA's prices, not a vendor's, so seeding them is not the "no
-- suggested money" rule: that rule is about the app inventing a vendor's
-- rates. The '*' row is the default for any city without its own row;
-- values are the design's (Admin › Marketplace › City rules, MPC0 Chennai).
--
-- Access model:
--   * Vendors never SELECT mkt_jobs directly: customer name, phone and
--     addresses stay hidden until they accept, which RLS alone cannot do
--     column by column. They read through mkt_vendor_jobs().
--   * Every write goes through a SECURITY DEFINER function that checks the
--     caller belongs to the org (owner or manager) with coalesce(..., false)
--     around the WHOLE condition, so an unknown answer denies (the
--     set_staff_pin fail-open lesson, 15 Sept 2026).
--   * Nagarva admins (is_platform_admin()) read and write everything.
--   * EXECUTE is revoked from PUBLIC and anon and granted to authenticated.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- Preflight: the helpers this file calls must exist, the tables must not.
-- -----------------------------------------------------------------------------
do $preflight$
declare
  v_missing text[] := '{}';
begin
  if to_regprocedure('public.current_org_ids()') is null then
    v_missing := array_append(v_missing, 'current_org_ids()');
  end if;
  if to_regprocedure('public.is_org_owner(uuid)') is null then
    v_missing := array_append(v_missing, 'is_org_owner(uuid)');
  end if;
  if to_regprocedure('public.is_org_manager(uuid)') is null then
    v_missing := array_append(v_missing, 'is_org_manager(uuid)');
  end if;
  if to_regprocedure('public.is_platform_admin()') is null then
    v_missing := array_append(v_missing, 'is_platform_admin()');
  end if;
  if array_length(v_missing, 1) is not null then
    raise exception 'PREFLIGHT FAILED: missing %', array_to_string(v_missing, ', ');
  end if;
  if to_regclass('public.mkt_jobs') is not null then
    raise exception 'PREFLIGHT FAILED: mkt_jobs already exists; this migration has run before';
  end if;
end
$preflight$;

-- -----------------------------------------------------------------------------
-- 1. Tables
-- -----------------------------------------------------------------------------

-- Nagarva's per-city rules. city '*' is the default.
create table public.mkt_city_rules (
  city               text primary key,
  gold_window_min    int     not null check (gold_window_min between 0 and 120),
  silver_window_min  int     not null check (silver_window_min between 0 and 120),
  wallet_min         numeric not null check (wallet_min >= 0),
  commission_pct     numeric not null check (commission_pct between 0 and 50),
  advance_pct        numeric not null check (advance_pct between 0 and 100),
  advance_min        numeric not null check (advance_min >= 0),
  late_min           int     not null check (late_min >= 0),
  stuck_hours        int     not null check (stuck_hours >= 0),
  return_delay_min   int     not null check (return_delay_min >= 0),
  updated_at         timestamptz not null default now()
);

insert into public.mkt_city_rules
  (city, gold_window_min, silver_window_min, wallet_min, commission_pct,
   advance_pct, advance_min, late_min, stuck_hours, return_delay_min)
values ('*', 5, 10, 2000, 12, 10, 999, 15, 4, 0);

-- Tier factor weights (Admin › Marketplace › Weights). Must total 100.
create table public.mkt_tier_weights (
  factor  text primary key,
  weight  int  not null check (weight between 0 and 100)
);

insert into public.mkt_tier_weights (factor, weight) values
  ('customer_rating', 25), ('on_time_arrival', 20), ('damage_claims', 15),
  ('acceptance_rate', 15), ('photo_compliance', 10),
  ('vendor_cancellations', 10), ('jobs_completed', 5);

-- One row per vendor org taking Nagarva jobs.
create table public.mkt_vendors (
  org_id            uuid primary key references public.organizations(id) on delete cascade,
  available         boolean not null default false,
  home_city         text,
  extra_cities      text[]  not null default '{}',
  score             numeric not null default 0 check (score between 0 and 100),
  suspended         boolean not null default false,
  -- Return-trip mode: a truck now in return_from_city heading home.
  return_from_city  text,
  return_on         date,
  updated_at        timestamptz not null default now()
);

create table public.mkt_jobs (
  id               uuid primary key default gen_random_uuid(),
  job_no           text not null unique,
  pickup_city      text not null,
  drop_city        text not null,
  package          text not null check (package in ('economy','standard','premium')),
  move_date        date not null,
  slot             text,
  cft              numeric,
  items            jsonb not null default '[]',
  total_inr        numeric not null check (total_inr >= 0),   -- incl. GST
  gst_inr          numeric not null default 0 check (gst_inr >= 0),
  advance_inr      numeric not null default 0 check (advance_inr >= 0),
  commission_pct   numeric not null check (commission_pct between 0 and 50),
  customer_name    text,
  customer_phone   text,
  pickup_address   text,
  drop_address     text,
  -- The customer reads this to the crew at delivery. Never returned to
  -- a vendor by mkt_vendor_jobs().
  delivery_otp     text,
  status           text not null default 'broadcast' check (status in
                     ('broadcast','accepted','on_the_way','arrived','loading',
                      'in_transit','delivered','cancelled')),
  broadcast_at     timestamptz not null default now(),
  accepted_org_id  uuid references public.organizations(id) on delete set null,
  accepted_at      timestamptz,
  delivered_at     timestamptz,
  loading_photos   text[] not null default '{}',
  rating           int check (rating between 1 and 5),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (gst_inr <= total_inr)
);

create index mkt_jobs_broadcast_idx on public.mkt_jobs (pickup_city, broadcast_at)
  where status = 'broadcast';
create index mkt_jobs_vendor_idx on public.mkt_jobs (accepted_org_id, status);

create table public.mkt_job_events (
  id       uuid primary key default gen_random_uuid(),
  job_id   uuid not null references public.mkt_jobs(id) on delete cascade,
  at       timestamptz not null default now(),
  kind     text not null,
  org_id   uuid references public.organizations(id) on delete set null,
  actor    uuid,
  note     text
);
create index mkt_job_events_job_idx on public.mkt_job_events (job_id, at);

-- Signed amounts: credits positive, debits negative. Balance = sum of
-- rows with status 'done'.
create table public.mkt_wallet_entries (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  job_id      uuid references public.mkt_jobs(id) on delete set null,
  kind        text not null check (kind in
                ('topup','withdrawal','advance_credit','commission','adjustment')),
  amount      numeric not null,
  status      text not null default 'done' check (status in ('pending','done','rejected')),
  reference   text,
  created_at  timestamptz not null default now(),
  created_by  uuid,
  check (kind <> 'topup'      or amount > 0),
  check (kind <> 'withdrawal' or amount < 0),
  check (kind <> 'commission' or amount <= 0)
);
create index mkt_wallet_org_idx on public.mkt_wallet_entries (org_id, created_at desc);
-- One advance credit and one commission per job, so a repeated delivery
-- call cannot pay twice.
create unique index mkt_wallet_job_kind_uniq on public.mkt_wallet_entries (job_id, kind)
  where job_id is not null and kind in ('advance_credit','commission');

-- -----------------------------------------------------------------------------
-- 2. Row-level security. Reads only; every write is a function below.
-- -----------------------------------------------------------------------------
alter table public.mkt_city_rules     enable row level security;
alter table public.mkt_tier_weights   enable row level security;
alter table public.mkt_vendors        enable row level security;
alter table public.mkt_jobs           enable row level security;
alter table public.mkt_job_events     enable row level security;
alter table public.mkt_wallet_entries enable row level security;

create policy mkt_city_rules_read on public.mkt_city_rules
  for select to authenticated using (true);
create policy mkt_city_rules_admin on public.mkt_city_rules
  for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

create policy mkt_tier_weights_read on public.mkt_tier_weights
  for select to authenticated using (true);
create policy mkt_tier_weights_admin on public.mkt_tier_weights
  for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

create policy mkt_vendors_read on public.mkt_vendors
  for select to authenticated
  using (org_id in (select public.current_org_ids()) or public.is_platform_admin());
create policy mkt_vendors_admin on public.mkt_vendors
  for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

-- mkt_jobs: admins only. Vendors go through mkt_vendor_jobs().
create policy mkt_jobs_admin on public.mkt_jobs
  for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

create policy mkt_job_events_read on public.mkt_job_events
  for select to authenticated
  using (org_id in (select public.current_org_ids()) or public.is_platform_admin());
create policy mkt_job_events_admin on public.mkt_job_events
  for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

create policy mkt_wallet_read on public.mkt_wallet_entries
  for select to authenticated
  using (org_id in (select public.current_org_ids()) or public.is_platform_admin());
create policy mkt_wallet_admin on public.mkt_wallet_entries
  for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

-- Table privileges: no anon, read-only for authenticated (admins write
-- through their policies).
revoke all on public.mkt_city_rules, public.mkt_tier_weights, public.mkt_vendors,
  public.mkt_jobs, public.mkt_job_events, public.mkt_wallet_entries from anon, public;
grant select, insert, update, delete on public.mkt_city_rules, public.mkt_tier_weights,
  public.mkt_vendors, public.mkt_jobs, public.mkt_job_events, public.mkt_wallet_entries
  to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Helpers
-- -----------------------------------------------------------------------------

-- The rules for a city, falling back to '*'.
create function public.mkt_rules_for(p_city text)
returns public.mkt_city_rules
language sql stable security definer set search_path = public
as $$
  select r.* from public.mkt_city_rules r
   where r.city in (p_city, '*')
   order by (r.city = '*') limit 1
$$;

create function public.mkt_tier(p_score numeric)
returns text language sql immutable
as $$ select case when p_score >= 80 then 'gold' when p_score >= 60 then 'silver' else 'bronze' end $$;

create function public.mkt_wallet_balance(p_org uuid)
returns numeric
language sql stable security definer set search_path = public
as $$
  select coalesce(sum(amount), 0) from public.mkt_wallet_entries
   where org_id = p_org and status = 'done'
     and (p_org in (select public.current_org_ids()) or public.is_platform_admin())
$$;

-- The caller may act for this vendor org: owner or manager.
create function public.mkt_can_act(p_org uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(
    p_org in (select public.current_org_ids())
      and (public.is_org_owner(p_org) or public.is_org_manager(p_org)),
    false)
$$;

-- Whether a broadcast job is visible to this vendor now. Tier windows
-- run from broadcast_at: Gold at once, Silver after gold_window_min,
-- Bronze after gold + silver. Premium is Gold only. A vendor in return
-- mode also sees jobs from where the truck is to their home city once
-- return_delay_min has passed. Wallet below the city minimum, not
-- available, or suspended: nothing.
create function public.mkt_job_visible(j public.mkt_jobs, v public.mkt_vendors)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  r public.mkt_city_rules := public.mkt_rules_for(j.pickup_city);
  t text := public.mkt_tier(v.score);
  open_at timestamptz;
  -- coalesce: a vendor with no home city must see nothing, and a NULL
  -- here would otherwise skip the `if not in_city` refusal below.
  in_city boolean := coalesce(j.pickup_city = v.home_city
                              or j.pickup_city = any(v.extra_cities), false);
  is_return boolean := coalesce(v.return_from_city is not null
                       and j.pickup_city = v.return_from_city
                       and j.drop_city = v.home_city, false);
begin
  if j.status <> 'broadcast' or not v.available or v.suspended then
    return false;
  end if;
  if public.mkt_wallet_balance(v.org_id) < r.wallet_min then
    return false;
  end if;
  if is_return and now() >= j.broadcast_at + make_interval(mins => r.return_delay_min) then
    return true;
  end if;
  if not in_city then
    return false;
  end if;
  if j.package = 'premium' and t <> 'gold' then
    return false;
  end if;
  open_at := j.broadcast_at + case t
    when 'gold'   then interval '0'
    when 'silver' then make_interval(mins => r.gold_window_min)
    else make_interval(mins => r.gold_window_min + r.silver_window_min)
  end;
  return now() >= open_at;
end
$$;

-- -----------------------------------------------------------------------------
-- 4. Vendor functions
-- -----------------------------------------------------------------------------

-- Jobs for the vendor's Jobs tab: open broadcasts it can see now (customer
-- masked) and its own accepted / active / delivered jobs (customer shown).
create function public.mkt_vendor_jobs(p_org uuid)
returns table (
  id uuid, job_no text, pickup_city text, drop_city text, package text,
  move_date date, slot text, cft numeric, items jsonb, total_inr numeric,
  gst_inr numeric, advance_inr numeric, commission_pct numeric,
  status text, broadcast_at timestamptz, accepted_at timestamptz,
  delivered_at timestamptz, rating int, mine boolean,
  customer_name text, customer_phone text, pickup_address text, drop_address text
)
language plpgsql stable security definer set search_path = public
as $$
declare
  v public.mkt_vendors;
begin
  if not public.mkt_can_act(p_org) then
    raise exception 'not authorized for this vendor';
  end if;
  select * into v from public.mkt_vendors where org_id = p_org;
  return query
    select j.id, j.job_no, j.pickup_city, j.drop_city, j.package, j.move_date,
           j.slot, j.cft, j.items, j.total_inr, j.gst_inr, j.advance_inr,
           j.commission_pct, j.status, j.broadcast_at, j.accepted_at,
           j.delivered_at, j.rating, (j.accepted_org_id = p_org),
           case when j.accepted_org_id = p_org then j.customer_name end,
           case when j.accepted_org_id = p_org then j.customer_phone end,
           case when j.accepted_org_id = p_org then j.pickup_address end,
           case when j.accepted_org_id = p_org then j.drop_address end
      from public.mkt_jobs j
     where j.accepted_org_id = p_org
        or (v.org_id is not null and public.mkt_job_visible(j, v))
     order by (j.accepted_org_id = p_org), j.broadcast_at desc;
end
$$;

-- Availability, pickup cities and return-trip mode. Score, tier and
-- suspension are Nagarva's and are not writable here.
create function public.mkt_set_vendor(
  p_org uuid, p_available boolean, p_home_city text, p_extra_cities text[],
  p_return_from_city text default null, p_return_on date default null)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.mkt_can_act(p_org) then
    raise exception 'not authorized for this vendor';
  end if;
  if nullif(btrim(coalesce(p_home_city, '')), '') is null then
    raise exception 'Choose a home city first.';
  end if;
  insert into public.mkt_vendors as m
    (org_id, available, home_city, extra_cities, return_from_city, return_on, updated_at)
  values (p_org, p_available, btrim(p_home_city), coalesce(p_extra_cities, '{}'),
          nullif(btrim(coalesce(p_return_from_city, '')), ''), p_return_on, now())
  on conflict (org_id) do update set
    available = excluded.available, home_city = excluded.home_city,
    extra_cities = excluded.extra_cities,
    return_from_city = excluded.return_from_city,
    return_on = excluded.return_on, updated_at = now();
end
$$;

-- First vendor to accept gets the job. Atomic: the update only matches a
-- job still in broadcast, so a second accept finds nothing.
create function public.mkt_accept_job(p_org uuid, p_job uuid)
returns text  -- 'accepted' | 'taken' | 'not_visible'
language plpgsql security definer set search_path = public
as $$
declare
  v public.mkt_vendors;
  j public.mkt_jobs;
  n int;
begin
  if not public.mkt_can_act(p_org) then
    raise exception 'not authorized for this vendor';
  end if;
  select * into v from public.mkt_vendors where org_id = p_org;
  select * into j from public.mkt_jobs where id = p_job for update;
  if j.id is null then
    raise exception 'job not found';
  end if;
  if j.status <> 'broadcast' then
    return 'taken';
  end if;
  if v.org_id is null or not public.mkt_job_visible(j, v) then
    return 'not_visible';
  end if;
  update public.mkt_jobs
     set status = 'accepted', accepted_org_id = p_org, accepted_at = now(),
         updated_at = now()
   where id = p_job and status = 'broadcast';
  get diagnostics n = row_count;
  if n = 0 then
    return 'taken';
  end if;
  insert into public.mkt_job_events (job_id, kind, org_id, actor)
  values (p_job, 'accepted', p_org, auth.uid());
  return 'accepted';
end
$$;

create function public.mkt_pass_job(p_org uuid, p_job uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.mkt_can_act(p_org) then
    raise exception 'not authorized for this vendor';
  end if;
  insert into public.mkt_job_events (job_id, kind, org_id, actor)
  values (p_job, 'passed', p_org, auth.uid());
end
$$;

-- Moves the vendor's job one step along the stepper. Loading needs three
-- photos; Delivered needs the customer's OTP and then credits the advance
-- and debits the commission (on the ex-GST value), once.
create function public.mkt_advance_job(
  p_org uuid, p_job uuid, p_to text,
  p_otp text default null, p_photos text[] default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  j public.mkt_jobs;
  steps text[] := array['accepted','on_the_way','arrived','loading','in_transit','delivered'];
  cur int;
  nxt int;
  commission numeric;
begin
  if not public.mkt_can_act(p_org) then
    raise exception 'not authorized for this vendor';
  end if;
  select * into j from public.mkt_jobs where id = p_job for update;
  if j.id is null or j.accepted_org_id is distinct from p_org then
    raise exception 'This job is not yours.';
  end if;
  cur := array_position(steps, j.status);
  nxt := array_position(steps, p_to);
  if cur is null or nxt is null or nxt <> cur + 1 then
    raise exception 'Move the job one step at a time (now %).', j.status;
  end if;
  if p_to = 'in_transit' and coalesce(array_length(
       coalesce(p_photos, j.loading_photos), 1), 0) < 3 then
    raise exception 'Add three loading photos before moving to in transit.';
  end if;
  if p_to = 'delivered' then
    if j.delivery_otp is null
       or coalesce(btrim(p_otp), '') <> j.delivery_otp then
      raise exception 'Delivery code does not match. Ask the customer again.';
    end if;
  end if;

  update public.mkt_jobs
     set status = p_to,
         loading_photos = coalesce(p_photos, loading_photos),
         delivered_at = case when p_to = 'delivered' then now() else delivered_at end,
         updated_at = now()
   where id = p_job;
  insert into public.mkt_job_events (job_id, kind, org_id, actor)
  values (p_job, p_to, p_org, auth.uid());

  if p_to = 'delivered' then
    commission := round((j.total_inr - j.gst_inr) * j.commission_pct / 100, 2);
    insert into public.mkt_wallet_entries (org_id, job_id, kind, amount, created_by)
    values (p_org, p_job, 'advance_credit', j.advance_inr, auth.uid()),
           (p_org, p_job, 'commission', -commission, auth.uid())
    on conflict do nothing;
  end if;
end
$$;

-- A top-up or withdrawal REQUEST. Status pending until a Nagarva admin
-- marks it done after the money has moved; it does not count toward the
-- balance until then. A withdrawal may not take the balance below the
-- city minimum.
create function public.mkt_request_wallet(p_org uuid, p_kind text, p_amount numeric, p_reference text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v public.mkt_vendors;
  r public.mkt_city_rules;
begin
  if not public.mkt_can_act(p_org) then
    raise exception 'not authorized for this vendor';
  end if;
  if p_kind not in ('topup','withdrawal') then
    raise exception 'unknown request %', p_kind;
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Enter an amount above zero.';
  end if;
  if p_kind = 'withdrawal' then
    select * into v from public.mkt_vendors where org_id = p_org;
    r := public.mkt_rules_for(v.home_city);
    -- Pending withdrawals count against it, or two requests could each
    -- pass on the same money.
    if public.mkt_wallet_balance(p_org)
       + coalesce((select sum(amount) from public.mkt_wallet_entries
                    where org_id = p_org and kind = 'withdrawal'
                      and status = 'pending'), 0)
       - p_amount < r.wallet_min then
      raise exception 'You can withdraw only the amount above the minimum of %.', r.wallet_min;
    end if;
  end if;
  insert into public.mkt_wallet_entries (org_id, kind, amount, status, reference, created_by)
  values (p_org, p_kind,
          case when p_kind = 'withdrawal' then -p_amount else p_amount end,
          'pending', nullif(btrim(coalesce(p_reference, '')), ''), auth.uid());
end
$$;

do $grants$
declare f text;
begin
  foreach f in array array[
    'public.mkt_rules_for(text)', 'public.mkt_tier(numeric)',
    'public.mkt_wallet_balance(uuid)', 'public.mkt_can_act(uuid)',
    'public.mkt_job_visible(public.mkt_jobs, public.mkt_vendors)',
    'public.mkt_vendor_jobs(uuid)',
    'public.mkt_set_vendor(uuid, boolean, text, text[], text, date)',
    'public.mkt_accept_job(uuid, uuid)', 'public.mkt_pass_job(uuid, uuid)',
    'public.mkt_advance_job(uuid, uuid, text, text, text[])',
    'public.mkt_request_wallet(uuid, text, numeric, text)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$grants$;

-- -----------------------------------------------------------------------------
-- Postflight: assert the constructs, inside the transaction.
-- -----------------------------------------------------------------------------
do $postflight$
declare
  t text;
  v_bad int;
begin
  foreach t in array array['mkt_city_rules','mkt_tier_weights','mkt_vendors',
                           'mkt_jobs','mkt_job_events','mkt_wallet_entries'] loop
    if not (select c.relrowsecurity from pg_class c
             where c.oid = to_regclass('public.' || t)) then
      raise exception 'POSTFLIGHT: RLS is off on %', t;
    end if;
    if has_table_privilege('anon', 'public.' || t, 'select') then
      raise exception 'POSTFLIGHT: anon can read %', t;
    end if;
  end loop;

  if (select sum(weight) from public.mkt_tier_weights) <> 100 then
    raise exception 'POSTFLIGHT: tier weights do not total 100';
  end if;
  if (select count(*) from public.mkt_city_rules where city = '*') <> 1 then
    raise exception 'POSTFLIGHT: default city rules row missing';
  end if;

  -- No marketplace function callable by anon or PUBLIC (aclexplode,
  -- grantee 0 = PUBLIC; CLAUDE.md, not a LIKE over the printed ACL).
  select count(*) into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
         lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
   where n.nspname = 'public' and p.proname like 'mkt\_%'
     and a.privilege_type = 'EXECUTE'
     and (a.grantee = 0 or a.grantee = 'anon'::regrole);
  if v_bad > 0 then
    raise exception 'POSTFLIGHT: % marketplace function grants reach anon/PUBLIC', v_bad;
  end if;

  -- The unauthenticated caller is refused, not let through (fail-open
  -- check): with no auth.uid(), mkt_can_act must be false, never NULL.
  if public.mkt_can_act('00000000-0000-0000-0000-000000000000') is distinct from false then
    raise exception 'POSTFLIGHT: mkt_can_act did not deny an unknown caller';
  end if;
end
$postflight$;

commit;
