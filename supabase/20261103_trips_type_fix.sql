-- 3 Nov 2026 — follow-up to 20261103_merge_vehicle_trips_into_trips.sql.
--
-- 1. The copied trips were tagged trip_type 'local', but the Trips screen
--    only knows 'own' / 'hired' (its edit dialog would fail on 'local').
--    The copied odometer trips were the company's own vehicle.
-- 2. They showed "(no trip no.)" and "— → —" in the Trips list. Fill the
--    trip number with the order number and the route with the order's
--    cities — only where blank, never overwriting.
--
-- Only touches the 6 trips the merge created (trip_type 'local').
-- Safe to re-run.

begin;

update public.trips t
   set trip_no  = coalesce(nullif(trim(t.trip_no), ''), o.id),
       from_loc = coalesce(nullif(trim(t.from_loc), ''), nullif(trim(o.from_city), '')),
       to_loc   = coalesce(nullif(trim(t.to_loc), ''),   nullif(trim(o.to_city), ''))
  from public.trip_orders tor
  join public.orders o on o.id = tor.order_id
 where tor.trip_id = t.id
   and t.trip_type = 'local';

update public.trips
   set trip_type = 'own'
 where trip_type = 'local';

select trip_type, count(*) as trips,
       count(*) filter (where trip_no is null) as without_number
  from public.trips
 group by trip_type;

commit;
