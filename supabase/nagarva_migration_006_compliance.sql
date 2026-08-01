-- ═══════════════════════════════════════════════════════════════════════════
-- NAGARVA MIGRATION 006 — COMPLIANCE TAIL & PLATFORM
-- Project: hqqcapifefsaqvotqvlt
-- Depends on: 001 (customers, documents, org_usage) · 005 (audit_log columns)
--
-- Covers: DPDP consent/erasure/export, push notification tokens & delivery log,
--         backup registry, tenant onboarding checklist, saved reports,
--         numbering series, app settings.
--
-- Final planned migration. Corrections beyond this are expected as real data
-- meets the schema — that is normal, not a planning failure.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. DPDP ACT COMPLIANCE  [LEGAL]
--    India's Digital Personal Data Protection Act. Nagarva is the data
--    processor; each tenant is the data fiduciary for their customers.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists consent_records (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  subject_type    text not null default 'customer',  -- customer | staff | lead
  subject_id      uuid,
  phone           text,
  purpose         text not null,
                  -- service_delivery | marketing | whatsapp_updates
                  -- kyc_storage | review_request
  consent_given   boolean default false,
  consent_method  text,               -- verbal | whatsapp | web_form | signed_doc | implied
  consent_text    text,               -- exact wording shown at the time
  consent_version text,
  given_at        timestamptz,
  withdrawn_at    timestamptz,
  withdrawal_reason text,
  evidence_url    text,
  recorded_by     text,
  created_at      timestamptz default now()
);
create index if not exists consent_subject_idx on consent_records (org_id, subject_type, subject_id);
create index if not exists consent_phone_idx   on consent_records (org_id, phone);
create index if not exists consent_purpose_idx on consent_records (org_id, purpose, consent_given);

-- Data subject requests: access, correction, erasure, portability
create table if not exists data_requests (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  request_type    text not null,      -- access | correction | erasure | portability
  subject_type    text default 'customer',
  subject_id      uuid,
  requester_name  text,
  requester_phone text,
  requester_email text,
  identity_verified boolean default false,
  verification_method text,
  details         text,
  status          text default 'received',
                  -- received | verifying | processing | completed | rejected
  -- statutory clock
  received_at     timestamptz default now(),
  due_at          timestamptz,        -- received_at + 30 days
  completed_at    timestamptz,
  rejection_reason text,
  -- outcome
  export_url      text,
  records_affected int default 0,
  handled_by      text,
  notes           text,
  created_at      timestamptz default now()
);
create index if not exists data_req_status_idx on data_requests (org_id, status, due_at);

-- Erasure audit: proof of what was deleted, retained after the data is gone
create table if not exists erasure_log (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  request_id      uuid references data_requests(id) on delete set null,
  subject_type    text,
  subject_id      uuid,
  subject_ref     text,               -- masked identifier, e.g. "98XXXXXX25"
  tables_affected text[] default '{}',
  records_deleted int default 0,
  records_anonymised int default 0,
  retained_tables text[] default '{}', -- kept for statutory reasons
  retention_basis text,               -- e.g. "GST invoice - 8 year retention"
  erased_at       timestamptz default now(),
  erased_by       text,
  created_at      timestamptz default now()
);
create index if not exists erasure_log_idx on erasure_log (org_id, erased_at desc);

-- Retention policy per data class
create table if not exists retention_policies (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  data_class      text not null,
                  -- invoice | lead | kyc_document | wa_message
                  -- call_log | pod | claim_photo
  retention_months int not null default 96,   -- 8 years default (GST)
  legal_basis     text,
  auto_purge      boolean default false,
  last_purge_at   timestamptz,
  active          boolean default true,
  created_at      timestamptz default now()
);
create unique index if not exists retention_class_uniq on retention_policies (org_id, data_class);

-- Breach register
create table if not exists breach_incidents (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  detected_at     timestamptz default now(),
  incident_type   text,               -- unauthorised_access | data_loss | disclosure
  severity        text default 'low', -- low | medium | high | critical
  description     text,
  affected_count  int default 0,
  data_classes    text[] default '{}',
  contained_at    timestamptz,
  reported_to_dpb boolean default false,
  reported_at     timestamptz,
  subjects_notified boolean default false,
  remediation     text,
  status          text default 'open',
  created_at      timestamptz default now()
);


-- ───────────────────────────────────────────────────────────────────────────
-- 2. PUSH NOTIFICATIONS
--    APC relies on WhatsApp only. Flutter can push natively.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists notification_tokens (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  staff_id        uuid references staff(id) on delete cascade,
  token           text not null,
  platform        text,               -- android | ios | web
  device_id       text,
  device_name     text,
  app_version     text,
  active          boolean default true,
  last_used_at    timestamptz,
  created_at      timestamptz default now()
);
create unique index if not exists notif_token_uniq on notification_tokens (token);
create index if not exists notif_staff_idx on notification_tokens (org_id, staff_id, active);

create table if not exists notification_log (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  staff_id        uuid references staff(id) on delete set null,
  token_id        uuid references notification_tokens(id) on delete set null,
  channel         text default 'push',   -- push | whatsapp | sms | in_app
  event_type      text,
                  -- lead_assigned | order_assigned | supervisor_accepted
                  -- otp_completed | payment_received | task_due
                  -- eway_expiring | doc_expiring | low_stock
  title           text,
  body            text,
  payload         jsonb default '{}'::jsonb,
  entity_type     text,
  entity_id       text,
  status          text default 'queued', -- queued | sent | delivered | failed | read
  error_message   text,
  sent_at         timestamptz,
  read_at         timestamptz,
  created_at      timestamptz default now()
);
create index if not exists notif_log_staff_idx  on notification_log (org_id, staff_id, created_at desc);
create index if not exists notif_log_status_idx on notification_log (status, created_at);

-- Per-user notification preferences
create table if not exists notification_prefs (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  staff_id        uuid references staff(id) on delete cascade,
  event_type      text not null,
  push_enabled    boolean default true,
  whatsapp_enabled boolean default false,
  quiet_from      time,
  quiet_to        time,
  created_at      timestamptz default now()
);
create unique index if not exists notif_prefs_uniq on notification_prefs (staff_id, event_type);


-- ───────────────────────────────────────────────────────────────────────────
-- 3. BACKUP & EXPORT REGISTRY
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists backup_registry (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  backup_type     text default 'scheduled',  -- scheduled | manual | pre_migration
  scope           text default 'full',       -- full | module
  modules         text[] default '{}',
  status          text default 'running',    -- running | completed | failed
  file_url        text,
  file_size_bytes bigint,
  row_counts      jsonb default '{}'::jsonb,
  started_at      timestamptz default now(),
  completed_at    timestamptz,
  error_message   text,
  expires_at      timestamptz,
  triggered_by    text,
  created_at      timestamptz default now()
);
create index if not exists backup_org_idx on backup_registry (org_id, started_at desc);

create table if not exists export_jobs (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  export_type     text not null,      -- module | report | full_tenant | dpdp_portability
  module          text,
  format          text default 'xlsx',-- xlsx | csv | pdf | json
  filters         jsonb default '{}'::jsonb,
  date_from       date,
  date_to         date,
  status          text default 'queued',
  file_url        text,
  row_count       int default 0,
  requested_by    text,
  completed_at    timestamptz,
  expires_at      timestamptz,
  created_at      timestamptz default now()
);
create index if not exists export_jobs_idx on export_jobs (org_id, status, created_at desc);


-- ───────────────────────────────────────────────────────────────────────────
-- 4. TENANT ONBOARDING
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists onboarding_progress (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid not null,
  step_key          text not null,
                    -- business_details | gst_details | branches | branding
                    -- first_staff | doc_templates | rate_card | whatsapp
                    -- payment_setup | first_lead | first_order
  status            text default 'pending',   -- pending | skipped | completed
  completed_at      timestamptz,
  completed_by      text,
  data              jsonb default '{}'::jsonb,
  created_at        timestamptz default now()
);
create unique index if not exists onboarding_step_uniq on onboarding_progress (org_id, step_key);

alter table organizations add column if not exists onboarding_completed boolean default false;
alter table organizations add column if not exists onboarding_completed_at timestamptz;
alter table organizations add column if not exists sample_data_loaded boolean default false;
alter table organizations add column if not exists business_type text;
alter table organizations add column if not exists address text;
alter table organizations add column if not exists city text;
alter table organizations add column if not exists state text;
alter table organizations add column if not exists state_code int;
alter table organizations add column if not exists pincode text;
alter table organizations add column if not exists pan text;
alter table organizations add column if not exists cin text;
alter table organizations add column if not exists website text;
alter table organizations add column if not exists support_email text;
alter table organizations add column if not exists tagline text;
alter table organizations add column if not exists primary_color text;
alter table organizations add column if not exists google_review_url text;
alter table organizations add column if not exists upi_id text;


-- ───────────────────────────────────────────────────────────────────────────
-- 5. NUMBERING SERIES
--    lr_series exists. Every other document numbers ad hoc.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists number_series (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  doc_type        text not null,
                  -- invoice | proforma | receipt | quotation | credit_note
                  -- debit_note | po | grn | payslip | claim | storage_job
                  -- contract | voucher | eway
  branch          text,
  fy              text,
  prefix          text default '',
  suffix          text default '',
  padding         int default 4,
  last_number     int default 0,
  active          boolean default true,
  created_at      timestamptz default now()
);
create unique index if not exists number_series_uniq
  on number_series (org_id, doc_type, coalesce(branch,''), coalesce(fy,''));

-- Atomic next-number allocation. Row lock prevents duplicates under concurrency.
create or replace function next_doc_number(
  p_org uuid, p_doc_type text, p_branch text default null, p_fy text default null
) returns text as $$
declare rec record; n int;
begin
  select * into rec from number_series
   where org_id = p_org and doc_type = p_doc_type
     and coalesce(branch,'') = coalesce(p_branch,'')
     and coalesce(fy,'') = coalesce(p_fy,'')
   for update;

  if not found then
    insert into number_series (org_id, doc_type, branch, fy, last_number)
    values (p_org, p_doc_type, p_branch, p_fy, 1)
    returning * into rec;
    n := 1;
  else
    n := rec.last_number + 1;
    update number_series set last_number = n where id = rec.id;
  end if;

  return coalesce(rec.prefix,'') || lpad(n::text, coalesce(rec.padding,4), '0')
         || coalesce(rec.suffix,'');
end;
$$ language plpgsql;


-- ───────────────────────────────────────────────────────────────────────────
-- 6. APP SETTINGS & SAVED REPORTS
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists app_settings (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  category        text not null,      -- documents | whatsapp | pricing | ops | branding
  key             text not null,
  value           jsonb,
  updated_by      text,
  updated_at      timestamptz default now(),
  created_at      timestamptz default now()
);
create unique index if not exists app_settings_uniq on app_settings (org_id, category, key);

create table if not exists saved_reports (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid,
  name            text not null,
  report_type     text not null,
  filters         jsonb default '{}'::jsonb,
  columns         text[] default '{}',
  group_by        text,
  sort_by         text,
  is_shared       boolean default false,
  created_by      text,
  -- scheduled delivery
  schedule        text,               -- null | daily | weekly | monthly
  schedule_day    int,
  recipients      text[] default '{}',
  last_run_at     timestamptz,
  created_at      timestamptz default now()
);
create index if not exists saved_reports_org_idx on saved_reports (org_id, report_type);


-- ───────────────────────────────────────────────────────────────────────────
-- 7. ROW LEVEL SECURITY
-- ───────────────────────────────────────────────────────────────────────────

do $$
declare t text;
begin
  foreach t in array array[
    'consent_records','data_requests','erasure_log','retention_policies',
    'breach_incidents',
    'notification_tokens','notification_log','notification_prefs',
    'backup_registry','export_jobs',
    'onboarding_progress','number_series','app_settings','saved_reports'
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
-- SEED
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- Retention defaults. Invoice at 96 months per GST record-keeping rules.
insert into retention_policies (org_id, data_class, retention_months, legal_basis)
select o.id, r.data_class, r.months, r.basis
from organizations o
cross join (values
  ('invoice',      96, 'GST Act - 72 months from annual return due date'),
  ('lead',         24, 'Business need'),
  ('kyc_document', 96, 'Statutory KYC retention'),
  ('wa_message',   24, 'Business need'),
  ('call_log',     12, 'Business need'),
  ('pod',          96, 'Carrier liability period'),
  ('claim_photo',  60, 'Insurance claim limitation period')
) as r(data_class, months, basis)
on conflict (org_id, data_class) do nothing;

-- Onboarding checklist. Existing orgs are marked complete so they are not
-- forced back through a wizard.
insert into onboarding_progress (org_id, step_key, status, completed_at)
select o.id, s.step_key,
       case when o.created_at < now() - interval '1 day' then 'completed' else 'pending' end,
       case when o.created_at < now() - interval '1 day' then now() else null end
from organizations o
cross join (values
  ('business_details'), ('gst_details'), ('branches'), ('branding'),
  ('first_staff'), ('doc_templates'), ('rate_card'), ('whatsapp'),
  ('payment_setup'), ('first_lead'), ('first_order')
) as s(step_key)
on conflict (org_id, step_key) do nothing;

update organizations
set onboarding_completed = true, onboarding_completed_at = now()
where created_at < now() - interval '1 day'
  and onboarding_completed is not true;

-- Number series for the current FY
insert into number_series (org_id, doc_type, fy, prefix, padding, last_number)
select o.id, d.doc_type,
       case when extract(month from current_date) >= 4
            then extract(year from current_date)::text || '-' ||
                 right((extract(year from current_date)+1)::text, 2)
            else (extract(year from current_date)-1)::text || '-' ||
                 right(extract(year from current_date)::text, 2)
       end,
       d.prefix, 4, 0
from organizations o
cross join (values
  ('invoice',     'INV-'), ('proforma',    'PI-'),
  ('receipt',     'RCP-'), ('quotation',   'QT-'),
  ('credit_note', 'CN-'),  ('debit_note',  'DN-'),
  ('po',          'PO-'),  ('grn',         'GRN-'),
  ('payslip',     'PS-'),  ('claim',       'CLM-'),
  ('storage_job', 'STG-'), ('contract',    'CTR-'),
  ('voucher',     'PV-')
) as d(doc_type, prefix)
on conflict do nothing;

commit;


-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════
--
-- select
--   (select count(*) from information_schema.tables where table_schema='public'
--      and table_name in ('consent_records','data_requests','erasure_log',
--        'retention_policies','breach_incidents','notification_tokens',
--        'notification_log','notification_prefs','backup_registry',
--        'export_jobs','onboarding_progress','number_series','app_settings',
--        'saved_reports')) as tables_expect_14,
--   (select count(*) from retention_policies)  as retention_expect_orgs_x_7,
--   (select count(*) from number_series)       as series_expect_orgs_x_13,
--   (select count(*) from onboarding_progress) as onboarding_expect_orgs_x_11;
--
-- -- test atomic numbering (returns INV-0001 on first call):
-- -- select next_doc_number((select id from organizations limit 1), 'invoice', null, '2026-27');
--
-- -- full object count across all six migrations:
-- select count(*) as total_tables from information_schema.tables
--  where table_schema='public' and table_type='BASE TABLE';
