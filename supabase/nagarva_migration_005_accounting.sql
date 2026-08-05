-- ═══════════════════════════════════════════════════════════════════════════
-- NAGARVA MIGRATION 005 — ACCOUNTING CORE
-- Project: hqqcapifefsaqvotqvlt
-- Depends on: 001 (bank_accounts, ledger_entries, vendors, customers)
--
-- Covers: chart of accounts, double-entry journal, bank reconciliation,
--         materials purchase/GRN/consumption, staff advance ledger.
--
-- Fixes the Part 11 §B2 gap: migration 001 delivered party ledgers but not
-- the chart of accounts or journal.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. CHART OF ACCOUNTS
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists account_groups (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid,
  code          text not null,
  name          text not null,
  nature        text not null,        -- asset | liability | income | expense | equity
  parent_id     uuid references account_groups(id) on delete set null,
  is_system     boolean default false,
  sort_order    int default 0,
  created_at    timestamptz default now()
);
create unique index if not exists acct_groups_code_uniq on account_groups (org_id, code);

create table if not exists chart_of_accounts (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  code            text not null,
  name            text not null,
  group_id        uuid references account_groups(id) on delete set null,
  nature          text not null,      -- asset | liability | income | expense | equity
  -- links to the operational tables
  linked_type     text,               -- bank_account | customer | vendor | staff | none
  linked_id       uuid,
  opening_balance numeric default 0,
  opening_dc      text default 'D',   -- D = debit, C = credit
  is_system       boolean default false,
  active          boolean default true,
  created_at      timestamptz default now()
);
create unique index if not exists coa_code_uniq on chart_of_accounts (org_id, code);
create index if not exists coa_group_idx  on chart_of_accounts (org_id, group_id);
create index if not exists coa_linked_idx on chart_of_accounts (linked_type, linked_id);


-- ───────────────────────────────────────────────────────────────────────────
-- 2. JOURNAL — double entry
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists journal_entries (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  voucher_no      text,
  voucher_type    text not null default 'journal',
                  -- journal|sales|purchase|receipt|payment|contra|credit_note|debit_note
  entry_date      date not null default current_date,
  narration       text,
  -- provenance: auto-posted entries carry their source
  source_table    text,
  source_id       text,
  is_auto         boolean default false,
  -- period control
  fy              text,
  is_posted       boolean default true,
  reversed_by     uuid references journal_entries(id) on delete set null,
  reverses        uuid references journal_entries(id) on delete set null,
  total_debit     numeric default 0,
  total_credit    numeric default 0,
  branch          text,
  created_by      text,
  created_at      timestamptz default now(),
  deleted_at      timestamptz
);
create unique index if not exists journal_voucher_uniq
  on journal_entries (org_id, voucher_no) where voucher_no is not null;
create index if not exists journal_date_idx   on journal_entries (org_id, entry_date);
create index if not exists journal_source_idx on journal_entries (source_table, source_id);

create table if not exists journal_lines (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  entry_id        uuid references journal_entries(id) on delete cascade,
  account_id      uuid references chart_of_accounts(id) on delete restrict,
  debit           numeric default 0,
  credit          numeric default 0,
  line_narration  text,
  -- optional analytical dimensions
  party_type      text,
  party_id        uuid,
  order_id        text references orders(id) on delete set null,
  branch          text,
  line_no         int default 1,
  created_at      timestamptz default now()
);
create index if not exists jlines_entry_idx   on journal_lines (entry_id);
create index if not exists jlines_account_idx on journal_lines (org_id, account_id);
create index if not exists jlines_order_idx   on journal_lines (order_id);

-- A journal entry must balance. Enforced at commit, so lines can be
-- inserted one at a time inside a transaction.
create or replace function assert_journal_balanced() returns trigger as $$
declare d numeric; c numeric; eid uuid;
begin
  eid := coalesce(new.entry_id, old.entry_id);
  select coalesce(sum(debit),0), coalesce(sum(credit),0)
    into d, c from journal_lines where entry_id = eid;
  if round(d,2) <> round(c,2) then
    raise exception 'Journal entry % is unbalanced: debit %, credit %', eid, d, c;
  end if;
  update journal_entries set total_debit = d, total_credit = c where id = eid;
  return null;
end;
$$ language plpgsql;

drop trigger if exists journal_lines_balance on journal_lines;
create constraint trigger journal_lines_balance
  after insert or update or delete on journal_lines
  deferrable initially deferred
  for each row execute function assert_journal_balanced();

-- Trial balance
create or replace view trial_balance_view as
select
  jl.org_id,
  coa.code                        as account_code,
  coa.name                        as account_name,
  coa.nature,
  ag.name                         as group_name,
  sum(jl.debit)                   as total_debit,
  sum(jl.credit)                  as total_credit,
  sum(jl.debit) - sum(jl.credit)  as balance,
  case when sum(jl.debit) >= sum(jl.credit) then 'D' else 'C' end as balance_dc
from journal_lines jl
join chart_of_accounts coa on coa.id = jl.account_id
left join account_groups ag on ag.id = coa.group_id
join journal_entries je on je.id = jl.entry_id
where je.deleted_at is null and je.is_posted
group by jl.org_id, coa.code, coa.name, coa.nature, ag.name;


-- ───────────────────────────────────────────────────────────────────────────
-- 3. BANK RECONCILIATION
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists bank_statements (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  account_id      uuid references bank_accounts(id) on delete cascade,
  statement_from  date,
  statement_to    date,
  opening_balance numeric default 0,
  closing_balance numeric default 0,
  imported_at     timestamptz default now(),
  imported_by     text,
  file_name       text,
  line_count      int default 0,
  matched_count   int default 0,
  created_at      timestamptz default now()
);
create index if not exists bank_stmt_acct_idx on bank_statements (account_id, statement_from);

create table if not exists bank_statement_lines (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  statement_id    uuid references bank_statements(id) on delete cascade,
  account_id      uuid references bank_accounts(id) on delete cascade,
  txn_date        date not null,
  value_date      date,
  description     text,
  reference       text,
  debit           numeric default 0,
  credit          numeric default 0,
  running_balance numeric,
  -- matching
  match_status    text default 'unmatched',   -- unmatched | matched | ignored | manual
  matched_type    text,                       -- payment_entry | vendor_payment | journal
  matched_id      uuid,
  matched_at      timestamptz,
  matched_by      text,
  created_at      timestamptz default now()
);
create index if not exists bank_lines_stmt_idx   on bank_statement_lines (statement_id);
create index if not exists bank_lines_status_idx on bank_statement_lines (org_id, account_id, match_status, txn_date);

-- Contra: cash to bank, bank to cash, inter-account transfer
create table if not exists account_transfers (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  from_account_id uuid references bank_accounts(id) on delete restrict,
  to_account_id   uuid references bank_accounts(id) on delete restrict,
  amount          numeric not null default 0,
  transfer_date   date default current_date,
  reference       text,
  note            text,
  journal_entry_id uuid references journal_entries(id) on delete set null,
  created_by      text,
  created_at      timestamptz default now()
);
create index if not exists acct_transfers_idx on account_transfers (org_id, transfer_date);


-- ───────────────────────────────────────────────────────────────────────────
-- 4. MATERIALS — purchase, GRN, consumption
--    materials has name/unit/quantity/min_stock/cost_per_unit only.
--    Stock currently has no movement history at all.
-- ───────────────────────────────────────────────────────────────────────────

alter table materials add column if not exists category text;
alter table materials add column if not exists sku text;
alter table materials add column if not exists branch text;
alter table materials add column if not exists warehouse_id uuid
  references warehouses(id) on delete set null;
alter table materials add column if not exists reorder_qty numeric default 0;
alter table materials add column if not exists is_returnable boolean default false;
alter table materials add column if not exists updated_at timestamptz default now();

drop trigger if exists materials_updated_at on materials;
create trigger materials_updated_at before update on materials
  for each row execute function set_updated_at();

create table if not exists purchase_orders (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  po_no           text,
  vendor_id       uuid references vendors(id) on delete set null,
  po_date         date default current_date,
  expected_date   date,
  branch          text,
  subtotal        numeric default 0,
  gst_amount      numeric default 0,
  total_amount    numeric default 0,
  status          text default 'draft',
                  -- draft | sent | partial | received | cancelled
  notes           text,
  created_by      text,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now(),
  deleted_at      timestamptz
);
create unique index if not exists po_no_uniq on purchase_orders (org_id, po_no) where po_no is not null;
create index if not exists po_vendor_idx on purchase_orders (vendor_id, status);

drop trigger if exists purchase_orders_updated_at on purchase_orders;
create trigger purchase_orders_updated_at before update on purchase_orders
  for each row execute function set_updated_at();

create table if not exists purchase_order_items (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  po_id           uuid references purchase_orders(id) on delete cascade,
  material_id     uuid references materials(id) on delete restrict,
  quantity        numeric not null default 0,
  rate            numeric default 0,
  gst_pct         numeric default 18,
  amount          numeric default 0,
  received_qty    numeric default 0,
  created_at      timestamptz default now()
);
create index if not exists po_items_po_idx on purchase_order_items (po_id);

-- Goods receipt
create table if not exists grn (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  grn_no          text,
  po_id           uuid references purchase_orders(id) on delete set null,
  vendor_id       uuid references vendors(id) on delete set null,
  vendor_bill_id  uuid references vendor_bills(id) on delete set null,
  received_date   date default current_date,
  received_by     text,
  branch          text,
  warehouse_id    uuid references warehouses(id) on delete set null,
  total_amount    numeric default 0,
  status          text default 'received',   -- received | rejected | partial
  notes           text,
  created_at      timestamptz default now()
);
create unique index if not exists grn_no_uniq on grn (org_id, grn_no) where grn_no is not null;
create index if not exists grn_po_idx on grn (po_id);

-- Single source of truth for every stock movement
create table if not exists stock_movements (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  material_id     uuid references materials(id) on delete restrict,
  movement_type   text not null,
                  -- purchase | consumption | return | adjustment
                  -- transfer_in | transfer_out | damage | opening
  quantity        numeric not null,          -- positive in, negative out
  rate            numeric default 0,
  value           numeric default 0,
  -- provenance
  ref_type        text,                      -- grn | order | adjustment | transfer
  ref_id          text,
  order_id        text references orders(id) on delete set null,
  grn_id          uuid references grn(id) on delete set null,
  warehouse_id    uuid references warehouses(id) on delete set null,
  branch          text,
  balance_after   numeric,
  movement_date   date default current_date,
  note            text,
  created_by      text,
  created_at      timestamptz default now()
);
create index if not exists stock_mov_material_idx on stock_movements (material_id, movement_date);
create index if not exists stock_mov_order_idx    on stock_movements (order_id);
create index if not exists stock_mov_type_idx     on stock_movements (org_id, movement_type, movement_date);

-- Keep materials.quantity in step with movements
create or replace function apply_stock_movement() returns trigger as $$
begin
  if tg_op = 'INSERT' then
    update materials set quantity = coalesce(quantity,0) + new.quantity
     where id = new.material_id;
  elsif tg_op = 'DELETE' then
    update materials set quantity = coalesce(quantity,0) - old.quantity
     where id = old.material_id;
  elsif tg_op = 'UPDATE' then
    update materials set quantity = coalesce(quantity,0) - old.quantity + new.quantity
     where id = new.material_id;
  end if;
  return null;
end;
$$ language plpgsql;

drop trigger if exists stock_movements_apply on stock_movements;
create trigger stock_movements_apply
  after insert or update or delete on stock_movements
  for each row execute function apply_stock_movement();

-- Low stock feed
create or replace view low_stock_view as
select m.org_id, m.id as material_id, m.name, m.unit, m.branch,
       m.quantity, m.min_stock, m.reorder_qty, m.cost_per_unit,
       (m.min_stock - m.quantity) as shortfall,
       case when m.quantity <= 0 then 'out_of_stock'
            when m.quantity <= m.min_stock then 'low'
            else 'ok' end as stock_status
from materials m
where m.deleted_at is null
  and m.min_stock > 0
  and m.quantity <= m.min_stock;


-- ───────────────────────────────────────────────────────────────────────────
-- 5. STAFF ADVANCE LEDGER
--    staff_advances holds a balance but no repayment history.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists staff_advance_entries (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  advance_id      uuid references staff_advances(id) on delete cascade,
  staff_id        uuid references staff(id) on delete cascade,
  entry_type      text not null,             -- disbursed | recovered | waived
  amount          numeric not null default 0,
  entry_date      date default current_date,
  payslip_id      uuid references payslips(id) on delete set null,
  account_id      uuid references bank_accounts(id) on delete set null,
  balance_after   numeric,
  note            text,
  created_by      text,
  created_at      timestamptz default now()
);
create index if not exists staff_adv_entries_idx on staff_advance_entries (staff_id, entry_date);
create index if not exists staff_adv_advance_idx on staff_advance_entries (advance_id);

alter table staff_advances add column if not exists recovery_per_month numeric default 0;
alter table staff_advances add column if not exists recovered_amount numeric default 0;
alter table staff_advances add column if not exists closed_at timestamptz;


-- ───────────────────────────────────────────────────────────────────────────
-- 6. AUDIT LOG — value capture
--    audit_log records entity/action/actor but not what changed.
-- ───────────────────────────────────────────────────────────────────────────

alter table audit_log add column if not exists old_value jsonb;
alter table audit_log add column if not exists new_value jsonb;
alter table audit_log add column if not exists changed_fields text[];
alter table audit_log add column if not exists ip_address text;
alter table audit_log add column if not exists user_agent text;
alter table audit_log add column if not exists actor_role text;

create index if not exists audit_log_entity_idx on audit_log (org_id, entity_type, entity_id, created_at desc);
create index if not exists audit_log_actor_idx  on audit_log (org_id, actor, created_at desc);


-- ───────────────────────────────────────────────────────────────────────────
-- 7. ROW LEVEL SECURITY
-- ───────────────────────────────────────────────────────────────────────────

do $$
declare t text;
begin
  foreach t in array array[
    'account_groups','chart_of_accounts','journal_entries','journal_lines',
    'bank_statements','bank_statement_lines','account_transfers',
    'purchase_orders','purchase_order_items','grn','stock_movements',
    'staff_advance_entries'
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
-- SEED — standard chart of accounts per org
-- ═══════════════════════════════════════════════════════════════════════════

begin;

insert into account_groups (org_id, code, name, nature, is_system, sort_order)
select o.id, g.code, g.name, g.nature, true, g.sort_order
from organizations o
cross join (values
  ('CA',  'Current Assets',        'asset',     1),
  ('FA',  'Fixed Assets',          'asset',     2),
  ('CL',  'Current Liabilities',   'liability', 3),
  ('LT',  'Long Term Liabilities', 'liability', 4),
  ('CAP', 'Capital',               'equity',    5),
  ('DI',  'Direct Income',         'income',    6),
  ('II',  'Indirect Income',       'income',    7),
  ('DE',  'Direct Expenses',       'expense',   8),
  ('IE',  'Indirect Expenses',     'expense',   9)
) as g(code, name, nature, sort_order)
on conflict (org_id, code) do nothing;

insert into chart_of_accounts (org_id, code, name, group_id, nature, is_system)
select o.id, a.code, a.name, ag.id, a.nature, true
from organizations o
cross join (values
  -- assets
  ('1000','Cash in Hand',            'CA','asset'),
  ('1010','Bank Accounts',           'CA','asset'),
  ('1100','Accounts Receivable',     'CA','asset'),
  ('1200','Materials Stock',         'CA','asset'),
  ('1300','Staff Advances',          'CA','asset'),
  ('1400','Input GST',               'CA','asset'),
  ('1500','Vehicles',                'FA','asset'),
  -- liabilities
  ('2000','Accounts Payable',        'CL','liability'),
  ('2100','Output GST',              'CL','liability'),
  ('2200','TDS Payable',             'CL','liability'),
  ('2300','Salary Payable',          'CL','liability'),
  ('2400','PF Payable',              'CL','liability'),
  ('2500','ESI Payable',             'CL','liability'),
  ('2600','Customer Advances',       'CL','liability'),
  -- equity
  ('3000','Owner Capital',           'CAP','equity'),
  ('3100','Retained Earnings',       'CAP','equity'),
  -- income
  ('4000','Shifting Revenue',        'DI','income'),
  ('4100','Storage Revenue',         'DI','income'),
  ('4200','Insurance Commission',    'II','income'),
  ('4300','Other Income',            'II','income'),
  -- direct expenses
  ('5000','Labour Wages',            'DE','expense'),
  ('5100','Vehicle Hire',            'DE','expense'),
  ('5200','Fuel & Diesel',           'DE','expense'),
  ('5300','Toll & Parking',          'DE','expense'),
  ('5400','Packing Materials',       'DE','expense'),
  ('5500','Subcontractor Charges',   'DE','expense'),
  ('5600','Insurance Premium',       'DE','expense'),
  ('5700','Claim Settlements',       'DE','expense'),
  -- indirect expenses
  ('6000','Staff Salary',            'IE','expense'),
  ('6100','Office Rent',             'IE','expense'),
  ('6200','Marketing & Advertising', 'IE','expense'),
  ('6300','Vehicle Maintenance',     'IE','expense'),
  ('6400','Telephone & Internet',    'IE','expense'),
  ('6500','Professional Fees',       'IE','expense'),
  ('6600','Bank Charges',            'IE','expense'),
  ('6700','Miscellaneous',           'IE','expense')
) as a(code, name, group_code, nature)
join account_groups ag on ag.org_id = o.id and ag.code = a.group_code
on conflict (org_id, code) do nothing;

-- Link existing bank/cash accounts to COA 1000/1010
update chart_of_accounts coa
set linked_type = 'bank_account', linked_id = ba.id
from bank_accounts ba
where ba.org_id = coa.org_id
  and coa.linked_id is null
  and ((ba.account_type = 'cash' and coa.code = '1000')
    or (ba.account_type <> 'cash' and coa.code = '1010'));

-- Opening stock movements for materials that already carry a quantity
insert into stock_movements (org_id, material_id, movement_type, quantity,
                             rate, value, ref_type, note, balance_after)
select m.org_id, m.id, 'opening', m.quantity,
       coalesce(m.cost_per_unit,0), m.quantity * coalesce(m.cost_per_unit,0),
       'adjustment', 'Opening stock (backfilled)', m.quantity
from materials m
where coalesce(m.quantity,0) <> 0
  and m.deleted_at is null
  and not exists (
    select 1 from stock_movements s
    where s.material_id = m.id and s.movement_type = 'opening'
  );

commit;

-- The opening back-fill fires apply_stock_movement and would double the
-- quantity. Correct it in a separate statement.
begin;
update materials m
set quantity = m.quantity - s.qty
from (
  select material_id, sum(quantity) as qty
  from stock_movements
  where movement_type = 'opening' and note = 'Opening stock (backfilled)'
  group by material_id
) s
where m.id = s.material_id;
commit;


-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════
--
-- select
--   (select count(*) from information_schema.tables where table_schema='public'
--      and table_name in ('account_groups','chart_of_accounts','journal_entries',
--        'journal_lines','bank_statements','bank_statement_lines',
--        'account_transfers','purchase_orders','purchase_order_items','grn',
--        'stock_movements','staff_advance_entries')) as tables_expect_12,
--   (select count(*) from account_groups)    as groups_expect_orgs_x_9,
--   (select count(*) from chart_of_accounts) as accounts_expect_orgs_x_36,
--   (select count(*) from chart_of_accounts where linked_id is not null) as linked_accts,
--   (select count(*) from stock_movements where movement_type='opening') as opening_stock;
--
-- -- materials.quantity must be unchanged from before this migration:
-- select id, name, quantity from materials order by name;
