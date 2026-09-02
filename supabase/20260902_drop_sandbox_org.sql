-- Drop ZZZ SANDBOX TWO - DELETE ME (f12f1dd5-9fb0-4060-8d10-6356d6bd57c9).
--
-- WHY. It still carries the old shared prefix at last_number 0, so its
-- next invoice would print a number APC has already issued. Verified
-- empty before writing this: 0 orders, 0 staff, 0 series with
-- last_number > 0. Its single org_members row is Arun's own membership;
-- the auth user is NOT touched, and APC remains his earliest membership
-- so create_org_with_owner's 'recover' path still resolves there.
--
-- HOW. Only 12 of ~116 org-scoped tables carry a foreign key to
-- organizations (CLAUDE.md's FK audit), so deleting the org row alone
-- would silently strand rows in the other ~104 -- exactly the dangling
-- expenses row found on 18 Aug 2026. This therefore sweeps every table
-- that has an org_id column rather than relying on cascades.
--
-- The retry loop exists because the sweep order is alphabetical, not
-- dependency order: where FKs DO exist a child may be visited after its
-- parent. Each pass deletes what it can and the loop repeats until a
-- pass makes no progress. For an org with no business data this settles
-- in one or two passes.

-- ALREADY APPLIED, 2 Sep 2026. The sandbox org is gone and this file is
-- spent. It is kept for the record and refuses to run again (see the
-- first check below) rather than being deleted, so the guard lesson at
-- the doc_prefix_reservations delete stays readable.

begin;

do $do$
declare
  v_org      uuid := 'f12f1dd5-9fb0-4060-8d10-6356d6bd57c9';
  v_tbl      record;
  v_deleted  bigint;
  v_progress boolean := true;
  v_pass     int := 0;
  v_left     bigint;
begin
  -- Already applied. Stop rather than doing nothing quietly - the same
  -- failure shape this script's own guard bug had.
  if not exists (select 1 from public.organizations where id = v_org) then
    raise exception
      'Sandbox org % is already gone; this script has been applied. Nothing to do.', v_org;
  end if;

  -- Refuse outright if the org acquired real data since this was written.
  execute 'select count(*) from public.orders where org_id = $1'
    into v_left using v_org;
  if v_left > 0 then
    raise exception 'Refusing to drop: org has % order(s). Re-verify before deleting.', v_left;
  end if;

  while v_progress and v_pass < 10 loop
    v_progress := false;
    v_pass := v_pass + 1;

    for v_tbl in
      select c.table_name
        from information_schema.columns c
        join information_schema.tables t
          on t.table_schema = c.table_schema and t.table_name = c.table_name
       where c.table_schema = 'public'
         and c.column_name = 'org_id'
         and t.table_type = 'BASE TABLE'
         -- org_members and organizations are removed last, by name.
         and c.table_name not in ('organizations', 'org_members')
       order by c.table_name
    loop
      begin
        execute format('delete from public.%I where org_id = $1', v_tbl.table_name)
          using v_org;
        get diagnostics v_deleted = ROW_COUNT;
        if v_deleted > 0 then
          v_progress := true;
          raise notice 'pass %: deleted % row(s) from %',
            v_pass, v_deleted, v_tbl.table_name;
        end if;
      exception
        when foreign_key_violation then
          -- A child elsewhere still references these rows. Leave them for
          -- the next pass rather than aborting the whole sweep.
          raise notice 'pass %: % deferred (fk)', v_pass, v_tbl.table_name;
      end;
    end loop;
  end loop;

  -- FIXED 2 Sep 2026. This read:
  --
  --     if to_regclass('public.doc_prefix_reservations') is not null then
  --       delete ... ;
  --     end if;
  --
  -- which was written to make run order not matter and instead made a
  -- missing dependency invisible: this script was run BEFORE
  -- 20260902_doc_prefix_identity.sql, the guard skipped, and the whole
  -- thing reported success while the identity migration had never
  -- executed. A guard that lets a script pass without doing its job is
  -- worse than no guard, because it spends the operator's attention and
  -- hands back a clean result. Assert and RAISE; never branch around an
  -- absent dependency.
  if to_regclass('public.doc_prefix_reservations') is null then
    raise exception
      'doc_prefix_reservations is missing. Run 20260902_doc_prefix_identity.sql first.';
  end if;
  delete from public.doc_prefix_reservations where org_id = v_org;

  delete from public.org_members    where org_id = v_org;
  delete from public.organizations  where id     = v_org;

  raise notice 'sandbox org dropped after % pass(es)', v_pass;
end;
$do$;

-- POSTFLIGHT. Expect exactly three orgs and no shared invoice prefix.
--
-- ORDERING NOTE, corrected 2 Sep 2026. This previously said the identity
-- migration's "zero shared prefixes" assertion would return one row on
-- its first run, because APC and the sandbox both carried '2026/'. That
-- was true when written and is no longer: this script ran first, so the
-- sandbox is gone, APC's '2026/' is unshared, and that assertion now
-- passes cleanly. There is no expected failure left there - any hit is
-- real. Re-verified against live state before the identity migration ran.
select slug, name from public.organizations order by created_at;

select o.slug, ns.prefix,
       ns.prefix || lpad((ns.last_number + 1)::text, ns.padding, '0')
         as next_invoice_would_be
  from public.number_series ns
  join public.organizations o on o.id = ns.org_id
 where ns.doc_type = 'invoice'
 order by o.slug;

-- Must return ZERO rows.
select prefix, count(distinct org_id) as orgs
  from public.number_series
 where doc_type in ('invoice','proforma','receipt','quotation',
                    'voucher','credit_note','debit_note')
 group by prefix having count(distinct org_id) > 1;

commit;
