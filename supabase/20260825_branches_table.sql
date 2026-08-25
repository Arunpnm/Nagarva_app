-- =====================================================================
-- 20260825_branches_table.sql
--
-- GAP 1 / TIER 1 of the branch architecture work: the `branches` table,
-- backfill, and referential integrity on the 22 tables that carry a
-- branch. Nothing here changes RLS — Class A policies are the NEXT
-- tier, and must not start until this one is device-verified.
--
-- =====================================================================
-- ONE DESIGN DECISION MADE HERE, FLAG IT BEFORE RUNNING
-- =====================================================================
-- The instruction was "branch columns become FKs instead of free text".
-- This implements that with a COMPOSITE NATURAL KEY —
-- `(org_id, branch) references branches(org_id, name)` — rather than
-- replacing 22 text columns with a uuid surrogate.
--
-- Reason is blast radius, and it is large:
--   * `current_staff_branch_or_owner(org_id, branch)` compares TEXT.
--     A uuid column means rewriting that helper AND all 7 live
--     branch_isolation policies in the same migration that changes the
--     data type — i.e. changing the security boundary and the schema
--     at once, on a boundary already verified working on a device.
--   * 22 tables x every Dart query that reads, filters or writes
--     `branch` would have to change in lockstep, or fail closed.
--   * `staff.branch` is read directly by the app in several places.
--
-- The composite FK gets the actual goal — no invented branch strings,
-- referential integrity, rename handled by ON UPDATE CASCADE — with
-- zero change to the helper, the policies, or app code. A surrogate id
-- can still be introduced later as an additive column if it is ever
-- wanted; this does not foreclose it.
--
-- If you want the surrogate instead, say so and this becomes a
-- different migration. Do not run this one and then convert later
-- without re-planning: doing both is strictly more work than doing
-- either.
--
-- =====================================================================
-- WHAT IS DELIBERATELY LEFT NULL
-- =====================================================================
--   * `state_code` on every branch. The APC GSTIN(33 = Tamil Nadu)
--     versus Bengaluru-address contradiction is with your CA and
--     unresolved. Guessing here would seed the exact wrong value into
--     the place GST place-of-supply will later read from — see
--     NAGARVA_GST_SPEC.md §6.1. Left NULL on purpose.
--   * `gstin` on every branch. Nullable by design: same-state branches
--     share the org GSTIN, different-state branches need their own.
--     Which structure APC uses is part of the same CA question.
--   * `manager_staff_id` on Bengaluru and Coimbatore. Only ONE staff
--     row has role='manager' (Rajesh Kumar, Chennai). Bengaluru's
--     senior person is a supervisor (Praveen S) and Coimbatore's is a
--     helper (Karthik V). Assigning either as branch manager is a
--     business decision, not a backfill.
--
-- Hand-run by Arun. Not executed by an agent.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- PREFLIGHT
-- ---------------------------------------------------------------------
do $$
declare v_bad text; v_dupe int;
begin
  if to_regclass('public.branches') is not null then
    raise exception 'PREFLIGHT: public.branches already exists.';
  end if;

  -- Every branch string in the database must be one of the values this
  -- migration is about to create, or the FKs at the end will fail after
  -- the table is already built. Checking up front turns that into a
  -- clean abort.
  with src as (
    select distinct org_id, branch from (
      select org_id, branch from orders          where branch is not null
      union all select org_id, branch from staff           where branch is not null
      union all select org_id, branch from leads           where branch is not null
      union all select org_id, branch from customers       where branch is not null
      union all select org_id, branch from attendance      where branch is not null
      union all select org_id, branch from tasks           where branch is not null
      union all select org_id, branch from trips           where branch is not null
      union all select org_id, branch from reviews         where branch is not null
      union all select org_id, branch from number_series   where branch is not null
      union all select org_id, branch from lr_series       where branch is not null
      union all select org_id, branch from lr_register     where branch is not null
      union all select org_id, branch from materials       where branch is not null
      union all select org_id, branch from stock_movements where branch is not null
      union all select org_id, branch from rate_cards      where branch is not null
      union all select org_id, branch from bank_accounts   where branch is not null
      union all select org_id, branch from journal_entries where branch is not null
      union all select org_id, branch from journal_lines   where branch is not null
      union all select org_id, branch from grn             where branch is not null
      union all select org_id, branch from marketing_spend where branch is not null
      union all select org_id, branch from payroll_runs    where branch is not null
      union all select org_id, branch from purchase_orders where branch is not null
      union all select org_id, branch from warehouses      where branch is not null
    ) u
  )
  select string_agg(distinct branch, ', ') into v_bad
  from src
  where branch <> trim(branch)          -- stray whitespace
     or branch is distinct from initcap(branch);  -- casing variants

  if v_bad is not null then
    raise exception
      'PREFLIGHT: branch value(s) need normalising before backfill: %. '
      'A trailing space makes two branches out of one.', v_bad;
  end if;

  -- Any branch string attached to an org_id that does not exist would
  -- silently vanish from the backfill and then fail the FK.
  select count(*) into v_dupe
  from (select distinct org_id from orders where branch is not null and org_id is not null) o
  where not exists (select 1 from organizations g where g.id = o.org_id);
  if v_dupe > 0 then
    raise exception 'PREFLIGHT: % orphan org_id(s) carry a branch.', v_dupe;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------
create table public.branches (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null references public.organizations(id) on delete cascade,
  name             text not null,
  address          text,
  city             text,
  state            text,
  -- Integer to match organizations.state_code. NULL until the CA
  -- resolves the APC GSTIN/address contradiction — see header.
  state_code       integer,
  -- NULLABLE BY DESIGN. A same-state branch bills under the org GSTIN;
  -- a different-state branch is a separate GST registration and needs
  -- its own. Both structures occur in this market, so neither can be
  -- the schema's assumption.
  gstin            text,
  manager_staff_id uuid references public.staff(id) on delete set null,
  active           boolean not null default true,
  created_at       timestamptz not null default now(),

  -- This is what makes the composite FKs below possible, and what stops
  -- two spellings of the same branch existing inside one org.
  constraint branches_org_name_uniq unique (org_id, name),
  constraint branches_name_not_blank check (length(trim(name)) > 0),
  -- A GSTIN's first two digits ARE its state code. If a branch declares
  -- both, they must agree — this is the check that would have caught
  -- the APC contradiction at entry time.
  constraint branches_gstin_matches_state check (
    gstin is null
    or state_code is null
    or left(gstin, 2) = lpad(state_code::text, 2, '0')
  )
);

comment on table public.branches is
  'Branch master. Branches live INSIDE an org and are isolated by the '
  'restrictive branch_isolation policies, with owner falling through to '
  'a merged view. Branches are deliberately NOT separate orgs: org RLS '
  'is absolute, and a merged all-branch view would require punching '
  'through tenant isolation.';

comment on column public.branches.gstin is
  'Nullable. Same-state branches share the org GSTIN; different-state '
  'branches need their own registration. Do not make this NOT NULL.';

create index branches_org_idx on public.branches (org_id) where active;

-- ---------------------------------------------------------------------
-- RLS — org-level only at this tier.
--
-- Deliberately NOT branch-scoped: a branch manager needs to resolve
-- branch names for display, and scoping the branch list itself is a
-- separate decision that belongs with the Class A tier, not smuggled
-- in here.
-- ---------------------------------------------------------------------
alter table public.branches enable row level security;

create policy org_isolation on public.branches
  for all
  using (org_id in (select current_org_ids()) or is_platform_admin())
  with check (org_id in (select current_org_ids()) or is_platform_admin());

grant select, insert, update, delete on public.branches to authenticated;
grant select on public.branches to anon;

-- ---------------------------------------------------------------------
-- Backfill — derived from what actually exists, never invented.
-- ---------------------------------------------------------------------
insert into public.branches (org_id, name, city, manager_staff_id)
select s.org_id,
       s.branch,
       -- Every current branch is named for its city. Recorded rather
       -- than left null so the GST place-of-supply work has something
       -- to reconcile against; correct it per branch if that stops
       -- being true.
       s.branch,
       (select st.id from public.staff st
         where st.org_id = s.org_id and st.branch = s.branch
           and lower(st.role) = 'manager' and coalesce(st.active, true)
         order by st.name limit 1)
from (
  select distinct org_id, branch from (
    select org_id, branch from orders          where branch is not null
    union all select org_id, branch from staff           where branch is not null
    union all select org_id, branch from leads           where branch is not null
    union all select org_id, branch from customers       where branch is not null
    union all select org_id, branch from attendance      where branch is not null
    union all select org_id, branch from tasks           where branch is not null
    union all select org_id, branch from trips           where branch is not null
    union all select org_id, branch from reviews         where branch is not null
    union all select org_id, branch from number_series   where branch is not null
    union all select org_id, branch from lr_series       where branch is not null
    union all select org_id, branch from lr_register     where branch is not null
    union all select org_id, branch from materials       where branch is not null
    union all select org_id, branch from stock_movements where branch is not null
    union all select org_id, branch from rate_cards      where branch is not null
    union all select org_id, branch from bank_accounts   where branch is not null
    union all select org_id, branch from journal_entries where branch is not null
    union all select org_id, branch from journal_lines   where branch is not null
    union all select org_id, branch from grn             where branch is not null
    union all select org_id, branch from marketing_spend where branch is not null
    union all select org_id, branch from payroll_runs    where branch is not null
    union all select org_id, branch from purchase_orders where branch is not null
    union all select org_id, branch from warehouses      where branch is not null
  ) u
  where org_id is not null
) s;

-- ---------------------------------------------------------------------
-- Referential integrity.
--
-- ON UPDATE CASCADE is the point: renaming a branch in `branches`
-- rewrites every reference atomically, which is precisely what free
-- text could never do.
--
-- ON DELETE RESTRICT, not CASCADE — deleting a branch must not silently
-- delete its orders. Deactivate (`active = false`) instead.
--
-- These FKs are added to ALL 22 branch-carrying tables, including the
-- six that will NEVER get a branch_isolation policy (number_series,
-- lr_series, rate_cards, bank_accounts, journal_entries,
-- journal_lines). Integrity and visibility are different questions:
-- those tables may legitimately carry a branch tag, they simply must
-- not be branch-FILTERED. See the NG-010 note in CLAUDE.md.
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    -- already branch-isolated (7)
    'orders','customers','leads','attendance','tasks','trips','reviews',
    -- Class A, to be scoped next tier (7)
    'staff','lr_register','warehouses','grn','purchase_orders',
    'payroll_runs','marketing_spend',
    -- carry a branch tag but must NEVER be branch-filtered (6)
    'number_series','lr_series','rate_cards','bank_accounts',
    'journal_entries','journal_lines',
    -- remaining Class A (2)
    'materials','stock_movements'
  ]
  loop
    execute format(
      'alter table public.%I
         add constraint %I foreign key (org_id, branch)
         references public.branches (org_id, name)
         on update cascade on delete restrict',
      t, t || '_branch_fk');
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- POSTFLIGHT
-- ---------------------------------------------------------------------
do $$
declare v_n int; v_fks int; v_orphan int;
begin
  select count(*) into v_n from public.branches;
  if v_n = 0 then
    raise exception 'POSTFLIGHT: no branches were backfilled.';
  end if;

  select count(*) into v_fks
  from pg_constraint where conname like '%\_branch\_fk' and contype = 'f';
  if v_fks <> 22 then
    raise exception 'POSTFLIGHT: expected 22 branch FKs, found %.', v_fks;
  end if;

  -- The FKs guarantee this, but assert it anyway: an unmatched branch
  -- string anywhere would mean the backfill missed a source table.
  select count(*) into v_orphan
  from orders o
  where o.branch is not null
    and not exists (select 1 from public.branches b
                     where b.org_id = o.org_id and b.name = o.branch);
  if v_orphan > 0 then
    raise exception 'POSTFLIGHT: % order(s) reference an unknown branch.', v_orphan;
  end if;

  raise notice
    'POSTFLIGHT OK: % branch row(s), 22 FKs, no orphans. '
    'state_code/gstin intentionally NULL pending CA.', v_n;
end $$;

commit;

-- =====================================================================
-- VERIFY AFTER RUNNING
--
--   select name, city, state_code, gstin, manager_staff_id, active
--     from public.branches order by name;
--
-- Expect exactly 3 rows for APC: Bengaluru, Chennai, Coimbatore.
-- Chennai should have manager_staff_id set (Rajesh Kumar, the only
-- staff row with role='manager'); Bengaluru and Coimbatore NULL —
-- assign those deliberately, they are not a backfill.
-- state_code and gstin NULL on all three, pending the CA.
--
-- Then confirm the FK actually bites:
--   -- should FAIL with a foreign key violation:
--   -- update orders set branch = 'Mysuru' where id = <some id>;
--
-- NEXT TIER — Class A policies — does not start until this is
-- device-verified with BOTH Rajesh (Chennai) and Praveen S
-- (Bengaluru), which is a genuine cross-branch check rather than a
-- single-branch one.
-- =====================================================================
