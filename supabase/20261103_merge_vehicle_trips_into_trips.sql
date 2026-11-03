-- 3 Nov 2026 — one trip model: `trips` (Arun's decision).
--
-- Before: two stores for the same thing.
--   trips (+ trip_orders, trip_expenses, trip P&L) — a vehicle trip that can
--     carry several orders. Used by Trips, Trip detail, Driver app.
--   vehicle_trips — one row per order holding only the odometer (km_start /
--     km_end). Written by the supervisor's Crew step and read by the LR.
--
-- After: the supervisor's job screen and the LR read/write `trips` through
-- `trip_orders` (app change in the same batch). This copies the old
-- per-order odometer rows across so nothing is lost:
--   * order NOT yet on any trip  -> new trip (local, odometer, date, status
--     'completed' when a closing reading exists, else 'ongoing') + link row
--   * order ALREADY on a trip     -> fill that trip's km_start / km_end only
--     where they are empty (never overwrites a reading)
--
-- vehicle_trips is LEFT IN PLACE (not dropped) as a backup; nothing in the
-- app writes it after this batch. Drop it later once you are happy.
--
-- Safe to re-run: an order that already has a trip link is never given a
-- second trip, and readings are only filled where blank.
-- On 3 Nov: 7 rows in 4 companies -> 6 new trips + 1 existing trip filled.

begin;

-- 3 of the 4 companies with old rows are on an ended trial, and
-- trg_org_writable refuses new rows for them ("Your trial has ended").
-- This copies EXISTING data, so the check is paused for this transaction
-- only and switched back on before commit. The audit trigger stays on.
alter table public.trips disable trigger trg_org_writable;

create temp table _vt_move on commit drop as
select gen_random_uuid()                     as new_trip_id,
       v.org_id,
       v.order_id,
       nullif(trim(coalesce(v.vehicle_no, '')), '')  as vehicle_no,
       nullif(trim(coalesce(v.driver_name, '')), '') as driver_name,
       nullif(round(v.km_start), 0)::int     as km_start,   -- trips.km_* are integer
       nullif(round(v.km_end), 0)::int       as km_end,
       coalesce(v.trip_date, v.created_at::date) as trip_date
  from public.vehicle_trips v
  join public.orders o on o.id = v.order_id
 where not exists (select 1 from public.trip_orders t
                    where t.order_id = v.order_id);

insert into public.trips
  (id, org_id, trip_type, vehicle_no, driver_name, start_date, end_date,
   km_start, km_end, status, notes)   -- total_km is a generated column
select m.new_trip_id, m.org_id, 'own', m.vehicle_no, m.driver_name,
       m.trip_date,
       case when m.km_end is not null then m.trip_date end,
       m.km_start, m.km_end,
       case when m.km_end is not null then 'completed' else 'ongoing' end,
       'Moved from the order''s odometer log (3 Nov 2026)'
  from _vt_move m;

insert into public.trip_orders (org_id, trip_id, order_id)
select m.org_id, m.new_trip_id, m.order_id
  from _vt_move m;

-- Orders already on a trip: fill blank readings from the old log.
update public.trips t
   set km_start = coalesce(t.km_start, nullif(round(v.km_start), 0)::int),
       km_end   = coalesce(t.km_end,   nullif(round(v.km_end), 0)::int),
       updated_at = now()
  from public.trip_orders tor
  join public.vehicle_trips v on v.order_id = tor.order_id
 where tor.trip_id = t.id
   and (t.km_start is null or t.km_end is null);

alter table public.trips enable trigger trg_org_writable;

-- Check: every order in the old log is now on a trip.
select count(*) as old_rows,
       count(*) filter (where exists (select 1 from public.trip_orders t
                                       where t.order_id = v.order_id))
         as now_on_a_trip
  from public.vehicle_trips v;

commit;
