-- ============================================================================
-- 20260801_pricing_config_charge_basis.sql
--
-- Part 8 Rev B, Q3 / item 4 decision: charge basis (lumpsum / per_cft /
-- per_floor / per_trip / per_km / percent_of_declared_value / at_actuals)
-- becomes PER-ORG CONFIGURABLE, seeded from kDefaultChargeFields' current
-- values. Explicitly NOT hardcoded per charge key in Dart — packers price
-- the same service differently (some charge packing per CFT, some
-- lumpsum by house type, some per room), and hardcoding APC's model would
-- be the first complaint from any new vendor.
--
-- This does NOT touch quote_charges (the jsonb column on quotations /
-- orders) at all — that stays schema-free by design, and the value-shape
-- upgrade (plain number = legacy lumpsum, object = {amount,basis,qty,rate})
-- is a Dart read/write change only, no migration needed for it.
--
-- pricing_config.config is jsonb, so no ALTER TABLE is needed — this is a
-- data backfill, not a schema change. Scope deliberately kept to ONLY
-- that: it does NOT touch default_pricing_config() or
-- create_org_with_owner() (20260731_create_org_with_owner.sql), both
-- already confirmed live. Reconstructing either of those large function
-- bodies from memory to add one key, rather than introspecting them
-- fresh first, is exactly the mistake this repo's own conventions warn
-- against — so that half is deliberately NOT in this file. Until a
-- follow-up migration adds charge_basis to default_pricing_config() too
-- (needs `select pg_get_functiondef('public.default_pricing_config'::regproc)`
-- first, not a copy from an earlier session's memory), brand new orgs
-- created after this runs will rely on the same Dart-side per-key
-- fallback PricingConfig already uses for survey_cats/cft_ranges/
-- packages/porter_rates when a section is absent from config — the
-- established pattern for this table, not a new exception.
--
-- RUN THIS FIRST. I have no live database access from this session —
-- everything below assumes pricing_config.config is jsonb (matches every
-- existing read in lib/backend/pricing_defaults.dart) but has NOT been
-- introspected against the live table. Check before running:
--
--   select column_name, data_type
--     from information_schema.columns
--    where table_schema = 'public' and table_name = 'pricing_config'
--    order by ordinal_position;
--
--   select org_id, config ? 'charge_basis' as has_charge_basis
--     from public.pricing_config;
--
-- ---------------------------------------------------------------------------
-- ALLOWED BASES (Rev B): lumpsum, per_cft, per_floor, per_trip, per_km,
-- percent_of_declared_value, at_actuals.
--
-- DEFAULT MAP mirrors this app's ACTUAL current behaviour, not the
-- reference APC web app's — e.g. this app has no odometer/per-km field
-- anywhere, so transport defaults to lumpsum here, not per_km:
--   packing                -> per_cft
--   loading                -> lumpsum
--   transport              -> lumpsum
--   unloading              -> lumpsum
--   unpacking              -> per_cft
--   rearrangement          -> lumpsum
--   materials              -> at_actuals
--   toll_parking_octroi    -> at_actuals
--   insurance              -> percent_of_declared_value
--
-- NOTE: kDefaultChargeFields (lib/backend/pricing_defaults.dart) has no
-- 'rearrangement', 'toll_parking_octroi', or 'insurance' keys today — the
-- Rev A brief's Item 4 table names them but they don't exist in this
-- app's charge model yet. Seeding basis entries for keys nothing writes
-- yet is harmless (unused jsonb keys cost nothing) and means adding
-- those charge fields later is a Dart-only change, not a second
-- migration.
-- ---------------------------------------------------------------------------

begin;

-- Backfill only. Non-destructive: `||` adds the charge_basis key without
-- touching anything an org has already customized elsewhere in config,
-- and the `where not (config ? 'charge_basis')` guard means re-running
-- this is a no-op everywhere it already applied.
update public.pricing_config
   set config = config || jsonb_build_object(
     'charge_basis', jsonb_build_object(
       'packing', 'per_cft',
       'loading', 'lumpsum',
       'transport', 'lumpsum',
       'unloading', 'lumpsum',
       'unpacking', 'per_cft',
       'rearrangement', 'lumpsum',
       'materials', 'at_actuals',
       'toll_parking_octroi', 'at_actuals',
       'insurance', 'percent_of_declared_value'
     )
   )
 where not (config ? 'charge_basis');

commit;

-- Verify after running:
--   select org_id, config->'charge_basis' from public.pricing_config;
--   -- expect every existing row to have the 9-key map above.
-- ============================================================================
