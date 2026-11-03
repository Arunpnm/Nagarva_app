-- BUG-045 (full test, 1 Nov 2026): Trip P&L counted each order's GROSS
-- amount as trip revenue — GST included, and Porter's commission not taken
-- off. Order 1002 (Porter, ₹25,000, 20% commission) showed ₹25,000
-- revenue on its trip; the vendor's real share is ₹20,000.
--
-- Revenue per order on a trip, now:
--     order_taxable_value(order)                -- before GST, incl. extras
--   − commission (taxable × commission_pct/100, only when commission is due)
--   × allocation_pct / 100                      -- the order's share of the
--                                                  trip (100 when not set)
-- order_taxable_value() comes from 20261103_payment_status_uses_order_total.
--
-- Same columns, same order, same security_invoker — the app needs no change.
-- NOT APPLIED — Arun runs this.

begin;

create or replace view public.trip_pnl_view
with (security_invoker = on) as
with rev as (
  select tord.trip_id,
         count(distinct tord.order_id) as order_count,
         coalesce(sum(
           (public.order_taxable_value(o.id)
             - case when coalesce(o.commission_expected, false)
                    then public.order_taxable_value(o.id)
                         * coalesce(o.commission_pct, 0) / 100
                    else 0 end)
           * coalesce(nullif(tord.allocation_pct, 0), 100) / 100
         ), 0) as revenue
    from public.trip_orders tord
    left join public.orders o
      on o.id = tord.order_id and o.deleted_at is null
   group by tord.trip_id
)
select t.org_id,
       t.id as trip_id,
       t.trip_no,
       t.trip_type,
       t.vehicle_no,
       t.start_date,
       t.total_km,
       coalesce(rev.order_count, 0) as order_count,
       round(coalesce(rev.revenue, 0), 2) as gross_revenue,
       coalesce(te.total_expenses, 0::numeric) as trip_expenses,
       t.hire_amount,
       round(coalesce(rev.revenue, 0), 2)
         - coalesce(te.total_expenses, 0::numeric)
         - coalesce(t.hire_amount, 0::numeric) as net_profit,
       case when t.total_km > 0
            then round(coalesce(te.total_expenses, 0::numeric) / t.total_km::numeric, 2)
            else 0::numeric end as cost_per_km
  from public.trips t
  left join rev on rev.trip_id = t.id
  left join lateral (
    select sum(x.amount) as total_expenses
      from public.trip_expenses x
     where x.trip_id = t.id
  ) te on true
 where t.deleted_at is null;

commit;

-- Check: select trip_no, gross_revenue, trip_expenses, net_profit
--          from trip_pnl_view where trip_no = 'TEST-TRIP-001';
-- → revenue 20000 (was 25000), expenses 970, profit 19030 (previewed
--   read-only on 3 Nov before running).
