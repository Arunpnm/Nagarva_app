-- =============================================================================
-- 20261031_marketplace_addon_slabs.sql — add-on prices by the move's size
-- =============================================================================
-- HANDED OVER, NOT RUN. Needs 20261030_marketplace_pricing.sql first.
-- One transaction; preflight refuses, postflight asserts and probes.
--
-- Arun, 31 Oct 2026: "the price is not fixed coz it depends upon the
-- volume, for example 1bhk unpacking 1200, if 2bhk then 1600" — and
-- "check the cft slab we have already those data".
--
-- The slabs are NOT redefined here. They are the 14 CFT slabs the product
-- already uses for vehicle and crew suggestions,
-- default_pricing_config()->'cft_ranges' (Micro Shifting up to 80 CFT,
-- 1 RK / Studio up to 155 … 4 BHK Medium up to 1600, 4 BHK Big above). All
-- five orgs carry exactly these today (checked live 31 Oct 2026). A
-- marketplace move is Nagarva's, not a vendor's, so it reads the platform
-- default rather than any one org's copy.
--
-- An add-on (floor charge, damage cover, unpacking, storage per month) is
-- priced per city per slab:
--
--     unpacking, Chennai:  1 BHK Medium  1200
--                          2 BHK Medium  1600
--
-- mkt_addon_price(city, addon, cft):
--   * that city has ANY slab price for the add-on -> the price for the
--     slab the move falls in; a slab left empty gives NO price, so the
--     quote refuses naming the add-on and the slab, instead of borrowing a
--     neighbouring slab's figure (CLAUDE.md: no suggested money);
--   * no slab prices -> the single price in mkt_city_prices, as before;
--   * neither -> no price.
-- The move's CFT comes from the items the customer picked (vehicles
-- excluded), computed on the server. Nothing is seeded.
--
-- mkt_quote() is replaced in place: same signature, same return type
-- (jsonb, now also carrying 'slab'), so CREATE OR REPLACE is enough.
-- mkt_addon_prices(jsonb) is new: what each add-on would cost for this
-- move, for the customer app's add-on screen.
-- =============================================================================

begin;

set local search_path = public, extensions;

do $preflight$
declare
  v_n int;
begin
  if to_regprocedure('public.mkt_quote(jsonb)') is null
     or to_regclass('public.mkt_city_prices') is null then
    raise exception 'PREFLIGHT FAILED: run 20261030_marketplace_pricing.sql first';
  end if;
  if to_regclass('public.mkt_addon_slabs') is not null then
    raise exception 'PREFLIGHT FAILED: mkt_addon_slabs already exists; this migration has run before';
  end if;
  if to_regprocedure('public.default_pricing_config()') is null then
    raise exception 'PREFLIGHT FAILED: default_pricing_config() missing; the CFT slabs live there';
  end if;
  select count(*) into v_n
    from jsonb_array_elements(public.default_pricing_config()->'cft_ranges') r
   where nullif(r->>'pkg', '') is not null;
  if v_n < 2 then
    raise exception 'PREFLIGHT FAILED: default_pricing_config() has % named CFT slabs; expected the 14', v_n;
  end if;
  -- Exactly one open-ended slab, and it is the largest, or "the slab a
  -- move falls in" is not well defined.
  if (select count(*) from jsonb_array_elements(public.default_pricing_config()->'cft_ranges') r
       where r->>'max' is null) <> 1 then
    raise exception 'PREFLIGHT FAILED: the CFT slabs need exactly one open-ended top slab';
  end if;
end
$preflight$;

-- The slab names, in size order.
create function public.mkt_slab_labels()
returns text[]
language sql immutable set search_path = public
as $$
  select array_agg(r->>'pkg' order by (r->>'max')::numeric nulls last)
    from jsonb_array_elements(public.default_pricing_config()->'cft_ranges') r
$$;

-- The slab a move of p_cft falls in: the smallest whose max covers it.
create function public.mkt_slab_for(p_cft numeric)
returns text
language sql immutable set search_path = public
as $$
  select r->>'pkg'
    from jsonb_array_elements(public.default_pricing_config()->'cft_ranges') r
   where r->>'max' is null or (r->>'max')::numeric >= coalesce(p_cft, 0)
   order by (r->>'max')::numeric nulls last
   limit 1
$$;

create table public.mkt_addon_slabs (
  city   text not null references public.mkt_cities(city) on update cascade,
  addon  text not null check (addon in ('per_floor','damage_cover','unpacking','storage_month')),
  slab   text not null check (slab = any (public.mkt_slab_labels())),
  price  numeric not null check (price >= 0),
  updated_at timestamptz not null default now(),
  primary key (city, addon, slab)
);

alter table public.mkt_addon_slabs enable row level security;
create policy mkt_addon_slabs_read on public.mkt_addon_slabs
  for select to anon, authenticated using (true);
create policy mkt_addon_slabs_admin on public.mkt_addon_slabs
  for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
revoke all on public.mkt_addon_slabs from anon, public;
grant select on public.mkt_addon_slabs to anon;
grant select, insert, update, delete on public.mkt_addon_slabs to authenticated;

-- The CFT of the picked items (vehicles excluded). Unknown items and bad
-- lines count as nothing here; mkt_quote is what refuses them.
create function public.mkt_move_cft(p_lines jsonb)
returns numeric
language sql stable security definer set search_path = public
as $$
  select coalesce(sum(
           greatest(coalesce((l->>'qty')::int, 0), 0)
           * coalesce((c.variants -> coalesce((l->>'variant')::int, 0) ->> 'cft')::numeric, 0)), 0)
    from jsonb_array_elements(case when jsonb_typeof(p_lines) = 'array' then p_lines else '[]' end) l
    join mkt_catalogue c on c.key = l->>'key' and c.active and c.cat <> 'veh'
$$;

-- One add-on's price for a move of p_cft in p_city, or NULL.
create function public.mkt_addon_price(p_city text, p_addon text, p_cft numeric)
returns numeric
language plpgsql stable security definer set search_path = public
as $$
declare
  v numeric;
begin
  if p_addon not in ('per_floor','damage_cover','unpacking','storage_month') then
    raise exception 'unknown add-on %', p_addon;
  end if;
  if exists (select 1 from mkt_addon_slabs where city = p_city and addon = p_addon) then
    select price into v from mkt_addon_slabs
     where city = p_city and addon = p_addon and slab = public.mkt_slab_for(p_cft);
    return v;  -- NULL when this slab has no price yet
  end if;
  execute format('select %I from mkt_city_prices where city = $1', p_addon)
     into v using p_city;
  return v;
end
$$;

-- What each add-on costs for this move: {ok, cft, slab, per_floor,
-- damage_cover, unpacking, storage_month}; a NULL price means not offered.
create function public.mkt_addon_prices(p jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_city text := btrim(coalesce(p->>'from_city', ''));
  v_cft  numeric := public.mkt_move_cft(p->'lines');
begin
  if not exists (select 1 from mkt_cities where city = v_city and active) then
    return jsonb_build_object('ok', false, 'reason', 'city_not_served');
  end if;
  return jsonb_build_object(
    'ok', true, 'cft', v_cft, 'slab', public.mkt_slab_for(v_cft),
    'per_floor',     public.mkt_addon_price(v_city, 'per_floor', v_cft),
    'damage_cover',  public.mkt_addon_price(v_city, 'damage_cover', v_cft),
    'unpacking',     public.mkt_addon_price(v_city, 'unpacking', v_cft),
    'storage_month', public.mkt_addon_price(v_city, 'storage_month', v_cft));
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
  v_price numeric;
  v_slab  text;
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

  v_slab := public.mkt_slab_for(v_cft);

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
    'move', v_move, 'floors', v_floor, 'vehicles', v_veh, 'services', v_svc,
    'addons', v_add, 'subtotal', v_sub, 'gst', v_gst, 'total', v_total,
    'advance', v_adv);
end
$$;

revoke all on function public.mkt_slab_labels() from public;
revoke all on function public.mkt_slab_for(numeric) from public;
-- Supabase's default privileges grant every new function in public to
-- anon and authenticated BY NAME, so revoking from PUBLIC alone leaves
-- those grants in place (found when the first live run's postflight
-- refused, 31 Oct 2026). Internal functions name all three.
revoke all on function public.mkt_move_cft(jsonb) from public, anon, authenticated;
revoke all on function public.mkt_addon_price(text, text, numeric) from public, anon, authenticated;
revoke all on function public.mkt_addon_prices(jsonb) from public;
grant execute on function public.mkt_slab_labels() to anon, authenticated;
grant execute on function public.mkt_slab_for(numeric) to anon, authenticated;
grant execute on function public.mkt_addon_prices(jsonb) to anon, authenticated;
-- mkt_move_cft and mkt_addon_price are internal: called only from the
-- SECURITY DEFINER functions above, which run as their owner.

do $postflight$
declare
  v_bad   int;
  v_city  text;
  v_small text;
  v_big   text;
  v_p     numeric;
  v_q     jsonb;
  v_had   boolean;
  v_orig  numeric;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.mkt_addon_slabs'::regclass) then
    raise exception 'POSTFLIGHT: RLS off on mkt_addon_slabs';
  end if;
  if has_table_privilege('anon', 'public.mkt_addon_slabs', 'insert')
     or has_table_privilege('anon', 'public.mkt_addon_slabs', 'update') then
    raise exception 'POSTFLIGHT: anon can write mkt_addon_slabs';
  end if;
  select count(*) into v_bad
    from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
   where p.oid in ('public.mkt_quote(jsonb)'::regprocedure,
                   'public.mkt_addon_price(text,text,numeric)'::regprocedure,
                   'public.mkt_addon_prices(jsonb)'::regprocedure,
                   'public.mkt_move_cft(jsonb)'::regprocedure,
                   'public.mkt_slab_for(numeric)'::regprocedure,
                   'public.mkt_slab_labels()'::regprocedure)
     and a.privilege_type = 'EXECUTE' and a.grantee = 0;
  if v_bad > 0 then
    raise exception 'POSTFLIGHT: PUBLIC can execute a pricing function';
  end if;
  if not has_function_privilege('anon', 'public.mkt_quote(jsonb)', 'execute')
     or not has_function_privilege('anon', 'public.mkt_addon_prices(jsonb)', 'execute') then
    raise exception 'POSTFLIGHT: anon cannot ask for a price';
  end if;
  if has_function_privilege('anon', 'public.mkt_addon_price(text,text,numeric)', 'execute')
     or has_function_privilege('anon', 'public.mkt_move_cft(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.mkt_addon_price(text,text,numeric)', 'execute')
     or has_function_privilege('authenticated', 'public.mkt_move_cft(jsonb)', 'execute') then
    raise exception 'POSTFLIGHT: a client role can call an internal pricing function';
  end if;
  if (select count(*) from mkt_addon_slabs) <> 0 then
    raise exception 'POSTFLIGHT: slabs must start empty';
  end if;

  -- The slab lookup, against the real boundaries.
  if public.mkt_slab_for(0) is distinct from (public.mkt_slab_labels())[1]
     or public.mkt_slab_for(1000000) is distinct from
        (public.mkt_slab_labels())[array_length(public.mkt_slab_labels(), 1)] then
    raise exception 'POSTFLIGHT: mkt_slab_for picks the wrong end slab';
  end if;

  -- Behaviour, all undone: price two slabs for one add-on in a real city
  -- and check a move is priced by its own slab, a slab left empty is
  -- refused rather than borrowed, and without slabs the fixed price
  -- still applies.
  select city into v_city from mkt_cities where active order by city limit 1;
  if v_city is null then
    raise exception 'POSTFLIGHT: no active city to probe with';
  end if;
  v_small := public.mkt_slab_for(100);
  v_big   := public.mkt_slab_for(500);
  if v_small = v_big then
    raise exception 'POSTFLIGHT: 100 and 500 CFT should fall in different slabs';
  end if;

  select true, unpacking into v_had, v_orig from mkt_city_prices where city = v_city;
  v_had := coalesce(v_had, false);
  if v_had then
    update mkt_city_prices set unpacking = 999 where city = v_city;
  else
    insert into mkt_city_prices (city, unpacking) values (v_city, 999);
  end if;
  if public.mkt_addon_price(v_city, 'unpacking', 100) is distinct from 999 then
    raise exception 'POSTFLIGHT: without slabs the fixed price is not used';
  end if;

  insert into mkt_addon_slabs (city, addon, slab, price) values
    (v_city, 'unpacking', v_small, 1200),
    (v_city, 'unpacking', v_big, 1600);
  v_p := public.mkt_addon_price(v_city, 'unpacking', 100);
  if v_p is distinct from 1200 then
    raise exception 'POSTFLIGHT: 100 CFT got %, expected 1200', v_p;
  end if;
  v_p := public.mkt_addon_price(v_city, 'unpacking', 500);
  if v_p is distinct from 1600 then
    raise exception 'POSTFLIGHT: 500 CFT got %, expected 1600', v_p;
  end if;
  v_p := public.mkt_addon_price(v_city, 'unpacking', 1000000);
  if v_p is not null then
    raise exception 'POSTFLIGHT: an unpriced slab borrowed %', v_p;
  end if;

  -- No items is 0 CFT, the smallest slab, which this probe left unpriced:
  -- the customer screen must see "not offered", not the 1200 next door.
  v_q := public.mkt_addon_prices(jsonb_build_object('from_city', v_city, 'lines', '[]'::jsonb));
  if (v_q->>'ok')::boolean is not true
     or v_q->>'slab' is distinct from (public.mkt_slab_labels())[1]
     or v_q->'unpacking' <> 'null'::jsonb then
    raise exception 'POSTFLIGHT: mkt_addon_prices returned %', v_q;
  end if;

  begin
    insert into mkt_addon_slabs (city, addon, slab, price)
    values (v_city, 'unpacking', 'Not a slab', 1);
    raise exception 'POSTFLIGHT: an unknown slab name was accepted';
  exception when check_violation then
    null;
  end;

  -- Undo the probe. Raising rolls everything back anyway; this is for the
  -- success path.
  delete from mkt_addon_slabs where city = v_city;
  if v_had then
    update mkt_city_prices set unpacking = v_orig where city = v_city;
  else
    delete from mkt_city_prices where city = v_city;
  end if;
end
$postflight$;

commit;
