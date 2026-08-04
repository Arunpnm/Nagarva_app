-- ═══════════════════════════════════════════════════════════════════════════
-- NAGARVA MIGRATION 008 — Session 2, Part A back-fill  [REVISED]
-- Project: hqqcapifefsaqvotqvlt
-- Depends on: 001-007
--
-- Propagates orders.job_team (jsonb array of staff.id strings) into
-- order_staff for orders that were only ever crewed through the supervisor
-- field job screen. Fixes the P&L Staff Salary under-reporting.
--
-- Scope guards (unchanged from the reviewed draft, both correct):
--   * Only orders with ZERO existing order_staff rows — an order crewed
--     manually via Team & Salary is left completely alone.
--   * Terminal orders excluded entirely, so no historical P&L figure moves.
--
-- FOUR REVIEW FIXES applied to the draft:
--   1. Legacy terminal statuses added. The draft excluded only
--      ('delivered','closed','cancelled'). Legacy rows carry 'completed'
--      and 'pending_review' (per the normalisation map in the master brief
--      §6.2: completed → closed, pending_review → delivered). Those would
--      have been treated as OPEN and back-filled — fabricating exactly the
--      historical crew cost this migration exists to avoid.
--   2. Org scoping on the staff join. The draft joined staff on id alone,
--      so a staff id appearing in another org's job_team would insert a
--      cross-tenant crew row. Now joined on (id, org_id).
--   3. Malformed-uuid guard. jsonb_array_elements_text -> ::uuid throws
--      22P02 on any non-uuid string, aborting the whole statement. Now
--      filtered with a regex before casting.
--   4. Inactive staff still back-filled (correct — they were on the crew)
--      but the day-rate falls back to 0 rather than a stale salary when
--      staff.salary is null.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

with terminal_status as (
  select array[
    'delivered', 'closed', 'cancelled',
    'completed',        -- legacy → closed
    'pending_review'    -- legacy → delivered
  ] as vals
)
insert into order_staff (org_id, order_id, staff_id, salary_amount, is_half_day, team_type)
select
  o.org_id,
  o.id,
  sid::uuid,
  round(coalesce(s.salary, 0) / 26.0)::numeric,
  false,
  'labour'
from orders o
cross join terminal_status ts
cross join lateral jsonb_array_elements_text(o.job_team) as sid
join staff s
  on s.id = sid::uuid
 and s.org_id is not distinct from o.org_id      -- FIX 2: cross-tenant guard
where o.job_team is not null
  and jsonb_typeof(o.job_team) = 'array'
  and jsonb_array_length(o.job_team) > 0
  and o.deleted_at is null
  and lower(coalesce(o.status, '')) <> all (ts.vals)   -- FIX 1: legacy included
  -- FIX 3: only cast strings that are actually uuids
  and sid ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  and not exists (
    select 1 from order_staff os where os.order_id = o.id
  );

commit;


-- ═══════════════════════════════════════════════════════════════════════════
-- PRE-FLIGHT — run these BEFORE the migration above
-- ═══════════════════════════════════════════════════════════════════════════
--
-- A. What status values actually exist? Confirms the terminal list is complete.
--    If anything here looks terminal but isn't in the array above, STOP.
-- select status, count(*) from orders where deleted_at is null
--  group by status order by count(*) desc;
--
-- B. Dry run — exactly what would be inserted, and for which orders:
-- select o.id, o.status, jsonb_array_length(o.job_team) as crew_size,
--        count(s.id) as resolvable_staff
-- from orders o
-- cross join lateral jsonb_array_elements_text(o.job_team) as sid
-- left join staff s on s.id::text = sid and s.org_id is not distinct from o.org_id
-- where o.job_team is not null
--   and jsonb_typeof(o.job_team) = 'array'
--   and jsonb_array_length(o.job_team) > 0
--   and o.deleted_at is null
--   and lower(coalesce(o.status,'')) not in
--       ('delivered','closed','cancelled','completed','pending_review')
--   and not exists (select 1 from order_staff os where os.order_id = o.id)
-- group by o.id, o.status, o.job_team;
--
-- C. Any job_team entry that is not a valid uuid (would have aborted the draft):
-- select o.id, sid
-- from orders o
-- cross join lateral jsonb_array_elements_text(o.job_team) as sid
-- where jsonb_typeof(o.job_team) = 'array'
--   and sid !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';


-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION — run AFTER
-- ═══════════════════════════════════════════════════════════════════════════
--
-- 1. Open orders still unresolved — expect 0. Non-zero means a staff id in
--    job_team no longer exists (deleted staff); re-pick the crew in the app.
-- select o.id, o.status, o.job_team
-- from orders o
-- where o.job_team is not null
--   and jsonb_typeof(o.job_team) = 'array'
--   and jsonb_array_length(o.job_team) > 0
--   and o.deleted_at is null
--   and lower(coalesce(o.status,'')) not in
--       ('delivered','closed','cancelled','completed','pending_review')
--   and not exists (select 1 from order_staff os where os.order_id = o.id);
--
-- 2. How many orders were back-filled:
-- select count(distinct order_id) as backfilled_orders
-- from order_staff
-- where created_at >= now() - interval '5 minutes';
--
-- 3. No terminal order was touched — expect 0 rows:
-- select o.id, o.status
-- from orders o
-- join order_staff os on os.order_id = o.id
-- where lower(coalesce(o.status,'')) in
--       ('delivered','closed','cancelled','completed','pending_review')
--   and os.created_at >= now() - interval '5 minutes';
--
-- 4. No cross-tenant rows — expect 0:
-- select os.id, os.order_id
-- from order_staff os
-- join orders o on o.id = os.order_id
-- join staff s on s.id = os.staff_id
-- where s.org_id is distinct from o.org_id;
