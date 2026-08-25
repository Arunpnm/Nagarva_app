-- =====================================================================
-- 20260825_dashboard_kpis_quotes_and_active_moves.sql
--
-- Adds two columns to dashboard_kpis_view for Phase 1 of the dashboard
-- redesign:
--     quotes_this_month  — Quotes tile
--     active_moves       — Active Moves tile
--
-- =====================================================================
-- ⚠️  security_invoker LIVES IN reloptions AND IS EASY TO LOSE
-- =====================================================================
-- CREATE OR REPLACE VIEW **preserves** reloptions.
-- DROP VIEW + CREATE VIEW **silently discards** them, reverting the view
-- to owner rights — no error, no warning, and no test failure, because
-- the columns and the data all still look right. The only symptom is
-- that every tenant's numbers become readable again with the anon key.
--
-- CREATE OR REPLACE can only APPEND columns at the end and cannot rename
-- or retype existing ones, which creates real pressure to just drop and
-- recreate. Do not. Both new columns are appended after
-- `reminders_today` precisely so replace-in-place remains possible.
--
-- Belt and braces: this migration ALSO issues an explicit
-- ALTER VIEW ... SET (security_invoker = on) afterwards, so the flag is
-- correct even if some future edit does drop and recreate. POSTFLIGHT
-- then asserts it rather than assuming it.
--
-- Verify by BEHAVIOUR, not by the flag: as anon,
--     select count(*) from public.dashboard_kpis_view;   -- expect 0
-- A flag that is set but untested proves the catalogue, not the wiring.
-- =====================================================================
--
-- ACTIVE MOVES — inclusion list, never exclusion.
-- Live vocabulary (non-deleted orders, verified 25 Aug 2026):
--     delivered 17 · transit 2 · closed 2 · booked 2 · confirmed 1
--     · cancelled 1
-- Active = booked + confirmed + transit = 5.
--
-- Counting `transit` alone gives 2 and understates by 60%; that is the
-- bug this column exists to avoid. An exclusion list (`status not in
-- ('delivered','closed','cancelled')`) would silently absorb every
-- status added later into "active", which is the worse failure because
-- it grows quietly. Anything new must be added here deliberately.
--
-- NOT month-scoped, unlike orders_this_month: a job booked last month
-- and still in transit is active NOW. That is the question the tile
-- answers.
--
-- Hand-run by Arun. Not executed by an agent.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- PREFLIGHT
-- ---------------------------------------------------------------------
do $$
declare v_opts text;
begin
  if to_regclass('public.dashboard_kpis_view') is null then
    raise exception 'PREFLIGHT: dashboard_kpis_view does not exist.';
  end if;

  -- Must already be invoker-rights. If it is not, the previous security
  -- migration was reverted and THAT is the thing to fix first — do not
  -- quietly paper over it here.
  select array_to_string(reloptions, ',') into v_opts
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'dashboard_kpis_view';

  if coalesce(v_opts, '') !~* 'security_invoker=(on|true)' then
    raise exception
      'PREFLIGHT: dashboard_kpis_view is NOT running with invoker rights '
      '(reloptions=%). The cross-tenant leak is open; run '
      '20260825_view_security_invoker.sql first.', coalesce(v_opts, 'null');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- CREATE OR REPLACE — append-only, so reloptions survive.
-- ---------------------------------------------------------------------
create or replace view public.dashboard_kpis_view as
with org_ids as (
  select distinct org_id from orders     where org_id is not null and deleted_at is null
  union
  select distinct org_id from staff      where org_id is not null
  union
  select distinct org_id from public.expenses where org_id is not null and deleted_at is null
  union
  select distinct org_id from leads      where org_id is not null and deleted_at is null
  union
  -- Added with this migration so an org whose only activity is quoting
  -- still gets a row (otherwise its Quotes tile would render nothing at
  -- all rather than a count).
  select distinct org_id from quotations where org_id is not null
),
month_orders as (
  select *
  from orders
  where date_trunc('month', created_at) = date_trunc('month', now())
    and deleted_at is null
),
revenue as (
  select org_id, coalesce(sum(amount), 0::numeric) as v
  from month_orders group by org_id
),
labour as (
  select org_id, coalesce(sum(salary), 0::numeric) as v
  from staff where active is distinct from false group by org_id
),
expenses as (
  select org_id, coalesce(sum(amount), 0::numeric) as v
  from public.expenses
  where date_trunc('month', coalesce(expense_date::timestamptz, created_at))
        = date_trunc('month', now())
    and deleted_at is null
  group by org_id
),
porter_comm as (
  select org_id,
         coalesce(sum(porter_cash_collect
                      * coalesce(porter_commission_pct, 0::numeric) / 100.0),
                  0::numeric) as v
  from month_orders where is_porter is true group by org_id
),
active_leads as (
  select org_id, count(*) as v
  from leads
  where (status <> all (array['won','lost','closed']) or status is null)
    and deleted_at is null
  group by org_id
),
orders_count as (
  select org_id, count(*) as v from month_orders group by org_id
),
outstanding as (
  select org_id,
         coalesce(sum(amount - coalesce(advance_paid, 0::numeric)), 0::numeric) as v
  from orders
  where payment_status is distinct from 'paid' and deleted_at is null
  group by org_id
),
reminders_today as (
  select org_id, count(*) as v
  from reminders
  where due_date = current_date
    and coalesce(done, completed, false) is not true
  group by org_id
),
-- ---- new ----------------------------------------------------------
quotes_month as (
  select org_id, count(*) as v
  from quotations
  where date_trunc('month', created_at) = date_trunc('month', now())
    and deleted_at is null
  group by org_id
),
active_moves as (
  select org_id, count(*) as v
  from orders
  where deleted_at is null
    and status in ('booked', 'confirmed', 'transit')  -- INCLUSION LIST
  group by org_id
)
select
  oi.org_id::text                                     as id,
  oi.org_id,
  coalesce(revenue.v, 0::numeric)                     as revenue_this_month,
  coalesce(labour.v, 0::numeric)                      as labour_this_month,
  coalesce(expenses.v, 0::numeric)                    as expenses_this_month,
  coalesce(porter_comm.v, 0::numeric)                 as porter_comm_this_month,
  coalesce(revenue.v, 0::numeric)
    - coalesce(labour.v, 0::numeric)
    - coalesce(expenses.v, 0::numeric)
    - coalesce(porter_comm.v, 0::numeric)             as net_profit_this_month,
  coalesce(active_leads.v, 0::bigint)                 as active_leads,
  coalesce(orders_count.v, 0::bigint)                 as orders_this_month,
  coalesce(outstanding.v, 0::numeric)                 as outstanding_amount,
  coalesce(reminders_today.v, 0::bigint)              as reminders_today,
  -- New columns MUST stay last; see the header.
  coalesce(quotes_month.v, 0::bigint)                 as quotes_this_month,
  coalesce(active_moves.v, 0::bigint)                 as active_moves
from org_ids oi
  left join revenue         on revenue.org_id         = oi.org_id
  left join labour          on labour.org_id          = oi.org_id
  left join expenses        on expenses.org_id        = oi.org_id
  left join porter_comm     on porter_comm.org_id     = oi.org_id
  left join active_leads    on active_leads.org_id    = oi.org_id
  left join orders_count    on orders_count.org_id    = oi.org_id
  left join outstanding     on outstanding.org_id     = oi.org_id
  left join reminders_today on reminders_today.org_id = oi.org_id
  left join quotes_month    on quotes_month.org_id    = oi.org_id
  left join active_moves    on active_moves.org_id    = oi.org_id;

-- Explicit, even though CREATE OR REPLACE preserves it. Cheap, and it
-- makes the guarantee independent of how this view is next edited.
alter view public.dashboard_kpis_view set (security_invoker = on);

-- ---------------------------------------------------------------------
-- POSTFLIGHT
-- ---------------------------------------------------------------------
do $$
declare v_opts text; v_missing text;
begin
  select array_to_string(reloptions, ',') into v_opts
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'dashboard_kpis_view';

  if coalesce(v_opts, '') !~* 'security_invoker=(on|true)' then
    raise exception
      'POSTFLIGHT: dashboard_kpis_view lost invoker rights (reloptions=%). '
      'The cross-tenant leak is OPEN.', coalesce(v_opts, 'null');
  end if;

  select string_agg(c, ', ') into v_missing
  from unnest(array['quotes_this_month','active_moves']) as c
  where not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'dashboard_kpis_view'
      and column_name = c
  );
  if v_missing is not null then
    raise exception 'POSTFLIGHT: column(s) missing: %', v_missing;
  end if;

  raise notice
    'POSTFLIGHT OK: quotes_this_month + active_moves added, invoker rights intact.';
end $$;

commit;

-- =====================================================================
-- VERIFY AFTER RUNNING
--
-- 1. Behavioural, as anon — the check that matters:
--      select count(*) from public.dashboard_kpis_view;   -- expect 0
--
-- 2. As the owner session, sanity-check the two new numbers against
--    the raw tables:
--      select active_moves, quotes_this_month
--        from public.dashboard_kpis_view;
--
--    Expected for APC today: active_moves = 5
--    (booked 2 + confirmed 1 + transit 2). If it reads 2, something
--    reverted the inclusion list to `transit` alone.
-- =====================================================================
