-- ============================================================================
-- Nagarva Supabase (hqqcapifefsaqvotqvlt) — Stage 1: rename string-namespaced
-- settings keys now that org_id does the isolation
-- ============================================================================
-- LEAK_AUDIT.md leaks #6 and #10: two `settings` keys used to encode the org
-- identity inside the key string itself instead of relying on the `org_id`
-- column — 'inv_seq_<SLUG>_<FY>' (invoice sequence counter, see
-- order_detail_page_widget.dart's _nextInvoiceNo) and
-- 'accounts_opening_balance:<orgId>' (accounts_page_widget.dart). The Stage 1
-- app-code pass rewrote every read/write of these rows to filter on org_id
-- AND the new, simpler key ('inv_seq_<FY>' / 'accounts_opening_balance'). This
-- migration rewrites any EXISTING rows so the app's new queries keep finding
-- them under the new key instead of silently starting a fresh counter /
-- opening balance at zero.
--
-- Safe to run more than once — both statements are no-ops once the keys are
-- already renamed (the WHERE/LIKE clauses won't match already-renamed rows).
--
-- ASSUMPTION TO VERIFY FIRST: if `settings` has a UNIQUE constraint on `key`
-- alone (not `UNIQUE(org_id, key)`), this migration could collide once a
-- second org exists with the same financial year — check
-- `\d public.settings` (or the constraint list in the dashboard) before
-- running if you're past single-tenant (APC-only) testing. As of this
-- writing (per CLAUDE.md) only APC is seeded, so there's nothing to collide
-- with yet, but this is exactly the gap that would bite a second tenant.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Invoice sequence counters: 'inv_seq_<SLUG>_<FY>' -> 'inv_seq_<FY>'
--    (e.g. 'inv_seq_APC_2526' -> 'inv_seq_2526')
-- ---------------------------------------------------------------------------
update public.settings s
set key = 'inv_seq_' || substring(s.key from '_(\d{4})$')
from public.organizations o
where s.org_id = o.id
  and s.key like 'inv\_seq\_' || upper(o.slug) || '\_%' escape '\';

-- ---------------------------------------------------------------------------
-- 2. Accounts opening balance: 'accounts_opening_balance:<orgId>' ->
--    'accounts_opening_balance' (org_id column already scopes the row; the
--    suffix was always redundant with it once the migration below ran).
-- ---------------------------------------------------------------------------
update public.settings
set key = 'accounts_opening_balance'
where key like 'accounts_opening_balance:%';

-- ---------------------------------------------------------------------------
-- 3. Sanity check — run after the above and eyeball the result: should show
--    one 'inv_seq_<FY>' row and one 'accounts_opening_balance' row per org
--    that had them before, with no leftover ':' or slug-suffixed keys.
-- ---------------------------------------------------------------------------
-- select org_id, key, value from public.settings
-- where key like 'inv_seq%' or key like 'accounts_opening_balance%'
-- order by org_id, key;
