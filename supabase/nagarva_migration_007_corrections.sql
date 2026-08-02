-- ═══════════════════════════════════════════════════════════════════════════
-- NAGARVA MIGRATION 007 — SESSION 1 CORRECTIONS
-- Project: hqqcapifefsaqvotqvlt
-- Depends on: 001-006
--
-- Fixes two real gaps found while building Order Details Session 1:
--   1. document_signatures.document_type CHECK too narrow for the
--      signature companions on Receipt / LR / Voucher.
--   2. lr_series has no atomic allocator, unlike next_doc_number().
--
-- NOT fixed here: orders.closed_at. It already exists in the live schema —
-- it pre-dates migrations 001-006, which is why it is absent from those files.
-- Mark Order Complete can and should stamp it.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Widen document_signatures.document_type
--    Current CHECK allows only ('quote','invoice'), so only Invoice can
--    durably persist a signature. Receipt, LR and Voucher could apply a
--    held signature to one PDF but never reload it.
-- ───────────────────────────────────────────────────────────────────────────

do $$
declare cname text;
begin
  -- Drop whatever the CHECK is actually named, rather than guessing.
  select con.conname into cname
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace ns on ns.oid = rel.relnamespace
  where ns.nspname = 'public'
    and rel.relname = 'document_signatures'
    and con.contype = 'c'
    and pg_get_constraintdef(con.oid) ilike '%document_type%'
  limit 1;

  if cname is not null then
    execute format('alter table document_signatures drop constraint %I', cname);
  end if;
end $$;

alter table document_signatures
  add constraint document_signatures_document_type_check
  check (document_type in (
    'quote',            -- pre-existing
    'invoice',          -- pre-existing
    'proforma',
    'receipt',
    'lr',
    'voucher',
    'packing_list',
    'loading_slip',
    'vehicle_condition',
    'pod',
    'contract',
    'order'             -- order-level signature (the existing e-sign banner)
  ));

-- Reverse lookup: which order does a signature belong to. document_id is
-- generic, so this makes "load the held signature for this order" cheap.
alter table document_signatures add column if not exists order_id text
  references orders(id) on delete cascade;
alter table document_signatures add column if not exists is_persistent boolean default false;

create index if not exists doc_sig_order_idx
  on document_signatures (org_id, order_id, document_type);


-- ───────────────────────────────────────────────────────────────────────────
-- 2. Atomic LR numbering
--    lr_series (migration 003) predates number_series (006) and has no
--    allocator, so LR numbers were being issued read-then-write — two
--    concurrent LRs can collide.
--
--    Consolidating onto number_series would mean rewriting lr_register's
--    numbering path mid-session. Instead: give lr_series the same atomic
--    allocator contract as next_doc_number(), and mirror the counters into
--    number_series so a later consolidation is a no-op.
-- ───────────────────────────────────────────────────────────────────────────

create or replace function next_lr_number(
  p_org uuid, p_branch text default null, p_fy text default null
) returns text as $$
declare rec record; n int;
begin
  select * into rec from lr_series
   where org_id = p_org
     and coalesce(branch,'') = coalesce(p_branch,'')
     and coalesce(fy,'')     = coalesce(p_fy,'')
   for update;                                  -- row lock, same as next_doc_number

  if not found then
    insert into lr_series (org_id, branch, fy, prefix, last_number)
    values (p_org, p_branch, p_fy, 'LR', 1)
    returning * into rec;
    n := 1;
  else
    n := rec.last_number + 1;
    update lr_series set last_number = n where id = rec.id;
  end if;

  return coalesce(rec.prefix,'LR') || lpad(n::text, 4, '0');
end;
$$ language plpgsql;

-- Register 'lr' in number_series so next_doc_number('lr') is also valid,
-- seeded from the current lr_series counter to avoid reissuing numbers.
insert into number_series (org_id, doc_type, branch, fy, prefix, padding, last_number)
select ls.org_id, 'lr', ls.branch, ls.fy,
       coalesce(ls.prefix,'LR'), 4, ls.last_number
from lr_series ls
on conflict do nothing;


-- ───────────────────────────────────────────────────────────────────────────
-- 3. Porter commission — no schema change needed, recording the correction
--    is_porter (boolean) + porter_commission_pct (numeric) already exist and
--    are the real mechanism. The 16%/19% local-vs-outstation split in the
--    Session 1 brief was carried over from APC and is wrong for this app.
--
--    Backfill the default rates for any porter order missing a pct, using
--    order_type only as the seed value — the column is the source of truth
--    from here on.
-- ───────────────────────────────────────────────────────────────────────────

update orders
set porter_commission_pct = case
      when lower(coalesce(order_type,'')) like '%outstation%' then 19
      else 16
    end
where is_porter is true
  and coalesce(porter_commission_pct, 0) = 0
  and deleted_at is null;


-- ───────────────────────────────────────────────────────────────────────────
-- 4. field_expenses shape — document the contract
--    Zero prior usage, so the shape was never pinned down. Fixing it now
--    prevents two different writers inventing two different shapes.
--
--    Agreed shape: jsonb array of objects
--      [{"type": "Fuel", "amount": 500, "note": "...", "at": "2026-08-02"}]
-- ───────────────────────────────────────────────────────────────────────────

comment on column orders.field_expenses is
  'jsonb array: [{"type": text, "amount": numeric, "note": text, "at": date}]. '
  'Removal is by array index. Feeds Order Expenses in the P&L.';

-- Normalise anything that is null or a non-array into an empty array so
-- readers never have to defend against three shapes.
update orders
set field_expenses = '[]'::jsonb
where (field_expenses is null or jsonb_typeof(field_expenses) <> 'array')
  and deleted_at is null;

alter table orders alter column field_expenses set default '[]'::jsonb;

commit;


-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════
--
-- -- 1. CHECK now accepts receipt/lr/voucher
-- select pg_get_constraintdef(con.oid)
-- from pg_constraint con join pg_class rel on rel.oid = con.conrelid
-- where rel.relname = 'document_signatures' and con.contype = 'c';
--
-- -- 2. atomic LR allocator (returns LR0001 on a fresh series)
-- select next_lr_number((select id from organizations limit 1), null, '2026-27');
--
-- -- 3. porter rates backfilled
-- select id, is_porter, order_type, porter_commission_pct
-- from orders where is_porter is true;
--
-- -- 4. field_expenses is an array everywhere
-- select count(*) as non_array from orders
-- where jsonb_typeof(field_expenses) <> 'array' and deleted_at is null;
-- -- expect 0
--
-- -- 5. closed_at confirmed present (no fix needed)
-- select column_name from information_schema.columns
-- where table_name='orders' and column_name='closed_at';
