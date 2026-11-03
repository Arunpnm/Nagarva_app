-- BUG-032 (found in the 1 Nov 2026 full test, org "TEST Movers Pvt Ltd").
--
-- A company created after 8 Sept 2026 cannot create ANY order:
--   "No active order-id series configured for org=... Seed number_series
--    (doc_type=order, fy null) before creating orders." (P0001)
--
-- 20260908_next_order_id_allocator.sql seeded the `order` counter once,
-- for the orgs that existed that day. `seed_org_number_series` (the
-- new-org seeder) was never given the row, so every org signed up since
-- then has invoice/receipt/LR/... counters but no order counter. Live on
-- 1 Nov: 3 of 6 orgs have one.
--
-- Fix: (1) the seeder also inserts the order row — fy NULL, branch NULL,
-- marker prefix 'ORD-', last_number 1000 (first id <SLUG>-1001), exactly
-- the shape the allocator migration documents; (2) backfill every org
-- that is missing it, seeded at or above any id already issued.
-- Rest of the seeder body is unchanged.

begin;

create or replace function public.seed_org_number_series(p_org_id uuid)
returns void
language plpgsql
security definer          -- unchanged from live (prosecdef = true)
set search_path = public  -- unchanged from live
as $function$
declare
  v_fy     text := public.current_fy_ist();
  v_prefix text;
begin
  v_prefix := public.seed_prefix_for_org(p_org_id, v_fy);

  insert into public.number_series
    (org_id, doc_type, branch, fy, prefix, padding, last_number, active)
  select p_org_id, d.doc_type, null, v_fy,
         case when d.branding then v_prefix else d.prefix end,
         4, 0, true
  from (values
      ('invoice',     true,  ''),
      ('proforma',    true,  ''),
      ('receipt',     true,  ''),
      ('quotation',   true,  ''),
      ('voucher',     true,  ''),
      ('credit_note', true,  ''),
      ('debit_note',  true,  ''),
      ('lr',          false, 'LR'),
      ('claim',       false, 'CLM-'),
      ('contract',    false, 'CTR-'),
      ('grn',         false, 'GRN-'),
      ('payslip',     false, 'PS-'),
      ('po',          false, 'PO-'),
      ('storage_job', false, 'STG-')
    ) as d(doc_type, branding, prefix)
  on conflict (org_id, doc_type, coalesce(branch, ''), coalesce(fy, ''))
  do nothing;

  -- Order ids: NOT FY-scoped (see 20260908_next_order_id_allocator.sql).
  insert into public.number_series
    (org_id, doc_type, branch, fy, prefix, padding, last_number, active)
  values (p_org_id, 'order', null, null, 'ORD-', 4, 1000, true)
  on conflict (org_id, doc_type, coalesce(branch, ''), coalesce(fy, ''))
  do nothing;
end;
$function$;

-- Backfill orgs created since 8 Sept.
insert into public.number_series
  (org_id, doc_type, branch, fy, prefix, padding, last_number, active)
select o.id, 'order', null, null, 'ORD-', 4,
       greatest(1000,
         coalesce((select max((substring(ord.id from '([0-9]+)$'))::bigint)
                     from public.orders ord
                    where ord.org_id = o.id and ord.id ~ '[0-9]+$'), 1000)),
       true
  from public.organizations o
 where not exists (select 1 from public.number_series ns
                    where ns.org_id = o.id and ns.doc_type = 'order')
on conflict (org_id, doc_type, coalesce(branch, ''), coalesce(fy, ''))
do nothing;

do $post$
declare v_bad text;
begin
  select string_agg(o.name, ', ') into v_bad
    from public.organizations o
   where (select count(*) from public.number_series ns
           where ns.org_id = o.id and ns.doc_type = 'order'
             and ns.fy is null and ns.branch is null and ns.active) <> 1;
  if v_bad is not null then
    raise exception 'POSTFLIGHT: org(s) without exactly one active order counter: %', v_bad;
  end if;
end
$post$;

commit;
