-- ═══════════════════════════════════════════════════════════════════════════
-- NAGARVA MIGRATION 009 — DOCUMENT FIELDS
-- Project: hqqcapifefsaqvotqvlt
-- Depends on: 001-008
--
-- Closes the schema gaps found by comparing Nagarva's document output against
-- four live APC documents (LR/Consignment Note, Quotation, Tax Invoice,
-- Money Receipt).
--
-- Three of these are GST requirements, not cosmetics:
--   * HSN/SAC on the invoice
--   * Reverse-charge declaration
--   * Amount in words (Indian numbering)
--
-- Verified against schema_snapshot_2026-08-01.csv before writing — columns
-- that already exist are NOT re-added. Notably already present and usable:
--   orders.from_floor / to_floor / declared_value / distance_km / move_date
--   lr_register.freight_mode / gst_payable_by / actual_weight_kg /
--     charged_weight_kg / declared_value / other_charges
--   payment_entries.reference
--   organizations.state_code / pan / website / tagline / upi_id
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. ORGANIZATIONS — document header block
--    Every document prints these. APC's header carries four phone numbers,
--    a landline, a UDYAM number and a government affiliation line.
-- ───────────────────────────────────────────────────────────────────────────

alter table organizations add column if not exists phone_secondary text;
alter table organizations add column if not exists phone_tertiary text;
alter table organizations add column if not exists phone_quaternary text;
alter table organizations add column if not exists landline text;
alter table organizations add column if not exists udyam_no text;
alter table organizations add column if not exists affiliation_text text;
alter table organizations add column if not exists branch_list_text text;
alter table organizations add column if not exists signatory_image_url text;
alter table organizations add column if not exists signatory_name text;

-- Bank block — printed on quotation and invoice
alter table organizations add column if not exists beneficiary_name text;
alter table organizations add column if not exists bank_name text;
alter table organizations add column if not exists bank_account_no text;
alter table organizations add column if not exists bank_ifsc text;
alter table organizations add column if not exists upi_display_number text;

comment on column organizations.affiliation_text is
  'e.g. "Affiliated By: Govt Of Karnataka" — printed top-left on documents';
comment on column organizations.branch_list_text is
  'e.g. "Branch: Chennai, Bengaluru, Coimbatore & Hyderabad"';


-- ───────────────────────────────────────────────────────────────────────────
-- 2. ORDERS — quotation and invoice fields
-- ───────────────────────────────────────────────────────────────────────────

-- Three operationally distinct dates. On an outstation move, packing,
-- moving and delivery are different days. move_date already exists.
alter table orders add column if not exists packing_date date;
alter table orders add column if not exists delivery_date date;

-- Consignment characteristics, printed on the quotation header
alter table orders add column if not exists load_type text;        -- full_load | part_load
alter table orders add column if not exists vehicle_type text;     -- dedicated | shared
alter table orders add column if not exists transport_mode text default 'road';
                                                                   -- road | rail | air | ship

-- Lift availability. Floors already exist; lift drives the floor charge and
-- prints on the quotation as "Is Lift Available: Yes/No".
alter table orders add column if not exists from_has_lift boolean;
alter table orders add column if not exists to_has_lift boolean;

-- Billing party can differ from the consignor (corporate relocation billed
-- to the employer, not the employee).
alter table orders add column if not exists billing_party_name text;
alter table orders add column if not exists billing_party_gstin text;
alter table orders add column if not exists billing_party_address text;
alter table orders add column if not exists billing_party_phone text;

-- GST fields — statutory
alter table orders add column if not exists hsn_sac_code text default '996719';
alter table orders add column if not exists reverse_charge boolean default false;
alter table orders add column if not exists payment_remark text;

comment on column orders.hsn_sac_code is
  'SAC 996719 = goods transport / packers and movers. Tenant-overridable.';
comment on column orders.reverse_charge is
  'GST reverse charge applicability — prints "Reverse Charge: YES/NO" on the invoice';


-- ───────────────────────────────────────────────────────────────────────────
-- 3. LR REGISTER — consignment note fields
-- ───────────────────────────────────────────────────────────────────────────

-- Risk declaration. Determines the panel title on the LR and who bears loss.
alter table lr_register add column if not exists risk_type text default 'owner';
                                                  -- owner | carrier

-- State codes print in brackets after the state name: "Tamil Nadu (33)"
alter table lr_register add column if not exists consignor_state text;
alter table lr_register add column if not exists consignor_state_code int;
alter table lr_register add column if not exists consignor_pincode text;
alter table lr_register add column if not exists consignee_state text;
alter table lr_register add column if not exists consignee_state_code int;
alter table lr_register add column if not exists consignee_pincode text;

-- Freight breakdown lines on the LR
alter table lr_register add column if not exists basic_freight numeric default 0;
alter table lr_register add column if not exists loading_charge numeric default 0;
alter table lr_register add column if not exists unloading_charge numeric default 0;
alter table lr_register add column if not exists st_charge numeric default 0;
alter table lr_register add column if not exists lr_cn_charge numeric default 0;
alter table lr_register add column if not exists gst_pct numeric default 18;
alter table lr_register add column if not exists gst_amount numeric default 0;

-- Invoice cross-reference printed on the LR
alter table lr_register add column if not exists goods_value numeric default 0;
alter table lr_register add column if not exists invoice_no text;
alter table lr_register add column if not exists invoice_date date;

-- Insurance snapshot at LR issue time
alter table lr_register add column if not exists material_insured boolean default false;
alter table lr_register add column if not exists insurer_name text;
alter table lr_register add column if not exists policy_no text;
alter table lr_register add column if not exists insurance_date date;
alter table lr_register add column if not exists insured_amount numeric default 0;
alter table lr_register add column if not exists distance_km int;

comment on column lr_register.risk_type is
  'owner = AT OWNER''S RISK, carrier = AT CARRIER''S RISK. Sets the LR panel heading.';

-- Which copies have been generated. The LR is issued in four versions.
create table if not exists lr_copies (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid,
  lr_id         uuid references lr_register(id) on delete cascade,
  copy_type     text not null,     -- driver | consignor | consignee | transporter
  generated_at  timestamptz default now(),
  generated_by  text,
  pdf_url       text,
  created_at    timestamptz default now()
);
create unique index if not exists lr_copies_uniq on lr_copies (lr_id, copy_type);
create index if not exists lr_copies_lr_idx on lr_copies (org_id, lr_id);


-- ───────────────────────────────────────────────────────────────────────────
-- 4. QUOTATION — survey answers and consignment characteristics
-- ───────────────────────────────────────────────────────────────────────────

alter table quotations add column if not exists packing_date date;
alter table quotations add column if not exists delivery_date date;
alter table quotations add column if not exists moving_date date;
alter table quotations add column if not exists load_type text;
alter table quotations add column if not exists vehicle_type text;
alter table quotations add column if not exists transport_mode text default 'road';
alter table quotations add column if not exists from_has_lift boolean;
alter table quotations add column if not exists to_has_lift boolean;
alter table quotations add column if not exists from_floor int;
alter table quotations add column if not exists to_floor int;

-- FOV / insurance line: "@3% On Declaration Value Of Goods (150000/-)"
alter table quotations add column if not exists declared_value numeric default 0;
alter table quotations add column if not exists fov_pct numeric default 0;
alter table quotations add column if not exists fov_amount numeric default 0;

-- Site-access answers captured at survey, printed on the quote
alter table quotations add column if not exists easy_access boolean;
alter table quotations add column if not exists access_restrictions boolean;
alter table quotations add column if not exists access_notes text;

-- Same three on the survey, since that is where they are collected
alter table surveys add column if not exists easy_access boolean;
alter table surveys add column if not exists access_restrictions boolean;
alter table surveys add column if not exists from_floor int;
alter table surveys add column if not exists to_floor int;
alter table surveys add column if not exists from_has_lift boolean;
alter table surveys add column if not exists to_has_lift boolean;
alter table surveys add column if not exists declared_value numeric default 0;


-- ───────────────────────────────────────────────────────────────────────────
-- 5. MONEY RECEIPT — invoice linkage and consolidated payments
-- ───────────────────────────────────────────────────────────────────────────

-- "Towards Final Payment of Bill No. 2026/0027 Dated 18-07-2026"
alter table payment_entries add column if not exists invoice_no text;
alter table payment_entries add column if not exists invoice_date date;
alter table payment_entries add column if not exists receipt_no text;
alter table payment_entries add column if not exists is_final_payment boolean default false;

create unique index if not exists payment_receipt_no_uniq
  on payment_entries (org_id, receipt_no) where receipt_no is not null;

-- APC's receipt shows three UPI transaction ids on one document — a receipt
-- can cover several payment entries. This groups them.
create table if not exists receipts (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  receipt_no      text not null,
  receipt_date    date default current_date,
  order_id        text references orders(id) on delete set null,
  customer_id     uuid references customers(id) on delete set null,
  invoice_no      text,
  invoice_date    date,
  total_amount    numeric default 0,
  amount_in_words text,
  payment_mode    text,
  reference_nos   text,            -- comma-separated txn ids
  is_final        boolean default false,
  pdf_url         text,
  created_by      text,
  created_at      timestamptz default now()
);
create unique index if not exists receipts_no_uniq on receipts (org_id, receipt_no);
create index if not exists receipts_order_idx on receipts (org_id, order_id);

alter table payment_entries add column if not exists receipt_id uuid
  references receipts(id) on delete set null;


-- ───────────────────────────────────────────────────────────────────────────
-- 6. LR/CN CHARGE — 16th charge head
-- ───────────────────────────────────────────────────────────────────────────

insert into rate_card_charges (org_id, card_id, charge_key, label, unit, sort_order)
select rc.org_id, rc.id, 'lrCnCharge', 'LR / CN Charge', 'flat', 16
from rate_cards rc
where rc.is_default = true
on conflict (card_id, charge_key) do nothing;


-- ───────────────────────────────────────────────────────────────────────────
-- 7. AMOUNT IN WORDS — Indian numbering
--    Required on quotation, invoice and receipt. Lakh/crore, not million.
-- ───────────────────────────────────────────────────────────────────────────

-- Postgres plpgsql has no nested function declarations, so the two helpers
-- are separate functions. They are prefixed _ to mark them internal.

create or replace function _words_two(v int) returns text as $$
declare
  ones text[] := array['','One','Two','Three','Four','Five','Six','Seven','Eight','Nine',
    'Ten','Eleven','Twelve','Thirteen','Fourteen','Fifteen','Sixteen','Seventeen',
    'Eighteen','Nineteen'];
  tens text[] := array['','','Twenty','Thirty','Forty','Fifty','Sixty','Seventy','Eighty','Ninety'];
begin
  if v is null or v = 0 then return ''; end if;
  if v < 20 then return ones[v + 1]; end if;
  return trim(tens[(v / 10) + 1] || ' ' || ones[(v % 10) + 1]);
end;
$$ language plpgsql immutable;

create or replace function _words_three(v int) returns text as $$
declare
  ones text[] := array['','One','Two','Three','Four','Five','Six','Seven','Eight','Nine'];
begin
  if v is null or v = 0 then return ''; end if;
  if v < 100 then return _words_two(v); end if;
  return trim(ones[(v / 100) + 1] || ' Hundred' ||
    case when v % 100 > 0 then ' and ' || _words_two(v % 100) else '' end);
end;
$$ language plpgsql immutable;

create or replace function amount_in_words(amt numeric)
returns text as $$
declare
  n bigint;
  paise int;
  res text := '';
begin
  if amt is null then return ''; end if;
  n := floor(abs(amt))::bigint;
  paise := round((abs(amt) - floor(abs(amt))) * 100)::int;

  if n = 0 then
    res := 'Zero';
  else
    if n >= 10000000 then
      res := res || _words_three((n / 10000000)::int) || ' Crore ';
      n := n % 10000000;
    end if;
    if n >= 100000 then
      res := res || _words_two((n / 100000)::int) || ' Lakh ';
      n := n % 100000;
    end if;
    if n >= 1000 then
      res := res || _words_two((n / 1000)::int) || ' Thousand ';
      n := n % 1000;
    end if;
    if n > 0 then
      res := res || _words_three(n::int);
    end if;
  end if;

  res := trim(regexp_replace(res, '\s+', ' ', 'g'));

  if paise > 0 then
    res := res || ' Rupees and ' || _words_two(paise) || ' Paise Only';
  else
    res := res || ' Rupees Only';
  end if;

  return res;
end;
$$ language plpgsql immutable;


-- ───────────────────────────────────────────────────────────────────────────
-- 8. ROW LEVEL SECURITY — new tables only
-- ───────────────────────────────────────────────────────────────────────────

do $$
declare t text;
begin
  foreach t in array array['lr_copies','receipts']
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
-- SEED — tenant-editable document boilerplate
-- ═══════════════════════════════════════════════════════════════════════════

begin;

insert into app_settings (org_id, category, key, value)
select o.id, 'documents', s.key, s.val::jsonb
from organizations o
cross join (values
  ('lr_notice_text', to_jsonb(
    'The consignment by the lorry receipt shall be stored at the destination under the control of the transport operator and shall be delivered to the order of the consignee whose name is mentioned in the lorry receipt. It will under no circumstances be delivered to anyone without written authorization from the consignee on its order.'::text)::text),
  ('demurrage_free_days', '5'),
  ('demurrage_rate_per_day', '500'),
  ('demurrage_text', to_jsonb(
    'Demurrage charge after more than {days} day(s) @ Rs.{rate} per day + handling & local transportation charges.'::text)::text),
  ('goods_description_default', to_jsonb(
    'Old and Used Household Goods For Personal Usage Only, Not For Sale'::text)::text),
  ('invoice_note', to_jsonb(
    'Please keep your Cash/Jewellery and all important documents in your Custody/Lock. Carrying Liquor, Gas Cylinder, Acid of any type of Liquids (like Ghee Tin, Oil etc.) is totally prohibited.'::text)::text),
  ('doc_footer_text', to_jsonb(
    'This is a computer-generated document. SAVE PAPER - SAVE TREES | BE DIGITAL - GO GREEN'::text)::text),
  ('quotation_terms', to_jsonb(
    'We do not undertake Electrical, Carpentry & Plumber Job.
Vehicle transportation charges are based on the present prevailing market rate.
We or our agent shall be exempted from any kind of loss or damage due to accident, pilferage, fire, rain, collision or any other road hazard or natural calamity. To avoid loss or damage we advise you to insure your consignment covering all risk.
We request 80% advance on total amount along with your purchase order, balance on completion at loading point. Insurance premium to be paid at loading point before departure.
If required we also provide storage facility at nominal charge.
Kindly give prior intimation of 4-5 days in advance to start packing.
Extra payment will be charged for wooden packing on moving date.
We are not responsible for Gold & Cash. Please keep in your custody lock.
Interest will be charged @24% per annum if payment is not made within 15 days.
Payment to be made in favour of the company by Cash/Cheque.'::text)::text)
) as s(key, val)
on conflict (org_id, category, key) do nothing;

-- Document numbering: APC uses FY/serial (2026/0013), not INV-0001.
-- number_series already supports this via prefix + padding.
update number_series
set prefix = case when extract(month from current_date) >= 4
                  then extract(year from current_date)::text || '/'
                  else (extract(year from current_date))::text || '/'
             end,
    padding = 4
where doc_type in ('invoice','proforma','receipt','quotation','credit_note',
                   'debit_note','voucher')
  and coalesce(prefix,'') like '%-';

update lr_series set prefix =
  case when extract(month from current_date) >= 4
       then extract(year from current_date)::text || '/'
       else extract(year from current_date)::text || '/'
  end
where coalesce(prefix,'LR') = 'LR';

commit;


-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════
--
-- select amount_in_words(44620);
--   -- expect: Forty Four Thousand Six Hundred and Twenty Rupees Only
-- select amount_in_words(150000);      -- One Lakh Fifty Thousand Rupees Only
-- select amount_in_words(12500000);    -- One Crore Twenty Five Lakh Rupees Only
-- select amount_in_words(0);           -- Zero Rupees Only
--
-- select count(*) as new_tables from information_schema.tables
--  where table_schema='public' and table_name in ('lr_copies','receipts');
--   -- expect 2
--
-- select key from app_settings where category='documents' order by key;
--   -- expect 8 per org
--
-- select doc_type, prefix, padding from number_series order by doc_type;
--   -- prefixes should read '2026/'
--
-- select count(*) from rate_card_charges where charge_key='lrCnCharge';
