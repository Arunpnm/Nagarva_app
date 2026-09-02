-- APC Bengaluru + APC Coimbatore — additional orgs under the existing owner.
--
-- Model (Arun, 2 Sep 2026): one owner, several LOCATIONS, each a separate
-- Nagarva org with its own licence. The owner switches orgs; branch staff
-- cannot — a staff row belongs to exactly one org, so their PIN only ever
-- resolves there. That half needs no code: see the report accompanying
-- this file.
--
-- WHY THE PREFIX BLOCK BELOW EXISTS, AND WHY IT MUST RUN IN THE SAME
-- SESSION AS THE CREATES
--
-- seed_org_number_series() hardcodes the calendar year as the prefix for
-- invoice/proforma/receipt/quotation/voucher/credit_note/debit_note:
--
--     case when d.calendar_prefix then v_year || '/' else d.prefix end
--
-- Nothing in it is org-specific. So EVERY org on the platform seeds
-- prefix '2026/' starting at 0, and every org's first invoice is the
-- string '2026/0001'. Counters are isolated per org (that part works);
-- the rendered NUMBER is not distinguishable at all.
--
-- For two APC locations under one owner that is not cosmetic. If they
-- share a GSTIN, Rule 46(b) requires ONE consecutive series per
-- registration, and two orgs each independently issuing 2026/0001 breaks
-- it. If they hold separate GSTINs it is legal but still leaves the owner
-- holding two different invoices with the same number.
--
-- A prefix edit is only safe while last_number = 0 — changing it after
-- documents exist silently continues the old counter under a new identity
-- (CLAUDE.md, numbering-prefix audit). These orgs are seconds old here,
-- so this is the one moment it is free. APC's own series is deliberately
-- NOT touched: it has already issued 2026/0001 and renumbering it
-- mid-year is exactly the break described above.

begin;

-- 1. Create the two orgs through the supported path, so number_series,
--    lr_series, pricing_config, document settings and the default branch
--    are all seeded the way signup seeds them.
--
--    'create_additional' inherits the parent's plan rather than opening a
--    second free trial. NOTE: that means both branches currently sit on
--    APC's single plan row — separate per-branch licensing is a billing
--    change, not something this script can fake (Item 31, on hold).
--
--    GSTINs are placeholders. Bengaluru is Karnataka (state code 29) and
--    needs its own registration; Coimbatore is Tamil Nadu (33), the same
--    state as APC, so confirm with your CA whether it is a separate
--    registration or an additional place of business under 33ARLPA3366M1ZO
--    before issuing a real invoice from it.
select * from public.create_org_with_owner(
  '26bf3ecd-4524-4c5d-b784-1aa5ca8a75a1'::uuid,
  'APC Bengaluru',
  '7411628282',
  '29AAAAA0000A1Z5',
  'Arun Kumar',
  'create_additional');

select * from public.create_org_with_owner(
  '26bf3ecd-4524-4c5d-b784-1aa5ca8a75a1'::uuid,
  'APC Coimbatore',
  '7411628283',
  '33ARLPA3366M1ZO',
  'Arun Kumar',
  'create_additional');

-- 2. Give each new org a distinguishable series, while last_number = 0.
update public.number_series ns
   set prefix = 'BLR/2026/'
  from public.organizations o
 where o.id = ns.org_id
   and o.slug = 'apc-bengaluru'
   and ns.last_number = 0
   and ns.doc_type in ('invoice','proforma','receipt','quotation',
                       'voucher','credit_note','debit_note');

update public.number_series ns
   set prefix = 'CBE/2026/'
  from public.organizations o
 where o.id = ns.org_id
   and o.slug = 'apc-coimbatore'
   and ns.last_number = 0
   and ns.doc_type in ('invoice','proforma','receipt','quotation',
                       'voucher','credit_note','debit_note');

-- LR runs on its own table and its own allocator.
update public.lr_series ls
   set prefix = 'BLR-LR'
  from public.organizations o
 where o.id = ls.org_id and o.slug = 'apc-bengaluru';

update public.lr_series ls
   set prefix = 'CBE-LR'
  from public.organizations o
 where o.id = ls.org_id and o.slug = 'apc-coimbatore';

-- 3. POSTFLIGHT — every org must now render a DIFFERENT first number.
--    Expect three distinct prefixes and three distinct next-number
--    strings. If any two match, stop and do not issue documents.
select o.slug,
       ns.prefix,
       ns.last_number,
       ns.prefix || lpad((ns.last_number + 1)::text, ns.padding, '0')
         as next_invoice_would_be
  from public.number_series ns
  join public.organizations o on o.id = ns.org_id
 where ns.doc_type = 'invoice'
 order by o.slug;

commit;
