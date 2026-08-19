-- ============================================================
-- supabase/20260817_item12c_package_columns.sql
--
-- Item 12C — get the suggested/chosen package, vehicle and crew out of
-- `quotations.charges->>'_suggestedPackage'` and into real columns on
-- both `quotations` and `orders`.
--
-- WHY BOTH VALUES, NOT JUST THE CHOSEN ONE (master brief 12C): the slab
-- table produces a *suggestion*; the surveyor overrides it for the narrow
-- staircases, long carries and fragile loads no CFT table predicts. Keeping
-- the suggestion alongside the choice means the gap between them, across
-- many jobs, is what tells the vendor their slabs need adjusting. Storing
-- only the outcome throws that signal away.
--
-- WHY STORED, NOT RE-DERIVED: re-running the slab lookup at render time
-- would let a later Settings edit silently rewrite the vehicle and crew on
-- an already-dispatched job. These columns are frozen at save.
--
-- Note on the jsonb key: `charges->>'_suggestedPackage'` is still written
-- by the app after this migration. It is NOT dead — quote_pdf.dart and
-- lead_detail_page's order snapshot both read it, and every quote created
-- before today only has it. The new columns are additive; the key is the
-- back-compat path. Don't drop it without migrating those readers.
--
-- Safe to re-run: every statement is IF NOT EXISTS / idempotent.
-- ============================================================

begin;

-- ---- 1. quotations -------------------------------------------------
-- `suggested_vehicle` already exists (text) and is reused as-is.
-- `vehicle_type` also already exists and is deliberately left alone —
-- it predates this work and nothing in the Item 12 flow writes it.

alter table quotations add column if not exists suggested_package text;
alter table quotations add column if not exists suggested_crew integer;
alter table quotations add column if not exists chosen_package text;
alter table quotations add column if not exists chosen_vehicle text;
alter table quotations add column if not exists chosen_crew integer;

-- `total_cft` exists but is INTEGER. The survey builder sums CFT as a
-- decimal (a custom item can carry a fractional CFT), so an integer
-- column silently rounds — the exact class of quiet-wrong-number bug the
-- 0-CFT fix and the packages.first fallback were both about. Widen it.
-- Column type changes don't need the DROP dance that functions and views
-- do (see CLAUDE.md's conventions section) — integer -> numeric is a
-- widening, so no USING clause and no data loss.
alter table quotations alter column total_cft type numeric;

comment on column quotations.suggested_package is
  'Item 12C: what the org''s CFT slab table suggested at save time. Kept '
  'alongside chosen_* so the gap between suggestion and reality shows '
  'the vendor where their slabs need adjusting. Never re-derived.';
comment on column quotations.chosen_package is
  'Item 12C: what the surveyor actually went with. Equals '
  'suggested_package when they did not override.';

-- ---- 2. orders -----------------------------------------------------
-- Carried across when a quote converts to an order (see
-- lead_detail_page_widget.dart's _snapshotQuoteOntoOrder), so a
-- dispatched job holds its own frozen copy rather than joining back to a
-- quotation that may since have been superseded.

alter table orders add column if not exists suggested_package text;
alter table orders add column if not exists suggested_vehicle text;
alter table orders add column if not exists suggested_crew integer;
alter table orders add column if not exists chosen_package text;
alter table orders add column if not exists chosen_vehicle text;
alter table orders add column if not exists chosen_crew integer;

comment on column orders.chosen_crew is
  'Item 12C: crew count this job was actually quoted with, frozen at '
  'quote-to-order conversion. Not re-derived from the slab table — a '
  'later Settings edit must never rewrite a dispatched job.';

-- ---- 3. Backfill from the jsonb key --------------------------------
-- Existing quotes only carry the package NAME (no vehicle/crew was ever
-- persisted), so only that one column can be backfilled. Vehicle and crew
-- stay null for historical rows rather than being re-derived from today's
-- slab table — re-deriving would invent a number that was never quoted,
-- which is precisely what these columns exist to prevent.
update quotations
set chosen_package = charges->>'_suggestedPackage'
where chosen_package is null
  and charges ? '_suggestedPackage'
  and coalesce(charges->>'_suggestedPackage', '') <> '';

update orders
set chosen_package = quote_packing_type
where chosen_package is null
  and coalesce(quote_packing_type, '') <> '';

commit;

-- ---- Verify (read-only) --------------------------------------------
-- select count(*) filter (where chosen_package is not null) as backfilled,
--        count(*) as total
-- from quotations;
