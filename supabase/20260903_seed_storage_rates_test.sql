-- TEST DATA: per-org storage rate cards.
--
-- Arun, 3 Sept 2026: "this is testing so u keep some random price all 3
-- not the same for all 4" — each of the three orgs gets its OWN card,
-- and the sizes within a card are priced differently from each other.
--
-- THESE ARE TEST FIGURES, NOT PRODUCT DEFAULTS. Storage rates are tenant
-- data (CLAUDE.md, "Warehouse storage — rates are TENANT DATA"): a rate
-- table shipped as a default is one vendor's prices pre-filled as every
-- other vendor's, which is the "No suggested money. Ever." rule. That is
-- why `PricingConfig.storageRates` has no fallback and why
-- kStorageSizeTemplate was deleted the day it was written. Replace these
-- with each vendor's real prices before anyone bills a customer.
--
-- The cards deliberately DISAGREE about whether monthly beats daily,
-- because storage_billing.dart must never compare the two plans:
--   * Bengaluru Tata Ace  — 380/day x 15 = 5,700  vs  4,800/month  (monthly cheaper)
--   * Coimbatore Tata Ace — 260/day x 12 = 3,120  vs  3,600/month  (DAILY cheaper)
-- Both directions are exercised, so a "helpfully" added best-rate
-- suggestion would visibly break one of them.
--
-- min_days also varies (10 / 12 / 15 / 20) so the minimum-stay floor is
-- not tested against a single hardcoded 15.

begin;

do $pre$
declare v_missing text;
begin
  select string_agg(s.slug, ', ') into v_missing
    from (values ('arun-packers-and-couriers'), ('apc-bengaluru'),
                 ('apc-coimbatore')) as s(slug)
   where not exists (select 1 from public.organizations o where o.slug = s.slug);
  if v_missing is not null then
    raise exception 'PREFLIGHT: missing org(s): %', v_missing;
  end if;

  select string_agg(o.slug, ', ') into v_missing
    from public.organizations o
   where o.slug in ('arun-packers-and-couriers','apc-bengaluru','apc-coimbatore')
     and not exists (select 1 from public.pricing_config p where p.org_id = o.id);
  if v_missing is not null then
    raise exception
      'PREFLIGHT: no pricing_config row for: %. Storage rates live inside that jsonb.', v_missing;
  end if;

  raise notice 'PREFLIGHT ok: 3 orgs present, each with a pricing_config row.';
end;
$pre$;

-- jsonb_set on the existing config so survey_cats / cft_ranges / packages
-- are preserved. coalesce guards a null config column.
update public.pricing_config p
   set config = jsonb_set(coalesce(p.config, '{}'::jsonb),
                          '{storage_rates}',
                          '[
  {"size":"Tata Ace","per_day":300,"per_month":4200,"min_days":15},
  {"size":"Pickup 8ft","per_day":350,"per_month":5300,"min_days":15},
  {"size":"Tata 407","per_day":500,"per_month":7000,"min_days":15},
  {"size":"Container 14ft","per_day":750,"per_month":10500,"min_days":20}
]'::jsonb, true)
  from public.organizations o
 where o.id = p.org_id and o.slug = 'arun-packers-and-couriers';

update public.pricing_config p
   set config = jsonb_set(coalesce(p.config, '{}'::jsonb),
                          '{storage_rates}',
                          '[
  {"size":"Tata Ace","per_day":380,"per_month":4800,"min_days":15},
  {"size":"Pickup 8ft","per_day":420,"per_month":5600,"min_days":10},
  {"size":"Tata 407","per_day":620,"per_month":8200,"min_days":15},
  {"size":"Container 17ft","per_day":900,"per_month":12000,"min_days":20}
]'::jsonb, true)
  from public.organizations o
 where o.id = p.org_id and o.slug = 'apc-bengaluru';

update public.pricing_config p
   set config = jsonb_set(coalesce(p.config, '{}'::jsonb),
                          '{storage_rates}',
                          '[
  {"size":"Tata Ace","per_day":260,"per_month":3600,"min_days":12},
  {"size":"Pickup 8ft","per_day":310,"per_month":4400,"min_days":15},
  {"size":"Tata 407","per_day":450,"per_month":6100,"min_days":15},
  {"size":"Container 20ft","per_day":820,"per_month":11200,"min_days":15}
]'::jsonb, true)
  from public.organizations o
 where o.id = p.org_id and o.slug = 'apc-coimbatore';

do $post$
declare
  v_bad text;
  v_dupes int;
begin
  -- (a) each org has exactly 4 sizes
  select string_agg(o.slug || '=' ||
           jsonb_array_length(coalesce(p.config->'storage_rates','[]'::jsonb))::text, ', ')
    into v_bad
    from public.organizations o
    join public.pricing_config p on p.org_id = o.id
   where o.slug in ('arun-packers-and-couriers','apc-bengaluru','apc-coimbatore')
     and jsonb_array_length(coalesce(p.config->'storage_rates','[]'::jsonb)) <> 4;
  if v_bad is not null then
    raise exception 'POSTFLIGHT(a): expected 4 rates per org, got %', v_bad;
  end if;

  -- (b) no two orgs share a rate card - the whole point of the exercise
  select count(*) into v_dupes from (
    select p.config->'storage_rates' as card
      from public.organizations o
      join public.pricing_config p on p.org_id = o.id
     where o.slug in ('arun-packers-and-couriers','apc-bengaluru','apc-coimbatore')
     group by 1 having count(*) > 1) z;
  if v_dupes > 0 then
    raise exception 'POSTFLIGHT(b): % rate card(s) shared between orgs.', v_dupes;
  end if;

  -- (c) the other pricing_config sections survived the jsonb_set
  select string_agg(o.slug, ', ') into v_bad
    from public.organizations o
    join public.pricing_config p on p.org_id = o.id
   where o.slug in ('arun-packers-and-couriers','apc-bengaluru','apc-coimbatore')
     and (p.config->'survey_cats' is null or p.config->'cft_ranges' is null);
  if v_bad is not null then
    raise exception
      'POSTFLIGHT(c): survey_cats/cft_ranges lost on: %. jsonb_set should have preserved them.', v_bad;
  end if;

  raise notice 'POSTFLIGHT ok: 3 distinct 4-size rate cards, other pricing sections intact.';
end;
$post$;

select o.slug,
       r->>'size' as size,
       (r->>'per_day')::numeric  as per_day,
       (r->>'per_month')::numeric as per_month,
       (r->>'min_days')::int      as min_days
  from public.organizations o
  join public.pricing_config p on p.org_id = o.id
  cross join lateral jsonb_array_elements(p.config->'storage_rates') r
 where o.slug in ('arun-packers-and-couriers','apc-bengaluru','apc-coimbatore')
 order by o.created_at, (r->>'per_day')::numeric;

commit;
