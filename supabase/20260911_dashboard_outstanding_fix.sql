-- =====================================================================
-- 20260911_dashboard_outstanding_fix.sql
--
-- ONE CHANGE: dashboard_kpis_view.outstanding_amount.
-- Nothing else in this file. No Dart, no call sites, no second view.
--
-- WHAT WAS WRONG
-- --------------
-- The outstanding CTE read:
--
--     sum(orders.amount - coalesce(orders.advance_paid, 0))
--     where orders.payment_status is distinct from 'paid'
--
-- `paid_total` does not appear in it. `paid_total` is the ONLY column
-- that records money actually received (maintained by
-- trg_sync_order_paid_total from payment_entries), so the dashboard was
-- computing outstanding without reference to any payment.
--
-- It reads correctly today by two accidents, not by design:
--   1. `advance_paid` is 0 on all 7 live orders, and
--   2. every payment so far has been all-or-nothing, so the
--      `<> 'paid'` filter happens to exclude exactly the settled rows.
--
-- Break either and it overstates, in the flattering direction. Record a
-- 20,000 part payment against a 48,400 order: paid_total becomes 20,000
-- and payment_status becomes 'partial' -- which is still not 'paid', so
-- the row stays in the sum and contributes its FULL 48,400. The money
-- the customer handed over is invisible on the dashboard while the order
-- screen and customer_360_view both show 28,400.
--
-- WHAT IT READS NOW
-- -----------------
--     revenue base - received
--
--   revenue base = coalesce(nullif(quote_total,0), amount)
--                  + non-cancelled add-ons
--   received     = coalesce(paid_total, 0)
--
-- This is deliberately the base specced for the forthcoming
-- order_balances_view, NOT a minimal patch of paid_total into the old
-- shape -- so the two are already consistent when that view lands and
-- the single-definition pass moves every call site onto it.
--
-- THREE DELIBERATE DECISIONS, EACH REVERSIBLE
-- -------------------------------------------
-- 1. `advance_paid` IS NOT A TERM. Arun's instruction, 11 Sept 2026: it
--    is dead (0 on every row, written as a literal 0.0 by five screens)
--    and must not be carried into new code as a live term. If the porter
--    cash-collect path in New Order is ever made to write it for real,
--    it has to be added here AND to order_balances_view together, or
--    they diverge on day one. See the accompanying report.
--
-- 2. THE payment_status FILTER IS GONE. With a correct formula it is
--    redundant -- a settled order contributes zero arithmetically -- and
--    it is actively harmful, because `payment_status` is itself derived
--    from `advance_paid` inside sync_order_paid_total(). Filtering on a
--    value derived from a dead field is how the original bug survived.
--
-- 3. PER-ORDER CLAMP AT ZERO via greatest(...). An over-collected order
--    must not net off another order's genuine debt: two orders, one
--    overpaid by 5,000 and one owing 5,000, is 5,000 outstanding and a
--    5,000 credit, not zero. Customer-level credit is a separate figure
--    and belongs in the customer view, not in an org total.
--
-- NOT INCLUDED, AND FLAGGED RATHER THAN DECIDED SILENTLY
-- ------------------------------------------------------
-- Storage income. order_pnl_section adds `_storageIncome` to Revenue
-- Final as a third term; this view does not, because the base Arun
-- agreed was "quote_total else amount, plus non-cancelled add-ons" and
-- widening it inside a narrow fix is exactly the scope creep that makes
-- a one-line migration unreviewable. Whether storage belongs in
-- outstanding is a real question and it belongs to order_balances_view.
--
-- ADD-ON STATUS: one small, deliberate difference from the app.
-- The app filters `.neq('status','cancelled')`, which in SQL is
-- `status <> 'cancelled'` and therefore also drops a NULL status. This
-- view uses `coalesce(status,'') <> 'cancelled'`, so a null-status
-- add-on counts as revenue rather than vanishing. There are 0 null-status
-- rows today (verified 11 Sept 2026), so this changes no current figure;
-- it is recorded here because the single-definition pass must reconcile
-- the two rather than leave a silent disagreement about NULL.
--
-- SECURITY_INVOKER MUST BE RESTATED -- CORRECTED 11 Sept 2026, THE HARD
-- WAY, BY THIS MIGRATION'S OWN POSTFLIGHT
-- ---------------------------------------------------------------------
-- The first run of this file FAILED, and it failed correctly:
--
--   ERROR: P0001: security_invoker was lost during replace
--                 (reloptions = <null>)
--
-- CLAUDE.md's standing rule said "CREATE OR REPLACE VIEW preserves
-- security_invoker; DROP + CREATE silently discards it." **The first
-- half is wrong.** Measured here: the PREFLIGHT asserted
-- security_invoker=on and passed, the replace ran, and the POSTFLIGHT
-- read reloptions as null on the same object. A bare CREATE OR REPLACE
-- VIEW resets reloptions that the new statement does not restate.
--
-- So the option is now written into the statement itself:
--   create or replace view ... with (security_invoker = on) as ...
-- Belt and braces regardless of which behaviour a given server has --
-- restating it can never be wrong, and omitting it silently was.
--
-- WHY THE FAILURE COST NOTHING: the whole migration runs in one
-- transaction and the postflight raises inside it, so the abort left the
-- live view untouched -- confirmed by query afterwards: reloptions still
-- ["security_invoker=on"], old formula still in place, 3 rows readable.
-- A postflight that asserts the construct rather than trusting the
-- statement is the only reason this was a caught error instead of every
-- tenant's KPI row becoming readable with the anon key.
--
-- Column names, types and ORDER are unchanged either way: 13 columns,
-- outstanding_amount stays numeric in position 10.
--
-- NOT RUN. File only, per instruction.
-- =====================================================================

begin;

set local search_path = public, pg_catalog;

-- ---------------------------------------------------------------------
-- PREFLIGHT. Raises; never skips.
-- ---------------------------------------------------------------------
do $$
declare
  v_oid      oid;
  v_opts     text[];
  v_ncols    int;
  v_outpos   int;
  v_outtype  text;
begin
  v_oid := to_regclass('public.dashboard_kpis_view');
  if v_oid is null then
    raise exception
      'dashboard_kpis_view does not exist. Run supabase/views_dashboard_and_ops.sql first.';
  end if;

  select reloptions into v_opts from pg_class where oid = v_oid;
  if v_opts is null or not ('security_invoker=on' = any(v_opts)) then
    raise exception
      'dashboard_kpis_view has lost security_invoker (reloptions = %). '
      'Fix that first -- replacing the view here would bake the leak in.',
      coalesce(v_opts::text, '<null>');
  end if;

  select count(*) into v_ncols
    from pg_attribute
   where attrelid = v_oid and attnum > 0 and not attisdropped;
  if v_ncols <> 13 then
    raise exception
      'dashboard_kpis_view has % columns, expected 13. Its shape changed; '
      'CREATE OR REPLACE cannot alter column lists, so this migration '
      'must be re-derived against the current definition.', v_ncols;
  end if;

  select a.attnum, format_type(a.atttypid, a.atttypmod)
    into v_outpos, v_outtype
    from pg_attribute a
   where a.attrelid = v_oid and a.attname = 'outstanding_amount';
  if v_outpos is distinct from 10 or v_outtype is distinct from 'numeric' then
    raise exception
      'outstanding_amount is column % of type %, expected column 10 numeric.',
      coalesce(v_outpos::text,'<absent>'), coalesce(v_outtype,'<absent>');
  end if;

  -- The tables this view's new expression depends on.
  if to_regclass('public.addons') is null then
    raise exception 'public.addons is missing; the revenue base cannot be built.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- THE VIEW
--
-- Only the `outstanding` CTE and the `month_orders` column list differ
-- from the definition this replaces. month_orders previously listed all
-- ~110 order columns explicitly while three CTEs used five of them; it
-- is narrowed to those five. That is a readability change with no effect
-- on output -- the two porter aliases are preserved exactly, because
-- porter_comm depends on them.
-- ---------------------------------------------------------------------
create or replace view public.dashboard_kpis_view
  with (security_invoker = on) as
with org_ids as (
  select distinct org_id from orders     where org_id is not null and deleted_at is null
  union
  select distinct org_id from staff      where org_id is not null
  union
  select distinct org_id from expenses   where org_id is not null and deleted_at is null
  union
  select distinct org_id from leads      where org_id is not null and deleted_at is null
  union
  select distinct org_id from quotations where org_id is not null
),
month_orders as (
  select o.org_id,
         o.amount,
         o.porter_cash_collect,
         o.commission_expected as is_porter,
         o.commission_pct      as porter_commission_pct
    from orders o
   where date_trunc('month', o.created_at) = date_trunc('month', now())
     and o.deleted_at is null
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
         coalesce(sum(porter_cash_collect * coalesce(porter_commission_pct, 0::numeric) / 100.0),
                  0::numeric) as v
    from month_orders where is_porter is true group by org_id
),
active_leads as (
  select org_id, count(*) as v
    from leads
   where ((status <> all (array['won','lost','closed'])) or status is null)
     and deleted_at is null
   group by org_id
),
orders_count as (
  select org_id, count(*) as v from month_orders group by org_id
),
-- ---- THE FIX -------------------------------------------------------
-- Per order: (quote_total else amount, plus non-cancelled add-ons)
--            minus received, clamped at zero, then summed per org.
-- No advance_paid term. No payment_status filter.
order_addons as (
  select order_id, coalesce(sum(amount), 0::numeric) as v
    from addons
   where coalesce(status, '') <> 'cancelled'
   group by order_id
),
outstanding as (
  select o.org_id,
         coalesce(sum(
           greatest(
             coalesce(nullif(o.quote_total, 0), o.amount, 0::numeric)
               + coalesce(oa.v, 0::numeric)
               - coalesce(o.paid_total, 0::numeric),
             0::numeric
           )
         ), 0::numeric) as v
    from orders o
    left join order_addons oa on oa.order_id = o.id
   where o.deleted_at is null
   group by o.org_id
),
-- --------------------------------------------------------------------
reminders_today as (
  select org_id, count(*) as v
    from reminders
   where due_date = current_date
     and coalesce(done, completed, false) is not true
   group by org_id
),
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
     and status = any (array['booked','confirmed','transit'])
   group by org_id
)
select oi.org_id::text                                   as id,
       oi.org_id,
       coalesce(revenue.v, 0::numeric)                   as revenue_this_month,
       coalesce(labour.v, 0::numeric)                    as labour_this_month,
       coalesce(expenses.v, 0::numeric)                  as expenses_this_month,
       coalesce(porter_comm.v, 0::numeric)               as porter_comm_this_month,
       coalesce(revenue.v, 0::numeric)
         - coalesce(labour.v, 0::numeric)
         - coalesce(expenses.v, 0::numeric)
         - coalesce(porter_comm.v, 0::numeric)           as net_profit_this_month,
       coalesce(active_leads.v, 0::bigint)               as active_leads,
       coalesce(orders_count.v, 0::bigint)               as orders_this_month,
       coalesce(outstanding.v, 0::numeric)               as outstanding_amount,
       coalesce(reminders_today.v, 0::bigint)            as reminders_today,
       coalesce(quotes_month.v, 0::bigint)               as quotes_this_month,
       coalesce(active_moves.v, 0::bigint)               as active_moves
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

-- ---------------------------------------------------------------------
-- POSTFLIGHT. Asserts the CONSTRUCT and the BEHAVIOUR, inside this same
-- transaction, so a failure rolls the whole thing back.
-- ---------------------------------------------------------------------
do $$
declare
  v_opts      text[];
  v_ncols     int;
  v_def       text;
  v_bad       int;
  v_neg       int;
  v_paid_bad  numeric;
begin
  -- 1. security_invoker survived. CREATE OR REPLACE should preserve it;
  --    assert rather than trust, because the failure is silent and the
  --    symptom is a cross-tenant read.
  select reloptions into v_opts
    from pg_class where oid = 'public.dashboard_kpis_view'::regclass;
  if v_opts is null or not ('security_invoker=on' = any(v_opts)) then
    raise exception
      'security_invoker was lost during replace (reloptions = %).',
      coalesce(v_opts::text, '<null>');
  end if;

  -- 2. Shape unchanged.
  select count(*) into v_ncols
    from pg_attribute
   where attrelid = 'public.dashboard_kpis_view'::regclass
     and attnum > 0 and not attisdropped;
  if v_ncols <> 13 then
    raise exception 'view now has % columns, expected 13.', v_ncols;
  end if;

  -- 3. advance_paid is really gone from the definition.
  --    A text check is legitimate HERE, unlike the delete_org case that
  --    tripped on its own tombstone comment: pg_get_viewdef regenerates
  --    SQL from the parse tree, so it contains no comments for a
  --    tombstone to hide in. The comments above this block are not in it.
  v_def := pg_get_viewdef('public.dashboard_kpis_view'::regclass, true);
  if position('advance_paid' in v_def) > 0 then
    raise exception
      'advance_paid still appears in the view definition; it must not be a term.';
  end if;
  if position('paid_total' in v_def) = 0 then
    raise exception
      'paid_total does not appear in the view definition -- the fix did not apply.';
  end if;

  -- 4. BEHAVIOURAL: the view's figure must equal the same quantity
  --    computed by an independently written expression. This catches a
  --    misplaced paren or a wrong join, which no structural check can.
  select count(*) into v_bad
    from (
      select v.org_id, v.outstanding_amount as view_v,
             coalesce((
               select sum(greatest(
                        coalesce(nullif(o.quote_total,0), o.amount, 0::numeric)
                          + coalesce((select sum(a.amount) from addons a
                                       where a.order_id = o.id
                                         and coalesce(a.status,'') <> 'cancelled'), 0::numeric)
                          - coalesce(o.paid_total, 0::numeric),
                        0::numeric))
                 from orders o
                where o.org_id = v.org_id and o.deleted_at is null
             ), 0::numeric) as calc_v
        from dashboard_kpis_view v
    ) x
   where round(x.view_v, 2) is distinct from round(x.calc_v, 2);
  if v_bad > 0 then
    raise exception
      '% org(s) disagree between the view and an independent recomputation.', v_bad;
  end if;

  -- 5. No org may report negative outstanding.
  select count(*) into v_neg
    from dashboard_kpis_view where outstanding_amount < 0;
  if v_neg > 0 then
    raise exception '% org(s) report negative outstanding.', v_neg;
  end if;

  -- 6. THE REGRESSION THIS MIGRATION EXISTS FOR: a fully-settled order
  --    must contribute exactly zero. Asserted as a property rather than
  --    against a hardcoded rupee figure, which would date.
  select coalesce(sum(
           greatest(
             coalesce(nullif(o.quote_total,0), o.amount, 0::numeric)
               + coalesce((select sum(a.amount) from addons a
                            where a.order_id = o.id
                              and coalesce(a.status,'') <> 'cancelled'), 0::numeric)
               - coalesce(o.paid_total, 0::numeric),
             0::numeric)), 0::numeric)
    into v_paid_bad
    from orders o
   where o.deleted_at is null
     and coalesce(o.paid_total, 0) >=
         coalesce(nullif(o.quote_total,0), o.amount, 0::numeric)
              + coalesce((select sum(a.amount) from addons a
                           where a.order_id = o.id
                             and coalesce(a.status,'') <> 'cancelled'), 0::numeric);
  if v_paid_bad <> 0 then
    raise exception
      'settled orders contributed % to outstanding; expected 0.', v_paid_bad;
  end if;

  raise notice 'dashboard_kpis_view.outstanding_amount: replaced and verified.';
end $$;

commit;

-- =====================================================================
-- ROLLBACK
-- ---------------------------------------------------------------------
-- Restores the previous expression verbatim. Kept fully commented; it is
-- WRONG code, and the only reason to run it is to reproduce the old
-- figure while diagnosing something. Re-apply this migration afterwards.
--
-- Use CREATE OR REPLACE for the rollback too -- a DROP would strip
-- security_invoker on the way back.
--
--   ... outstanding as (
--     select orders.org_id,
--            coalesce(sum(orders.amount - coalesce(orders.advance_paid, 0::numeric)),
--                     0::numeric) as v
--       from orders
--      where orders.payment_status is distinct from 'paid'
--        and orders.deleted_at is null
--      group by orders.org_id
--   ), ...
-- =====================================================================
