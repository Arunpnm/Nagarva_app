-- Supervisor field operations — step 3, schema only (NG-DESIGN-supervisor-field-operations.md).
-- Handed over for Arun to review and run — not executed from this session.
-- Third rewrite (2026-08-07). Previous run failed and rolled back cleanly on the column drops:
-- ERROR 2BP01, dashboard_kpis_view depends on loading_signature. 60110b4 ran fine first;
-- current_staff_id()/is_org_owner() confirmed live, so this file's is_org_owner() references
-- are safe.
--
-- This rewrite:
--   A. Checked pg_depend + information_schema.view_column_usage for all 5 dead-column
--      candidates, not just the one that errored — see the report before section 10.
--   B. Recreates dashboard_kpis_view without the 5 columns, BEFORE dropping them, same
--      transaction. NOT using CASCADE anywhere.
--   C. orders.field_expenses is NOT dropped this pass — see the column comment in section 1.
--      Dropping it now would break the LIVE order_pnl_section.dart P&L card, which reads it
--      today; this migration is schema-only, no Dart change lands with it to stop that read.
--   D. Every CREATE POLICY in the file is now preceded by DROP POLICY IF EXISTS — applied
--      everywhere, not just the two sections flagged, for consistency.
--   E. Noted on the cast: backfilled float-entry spent_at values land at midnight (date-only
--      source data), not a real capture time.
--
-- Sequencing per Arun's own stated order: 60110b4 (done) -> Phase 0 -> Tier A -> this file.
-- Wrapped in one transaction: the data backfills at the bottom should never apply against a
-- schema that only partially landed.

begin;

-- ============================================================================
-- 1. orders — job_stage, exception-path columns, move_time.
-- ============================================================================
alter table orders
  add column if not exists job_stage text,
  add column if not exists hold_reason_code text,
  add column if not exists hold_reason_note text,
  add column if not exists move_time time;

alter table orders
  add constraint orders_job_stage_check
  check (job_stage is null or job_stage in (
    'assigned', 'accepted', 'departed_base', 'at_pickup', 'pre_move_documented',
    'packing', 'loading', 'in_transit', 'at_drop', 'unloading', 'unpacking',
    'job_complete', 'pending_verification', 'verified', 'settled',
    'on_hold', 'aborted'
  ));

alter table orders
  add constraint orders_hold_reason_code_check
  check (hold_reason_code is null or hold_reason_code in (
    'customer_not_home', 'wrong_address', 'goods_dont_fit',
    'customer_cancelled', 'vehicle_breakdown', 'damage_occurred'
  ));

-- Enforced, not advisory: resuming a job (moving job_stage off on_hold/aborted) while leaving
-- hold_reason_code set is REJECTED by this constraint, not silently cleared. The resume
-- action must null hold_reason_code (and probably hold_reason_note) in the same statement.
-- The reason isn't lost either way — the on_hold transition's order_status_history row keeps
-- its own copy in metadata.
alter table orders
  add constraint orders_hold_reason_requires_stage
  check (hold_reason_code is null or job_stage in ('on_hold', 'aborted'));

comment on column orders.hold_reason_code is
  'Only valid while job_stage is on_hold/aborted (enforced by orders_hold_reason_requires_'
  'stage — an update that changes job_stage away from those without also nulling this column '
  'in the same statement will be rejected, not silently cleared). Resuming from hold must '
  'null this explicitly. The reason is not lost on resume: the order_status_history row for '
  'the original on_hold transition carries its own copy in metadata.';

comment on column orders.move_time is
  'Scheduled start time for the crew on move_date. Single instant, not a booking window — no '
  'existing concept of a customer-available time RANGE exists anywhere else in this app.';

-- NOT dropped, NOT yet superseded in practice — see the recommendation this responds to
-- (2026-08-07): job_expense_float_entries now holds the same 5 legacy line items migrated
-- from this column (section 12), but order_pnl_section.dart still reads field_expenses live
-- today and this migration ships no Dart change to stop that. Dropping the column now would
-- break a working feature immediately. Once the P&L card is updated to read
-- job_expense_float_entries instead (a later, Dart-carrying step), field_expenses becomes
-- genuinely dead and THAT migration should drop it — don't read from this column again once
-- that happens, and don't reintroduce a write path to it either.
comment on column orders.field_expenses is
  'SUPERSEDED BY job_expense_float_entries as of the 2026-08-07 supervisor field-ops '
  'migration, but still the live read path for order_pnl_section.dart until that Dart change '
  'ships — do not drop this column until that reader is updated, or the P&L card breaks. '
  'Do not add a new write path to this column; new field-cost entries belong in '
  'job_expense_float_entries.';

-- ============================================================================
-- 2. vehicle_trips — make the per-order relationship DB-enforced.
-- ============================================================================
alter table vehicle_trips
  add constraint vehicle_trips_order_id_fkey
  foreign key (order_id) references orders(id) on delete set null;

alter table vehicle_trips
  add constraint vehicle_trips_order_id_key unique (order_id);

-- ============================================================================
-- 3. order_status_history — extension.
-- ============================================================================
alter table order_status_history
  add column if not exists job_stage text,
  add column if not exists device_at timestamptz,
  add column if not exists latitude numeric,
  add column if not exists longitude numeric,
  add column if not exists metadata jsonb not null default '{}'::jsonb,
  add column if not exists customer_visible boolean not null default false;

comment on column order_status_history.job_stage is
  'Fine-grained stage value, populated only by the supervisor field-ops flow. Existing '
  'status-only writers (TrackingService) are unaffected and leave this null.';
comment on column order_status_history.metadata is
  'Non-queried stage context only. Anything that needs to be scanned/reported on (photos, '
  'item counts) has its own table (job_photos, order_item_counts) — do not add another '
  'queryable fact into this jsonb blob instead of a real column/table.';
comment on column order_status_history.customer_visible is
  'Whether this row''s job_stage MILESTONE (label + changed_at only) appears on the public '
  'customer tracking timeline. Stamped once, at write time, by the logging app code from a '
  'fixed allowlist keyed on job_stage — never computed later by the read side. Independent of '
  'this flag: note/metadata/latitude/longitude/device_at are NEVER returned by the customer-'
  'facing RPC regardless of this column''s value — it gates whether a milestone shows at all, '
  'not which fields widen once it does.';

create index if not exists idx_order_status_history_order_stage
  on order_status_history (order_id, job_stage);

-- ============================================================================
-- 4. job_photos — new.
-- ============================================================================
create table if not exists job_photos (
  id uuid primary key default gen_random_uuid(),
  org_id uuid,
  order_id text not null,
  event_id uuid references order_status_history(id) on delete set null,
  category text not null check (category in (
    'pre_existing_damage', 'packing', 'loading', 'crew_departure', 'vehicle_departure',
    'unpacking', 'crew_return', 'vehicle_return', 'pod'
  )),
  storage_path text not null,
  taken_at timestamptz,
  uploaded_at timestamptz not null default now(),
  created_by uuid
);

comment on column job_photos.storage_path is
  'Bucket-relative path in job-photos ({org_id}/{order_id}/{category}/{file}), resolved to a '
  'signed URL only at display time. Never store a signed/public URL here — it expires.';

create index if not exists idx_job_photos_org_taken_at on job_photos (org_id, taken_at);
create index if not exists idx_job_photos_order on job_photos (order_id);

alter table job_photos enable row level security;

drop policy if exists org_isolation on job_photos;
create policy org_isolation on job_photos
  for all
  using (org_id in (select current_org_ids()) or is_platform_admin())
  with check (org_id in (select current_org_ids()) or is_platform_admin());

-- ============================================================================
-- 5. order_item_counts — new.
-- ============================================================================
create table if not exists order_item_counts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid,
  order_id text not null,
  stage text not null check (stage in ('loading', 'unloading')),
  expected_count integer,
  actual_count integer not null,
  recorded_at timestamptz not null default now(),
  recorded_by uuid,
  note text,
  unique (order_id, stage)
);

create index if not exists idx_order_item_counts_order on order_item_counts (order_id);

alter table order_item_counts enable row level security;

drop policy if exists org_isolation on order_item_counts;
create policy org_isolation on order_item_counts
  for all
  using (org_id in (select current_org_ids()) or is_platform_admin())
  with check (org_id in (select current_org_ids()) or is_platform_admin());

-- ============================================================================
-- 6. wage_rate_defaults — new.
-- ============================================================================
create table if not exists wage_rate_defaults (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  role text not null,
  day_rate numeric not null default 0,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  unique (org_id, role)
);

alter table wage_rate_defaults enable row level security;

drop policy if exists owner_only on wage_rate_defaults;
create policy owner_only on wage_rate_defaults
  for all
  using (is_org_owner(org_id) or is_platform_admin())
  with check (is_org_owner(org_id) or is_platform_admin());

-- ============================================================================
-- 7. job_expense_floats / job_expense_float_entries — Tier C, float issuance owner-only.
-- ============================================================================
create table if not exists job_expense_floats (
  id uuid primary key default gen_random_uuid(),
  org_id uuid,
  order_id text not null,
  staff_id uuid,
  issued_amount numeric not null default 0,
  issued_at timestamptz,
  issued_by uuid,
  status text not null default 'open' check (status in ('open', 'reconciled')),
  reconciled_amount numeric,
  reconciled_at timestamptz,
  reconciled_by uuid,
  is_backfill boolean not null default false,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists job_expense_float_entries (
  id uuid primary key default gen_random_uuid(),
  float_id uuid not null references job_expense_floats(id) on delete cascade,
  org_id uuid,
  expense_type text not null,
  amount numeric not null,
  -- timestamptz, not date: real field entries carry a real capture instant. The 5 rows this
  -- migration backfills from legacy orders.field_expenses are the one exception — that
  -- source data was date-only, so section 12 casts to ::date and every backfilled row lands
  -- at midnight. That's expected for historical data, not a bug — do not read a backfilled
  -- row's spent_at as a real capture time.
  spent_at timestamptz,
  location text,
  receipt_path text,
  note text,
  created_at timestamptz not null default now()
);

comment on column job_expense_float_entries.receipt_path is
  'Bucket-relative storage path, same convention as job_photos.storage_path — resolved to a '
  'signed URL only at display time. Not a signed URL itself — those expire.';

comment on column job_expense_floats.is_backfill is
  'True only for the 2 rows this migration backfills from legacy orders.field_expenses — no '
  'float was ever actually issued for those orders (issued_amount is 0 by construction). '
  'MANDATORY: every balance / outstanding-float / "amount owed back" calculation must filter '
  'is_backfill = true out, not just exclude it from reporting — with issued_amount = 0 and a '
  'positive reconciled_amount, an unfiltered calculation reads as the company owing the '
  'supervisor money, which is backwards. No app code reads this table yet; this comment is '
  'the spec for whoever writes the first query against it.';

create index if not exists idx_job_expense_floats_order on job_expense_floats (order_id);
create index if not exists idx_job_expense_float_entries_float
  on job_expense_float_entries (float_id);

alter table job_expense_floats enable row level security;
alter table job_expense_float_entries enable row level security;

drop policy if exists job_expense_floats_select on job_expense_floats;
create policy job_expense_floats_select on job_expense_floats
  for select
  using (org_id in (select current_org_ids()) or is_platform_admin());

-- Float ISSUANCE is owner-only: a supervisor inserting their own float row is handing
-- themselves cash. Same is_org_owner() gate as UPDATE/DELETE.
drop policy if exists job_expense_floats_insert on job_expense_floats;
create policy job_expense_floats_insert on job_expense_floats
  for insert
  with check (is_org_owner(org_id) or is_platform_admin());

drop policy if exists job_expense_floats_update on job_expense_floats;
create policy job_expense_floats_update on job_expense_floats
  for update
  using (is_org_owner(org_id) or is_platform_admin())
  with check (is_org_owner(org_id) or is_platform_admin());

drop policy if exists job_expense_floats_delete on job_expense_floats;
create policy job_expense_floats_delete on job_expense_floats
  for delete
  using (is_org_owner(org_id) or is_platform_admin());

-- Float entries stay staff-writable — spending against an already-issued float is the
-- supervisor's actual job, not a privileged action.
drop policy if exists job_expense_float_entries_select on job_expense_float_entries;
create policy job_expense_float_entries_select on job_expense_float_entries
  for select
  using (org_id in (select current_org_ids()) or is_platform_admin());

drop policy if exists job_expense_float_entries_insert on job_expense_float_entries;
create policy job_expense_float_entries_insert on job_expense_float_entries
  for insert
  with check (org_id in (select current_org_ids()) or is_platform_admin());

drop policy if exists job_expense_float_entries_update on job_expense_float_entries;
create policy job_expense_float_entries_update on job_expense_float_entries
  for update
  using (is_org_owner(org_id) or is_platform_admin())
  with check (is_org_owner(org_id) or is_platform_admin());

drop policy if exists job_expense_float_entries_delete on job_expense_float_entries;
create policy job_expense_float_entries_delete on job_expense_float_entries
  for delete
  using (is_org_owner(org_id) or is_platform_admin());

-- ============================================================================
-- 8. Storage — job-photos bucket and its access policies.
-- ============================================================================
insert into storage.buckets (id, name, public)
values ('job-photos', 'job-photos', false)
on conflict (id) do nothing;

-- storage.foldername(name) returns the path segments as text[]; comparing that first segment
-- as TEXT against current_org_ids()::text (rather than casting the path segment itself to
-- uuid) is deliberate — a malformed path would make a ::uuid cast on untrusted input THROW,
-- turning a bad upload into a hard error instead of a clean access denial.
-- No UPDATE policy: a photo is uploaded once and never edited in place.
drop policy if exists job_photos_select on storage.objects;
create policy job_photos_select on storage.objects
  for select
  using (
    bucket_id = 'job-photos'
    and (
      (storage.foldername(name))[1] in (select current_org_ids()::text)
      or is_platform_admin()
    )
  );

drop policy if exists job_photos_insert on storage.objects;
create policy job_photos_insert on storage.objects
  for insert
  with check (
    bucket_id = 'job-photos'
    and (
      (storage.foldername(name))[1] in (select current_org_ids()::text)
      or is_platform_admin()
    )
  );

drop policy if exists job_photos_delete on storage.objects;
create policy job_photos_delete on storage.objects
  for delete
  using (
    bucket_id = 'job-photos'
    and (
      (storage.foldername(name))[1] in (select current_org_ids()::text)
      or is_platform_admin()
    )
  );

-- ============================================================================
-- 9. dashboard_kpis_view — recreated WITHOUT the 5 columns section 10 drops.
-- ============================================================================
-- Live failure from the previous run, reported by Arun: DROP COLUMN loading_signature failed
-- with 2BP01, "view dashboard_kpis_view depends on column loading_signature". Checked
-- pg_depend + information_schema.view_column_usage for all 5 candidate columns (not just the
-- one that errored, per the same request) — dashboard_kpis_view is the ONLY dependent object
-- for any of loading_signature / delivery_signature / loading_photos / delivery_photos /
-- submitted_at. Nothing else in the schema (no other view, function, trigger, index)
-- references any of them.
--
-- Read the view's definition before writing this: NOT a `select *` dependency, but
-- functionally the same thing — the view's `month_orders` CTE pulls all 5 columns into its
-- own column list (looks like a full pass-through of most of `orders`), but NONE of the 5 is
-- referenced again anywhere downstream — not in revenue/labour/expenses/porter_comm/
-- active_leads/orders_count/outstanding/reminders_today, and not in the final SELECT. They
-- are dead weight in an intermediate CTE, not something the dashboard computes from or
-- filters on. This is the "incidental" case: recreating the view without them changes
-- nothing about what the dashboard shows.
--
-- CREATE OR REPLACE is sufficient here (not DROP + CREATE) because the view's actual OUTPUT
-- column list — the columns Postgres enforces can't change on a plain REPLACE — is unchanged;
-- only an internal CTE's unused pass-through columns are being trimmed. No CASCADE anywhere
-- in this file. This statement must run BEFORE section 10's column drops, in the same
-- transaction, or the drops fail again exactly as they did before.
create or replace view dashboard_kpis_view as
 with org_ids as (
         select distinct orders.org_id
           from orders
          where orders.org_id is not null and orders.deleted_at is null
        union
         select distinct staff.org_id
           from staff
          where staff.org_id is not null
        union
         select distinct expenses_1.org_id
           from public.expenses expenses_1
          where expenses_1.org_id is not null and expenses_1.deleted_at is null
        union
         select distinct leads.org_id
           from leads
          where leads.org_id is not null and leads.deleted_at is null
        ), month_orders as (
         select orders.id,
            orders.lead_id,
            orders.quotation_id,
            orders.customer,
            orders.phone,
            orders.from_city,
            orders.to_city,
            orders.from_address,
            orders.to_address,
            orders.from_floor,
            orders.to_floor,
            orders.move_date,
            orders.amount,
            orders.order_type,
            orders.distance_km,
            orders.status,
            orders.service,
            orders.branch,
            orders.notes,
            orders.advance_paid,
            orders.payment_status,
            orders.created_at,
            orders.invoice_no,
            orders.supervisor_id,
            orders.quotation_token,
            orders.assigned_at,
            orders.accepted_at,
            orders.loading_started_at,
            orders.loading_completed_at,
            orders.transit_started_at,
            orders.unloading_started_at,
            orders.delivered_at,
            orders.closed_at,
            orders.field_expenses,
            orders.damage_report,
            orders.vehicle_no,
            orders.driver_name,
            orders.driver_phone,
            orders.lr_no,
            orders.lr_issued_at,
            orders.invoice_issued_at,
            orders.order_complete,
            orders.order_source,
            orders.porter_cash_collect,
            orders.is_porter,
            orders.porter_commission_pct,
            orders.porter_order_no,
            orders.job_start_time,
            orders.job_end_time,
            orders.job_otp,
            orders.job_team,
            orders.supervisor_notes,
            orders.supervisor_status,
            orders.tracking_status,
            orders.org_id,
            orders.paid_total,
            orders.tracking_token,
            orders.deleted_at,
            orders.deleted_by,
            orders.delete_reason
           from orders
          where date_trunc('month'::text, orders.created_at) = date_trunc('month'::text, now()) and orders.deleted_at is null
        ), revenue as (
         select month_orders.org_id,
            coalesce(sum(month_orders.amount), 0::numeric) as v
           from month_orders
          group by month_orders.org_id
        ), labour as (
         select staff.org_id,
            coalesce(sum(staff.salary), 0::numeric) as v
           from staff
          where staff.active is distinct from false
          group by staff.org_id
        ), expenses as (
         select expenses_1.org_id,
            coalesce(sum(expenses_1.amount), 0::numeric) as v
           from public.expenses expenses_1
          where date_trunc('month'::text, coalesce(expenses_1.expense_date::timestamp with time zone, expenses_1.created_at)) = date_trunc('month'::text, now()) and expenses_1.deleted_at is null
          group by expenses_1.org_id
        ), porter_comm as (
         select month_orders.org_id,
            coalesce(sum(month_orders.porter_cash_collect * coalesce(month_orders.porter_commission_pct, 0::numeric) / 100.0), 0::numeric) as v
           from month_orders
          where month_orders.is_porter is true
          group by month_orders.org_id
        ), active_leads as (
         select leads.org_id,
            count(*) as v
           from leads
          where ((leads.status <> all (array['won'::text, 'lost'::text, 'closed'::text])) or leads.status is null) and leads.deleted_at is null
          group by leads.org_id
        ), orders_count as (
         select month_orders.org_id,
            count(*) as v
           from month_orders
          group by month_orders.org_id
        ), outstanding as (
         select orders.org_id,
            coalesce(sum(orders.amount - coalesce(orders.advance_paid, 0::numeric)), 0::numeric) as v
           from orders
          where orders.payment_status is distinct from 'paid'::text and orders.deleted_at is null
          group by orders.org_id
        ), reminders_today as (
         select reminders.org_id,
            count(*) as v
           from reminders
          where reminders.due_date = current_date and coalesce(reminders.done, reminders.completed, false) is not true
          group by reminders.org_id
        )
 select oi.org_id::text as id,
    oi.org_id,
    coalesce(revenue.v, 0::numeric) as revenue_this_month,
    coalesce(labour.v, 0::numeric) as labour_this_month,
    coalesce(expenses.v, 0::numeric) as expenses_this_month,
    coalesce(porter_comm.v, 0::numeric) as porter_comm_this_month,
    coalesce(revenue.v, 0::numeric) - coalesce(labour.v, 0::numeric) - coalesce(expenses.v, 0::numeric) - coalesce(porter_comm.v, 0::numeric) as net_profit_this_month,
    coalesce(active_leads.v, 0::bigint) as active_leads,
    coalesce(orders_count.v, 0::bigint) as orders_this_month,
    coalesce(outstanding.v, 0::numeric) as outstanding_amount,
    coalesce(reminders_today.v, 0::bigint) as reminders_today
   from org_ids oi
     left join revenue on revenue.org_id = oi.org_id
     left join labour on labour.org_id = oi.org_id
     left join expenses on expenses.org_id = oi.org_id
     left join porter_comm on porter_comm.org_id = oi.org_id
     left join active_leads on active_leads.org_id = oi.org_id
     left join orders_count on orders_count.org_id = oi.org_id
     left join outstanding on outstanding.org_id = oi.org_id
     left join reminders_today on reminders_today.org_id = oi.org_id;

-- ============================================================================
-- 10. Dead columns — dropped. Live counts verified (7 Aug 2026):
--   loading_signature: 0/25 non-null.  delivery_signature: 0/25 non-null.
--   loading_photos: 0/25 non-empty.    delivery_photos: 0/25 non-empty.
--   submitted_at: 0/25 non-null.
-- Dependency-checked (this pass): only dashboard_kpis_view referenced any of them, and only
-- incidentally (section 9) — now recreated without them, so these drops are safe. No CASCADE.
-- pod_records.photo_urls is NOT dropped — left in place, unwritten, per the design decision.
-- orders.field_expenses is NOT dropped this pass — see its column comment in section 1.
-- ============================================================================
alter table orders
  drop column if exists loading_signature,
  drop column if exists delivery_signature,
  drop column if exists loading_photos,
  drop column if exists delivery_photos,
  drop column if exists submitted_at;

-- ============================================================================
-- 11. Data backfill — the 2 existing closed orders.
-- ============================================================================
update orders
set job_stage = 'settled'
where id in ('APC-1006', 'APC-1007')
  and status = 'closed'
  and supervisor_status = 'approved';

-- ============================================================================
-- 12. Data migration — orders.field_expenses -> job_expense_floats / ...entries.
-- ============================================================================
-- (e->>'at')::date cast below is deliberate for THIS backfill only — the legacy jsonb only
-- ever carried a date string, not a time, so every migrated entry's spent_at lands at
-- midnight. See the column comment on job_expense_float_entries.spent_at (section 7): this
-- is expected for historical data, not a real capture time, and not a pattern to repeat for
-- entries created going forward by the real field-ops flow.
with affected as (
  select id as order_id, org_id, supervisor_id, closed_at, field_expenses
  from orders
  where field_expenses is not null and field_expenses <> '[]'::jsonb
),
new_floats as (
  insert into job_expense_floats
    (org_id, order_id, staff_id, issued_amount, status,
     reconciled_amount, reconciled_at, is_backfill, notes)
  select
    a.org_id,
    a.order_id,
    a.supervisor_id,
    0,
    'reconciled',
    (select coalesce(sum((e->>'amount')::numeric), 0)
       from jsonb_array_elements(a.field_expenses) e),
    a.closed_at,
    true,
    'Backfilled from legacy orders.field_expenses at the supervisor field-ops schema '
    'migration (2026-08-07) — no float was actually issued for this order, the float '
    'concept did not exist yet. See is_backfill column comment: every balance calculation '
    'must filter this out, not just exclude it from reporting.'
  from affected a
  returning id, order_id
)
insert into job_expense_float_entries
  (float_id, org_id, expense_type, amount, spent_at, note)
select
  nf.id,
  a.org_id,
  e->>'type',
  (e->>'amount')::numeric,
  (e->>'at')::date,
  nullif(e->>'note', '')
from affected a
join new_floats nf on nf.order_id = a.order_id
cross join lateral jsonb_array_elements(a.field_expenses) e;

commit;
