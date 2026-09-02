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

  -- Guarded so this script runs in either order relative to
  -- 20260902_doc_prefix_identity.sql, which is what creates this table.
  if to_regclass('public.doc_prefix_reservations') is not null then
    delete from public.doc_prefix_reservations where org_id = v_org;
  end if;

  delete from public.org_members    where org_id = v_org;
  delete from public.organizations  where id     = v_org;

  raise notice 'sandbox org dropped after % pass(es)', v_pass;
end;
$do$;

-- POSTFLIGHT. Expect exactly three orgs and no shared invoice prefix.
--
-- ORDERING NOTE. Until this script runs, APC and the sandbox BOTH carry
-- prefix '2026/', so the "zero shared prefixes" assertion at the end of
-- 20260902_doc_prefix_identity.sql will return one row on its first run.
-- That is expected, not a failure of that migration: its trigger fires
-- on INSERT/UPDATE and cannot retroactively split two rows that already
-- shared a prefix before it existed. The assertion below is the one that
-- must come back empty.
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
