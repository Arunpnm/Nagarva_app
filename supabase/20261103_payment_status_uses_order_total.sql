-- 3 Nov 2026 — full-test BUG-036 / BUG-044 (overnight fix run).
-- NOT APPLIED. Arun applies migrations himself.
--
-- payment_status ('paid' / 'partial' / 'pending') compared payments with
-- orders.amount only. So:
--   * an order with extra charges (addons) was marked 'paid' while the
--     extras were still owed (order 1001: ₹1,400 owed, status 'paid'), and
--     dropped out of Payments / Record Payment;
--   * a directly-booked GST order (GST on top, e.g. 1002: 25,000 + 4,500)
--     was 'paid' at 25,000.
--
-- This mirrors lib/backend/order_money.dart exactly (Arun's rule, 2 Nov):
--   base  = amount − quote_gst_amount  when the order came from a quote whose
--           total already includes GST (amount = quote_total and
--           quote_subtotal + gst = quote_total); otherwise base = amount
--   total = base + gst + Σ non-cancelled addons + GST on addons (same rate,
--           only when the order is GST-billed)
-- and re-syncs when payments OR addons change.

begin;

create or replace function public.order_total_due(p_order_id text)
returns numeric
language sql
stable
as $fn$
  with o as (
    select coalesce(amount, 0)            as amount,
           coalesce(quote_gst_amount, 0)  as gst,
           coalesce(quote_gst_pct, 0)     as pct,
           quote_total, quote_subtotal
      from public.orders where id = p_order_id
  ), a as (
    select coalesce(sum(amount), 0) as extras
      from public.addons
     where order_id = p_order_id
       and coalesce(lower(status), '') <> 'cancelled'
  )
  select
    (case when o.gst > 0
               and o.quote_total is not null
               and abs(o.quote_total - o.amount) < 1
               and (o.quote_subtotal is null
                    or abs((o.quote_subtotal + o.gst) - o.quote_total) < 1)
          then o.amount - o.gst
          else o.amount end)
    + o.gst
    + a.extras
    + case when o.gst > 0 then round(a.extras * o.pct / 100) else 0 end
  from o, a;
$fn$;

create or replace function public.sync_order_paid_total()
returns trigger
language plpgsql
as $fn$
declare
  v_order_id text;
  v_paid numeric;
  v_total numeric;
begin
  v_order_id := coalesce(new.order_id, old.order_id);

  select coalesce(sum(amount), 0) into v_paid
    from payment_entries
   where order_id = v_order_id
     and deleted_at is null;

  v_total := coalesce(public.order_total_due(v_order_id), 0);

  update orders set
    paid_total = v_paid,
    payment_status = case
      when v_total > 0 and v_paid >= v_total then 'paid'
      when v_paid > 0 then 'partial'
      else 'pending'
    end
  where id = v_order_id;

  return coalesce(new, old);
end
$fn$;

-- Taxable value and GST of an order under the same rule (for GST views).
create or replace function public.order_taxable_value(p_order_id text)
returns numeric
language sql
stable
as $fn$
  select public.order_total_due(p_order_id)
         - coalesce((select quote_gst_amount from public.orders where id = p_order_id), 0)
         - coalesce((select case when coalesce(o.quote_gst_amount,0) > 0
                                 then round(coalesce(sum(a.amount),0) * coalesce(o.quote_gst_pct,0) / 100)
                                 else 0 end
                       from public.orders o
                       left join public.addons a
                         on a.order_id = o.id and coalesce(lower(a.status),'') <> 'cancelled'
                      where o.id = p_order_id
                      group by o.quote_gst_amount, o.quote_gst_pct), 0);
$fn$;

-- GSTR-1 views (BUG-044): read quote_subtotal (null on directly-booked
-- orders) and treated a null quote_gst_mode as "no tax" — order 1002's
-- ₹4,500 GST showed as 0 and its taxable value as null. Now: taxable and
-- tax from the shared rule; a null mode is intra-state (CGST + SGST).
create or replace view public.gstr1_b2b_view
  with (security_invoker = on) as   -- keep RLS as the caller (was on)
 SELECT o.org_id,
    c.gstin AS customer_gstin,
    COALESCE(c.company_name, c.name) AS customer_name,
    o.invoice_no,
    (o.invoice_issued_at)::date AS invoice_date,
    public.order_total_due(o.id) AS invoice_value,
    '996719'::text AS sac_code,
    o.quote_gst_pct AS rate,
    public.order_taxable_value(o.id) AS taxable_value,
    CASE WHEN o.quote_gst_mode = 'igst'
         THEN public.order_total_due(o.id) - public.order_taxable_value(o.id)
         ELSE 0::numeric END AS igst,
    CASE WHEN coalesce(o.quote_gst_mode, 'intra') <> 'igst'
         THEN (public.order_total_due(o.id) - public.order_taxable_value(o.id)) / 2
         ELSE 0::numeric END AS cgst,
    CASE WHEN coalesce(o.quote_gst_mode, 'intra') <> 'igst'
         THEN (public.order_total_due(o.id) - public.order_taxable_value(o.id)) / 2
         ELSE 0::numeric END AS sgst,
    o.branch
   FROM orders o
     JOIN customers c ON c.id = o.customer_id
  WHERE o.invoice_no IS NOT NULL AND o.deleted_at IS NULL
    AND COALESCE(c.gstin, '') <> '';

create or replace view public.gstr1_b2c_view
  with (security_invoker = on) as
 SELECT o.org_id,
    (date_trunc('month', o.invoice_issued_at))::date AS period,
    o.quote_gst_pct AS rate,
    sum(public.order_taxable_value(o.id)) AS taxable_value,
    sum(CASE WHEN o.quote_gst_mode = 'igst'
             THEN public.order_total_due(o.id) - public.order_taxable_value(o.id)
             ELSE 0::numeric END) AS igst,
    sum(CASE WHEN coalesce(o.quote_gst_mode, 'intra') <> 'igst'
             THEN (public.order_total_due(o.id) - public.order_taxable_value(o.id)) / 2
             ELSE 0::numeric END) AS cgst,
    sum(CASE WHEN coalesce(o.quote_gst_mode, 'intra') <> 'igst'
             THEN (public.order_total_due(o.id) - public.order_taxable_value(o.id)) / 2
             ELSE 0::numeric END) AS sgst,
    count(*) AS invoice_count
   FROM orders o
     LEFT JOIN customers c ON c.id = o.customer_id
  WHERE o.invoice_no IS NOT NULL AND o.deleted_at IS NULL
    AND COALESCE(c.gstin, '') = ''
  GROUP BY o.org_id, (date_trunc('month', o.invoice_issued_at)), o.quote_gst_pct;

-- Extras added/changed/cancelled must re-check paid status too.
drop trigger if exists addons_sync_order_paid on public.addons;
create trigger addons_sync_order_paid
  after insert or update or delete on public.addons
  for each row execute function public.sync_order_paid_total();

-- Re-sync every order once under the new rule.
update public.orders o set
  payment_status = case
    when public.order_total_due(o.id) > 0
         and coalesce(o.paid_total, 0) >= public.order_total_due(o.id) then 'paid'
    when coalesce(o.paid_total, 0) > 0 then 'partial'
    else 'pending'
  end;

commit;

-- Check after running (expected for TEST Movers):
--   select id, amount, paid_total, public.order_total_due(id), payment_status
--     from orders where org_id = '2180a9a6-1790-424e-b41f-b1589690b540';
--   1001 → total 19,470 (17,818 + extras 1,400 + 18% GST on extras 252),
--          paid 17,818, 'partial'  (verified read-only 3 Nov)
-- NOTE: this also re-syncs APC's real orders — any with extra charges or
-- direct GST may move from 'paid' to 'partial'. That is the intended fix;
-- look at the list before running if you want to see them:
--   select id, amount, paid_total from orders o
--    where payment_status = 'paid'
--      and paid_total < public.order_total_due(o.id);   -- after step 1
--   1002 → total 29,500, paid 25,000, 'partial'
