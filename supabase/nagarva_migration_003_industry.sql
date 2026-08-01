-- ═══════════════════════════════════════════════════════════════════════════
-- NAGARVA MIGRATION 003 — INDUSTRY DEPTH
-- Project: hqqcapifefsaqvotqvlt
-- Depends on: 001 (customers, vendors, bank_accounts) · 002 (eway_bills)
--
-- Covers: Rate card & pricing engine, storage/warehousing, part-load trips
--         with cost allocation, LR/consignment register with POD capture.
--
-- Conventions: org_id uuid | orders.id TEXT | soft delete triplet
--              RLS org_isolation, org_id in (select current_org_ids())
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. RATE CARD & PRICING ENGINE
--    pricing_config (jsonb stub) stays for global defaults. This is the
--    structured engine that auto-quotes from survey CFT.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists rate_cards (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  name            text not null,
  code            text,
  card_type       text default 'standard',   -- standard | corporate | seasonal
  customer_id     uuid references customers(id) on delete cascade,
  branch          text,
  valid_from      date default current_date,
  valid_to        date,
  is_default      boolean default false,
  active          boolean default true,
  notes           text,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now(),
  deleted_at      timestamptz,
  deleted_by      text,
  delete_reason   text
);
create index if not exists rate_cards_org_idx  on rate_cards (org_id, active);
create index if not exists rate_cards_cust_idx on rate_cards (customer_id);
create unique index if not exists rate_cards_code_uniq
  on rate_cards (org_id, code) where code is not null and deleted_at is null;
create unique index if not exists rate_cards_default_uniq
  on rate_cards (org_id) where is_default = true and deleted_at is null;

drop trigger if exists rate_cards_updated_at on rate_cards;
create trigger rate_cards_updated_at before update on rate_cards
  for each row execute function set_updated_at();

-- Close the dangling reference left by migration 001
alter table customers drop constraint if exists customers_rate_card_fk;
alter table customers add constraint customers_rate_card_fk
  foreign key (rate_card_id) references rate_cards(id) on delete set null;

-- Base transport pricing: distance slab x CFT slab
create table if not exists rate_card_rules (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  card_id         uuid references rate_cards(id) on delete cascade,
  service         text default 'home_shifting',
  order_type      text default 'local',      -- local | outstation
  min_km          numeric default 0,
  max_km          numeric,
  min_cft         numeric default 0,
  max_cft         numeric,
  base_amount     numeric default 0,
  per_km_rate     numeric default 0,
  per_cft_rate    numeric default 0,
  min_charge      numeric default 0,
  vehicle_type    text,
  created_at      timestamptz default now()
);
create index if not exists rc_rules_card_idx on rate_card_rules (card_id, order_type);

-- Per-charge-head rates. Heads match the 15 quote line items.
create table if not exists rate_card_charges (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  card_id         uuid references rate_cards(id) on delete cascade,
  charge_key      text not null,
                  -- packing|unpacking|loading|unloading|transport|materials
                  -- acUninstall|acInstall|tvUninstall|tvInstall|wardrobe
                  -- carpenter|electrician|bikeTransport|otherCharges
  label           text,
  unit            text default 'flat',       -- flat|per_cft|per_item|per_floor|percent
  rate            numeric default 0,
  min_amount      numeric default 0,
  is_optional     boolean default true,
  sort_order      int default 0,
  created_at      timestamptz default now()
);
create unique index if not exists rc_charges_uniq on rate_card_charges (card_id, charge_key);

-- Floor / lift / long-carry differentials
create table if not exists rate_card_floor_charges (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  card_id         uuid references rate_cards(id) on delete cascade,
  floor_from      int default 0,
  floor_to        int default 0,
  has_lift        boolean default false,
  charge_type     text default 'flat',       -- flat | per_cft | per_floor
  amount          numeric default 0,
  long_carry_m    int default 0,
  long_carry_rate numeric default 0,
  created_at      timestamptz default now()
);
create index if not exists rc_floor_card_idx on rate_card_floor_charges (card_id);

-- Peak-date and seasonal multipliers
create table if not exists rate_card_multipliers (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  card_id         uuid references rate_cards(id) on delete cascade,
  name            text,
  date_from       date,
  date_to         date,
  weekday_mask    int[] default '{}',        -- 0=Sun .. 6=Sat, empty = all days
  multiplier_pct  numeric default 100,       -- 120 = +20%
  applies_to      text default 'total',      -- total | transport | labour
  created_at      timestamptz default now()
);
create index if not exists rc_mult_card_idx on rate_card_multipliers (card_id, date_from, date_to);

-- Materials need a sell price, not just cost
alter table materials add column if not exists selling_price numeric default 0;
alter table materials add column if not exists hsn_code text;

-- Rate card linkage
alter table orders     add column if not exists rate_card_id uuid references rate_cards(id) on delete set null;
alter table quotations add column if not exists rate_card_id uuid references rate_cards(id) on delete set null;


-- ───────────────────────────────────────────────────────────────────────────
-- 2. STORAGE / WAREHOUSING
--    Goods held between moves. Separate job type, recurring billing.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists warehouses (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  name            text not null,
  code            text,
  address         text,
  city            text,
  pincode         text,
  branch          text,
  capacity_cft    numeric default 0,
  contact_person  text,
  contact_phone   text,
  vendor_id       uuid references vendors(id) on delete set null,  -- third-party godown
  active          boolean default true,
  created_at      timestamptz default now(),
  deleted_at      timestamptz
);
create index if not exists warehouses_org_idx on warehouses (org_id, active);

create table if not exists storage_jobs (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid,
  job_no            text,
  customer_id       uuid references customers(id) on delete set null,
  order_id          text references orders(id) on delete set null,
  warehouse_id      uuid references warehouses(id) on delete set null,
  in_date           date default current_date,
  expected_out_date date,
  out_date          date,
  total_cft         numeric default 0,
  package_count     int default 0,
  billing_mode      text default 'per_month',  -- per_day | per_month | flat
  rate              numeric default 0,
  min_billing_days  int default 0,
  security_deposit  numeric default 0,
  handling_in_charge  numeric default 0,
  handling_out_charge numeric default 0,
  declared_value    numeric default 0,
  insurance_policy_id uuid references insurance_policies(id) on delete set null,
  status            text default 'in_storage',
                    -- quoted | in_storage | partially_out | closed | cancelled
  notes             text,
  created_at        timestamptz default now(),
  updated_at        timestamptz default now(),
  deleted_at        timestamptz,
  deleted_by        text,
  delete_reason     text
);
create unique index if not exists storage_jobs_no_uniq
  on storage_jobs (org_id, job_no) where job_no is not null;
create index if not exists storage_jobs_cust_idx   on storage_jobs (customer_id);
create index if not exists storage_jobs_status_idx on storage_jobs (org_id, status);

drop trigger if exists storage_jobs_updated_at on storage_jobs;
create trigger storage_jobs_updated_at before update on storage_jobs
  for each row execute function set_updated_at();

create table if not exists storage_items (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  storage_job_id  uuid references storage_jobs(id) on delete cascade,
  item_name       text not null,
  description     text,
  quantity        numeric default 1,
  cft             numeric default 0,
  rack_location   text,
  condition_in    text,
  condition_out   text,
  photo_urls      text[] default '{}',
  in_date         date,
  out_date        date,
  status          text default 'stored',     -- stored | released | damaged | lost
  created_at      timestamptz default now()
);
create index if not exists storage_items_job_idx on storage_items (storage_job_id);

-- Recurring billing periods for a storage job
create table if not exists storage_billing_cycles (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  storage_job_id  uuid references storage_jobs(id) on delete cascade,
  period_start    date not null,
  period_end      date not null,
  billable_days   int default 0,
  rate            numeric default 0,
  amount          numeric default 0,
  gst_pct         numeric default 18,
  gst_amount      numeric default 0,
  total_amount    numeric default 0,
  invoice_no      text,
  status          text default 'unbilled',   -- unbilled | invoiced | paid | waived
  invoiced_at     timestamptz,
  paid_at         timestamptz,
  created_at      timestamptz default now()
);
create unique index if not exists storage_cycle_uniq
  on storage_billing_cycles (storage_job_id, period_start);
create index if not exists storage_cycle_status_idx
  on storage_billing_cycles (org_id, status);


-- ───────────────────────────────────────────────────────────────────────────
-- 3. TRIPS & PART-LOAD CONSOLIDATION
--    vehicle_trips is 1:1 with an order and stays as legacy. `trips` is
--    many-orders-per-vehicle, which is how outstation economics actually work.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists trips (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  trip_no         text,
  trip_type       text default 'outstation', -- local | outstation | part_load
  vehicle_id      uuid references vehicles(id) on delete set null,
  vehicle_no      text,
  is_hired        boolean default false,
  vendor_id       uuid references vendors(id) on delete set null,
  hire_amount     numeric default 0,
  driver_name     text,
  driver_phone    text,
  from_loc        text,
  to_loc          text,
  start_date      date,
  end_date        date,
  km_start        int,
  km_end          int,
  total_km        int generated always as (greatest(coalesce(km_end,0) - coalesce(km_start,0), 0)) stored,
  fuel_litres     numeric default 0,
  status          text default 'planned',
                  -- planned | loading | in_transit | delivering | completed | cancelled
  branch          text,
  notes           text,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now(),
  deleted_at      timestamptz
);
create unique index if not exists trips_no_uniq
  on trips (org_id, trip_no) where trip_no is not null;
create index if not exists trips_status_idx  on trips (org_id, status, start_date);
create index if not exists trips_vehicle_idx on trips (vehicle_id);

drop trigger if exists trips_updated_at on trips;
create trigger trips_updated_at before update on trips
  for each row execute function set_updated_at();

-- Which orders ride on which trip, and how trip cost splits between them
create table if not exists trip_orders (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid,
  trip_id           uuid references trips(id) on delete cascade,
  order_id          text references orders(id) on delete cascade,
  pickup_seq        int default 1,
  drop_seq          int default 1,
  cft_share         numeric default 0,
  weight_share_kg   numeric default 0,
  allocation_pct    numeric default 0,       -- share of trip cost, 0-100
  allocated_cost    numeric default 0,
  picked_up_at      timestamptz,
  delivered_at      timestamptz,
  notes             text,
  created_at        timestamptz default now()
);
create unique index if not exists trip_orders_uniq on trip_orders (trip_id, order_id);
create index if not exists trip_orders_order_idx on trip_orders (order_id);

create table if not exists trip_expenses (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  trip_id         uuid references trips(id) on delete cascade,
  expense_type    text not null,
                  -- fuel|toll|parking|permit|rto|driver_bata|food|repair
                  -- loading|unloading|other
  amount          numeric not null default 0,
  quantity        numeric,                   -- litres for fuel
  rate            numeric,
  location        text,
  vendor_id       uuid references vendors(id) on delete set null,
  paid_by         text,                      -- driver | supervisor | office
  receipt_url     text,
  expense_date    date default current_date,
  note            text,
  created_at      timestamptz default now()
);
create index if not exists trip_exp_trip_idx on trip_expenses (trip_id, expense_date);

alter table orders add column if not exists trip_id uuid references trips(id) on delete set null;
create index if not exists orders_trip_idx on orders (trip_id);

-- Trip profitability: allocated order revenue less trip cost
create or replace view trip_pnl_view as
select
  t.org_id,
  t.id                                as trip_id,
  t.trip_no,
  t.trip_type,
  t.vehicle_no,
  t.start_date,
  t.total_km,
  count(distinct tord.order_id)       as order_count,
  coalesce(sum(o.amount), 0)          as gross_revenue,
  coalesce(te.total_expenses, 0)      as trip_expenses,
  t.hire_amount,
  coalesce(sum(o.amount), 0)
    - coalesce(te.total_expenses, 0)
    - coalesce(t.hire_amount, 0)      as net_profit,
  case when t.total_km > 0
       then round(coalesce(te.total_expenses, 0) / t.total_km, 2)
       else 0 end                     as cost_per_km
from trips t
left join trip_orders tord on tord.trip_id = t.id
left join orders o         on o.id = tord.order_id and o.deleted_at is null
left join lateral (
  select sum(amount) as total_expenses
  from trip_expenses x where x.trip_id = t.id
) te on true
where t.deleted_at is null
group by t.org_id, t.id, t.trip_no, t.trip_type, t.vehicle_no,
         t.start_date, t.total_km, t.hire_amount, te.total_expenses;


-- ───────────────────────────────────────────────────────────────────────────
-- 4. LR / CONSIGNMENT REGISTER + POD
--    orders.lr_no / lr_issued_at exist. This is the register behind them.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists lr_series (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid,
  branch        text,
  fy            text not null,               -- e.g. 2026-27
  prefix        text default 'LR',
  last_number   int default 0,               -- "last issued" convention
  active        boolean default true,
  created_at    timestamptz default now()
);
create unique index if not exists lr_series_uniq
  on lr_series (org_id, coalesce(branch, ''), fy);

create table if not exists lr_register (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid,
  lr_no             text not null,
  lr_date           date default current_date,
  order_id          text references orders(id) on delete set null,
  trip_id           uuid references trips(id) on delete set null,
  eway_bill_id      uuid references eway_bills(id) on delete set null,
  -- consignor
  consignor_name    text,
  consignor_gstin   text,
  consignor_address text,
  consignor_phone   text,
  -- consignee
  consignee_name    text,
  consignee_gstin   text,
  consignee_address text,
  consignee_phone   text,
  -- consignment
  from_place        text,
  to_place          text,
  package_count     int default 0,
  description       text default 'Household Goods',
  actual_weight_kg  numeric default 0,
  charged_weight_kg numeric default 0,
  declared_value    numeric default 0,
  -- freight
  freight_amount    numeric default 0,
  freight_mode      text default 'paid',     -- paid | to_pay | tbb
  gst_payable_by    text default 'consignor',
  other_charges     numeric default 0,
  total_amount      numeric default 0,
  -- movement
  vehicle_no        text,
  driver_name       text,
  driver_phone      text,
  status            text default 'issued',
                    -- issued | in_transit | delivered | cancelled
  branch            text,
  remarks           text,
  created_by        text,
  created_at        timestamptz default now(),
  updated_at        timestamptz default now(),
  deleted_at        timestamptz
);
create unique index if not exists lr_register_no_uniq on lr_register (org_id, lr_no);
create index if not exists lr_register_order_idx  on lr_register (order_id);
create index if not exists lr_register_trip_idx   on lr_register (trip_id);
create index if not exists lr_register_status_idx on lr_register (org_id, status, lr_date);

drop trigger if exists lr_register_updated_at on lr_register;
create trigger lr_register_updated_at before update on lr_register
  for each row execute function set_updated_at();

alter table orders add column if not exists lr_id uuid
  references lr_register(id) on delete set null;

-- Proof of delivery
create table if not exists pod_records (
  id                  uuid primary key default gen_random_uuid(),
  org_id              uuid,
  lr_id               uuid references lr_register(id) on delete cascade,
  order_id            text references orders(id) on delete set null,
  delivered_at        timestamptz default now(),
  received_by_name    text,
  received_by_phone   text,
  relationship        text,                  -- self | family | neighbour | security
  signature_data      text,
  photo_urls          text[] default '{}',
  packages_delivered  int default 0,
  packages_short      int default 0,
  damage_noted        boolean default false,
  damage_description  text,
  otp_verified        boolean default false,
  remarks             text,
  captured_by         text,
  latitude            numeric,
  longitude           numeric,
  created_at          timestamptz default now()
);
create index if not exists pod_lr_idx    on pod_records (lr_id);
create index if not exists pod_order_idx on pod_records (order_id);


-- ───────────────────────────────────────────────────────────────────────────
-- 5. ROW LEVEL SECURITY
-- ───────────────────────────────────────────────────────────────────────────

do $$
declare t text;
begin
  foreach t in array array[
    'rate_cards','rate_card_rules','rate_card_charges',
    'rate_card_floor_charges','rate_card_multipliers',
    'warehouses','storage_jobs','storage_items','storage_billing_cycles',
    'trips','trip_orders','trip_expenses',
    'lr_series','lr_register','pod_records'
  ]
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists org_isolation on %I', t);
    execute format(
      'create policy org_isolation on %I for all
         using (org_id in (select current_org_ids()))
         with check (org_id in (select current_org_ids()))', t);
  end loop;
end $$;

commit;


-- ═══════════════════════════════════════════════════════════════════════════
-- SEED — one default rate card per org, with the 15 charge heads
-- ═══════════════════════════════════════════════════════════════════════════

begin;

insert into rate_cards (org_id, name, code, card_type, is_default)
select o.id, 'Standard Rate Card', 'STD', 'standard', true
from organizations o
where not exists (
  select 1 from rate_cards rc where rc.org_id = o.id and rc.is_default = true
);

insert into rate_card_charges (org_id, card_id, charge_key, label, unit, sort_order)
select rc.org_id, rc.id, k.charge_key, k.label, k.unit, k.sort_order
from rate_cards rc
cross join (values
  ('packing',       'Packing',        'per_cft', 1),
  ('unpacking',     'Unpacking',      'per_cft', 2),
  ('loading',       'Loading',        'flat',    3),
  ('unloading',     'Unloading',      'flat',    4),
  ('transport',     'Transport',      'flat',    5),
  ('materials',     'Materials',      'flat',    6),
  ('acUninstall',   'AC Uninstall',   'per_item',7),
  ('acInstall',     'AC Install',     'per_item',8),
  ('tvUninstall',   'TV Uninstall',   'per_item',9),
  ('tvInstall',     'TV Install',     'per_item',10),
  ('wardrobe',      'Wardrobe',       'per_item',11),
  ('carpenter',     'Carpenter',      'flat',    12),
  ('electrician',   'Electrician',    'flat',    13),
  ('bikeTransport', 'Bike Transport', 'per_item',14),
  ('otherCharges',  'Other',          'flat',    15)
) as k(charge_key, label, unit, sort_order)
where rc.is_default = true
on conflict (card_id, charge_key) do nothing;

-- Current FY LR series per org
insert into lr_series (org_id, fy, prefix, last_number)
select o.id,
       case when extract(month from current_date) >= 4
            then extract(year from current_date)::text || '-' ||
                 right((extract(year from current_date) + 1)::text, 2)
            else (extract(year from current_date) - 1)::text || '-' ||
                 right(extract(year from current_date)::text, 2)
       end,
       'LR', 0
from organizations o
where not exists (select 1 from lr_series s where s.org_id = o.id);

commit;


-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════
--
-- select
--   (select count(*) from information_schema.tables where table_schema='public'
--      and table_name in ('rate_cards','rate_card_rules','rate_card_charges',
--        'rate_card_floor_charges','rate_card_multipliers','warehouses',
--        'storage_jobs','storage_items','storage_billing_cycles','trips',
--        'trip_orders','trip_expenses','lr_series','lr_register','pod_records'))
--        as tables_expect_15,
--   (select count(*) from pg_policies where schemaname='public'
--      and policyname='org_isolation'
--      and tablename in ('rate_cards','storage_jobs','trips','lr_register'))
--        as policies_expect_4,
--   (select count(*) from rate_cards where is_default) as default_cards,
--   (select count(*) from rate_card_charges)           as charge_heads_expect_orgs_x_15,
--   (select count(*) from lr_series)                   as lr_series_seeded;
--
-- select * from trip_pnl_view limit 5;
