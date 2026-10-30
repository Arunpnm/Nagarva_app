-- =============================================================================
-- 20261030_marketplace_pricing.sql — what a customer pays Nagarva for a move
-- =============================================================================
-- HANDED OVER, NOT RUN. Needs 20261030_marketplace_vendor.sql first (the
-- preflight refuses otherwise). One transaction; postflight asserts.
--
-- The customer app (design: Nagarva Customer.dc.html) prices a move from
-- the items the customer picks, the package, the distance, floors without
-- a lift, vehicles, per-item services and add-ons, plus 18% GST. Arun's
-- call, 30 Oct 2026: Nagarva's admins enter every price; nothing is
-- invented here. So:
--   * mkt_cities       — the cities served, with coordinates for distance
--                        (geography, seeded from the design's city list)
--   * mkt_catalogue    — items and their sizes in CFT (volume, seeded from
--                        the design); each item's services carry a price
--                        that starts NULL
--   * mkt_rates        — per city and package: rate per CFT, extra per CFT
--                        per km for intercity, minimum move charge. EMPTY.
--   * mkt_city_prices  — per city: floor charge, car and bike shipping,
--                        damage cover, unpacking, storage. EMPTY.
--   * mkt_quote(jsonb) — the one price calculation. The app shows what it
--                        returns, and booking (later) will re-run it on the
--                        server, so a customer cannot send their own price.
--                        A missing price returns ok=false with the reason;
--                        it never substitutes a number.
--
-- Read by anyone (anon too): prices and the catalogue are what the public
-- booking app shows. Written by Nagarva admins only.
-- =============================================================================

begin;

do $preflight$
begin
  if to_regclass('public.mkt_city_rules') is null then
    raise exception 'PREFLIGHT FAILED: run 20261030_marketplace_vendor.sql first';
  end if;
  if to_regprocedure('public.is_platform_admin()') is null then
    raise exception 'PREFLIGHT FAILED: is_platform_admin() missing';
  end if;
  if to_regclass('public.mkt_rates') is not null then
    raise exception 'PREFLIGHT FAILED: mkt_rates already exists; this migration has run before';
  end if;
end
$preflight$;

create table public.mkt_cities (
  city    text primary key,
  lat     numeric not null,
  lng     numeric not null,
  active  boolean not null default true
);
insert into public.mkt_cities (city, lat, lng) values
  ('Chennai', 13.08, 80.27), ('Bengaluru', 12.97, 77.59),
  ('Coimbatore', 11.02, 76.96), ('Hyderabad', 17.39, 78.49),
  ('Kochi', 9.93, 76.27), ('Mumbai', 19.08, 72.88),
  ('Pune', 18.52, 73.86), ('Delhi', 28.61, 77.21);

create table public.mkt_catalogue (
  key       text primary key,
  cat       text not null check (cat in ('bed','liv','din','app','ele','off','veh','oth')),
  name      text not null,
  sort      int  not null default 0,
  -- [{"name": "...", "cft": 25}, ...]
  variants  jsonb not null check (jsonb_typeof(variants) = 'array'),
  -- [{"code": "dis", "label": "...", "price": null}, ...]
  services  jsonb not null default '[]' check (jsonb_typeof(services) = 'array'),
  active    boolean not null default true
);

insert into public.mkt_catalogue (key, cat, name, sort, variants, services) values
  ('cot', 'bed', 'Cot / bed', 1, '[{"name": "Single · basic", "cft": 35}, {"name": "Double · basic", "cft": 55}, {"name": "Queen · hydraulic storage", "cft": 70}, {"name": "King · hydraulic storage", "cft": 80}, {"name": "Bunk bed", "cft": 60}, {"name": "Diwan / folding", "cft": 25}]'::jsonb, '[{"code": "dis", "label": "Dismantle & assemble", "price": null}]'::jsonb),
  ('mat', 'bed', 'Mattress', 2, '[{"name": "Single", "cft": 10}, {"name": "Double / queen", "cft": 18}, {"name": "King", "cft": 22}]'::jsonb, '[]'::jsonb),
  ('ward', 'bed', 'Wardrobe', 3, '[{"name": "1-door", "cft": 25}, {"name": "2-door", "cft": 40}, {"name": "3-door", "cft": 55}, {"name": "4-door", "cft": 70}, {"name": "Sliding door", "cft": 75}]'::jsonb, '[{"code": "dis", "label": "Dismantle & assemble", "price": null}]'::jsonb),
  ('dress', 'bed', 'Dressing table', 4, '[{"name": "Small", "cft": 15}, {"name": "With mirror", "cft": 22}]'::jsonb, '[{"code": "dis", "label": "Dismantle & assemble", "price": null}]'::jsonb),
  ('side', 'bed', 'Side table', 5, '[{"name": "Standard", "cft": 5}]'::jsonb, '[]'::jsonb),
  ('cradle', 'bed', 'Baby cot / cradle', 6, '[{"name": "Standard", "cft": 12}]'::jsonb, '[{"code": "dis", "label": "Dismantle & assemble", "price": null}]'::jsonb),
  ('sofa', 'liv', 'Sofa', 7, '[{"name": "1-seater", "cft": 15}, {"name": "2-seater", "cft": 30}, {"name": "3-seater", "cft": 45}, {"name": "L-shape", "cft": 70}, {"name": "Sofa cum bed", "cft": 50}]'::jsonb, '[{"code": "dis", "label": "Dismantle & assemble", "price": null}]'::jsonb),
  ('recl', 'liv', 'Recliner', 8, '[{"name": "1-seater", "cft": 20}, {"name": "2-seater", "cft": 40}, {"name": "3-seater", "cft": 55}]'::jsonb, '[]'::jsonb),
  ('ctab', 'liv', 'Centre table', 9, '[{"name": "Wooden", "cft": 10}, {"name": "Glass top", "cft": 12}, {"name": "Marble top", "cft": 15}]'::jsonb, '[]'::jsonb),
  ('tvu', 'liv', 'TV unit', 10, '[{"name": "Small", "cft": 15}, {"name": "Wall-length", "cft": 30}]'::jsonb, '[{"code": "dis", "label": "Dismantle & assemble", "price": null}]'::jsonb),
  ('shelf', 'liv', 'Bookshelf', 11, '[{"name": "Small", "cft": 12}, {"name": "Large", "cft": 25}]'::jsonb, '[{"code": "dis", "label": "Dismantle & assemble", "price": null}]'::jsonb),
  ('shoe', 'liv', 'Shoe rack', 12, '[{"name": "Standard", "cft": 6}]'::jsonb, '[]'::jsonb),
  ('pooja', 'liv', 'Pooja unit', 13, '[{"name": "Wall-mounted", "cft": 6}, {"name": "Floor standing", "cft": 12}]'::jsonb, '[{"code": "un", "label": "Wall unmount", "price": null}, {"code": "re", "label": "Wall mount", "price": null}]'::jsonb),
  ('dtab', 'din', 'Dining table', 14, '[{"name": "4-seater", "cft": 25}, {"name": "6-seater", "cft": 35}, {"name": "8-seater", "cft": 50}]'::jsonb, '[{"code": "dis", "label": "Dismantle & assemble", "price": null}, {"code": "glass", "label": "Glass / marble top", "price": null}]'::jsonb),
  ('dch', 'din', 'Dining chair', 15, '[{"name": "Wooden", "cft": 6}, {"name": "Cushioned", "cft": 7}, {"name": "Plastic", "cft": 3}]'::jsonb, '[]'::jsonb),
  ('fridge', 'din', 'Fridge', 16, '[{"name": "Single door", "cft": 25}, {"name": "Double door", "cft": 35}, {"name": "Side-by-side", "cft": 55}]'::jsonb, '[]'::jsonb),
  ('stove', 'din', 'Gas stove', 17, '[{"name": "2-burner", "cft": 3}, {"name": "3 / 4-burner", "cft": 4}, {"name": "Built-in hob", "cft": 4}]'::jsonb, '[{"code": "un", "label": "Uninstall", "price": null}, {"code": "re", "label": "Reinstall", "price": null}]'::jsonb),
  ('cyl', 'din', 'Gas cylinder', 18, '[{"name": "Filled", "cft": 3}, {"name": "Empty", "cft": 3}]'::jsonb, '[]'::jsonb),
  ('micro', 'din', 'Microwave / OTG', 19, '[{"name": "Standard", "cft": 5}]'::jsonb, '[]'::jsonb),
  ('ro', 'din', 'Water purifier', 20, '[{"name": "Standard", "cft": 3}]'::jsonb, '[{"code": "un", "label": "Uninstall", "price": null}, {"code": "re", "label": "Reinstall", "price": null}]'::jsonb),
  ('chim', 'din', 'Kitchen chimney', 21, '[{"name": "Standard", "cft": 6}]'::jsonb, '[{"code": "un", "label": "Uninstall", "price": null}, {"code": "re", "label": "Reinstall", "price": null}]'::jsonb),
  ('ac', 'app', 'AC', 22, '[{"name": "Split", "cft": 12}, {"name": "Window", "cft": 15}]'::jsonb, '[{"code": "un", "label": "Uninstall", "price": null}, {"code": "re", "label": "Reinstall", "price": null}, {"code": "gas", "label": "Gas top-up", "price": null}]'::jsonb),
  ('wm', 'app', 'Washing machine', 23, '[{"name": "Top load", "cft": 20}, {"name": "Front load", "cft": 22}, {"name": "Semi-automatic", "cft": 20}]'::jsonb, '[{"code": "un", "label": "Uninstall", "price": null}, {"code": "re", "label": "Reinstall", "price": null}]'::jsonb),
  ('gey', 'app', 'Geyser', 24, '[{"name": "Storage", "cft": 4}, {"name": "Instant", "cft": 3}]'::jsonb, '[{"code": "un", "label": "Uninstall", "price": null}, {"code": "re", "label": "Reinstall", "price": null}]'::jsonb),
  ('cool', 'app', 'Air cooler', 25, '[{"name": "Personal", "cft": 8}, {"name": "Desert", "cft": 14}]'::jsonb, '[]'::jsonb),
  ('fan', 'app', 'Fan', 26, '[{"name": "Ceiling", "cft": 2}, {"name": "Pedestal / table", "cft": 4}]'::jsonb, '[{"code": "un", "label": "Uninstall", "price": null}, {"code": "re", "label": "Reinstall", "price": null}]'::jsonb),
  ('inv', 'app', 'Inverter + battery', 27, '[{"name": "Single battery", "cft": 8}, {"name": "Double battery", "cft": 14}]'::jsonb, '[{"code": "un", "label": "Disconnect", "price": null}, {"code": "re", "label": "Reconnect", "price": null}]'::jsonb),
  ('dw', 'app', 'Dishwasher', 28, '[{"name": "Standard", "cft": 15}]'::jsonb, '[{"code": "un", "label": "Uninstall", "price": null}, {"code": "re", "label": "Reinstall", "price": null}]'::jsonb),
  ('tv', 'ele', 'TV', 29, '[{"name": "Up to 32\"", "cft": 6}, {"name": "40–50\"", "cft": 10}, {"name": "55–65\"", "cft": 14}, {"name": "75\" and above", "cft": 18}]'::jsonb, '[{"code": "un", "label": "Wall unmount", "price": null}, {"code": "re", "label": "Wall mount", "price": null}]'::jsonb),
  ('pc', 'ele', 'Desktop computer', 30, '[{"name": "With monitor", "cft": 6}]'::jsonb, '[]'::jsonb),
  ('prn', 'ele', 'Printer', 31, '[{"name": "Home", "cft": 3}, {"name": "Office", "cft": 8}]'::jsonb, '[]'::jsonb),
  ('music', 'ele', 'Music system / speakers', 32, '[{"name": "Standard", "cft": 6}]'::jsonb, '[]'::jsonb),
  ('cctv', 'ele', 'CCTV / Wi-Fi', 33, '[{"name": "Per camera / router", "cft": 1}]'::jsonb, '[{"code": "un", "label": "Uninstall", "price": null}, {"code": "re", "label": "Reinstall", "price": null}]'::jsonb),
  ('wsd', 'off', 'Workstation desk', 34, '[{"name": "1-seater", "cft": 18}, {"name": "2-seater", "cft": 30}, {"name": "4-seater cluster", "cft": 55}]'::jsonb, '[{"code": "dis", "label": "Dismantle & assemble", "price": null}]'::jsonb),
  ('och', 'off', 'Office chair', 35, '[{"name": "Revolving", "cft": 7}, {"name": "Visitor", "cft": 5}]'::jsonb, '[]'::jsonb),
  ('conf', 'off', 'Conference table', 36, '[{"name": "6-seater", "cft": 35}, {"name": "8-seater", "cft": 45}, {"name": "12-seater", "cft": 70}]'::jsonb, '[{"code": "dis", "label": "Dismantle & assemble", "price": null}]'::jsonb),
  ('cab', 'off', 'Filing cabinet', 37, '[{"name": "2-drawer", "cft": 10}, {"name": "4-drawer", "cft": 18}, {"name": "Steel almirah", "cft": 30}]'::jsonb, '[]'::jsonb),
  ('rec', 'off', 'Reception desk', 38, '[{"name": "Standard", "cft": 35}]'::jsonb, '[{"code": "dis", "label": "Dismantle & assemble", "price": null}]'::jsonb),
  ('srv', 'off', 'Server rack', 39, '[{"name": "Half rack", "cft": 25}, {"name": "Full rack", "cft": 45}]'::jsonb, '[{"code": "un", "label": "Disconnect", "price": null}, {"code": "re", "label": "Reconnect", "price": null}]'::jsonb),
  ('car', 'veh', 'Car', 40, '[{"name": "Hatchback", "cft": 0}, {"name": "Sedan", "cft": 0}, {"name": "SUV / MUV", "cft": 0}, {"name": "Luxury", "cft": 0}]'::jsonb, '[{"code": "enc", "label": "Enclosed carrier", "price": null}]'::jsonb),
  ('bike', 'veh', 'Two-wheeler', 41, '[{"name": "Scooter", "cft": 0}, {"name": "Bike up to 200cc", "cft": 0}, {"name": "Premium bike", "cft": 0}]'::jsonb, '[]'::jsonb),
  ('box', 'oth', 'Cartons', 42, '[{"name": "Small", "cft": 3}, {"name": "Medium", "cft": 4}, {"name": "Large", "cft": 6}]'::jsonb, '[]'::jsonb),
  ('study', 'oth', 'Study table', 43, '[{"name": "Standard", "cft": 18}, {"name": "With hutch", "cft": 25}]'::jsonb, '[{"code": "dis", "label": "Dismantle & assemble", "price": null}]'::jsonb),
  ('tread', 'oth', 'Treadmill', 44, '[{"name": "Manual", "cft": 20}, {"name": "Motorised", "cft": 30}]'::jsonb, '[{"code": "dis", "label": "Dismantle & assemble", "price": null}]'::jsonb),
  ('gym', 'oth', 'Exercise cycle / gym', 45, '[{"name": "Cycle", "cft": 12}, {"name": "Multi-gym", "cft": 40}]'::jsonb, '[{"code": "dis", "label": "Dismantle & assemble", "price": null}]'::jsonb),
  ('cyc', 'oth', 'Bicycle', 46, '[{"name": "Adult", "cft": 10}, {"name": "Kids", "cft": 6}]'::jsonb, '[]'::jsonb),
  ('plant', 'oth', 'Plants', 47, '[{"name": "Small pot", "cft": 2}, {"name": "Large pot", "cft": 6}]'::jsonb, '[]'::jsonb),
  ('suit', 'oth', 'Suitcase / trunk', 48, '[{"name": "Suitcase", "cft": 4}, {"name": "Steel trunk", "cft": 8}]'::jsonb, '[]'::jsonb),
  ('piano', 'oth', 'Piano / keyboard', 49, '[{"name": "Keyboard", "cft": 6}, {"name": "Upright piano", "cft": 45}]'::jsonb, '[]'::jsonb);

create table public.mkt_rates (
  city               text not null references public.mkt_cities(city) on update cascade,
  package            text not null check (package in ('economy','standard','premium')),
  per_cft            numeric not null check (per_cft >= 0),
  per_cft_per_km     numeric not null check (per_cft_per_km >= 0),
  min_move           numeric not null check (min_move >= 0),
  updated_at         timestamptz not null default now(),
  primary key (city, package)
);

create table public.mkt_city_prices (
  city            text primary key references public.mkt_cities(city) on update cascade,
  per_floor       numeric check (per_floor >= 0),
  car_local       numeric check (car_local >= 0),
  car_base        numeric check (car_base >= 0),
  car_per_km      numeric check (car_per_km >= 0),
  bike_local      numeric check (bike_local >= 0),
  bike_base       numeric check (bike_base >= 0),
  bike_per_km     numeric check (bike_per_km >= 0),
  damage_cover    numeric check (damage_cover >= 0),
  unpacking       numeric check (unpacking >= 0),
  storage_month   numeric check (storage_month >= 0),
  updated_at      timestamptz not null default now()
);

alter table public.mkt_cities      enable row level security;
alter table public.mkt_catalogue   enable row level security;
alter table public.mkt_rates       enable row level security;
alter table public.mkt_city_prices enable row level security;

do $policies$
declare t text;
begin
  foreach t in array array['mkt_cities','mkt_catalogue','mkt_rates','mkt_city_prices'] loop
    execute format('create policy %I on public.%I for select to anon, authenticated using (true)', t || '_read', t);
    execute format('create policy %I on public.%I for all to authenticated using (public.is_platform_admin()) with check (public.is_platform_admin())', t || '_admin', t);
    execute format('revoke all on public.%I from anon, public', t);
    execute format('grant select on public.%I to anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end
$policies$;

-- Road distance estimate between two served cities: straight line x 1.25,
-- as the design does. Within one city the design uses 15 km; distance
-- does not enter a local price, it is shown only.
create function public.mkt_distance_km(p_from text, p_to text)
returns int
language sql stable security definer set search_path = public
as $$
  select case when p_from = p_to then 15 else (
    select round(2 * 6371 * asin(sqrt(
             power(sin(radians(b.lat - a.lat) / 2), 2)
           + cos(radians(a.lat)) * cos(radians(b.lat))
             * power(sin(radians(b.lng - a.lng) / 2), 2))) * 1.25)::int
      from public.mkt_cities a, public.mkt_cities b
     where a.city = p_from and b.city = p_to) end
$$;

-- The price of a move. Input:
-- {"from_city","to_city","package",
--  "lines":[{"key","variant":0,"qty":1,"services":["dis"]}],
--  "pickup_floor":2,"pickup_lift":false,"drop_floor":4,"drop_lift":true,
--  "addons":{"cover":true,"unpack":false,"storage_months":0}}
-- Output: {"ok":true, km, cft, move, floors, vehicles, services, addons,
-- subtotal, gst, total, advance} or {"ok":false,"reason":...,"detail":...}.
create function public.mkt_quote(p jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_from  text := btrim(coalesce(p->>'from_city', ''));
  v_to    text := btrim(coalesce(p->>'to_city', ''));
  v_pkg   text := coalesce(p->>'package', '');
  v_local boolean;
  v_km    int;
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
  v_km := public.mkt_distance_km(v_from, v_to);
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

  if v_cft > 0 then
    select * into r from mkt_rates where city = v_from and package = v_pkg;
    if r.city is null then
      return jsonb_build_object('ok', false, 'reason', 'no_price', 'detail', 'rates ' || v_from || ' ' || v_pkg);
    end if;
    v_move := greatest(r.min_move,
      round(v_cft * (r.per_cft + case when v_local then 0 else v_km * r.per_cft_per_km end) / 10) * 10);
    n_floors := (case when coalesce((p->>'pickup_lift')::boolean, false) then 0 else greatest(coalesce((p->>'pickup_floor')::int, 0), 0) end)
              + (case when coalesce((p->>'drop_lift')::boolean, false) then 0 else greatest(coalesce((p->>'drop_floor')::int, 0), 0) end);
    if n_floors > 0 then
      if cp.per_floor is null then
        return jsonb_build_object('ok', false, 'reason', 'no_price', 'detail', 'floor charge ' || v_from);
      end if;
      v_floor := n_floors * cp.per_floor;
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
    if cp.damage_cover is null then
      return jsonb_build_object('ok', false, 'reason', 'no_price', 'detail', 'damage cover ' || v_from);
    end if;
    v_add := v_add + cp.damage_cover;
  end if;
  -- Unpacking & arranging is included in Premium (design rule).
  if coalesce((p->'addons'->>'unpack')::boolean, false) and v_pkg <> 'premium' then
    if cp.unpacking is null then
      return jsonb_build_object('ok', false, 'reason', 'no_price', 'detail', 'unpacking ' || v_from);
    end if;
    v_add := v_add + cp.unpacking;
  end if;
  if v_months > 0 then
    if cp.storage_month is null then
      return jsonb_build_object('ok', false, 'reason', 'no_price', 'detail', 'storage ' || v_from);
    end if;
    v_add := v_add + v_months * cp.storage_month;
  end if;

  v_sub := v_move + v_floor + v_veh + v_svc + v_add;
  v_gst := round(v_sub * 0.18, 2);
  v_total := v_sub + v_gst;
  v_adv := least(v_total, greatest(coalesce(rules.advance_min, 0),
                                   round(v_total * coalesce(rules.advance_pct, 0) / 100)));
  return jsonb_build_object(
    'ok', true, 'km', v_km, 'local', v_local, 'cft', v_cft,
    'move', v_move, 'floors', v_floor, 'vehicles', v_veh, 'services', v_svc,
    'addons', v_add, 'subtotal', v_sub, 'gst', v_gst, 'total', v_total,
    'advance', v_adv);
end
$$;

revoke all on function public.mkt_distance_km(text, text) from public;
revoke all on function public.mkt_quote(jsonb) from public;
grant execute on function public.mkt_distance_km(text, text) to anon, authenticated;
grant execute on function public.mkt_quote(jsonb) to anon, authenticated;
-- mkt_quote reads the city rules for the advance; it calls mkt_rules_for
-- as its owner (SECURITY DEFINER), so anon needs no grant on that.

do $postflight$
declare t text;
begin
  foreach t in array array['mkt_cities','mkt_catalogue','mkt_rates','mkt_city_prices'] loop
    if not (select relrowsecurity from pg_class where oid = to_regclass('public.' || t)) then
      raise exception 'POSTFLIGHT: RLS off on %', t;
    end if;
    if has_table_privilege('anon', 'public.' || t, 'insert')
       or has_table_privilege('anon', 'public.' || t, 'update') then
      raise exception 'POSTFLIGHT: anon can write %', t;
    end if;
  end loop;
  if (select count(*) from public.mkt_catalogue) <> 49 then
    raise exception 'POSTFLIGHT: expected 49 catalogue items';
  end if;
  if (select count(*) from public.mkt_rates) <> 0
     or (select count(*) from public.mkt_city_prices) <> 0 then
    raise exception 'POSTFLIGHT: prices must start empty';
  end if;
  if exists (select 1 from public.mkt_catalogue c, jsonb_array_elements(c.services) s
              where s->>'price' is not null) then
    raise exception 'POSTFLIGHT: service prices must start empty';
  end if;
  -- With no prices entered, a quote must refuse, never price at zero.
  if (public.mkt_quote('{"from_city":"Chennai","to_city":"Chennai","package":"standard","lines":[{"key":"fridge","variant":0,"qty":1}]}'::jsonb)->>'reason')
     is distinct from 'no_price' then
    raise exception 'POSTFLIGHT: an unpriced quote did not refuse';
  end if;
end
$postflight$;

commit;
