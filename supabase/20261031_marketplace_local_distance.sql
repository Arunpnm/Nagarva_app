-- =============================================================================
-- 20261031_marketplace_local_distance.sql — within-city price by distance
-- =============================================================================
-- HANDED OVER, NOT RUN. Run AFTER 20261031_marketplace_addon_slabs.sql.
-- One transaction; preflight refuses, postflight asserts and probes.
--
-- Arun, 31 Oct 2026: "the price is calculated by cft and distance with
-- addon" and "even within city also we can have price range ... by
-- distance". Until now a move inside one city ignored distance entirely
-- (mkt_distance_km returned a fixed 15 for same-city, which priced
-- nothing but was shown to the customer as if measured).
--
-- Now, per city, the admin sets DISTANCE BANDS, each with an extra rate
-- per CFT:
--
--     Chennai:  up to 10 km   + Rs 2 per CFT
--               up to 25 km   + Rs 4 per CFT
--               up to 40 km   + Rs 6 per CFT
--
-- and a local move is priced CFT x (package rate + band rate), the same
-- shape as intercity's CFT x (rate + km x per-km rate). The km is
-- measured on the server from the pickup and drop points the customer
-- gives ({"lat","lng"}), straight-line x 1.25 for roads, the same factor
-- the intercity distance already uses.
--
-- Rules:
--   * the city has bands -> both points are required; a move longer than
--     the last band is refused ('too_far'), never priced at the last
--     band's rate;
--   * no bands -> as before, no distance part (points are optional and
--     only reported back);
--   * a point more than 80 km from the city centre is refused
--     ('outside_city'). That is a sanity bound on where a "within city"
--     point can be, not a price.
-- Nothing is seeded. Admins enter bands in Super Admin > Marketplace >
-- Prices.
--
-- mkt_quote() is replaced in place again (same signature and return type);
-- its output gains 'band_km', and 'km' is NULL for a local move with no
-- points rather than an invented 15.
-- =============================================================================

begin;

set local search_path = public, extensions;

do $preflight$
begin
  if to_regclass('public.mkt_addon_slabs') is null
     or to_regprocedure('public.mkt_addon_price(text,text,numeric)') is null then
    raise exception 'PREFLIGHT FAILED: run 20261031_marketplace_addon_slabs.sql first';
  end if;
  if to_regclass('public.mkt_local_bands') is not null then
    raise exception 'PREFLIGHT FAILED: mkt_local_bands already exists; this migration has run before';
  end if;
end
$preflight$;

create table public.mkt_local_bands (
  city    text not null references public.mkt_cities(city) on update cascade,
  max_km  numeric not null check (max_km > 0 and max_km <= 80),
  per_cft numeric not null check (per_cft >= 0),
  updated_at timestamptz not null default now(),
  primary key (city, max_km)
);

alter table public.mkt_local_bands enable row level security;
create policy mkt_local_bands_read on public.mkt_local_bands
  for select to anon, authenticated using (true);
create policy mkt_local_bands_admin on public.mkt_local_bands
  for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
revoke all on public.mkt_local_bands from anon, public;
grant select on public.mkt_local_bands to anon;
grant select, insert, update, delete on public.mkt_local_bands to authenticated;

-- Road km between two {"lat","lng"} points: straight line x 1.25.
create function public.mkt_points_km(a jsonb, b jsonb)
returns numeric
language sql immutable set search_path = public
as $$
  select round((2 * 6371 * asin(sqrt(
           power(sin(radians((b->>'lat')::numeric - (a->>'lat')::numeric) / 2), 2)
         + cos(radians((a->>'lat')::numeric)) * cos(radians((b->>'lat')::numeric))
           * power(sin(radians((b->>'lng')::numeric - (a->>'lng')::numeric) / 2), 2))) * 1.25)::numeric, 1)
$$;

-- Why a point cannot be used for a move in p_city, or NULL if it can.
create function public.mkt_point_problem(p_city text, pt jsonb)
returns text
language plpgsql stable security definer set search_path = public
as $$
declare
  c mkt_cities;
begin
  if jsonb_typeof(pt) is distinct from 'object'
     or jsonb_typeof(pt->'lat') is distinct from 'number'
     or jsonb_typeof(pt->'lng') is distinct from 'number' then
    return 'no_address';
  end if;
  if abs((pt->>'lat')::numeric) > 90 or abs((pt->>'lng')::numeric) > 180 then
    return 'bad_address';
  end if;
  select * into c from mkt_cities where city = p_city;
  if c.city is null
     or public.mkt_points_km(jsonb_build_object('lat', c.lat, 'lng', c.lng), pt) > 80 then
    return 'outside_city';
  end if;
  return null;
end
$$;

create or replace function public.mkt_quote(p jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_from  text := btrim(coalesce(p->>'from_city', ''));
  v_to    text := btrim(coalesce(p->>'to_city', ''));
  v_pkg   text := coalesce(p->>'package', '');
  v_local boolean;
  v_km    numeric;
  r       public.mkt_rates;
  cp      public.mkt_city_prices;
  rules   public.mkt_city_rules;
  l       jsonb;
  it      public.mkt_catalogue;
  v_var   jsonb;
  v_qty   int;
  s       text;
  sv      jsonb;
  v_cft   numeric := 0;
  v_move  numeric := 0;
  v_floor numeric := 0;
  v_veh   numeric := 0;
  v_svc   numeric := 0;
  v_add   numeric := 0;
  v_sub   numeric;
  v_gst   numeric;
  v_total numeric;
  v_adv   numeric;
  v_cars  int := 0;
  v_bikes int := 0;
  v_months int := greatest(coalesce((p->'addons'->>'storage_months')::int, 0), 0);
  n_floors int := 0;
  v_price numeric;
  v_slab  text;
  v_band  public.mkt_local_bands;
  v_bands boolean;
  v_why   text;
begin
  if not exists (select 1 from mkt_cities where city = v_from and active)
     or not exists (select 1 from mkt_cities where city = v_to and active) then
    return jsonb_build_object('ok', false, 'reason', 'city_not_served');
  end if;
  if v_pkg not in ('economy','standard','premium') then
    return jsonb_build_object('ok', false, 'reason', 'bad_package');
  end if;
  if jsonb_typeof(p->'lines') is distinct from 'array'
     or jsonb_array_length(p->'lines') = 0 then
    return jsonb_build_object('ok', false, 'reason', 'no_items');
  end if;

  v_local := v_from = v_to;
  if not v_local then
    v_km := public.mkt_distance_km(v_from, v_to);
  else
    -- Within a city the price depends on how far apart the two addresses
    -- are, once the admin has set distance bands for that city.
    v_bands := exists (select 1 from mkt_local_bands where city = v_from);
    v_why := public.mkt_point_problem(v_from, p->'pickup');
    if v_why is null then
      v_why := public.mkt_point_problem(v_from, p->'drop');
    end if;
    if v_why is null then
      v_km := public.mkt_points_km(p->'pickup', p->'drop');
    elsif v_bands then
      return jsonb_build_object('ok', false, 'reason', v_why);
    end if;
    if v_bands then
      select * into v_band from mkt_local_bands
       where city = v_from and max_km >= v_km
       order by max_km limit 1;
      if v_band.city is null then
        return jsonb_build_object('ok', false, 'reason', 'too_far',
          'detail', v_km || ' km within ' || v_from);
      end if;
    end if;
  end if;
  select * into cp from mkt_city_prices where city = v_from;
  rules := public.mkt_rules_for(v_from);

  for l in select * from jsonb_array_elements(p->'lines') loop
    select * into it from mkt_catalogue where key = l->>'key' and active;
    if it.key is null then
      return jsonb_build_object('ok', false, 'reason', 'unknown_item', 'detail', l->>'key');
    end if;
    v_var := it.variants -> coalesce((l->>'variant')::int, 0);
    v_qty := coalesce((l->>'qty')::int, 0);
    if v_var is null or v_qty < 1 or v_qty > 50 then
      return jsonb_build_object('ok', false, 'reason', 'bad_line', 'detail', it.key);
    end if;
    if it.cat = 'veh' then
      if it.key = 'car' then v_cars := v_cars + v_qty; else v_bikes := v_bikes + v_qty; end if;
    else
      v_cft := v_cft + v_qty * (v_var->>'cft')::numeric;
    end if;
    for s in select jsonb_array_elements_text(coalesce(l->'services', '[]')) loop
      select x into sv from jsonb_array_elements(it.services) x where x->>'code' = s;
      if sv is null then
        return jsonb_build_object('ok', false, 'reason', 'unknown_service', 'detail', it.key || ':' || s);
      end if;
      -- Dismantle & assemble is included above Economy (design rule).
      continue when s = 'dis' and v_pkg <> 'economy';
      if sv->>'price' is null then
        return jsonb_build_object('ok', false, 'reason', 'no_price', 'detail', 'service ' || it.key || ':' || s);
      end if;
      v_svc := v_svc + v_qty * (sv->>'price')::numeric;
    end loop;
  end loop;

  v_slab := public.mkt_slab_for(v_cft);

  if v_cft > 0 then
    select * into r from mkt_rates where city = v_from and package = v_pkg;
    if r.city is null then
      return jsonb_build_object('ok', false, 'reason', 'no_price', 'detail', 'rates ' || v_from || ' ' || v_pkg);
    end if;
    v_move := greatest(r.min_move,
      round(v_cft * (r.per_cft + case when v_local then coalesce(v_band.per_cft, 0)
                                      else v_km * r.per_cft_per_km end) / 10) * 10);
    n_floors := (case when coalesce((p->>'pickup_lift')::boolean, false) then 0 else greatest(coalesce((p->>'pickup_floor')::int, 0), 0) end)
              + (case when coalesce((p->>'drop_lift')::boolean, false) then 0 else greatest(coalesce((p->>'drop_floor')::int, 0), 0) end);
    if n_floors > 0 then
      v_price := public.mkt_addon_price(v_from, 'per_floor', v_cft);
      if v_price is null then
        return jsonb_build_object('ok', false, 'reason', 'no_price', 'detail', 'floor charge ' || v_from || ', ' || v_slab);
      end if;
      v_floor := n_floors * v_price;
    end if;
  end if;

  if v_cars > 0 then
    if (v_local and cp.car_local is null) or (not v_local and (cp.car_base is null or cp.car_per_km is null)) then
      return jsonb_build_object('ok', false, 'reason', 'no_price', 'detail', 'car shipping ' || v_from);
    end if;
    v_veh := v_veh + v_cars * case when v_local then cp.car_local
                                   else round((cp.car_base + v_km * cp.car_per_km) / 10) * 10 end;
  end if;
  if v_bikes > 0 then
    if (v_local and cp.bike_local is null) or (not v_local and (cp.bike_base is null or cp.bike_per_km is null)) then
      return jsonb_build_object('ok', false, 'reason', 'no_price', 'detail', 'bike shipping ' || v_from);
    end if;
    v_veh := v_veh + v_bikes * case when v_local then cp.bike_local
                                    else round((cp.bike_base + v_km * cp.bike_per_km) / 10) * 10 end;
  end if;

  if coalesce((p->'addons'->>'cover')::boolean, false) then
    v_price := public.mkt_addon_price(v_from, 'damage_cover', v_cft);
    if v_price is null then
      return jsonb_build_object('ok', false, 'reason', 'no_price', 'detail', 'damage cover ' || v_from || ', ' || v_slab);
    end if;
    v_add := v_add + v_price;
  end if;
  -- Unpacking & arranging is included in Premium (design rule).
  if coalesce((p->'addons'->>'unpack')::boolean, false) and v_pkg <> 'premium' then
    v_price := public.mkt_addon_price(v_from, 'unpacking', v_cft);
    if v_price is null then
      return jsonb_build_object('ok', false, 'reason', 'no_price', 'detail', 'unpacking ' || v_from || ', ' || v_slab);
    end if;
    v_add := v_add + v_price;
  end if;
  if v_months > 0 then
    v_price := public.mkt_addon_price(v_from, 'storage_month', v_cft);
    if v_price is null then
      return jsonb_build_object('ok', false, 'reason', 'no_price', 'detail', 'storage ' || v_from || ', ' || v_slab);
    end if;
    v_add := v_add + v_months * v_price;
  end if;

  v_sub := v_move + v_floor + v_veh + v_svc + v_add;
  v_gst := round(v_sub * 0.18, 2);
  v_total := v_sub + v_gst;
  v_adv := least(v_total, greatest(coalesce(rules.advance_min, 0),
                                   round(v_total * coalesce(rules.advance_pct, 0) / 100)));
  return jsonb_build_object(
    'ok', true, 'km', v_km, 'local', v_local, 'cft', v_cft, 'slab', v_slab,
    'band_km', v_band.max_km,
    'move', v_move, 'floors', v_floor, 'vehicles', v_veh, 'services', v_svc,
    'addons', v_add, 'subtotal', v_sub, 'gst', v_gst, 'total', v_total,
    'advance', v_adv);
end
$$;

revoke all on function public.mkt_points_km(jsonb, jsonb) from public;
revoke all on function public.mkt_point_problem(text, jsonb) from public;
-- Internal: called only from mkt_quote, which runs as its owner.

do $postflight$
declare
  v_bad  int;
  v_city text;
  c      mkt_cities;
  v_near jsonb;
  v_mid  jsonb;
  v_far  jsonb;
  v_q    jsonb;
  v_q2   jsonb;
  v_key  text;
  v_lines jsonb;
  v_had_rate boolean;
  r      mkt_rates;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.mkt_local_bands'::regclass) then
    raise exception 'POSTFLIGHT: RLS off on mkt_local_bands';
  end if;
  if has_table_privilege('anon', 'public.mkt_local_bands', 'insert')
     or has_table_privilege('anon', 'public.mkt_local_bands', 'update') then
    raise exception 'POSTFLIGHT: anon can write mkt_local_bands';
  end if;
  select count(*) into v_bad
    from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
   where p.oid in ('public.mkt_quote(jsonb)'::regprocedure,
                   'public.mkt_points_km(jsonb,jsonb)'::regprocedure,
                   'public.mkt_point_problem(text,jsonb)'::regprocedure)
     and a.privilege_type = 'EXECUTE' and a.grantee = 0;
  if v_bad > 0 then
    raise exception 'POSTFLIGHT: PUBLIC can execute a pricing function';
  end if;
  if not has_function_privilege('anon', 'public.mkt_quote(jsonb)', 'execute') then
    raise exception 'POSTFLIGHT: anon lost execute on mkt_quote';
  end if;
  if (select count(*) from mkt_local_bands) <> 0 then
    raise exception 'POSTFLIGHT: bands must start empty';
  end if;

  -- Behaviour, all undone: a city with two bands prices a near move and a
  -- farther one differently, refuses a move past the last band, and
  -- refuses a move with no points.
  select * into c from mkt_cities where active order by city limit 1;
  v_city := c.city;
  v_near := jsonb_build_object('lat', c.lat, 'lng', c.lng);
  v_mid  := jsonb_build_object('lat', c.lat + 0.10, 'lng', c.lng);   -- ~14 km
  v_far  := jsonb_build_object('lat', c.lat + 0.40, 'lng', c.lng);   -- ~56 km
  select key into v_key from mkt_catalogue
   where active and cat <> 'veh' and services = '[]'::jsonb order by sort limit 1;
  v_lines := jsonb_build_array(jsonb_build_object('key', v_key, 'variant', 0, 'qty', 5));

  v_had_rate := exists (select 1 from mkt_rates where city = v_city and package = 'standard');
  if not v_had_rate then
    insert into mkt_rates (city, package, per_cft, per_cft_per_km, min_move)
    values (v_city, 'standard', 10, 0, 0);
  end if;
  select * into r from mkt_rates where city = v_city and package = 'standard';
  insert into mkt_local_bands (city, max_km, per_cft) values
    (v_city, 10, 1), (v_city, 30, 5);

  v_q := public.mkt_quote(jsonb_build_object('from_city', v_city, 'to_city', v_city,
    'package', 'standard', 'lines', v_lines, 'pickup', v_near, 'drop', v_near));
  v_q2 := public.mkt_quote(jsonb_build_object('from_city', v_city, 'to_city', v_city,
    'package', 'standard', 'lines', v_lines, 'pickup', v_near, 'drop', v_mid));
  if (v_q->>'ok')::boolean is not true or (v_q2->>'ok')::boolean is not true
     or (v_q->>'band_km')::numeric <> 10 or (v_q2->>'band_km')::numeric <> 30
     or (v_q->>'move')::numeric is distinct from
        greatest(r.min_move, round((v_q->>'cft')::numeric * (r.per_cft + 1) / 10) * 10)
     or (v_q2->>'move')::numeric is distinct from
        greatest(r.min_move, round((v_q2->>'cft')::numeric * (r.per_cft + 5) / 10) * 10) then
    raise exception 'POSTFLIGHT: band pricing wrong: near % / farther %', v_q, v_q2;
  end if;

  v_q := public.mkt_quote(jsonb_build_object('from_city', v_city, 'to_city', v_city,
    'package', 'standard', 'lines', v_lines, 'pickup', v_near, 'drop', v_far));
  if v_q->>'reason' is distinct from 'too_far' then
    raise exception 'POSTFLIGHT: a move past the last band was not refused: %', v_q;
  end if;
  v_q := public.mkt_quote(jsonb_build_object('from_city', v_city, 'to_city', v_city,
    'package', 'standard', 'lines', v_lines));
  if v_q->>'reason' is distinct from 'no_address' then
    raise exception 'POSTFLIGHT: a banded city priced a move with no addresses: %', v_q;
  end if;

  delete from mkt_local_bands where city = v_city;
  if not v_had_rate then
    delete from mkt_rates where city = v_city and package = 'standard';
  end if;
end
$postflight$;

commit;
