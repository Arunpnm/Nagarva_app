-- Stale number_series/lr_series row cleanup (RLS/numbering audit, 12 Aug
-- 2026) — REWRITTEN after the numbering-scheme decision: one org-wide
-- series per doc type per FY, branch dimension dropped (permitted under
-- GST only for genuinely separate registrations, not two branches under
-- one GSTIN; a multi-tenant product shouldn't make every tenant inherit a
-- branch dimension nobody asked for). Handed over for Arun to review and
-- run — not executed from this session.
--
-- Deactivate, don't delete — keeps the evidence (per Arun's own
-- instruction) rather than erasing the rows that explain why APC-1006's
-- invoice_no is '0001' instead of '2026/0001'.
--
-- ============================================================================
-- Seed-row gap report (requested before writing this): NONE. Checked live,
-- both orgs, every doc type actually called with a branch before the
-- Dart-side branch:null fix — invoice, receipt, proforma, voucher (via
-- number_series) and lr (via the separate lr_series table, which
-- next_lr_number() actually reads/writes — number_series' own 'lr' row is
-- only a mirror per migration 007's comment, not what's live-called).
-- Every one of them already has an ACTIVE, correctly-configured org-wide
-- row (branch null, fy '2026-27', prefix '2026/', last_number 0) for BOTH
-- live orgs. Nothing needs seeding — this migration is cleanup-only.
--
-- Stray branch-scoped rows found (all org 11111111-1111-4111-8111-111111111111
-- / APC; org ed0c56d8-6c84-40b5-a139-8f3cb7254e93 / test-1-ae74 has none):
--   number_series: invoice/Bengaluru/2627  last_number 1
--   number_series: invoice/Chennai/2627    last_number 1
--   number_series: receipt/Bengaluru/2627  last_number 1
--   number_series: receipt/Chennai/2627    last_number 5
--   number_series: proforma/Chennai/2627   last_number 1   -- not caught in
--     the first pass at this cleanup; only surfaced once proforma was
--     checked directly rather than inferred from the invoice/receipt shape.
--   lr_series:     Chennai/2627, prefix '2026/', last_number 2
-- voucher has no stray row in either table for either org — never
-- exercised live yet, nothing to clean there.
--
-- NOT touched: the org-wide 'YYYY-YY' rows — left at their current
-- last_number (0 for every one of them, per Arun's explicit instruction).
-- NOT touched: APC-1006 itself — no renumbering; the correct GST
-- mechanism for its rate differential is a debit note referencing the
-- original invoice, not an overwrite, pending Arun's CA.
-- ============================================================================

begin;

update number_series
   set active = false
 where org_id = '11111111-1111-4111-8111-111111111111'
   and doc_type in ('invoice', 'receipt', 'proforma')
   and fy = '2627'
   and active = true;

update lr_series
   set active = false
 where org_id = '11111111-1111-4111-8111-111111111111'
   and fy = '2627'
   and active = true;

commit;

-- Verify after running:
--   select doc_type, branch, fy, last_number, active
--     from number_series
--    where org_id = '11111111-1111-4111-8111-111111111111'
--      and doc_type in ('invoice','receipt','proforma','voucher')
--    order by doc_type, branch;
--   -- expect the five stray rows above at active = false; org-wide
--   -- (branch null) rows for invoice/receipt/proforma/voucher still
--   -- active = true, last_number unchanged.
--
--   select branch, fy, last_number, active from lr_series
--    where org_id = '11111111-1111-4111-8111-111111111111';
--   -- expect Chennai/2627 at active = false, the org-wide row untouched.
--
-- Ordering (unchanged from before): do not run this, or the fail-loud
-- migrations, before the Dart branch:null + fy fix has shipped and been
-- confirmed on device. Running this first just means the next call under
-- the OLD code (still passing a real branch, still emitting '2627') would
-- silently auto-create a THIRD stray row per doc type instead of a
-- second — the opposite of the point. Order: Dart ships and is confirmed
-- -> next_doc_number() fail-loud -> next_lr_number() fail-loud -> this
-- cleanup.
