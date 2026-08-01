-- ═══════════════════════════════════════════════════════════════════════════
-- NAGARVA MIGRATION 004 — CRM DEPTH
-- Project: hqqcapifefsaqvotqvlt
-- Depends on: 001 (customers, vendors) · 003 (rate_cards)
--
-- Covers: quotation versioning & discount approval, tasks/activities/call logs,
--         corporate contracts & SLAs, lead source attribution & marketing ROI.
--
-- Conventions: org_id uuid | orders.id TEXT | quotations.id TEXT
--              soft delete triplet | RLS org_isolation
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. QUOTATION VERSIONING & APPROVAL
--    quotations exists but holds only the current state. No revision history,
--    no discount control, no won/lost reason.
-- ───────────────────────────────────────────────────────────────────────────

alter table quotations add column if not exists version int default 1;
alter table quotations add column if not exists parent_quote_id text
  references quotations(id) on delete set null;
alter table quotations add column if not exists is_current boolean default true;
alter table quotations add column if not exists valid_until date;
alter table quotations add column if not exists sent_at timestamptz;
alter table quotations add column if not exists viewed_at timestamptz;
alter table quotations add column if not exists accepted_at timestamptz;
alter table quotations add column if not exists rejected_at timestamptz;
alter table quotations add column if not exists customer_id uuid
  references customers(id) on delete set null;
-- discount control
alter table quotations add column if not exists list_amount numeric default 0;
alter table quotations add column if not exists discount_amount numeric default 0;
alter table quotations add column if not exists discount_pct numeric default 0;
alter table quotations add column if not exists margin_pct numeric;
alter table quotations add column if not exists approval_status text default 'not_required';
                       -- not_required | pending | approved | rejected
alter table quotations add column if not exists approved_by text;
alter table quotations add column if not exists approved_at timestamptz;

create index if not exists quotations_customer_idx on quotations (customer_id);
create index if not exists quotations_current_idx  on quotations (org_id, is_current);

-- Immutable snapshot of each revision
create table if not exists quote_versions (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  quote_id        text references quotations(id) on delete cascade,
  version         int not null,
  snapshot        jsonb not null,          -- full quote state at this revision
  change_summary  text,
  changed_fields  text[] default '{}',
  total_amount    numeric default 0,
  created_by      text,
  created_at      timestamptz default now()
);
create unique index if not exists quote_versions_uniq on quote_versions (quote_id, version);
create index if not exists quote_versions_quote_idx on quote_versions (quote_id, version desc);

-- Discount approval requests
create table if not exists quote_approvals (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  quote_id        text references quotations(id) on delete cascade,
  version         int,
  requested_by    text,
  requested_at    timestamptz default now(),
  reason          text,
  list_amount     numeric default 0,
  proposed_amount numeric default 0,
  discount_pct    numeric default 0,
  margin_pct      numeric,
  floor_margin_pct numeric,               -- threshold that triggered this
  status          text default 'pending',  -- pending | approved | rejected | withdrawn
  decided_by      text,
  decided_at      timestamptz,
  decision_note   text,
  created_at      timestamptz default now()
);
create index if not exists quote_approvals_status_idx on quote_approvals (org_id, status);
create index if not exists quote_approvals_quote_idx  on quote_approvals (quote_id);

-- Won/lost outcome with competitor intelligence
create table if not exists quote_outcomes (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid,
  quote_id          text references quotations(id) on delete cascade,
  lead_id           uuid references leads(id) on delete set null,
  outcome           text not null,         -- won | lost | no_response | withdrawn
  reason_code       text,
                    -- price | timing | trust | service_scope | competitor
                    -- customer_cancelled | unreachable | other
  reason_note       text,
  competitor_name   text,
  competitor_price  numeric,
  our_price         numeric,
  price_gap_pct     numeric,
  recorded_by       text,
  recorded_at       timestamptz default now()
);
create index if not exists quote_outcomes_quote_idx  on quote_outcomes (quote_id);
create index if not exists quote_outcomes_reason_idx on quote_outcomes (org_id, outcome, reason_code);

-- Discount policy per org
create table if not exists discount_policies (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid,
  name              text default 'Default',
  role              text,                  -- null = applies to all
  max_discount_pct  numeric default 0,     -- above this, approval required
  floor_margin_pct  numeric default 15,    -- below this, approval required
  approver_role     text default 'owner',
  active            boolean default true,
  created_at        timestamptz default now()
);
create index if not exists discount_policies_org_idx on discount_policies (org_id, active);


-- ───────────────────────────────────────────────────────────────────────────
-- 2. TASKS, ACTIVITIES & CALL LOGS
--    reminders exist on leads only. This is polymorphic across any entity.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists tasks (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  title           text not null,
  description     text,
  task_type       text default 'todo',
                  -- todo | call | followup | site_visit | payment_chase
                  -- document | delivery_check
  -- polymorphic link
  entity_type     text,                    -- lead|order|customer|vendor|quote|claim
  entity_id       text,
  -- assignment
  assigned_to     uuid references staff(id) on delete set null,
  assigned_by     text,
  branch          text,
  -- scheduling
  due_at          timestamptz,
  reminder_at     timestamptz,
  priority        text default 'normal',   -- low | normal | high | urgent
  -- state
  status          text default 'open',     -- open | in_progress | done | cancelled
  completed_at    timestamptz,
  completed_by    text,
  completion_note text,
  -- recurrence
  recurrence      text,                    -- null | daily | weekly | monthly
  recurrence_until date,
  parent_task_id  uuid references tasks(id) on delete set null,
  -- escalation
  escalated       boolean default false,
  escalated_at    timestamptz,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now(),
  deleted_at      timestamptz
);
create index if not exists tasks_assignee_idx on tasks (org_id, assigned_to, status, due_at);
create index if not exists tasks_entity_idx   on tasks (entity_type, entity_id);
create index if not exists tasks_due_idx      on tasks (org_id, status, due_at);

drop trigger if exists tasks_updated_at on tasks;
create trigger tasks_updated_at before update on tasks
  for each row execute function set_updated_at();

-- Activity timeline: what actually happened, as opposed to what was planned
create table if not exists activities (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  activity_type   text not null,
                  -- call | whatsapp | email | meeting | site_visit
                  -- note | status_change | document_sent
  entity_type     text,
  entity_id       text,
  customer_id     uuid references customers(id) on delete set null,
  lead_id         uuid references leads(id) on delete set null,
  subject         text,
  body            text,
  direction       text,                    -- inbound | outbound
  -- call specifics
  call_outcome    text,                    -- connected|no_answer|busy|wrong_number|callback
  duration_sec    int,
  -- meeting/visit specifics
  location        text,
  latitude        numeric,
  longitude       numeric,
  occurred_at     timestamptz default now(),
  performed_by    uuid references staff(id) on delete set null,
  task_id         uuid references tasks(id) on delete set null,
  attachments     text[] default '{}',
  created_at      timestamptz default now()
);
create index if not exists activities_entity_idx on activities (entity_type, entity_id, occurred_at desc);
create index if not exists activities_cust_idx   on activities (customer_id, occurred_at desc);
create index if not exists activities_lead_idx   on activities (lead_id, occurred_at desc);
create index if not exists activities_user_idx   on activities (org_id, performed_by, occurred_at desc);


-- ───────────────────────────────────────────────────────────────────────────
-- 3. CONTRACTS & SLA
--    Corporate accounts with agreed rates and service commitments.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists contracts (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid,
  contract_no       text,
  customer_id       uuid references customers(id) on delete cascade,
  title             text,
  contract_type     text default 'annual',  -- annual | project | retainer | rate_agreement
  rate_card_id      uuid references rate_cards(id) on delete set null,
  start_date        date,
  end_date          date,
  auto_renew        boolean default false,
  renewal_notice_days int default 30,
  -- commercials
  contract_value    numeric default 0,
  billing_cycle     text default 'per_order',  -- per_order | monthly | quarterly
  credit_days       int default 0,
  -- SLA
  response_time_hrs int,
  transit_time_days int,
  damage_liability_cap numeric,
  penalty_clause    text,
  -- lifecycle
  status            text default 'draft',
                    -- draft | active | expired | terminated | renewed
  signed_at         date,
  signed_by         text,
  document_url      text,
  terminated_at     date,
  termination_reason text,
  notes             text,
  created_at        timestamptz default now(),
  updated_at        timestamptz default now(),
  deleted_at        timestamptz
);
create unique index if not exists contracts_no_uniq
  on contracts (org_id, contract_no) where contract_no is not null;
create index if not exists contracts_cust_idx   on contracts (customer_id);
create index if not exists contracts_expiry_idx on contracts (org_id, status, end_date);

drop trigger if exists contracts_updated_at on contracts;
create trigger contracts_updated_at before update on contracts
  for each row execute function set_updated_at();

alter table orders add column if not exists contract_id uuid
  references contracts(id) on delete set null;

-- SLA breach tracking against actual orders
create table if not exists sla_events (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  contract_id     uuid references contracts(id) on delete cascade,
  order_id        text references orders(id) on delete set null,
  metric          text not null,           -- response_time | transit_time | damage
  target_value    numeric,
  actual_value    numeric,
  breached        boolean default false,
  breach_severity text,                    -- minor | major | critical
  penalty_amount  numeric default 0,
  waived          boolean default false,
  note            text,
  recorded_at     timestamptz default now()
);
create index if not exists sla_events_contract_idx on sla_events (contract_id, breached);
create index if not exists sla_events_order_idx    on sla_events (order_id);


-- ───────────────────────────────────────────────────────────────────────────
-- 4. LEAD SOURCE ATTRIBUTION & MARKETING ROI
--    leads.source is free text. This makes it a managed dimension with cost.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists lead_sources (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  code            text not null,           -- justdial | google_ads | whatsapp | referral
  name            text not null,
  channel         text,                    -- directory | paid_ads | organic | referral
                                           -- walk_in | repeat | partner
  is_paid         boolean default false,
  api_enabled     boolean default false,
  active          boolean default true,
  sort_order      int default 0,
  created_at      timestamptz default now()
);
create unique index if not exists lead_sources_code_uniq on lead_sources (org_id, code);

alter table leads add column if not exists source_id uuid
  references lead_sources(id) on delete set null;
alter table leads add column if not exists campaign_id uuid;
alter table leads add column if not exists referrer_customer_id uuid
  references customers(id) on delete set null;
alter table leads add column if not exists utm_source text;
alter table leads add column if not exists utm_medium text;
alter table leads add column if not exists utm_campaign text;
alter table leads add column if not exists first_response_at timestamptz;

-- Marketing spend per source per period
create table if not exists marketing_spend (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  source_id       uuid references lead_sources(id) on delete cascade,
  campaign_name   text,
  period_start    date not null,
  period_end      date not null,
  amount          numeric default 0,
  branch          text,
  note            text,
  created_at      timestamptz default now()
);
create index if not exists marketing_spend_idx on marketing_spend (org_id, source_id, period_start);

alter table marketing_spend
  drop constraint if exists marketing_spend_campaign_fk;

-- Referral payouts
create table if not exists referrals (
  id                  uuid primary key default gen_random_uuid(),
  org_id              uuid,
  referrer_customer_id uuid references customers(id) on delete set null,
  referrer_staff_id   uuid references staff(id) on delete set null,
  referrer_name       text,
  referrer_phone      text,
  lead_id             uuid references leads(id) on delete set null,
  order_id            text references orders(id) on delete set null,
  reward_type         text default 'cash',  -- cash | discount | credit
  reward_amount       numeric default 0,
  status              text default 'pending',  -- pending | approved | paid | rejected
  paid_at             timestamptz,
  payment_ref         text,
  note                text,
  created_at          timestamptz default now()
);
create index if not exists referrals_referrer_idx on referrals (org_id, referrer_customer_id);
create index if not exists referrals_status_idx   on referrals (org_id, status);

-- Source performance: leads, conversion, spend, CPL, CAC
create or replace view lead_source_performance_view as
select
  l.org_id,
  coalesce(ls.name, l.source, 'Unknown')          as source_name,
  ls.id                                           as source_id,
  ls.channel,
  date_trunc('month', l.created_at)::date         as period,
  count(*)                                        as total_leads,
  count(*) filter (where l.status = 'confirmed')  as converted_leads,
  count(*) filter (where l.status = 'lost')       as lost_leads,
  round(
    100.0 * count(*) filter (where l.status = 'confirmed')
    / nullif(count(*), 0), 2)                     as conversion_pct,
  coalesce(sum(o.amount), 0)                      as revenue,
  coalesce(ms.spend, 0)                           as marketing_spend,
  round(coalesce(ms.spend, 0) / nullif(count(*), 0), 2) as cost_per_lead,
  round(
    coalesce(ms.spend, 0)
    / nullif(count(*) filter (where l.status = 'confirmed'), 0), 2) as cost_per_acquisition
from leads l
left join lead_sources ls on ls.id = l.source_id
left join orders o        on o.lead_id = l.id and o.deleted_at is null
left join lateral (
  select sum(m.amount) as spend
  from marketing_spend m
  where m.source_id = ls.id
    and date_trunc('month', m.period_start) = date_trunc('month', l.created_at)
) ms on true
where l.deleted_at is null
group by l.org_id, ls.id, ls.name, l.source, ls.channel,
         date_trunc('month', l.created_at), ms.spend;

-- Customer 360 rollup
create or replace view customer_360_view as
select
  c.id                                as customer_id,
  c.org_id,
  c.name,
  c.phone,
  c.customer_type,
  c.company_name,
  c.customer_since,
  count(distinct o.id)                as total_orders,
  coalesce(sum(o.amount), 0)          as lifetime_value,
  coalesce(avg(o.amount), 0)          as avg_order_value,
  max(o.created_at)                   as last_order_at,
  count(distinct l.id)                as total_leads,
  count(distinct q.id)                as total_quotes,
  coalesce(sum(o.amount), 0)
    - coalesce(sum(o.paid_total), 0)  as outstanding_estimate,
  coalesce(sum(o.paid_total), 0)      as total_collected,
  coalesce(sum(o.advance_paid), 0)    as total_advance,
  count(distinct ct.id) filter (where ct.status = 'active') as active_contracts,
  max(a.occurred_at)                  as last_contact_at
from customers c
left join orders     o  on o.customer_id  = c.id and o.deleted_at is null
left join leads      l  on l.customer_id  = c.id and l.deleted_at is null
left join quotations q  on q.customer_id  = c.id
left join contracts  ct on ct.customer_id = c.id and ct.deleted_at is null
left join activities a  on a.customer_id  = c.id
where c.deleted_at is null
group by c.id, c.org_id, c.name, c.phone, c.customer_type,
         c.company_name, c.customer_since;


-- ───────────────────────────────────────────────────────────────────────────
-- 5. ROW LEVEL SECURITY
-- ───────────────────────────────────────────────────────────────────────────

do $$
declare t text;
begin
  foreach t in array array[
    'quote_versions','quote_approvals','quote_outcomes','discount_policies',
    'tasks','activities',
    'contracts','sla_events',
    'lead_sources','marketing_spend','referrals'
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
-- SEED — lead sources and a default discount policy per org
-- ═══════════════════════════════════════════════════════════════════════════

begin;

insert into lead_sources (org_id, code, name, channel, is_paid, sort_order)
select o.id, s.code, s.name, s.channel, s.is_paid, s.sort_order
from organizations o
cross join (values
  ('direct',      'Direct / Walk-in',  'walk_in',   false, 1),
  ('whatsapp',    'WhatsApp',          'organic',   false, 2),
  ('justdial',    'Justdial',          'directory', true,  3),
  ('sulekha',     'Sulekha',           'directory', true,  4),
  ('google_ads',  'Google Ads',        'paid_ads',  true,  5),
  ('facebook',    'Facebook / Meta',   'paid_ads',  true,  6),
  ('website',     'Website Enquiry',   'organic',   false, 7),
  ('referral',    'Referral',          'referral',  false, 8),
  ('repeat',      'Repeat Customer',   'repeat',    false, 9),
  ('porter',      'Porter',            'partner',   true,  10),
  ('other',       'Other',             'organic',   false, 11)
) as s(code, name, channel, is_paid, sort_order)
on conflict (org_id, code) do nothing;

-- Map existing free-text leads.source onto the new dimension
update leads l
set source_id = ls.id
from lead_sources ls
where l.source_id is null
  and ls.org_id = l.org_id
  and lower(trim(coalesce(l.source, ''))) = ls.code;

-- Anything unmatched goes to 'other'
update leads l
set source_id = ls.id
from lead_sources ls
where l.source_id is null
  and ls.org_id = l.org_id
  and ls.code = 'other';

insert into discount_policies (org_id, name, max_discount_pct, floor_margin_pct, approver_role)
select o.id, 'Default', 10, 15, 'owner'
from organizations o
where not exists (
  select 1 from discount_policies d where d.org_id = o.id
);

-- Backfill quote version 1 for existing quotations
insert into quote_versions (org_id, quote_id, version, snapshot, change_summary, total_amount)
select q.org_id, q.id, 1, to_jsonb(q), 'Initial version (backfilled)',
       coalesce(q.total, 0)
from quotations q
where not exists (
  select 1 from quote_versions qv where qv.quote_id = q.id
);

commit;


-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════
--
-- select
--   (select count(*) from information_schema.tables where table_schema='public'
--      and table_name in ('quote_versions','quote_approvals','quote_outcomes',
--        'discount_policies','tasks','activities','contracts','sla_events',
--        'lead_sources','marketing_spend','referrals')) as tables_expect_11,
--   (select count(*) from pg_policies where schemaname='public'
--      and policyname='org_isolation'
--      and tablename in ('tasks','activities','contracts','lead_sources'))
--        as policies_expect_4,
--   (select count(*) from lead_sources)        as sources_expect_orgs_x_11,
--   (select count(*) from leads where source_id is null) as unmapped_leads_expect_0,
--   (select count(*) from quote_versions)      as quote_versions_backfilled,
--   (select count(*) from discount_policies)   as policies_seeded;
--
-- select * from customer_360_view order by lifetime_value desc limit 5;
-- select * from lead_source_performance_view order by total_leads desc limit 10;
