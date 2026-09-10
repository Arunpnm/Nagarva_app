-- CFT slab defaults -> rate_card_rules
--
-- Arun, 9 Sept 2026. The band table that fired during the 9 Sept flow test
-- ("2 BHK Small · 4 crew · 14 Ft" at 362 CFT) is wrong, and it lives in the
-- wrong place. This migration makes `rate_card_rules` the home for it.
--
-- ==========================================================================
-- READ THIS BEFORE RUNNING: THERE ARE THREE BAND TABLES TODAY, NOT TWO
-- ==========================================================================
--
-- The brief for this migration said the slabs are hardcoded in Dart and that
-- deleting the Dart table completes the cut-over. Verified against the live
-- database, that is only two thirds of the picture:
--
--   1. `lib/backend/pricing_defaults.dart:359-390` — `kDefaultCftRanges` +
--      `kDefaultPackages`, two const lists joined by package NAME. Documented
--      in that file as a per-key FALLBACK, not the live source.
--   2. `pricing_config.config->'cft_ranges'` + `->'packages'` — **14 + 14
--      entries in ALL THREE ORGS**, byte-identical to (1) because
--      `20260728_pricing_config_survey_seed.sql` copied the constants in.
--      **This is what actually resolved 362 CFT during the flow test.**
--   3. `rate_card_rules` — 0 rows. What this migration fills.
--
-- So deleting the Dart constants alone changes nothing observable: the wrong
-- bands keep firing from the jsonb in all three orgs. The jsonb copies have
-- to go in the same cut-over, and the Settings slabs editor
-- (`lib/settings_page/survey_pricing_page.dart`) writes that jsonb, so it
-- has to move or retire too.
--
-- This migration deliberately does NOT clear the jsonb. Clearing it while the
-- app still reads it — and before any Dart reads `rate_card_rules` — leaves
-- every org with no bands at all. That is the `kServerSideOrderIds` outage
-- shape: remove the old source before the new one is wired, and the feature
-- dies in production. The jsonb teardown belongs in a follow-up migration
-- that ships WITH the Dart cut-over, after this one is confirmed live.
--
-- ==========================================================================
-- WHAT THE OLD BANDS GOT WRONG
-- ==========================================================================
--
-- Observed live, 9 Sept 2026 flow test:
--   362 CFT -> "2 BHK Small · 4 crew · 14 Ft"   should be 1 BHK Big (331-450)
--   260 CFT -> "1 BHK Big · 4 crew · 10 Ft"     should be 1 BHK Medium (241-330), 407
--    93 CFT -> "1 RK / Studio · 2 crew · 7 Ft"  should be Micro Shifting (0-100), Tata Ace
--
-- (The brief recalled 260 CFT as emitting "14 Ft"; the live run emitted
-- "10 Ft". Either way it is not a class the fleet runs.)
--
-- The old table also emits "7 Ft", "8 Ft", "10 Ft" and compound strings like
-- "19 Ft + 14 Ft" — none of which are vehicle classes this business uses.
--
-- ==========================================================================
-- VEHICLE CLASS — WHY A NEW COLUMN AND NOT `vehicle_type`
-- ==========================================================================
--
-- `vehicle_type` already exists on four tables carrying THREE different
-- meanings, so reusing it here would deepen an existing ambiguity:
--
--   * `vehicles.vehicle_type`     — free text the vendor types into
--     `fleet_page/vehicle_detail_sheet.dart:356` (a plain text field, no
--     dropdown, no validation). Live values: 'Tata Ace', 'Eicher 14ft',
--     'Tempo 14 Ft' — two spellings of one class, neither matching a band.
--   * `quotations.vehicle_type` / `orders.vehicle_type` — means
--     **dedicated | shared** (see `components/quote_pdf.dart:62`), a
--     transport MODE. Unrelated to size.
--   * `rate_card_rules.vehicle_type` — unused, 0 rows.
--
-- And the band's vehicle output does not go to any of them: it lands in
-- `quotations.suggested_vehicle` / `chosen_vehicle` as free text that nothing
-- ever compares against the fleet. There is no join, no matching, no
-- validation anywhere in `lib/` today — the suggestion is display-only.
--
-- So this migration adds `vehicle_class` to BOTH sides:
--   * `rate_card_rules.vehicle_class` — what the band SUGGESTS.
--   * `vehicles.vehicle_class`        — what a truck DECLARES, nullable.
--
-- `vehicles.vehicle_type` is left exactly as it is. A vendor keeps calling
-- their truck "Eicher 14ft" and is never asked to rename it to match our
-- bands; they optionally tag it `14 ft` once. Existing fleet rows get NULL,
-- which means "not declared" and is never guessed from the free-text name —
-- guessing is how 'Tempo 14 Ft' and 'Eicher 14ft' would silently become the
-- same or different things depending on whitespace.
--
-- No CHECK constraint pins the class vocabulary: a vendor whose fleet is
-- built on other classes must be able to author their own. If a controlled
-- list is wanted later it should be a per-org `vehicle_classes` table, not a
-- CHECK that ships one business's trucks to every tenant.
--
-- ==========================================================================
-- §52 — NO MONEY ON ANY OF THIS
-- ==========================================================================
--
-- house_type, the CFT bands, vehicle class and crew are OPERATIONAL facts, so
-- seeding them is correct and is not a suggested price. Every money column on
-- every seeded row stays NULL or zero: `per_cft_rate`, `base_amount`,
-- `per_km_rate`, `min_charge`. Asserted in POSTFLIGHT, not merely intended.
--
-- Crew figures are proposals. Arun overwrites them per org.

begin;

-- ==========================================================================
-- PREFLIGHT — raises, never skips
-- ==========================================================================
do $pre$
declare
  v_orgs int;
  v_rules int;
begin
  -- Seeding bands into a table that already holds some risks overlapping an
  -- existing vendor-authored row, which is the exact ambiguity the exclusion
  -- constraint below exists to prevent. Stop rather than merge.
  select count(*) into v_rules from public.rate_card_rules;
  if v_rules <> 0 then
    raise exception
      'PREFLIGHT: rate_card_rules already holds % row(s). This migration seeds a fresh band table and will not merge into existing rules. Review them first.',
      v_rules;
  end if;

  select count(*) into v_orgs from public.organizations
   where slug in ('arun-packers-and-couriers','apc-bengaluru','apc-coimbatore');
  if v_orgs <> 3 then
    raise exception
      'PREFLIGHT: expected 3 seed orgs (arun-packers-and-couriers, apc-bengaluru, apc-coimbatore), found %.',
      v_orgs;
  end if;
end
$pre$;

-- ==========================================================================
-- btree_gist — REQUIRED, AND IT IS NOT INSTALLED ON THIS DATABASE
-- ==========================================================================
-- The exclusion constraint below mixes `card_id with =` (a uuid, equality)
-- against a range `with &&`. Core GiST has no operator class for uuid, so
-- without btree_gist the ALTER TABLE fails with "data type uuid has no
-- default operator class for access method gist".
--
-- Verified 9 Sept 2026 against THIS database, and the catalogue matters:
--   * `pg_extension`            -> btree_gist ABSENT. This is the question.
--   * `pg_available_extensions` -> btree_gist 1.7 present. This is NOT.
-- "Available to install" and "installed" are different states; an earlier
-- draft of this file's report confused them. Same failure shape as reading
-- pg_constraint to ask about uniqueness — see CLAUDE.md's wrong-catalogue
-- convention, which now carries both instances.
-- Confirming the consequence rather than reasoning about it: a count of GiST
-- opclasses over uuid returns 0 on this database today.
--
-- SCHEMA. Supabase installs extensions into `extensions`, not `public` —
-- pg_stat_statements, pgcrypto and uuid-ossp all live there. A bare
-- CREATE EXTENSION would land btree_gist in public against that convention,
-- so it is placed explicitly.
--
-- The postgres role's own search_path (pg_db_role_setting) is already
-- `"$user", public, extensions`, so the opclass resolves for the SQL editor.
-- It is set LOCAL here anyway so the migration does not depend on who runs
-- it — a migration runner with a stripped search_path would otherwise fail
-- at the ALTER TABLE with an error that names the opclass, not the cause.
-- Every object in this file is schema-qualified, so this cannot change what
-- anything else resolves to.
set local search_path = public, extensions, pg_catalog;

create extension if not exists btree_gist with schema extensions;

do $ext$
begin
  if not exists (select 1 from pg_extension where extname = 'btree_gist') then
    raise exception
      'btree_gist is not installed and CREATE EXTENSION did not take. The exclusion constraint cannot be built without it. Install it as a superuser first: create extension btree_gist with schema extensions;';
  end if;
end
$ext$;

-- ==========================================================================
-- COLUMNS
-- ==========================================================================
alter table public.rate_card_rules
  add column if not exists suggested_crew integer,
  add column if not exists house_type     text,
  add column if not exists vehicle_class  text,
  -- The brief asked for "no two ACTIVE rows in the same rate card overlap".
  -- rate_card_rules had no active flag at all — only `rate_cards.active`
  -- exists — so a rule could not be retired without deleting it. Added here
  -- because the exclusion constraint below is scoped to it.
  add column if not exists active         boolean not null default true;

alter table public.vehicles
  add column if not exists vehicle_class  text;

comment on column public.rate_card_rules.suggested_crew is
  'Proposed crew headcount for this band. Operational, not money. Vendor-editable.';
comment on column public.rate_card_rules.house_type is
  'Band label shown to the surveyor, e.g. "1 BHK Big". Vendor-editable.';
comment on column public.rate_card_rules.vehicle_class is
  'Vehicle CLASS this band suggests, e.g. "407", "14 ft". Matched against '
  'vehicles.vehicle_class, never against the free-text vehicles.vehicle_type.';
comment on column public.rate_card_rules.vehicle_type is
  'SUPERSEDED for band purposes by vehicle_class. Left NULL on seeded rows. '
  'Do not reintroduce as the band output — see this migration header.';
comment on column public.vehicles.vehicle_class is
  'Optional class tag linking this truck to a rate_card_rules band. NULL means '
  'the vendor has not declared one; it is never inferred from vehicle_type.';

-- ==========================================================================
-- CONSTRAINTS
-- ==========================================================================

-- A band whose ceiling is below its floor matches nothing and reads as a typo.
alter table public.rate_card_rules
  drop constraint if exists rate_card_rules_cft_order_chk;
alter table public.rate_card_rules
  add constraint rate_card_rules_cft_order_chk
  check (max_cft is null or min_cft is null or max_cft >= min_cft);

-- Crew is a headcount, not a rate. Zero or negative is meaningless.
alter table public.rate_card_rules
  drop constraint if exists rate_card_rules_crew_chk;
alter table public.rate_card_rules
  add constraint rate_card_rules_crew_chk
  check (suggested_crew is null or suggested_crew > 0);

-- THE ONE THAT MATTERS. Two active rows in one card whose CFT ranges overlap
-- means two rows match a single lookup and the winner is whichever the
-- planner returned first — arbitrary, and invisible until a vendor notices a
-- quote suggesting the wrong truck. The source table this replaces had
-- exactly that defect: 4 BHK Small was authored as 1051-1300 while 3 BHK Big
-- held 1001-1150, so every total from 1051 to 1150 matched both.
--
-- Ranges are inclusive on both ends ('[]'); a NULL max_cft yields an
-- unbounded-above range, which is what the open-ended top band needs.
alter table public.rate_card_rules
  drop constraint if exists rate_card_rules_no_overlap;
alter table public.rate_card_rules
  add constraint rate_card_rules_no_overlap
  exclude using gist (
    card_id with =,
    numrange(min_cft, max_cft, '[]') with &&
  ) where (active and min_cft is not null);

-- ==========================================================================
-- SEED — one default card per org, 14 bands each
-- ==========================================================================
-- `service` and `order_type` keep their column defaults ('home_shifting',
-- 'local'). Worth knowing before the Dart reader is written: if the lookup
-- filters on order_type, an outstation job will match nothing until a second
-- card is authored. The band lookup should ignore order_type.
with card as (
  insert into public.rate_cards (org_id, name, code, card_type, is_default, active, notes)
  select o.id, 'Standard CFT slabs', 'STD-CFT', 'standard', true, true,
         'Seeded 9 Sept 2026. CFT band -> house type, vehicle class, crew. '
         'No pricing on these rows; the vendor sets their own rates.'
    from public.organizations o
   where o.slug in ('arun-packers-and-couriers','apc-bengaluru','apc-coimbatore')
  returning id, org_id
),
bands (min_cft, max_cft, house_type, vehicle_class, suggested_crew) as (
  values
    (   0::numeric,  100::numeric, 'Micro Shifting', 'Tata Ace',  2),
    ( 101,           180,          '1 RK/Studio',    'Tata Ace',  2),
    ( 181,           240,          '1 BHK Small',    'Bolero',    3),
    ( 241,           330,          '1 BHK Medium',   '407',       3),
    ( 331,           450,          '1 BHK Big',      '14 ft',     4),
    ( 451,           520,          '2 BHK Small',    '14 ft',     4),
    ( 521,           650,          '2 BHK Medium',   '17 ft',     5),
    ( 651,           720,          '2 BHK Big',      '17 ft',     5),
    ( 721,           820,          '3 BHK Small',    '19 ft',     6),
    ( 821,          1000,          '3 BHK Medium',   '19 ft',     6),
    (1001,          1150,          '3 BHK Big',      '22 ft',     7),
    -- Authored as 1051 in the source, which overlapped 3 BHK Big's 1001-1150.
    -- Read as a typo for 1151 and corrected; the exclusion constraint above
    -- would have refused the original.
    (1151,          1300,          '4 BHK Small',    '32 ft',     8),
    (1301,          1500,          '4 BHK Medium',   '32 ft',     8),
    -- Open-ended on purpose. The source stopped at 1650, which left every
    -- total from 1651 upward matching no band at all.
    (1501,          null,          '4 BHK Big',      '32 ft',    10)
)
insert into public.rate_card_rules
  (org_id, card_id, min_cft, max_cft, house_type, vehicle_class, suggested_crew,
   base_amount, per_km_rate, per_cft_rate, min_charge, vehicle_type, active)
select c.org_id, c.id, b.min_cft, b.max_cft, b.house_type, b.vehicle_class, b.suggested_crew,
       0, 0, 0, 0, null, true
  from card c cross join bands b;

-- ==========================================================================
-- POSTFLIGHT — assertions inside the transaction
-- ==========================================================================
do $post$
declare
  v_cards int;
  v_rules int;
  v_bad   int;
  v_txt   text;
begin
  select count(*) into v_cards from public.rate_cards where code = 'STD-CFT';
  if v_cards <> 3 then
    raise exception 'POSTFLIGHT: expected 3 seeded rate cards, found %.', v_cards;
  end if;

  -- Derived from the number of cards actually seeded, not the literal 42, so
  -- a fourth org later makes this assert 56 rather than failing for the wrong
  -- reason and sending someone hunting a seeding bug that isn't there.
  select count(*) into v_rules from public.rate_card_rules;
  if v_rules <> v_cards * 14 then
    raise exception 'POSTFLIGHT: expected % band rows (14 x % card(s)), found %.',
      v_cards * 14, v_cards, v_rules;
  end if;

  -- Every band must carry its operational payload. A NULL house_type or
  -- vehicle_class renders as a blank suggestion, which reads to a surveyor as
  -- "no recommendation" rather than "misconfigured".
  select count(*) into v_bad from public.rate_card_rules
   where house_type is null or vehicle_class is null or suggested_crew is null;
  if v_bad > 0 then
    raise exception 'POSTFLIGHT: % seeded row(s) missing house_type, vehicle_class or suggested_crew.', v_bad;
  end if;

  -- §52. Asserted, not assumed.
  select count(*) into v_bad from public.rate_card_rules
   where coalesce(base_amount,0)  <> 0
      or coalesce(per_km_rate,0)  <> 0
      or coalesce(per_cft_rate,0) <> 0
      or coalesce(min_charge,0)   <> 0;
  if v_bad > 0 then
    raise exception
      'POSTFLIGHT: % seeded row(s) carry a non-zero money value. Bands are operational; the vendor sets every rate.', v_bad;
  end if;

  -- vehicle_type must stay NULL on band rows — see the header. If a future
  -- edit starts writing it, the band has two vehicle outputs that can differ.
  select count(*) into v_bad from public.rate_card_rules where vehicle_type is not null;
  if v_bad > 0 then
    raise exception 'POSTFLIGHT: % band row(s) wrote vehicle_type. Use vehicle_class.', v_bad;
  end if;

  -- CONTIGUITY: the top of one band and the bottom of the next must differ by
  -- exactly 1. A gap means some CFT total silently matches nothing.
  select count(*), string_agg(format('card %s: %s -> %s', card_id, max_cft, next_min), '; ')
    into v_bad, v_txt
    from (
      select card_id, max_cft,
             lead(min_cft) over (partition by card_id order by min_cft) as next_min
        from public.rate_card_rules
       where active
    ) t
   where next_min is not null and next_min <> max_cft + 1;
  if v_bad > 0 then
    raise exception 'POSTFLIGHT: % non-contiguous band boundar(ies): %', v_bad, v_txt;
  end if;

  -- Exactly one open-ended band per card, and it must be the highest. Two
  -- open-ended rows overlap by definition; an open-ended row that is not the
  -- highest swallows every band above it.
  select count(*) into v_bad
    from (
      select card_id
        from public.rate_card_rules
       where active
       group by card_id
      having count(*) filter (where max_cft is null) <> 1
    ) t;
  if v_bad > 0 then
    raise exception 'POSTFLIGHT: % card(s) do not have exactly one open-ended band.', v_bad;
  end if;

  select count(*) into v_bad
    from public.rate_card_rules r
   where r.active and r.max_cft is null
     and r.min_cft <> (select max(r2.min_cft) from public.rate_card_rules r2
                        where r2.card_id = r.card_id and r2.active);
  if v_bad > 0 then
    raise exception 'POSTFLIGHT: % open-ended band(s) are not the highest band in their card.', v_bad;
  end if;

  -- The exclusion constraint enforces non-overlap on write; assert it exists
  -- by shape so a later edit cannot quietly drop it and leave the seed intact.
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.rate_card_rules'::regclass
       and conname  = 'rate_card_rules_no_overlap'
       and contype  = 'x'
  ) then
    raise exception 'POSTFLIGHT: the no-overlap exclusion constraint is missing.';
  end if;

  -- btree_gist, asserted against pg_extension — the catalogue that answers
  -- "is it installed". pg_available_extensions answers "could it be", which
  -- is a different question and would pass on a database where the constraint
  -- above could not exist.
  if not exists (select 1 from pg_extension where extname = 'btree_gist') then
    raise exception 'POSTFLIGHT: btree_gist is not present in pg_extension.';
  end if;

  -- And by behaviour, not just the flag: the constraint above is only
  -- enforceable if a GiST operator class over uuid actually resolved. This
  -- count is 0 on a database without btree_gist.
  select count(*) into v_bad
    from pg_opclass oc join pg_am am on am.oid = oc.opcmethod
   where am.amname = 'gist' and oc.opcintype = 'uuid'::regtype;
  if v_bad = 0 then
    raise exception
      'POSTFLIGHT: no GiST operator class over uuid exists, so rate_card_rules_no_overlap cannot be enforcing anything.';
  end if;
end
$post$;

commit;

-- ==========================================================================
-- ROLLBACK
-- ==========================================================================
-- Removes only what this migration added. The jsonb bands in pricing_config
-- are untouched by this file, so rolling back returns the app to exactly the
-- behaviour it has today.
-- begin;
--   delete from public.rate_card_rules
--    where card_id in (select id from public.rate_cards where code = 'STD-CFT');
--   delete from public.rate_cards where code = 'STD-CFT';
--   alter table public.rate_card_rules
--     drop constraint if exists rate_card_rules_no_overlap,
--     drop constraint if exists rate_card_rules_cft_order_chk,
--     drop constraint if exists rate_card_rules_crew_chk;
--   alter table public.rate_card_rules
--     drop column if exists suggested_crew,
--     drop column if exists house_type,
--     drop column if exists vehicle_class,
--     drop column if exists active;
--   alter table public.vehicles drop column if exists vehicle_class;
-- commit;
