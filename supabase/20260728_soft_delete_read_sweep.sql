-- ============================================================================
-- 20260728_soft_delete_read_sweep.sql
--
-- Item 11's read sweep, SQL side. Run AFTER
-- 20260728_reminders_and_soft_delete.sql (which adds the deleted_at columns).
--
-- WHY THIS FILE EXISTS
-- The Dart side filters `deleted_at is null` inside SupabaseTable._select(),
-- so every read through a generated table class is covered automatically.
-- Views and RPCs do not go through that path at all — they run in the
-- database. An audit of every view and function in this repo against the
-- seven soft-delete tables (leads, quotations, orders, payment_entries,
-- expenses, materials, vehicles) found EIGHT places that would still count
-- or expose deleted rows. All eight are fixed below.
--
-- Confirmed already correct, no change needed:
--   reminders_view          — joins leads/orders WITH `deleted_at is null`
--                             (added in the 28 Jul reminders migration)
--   can_delete_order()      — its payment_entries check filters deleted_at.
--                             Its `orders` read deliberately does NOT: you
--                             are asking about a row you are about to
--                             delete, so it must still be visible.
--   attendance_view, advances_view, get_survey_by_token, submit_survey,
--   verify_org_pin, verify_staff_pin, current_org_ids, is_platform_admin,
--   notify_new_lead, notify_supervisor_assigned, resolve_org_by_slug,
--   get_org_owner_email, assign_default_trial_plan, staff_hash_pin,
--   org_members_hash_pin, reminders_sync_status
--                           — none of these read any of the seven tables.
--
-- `materials` and `vehicles` are read by no view or RPC at all.
--
-- ---------------------------------------------------------------------------
-- A NOTE ON RLS, because the brief asked for something I did NOT do.
--
-- The brief says to append `deleted_at is null` to every RLS policy. That
-- would break the feature it is part of: the recycle bin has to READ
-- soft-deleted rows, and Restore has to UPDATE them. An RLS policy with
-- `deleted_at is null` in USING makes both impossible — the row becomes
-- invisible to its own owner the instant it is deleted, and unrecoverable.
--
-- RLS answers "which org's rows may this session touch". Whether a deleted
-- row is *shown* is a query concern, handled above and in Dart. Keeping
-- them separate is what makes an owner-only recycle bin possible at all.
-- The org_isolation policies are therefore left exactly as they are.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- GAP 1 (worst) — sync_order_paid_total()
--
-- This trigger recomputes orders.paid_total and payment_status by summing
-- payment_entries. With no deleted filter, a soft-deleted payment kept
-- counting as paid: the order stayed marked 'paid', outstanding stayed
-- understated, and the P&L stayed wrong. Silent financial corruption, and
-- it re-fires on every payment change.
--
-- Soft-deleting a payment is an UPDATE, which fires this trigger, so
-- paid_total now self-corrects the moment a payment is deleted or restored.
-- ---------------------------------------------------------------------------
create or replace function public.sync_order_paid_total()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
  v_order_id text;
  v_paid numeric;
  v_amount numeric;
  v_advance numeric;
begin
  v_order_id := coalesce(new.order_id, old.order_id);
  select coalesce(sum(amount), 0) into v_paid
    from payment_entries
   where order_id = v_order_id
     and deleted_at is null;          -- <-- the fix
  select coalesce(amount, 0), coalesce(advance_paid, 0)
    into v_amount, v_advance
    from orders where id = v_order_id;
  update orders set
    paid_total = v_paid,
    payment_status = case
      when v_amount > 0 and (v_paid + v_advance) >= v_amount then 'paid'
      when (v_paid + v_advance) > 0 then 'partial'
      else 'pending'
    end
  where id = v_order_id;
  return coalesce(new, old);
end $$;

-- One-off correction for any order whose paid_total was computed while a
-- deleted payment was still being counted. No-op if nothing is deleted yet.
update public.orders o
   set paid_total = coalesce(p.total, 0)
  from (select order_id, sum(amount) as total
          from public.payment_entries
         where deleted_at is null
         group by order_id) p
 where p.order_id = o.id
   and o.paid_total is distinct from coalesce(p.total, 0);

-- ---------------------------------------------------------------------------
-- GAP 2 — dashboard_kpis_view
--
-- The brief's exact warning: "a deleted lead that vanishes from the list
-- but still counts in dashboard numbers is worse than no delete at all."
-- Revenue, outstanding, order count, active leads and expenses were all
-- computed over deleted rows.
--
-- Column list and types are unchanged, so CREATE OR REPLACE is safe here
-- (no 42P16 risk — that only bites when a column's TYPE changes).
-- ---------------------------------------------------------------------------
create or replace view public.dashboard_kpis_view as
with org_ids as (
  select distinct org_id from public.orders
   where org_id is not null and deleted_at is null
  union
  select distinct org_id from public.staff where org_id is not null
  union
  select distinct org_id from public.expenses
   where org_id is not null and deleted_at is null
  union
  select distinct org_id from public.leads
   where org_id is not null and deleted_at is null
),
month_orders as (
  select *
  from public.orders
  where date_trunc('month', created_at) = date_trunc('month', now())
    and deleted_at is null
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
    and deleted_at is null
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
  where (status not in ('won', 'lost', 'closed') or status is null)
    and deleted_at is null
  group by org_id
),
orders_count as (
  select org_id, count(*) as v from month_orders group by org_id
),
outstanding as (
  select org_id, coalesce(sum(amount - coalesce(advance_paid, 0)), 0) as v
  from public.orders
  where payment_status is distinct from 'paid'
    and deleted_at is null
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

-- ---------------------------------------------------------------------------
-- GAP 3 — branch_kpis_view (per-branch revenue / outstanding / net profit)
-- ---------------------------------------------------------------------------
-- Column list, order and expressions are copied VERBATIM from
-- views_dashboard_and_ops.sql; the only change is the added
-- `and o.deleted_at is null`. CREATE OR REPLACE VIEW requires an identical
-- column list, so any drift here fails the whole migration.
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
  and o.deleted_at is null
group by o.branch, o.org_id;

-- ---------------------------------------------------------------------------
-- GAP 4 — trips_view
--
-- Lower stakes than the KPI views (it only pulls a customer NAME through
-- the join), but a deleted order should not keep labelling a trip.
-- The join stays LEFT, so the trip itself still lists with a null name.
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
left join public.orders o
  on o.id::text = vt.order_id::text
 and o.deleted_at is null;

-- ---------------------------------------------------------------------------
-- GAPS 5 & 6 — the two PUBLIC quote RPCs (granted to anon)
--
-- Without this, a customer holding an old link could still view — and
-- ACCEPT — a quote the office had deleted. Deleting a quote must revoke
-- its public link.
-- ---------------------------------------------------------------------------
create or replace function public.get_quotation_by_token(p_token text)
returns table (
  id uuid, customer text, phone text, from_address text, to_address text,
  from_floor int, to_floor int, items jsonb, charges jsonb,
  subtotal numeric, gst_pct numeric, gst_amount numeric, total numeric,
  status text, accepted_at timestamptz, org_name text
)
language sql
security definer
set search_path = public, extensions
stable
as $$
  select
    q.id, q.customer, q.phone, q.from_address, q.to_address,
    q.from_floor, q.to_floor, q.items, q.charges, q.subtotal,
    q.gst_pct, q.gst_amount, q.total, q.status, q.accepted_at,
    o.name as org_name
  from public.quotations q
  join public.organizations o on o.id = q.org_id
  where q.token = p_token
    and q.deleted_at is null;
$$;

revoke all on function public.get_quotation_by_token(text) from public;
grant execute on function public.get_quotation_by_token(text) to anon;
grant execute on function public.get_quotation_by_token(text) to authenticated;

create or replace function public.accept_quotation(
  p_token text, p_signature_name text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update public.quotations
    set status = 'accepted',
        accepted_at = now(),
        accepted_by_name = p_signature_name
    where token = p_token
      and status <> 'accepted'
      and deleted_at is null;
  return found;
end;
$$;

revoke all on function public.accept_quotation(text, text) from public;
grant execute on function public.accept_quotation(text, text) to anon;

-- ---------------------------------------------------------------------------
-- GAPS 7 & 8 — the two public-link RPCs added earlier today
-- (20260728_public_links_sign_and_track.sql). Same reasoning: deleting the
-- document must revoke its signature and tracking links.
--
-- DROP first, per CLAUDE.md, because these RETURN TABLE shapes have bitten
-- 42P13 before when changed in place.
-- ---------------------------------------------------------------------------
drop function if exists public.get_signature_request(text);

create or replace function public.get_signature_request(p_token text)
returns table (
  signature_id uuid,
  doc_type text,
  doc_id text,
  sig_status text,
  sig_customer_name text,
  sig_signed_at timestamptz,
  org_name text,
  payload jsonb
)
language plpgsql
security definer
set search_path = public, extensions
stable
as $$
begin
  return query
  select ds.id,
         ds.document_type,
         ds.document_id,
         ds.status,
         ds.customer_name,
         ds.signed_at,
         o.name,
         case ds.document_type
           when 'quote' then (
             select to_jsonb(q) - 'org_id'
             from public.quotations q
             where q.id = ds.document_id and q.org_id = ds.org_id
               and q.deleted_at is null
           )
           else (
             select to_jsonb(ord) - 'org_id' - 'job_otp'
             from public.orders ord
             where ord.id = ds.document_id and ord.org_id = ds.org_id
               and ord.deleted_at is null
           )
         end
  from public.document_signatures ds
  join public.organizations o on o.id = ds.org_id
  where ds.sign_token = p_token
  limit 1;
end;
$$;

revoke all on function public.get_signature_request(text) from public;
revoke all on function public.get_signature_request(text) from anon;
revoke all on function public.get_signature_request(text) from authenticated;
grant execute on function public.get_signature_request(text) to service_role;

drop function if exists public.get_order_tracking(text);

create or replace function public.get_order_tracking(p_token text)
returns table (
  order_ref text,
  cust_name text,
  from_city text,
  to_city text,
  move_date date,
  current_status text,
  tracking_stage text,
  org_name text,
  show_crew boolean,
  crew_vehicle text,
  crew_driver text,
  crew_phone text,
  history jsonb
)
language plpgsql
security definer
set search_path = public, extensions
stable
as $$
declare
  v_show_crew boolean;
  v_org uuid;
begin
  select ord.org_id into v_org
  from public.orders ord
  where ord.tracking_token = p_token
    and ord.deleted_at is null;

  if v_org is null then
    return;  -- unknown OR deleted token: zero rows -> Edge Function 404s
  end if;

  select coalesce((s.value #>> '{}') in ('true', '1'), false)
    into v_show_crew
  from public.settings s
  where s.org_id = v_org and s.key = 'tracking_show_crew';
  v_show_crew := coalesce(v_show_crew, false);

  return query
  select ord.id,
         ord.customer,
         ord.from_city,
         ord.to_city,
         ord.move_date::date,
         ord.status,
         ord.tracking_status,
         o.name,
         v_show_crew,
         case when v_show_crew then ord.vehicle_no end,
         case when v_show_crew then ord.driver_name end,
         case when v_show_crew then ord.phone end,
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'status', h.status,
                    'note', h.note,
                    'changed_at', h.changed_at)
                  order by h.changed_at)
           from public.order_status_history h
           where h.order_id = ord.id and h.org_id = ord.org_id
         ), '[]'::jsonb)
  from public.orders ord
  join public.organizations o on o.id = ord.org_id
  where ord.tracking_token = p_token
    and ord.deleted_at is null
  limit 1;
end;
$$;

revoke all on function public.get_order_tracking(text) from public;
revoke all on function public.get_order_tracking(text) from anon;
revoke all on function public.get_order_tracking(text) from authenticated;
grant execute on function public.get_order_tracking(text) to service_role;

commit;

-- ============================================================================
-- Verify after running — soft-delete one order in a scratch org, then:
--
--   -- 1. KPI views must drop it
--   select revenue_this_month, orders_this_month, outstanding_amount
--     from dashboard_kpis_view where org_id = '<org>';
--   select branch, revenue from branch_kpis_view where org_id = '<org>';
--
--   -- 2. Public links must stop resolving
--   select * from get_order_tracking('<that order''s tracking_token>');
--       -- expect ZERO rows
--
--   -- 3. Payments must stop counting once deleted
--   update payment_entries set deleted_at = now() where id = '<some id>';
--   select id, paid_total, payment_status from orders where id = '<order>';
--       -- paid_total must have dropped by that payment's amount
--
--   -- 4. And restore must put it all back
--   update payment_entries set deleted_at = null where id = '<some id>';
--
-- Grep check that nothing was missed — every view/function body mentioning
-- one of the seven tables should also mention deleted_at (except
-- can_delete_order's orders read, which is intentional):
--
--   select p.proname
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and p.prosrc ~* '(from|join)\s+(public\.)?(leads|quotations|orders|payment_entries|expenses|materials|vehicles)\M'
--      and p.prosrc !~* 'deleted_at';
--   -- expect only: can_delete_order
-- ============================================================================
