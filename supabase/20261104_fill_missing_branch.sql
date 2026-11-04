-- 20261104_fill_missing_branch.sql  (4 Nov 2026, BUG-063)
--
-- WHAT WAS WRONG
-- Seven tables carry a RESTRICTIVE branch_isolation policy:
--   attendance, customers, leads, orders, reviews, tasks, trips
-- It compares branch = <the staff member's branch>, and NULL matches
-- nobody. So any row saved without a branch is
--   * invisible to every staff session, forever, and
--   * REFUSED outright when a staff session saves it
--     ("new row violates row-level security policy").
-- Several app paths save without a branch: supervisor "mark present" and
-- the job page (attendance), customer find-or-create, tasks, trips.
-- Measured 4 Nov 2026 (count(*), all tenants): attendance 11, customers 12,
-- trips 6, tasks 1 rows with NULL branch -- including the live Arun Packers
-- company. Example: TEST Helper Arjun's own "present" for 2 Nov exists but
-- he cannot see it, so his week strip shows Monday blank.
--
-- THE FIX
-- 1. A BEFORE INSERT trigger on those seven tables. Only when branch is
--    NULL, it fills it from, in order:
--      a) the branch of the staff member saving the row (auth.uid()), or
--      b) the company's branch, when the company has exactly ONE.
--    Otherwise it stays NULL (a multi-branch owner saving without choosing
--    -- the screen must ask). It never overwrites a branch that was sent,
--    and never picks between several branches.
--    BEFORE triggers run before the RLS check, so a supervisor's save now
--    passes instead of being refused.
-- 2. A one-time back-fill of existing NULLs, ONLY in single-branch
--    companies (every company today has exactly one branch). Multi-branch
--    rows are left for a person to decide.
--
-- Run the WHOLE file. One transaction; any failed check rolls it all back.

begin;

-- ---------- preflight -------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['attendance','customers','leads','orders','reviews','tasks','trips'] loop
    if not exists (select 1 from pg_policies
                    where schemaname = 'public' and tablename = t
                      and policyname = 'branch_isolation') then
      raise exception 'public.% has no branch_isolation policy -- the list in this file is out of date; stop and re-check.', t;
    end if;
    if not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = t
                      and column_name = 'branch' and data_type = 'text') then
      raise exception 'public.%.branch is missing or not text', t;
    end if;
  end loop;
  -- The policy list must not have grown beyond these seven either.
  if (select count(distinct tablename) from pg_policies
       where schemaname = 'public' and policyname = 'branch_isolation') <> 7 then
    raise exception 'branch_isolation now covers a different set of tables than the seven named here -- update this file first.';
  end if;
end $$;

-- ---------- 1. trigger ------------------------------------------------
create or replace function public.fill_missing_branch()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v text;
begin
  if new.branch is not null or new.org_id is null then
    return new;
  end if;
  -- a) the person saving it
  select s.branch into v
    from staff s
   where s.auth_user_id = auth.uid()
     and s.org_id = new.org_id
     and s.branch is not null
   limit 1;
  -- b) the company's only branch
  if v is null then
    select min(b.name) into v
      from branches b
     where b.org_id = new.org_id
    having count(*) = 1;
  end if;
  new.branch := v;   -- still NULL if neither applies: no guessing
  return new;
end $$;

revoke all on function public.fill_missing_branch() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['attendance','customers','leads','orders','reviews','tasks','trips'] loop
    execute format('drop trigger if exists trg_fill_missing_branch on public.%I', t);
    execute format('create trigger trg_fill_missing_branch before insert on public.%I
                    for each row execute function public.fill_missing_branch()', t);
  end loop;
end $$;

-- ---------- 2. back-fill (single-branch companies only) ---------------
do $$
declare t text;
begin
  foreach t in array array['attendance','customers','leads','orders','reviews','tasks','trips'] loop
    execute format(
      'update public.%I x set branch = one.name
         from (select org_id, min(name) as name from public.branches
                group by org_id having count(*) = 1) one
        where x.org_id = one.org_id and x.branch is null', t);
  end loop;
end $$;

-- ---------- postflight ------------------------------------------------
do $$
declare t text; n int;
begin
  foreach t in array array['attendance','customers','leads','orders','reviews','tasks','trips'] loop
    -- the trigger exists, is enabled, and is BEFORE INSERT ROW
    if not exists (
      select 1 from pg_trigger g
       where g.tgrelid = format('public.%I', t)::regclass
         and g.tgname = 'trg_fill_missing_branch'
         and g.tgenabled = 'O'
         and g.tgtype = (1 | 2 | 4)   -- ROW | BEFORE | INSERT
         and g.tgfoid = 'public.fill_missing_branch()'::regprocedure) then
      raise exception 'trg_fill_missing_branch missing or wrong on public.%', t;
    end if;
    execute format(
      'select count(*) from public.%I x
        where x.branch is null
          and x.org_id in (select org_id from public.branches
                            group by org_id having count(*) = 1)', t)
      into n;
    if n <> 0 then
      raise exception '% NULL-branch rows remain in public.% (single-branch companies)', n, t;
    end if;
  end loop;
end $$;

commit;
