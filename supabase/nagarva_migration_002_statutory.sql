-- ═══════════════════════════════════════════════════════════════════════════
-- NAGARVA MIGRATION 002 — STATUTORY & COMPLIANCE LAYER
-- Project: hqqcapifefsaqvotqvlt
-- Depends on: migration 001 (customers, vendors, vendor_bills, bank_accounts)
--
-- Covers: E-Way Bill register, GST return exports, TDS, statutory payroll,
--         transit insurance & claims, fleet compliance.
--
-- Conventions: org_id uuid | orders.id TEXT | soft delete triplet
--              RLS policy org_isolation, predicate org_id in (select current_org_ids())
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. E-WAY BILL REGISTER  [LEGAL]
--    Mandatory for goods movement above Rs.50,000. Mirrors the NIC EWB API
--    payload so generation is a direct field map, not a translation layer.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists eway_bills (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid,
  order_id          text references orders(id) on delete set null,
  -- NIC identifiers
  ewb_no            text,
  ewb_date          timestamptz,
  valid_until       timestamptz,
  -- document
  supply_type       text default 'O',          -- O=outward, I=inward
  sub_supply_type   text default '1',          -- 1=supply, 8=others (household goods)
  doc_type          text default 'INV',        -- INV | BIL | BOE | CHL | OTH
  doc_no            text,
  doc_date          date,
  -- consignor (from)
  from_gstin        text default 'URP',        -- URP for unregistered
  from_name         text,
  from_address1     text,
  from_address2     text,
  from_place        text,
  from_pincode      text,
  from_state_code   int,
  -- consignee (to)
  to_gstin          text default 'URP',
  to_name           text,
  to_address1       text,
  to_address2       text,
  to_place          text,
  to_pincode        text,
  to_state_code     int,
  -- goods
  hsn_code          text,
  product_name      text default 'Household Goods',
  product_desc      text,
  quantity          numeric default 1,
  unit_of_measure   text default 'NOS',
  taxable_value     numeric default 0,
  cgst_rate         numeric default 0,
  sgst_rate         numeric default 0,
  igst_rate         numeric default 0,
  cess_rate         numeric default 0,
  total_invoice_value numeric default 0,
  -- transport (Part A)
  trans_mode        text default '1',          -- 1=road 2=rail 3=air 4=ship
  trans_distance    int default 0,
  transporter_id    text,                      -- transporter GSTIN
  transporter_name  text,
  vendor_id         uuid references vendors(id) on delete set null,
  trans_doc_no      text,
  trans_doc_date    date,
  -- vehicle (Part B)
  vehicle_no        text,
  vehicle_type      text default 'R',          -- R=regular, O=ODC
  -- lifecycle
  status            text default 'draft',
                    -- draft|generated|part_b_pending|active|cancelled|expired
  extension_count   int default 0,
  cancelled_at      timestamptz,
  cancel_reason     text,
  api_request       jsonb,
  api_response      jsonb,
  generated_by      text,
  created_at        timestamptz default now(),
  updated_at        timestamptz default now()
);

create unique index if not exists eway_bills_no_uniq
  on eway_bills (org_id, ewb_no) where ewb_no is not null;
create index if not exists eway_bills_order_idx  on eway_bills (order_id);
create index if not exists eway_bills_status_idx on eway_bills (org_id, status, valid_until);

drop trigger if exists eway_bills_updated_at on eway_bills;
create trigger eway_bills_updated_at before update on eway_bills
  for each row execute function set_updated_at();

-- Part B vehicle changes must be logged; a transhipment updates the EWB
create table if not exists eway_vehicle_updates (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid,
  eway_bill_id  uuid references eway_bills(id) on delete cascade,
  vehicle_no    text not null,
  from_place    text,
  from_state_code int,
  reason_code   text,          -- 1=due to breakdown 2=transhipment 3=others
  reason_note   text,
  trans_mode    text default '1',
  updated_at_nic timestamptz,
  api_response  jsonb,
  created_at    timestamptz default now()
);
create index if not exists eway_veh_upd_idx on eway_vehicle_updates (eway_bill_id);

-- Consolidated EWB for part-load vehicles carrying several consignments
create table if not exists eway_consolidated (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  ceww_no         text,
  generated_at    timestamptz default now(),
  vehicle_no      text,
  trans_mode      text default '1',
  from_place      text,
  from_state_code int,
  ewb_ids         uuid[] default '{}',
  api_response    jsonb,
  created_at      timestamptz default now()
);

alter table orders add column if not exists eway_bill_id uuid
  references eway_bills(id) on delete set null;


-- ───────────────────────────────────────────────────────────────────────────
-- 2. GST RETURNS  [LEGAL]
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists gst_returns (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  return_type     text not null,          -- gstr1 | gstr3b
  period_month    int not null check (period_month between 1 and 12),
  period_year     int not null,
  gstin           text,
  status          text default 'draft',   -- draft | generated | filed
  -- GSTR-3B summary
  outward_taxable numeric default 0,
  outward_cgst    numeric default 0,
  outward_sgst    numeric default 0,
  outward_igst    numeric default 0,
  itc_cgst        numeric default 0,
  itc_sgst        numeric default 0,
  itc_igst        numeric default 0,
  net_payable     numeric default 0,
  payload         jsonb,                  -- generated JSON for portal upload
  filed_at        timestamptz,
  arn             text,                   -- acknowledgement reference number
  generated_by    text,
  created_at      timestamptz default now()
);
create unique index if not exists gst_returns_period_uniq
  on gst_returns (org_id, return_type, period_year, period_month);

-- Credit / debit notes against issued invoices
create table if not exists credit_notes (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  note_type       text not null default 'credit',   -- credit | debit
  note_no         text,
  note_date       date default current_date,
  order_id        text references orders(id) on delete set null,
  customer_id     uuid references customers(id) on delete set null,
  original_invoice_no text,
  reason          text,
  taxable_amount  numeric default 0,
  gst_mode        text default 'cgst_sgst',
  gst_pct         numeric default 18,
  gst_amount      numeric default 0,
  total_amount    numeric default 0,
  created_at      timestamptz default now()
);
create unique index if not exists credit_notes_no_uniq
  on credit_notes (org_id, note_no) where note_no is not null;
create index if not exists credit_notes_order_idx on credit_notes (order_id);

-- GSTR-1 B2B: registered customers only
create or replace view gstr1_b2b_view as
select
  o.org_id,
  c.gstin                        as customer_gstin,
  coalesce(c.company_name, c.name) as customer_name,
  o.invoice_no,
  o.invoice_issued_at::date      as invoice_date,
  o.amount                       as invoice_value,
  '996719'                       as sac_code,
  o.quote_gst_pct                as rate,
  o.quote_subtotal               as taxable_value,
  case when o.quote_gst_mode = 'igst' then o.quote_gst_amount else 0 end as igst,
  case when o.quote_gst_mode <> 'igst' then o.quote_gst_amount / 2 else 0 end as cgst,
  case when o.quote_gst_mode <> 'igst' then o.quote_gst_amount / 2 else 0 end as sgst,
  o.branch
from orders o
join customers c on c.id = o.customer_id
where o.invoice_no is not null
  and o.deleted_at is null
  and coalesce(c.gstin, '') <> '';

-- GSTR-1 B2C: unregistered, aggregated
create or replace view gstr1_b2c_view as
select
  o.org_id,
  date_trunc('month', o.invoice_issued_at)::date as period,
  o.quote_gst_pct                as rate,
  sum(o.quote_subtotal)          as taxable_value,
  sum(case when o.quote_gst_mode = 'igst' then o.quote_gst_amount else 0 end) as igst,
  sum(case when o.quote_gst_mode <> 'igst' then o.quote_gst_amount / 2 else 0 end) as cgst,
  sum(case when o.quote_gst_mode <> 'igst' then o.quote_gst_amount / 2 else 0 end) as sgst,
  count(*)                       as invoice_count
from orders o
left join customers c on c.id = o.customer_id
where o.invoice_no is not null
  and o.deleted_at is null
  and coalesce(c.gstin, '') = ''
group by o.org_id, date_trunc('month', o.invoice_issued_at), o.quote_gst_pct;

-- Input tax credit register, from vendor bills
create or replace view itc_register_view as
select
  vb.org_id,
  date_trunc('month', vb.bill_date)::date as period,
  v.name                as vendor_name,
  v.gstin               as vendor_gstin,
  vb.bill_no,
  vb.bill_date,
  vb.taxable_amount,
  vb.gst_mode,
  case when vb.gst_mode = 'igst' then vb.gst_amount else 0 end as igst,
  case when vb.gst_mode = 'cgst_sgst' then vb.gst_amount / 2 else 0 end as cgst,
  case when vb.gst_mode = 'cgst_sgst' then vb.gst_amount / 2 else 0 end as sgst,
  vb.is_reverse_charge,
  vb.total_amount
from vendor_bills vb
join vendors v on v.id = vb.vendor_id
where vb.deleted_at is null
  and vb.gst_amount > 0;


-- ───────────────────────────────────────────────────────────────────────────
-- 3. TDS  [LEGAL] — Section 194C on transport contractors
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists tds_entries (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  vendor_id       uuid references vendors(id) on delete set null,
  bill_id         uuid references vendor_bills(id) on delete set null,
  payment_id      uuid references vendor_payments(id) on delete set null,
  section         text default '194C',
  fy              text,                    -- e.g. 2026-27
  quarter         text,                    -- Q1 | Q2 | Q3 | Q4
  taxable_amount  numeric default 0,
  rate_pct        numeric default 1,
  tds_amount      numeric default 0,
  deducted_on     date default current_date,
  -- remittance
  challan_no      text,
  challan_date    date,
  bsr_code        text,
  deposited       boolean default false,
  -- certificate
  form16a_issued  boolean default false,
  form16a_url     text,
  created_at      timestamptz default now()
);
create index if not exists tds_vendor_idx on tds_entries (org_id, vendor_id, fy);
create index if not exists tds_quarter_idx on tds_entries (org_id, fy, quarter);


-- ───────────────────────────────────────────────────────────────────────────
-- 4. STATUTORY PAYROLL  [LEGAL]
--    staff already carries pf_applicable / pf_employee_pct / uan_no /
--    esic_applicable / esic_employee_pct / esic_no. This is the run engine.
-- ───────────────────────────────────────────────────────────────────────────

alter table staff add column if not exists pt_applicable boolean default false;
alter table staff add column if not exists basic_pct numeric default 100;
alter table staff add column if not exists pan text;
alter table staff add column if not exists bank_account text;
alter table staff add column if not exists bank_ifsc text;
alter table staff add column if not exists date_of_joining date;

create table if not exists payroll_runs (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid,
  period_month      int not null check (period_month between 1 and 12),
  period_year       int not null,
  branch            text,
  status            text default 'draft',   -- draft | approved | paid | cancelled
  staff_count       int default 0,
  total_gross       numeric default 0,
  total_deductions  numeric default 0,
  total_net         numeric default 0,
  total_pf_employer numeric default 0,
  total_esi_employer numeric default 0,
  run_at            timestamptz default now(),
  approved_by       text,
  approved_at       timestamptz,
  paid_at           timestamptz,
  account_id        uuid references bank_accounts(id) on delete set null,
  notes             text,
  created_at        timestamptz default now()
);
create unique index if not exists payroll_runs_period_uniq
  on payroll_runs (org_id, period_year, period_month, coalesce(branch, ''));

create table if not exists payslips (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid,
  run_id            uuid references payroll_runs(id) on delete cascade,
  staff_id          uuid references staff(id) on delete set null,
  payslip_no        text,
  -- attendance
  days_in_month     int default 30,
  days_present      numeric default 0,
  days_absent       numeric default 0,
  half_days         numeric default 0,
  overtime_hours    numeric default 0,
  -- earnings
  basic             numeric default 0,
  hra               numeric default 0,
  conveyance        numeric default 0,
  order_incentive   numeric default 0,
  overtime_amount   numeric default 0,
  other_earnings    jsonb default '{}'::jsonb,
  gross             numeric default 0,
  -- deductions
  pf_employee       numeric default 0,
  pf_employer       numeric default 0,
  esi_employee      numeric default 0,
  esi_employer      numeric default 0,
  professional_tax  numeric default 0,
  advance_recovery  numeric default 0,
  other_deductions  jsonb default '{}'::jsonb,
  total_deductions  numeric default 0,
  net_pay           numeric default 0,
  -- payout
  paid              boolean default false,
  paid_at           timestamptz,
  payment_mode      text,
  pdf_url           text,
  created_at        timestamptz default now()
);
create index if not exists payslips_run_idx   on payslips (run_id);
create index if not exists payslips_staff_idx on payslips (org_id, staff_id);
create unique index if not exists payslips_no_uniq
  on payslips (org_id, payslip_no) where payslip_no is not null;


-- ───────────────────────────────────────────────────────────────────────────
-- 5. TRANSIT INSURANCE & CLAIMS
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists insurance_policies (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid,
  order_id          text references orders(id) on delete set null,
  customer_id       uuid references customers(id) on delete set null,
  policy_type       text default 'declared_value',
                    -- carrier_liability | all_risk | declared_value | transit
  insurer_name      text,
  policy_no         text,
  declared_value    numeric default 0,
  premium_pct       numeric default 0,
  premium_amount    numeric default 0,
  gst_on_premium    numeric default 0,
  total_premium     numeric default 0,
  coverage_start    date,
  coverage_end      date,
  excess_amount     numeric default 0,      -- deductible borne by customer
  certificate_url   text,
  status            text default 'active',  -- quoted|active|expired|claimed|cancelled
  notes             text,
  created_at        timestamptz default now(),
  updated_at        timestamptz default now()
);
create index if not exists ins_policies_order_idx on insurance_policies (order_id);
create unique index if not exists ins_policies_no_uniq
  on insurance_policies (org_id, policy_no) where policy_no is not null;

drop trigger if exists ins_policies_updated_at on insurance_policies;
create trigger ins_policies_updated_at before update on insurance_policies
  for each row execute function set_updated_at();

alter table orders add column if not exists insurance_opted boolean default false;
alter table orders add column if not exists insurance_policy_id uuid
  references insurance_policies(id) on delete set null;

create table if not exists claims (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid,
  claim_no          text,
  order_id          text references orders(id) on delete set null,
  policy_id         uuid references insurance_policies(id) on delete set null,
  customer_id       uuid references customers(id) on delete set null,
  complaint_id      uuid references complaints(id) on delete set null,
  liable_vendor_id  uuid references vendors(id) on delete set null,
  claim_type        text default 'damage',   -- damage | loss | delay | theft
  intimated_at      timestamptz default now(),
  incident_date     date,
  description       text,
  claimed_amount    numeric default 0,
  -- survey
  surveyor_name     text,
  surveyor_phone    text,
  survey_date       date,
  surveyor_report_url text,
  assessed_amount   numeric default 0,
  -- outcome
  approved_amount   numeric default 0,
  settled_amount    numeric default 0,
  settled_at        timestamptz,
  settlement_mode   text,
  borne_by          text,                   -- insurer | company | vendor | customer
  status            text default 'intimated',
                    -- intimated|under_survey|assessed|approved|rejected|settled|closed
  rejection_reason  text,
  notes             text,
  created_by        text,
  created_at        timestamptz default now(),
  updated_at        timestamptz default now()
);
create unique index if not exists claims_no_uniq
  on claims (org_id, claim_no) where claim_no is not null;
create index if not exists claims_order_idx  on claims (order_id);
create index if not exists claims_status_idx on claims (org_id, status);

drop trigger if exists claims_updated_at on claims;
create trigger claims_updated_at before update on claims
  for each row execute function set_updated_at();

create table if not exists claim_items (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  claim_id        uuid references claims(id) on delete cascade,
  item_name       text not null,
  description     text,
  quantity        numeric default 1,
  declared_value  numeric default 0,
  claimed_amount  numeric default 0,
  assessed_amount numeric default 0,
  damage_type     text,
  photo_urls      text[] default '{}',
  created_at      timestamptz default now()
);
create index if not exists claim_items_claim_idx on claim_items (claim_id);

-- Tie the existing complaints module into claims
alter table complaints add column if not exists claim_id uuid
  references claims(id) on delete set null;


-- ───────────────────────────────────────────────────────────────────────────
-- 6. FLEET COMPLIANCE
--    vehicles already has insurance_expiry / permit_expiry / last_service.
-- ───────────────────────────────────────────────────────────────────────────

alter table vehicles add column if not exists fitness_expiry date;
alter table vehicles add column if not exists puc_expiry date;
alter table vehicles add column if not exists road_tax_expiry date;
alter table vehicles add column if not exists national_permit_expiry date;
alter table vehicles add column if not exists next_service_date date;
alter table vehicles add column if not exists next_service_km int;
alter table vehicles add column if not exists current_km int default 0;
alter table vehicles add column if not exists owner_type text default 'own';
alter table vehicles add column if not exists vendor_id uuid
  references vendors(id) on delete set null;

create table if not exists vehicle_service_logs (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  vehicle_id      uuid references vehicles(id) on delete cascade,
  service_date    date default current_date,
  service_type    text,                -- routine | repair | tyre | battery | breakdown
  odometer_km     int,
  garage_name     text,
  vendor_id       uuid references vendors(id) on delete set null,
  parts_cost      numeric default 0,
  labour_cost     numeric default 0,
  total_cost      numeric default 0,
  next_due_date   date,
  next_due_km     int,
  notes           text,
  created_at      timestamptz default now()
);
create index if not exists veh_service_idx on vehicle_service_logs (vehicle_id, service_date desc);

-- Single view driving the expiry alert feed
create or replace view fleet_compliance_view as
select v.org_id, v.id as vehicle_id, v.reg_no, d.doc_type, d.expiry_date,
       (d.expiry_date - current_date) as days_remaining,
       case
         when d.expiry_date < current_date then 'expired'
         when d.expiry_date <= current_date + 7  then 'critical'
         when d.expiry_date <= current_date + 15 then 'warning'
         when d.expiry_date <= current_date + 30 then 'upcoming'
         else 'ok'
       end as alert_level
from vehicles v
cross join lateral (values
  ('insurance',       v.insurance_expiry),
  ('permit',          v.permit_expiry),
  ('fitness',         v.fitness_expiry),
  ('puc',             v.puc_expiry),
  ('road_tax',        v.road_tax_expiry),
  ('national_permit', v.national_permit_expiry)
) as d(doc_type, expiry_date)
where d.expiry_date is not null
  and v.deleted_at is null;


-- ───────────────────────────────────────────────────────────────────────────
-- 7. ROW LEVEL SECURITY
-- ───────────────────────────────────────────────────────────────────────────

do $$
declare t text;
begin
  foreach t in array array[
    'eway_bills','eway_vehicle_updates','eway_consolidated',
    'gst_returns','credit_notes','tds_entries',
    'payroll_runs','payslips',
    'insurance_policies','claims','claim_items',
    'vehicle_service_logs'
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
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════
--
-- select count(*) as new_tables from information_schema.tables
--  where table_schema='public' and table_name in
--   ('eway_bills','eway_vehicle_updates','eway_consolidated','gst_returns',
--    'credit_notes','tds_entries','payroll_runs','payslips',
--    'insurance_policies','claims','claim_items','vehicle_service_logs');
--   -- expect 12
--
-- select count(*) as new_policies from pg_policies
--  where schemaname='public' and policyname='org_isolation'
--    and tablename in ('eway_bills','gst_returns','payroll_runs','claims');
--   -- expect 4
--
-- select * from fleet_compliance_view where alert_level <> 'ok' order by days_remaining;
-- select * from gstr1_b2b_view limit 5;
