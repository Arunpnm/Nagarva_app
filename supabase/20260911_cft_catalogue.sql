-- =====================================================================
-- 20260911_cft_catalogue.sql                                    PART A
--
-- The CFT catalogue: a platform-level default list, a per-tenant copy,
-- and a COPY-ON-CREATE seeder. This is the missing link in the chain
--   photos -> item names -> catalogue match -> CFT total -> vehicle/crew
-- whose downstream half already works.
--
-- COPY-ON-CREATE, NOT FALLBACK-AT-READ.
-- A new org gets its own rows at creation; from then on it owns them.
-- There is deliberately NO read-time union of defaults and overrides --
-- that is the two-sources-one-value pattern this project has removed
-- four times (duplicate CFT bands, the two survey tables, field
-- expenses, the five outstanding formulas). One reader, one table:
-- `cft_catalogue` scoped to the org. `cft_catalogue_defaults` is a
-- SEED, never a fallback, and is read by exactly one function.
-- Consequence, stated so nobody is surprised: a central catalogue
-- change reaches NEW orgs only. Existing tenants keep what they have,
-- which is the point -- a vendor's catalogue is theirs.
--
-- §52 -- NO MONEY ON EITHER TABLE.
-- `cft` is cubic feet. Cubic feet is physics: a double-door fridge
-- displaces the same volume for every vendor in India, so seeding it is
-- correct and required. There is no price, rate, charge or amount
-- column on either table, and the postflight ASSERTS their absence so
-- a future migration cannot quietly add one. If you find yourself
-- adding one: stop and ask.
--
-- WHERE THE SEED DATA COMES FROM -- measured, not invented.
-- All 110 lines are lifted from the catalogue already live in
-- `pricing_config.config->'survey_cats'` and rendering on the public
-- survey page today. It is the real Indian household inventory this
-- product already asks customers to pick from, so it is proven rather
-- than imagined. Flattened from {item, subs[{label, cft}]} to one row
-- per selectable line, named "Item - Variant". En dashes normalised to
-- hyphens to keep this file ASCII.
--
-- NOT RUN. File only.
-- =====================================================================

begin;

set local search_path = public, pg_catalog;

-- ---------------------------------------------------------------------
-- PREFLIGHT. Raises; never skips.
-- ---------------------------------------------------------------------
do $$
begin
  if to_regclass('public.organizations') is null then
    raise exception 'public.organizations is missing.';
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='current_org_ids') then
    raise exception
      'current_org_ids() is missing; the RLS policy below depends on it.';
  end if;
  -- Re-running must not double-seed. The seeder is ON CONFLICT DO
  -- NOTHING, but a pre-existing table with a DIFFERENT shape would make
  -- that silently wrong, so refuse rather than adapt.
  if to_regclass('public.cft_catalogue') is not null
     and not exists (select 1 from information_schema.columns
                      where table_schema='public' and table_name='cft_catalogue'
                        and column_name='is_custom') then
    raise exception
      'public.cft_catalogue exists with an unexpected shape (no is_custom). '
      'Inspect it before re-running this migration.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. PLATFORM DEFAULTS -- no org_id, by design.
-- ---------------------------------------------------------------------
create table if not exists public.cft_catalogue_defaults (
  id          uuid primary key default gen_random_uuid(),
  name        text    not null,
  category    text    not null,
  cft         numeric not null check (cft > 0),
  sort_order  int     not null default 0,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  constraint cft_catalogue_defaults_uniq unique (category, name)
);

comment on table public.cft_catalogue_defaults is
  'Platform-level seed catalogue. Read ONLY by seed_cft_catalogue_for_org(). '
  'Never read at query time -- a new org is COPIED from here at creation and '
  'owns its rows thereafter. No price/rate column, ever (§52).';

-- Read-only to signed-in users, invisible to anon and PUBLIC.
-- RLS as well as grants: this project's linter flags any public table
-- without it, and a grant alone would leave the table exposed the
-- moment someone adds a permissive default privilege.
alter table public.cft_catalogue_defaults enable row level security;

drop policy if exists cft_defaults_read on public.cft_catalogue_defaults;
create policy cft_defaults_read
  on public.cft_catalogue_defaults
  for select to authenticated
  using (true);

revoke all on public.cft_catalogue_defaults from public;
revoke all on public.cft_catalogue_defaults from anon;
grant select on public.cft_catalogue_defaults to authenticated;

-- ---------------------------------------------------------------------
-- 2. PER-TENANT CATALOGUE
-- ---------------------------------------------------------------------
create table if not exists public.cft_catalogue (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  name        text    not null,
  category    text    not null,
  cft         numeric not null check (cft > 0),
  sort_order  int     not null default 0,
  is_custom   boolean not null default false,
  active      boolean not null default true,
  deleted_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.cft_catalogue is
  'Per-tenant CFT catalogue. Seeded by copy at org creation, owned by the '
  'vendor thereafter. THE single source for item CFT -- no read-time union '
  'with cft_catalogue_defaults. is_custom marks a line the vendor added. '
  'No price/rate column, ever (§52).';

comment on column public.cft_catalogue.is_custom is
  'false = copied from the platform defaults; true = the vendor created it. '
  'Purely informational -- both kinds are equally the vendor''s to edit.';

-- A vendor must not end up with two lines of the same name in one
-- category: Part B asks a vision model to return catalogue IDs, and two
-- identical names are a coin flip it should never have to make.
-- Partial, so a soft-deleted line does not block re-adding the name.
create unique index if not exists cft_catalogue_org_name_uniq
  on public.cft_catalogue (org_id, category, name)
  where deleted_at is null;

create index if not exists cft_catalogue_org_active_idx
  on public.cft_catalogue (org_id, active)
  where deleted_at is null;

alter table public.cft_catalogue enable row level security;

drop policy if exists org_isolation on public.cft_catalogue;
create policy org_isolation
  on public.cft_catalogue
  for all to authenticated
  using (org_id in (select current_org_ids()))
  with check (org_id in (select current_org_ids()));

revoke all on public.cft_catalogue from public;
revoke all on public.cft_catalogue from anon;
grant select, insert, update, delete on public.cft_catalogue to authenticated;

-- ---------------------------------------------------------------------
-- 3. SEED THE PLATFORM DEFAULTS -- 110 lines, 5 categories.
--    ON CONFLICT DO NOTHING so re-running is safe.
-- ---------------------------------------------------------------------
insert into public.cft_catalogue_defaults (name, category, cft, sort_order) values
  -- Bedrooms (29)
  ('Air Conditioner - Split AC 1T',    'Bedrooms', 10,  10),
  ('Air Conditioner - Split AC 1.5T',  'Bedrooms', 12,  20),
  ('Air Conditioner - Split AC 2T',    'Bedrooms', 14,  30),
  ('Air Conditioner - Window AC',      'Bedrooms', 15,  40),
  ('Bed - Single',                     'Bedrooms', 30,  50),
  ('Bed - Double',                     'Bedrooms', 45,  60),
  ('Bed - Queen Size',                 'Bedrooms', 55,  70),
  ('Bed - King Size',                  'Bedrooms', 65,  80),
  ('Cabinet & Storage - Small',        'Bedrooms', 15,  90),
  ('Cabinet & Storage - Medium',       'Bedrooms', 25, 100),
  ('Cabinet & Storage - Large',        'Bedrooms', 35, 110),
  ('Chair - 1 Chair',                  'Bedrooms',  5, 120),
  ('Chair - 2 Chairs',                 'Bedrooms', 10, 130),
  ('Chair - Recliner',                 'Bedrooms', 18, 140),
  ('Mattress - Single',                'Bedrooms', 12, 150),
  ('Mattress - Double',                'Bedrooms', 15, 160),
  ('Mattress - Queen',                 'Bedrooms', 18, 170),
  ('Mattress - King',                  'Bedrooms', 20, 180),
  ('Other Appliances - Item',          'Bedrooms', 10, 190),
  ('Table - Bedside Table',            'Bedrooms',  8, 200),
  ('Table - Study Table',              'Bedrooms', 15, 210),
  ('Table - Dressing Table',           'Bedrooms', 20, 220),
  ('Television - Up to 32"',           'Bedrooms',  8, 230),
  ('Television - 32"-50"',             'Bedrooms', 12, 240),
  ('Television - 50"+ LED',            'Bedrooms', 16, 250),
  ('Wardrobe / Almirah - 2 Door',      'Bedrooms', 40, 260),
  ('Wardrobe / Almirah - 3 Door',      'Bedrooms', 55, 270),
  ('Wardrobe / Almirah - Sliding',     'Bedrooms', 60, 280),
  ('Wardrobe / Almirah - 4 Door',      'Bedrooms', 70, 290),

  -- Cartons & Packing (4)
  ('Self Carton Small - Qty',          'Cartons & Packing', 3,  10),
  ('Self Carton Medium - Qty',         'Cartons & Packing', 4,  20),
  ('Gunny Bag - Qty',                  'Cartons & Packing', 5,  30),
  ('Self Carton Large - Qty',          'Cartons & Packing', 6,  40),

  -- Kitchen (18)
  ('Gas Stove / Chimney - Gas Stove',  'Kitchen',  6,  10),
  ('Gas Stove / Chimney - Chimney',    'Kitchen', 10,  20),
  ('Gas Stove / Chimney - Both',       'Kitchen', 16,  30),
  ('Kitchen Appliances - Item',        'Kitchen',  5,  40),
  ('Kitchen Furniture - Cabinet',      'Kitchen', 20,  50),
  ('Kitchen Furniture - Dining',       'Kitchen', 25,  60),
  ('Kitchen Furniture - Island',       'Kitchen', 30,  70),
  ('Microwave - Small',                'Kitchen',  6,  80),
  ('Microwave - Large',                'Kitchen', 10,  90),
  ('Mixer / Grinder - 1',              'Kitchen',  4, 100),
  ('Mixer / Grinder - 2+',             'Kitchen',  8, 110),
  ('Refrigerator - Single Door',       'Kitchen', 15, 120),
  ('Refrigerator - Double Door',       'Kitchen', 20, 130),
  ('Refrigerator - Triple Door',       'Kitchen', 28, 140),
  ('Refrigerator - Side by Side',      'Kitchen', 35, 150),
  ('Utensils & Crockery - 1 Box',      'Kitchen',  6, 160),
  ('Utensils & Crockery - 2 Boxes',    'Kitchen', 12, 170),
  ('Utensils & Crockery - 3+ Boxes',   'Kitchen', 18, 180),

  -- Living Room (29)
  ('Air Conditioner - Split AC',       'Living Room', 12,  10),
  ('Air Conditioner - Window AC',      'Living Room', 15,  20),
  ('Appliances - Item',                'Living Room',  8,  30),
  ('Bar Furniture - Wine Rack',        'Living Room', 15,  40),
  ('Bar Furniture - Bar Cabinet',      'Living Room', 25,  50),
  ('Bookshelf - Small',                'Living Room', 12,  60),
  ('Bookshelf - Medium',               'Living Room', 20,  70),
  ('Bookshelf - Large',                'Living Room', 30,  80),
  ('Cabinet / TV Unit - Small',        'Living Room', 15,  90),
  ('Cabinet / TV Unit - Medium',       'Living Room', 25, 100),
  ('Cabinet / TV Unit - Large',        'Living Room', 35, 110),
  ('Center Table - Small',             'Living Room',  8, 120),
  ('Center Table - Medium',            'Living Room', 12, 130),
  ('Center Table - Large',             'Living Room', 18, 140),
  ('Chair - 1',                        'Living Room',  5, 150),
  ('Chair - 2',                        'Living Room', 10, 160),
  ('Chair - 4',                        'Living Room', 20, 170),
  ('Dining Table - 2 Seater',          'Living Room', 15, 180),
  ('Dining Table - 4 Seater',          'Living Room', 25, 190),
  ('Dining Table - 6 Seater',          'Living Room', 35, 200),
  ('Dining Table - 8 Seater',          'Living Room', 50, 210),
  ('Sofa - 1 Seater',                  'Living Room', 15, 220),
  ('Sofa - 2 Seater',                  'Living Room', 25, 230),
  ('Sofa - 3 Seater',                  'Living Room', 35, 240),
  ('Sofa - L-Shape',                   'Living Room', 60, 250),
  ('Sofa - 5 Seater',                  'Living Room', 70, 260),
  ('Television - Up to 32"',           'Living Room',  8, 270),
  ('Television - 32"-50"',             'Living Room', 12, 280),
  ('Television - 50"+ LED',            'Living Room', 16, 290),

  -- Miscellaneous (30)
  ('Home Appliances - Iron',           'Miscellaneous',  3,  10),
  ('Decorative Items - Small',         'Miscellaneous',  5,  20),
  ('Plants & Pots - Small (<5)',       'Miscellaneous',  5,  30),
  ('Home Appliances - Fan',            'Miscellaneous',  6,  40),
  ('Home Appliances - Vacuum Cleaner', 'Miscellaneous',  8,  50),
  ('Home Appliances - Geyser',         'Miscellaneous',  8,  60),
  ('Suitcases & Bags - 1-2',           'Miscellaneous',  8,  70),
  ('Decorative Items - Medium',        'Miscellaneous', 10,  80),
  ('Kids Vehicle - Toy Car',           'Miscellaneous', 10,  90),
  ('Bicycle - Kids',                   'Miscellaneous', 12, 100),
  ('Kids Vehicle - Cycle',             'Miscellaneous', 12, 110),
  ('Plants & Pots - Medium (5-10)',    'Miscellaneous', 12, 120),
  ('Gym Equipment - Others',           'Miscellaneous', 15, 130),
  ('Musical Instruments - Item',       'Miscellaneous', 15, 140),
  ('Washing Machine - Top Load',       'Miscellaneous', 15, 150),
  ('Suitcases & Bags - 3-5',           'Miscellaneous', 16, 160),
  ('Bicycle - Adult',                  'Miscellaneous', 18, 170),
  ('Kids Vehicle - Scooter',           'Miscellaneous', 18, 180),
  ('Washing Machine - Front Load',     'Miscellaneous', 18, 190),
  ('Decorative Items - Large',         'Miscellaneous', 20, 200),
  ('Gym Equipment - Weights Set',      'Miscellaneous', 20, 210),
  ('Bicycle - Electric',               'Miscellaneous', 22, 220),
  ('Bike / Two Wheeler - Scooter',     'Miscellaneous', 25, 230),
  ('Gym Equipment - Exercise Bike',    'Miscellaneous', 25, 240),
  ('Plants & Pots - Large (10+)',      'Miscellaneous', 25, 250),
  ('Bike / Two Wheeler - Electric Bike','Miscellaneous',28, 260),
  ('Suitcases & Bags - 6+',            'Miscellaneous', 28, 270),
  ('Bike / Two Wheeler - Standard Bike','Miscellaneous',30, 280),
  ('Bike / Two Wheeler - Sports Bike', 'Miscellaneous', 35, 290),
  ('Gym Equipment - Treadmill',        'Miscellaneous', 40, 300)
on conflict (category, name) do nothing;

-- ---------------------------------------------------------------------
-- 4. THE SEEDER -- copy-on-create.
--
-- SECURITY DEFINER because it is called during org creation, before the
-- caller has any membership in the new org, so the org_isolation policy
-- on cft_catalogue would refuse the insert.
-- ---------------------------------------------------------------------
create or replace function public.seed_cft_catalogue_for_org(p_org_id uuid)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare
  v_n integer;
begin
  if p_org_id is null then
    raise exception 'seed_cft_catalogue_for_org: p_org_id is null.';
  end if;
  if not exists (select 1 from organizations where id = p_org_id) then
    raise exception 'seed_cft_catalogue_for_org: org % does not exist.', p_org_id;
  end if;

  insert into cft_catalogue (org_id, name, category, cft, sort_order, is_custom, active)
  select p_org_id, d.name, d.category, d.cft, d.sort_order, false, true
    from cft_catalogue_defaults d
   where d.active
  on conflict (org_id, category, name) where deleted_at is null do nothing;

  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

comment on function public.seed_cft_catalogue_for_org(uuid) is
  'Copies the platform default catalogue into one org. Called at org '
  'creation. COPY-ON-CREATE: after this runs the org owns its rows and '
  'nothing reads cft_catalogue_defaults on its behalf again.';

revoke all on function public.seed_cft_catalogue_for_org(uuid) from public;
revoke all on function public.seed_cft_catalogue_for_org(uuid) from anon;
grant execute on function public.seed_cft_catalogue_for_org(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 5. BACKFILL the three existing orgs.
--    They predate the seeder, so they get the same copy now.
-- ---------------------------------------------------------------------
do $$
declare
  r      record;
  v_n    integer;
begin
  for r in select id, slug from organizations order by created_at loop
    v_n := public.seed_cft_catalogue_for_org(r.id);
    raise notice 'seeded % catalogue lines for %', v_n, r.slug;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- POSTFLIGHT. Asserts the construct, the grants, and §52.
-- ---------------------------------------------------------------------
do $$
declare
  v_defaults  int;
  v_orgs      int;
  v_bad_org   text;
  v_exposed   int;
  v_money     text;
  v_secdef    boolean;
begin
  -- 1. The defaults seeded completely.
  select count(*) into v_defaults from cft_catalogue_defaults;
  if v_defaults <> 110 then
    raise exception
      'cft_catalogue_defaults holds % rows, expected 110.', v_defaults;
  end if;

  -- 2. Every org has a full copy. Derived as (defaults x orgs), not a
  --    hardcoded total, so this assertion survives a fourth org.
  select count(*) into v_orgs from organizations;
  select o.slug into v_bad_org
    from organizations o
    left join (
      select org_id, count(*) n from cft_catalogue
       where deleted_at is null group by org_id
    ) c on c.org_id = o.id
   where coalesce(c.n, 0) <> v_defaults
   limit 1;
  if v_bad_org is not null then
    raise exception
      'org % does not have the full % catalogue lines.', v_bad_org, v_defaults;
  end if;

  -- 3. GRANTS: anon and PUBLIC must hold nothing on the defaults table.
  --    grantee 0 is PUBLIC. Read relacl, not assumptions.
  select count(*) into v_exposed
    from pg_class c, aclexplode(c.relacl) a
   where c.oid = 'public.cft_catalogue_defaults'::regclass
     and (a.grantee = 0 or a.grantee = 'anon'::regrole);
  if v_exposed > 0 then
    raise exception
      'cft_catalogue_defaults grants % privilege(s) to anon or PUBLIC.', v_exposed;
  end if;

  select count(*) into v_exposed
    from pg_class c, aclexplode(c.relacl) a
   where c.oid = 'public.cft_catalogue'::regclass
     and (a.grantee = 0 or a.grantee = 'anon'::regrole);
  if v_exposed > 0 then
    raise exception
      'cft_catalogue grants % privilege(s) to anon or PUBLIC.', v_exposed;
  end if;

  -- 4. RLS on both.
  if not (select relrowsecurity from pg_class
           where oid='public.cft_catalogue_defaults'::regclass) then
    raise exception 'RLS is not enabled on cft_catalogue_defaults.';
  end if;
  if not (select relrowsecurity from pg_class
           where oid='public.cft_catalogue'::regclass) then
    raise exception 'RLS is not enabled on cft_catalogue.';
  end if;

  -- 5. §52 STRUCTURAL GUARD: no money column on either table, now or
  --    later. Cheap to assert, and it turns a rule into a constraint.
  select table_name || '.' || column_name into v_money
    from information_schema.columns
   where table_schema = 'public'
     and table_name in ('cft_catalogue','cft_catalogue_defaults')
     and (column_name ~* '(price|rate|charge|amount|cost|fee)')
   limit 1;
  if v_money is not null then
    raise exception
      '§52: % is a money column on a catalogue table. The catalogue '
      'carries volume, never money.', v_money;
  end if;

  -- 6. The seeder is SECURITY DEFINER, or org creation cannot use it.
  select p.prosecdef into v_secdef
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='seed_cft_catalogue_for_org';
  if v_secdef is distinct from true then
    raise exception 'seed_cft_catalogue_for_org is not SECURITY DEFINER.';
  end if;

  raise notice
    'cft_catalogue: % defaults, % orgs seeded, grants clean, no money columns.',
    v_defaults, v_orgs;
end $$;

commit;

-- =====================================================================
-- STILL TO DO -- named here so it is not discovered later
-- ---------------------------------------------------------------------
-- 1. WIRE THE SEEDER INTO ORG CREATION. `create_org_with_owner()` must
--    call seed_cft_catalogue_for_org(new_org_id). Until it does, a new
--    tenant gets an EMPTY catalogue -- worse than the APC-shaped one,
--    because the survey page would render nothing. This is a one-line
--    change to that function and it is deliberately NOT bundled here:
--    it edits a live signup path and deserves its own reviewable commit.
--    Do it before the invite gate is switched off again.
--
-- 2. RETIRE pricing_config.config->'survey_cats'. Two catalogues now
--    exist for the same thing -- exactly the pattern this project keeps
--    removing -- and that is tolerable ONLY while the new one has no
--    reader. The public survey page and PricingConfig.surveyCats still
--    read the jsonb. Moving them is its own pass; do not leave both live
--    once anything reads cft_catalogue.
--
-- 3. `customer_surveys.rooms` vs `items`: the customer's picks land in
--    `rooms`, in TWO shapes (the current {cat,item,sub,cft,qty} and a
--    legacy {room,items} free-text row from 2 Sept). `items` is NULL on
--    all 7 rows with no writer. Part B defines the shape of `items` and
--    must retire `rooms` in the same move, or there will be three homes.
--
-- ROLLBACK
--   drop function if exists public.seed_cft_catalogue_for_org(uuid);
--   drop table if exists public.cft_catalogue;
--   drop table if exists public.cft_catalogue_defaults;
-- Safe while nothing reads either table. After Part B ships it is not.
-- =====================================================================
