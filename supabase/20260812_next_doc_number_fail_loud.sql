-- next_doc_number() fail-loud fix (RLS/numbering audit, 12 Aug 2026).
-- Handed over for Arun to review and run — not executed from this session.
--
-- ROOT CAUSE this closes: next_doc_number(org, doc_type, branch, fy) never
-- errors on a miss — migration 006's original body silently INSERTs a
-- brand-new, unprefixed number_series row the first time a given
-- (org, doc_type, branch, fy) combination is seen, starting it at 1. That
-- turned a client-side bug (currentFy() emitting '2627' instead of the
-- seeded '2026-27') into invisible drift: every real invoice/receipt/LR/
-- proforma/voucher call auto-created its own bare series instead of
-- failing where the mismatch could be noticed. Confirmed live: APC-1006's
-- invoice_no is '0001', not the intended '2026/0001' — issued through a
-- silently-created row, not the seeded one.
--
-- The Dart-side fix (OrderDetailPage.currentFy() and its two duplicate
-- copies in quick_payment_section.dart / order_documents_section.dart,
-- all now emitting 'YYYY-YY') closes the immediate mismatch. This
-- migration is the other half: make the function itself refuse to paper
-- over the NEXT config mismatch, of any kind, the same way. A real
-- signup-orphan class of bug, not just this one.
--
-- Same signature and return type as the existing function (uuid, text,
-- text default null, text default null) -> text — CREATE OR REPLACE is
-- sufficient, no DROP needed per this repo's own convention (that rule
-- only applies when the signature or return type changes).
--
-- Behaviour change beyond "raise instead of insert": the match now also
-- requires active = true. This is deliberate, not incidental — it's what
-- makes the accompanying cleanup migration's `active = false` on the two
-- stale branch-scoped 'invoice'/2627 rows actually mean something. Without
-- this, deactivating those rows would be cosmetic: the old body doesn't
-- consult `active` at all, so a caller that somehow still passed
-- branch='Bengaluru'/fy='2627' would keep drawing numbers from a row
-- marked "not in use." With this, that caller now gets the same loud
-- error as any other unconfigured combination — which is correct, since a
-- deactivated series is not a configured one.
--
-- Every legitimate call site already passes a doc_type this table has a
-- seeded row for (invoice, receipt, quotation, lr, proforma, voucher,
-- credit_note, debit_note, po, grn, payslip, storage_job, claim,
-- contract — confirmed live, all present per org). None of them are
-- expected to hit this exception once the Dart-side fy fix has shipped
-- and rolled out — same "ship code first, confirm rollout, then run this"
-- ordering as every other migration in this project. Running this BEFORE
-- the Dart fix ships would make every document generation in the app fail
-- loudly instead of drifting silently — correct in principle, but do not
-- run it out of order.

begin;

create or replace function next_doc_number(
  p_org uuid, p_doc_type text, p_branch text default null, p_fy text default null
) returns text as $$
declare rec record; n int;
begin
  select * into rec from number_series
   where org_id = p_org and doc_type = p_doc_type
     and coalesce(branch,'') = coalesce(p_branch,'')
     and coalesce(fy,'') = coalesce(p_fy,'')
     and active
   for update;

  if not found then
    raise exception
      'No active number series configured for org=%, doc_type=%, branch=%, fy=%. '
      'Configure one in number_series (or reactivate an existing row) before '
      'generating this document.',
      p_org, p_doc_type, coalesce(p_branch, '<none>'), coalesce(p_fy, '<none>')
      using errcode = 'P0001';
  end if;

  n := rec.last_number + 1;
  update number_series set last_number = n where id = rec.id;

  return coalesce(rec.prefix,'') || lpad(n::text, coalesce(rec.padding,4), '0')
         || coalesce(rec.suffix,'');
end;
$$ language plpgsql;

commit;

-- Verify after running, and after the Dart fy fix has shipped/rolled out:
--   -- should succeed and return e.g. '2026/0002' (or the next number in
--   -- whatever the seeded org-wide row is already at):
--   select next_doc_number(
--     (select id from organizations where slug = 'apc'),
--     'invoice', null, '2026-27');
--
--   -- should now RAISE (was previously silent-succeed with a fresh row):
--   select next_doc_number(
--     (select id from organizations where slug = 'apc'),
--     'invoice', 'Bengaluru', '2627');
