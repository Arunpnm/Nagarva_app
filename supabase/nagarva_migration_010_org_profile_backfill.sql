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
-- ── THREE CORRECTIONS, all found before/while this ran ─────────────────────
--
-- (a) `settings.value` is **jsonb**, not text. The first draft failed with
--     42883: function pg_catalog.btrim(jsonb) does not exist.
--       1. `s.value::jsonb` was a redundant cast.
--       2. `trim(s.value)` is invalid on jsonb — extract with `#>> '{}'`
--          (jsonb scalar -> text) before trimming.
--       3. `signatory_image_url = sig.url` would assign jsonb to a text
--          column.
--
-- (b) business_profile is **double-encoded**. The second draft guarded on
--     `jsonb_typeof(value) = 'object'`, which matches nothing: the app writes
--     `jsonEncode(profile)` through SettingsRow's `String?` setter, so the
--     column holds a jsonb SCALAR STRING containing JSON text. Verified live:
--       jsonb_typeof(value) -> 'string'
--       value #>> '{}'      -> {"tagline":"Moving You Towards Your Future",...}
--     That guard would have skipped every row and reported success having
--     done nothing. Now unwrapped with `(s.value #>> '{}')::jsonb`.
--
-- (c) `phone1` was missing from the mapping — only `phone2` (->
--     phone_secondary) was backfilled. `organizations.phone` is the primary-
--     phone column (pre-existing, not added by migration 009) and business_
--     profile's `phone1` key is its counterpart, same as `phone2`/
--     `phone_secondary`. Added below. Harmless to re-run against a tenant
--     that already has `phone` set (e.g. APC, set at signup, independent of
--     this backfill) — coalesce leaves it untouched.
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
  -- business_profile is DOUBLE-ENCODED: jsonEncode(profile) is written through
  -- SettingsRow's String? setter, so the column holds a jsonb *scalar string*
  -- containing JSON text, not a jsonb object. Verified on the live row:
  --   jsonb_typeof(value) = 'string'
  -- So it must be unwrapped to text with #>> '{}' and re-parsed as jsonb
  -- before any key can be read. Keying straight into the scalar returns null.
  select s.org_id, (s.value #>> '{}')::jsonb as bp
  from settings s
  where s.key = 'business_profile'
    and s.value is not null
    and jsonb_typeof(s.value) = 'string'
    and coalesce(s.value #>> '{}', '') like '{%'   -- guard: parseable object
)
update organizations o
set
  tagline           = coalesce(o.tagline,           nullif(trim(p.bp ->> 'tagline'), '')),
  gstin             = coalesce(o.gstin,             nullif(trim(p.bp ->> 'gstin'), '')),
  pan               = coalesce(o.pan,               nullif(trim(p.bp ->> 'pan'), '')),
  address           = coalesce(o.address,           nullif(trim(p.bp ->> 'address'), '')),
  phone             = coalesce(o.phone,             nullif(trim(p.bp ->> 'phone1'), '')),
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
-- -- What keys does the profile actually contain? (unwraps the double encoding)
-- select s.org_id, jsonb_object_keys((s.value #>> '{}')::jsonb) as key
-- from settings s
-- where s.key = 'business_profile' and jsonb_typeof(s.value) = 'string'
-- order by s.org_id, key;
--
-- -- Full profile, readable:
-- select org_id, jsonb_pretty((value #>> '{}')::jsonb)
-- from settings where key = 'business_profile';
--
-- -- How signature_url is stored (expect a jsonb string):
-- select org_id, jsonb_typeof(value) as type, value #>> '{}' as url
-- from settings where key = 'signature_url';


-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION — run AFTER
-- ═══════════════════════════════════════════════════════════════════════════
--
-- select id, name, tagline, gstin, pan, address, phone, phone_secondary,
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
