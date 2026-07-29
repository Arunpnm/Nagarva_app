-- ============================================================================
-- 20260729_order_quote_snapshot.sql
--
-- Item 2, snapshot half. Freezes the quote figures onto the order at the
-- moment of Convert to Order, so a later quote revision (operational flow
-- 1.2) or a signed quote (item 3) can never change what an order was
-- confirmed on.
--
-- `orders.quotation_id` STAYS as the live link — this is additional, not a
-- replacement. Two different questions, two different answers:
--     quotation_id  -> "what does the quote say now"     (current, may move)
--     quote_*       -> "what was this order confirmed on" (frozen, never moves)
-- Same principle as storing per-line CFT at add-time.
--
-- ---------------------------------------------------------------------------
-- RUN THIS FIRST. I have no live database access from this session, so I
-- have NOT introspected `orders` — the column list I worked from is the
-- generated Dart mirror (lib/backend/supabase/database/tables/orders.dart),
-- which is maintained by hand and is not authoritative. Every statement
-- below is `add column if not exists`, so it is safe whatever this returns,
-- but check it anyway before running:
--
--   select column_name, data_type, is_nullable
--     from information_schema.columns
--    where table_schema = 'public' and table_name = 'orders'
--    order by ordinal_position;
--
-- If any `quote_*` name below already exists with a DIFFERENT type, the
-- `if not exists` will silently skip it and the app will then write the
-- wrong shape into it. That is the one failure mode this file cannot
-- defend against — hence the check.
-- ---------------------------------------------------------------------------
--
-- No functions or views are created here, so there is no RETURNS TABLE to
-- drop first. Nothing existing is altered or dropped; this is purely
-- additive, and every existing order simply has nulls in the new columns.
-- ============================================================================

begin;

alter table public.orders
  -- The line data. jsonb because it is inherently variable-shape — this is
  -- a verbatim copy of quotations.items / quotations.charges as they stood
  -- at conversion, including each line's stored per-line `cft`.
  --
  -- quote_charges also carries the keys the quote builder writes alongside
  -- the amounts: `_billingMode` (per-charge included/additional),
  -- `_gstType`, `_suggestedPackage`, `_totalCft`, `_totalItems`.
  add column if not exists quote_items    jsonb,
  add column if not exists quote_charges  jsonb,

  -- Scalars promoted OUT of the jsonb deliberately, not duplicated for
  -- convenience: the reports pack (master brief item 29) needs a GST
  -- summary with an IGST vs CGST+SGST split aggregated by month. That has
  -- to be a plain group-by over real columns; unnesting jsonb for every
  -- order in a financial year would be painful and slow.
  add column if not exists quote_subtotal   numeric,
  add column if not exists quote_gst_pct    numeric,
  add column if not exists quote_gst_amount numeric,
  add column if not exists quote_total      numeric,

  -- The RESOLVED interstate/intrastate mode ('inter' | 'intra'), never
  -- 'auto'. The quote stores `_gstType = 'auto'` when the surveyor let it
  -- derive from the from/to cities — but that derivation re-runs against
  -- whatever the addresses say later. Freezing the resolved answer is the
  -- whole point; storing 'auto' here would re-introduce exactly the drift
  -- this table is meant to stop.
  add column if not exists quote_gst_mode text,

  -- Suggested package / packing type as chosen at conversion
  -- (charges->>'_suggestedPackage'), plus the CFT it was derived from.
  -- Frozen for the same reason: master brief item 12B makes the CFT->
  -- package slabs per-tenant editable, and editing a slab must not
  -- silently re-describe a dispatched job.
  add column if not exists quote_packing_type text,
  add column if not exists quote_total_cft    numeric,

  -- Which version of the quote this order was confirmed on.
  --
  -- Quote versioning is NOT built yet — `quotations` has no `version` or
  -- `parent_quote_id` column today (operational flow 1.2 specifies it).
  -- Until it lands every snapshot is version 1, which is correct rather
  -- than a placeholder: the first quote IS v1. Adding the column now means
  -- versioning ships without a second migration, and orders confirmed
  -- before versioning are correctly recorded as having been on v1.
  add column if not exists quote_version integer,

  -- Null on orders never converted from a quote, and the flag for "has a
  -- snapshot" — do not infer that from quote_total being non-null, since a
  -- zero-value quote is legitimate.
  add column if not exists quote_snapshot_at timestamptz;

comment on column public.orders.quote_gst_mode is
  'Resolved inter|intra at conversion. Never ''auto'' — see migration notes.';
comment on column public.orders.quote_snapshot_at is
  'Set when the quote figures were frozen onto this order. Null = no snapshot.';

do $$
begin
  if not exists (select 1 from pg_constraint
                 where conname = 'orders_quote_gst_mode_check') then
    alter table public.orders
      add constraint orders_quote_gst_mode_check
      check (quote_gst_mode is null or quote_gst_mode in ('inter', 'intra'));
  end if;
end $$;

commit;

-- ---------------------------------------------------------------------------
-- DELIBERATELY NOT DONE
--
-- 1. No backfill. Existing orders keep null quote_* columns. A snapshot is
--    a record of what was agreed AT a moment; synthesising one now from
--    whatever the linked quote currently says would be a fabrication, and
--    indistinguishable from a real one afterwards. The app treats null as
--    "no snapshot, fall back to the live quote", which is the honest
--    behaviour for orders confirmed before this existed.
--
-- 2. No trigger. The snapshot is written by the app at Convert to Order,
--    not by the database. A trigger on orders would fire for every insert
--    including manual orders with no quote at all, and would have to guess
--    which quote to freeze.
--
-- 3. No `orders.amount` change. That column already holds the quote total
--    at conversion, but it is EDITABLE afterwards via Edit Order — which is
--    correct, an order's value can legitimately be renegotiated.
--    quote_total is the immutable one. Where they differ, that difference
--    is itself useful: it is exactly "how far this job moved from what was
--    quoted", which the reports pack will want.
--
-- 4. No extra indexes. The reporting queries these columns serve filter by
--    org_id and a date, both of which are already indexed; adding indexes
--    on columns that are null for every historic row would carry cost for
--    no current benefit. Revisit when the GST report actually exists and
--    has a measurable plan.
-- ---------------------------------------------------------------------------

-- Verify after running:
--   select column_name, data_type
--     from information_schema.columns
--    where table_schema = 'public' and table_name = 'orders'
--      and column_name like 'quote\_%'
--    order by column_name;
--   -- expect exactly 11 rows:
--   --   quote_charges       jsonb
--   --   quote_gst_amount    numeric
--   --   quote_gst_mode      text
--   --   quote_gst_pct       numeric
--   --   quote_items         jsonb
--   --   quote_packing_type  text
--   --   quote_snapshot_at   timestamp with time zone
--   --   quote_subtotal      numeric
--   --   quote_total         numeric
--   --   quote_total_cft     numeric
--   --   quote_version       integer
--
--   -- and the guard rejects a bad mode:
--   -- update public.orders set quote_gst_mode = 'auto' where id = '<any>';
--   --   -> expect: violates check constraint orders_quote_gst_mode_check
