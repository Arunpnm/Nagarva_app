-- =====================================================================
-- 20260825_gst_treatment_and_display.sql
--
-- NAGARVA_GST_SPEC.md build order STEP 2:
--   new columns + CHECK constraints + backfill of the existing quotations.
--
-- STEP 1 (populate organizations.state_code) IS DELIBERATELY NOT HERE.
-- ---------------------------------------------------------------------
-- §6 says "Backfill APC and Ponci (both Karnataka, code 29)". Live data
-- contradicts that and the contradiction is not mine to resolve:
--
--   APC   gstin='33ARLPA3366M1ZO'  -> state digits 33 = TAMIL NADU
--         state='karnataka', city='Bengaluru', state_code=NULL
--   Ponci gstin=NULL, state=NULL, city=NULL
--
-- The first two digits of a GSTIN ARE the state of registration, and the
-- GSTIN is what determines whether a supply is intra- or inter-state.
-- Setting state_code=29 against a 33 GSTIN would invert gst_split on
-- every order: Chennai->Chennai billed as IGST, Bengaluru deliveries as
-- CGST/SGST. That is a filing error on every invoice, not a cosmetic
-- default. §6's own rule — "Do not derive silently from NULL" — applies
-- just as much to deriving silently from contradictory values.
--
-- Arun to confirm which is correct (most likely: the GSTIN is right and
-- state/city are stale onboarding text), then step 1 lands separately.
-- Nothing in THIS migration depends on it: the backfill leaves gst_split
-- NULL wherever it is not knowable, which is the required behaviour.
--
-- Hand-run by Arun. Not executed by an agent.
--
-- ---------------------------------------------------------------------
-- TWO ADDITIONS BEYOND §3's DDL, both flagged rather than smuggled in:
--
--   1. `round_off` — §4 mandates storing it and test case 9 asserts on
--      it, but §3's column list omits it. Added.
--   2. `cgst_amount` / `sgst_amount` / `igst_amount` — §9 requires every
--      case to assert "against a stored quotation re-read from Postgres",
--      and test case 8 asserts the two halves sum to the tax exactly.
--      With nothing stored there is nothing to re-read and case 8 can
--      only ever test in-memory arithmetic, which is precisely the
--      weaker thing the spec forbids. Columns are cheap now and
--      expensive once real rows exist.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- PREFLIGHT
-- ---------------------------------------------------------------------
do $$
declare v_bad_rate text; v_exists text;
begin
  -- Re-running must not half-apply.
  select string_agg(a.attname, ', ') into v_exists
  from pg_attribute a
  where a.attrelid = 'public.quotations'::regclass
    and a.attnum > 0 and not a.attisdropped
    and a.attname in ('gst_treatment','gst_print','taxable_value');
  if v_exists is not null then
    raise exception
      'PREFLIGHT: column(s) already present on quotations (%) — this '
      'migration has already run, at least in part.', v_exists;
  end if;

  -- The gst_pct CHECK below must not reject data that already exists.
  select string_agg(distinct gst_pct::text, ', ') into v_bad_rate
  from public.quotations
  where gst_pct is not null and gst_pct not in (0, 5, 12, 18, 28);
  if v_bad_rate is not null then
    raise exception
      'PREFLIGHT: existing quotations carry gst_pct outside the allowed '
      'set {0,5,12,18,28}: %. Reconcile before constraining.', v_bad_rate;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Quotations
-- ---------------------------------------------------------------------
alter table public.quotations
  add column gst_treatment              text    not null default 'exclusive',
  add column gst_print                  text    not null default 'full',
  add column show_total_in_pdf          boolean not null default true,
  add column gst_split                  text,
  add column place_of_supply_state_code integer,
  add column taxable_value              numeric not null default 0,
  add column exempt_reason              text,
  add column round_off                  numeric not null default 0,
  add column cgst_amount                numeric not null default 0,
  add column sgst_amount                numeric not null default 0,
  add column igst_amount                numeric not null default 0;

-- ---------------------------------------------------------------------
-- Backfill BEFORE the exempt_reason CHECK is added, so the constraint is
-- validated against corrected data rather than fighting it.
--
-- gst_print derives from charges->>'_gstShowInPdf' — the live flag that
-- already governs display — with gst_amount as a fallback ONLY where the
-- legacy key is absent (the four pre-survey-builder rows).
--
-- 'false' maps to rate_only, NOT hidden: the tax was genuinely charged
-- and is inside `total`. Mapping it to hidden would misrepresent an
-- exclusive quote as a none quote and `total` would stop reconciling
-- against `taxable_value`. rate_only is the mode that actually means
-- "tax exists, figures suppressed".
-- ---------------------------------------------------------------------
update public.quotations q
   set gst_treatment = case
         when coalesce(q.gst_amount, 0) > 0 then 'exclusive'
         else 'none'
       end,
       gst_print = case
         when q.charges->>'_gstShowInPdf' = 'true'  then 'full'
         when q.charges->>'_gstShowInPdf' = 'false' then 'rate_only'
         when coalesce(q.gst_amount, 0) > 0         then 'full'
         else 'hidden'
       end,
       gst_split = case q.charges->>'_gstType'
         when 'intra' then 'cgst_sgst'
         when 'inter' then 'igst'
         else null   -- 'auto' and absent both mean "not decided"; never guess
       end,
       taxable_value = coalesce(q.subtotal, 0) - coalesce(q.discount_amount, 0),
       -- Historical rows: the split was never recorded, so attribute the
       -- whole tax to the side the split says, and nothing where unknown.
       -- Deriving a split we never quoted would invent figures, which is
       -- the same error §3 warns about for vehicle/crew in Item 12C.
       cgst_amount = case when q.charges->>'_gstType' = 'intra'
                          then round(coalesce(q.gst_amount,0) / 2, 2)
                          else 0 end,
       sgst_amount = case when q.charges->>'_gstType' = 'intra'
                          then coalesce(q.gst_amount,0)
                               - round(coalesce(q.gst_amount,0) / 2, 2)
                          else 0 end,
       igst_amount = case when q.charges->>'_gstType' = 'inter'
                          then coalesce(q.gst_amount,0)
                          else 0 end;

-- ---------------------------------------------------------------------
-- Constraints (added after the backfill).
-- ---------------------------------------------------------------------
alter table public.quotations
  add constraint quotations_gst_treatment_chk
    check (gst_treatment in ('exclusive','inclusive','exempt','extra','none')),
  add constraint quotations_gst_print_chk
    check (gst_print in ('full','rate_only','note_only','hidden')),
  add constraint quotations_gst_split_chk
    check (gst_split is null or gst_split in ('cgst_sgst','igst')),
  add constraint quotations_exempt_reason_chk
    check (gst_treatment <> 'exempt' or exempt_reason is not null),
  add constraint quotations_gst_pct_chk
    check (gst_pct is null or gst_pct in (0, 5, 12, 18, 28));

-- ---------------------------------------------------------------------
-- Orders — mirror, so quote -> order conversion carries treatment.
--
-- `quote_gst_mode` is UNTOUCHED. It already means intra/inter (live:
-- 'inter' x1, NULL x24) and §1.2 is explicit that reusing the name would
-- be a silent semantic collision. The new column is quote_gst_split;
-- renaming the old one is left to its own migration so this one cannot
-- break the single live row.
--
-- Nullable with defaults rather than NOT NULL: 25 existing orders
-- predate this and a NOT NULL backfill would assert a treatment for
-- orders that never had one.
-- ---------------------------------------------------------------------
alter table public.orders
  add column quote_gst_treatment       text    default 'exclusive',
  add column quote_gst_print           text    default 'full',
  add column quote_show_total_in_pdf   boolean default true,
  add column quote_gst_split           text,
  add column quote_taxable_value       numeric,
  add column quote_exempt_reason       text,
  add column quote_round_off           numeric,
  add column quote_cgst_amount         numeric,
  add column quote_sgst_amount         numeric,
  add column quote_igst_amount         numeric,
  add column place_of_supply_state_code integer;

alter table public.orders
  add constraint orders_quote_gst_treatment_chk
    check (quote_gst_treatment is null
           or quote_gst_treatment in ('exclusive','inclusive','exempt','extra','none')),
  add constraint orders_quote_gst_print_chk
    check (quote_gst_print is null
           or quote_gst_print in ('full','rate_only','note_only','hidden')),
  add constraint orders_quote_gst_split_chk
    check (quote_gst_split is null or quote_gst_split in ('cgst_sgst','igst'));

-- ---------------------------------------------------------------------
-- POSTFLIGHT — assert the product, and specifically assert the thing
-- test case 13 exists to catch: no historical document's total moved.
-- ---------------------------------------------------------------------
do $$
declare v_broken int; v_hidden_with_tax int;
begin
  -- taxable_value + gst_amount must still equal total on every row that
  -- had tax. If this fires, the backfill changed a printed document.
  select count(*) into v_broken
  from public.quotations
  where coalesce(gst_amount,0) > 0
    and round(coalesce(taxable_value,0) + coalesce(gst_amount,0), 2)
        <> round(coalesce(total,0), 2);
  if v_broken > 0 then
    raise exception
      'POSTFLIGHT: % quotation(s) no longer reconcile '
      '(taxable_value + gst_amount <> total).', v_broken;
  end if;

  -- A row with real tax must never have been backfilled to a mode that
  -- denies tax exists. This is the specific defect in the original §3.
  select count(*) into v_hidden_with_tax
  from public.quotations
  where coalesce(gst_amount,0) > 0
    and gst_print = 'hidden';
  if v_hidden_with_tax > 0 then
    raise exception
      'POSTFLIGHT: % quotation(s) carry tax but were set to gst_print '
      '= hidden.', v_hidden_with_tax;
  end if;

  -- Split halves must sum to the tax exactly (test case 8's invariant).
  select count(*) into v_broken
  from public.quotations
  where round(cgst_amount + sgst_amount + igst_amount, 2)
        not in (0, round(coalesce(gst_amount,0), 2));
  if v_broken > 0 then
    raise exception
      'POSTFLIGHT: % quotation(s) where the split does not sum to '
      'gst_amount.', v_broken;
  end if;

  raise notice 'POSTFLIGHT OK: totals reconcile, no tax hidden, split sums.';
end $$;

commit;

-- =====================================================================
-- VERIFY AFTER RUNNING (read-only)
--
--   select id, customer, gst_pct, gst_amount, taxable_value, total,
--          gst_treatment, gst_print, gst_split,
--          charges->>'_gstShowInPdf' as legacy_show
--     from public.quotations order by created_at;
--
-- Expect specifically:
--   * 'Test 1' and 'Abi'  -> gst_print = 'rate_only'  (legacy false)
--   * 'abi' and 'dssdf'   -> gst_print = 'full'       (legacy true)
--   * NGVQ-1001..1003 and 'Deepak Sharma' -> gst_print = 'full'
--     via the gst_amount fallback (no legacy key at all)
--   * gst_split = 'cgst_sgst' on 'dssdf' only; NULL elsewhere
--
-- Then the check that actually matters (test case 13): re-render one of
-- 'Test 1' or 'Abi' as a PDF and confirm the printed total is unchanged.
-- A constraint passing is not the same as a document being unchanged.
--
-- STILL OUTSTANDING BEFORE §6 CAN WORK:
--   organizations.state_code for both orgs — blocked on the APC
--   GSTIN(33) vs state('karnataka') contradiction described at the top.
-- =====================================================================
