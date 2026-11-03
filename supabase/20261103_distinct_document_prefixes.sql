-- 3 Nov 2026 — full-test BUG-038 / BUG-016. Arun applies migrations himself.
--
-- REVISION 2 (08:55): the first version gave every company the same fixed
-- prefixes (QT/2026-27/ …) and failed on the existing rule that a document
-- prefix must be unique ACROSS companies (enforce_doc_prefix_unique:
-- 'Prefix "QT/2026-27/" is already used by Arun Packers and Couriers').
-- That run rolled back completely — nothing was changed.
--
-- Problem: invoice, receipt, credit note, debit note, proforma, quotation
-- and voucher all used the SAME prefix (e.g. TES/2026-27/), so three
-- different documents for one order were all numbered TES/2026-27/0001.
--
-- New format, unique per company AND per document type, inside the
-- 12-character prefix limit, and still renewed by roll_over_number_series
-- every April (it replaces the start year '2026' -> '2027'):
--     <company code>-<type letter>/<FY start year>/
--   invoice      unchanged        TES/2026-27/0003
--   receipt      R                TES-R/2026/0001
--   quotation    Q                TES-Q/2026/0001
--   proforma     P                TES-P/2026/0001
--   voucher      V                TES-V/2026/0001
--   credit note  C                TES-C/2026/0001
--   debit note   D                TES-D/2026/0001
-- Company code = the letters before the first "/" of the company's invoice
-- prefix (TES, BLR, CBE, ARN …); a company whose invoice prefix has no
-- letters (Arun Packers and Couriers: "2026/") gets a 3-letter code from
-- its slug, made unique the same way new companies get theirs.
--
-- Arun, 3 Nov: used series keep their old prefix; the new rule applies
-- going forward. So existing rows change ONLY where nothing has been
-- issued yet (last_number = 0). Any row whose new prefix would clash is
-- skipped with a NOTICE instead of failing the whole script.
--
-- LR (BUG-016): next_lr_number uses lr_series; number_series 'lr' rows were
-- never used. The seeder stops creating them and unused ones are removed,
-- so there is one LR counter.

begin;

create or replace function public.doc_type_letter(p_doc_type text)
returns text
language sql
immutable
as $$
  select case p_doc_type
    when 'receipt'     then 'R'
    when 'quotation'   then 'Q'
    when 'proforma'    then 'P'
    when 'voucher'     then 'V'
    when 'credit_note' then 'C'
    when 'debit_note'  then 'D'
  end
$$;

-- The company's 3-letter document code.
create or replace function public.org_doc_code(p_org_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_inv  text;
  v_code text;
  v_slug text;
begin
  select ns.prefix into v_inv
    from public.number_series ns
   where ns.org_id = p_org_id and ns.doc_type = 'invoice'
   order by ns.fy desc nulls last
   limit 1;
  v_code := upper(regexp_replace(split_part(coalesce(v_inv, ''), '/', 1),
                                 '[^A-Za-z]', '', 'g'));
  if length(v_code) = 0 then
    select o.slug into v_slug from public.organizations o where o.id = p_org_id;
    v_code := upper(regexp_replace(coalesce(v_slug, 'org'), '[^A-Za-z]', '', 'g'));
  end if;
  if length(v_code) = 0 then v_code := 'ORG'; end if;
  return substr(v_code, 1, 3);
end;
$$;

-- A free prefix for one document type of one company and FY.
create or replace function public.doc_prefix_for(
  p_org_id uuid, p_doc_type text, p_fy text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_letter text := public.doc_type_letter(p_doc_type);
  v_base   text := public.org_doc_code(p_org_id);
  v_code   text;
  v_year   text := left(coalesce(p_fy, public.current_fy_ist()), 4);
  v_try    int := 0;
  v_prefix text;
begin
  if v_letter is null then
    return null;
  end if;
  v_code := v_base;
  loop
    v_prefix := v_code || '-' || v_letter || '/' || v_year || '/';
    exit when public.doc_prefix_conflict(v_prefix, p_org_id) is null;
    v_try := v_try + 1;
    if v_try > 99 then
      raise exception 'Could not find a free % prefix for org %',
        p_doc_type, p_org_id using errcode = 'P0001';
    end if;
    v_code := substr(v_base, 1, 3 - length(v_try::text)) || v_try::text;
  end loop;
  return v_prefix;
end;
$$;

-- New companies: invoice keeps the branded prefix, the rest get their own.
create or replace function public.seed_org_number_series(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_fy     text := public.current_fy_ist();
  v_prefix text;
begin
  v_prefix := public.seed_prefix_for_org(p_org_id, v_fy);

  -- Invoice first: org_doc_code() reads the company code from it.
  insert into public.number_series
    (org_id, doc_type, branch, fy, prefix, padding, last_number, active)
  values (p_org_id, 'invoice', null, v_fy, v_prefix, 4, 0, true)
  on conflict (org_id, doc_type, coalesce(branch, ''), coalesce(fy, ''))
  do nothing;

  insert into public.number_series
    (org_id, doc_type, branch, fy, prefix, padding, last_number, active)
  select p_org_id, d.doc_type, null, v_fy,
         public.doc_prefix_for(p_org_id, d.doc_type, v_fy), 4, 0, true
  from (values ('proforma'), ('receipt'), ('quotation'), ('voucher'),
               ('credit_note'), ('debit_note')) as d(doc_type)
  on conflict (org_id, doc_type, coalesce(branch, ''), coalesce(fy, ''))
  do nothing;

  insert into public.number_series
    (org_id, doc_type, branch, fy, prefix, padding, last_number, active)
  select p_org_id, d.doc_type, null, v_fy, d.prefix, 4, 0, true
  from (values ('claim', 'CLM-'), ('contract', 'CTR-'), ('grn', 'GRN-'),
               ('payslip', 'PS-'), ('po', 'PO-'), ('storage_job', 'STG-'))
       as d(doc_type, prefix)
  on conflict (org_id, doc_type, coalesce(branch, ''), coalesce(fy, ''))
  do nothing;

  -- Order ids (20261101 migration): not FY-scoped.
  insert into public.number_series
    (org_id, doc_type, branch, fy, prefix, padding, last_number, active)
  values (p_org_id, 'order', null, null, 'ORD-', 4, 1000, true)
  on conflict (org_id, doc_type, coalesce(branch, ''), coalesce(fy, ''))
  do nothing;
end;
$function$;

-- Existing companies: unused series only, one row at a time.
do $upd$
declare
  r        record;
  v_new    text;
  v_done   int := 0;
  v_skip   int := 0;
begin
  for r in
    select ns.ctid as rid, ns.org_id, ns.doc_type, ns.fy, ns.prefix
      from public.number_series ns
     where ns.doc_type in ('receipt', 'quotation', 'proforma', 'voucher',
                           'credit_note', 'debit_note')
       and ns.fy is not null
       and ns.last_number = 0
     order by ns.org_id, ns.fy, ns.doc_type
  loop
    begin
      v_new := public.doc_prefix_for(r.org_id, r.doc_type, r.fy);
      update public.number_series set prefix = v_new where ctid = r.rid;
      v_done := v_done + 1;
    exception when others then
      v_skip := v_skip + 1;
      raise notice 'Skipped % % % (%): %', r.org_id, r.doc_type, r.fy,
        r.prefix, sqlerrm;
    end;
  end loop;
  raise notice 'Prefixes changed: %, skipped: %', v_done, v_skip;
end
$upd$;

-- One LR counter: drop never-used number_series 'lr' rows.
delete from public.number_series where doc_type = 'lr' and last_number = 0;

do $post$
declare v_bad text;
begin
  select string_agg(prefix, ', ') into v_bad
    from public.number_series
   where prefix !~ '^[A-Za-z0-9/-]{1,12}$';
  if v_bad is not null then
    raise exception 'POSTFLIGHT: prefix outside the 12-char CHECK: %', v_bad;
  end if;
end
$post$;

commit;

-- Check (TEST Movers): receipt 2026-27 keeps TES/2026-27/ (2 issued);
-- quotation 2026-27 becomes TES-Q/2026/, quotation 2027-28 TES-Q/2027/.
-- select doc_type, fy, prefix, last_number from number_series
--  where org_id = '2180a9a6-1790-424e-b41f-b1589690b540' order by doc_type, fy;
