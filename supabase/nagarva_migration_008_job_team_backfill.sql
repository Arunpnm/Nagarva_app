-- ═══════════════════════════════════════════════════════════════════════════
-- NAGARVA MIGRATION 008 — Session 2, Part A back-fill
-- Project: hqqcapifefsaqvotqvlt
-- Depends on: 001-007
--
-- orders.job_team (jsonb array of staff.id strings) never propagated to
-- order_staff until this session's app-side fix (CrewSyncService). Every
-- order whose crew was only ever set through the supervisor's field job
-- screen has ZERO order_staff rows, which is why the P&L card's Staff
-- Salary line has been under-reporting.
--
-- Scope, deliberately narrow: only touches orders with NO existing
-- order_staff rows at all — an order the owner already crewed manually via
-- Order Details' Team & Salary section (order_staff written directly,
-- job_team never touched) is left completely alone.
--
-- salary_amount default matches the app's own established day-rate
-- convention — staff.salary / 26, rounded — NOT the raw monthly salary.
-- See order_crew_section.dart's existing "Add Labour" dialog, which
-- already uses this exact formula as its own suggested-salary default.
--
-- CORRECTION (caught in review before this ran): the first draft applied
-- TODAY's staff.salary to every matching order regardless of age. For an
-- order still open, that's the right estimate — it's what the app itself
-- would default to if a supervisor added the same crew today. But for an
-- order already 'delivered' or 'closed', it would invent a crew cost that
-- was never actually recorded at the time, and that fabricated number
-- flows straight into Order Details Session 1's P&L card — silently
-- changing a historical profit figure the owner may have already relied
-- on, using a salary rate that may not even be what that staff member
-- earned back then.
--
-- Fix: delivered/closed/cancelled orders are excluded from this back-fill
-- entirely. Their crew simply stays unrecorded in order_staff, exactly as
-- it was before this migration — no historical figure changes. Only
-- orders still in an open/in-progress status (booked/pending/confirmed/
-- team_assigned/transit, or any other non-terminal value) get back-filled,
-- since those P&L figures are still live and a supervisor could still add
-- the same crew today anyway.
--
-- Convention: commit first, then run in the Supabase SQL editor
-- (nagarva project hqqcapifefsaqvotqvlt). Not safe to blindly re-run after
-- the app-side fix has started writing order_staff rows going forward —
-- but harmless to re-run before that, since the "no existing rows" guard
-- makes it a no-op for anything it already touched.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

insert into order_staff (org_id, order_id, staff_id, salary_amount, is_half_day, team_type)
select
  o.org_id,
  o.id,
  staff_id_text::uuid,
  round(coalesce(s.salary, 0) / 26.0)::numeric,
  false,
  'labour'
from orders o
cross join lateral jsonb_array_elements_text(o.job_team) as staff_id_text
join staff s on s.id = staff_id_text::uuid
where o.job_team is not null
  and jsonb_typeof(o.job_team) = 'array'
  and jsonb_array_length(o.job_team) > 0
  and o.deleted_at is null
  -- Never fabricate a crew cost for an order whose outcome is already
  -- settled — see the CORRECTION note above.
  and o.status not in ('delivered', 'closed', 'cancelled')
  and not exists (
    select 1 from order_staff os where os.order_id = o.id
  )
on conflict do nothing;

commit;


-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════
--
-- -- Open orders that still have job_team but no order_staff after this
-- -- runs — expect 0. (A non-zero row here most likely means a staff id
-- -- inside job_team no longer exists in `staff`, e.g. a deleted staff
-- -- member — that order needs its crew re-picked in the app.)
-- select o.id, o.status, o.job_team
-- from orders o
-- where o.job_team is not null
--   and jsonb_typeof(o.job_team) = 'array'
--   and jsonb_array_length(o.job_team) > 0
--   and o.deleted_at is null
--   and o.status not in ('delivered', 'closed', 'cancelled')
--   and not exists (select 1 from order_staff os where os.order_id = o.id);
--
-- -- How many orders this actually back-filled:
-- select count(distinct order_id) as backfilled_orders
-- from order_staff
-- where team_type = 'labour'
--   and created_at >= now() - interval '5 minutes';
--
-- -- Sanity check: delivered/closed/cancelled orders with job_team set are
-- -- deliberately UNTOUCHED by this migration — confirm none of them
-- -- picked up order_staff rows some other way that would look like this
-- -- migration ran on them (should be 0 or explainable by manual entry):
-- select o.id, o.status
-- from orders o
-- where o.status in ('delivered', 'closed', 'cancelled')
--   and o.job_team is not null
--   and jsonb_typeof(o.job_team) = 'array'
--   and jsonb_array_length(o.job_team) > 0
--   and exists (
--     select 1 from order_staff os
--     where os.order_id = o.id and os.created_at >= now() - interval '5 minutes'
--   );
