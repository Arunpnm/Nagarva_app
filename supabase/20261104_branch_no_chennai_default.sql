-- 20261104_branch_no_chennai_default.sql  (4 Nov 2026, BUG-062)
--
-- WHAT: leads.branch, orders.branch and staff.branch all default to
-- 'Chennai' -- APC's own branch, applied to every tenant. Each column has
-- an FK (org_id, branch) -> branches(org_id, name), so a row saved without
-- a branch either fails with a raw foreign-key error (most orgs) or lands
-- silently in a "Chennai" branch the vendor never chose (any org that has
-- one). A default branch is a decision the vendor makes, never the platform.
--
-- ALSO: back-fills a NULL branch on orders/leads/staff ONLY where the org
-- has exactly one branch -- there is then no choice to make. A NULL branch
-- is invisible to every staff session (branch_isolation compares
-- branch = p_branch and NULL matches nobody), which is why TEST Helper
-- Arjun's Rs600 for order 1001 never reached his My Earnings and Monday
-- stayed blank in his week. Measured 4 Nov 2026: exactly ONE such row in
-- the whole database (TEST-MOVERS-PVT-LTD-1001). Multi-branch orgs are
-- left alone: picking a branch for them would be inventing one.
--
-- Run the WHOLE file in the SQL editor. One transaction; any failed
-- assertion rolls everything back.

begin;

-- ---------- preflight -------------------------------------------------
do $$
declare v text;
begin
  foreach v in array array['leads','orders','staff'] loop
    if (select column_default from information_schema.columns
         where table_schema = 'public' and table_name = v
           and column_name = 'branch') is distinct from '''Chennai''::text' then
      raise exception '%.branch default is not ''Chennai'' -- already applied, or changed since 4 Nov 2026. Read the column before re-running.', v;
    end if;
  end loop;
end $$;

-- ---------- change ----------------------------------------------------
alter table public.leads  alter column branch drop default;
alter table public.orders alter column branch drop default;
alter table public.staff  alter column branch drop default;

with one as (
  select org_id, min(name) as name
    from public.branches group by org_id having count(*) = 1
)
update public.orders t set branch = one.name
  from one where t.org_id = one.org_id and t.branch is null;

with one as (
  select org_id, min(name) as name
    from public.branches group by org_id having count(*) = 1
)
update public.leads t set branch = one.name
  from one where t.org_id = one.org_id and t.branch is null;

with one as (
  select org_id, min(name) as name
    from public.branches group by org_id having count(*) = 1
)
update public.staff t set branch = one.name
  from one where t.org_id = one.org_id and t.branch is null;

-- ---------- postflight ------------------------------------------------
do $$
declare v text; n int;
begin
  foreach v in array array['leads','orders','staff'] loop
    if (select column_default from information_schema.columns
         where table_schema = 'public' and table_name = v
           and column_name = 'branch') is not null then
      raise exception '%.branch still has a default after the change', v;
    end if;
    execute format(
      'select count(*) from public.%I t
        where t.branch is null
          and t.org_id in (select org_id from public.branches
                            group by org_id having count(*) = 1)', v)
      into n;
    if n <> 0 then
      raise exception '% rows in %.branch still NULL in single-branch orgs', n, v;
    end if;
  end loop;
  if (select branch from public.orders
       where id = 'TEST-MOVERS-PVT-LTD-1001') is distinct from 'Head Office' then
    raise exception 'TEST-MOVERS-PVT-LTD-1001 did not get Head Office';
  end if;
end $$;

commit;
