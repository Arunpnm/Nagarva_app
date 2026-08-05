-- ═══════════════════════════════════════════════════════════════════════════
-- NAGARVA MIGRATION 001 — ERP FOUNDATIONS
-- Project: hqqcapifefsaqvotqvlt
--
-- Conventions matched from the live schema:
--   org_id            uuid, nullable
--   surrogate keys    uuid default gen_random_uuid()
--   orders.id         TEXT  (NGV-XXXX)  -> FKs to orders use text
--   quotations.id     TEXT
--   soft delete       deleted_at / deleted_by / delete_reason
--   RLS policy name   org_isolation, cmd ALL
--   RLS predicate     org_id in (select current_org_ids())
--
-- RUN ORDER: sections are independent and idempotent. Run top to bottom.
-- Section 9 (back-fill) is the only one that writes data — read it first.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────────────
-- 0. Shared helpers
-- ───────────────────────────────────────────────────────────────────────────

create or replace function set_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- Normalise an Indian phone to its last 10 digits for identity matching.
create or replace function norm_phone(p text) returns text as $$
  select nullif(right(regexp_replace(coalesce(p,''), '\D', '', 'g'), 10), '');
$$ language sql immutable;


-- ───────────────────────────────────────────────────────────────────────────
-- 1. CUSTOMER MASTER
--    The structural gap: orders/leads currently carry a loose name + phone.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists customers (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid,
  customer_type     text not null default 'individual',   -- individual | corporate
  name              text not null,
  company_name      text,
  phone             text,
  phone_normalized  text generated always as (norm_phone(phone)) stored,
  alt_phone         text,
  email             text,
  gstin             text,
  pan               text,
  billing_address   text,
  city              text,
  state             text,
  pincode           text,
  source            text,
  branch            text,
  -- corporate credit control
  credit_limit      numeric default 0,
  credit_days       int default 0,
  rate_card_id      uuid,
  -- flags
  is_blacklisted    boolean default false,
  blacklist_reason  text,
  notes             text,
  customer_since    date default current_date,
  created_at        timestamptz default now(),
  updated_at        timestamptz default now(),
  deleted_at        timestamptz,
  deleted_by        text,
  delete_reason     text
);

create unique index if not exists customers_org_phone_uniq
  on customers (org_id, phone_normalized)
  where phone_normalized is not null and deleted_at is null;

create index if not exists customers_org_idx    on customers (org_id);
create index if not exists customers_name_idx   on customers (org_id, lower(name));
create index if not exists customers_gstin_idx  on customers (org_id, gstin);

drop trigger if exists customers_updated_at on customers;
create trigger customers_updated_at before update on customers
  for each row execute function set_updated_at();

-- Multiple shipping / site addresses per customer
create table if not exists customer_addresses (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid,
  customer_id   uuid references customers(id) on delete cascade,
  label         text,
  address       text,
  city          text,
  floor         int default 0,
  has_lift      boolean default false,
  pincode       text,
  is_primary    boolean default false,
  created_at    timestamptz default now()
);
create index if not exists cust_addr_cust_idx on customer_addresses (customer_id);

-- Named contacts for corporate accounts
create table if not exists customer_contacts (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid,
  customer_id   uuid references customers(id) on delete cascade,
  name          text not null,
  designation   text,
  phone         text,
  email         text,
  is_primary    boolean default false,
  created_at    timestamptz default now()
);
create index if not exists cust_contact_cust_idx on customer_contacts (customer_id);


-- ───────────────────────────────────────────────────────────────────────────
-- 2. VENDOR / SUBCONTRACTOR LAYER
--    Without this, order P&L is wrong on every subcontracted move.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists vendors (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid,
  vendor_type       text not null default 'transporter',
                    -- transporter | labour_contractor | material_supplier
                    -- warehouse | equipment | other
  name              text not null,
  contact_person    text,
  phone             text,
  email             text,
  gstin             text,
  pan               text,
  address           text,
  city              text,
  bank_name         text,
  bank_account      text,
  bank_ifsc         text,
  upi_id            text,
  -- statutory
  tds_applicable    boolean default false,
  tds_section       text default '194C',
  tds_rate_pct      numeric default 1,
  is_unregistered   boolean default false,   -- drives reverse-charge handling
  payment_terms_days int default 0,
  active            boolean default true,
  notes             text,
  created_at        timestamptz default now(),
  updated_at        timestamptz default now(),
  deleted_at        timestamptz,
  deleted_by        text,
  delete_reason     text
);
create index if not exists vendors_org_idx  on vendors (org_id);
create index if not exists vendors_type_idx on vendors (org_id, vendor_type);

drop trigger if exists vendors_updated_at on vendors;
create trigger vendors_updated_at before update on vendors
  for each row execute function set_updated_at();

-- Which vendor served which order
create table if not exists order_vendors (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid,
  order_id       text references orders(id) on delete cascade,
  vendor_id      uuid references vendors(id),
  service_type   text,
  agreed_amount  numeric default 0,
  notes          text,
  created_at     timestamptz default now()
);
create index if not exists order_vendors_order_idx  on order_vendors (order_id);
create index if not exists order_vendors_vendor_idx on order_vendors (vendor_id);

-- Vendor bills (payables)
create table if not exists vendor_bills (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  vendor_id       uuid references vendors(id),
  order_id        text references orders(id) on delete set null,
  bill_no         text,
  bill_date       date default current_date,
  due_date        date,
  taxable_amount  numeric default 0,
  gst_mode        text default 'none',       -- none | igst | cgst_sgst
  gst_pct         numeric default 0,
  gst_amount      numeric default 0,
  tds_amount      numeric default 0,
  total_amount    numeric default 0,
  paid_amount     numeric default 0,
  status          text default 'unpaid',     -- unpaid | partial | paid | cancelled
  is_reverse_charge boolean default false,
  notes           text,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now(),
  deleted_at      timestamptz,
  deleted_by      text,
  delete_reason   text
);
create index if not exists vendor_bills_vendor_idx on vendor_bills (vendor_id);
create index if not exists vendor_bills_order_idx  on vendor_bills (order_id);
create index if not exists vendor_bills_status_idx on vendor_bills (org_id, status);

drop trigger if exists vendor_bills_updated_at on vendor_bills;
create trigger vendor_bills_updated_at before update on vendor_bills
  for each row execute function set_updated_at();

-- Vendor payments (money out)
create table if not exists vendor_payments (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  vendor_id       uuid references vendors(id),
  bill_id         uuid references vendor_bills(id) on delete set null,
  account_id      uuid,                      -- FK added in section 3
  amount          numeric not null default 0,
  mode            text not null default 'cash',
  reference       text,
  paid_at         timestamptz default now(),
  note            text,
  created_at      timestamptz default now(),
  deleted_at      timestamptz,
  deleted_by      text,
  delete_reason   text
);
create index if not exists vendor_payments_vendor_idx on vendor_payments (vendor_id);
create index if not exists vendor_payments_bill_idx   on vendor_payments (bill_id);


-- ───────────────────────────────────────────────────────────────────────────
-- 3. BANK / CASH ACCOUNTS
--    payment_entries.mode is a text label; there is no account entity.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists bank_accounts (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid,
  account_type      text not null default 'bank',   -- cash | bank | upi | wallet
  name              text not null,
  bank_name         text,
  account_no        text,
  ifsc              text,
  upi_id            text,
  branch            text,
  opening_balance   numeric default 0,
  opening_date      date default current_date,
  is_default        boolean default false,
  active            boolean default true,
  created_at        timestamptz default now()
);
create index if not exists bank_accounts_org_idx on bank_accounts (org_id);

alter table vendor_payments
  drop constraint if exists vendor_payments_account_fk;
alter table vendor_payments
  add constraint vendor_payments_account_fk
  foreign key (account_id) references bank_accounts(id) on delete set null;

-- Tag incoming payments to an account
alter table payment_entries add column if not exists account_id uuid
  references bank_accounts(id) on delete set null;
alter table payment_entries add column if not exists reference text;
alter table payment_entries add column if not exists reconciled boolean default false;
alter table payment_entries add column if not exists reconciled_at timestamptz;


-- ───────────────────────────────────────────────────────────────────────────
-- 4. PARTY LEDGER
--    One append-only line per financial event, per party. Drives AR/AP aging
--    and statements without needing full double-entry yet.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists ledger_entries (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid,
  party_type    text not null,               -- customer | vendor | staff
  party_id      uuid not null,
  entry_date    date not null default current_date,
  entry_type    text not null,               -- invoice | payment | credit_note
                                             -- debit_note | opening | adjustment
  ref_table     text,
  ref_id        text,
  narration     text,
  debit         numeric default 0,
  credit        numeric default 0,
  account_id    uuid references bank_accounts(id) on delete set null,
  created_by    text,
  created_at    timestamptz default now()
);
create index if not exists ledger_party_idx on ledger_entries (org_id, party_type, party_id, entry_date);
create index if not exists ledger_ref_idx   on ledger_entries (ref_table, ref_id);


-- ───────────────────────────────────────────────────────────────────────────
-- 5. ORDER GAPS — columns the Master Brief needs that do not yet exist
-- ───────────────────────────────────────────────────────────────────────────

alter table orders add column if not exists customer_id uuid
  references customers(id) on delete set null;
alter table orders add column if not exists wa_muted boolean default false;
alter table orders add column if not exists vehicle_id uuid
  references vehicles(id) on delete set null;
alter table orders add column if not exists third_party_vehicle boolean default false;

-- E-way bill (LEGAL — goods movement above Rs.50,000)
alter table orders add column if not exists declared_value numeric default 0;
alter table orders add column if not exists eway_bill_no text;
alter table orders add column if not exists eway_generated_at timestamptz;
alter table orders add column if not exists eway_valid_until timestamptz;
alter table orders add column if not exists eway_status text;   -- active|cancelled|expired

-- E-invoice / IRN (LEGAL above the turnover threshold)
alter table orders add column if not exists irn text;
alter table orders add column if not exists irn_ack_no text;
alter table orders add column if not exists irn_generated_at timestamptz;
alter table orders add column if not exists irn_qr_data text;

create index if not exists orders_customer_idx on orders (customer_id);

-- Leads link to the same customer identity
alter table leads add column if not exists customer_id uuid
  references customers(id) on delete set null;
create index if not exists leads_customer_idx on leads (customer_id);


-- ───────────────────────────────────────────────────────────────────────────
-- 6. ADD-ON SERVICES  (post-quote upsell; rolls into Revenue Final)
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists addons (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid,
  order_id      text references orders(id) on delete cascade,
  description   text not null,
  amount        numeric default 0,
  status        text default 'pending',      -- pending | done | cancelled
  assigned_to   uuid references staff(id) on delete set null,
  completed_at  timestamptz,
  created_at    timestamptz default now()
);
create index if not exists addons_order_idx on addons (order_id);


-- ───────────────────────────────────────────────────────────────────────────
-- 7. REVIEWS
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists reviews (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid,
  order_id      text references orders(id) on delete set null,
  customer_id   uuid references customers(id) on delete set null,
  rating        int check (rating between 1 and 5),
  comment       text,
  channel       text default 'internal',     -- internal | google | whatsapp
  requested_at  timestamptz,
  responded_at  timestamptz,
  branch        text,
  created_at    timestamptz default now()
);
create index if not exists reviews_org_idx   on reviews (org_id, created_at desc);
create index if not exists reviews_order_idx on reviews (order_id);


-- ───────────────────────────────────────────────────────────────────────────
-- 8. WHATSAPP INBOX
--    Source of the "Auto-created from WhatsApp reply" leads.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists wa_contacts (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid,
  phone             text not null,
  phone_normalized  text generated always as (norm_phone(phone)) stored,
  display_name      text,
  customer_id       uuid references customers(id) on delete set null,
  lead_id           uuid references leads(id) on delete set null,
  last_message_at   timestamptz,
  last_message_text text,
  unread_count      int default 0,
  muted             boolean default false,
  created_at        timestamptz default now()
);
create unique index if not exists wa_contacts_org_phone_uniq
  on wa_contacts (org_id, phone_normalized);
create index if not exists wa_contacts_recent_idx
  on wa_contacts (org_id, last_message_at desc);

create table if not exists wa_messages (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid,
  contact_id    uuid references wa_contacts(id) on delete cascade,
  wa_message_id text,
  direction     text not null,               -- in | out
  msg_type      text default 'text',         -- text|image|document|audio|unsupported
  body          text,
  media_url     text,
  template_name text,
  status        text,                        -- sent|delivered|read|failed
  error_code    text,
  sent_at       timestamptz default now(),
  created_at    timestamptz default now()
);
create index if not exists wa_messages_contact_idx on wa_messages (contact_id, sent_at desc);
create unique index if not exists wa_messages_waid_uniq
  on wa_messages (org_id, wa_message_id) where wa_message_id is not null;


-- ───────────────────────────────────────────────────────────────────────────
-- 9. TENANT BILLING & USAGE  (multi-tenant SaaS layer)
--    subscription_plans + organizations.plan_status exist.
--    What a tenant was charged, and what they have consumed, does not.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists org_subscriptions (
  id                  uuid primary key default gen_random_uuid(),
  org_id              uuid not null,
  plan_id             uuid references subscription_plans(id),
  status              text not null default 'trialing',
                      -- trialing | active | past_due | grace | suspended | cancelled
  billing_period      text default 'monthly',   -- monthly | yearly
  amount_inr          numeric default 0,
  started_at          timestamptz default now(),
  current_period_start timestamptz default now(),
  current_period_end  timestamptz,
  trial_ends_at       timestamptz,
  grace_ends_at       timestamptz,
  cancelled_at        timestamptz,
  cancel_reason       text,
  auto_renew          boolean default true,
  gateway             text default 'razorpay',
  gateway_sub_id      text,
  coupon_code         text,
  created_at          timestamptz default now(),
  updated_at          timestamptz default now()
);
create index if not exists org_subs_org_idx    on org_subscriptions (org_id);
create index if not exists org_subs_status_idx on org_subscriptions (status, current_period_end);

drop trigger if exists org_subs_updated_at on org_subscriptions;
create trigger org_subs_updated_at before update on org_subscriptions
  for each row execute function set_updated_at();

-- Nagarva's own GST invoices to the tenant
create table if not exists platform_invoices (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid not null,
  subscription_id   uuid references org_subscriptions(id) on delete set null,
  invoice_no        text,
  invoice_date      date default current_date,
  period_start      date,
  period_end        date,
  taxable_amount    numeric default 0,
  gst_mode          text default 'cgst_sgst',
  gst_pct           numeric default 18,
  gst_amount        numeric default 0,
  total_amount      numeric default 0,
  status            text default 'unpaid',   -- unpaid | paid | failed | refunded
  paid_at           timestamptz,
  gateway_payment_id text,
  pdf_url           text,
  created_at        timestamptz default now()
);
create index if not exists platform_inv_org_idx on platform_invoices (org_id, invoice_date desc);
create unique index if not exists platform_inv_no_uniq
  on platform_invoices (invoice_no) where invoice_no is not null;

-- Metering against subscription_plans.limits
create table if not exists org_usage (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null,
  period_start  date not null,
  period_end    date not null,
  metric        text not null,              -- orders|users|branches|wa_messages|storage_mb
  used          numeric default 0,
  limit_value   numeric,
  updated_at    timestamptz default now()
);
create unique index if not exists org_usage_uniq
  on org_usage (org_id, period_start, metric);
create index if not exists org_usage_org_idx on org_usage (org_id, period_start desc);

-- Dunning / lifecycle event trail
create table if not exists billing_events (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null,
  event_type    text not null,   -- trial_started|renewed|payment_failed|reminder_sent
                                 -- grace_started|suspended|reactivated|plan_changed
  detail        jsonb default '{}'::jsonb,
  created_at    timestamptz default now()
);
create index if not exists billing_events_org_idx on billing_events (org_id, created_at desc);


-- ───────────────────────────────────────────────────────────────────────────
-- 10. DOCUMENT STORE  (KYC, PODs, damage photos — quota-tied)
--     document_signatures already covers e-sign; this is general file storage.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists documents (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid,
  entity_type   text not null,              -- order|lead|customer|vendor|staff|vehicle
  entity_id     text not null,
  doc_type      text,                       -- kyc|pod|damage_photo|invoice|contract|other
  file_name     text,
  storage_path  text not null,
  mime_type     text,
  size_bytes    bigint default 0,
  uploaded_by   text,
  is_sensitive  boolean default false,      -- KYC/ID -> restricted roles only
  created_at    timestamptz default now(),
  deleted_at    timestamptz
);
create index if not exists documents_entity_idx on documents (org_id, entity_type, entity_id);


-- ───────────────────────────────────────────────────────────────────────────
-- 11. ROW LEVEL SECURITY  — matches the existing org_isolation convention
-- ───────────────────────────────────────────────────────────────────────────

do $$
declare t text;
begin
  foreach t in array array[
    'customers','customer_addresses','customer_contacts',
    'vendors','order_vendors','vendor_bills','vendor_payments',
    'bank_accounts','ledger_entries',
    'addons','reviews',
    'wa_contacts','wa_messages',
    'org_subscriptions','platform_invoices','org_usage','billing_events',
    'documents'
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
-- SECTION 12 — CUSTOMER BACK-FILL   ** REVIEW BEFORE RUNNING **
--
-- Creates one customer per distinct (org_id, normalised phone) found in
-- orders and leads, then links both tables to it. Idempotent: re-running
-- will not duplicate, because of customers_org_phone_uniq.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- 12a. Seed customers from orders (most recent name wins)
insert into customers (org_id, name, phone, branch, source, customer_since)
select distinct on (o.org_id, norm_phone(o.phone))
       o.org_id,
       coalesce(nullif(trim(o.customer), ''), 'Unknown'),
       o.phone,
       o.branch,
       o.order_source,
       coalesce(o.created_at::date, current_date)
from orders o
where o.org_id is not null
  and norm_phone(o.phone) is not null
  and o.deleted_at is null
order by o.org_id, norm_phone(o.phone), o.created_at desc
on conflict do nothing;

-- 12b. Seed any remaining customers from leads
insert into customers (org_id, name, phone, email, branch, source, customer_since)
select distinct on (l.org_id, norm_phone(l.phone))
       l.org_id,
       coalesce(nullif(trim(l.customer), ''), 'Unknown'),
       l.phone,
       l.email,
       l.branch,
       l.source,
       coalesce(l.created_at::date, current_date)
from leads l
where l.org_id is not null
  and norm_phone(l.phone) is not null
  and l.deleted_at is null
order by l.org_id, norm_phone(l.phone), l.created_at desc
on conflict do nothing;

-- 12c. Link orders
update orders o
set customer_id = c.id
from customers c
where o.customer_id is null
  and c.org_id = o.org_id
  and c.phone_normalized = norm_phone(o.phone);

-- 12d. Link leads
update leads l
set customer_id = c.id
from customers c
where l.customer_id is null
  and c.org_id = l.org_id
  and c.phone_normalized = norm_phone(l.phone);

-- 12e. Seed a default cash account per org
insert into bank_accounts (org_id, account_type, name, is_default)
select o.id, 'cash', 'Cash in Hand', true
from organizations o
where not exists (
  select 1 from bank_accounts b where b.org_id = o.id
);

commit;


-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION — run after the migration
-- ═══════════════════════════════════════════════════════════════════════════
--
-- select count(*) as customers_created from customers;
-- select count(*) as orders_unlinked from orders
--   where customer_id is null and norm_phone(phone) is not null and deleted_at is null;
-- select count(*) as leads_unlinked from leads
--   where customer_id is null and norm_phone(phone) is not null and deleted_at is null;
-- select tablename, policyname, cmd from pg_policies
--   where schemaname='public' and tablename in ('customers','vendors','org_subscriptions');
