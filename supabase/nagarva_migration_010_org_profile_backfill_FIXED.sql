-- ═══════════════════════════════════════════════════════════════════════════
-- NAGARVA MIGRATION 010 — organizations backfill from settings.business_profile
-- Project: hqqcapifefsaqvotqvlt
-- Depends on: 001-009
--
-- Session 3's document header reads `organizations` columns first, falling
-- back to the org's own `settings.business_profile` jsonb only where the
-- column is still null. That fallback is deliberately temporary — this
-- migration converges the two sources so it becomes dead code rather than
-- permanent architecture.
--
-- SAFE BY CONSTRUCTION: every assignment is
--   coalesce(organizations.<col>, business_profile ->> '<key>')
-- so a column that already holds a value is left alone. Only genuinely-null
-- columns receive the jsonb value. Re-running is a no-op.
--
-- ── CORRECTION vs the first draft ──────────────────────────────────────────
-- `settings.value` is **jsonb**, not text (confirmed against
-- schema_snapshot_2026-08-01.csv). The draft failed with
--   42883: function pg_catalog.btrim(jsonb) does not exist
-- Three consequences, all fixed below:
--   1. `s.value::jsonb` was a redundant cast — value is already jsonb.
--   2. `trim(s.value)` is invalid on jsonb. The signature URL must be
--      extracted with `#>> '{}'` (jsonb scalar -> text) before trimming.
--   3. `signatory_image_url = sig.url` would have assigned jsonb to a text
--      column. Now extracts to text first.
--
-- NOT backfilled, deliberately (reasoning from the original draft stands):
--   * business_profile.invoice_terms — no matching organizations column;
--     app_settings.quotation_terms is a different document's terms.
--   * organizations.signatory_name — no source exists anywhere yet.
--   * city / state / pincode / state_code / upi_display_number —
--     business_profile stores one combined address string and has no
--     separate keys for these.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. business_profile jsonb -> organizations columns
-- ───────────────────────────────────────────────────────────────────────────

with profile as (
  select s.org_id, s.value as bp          -- already jsonb, no cast needed
  from settings s
  where s.key = 'business_profile'
    and s.value is not null
    and jsonb_typeof(s.value) = 'object'  -- guard against a scalar/array
)
update organizations o
set
  tagline           = coalesce(o.tagline,           nullif(trim(p.bp ->> 'tagline'), '')),
  gstin             = coalesce(o.gstin,             nullif(trim(p.bp ->> 'gstin'), '')),
  pan               = coalesce(o.pan,               nullif(trim(p.bp ->> 'pan'), '')),
  address           = coalesce(o.address,           nullif(trim(p.bp ->> 'address'), '')),
  phone_secondary   = coalesce(o.phone_secondary,   nullif(trim(p.bp ->> 'phone2'), '')),
  support_email     = coalesce(o.support_email,     nullif(trim(p.bp ->> 'email'), '')),
  website           = coalesce(o.website,           nullif(trim(p.bp ->> 'website'), '')),
  bank_name         = coalesce(o.bank_name,         nullif(trim(p.bp ->> 'bank_name'), '')),
  bank_account_no   = coalesce(o.bank_account_no,   nullif(trim(p.bp ->> 'account_no'), '')),
  bank_ifsc         = coalesce(o.bank_ifsc,         nullif(trim(p.bp ->> 'ifsc'), '')),
  upi_id            = coalesce(o.upi_id,            nullif(trim(p.bp ->> 'upi_id'), '')),
  beneficiary_name  = coalesce(o.beneficiary_name,  nullif(trim(p.bp ->> 'beneficiary_name'), ''))
from profile p
where p.org_id = o.id;

-- `->>` on a missing key returns NULL, so absent keys are harmless.
-- `beneficiary_name` added on the chance the profile carries it; if the key
-- does not exist the column simply stays null.

-- ───────────────────────────────────────────────────────────────────────────
-- 2. signature_url — a separate settings key, not part of the blob
--    Stored as a jsonb scalar string, so `#>> '{}'` unwraps it to text.
-- ───────────────────────────────────────────────────────────────────────────

with sig as (
  select s.org_id, nullif(trim(s.value #>> '{}'), '') as url
  from settings s
  where s.key = 'signature_url'
    and s.value is not null
)
update organizations o
set signatory_image_url = coalesce(o.signatory_image_url, sig.url)
from sig
where sig.org_id = o.id
  and sig.url is not null;

commit;


-- ═══════════════════════════════════════════════════════════════════════════
-- PRE-FLIGHT — run BEFORE the migration to see what will be read
-- ═══════════════════════════════════════════════════════════════════════════
--
-- -- What keys does each org's business_profile actually contain?
-- select s.org_id, jsonb_object_keys(s.value) as key
-- from settings s
-- where s.key = 'business_profile' and jsonb_typeof(s.value) = 'object'
-- order by s.org_id, key;
--
-- -- How signature_url is stored (expect a jsonb string):
-- select org_id, jsonb_typeof(value) as type, value #>> '{}' as url
-- from settings where key = 'signature_url';


-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION — run AFTER
-- ═══════════════════════════════════════════════════════════════════════════
--
-- select id, name, tagline, gstin, pan, address, phone_secondary,
--        support_email, website, bank_name, bank_account_no, bank_ifsc,
--        upi_id, beneficiary_name, signatory_image_url
-- from organizations
-- order by name;
--
-- -- Orgs with a business_profile still showing nulls in the three core
-- -- fields. Non-zero means that org's profile itself has those keys empty
-- -- or missing — this migration cannot invent data never entered.
-- select o.id, o.name
-- from organizations o
-- join settings s on s.org_id = o.id and s.key = 'business_profile'
-- where o.tagline is null and o.address is null and o.gstin is null;
