-- TYPE-SAFETY NOTE (added 2026-07-19): all joins cast both sides to ::text.
-- This live schema mixes id types (staff.id uuid, orders.id text,
-- attendance.staff_id text, ...) and bare `uuid = text` joins fail with
-- 42883. uuid::text is always valid and text::text is a no-op, so the
-- casts make every join type-proof without caring which side is which.
-- ============================================================================
-- Nagarva Supabase (hqqcapifefsaqvotqvlt) — missing dashboard/ops views
-- ============================================================================
-- Fixes CLAUDE.md known bug #1: HomePage/SalaryPage/OperationsPage/CalendarPage
-- throw PGRST205 "Could not find the table 'public.<view>'" because these 6
-- views were never created in this Supabase project (only in the old,
-- unrelated xwnvhrecgubikloxkiis project).
--
-- IMPORTANT — run this first and paste the output back before running the
-- CREATE VIEW statements below, so column names/types can be double-checked
-- against what's actually in your tables (this SQL was written by reading
-- the Flutter generated table classes in lib/backend/supabase/database/tables/,
-- not by inspecting the live schema):
--
--   select table_name, column_name, data_type
--   from information_schema.columns
--   where table_schema = 'public'
--     and table_name in ('orders','leads','staff','attendance','staff_advances',
--                         'vehicle_trips','reminders','expenses')
--   order by table_name, ordinal_position;
--
-- NOTES / ASSUMPTIONS (flagged so you can correct before running):
--  1. UPDATED 13 Jul 2026 (Phase 1 pass): these views now pass org_id
--     through from their base tables so the app can filter client-side —
--     run supabase/phase1_add_org_id.sql FIRST, since these views select
--     org_id from orders/staff/attendance/etc. and will fail to create if
--     those columns don't exist yet. dashboard_kpis_view and
--     branch_kpis_view are now grouped per-org (one row per org_id) instead
--     of one global row — the Dart queries need `.eq('org_id', currentOrgId)`
--     added (already done on the pages touched this session; double check
--     any others that read these two views).
--  2. "This month" = calendar month in server time (date_trunc('month', now())).
--  3. revenue_this_month is based on orders.created_at (booking date), not
--     move_date. If the business wants revenue recognised on move_date
--     instead, change the two date_trunc predicates in dashboard_kpis_view
--     and branch_kpis_view accordingly.
--  4. net_profit_this_month = revenue - labour - expenses - porter commission.
--     labour is total active-staff salary (not date-scoped, since staff.salary
--     has no pay-period column yet) rather than a true monthly payroll run.
--  5. dashboard_kpis_view and branch_kpis_view return exactly one synthetic
--     row (dashboard_kpis_view) / one row per branch (branch_kpis_view) to
--     match how the Flutter code reads them (queryRows with no filter, then
--     takes the list).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. attendance_view — attendance joined with staff name/branch/role
--    (lib/salary_page, expects: id, staff_id, attendance_date, status,
--     location_branch, marked_by, note, staff_name, staff_branch, staff_role)
-- ---------------------------------------------------------------------------
-- DROP-FIRST (added 2026-07-19): some of these views already exist in the
-- live DB from an earlier partial run, and CREATE OR REPLACE VIEW cannot
-- change an existing column's type (42P16 on reminders_view.due_date).
-- Dropping first makes the whole file freely re-runnable.
drop view if exists public.dashboard_kpis_view;
drop view if exists public.branch_kpis_view;
drop view if exists public.reminders_view;
drop view if exists public.trips_view;
drop view if exists public.advances_view;
drop view if exists public.attendance_view;

create or replace view public.attendance_view as
select
  a.id,
  a.org_id,
  a.staff_id,
  a.attendance_date,
  a.status,
  a.branch as location_branch,
  a.marked_by,
  a.note,
  s.name as staff_name,
  s.branch as staff_branch,
  s.role as staff_role
from public.attendance a
left join public.staff s on s.id::text = a.staff_id::text;

-- ---------------------------------------------------------------------------
-- 2. advances_view — staff_advances joined with staff name/branch/role
--    (lib/salary_page, expects: id, staff_id, amount, advance_date, status,
--     balance, note, staff_name, staff_branch, staff_role)
-- ---------------------------------------------------------------------------
create or replace view public.advances_view as
select
  sa.id,
  sa.org_id,
  sa.staff_id,
  sa.amount,
  sa.advance_date,
  sa.status,
  sa.balance,
  sa.note,
  s.name as staff_name,
  s.branch as staff_branch,
  s.role as staff_role
from public.staff_advances sa
left join public.staff s on s.id::text = sa.staff_id::text;

-- ---------------------------------------------------------------------------
-- 3. trips_view — vehicle_trips joined with the order's customer name
--    (lib/operations_page, expects: id, order_id, vehicle_no, driver_name,
--     from_loc, to_loc, km_start, km_end, fuel_amount, toll_amount,
--     driver_bata, trip_date, trip_type, note, order_customer)
-- ---------------------------------------------------------------------------
create or replace view public.trips_view as
select
  vt.id,
  vt.org_id,
  vt.order_id,
  vt.vehicle_no,
  vt.driver_name,
  vt.from_loc,
  vt.to_loc,
  vt.km_start,
  vt.km_end,
  vt.fuel_amount,
  vt.toll_amount,
  vt.driver_bata,
  vt.trip_date,
  vt.trip_type,
  vt.note,
  o.customer as order_customer
from public.vehicle_trips vt
left join public.orders o on o.id::text = vt.order_id::text;

-- ---------------------------------------------------------------------------
-- 4. reminders_view — reminders joined with lead/order customer name
--    (lib/calendar_page, expects: id, lead_id, order_id, title, description,
--     reminder_type, due_date, done, created_by, lead_customer, order_customer)
--    Base `reminders` table has both `completed` and `done` booleans in the
--    generated model — using `done` since that's what the view is expected
--    to expose; if the real column is only `completed`, alias it as done.
-- ---------------------------------------------------------------------------
create or replace view public.reminders_view as
select
  r.id,
  r.org_id,
  r.lead_id,
  r.order_id,
  r.title,
  r.description,
  r.reminder_type,
  r.due_date::text as due_date,
  coalesce(r.done, r.completed) as done,
  r.created_by,
  l.customer as lead_customer,
  o.customer as order_customer
from public.reminders r
left join public.leads l on l.id::text = r.lead_id::text
left join public.orders o on o.id::text = r.order_id::text;

-- ---------------------------------------------------------------------------
-- 5. branch_kpis_view — revenue/orders/outstanding/profit per branch
--    (lib/home_page dashboard "branch performance", expects: id, branch,
--     revenue, order_count, outstanding, net_profit)
-- ---------------------------------------------------------------------------
create or replace view public.branch_kpis_view as
select
  o.branch || ':' || coalesce(o.org_id::text, 'null') as id,
  o.org_id,
  o.branch,
  coalesce(sum(o.amount) filter (
    where date_trunc('month', o.created_at) = date_trunc('month', now())
  ), 0) as revenue,
  count(*) filter (
    where date_trunc('month', o.created_at) = date_trunc('month', now())
  ) as order_count,
  coalesce(sum(o.amount - coalesce(o.advance_paid, 0)) filter (
    where o.payment_status is distinct from 'paid'
  ), 0) as outstanding,
  coalesce(sum(o.amount) filter (
    where date_trunc('month', o.created_at) = date_trunc('month', now())
  ), 0)
    - coalesce(sum(
        case when o.is_porter then
          o.porter_cash_collect * coalesce(o.porter_commission_pct, 0) / 100.0
        else 0 end
      ) filter (
        where date_trunc('month', o.created_at) = date_trunc('month', now())
      ), 0) as net_profit
from public.orders o
where o.branch is not null
group by o.branch, o.org_id;

-- ---------------------------------------------------------------------------
-- 6. dashboard_kpis_view — single-row summary for the HomePage dashboard
--    (expects: id, revenue_this_month, labour_this_month, expenses_this_month,
--     porter_comm_this_month, net_profit_this_month, active_leads,
--     orders_this_month, outstanding_amount, reminders_today)
-- ---------------------------------------------------------------------------
-- Now grouped per org_id (one row per org, was one global row) so the app
-- can `.eq('org_id', currentOrgId)` instead of reading data from every
-- tenant. Built with `union all` per source org set (orgs that have at
-- least one row in orders/staff/expenses/leads/reminders) rather than a
-- cross join, to keep it simple and avoid a full `organizations` scan.
create or replace view public.dashboard_kpis_view as
with org_ids as (
  select distinct org_id from public.orders where org_id is not null
  union
  select distinct org_id from public.staff where org_id is not null
  union
  select distinct org_id from public.expenses where org_id is not null
  union
  select distinct org_id from public.leads where org_id is not null
),
month_orders as (
  select *
  from public.orders
  where date_trunc('month', created_at) = date_trunc('month', now())
),
revenue as (
  select org_id, coalesce(sum(amount), 0) as v
  from month_orders group by org_id
),
labour as (
  select org_id, coalesce(sum(salary), 0) as v
  from public.staff
  where active is distinct from false
  group by org_id
),
expenses as (
  select org_id, coalesce(sum(amount), 0) as v
  from public.expenses
  where date_trunc('month', coalesce(expense_date, created_at)) = date_trunc('month', now())
  group by org_id
),
porter_comm as (
  select org_id, coalesce(sum(
    porter_cash_collect * coalesce(porter_commission_pct, 0) / 100.0
  ), 0) as v
  from month_orders
  where is_porter is true
  group by org_id
),
active_leads as (
  select org_id, count(*) as v
  from public.leads
  where status not in ('won', 'lost', 'closed')
     or status is null
  group by org_id
),
orders_count as (
  select org_id, count(*) as v from month_orders group by org_id
),
outstanding as (
  select org_id, coalesce(sum(amount - coalesce(advance_paid, 0)), 0) as v
  from public.orders
  where payment_status is distinct from 'paid'
  group by org_id
),
reminders_today as (
  select org_id, count(*) as v
  from public.reminders
  where due_date::date = current_date
    and coalesce(done, completed, false) is not true
  group by org_id
)
select
  oi.org_id::text as id,
  oi.org_id,
  coalesce(revenue.v, 0) as revenue_this_month,
  coalesce(labour.v, 0) as labour_this_month,
  coalesce(expenses.v, 0) as expenses_this_month,
  coalesce(porter_comm.v, 0) as porter_comm_this_month,
  (coalesce(revenue.v, 0) - coalesce(labour.v, 0) - coalesce(expenses.v, 0) - coalesce(porter_comm.v, 0)) as net_profit_this_month,
  coalesce(active_leads.v, 0) as active_leads,
  coalesce(orders_count.v, 0) as orders_this_month,
  coalesce(outstanding.v, 0) as outstanding_amount,
  coalesce(reminders_today.v, 0) as reminders_today
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
-- After running: reload the app. If a view errors with "column does not
-- exist", that means the live table doesn't have a column this SQL assumed
-- (most likely candidates: leads.status values, reminders.done vs
-- .completed, or expenses.expense_date vs .date) — paste the error and the
-- information_schema output above and it can be corrected.
-- ============================================================================
