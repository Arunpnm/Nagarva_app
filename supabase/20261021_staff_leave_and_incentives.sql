-- 20261021_staff_leave_and_incentives.sql
--
-- Two People modules from the design handoff that have no table at all:
--   * Leave                  -> public.staff_leaves
--   * Overtime & incentives  -> public.staff_incentives
--
-- Neither feeds Salary or payslips yet. They are records: who was off
-- and when, and what extra a person earned and whether it was paid.
-- Wiring them into pay is a separate decision, not taken here.
--
-- No generated columns, on purpose: a generated column cannot be written
-- and the Crew Sheet spent its whole life failing on one (CLAUDE.md,
-- order_staff.ac_amount). `days` is written by the app.
--
-- RLS: read for any member of the org, write for owner/admin/manager
-- (is_org_manager), the same split Tier A/B uses for staff records.
--
-- After this runs and both tables are confirmed BY QUERY, flip
-- kStaffLeaveIncentivesLive in lib/config/app_config.dart.
--
-- Handed over unrun.

begin;

do $$
begin
  if to_regclass('public.staff') is null then
    raise exception 'public.staff does not exist — wrong database?';
  end if;
  if to_regprocedure('public.is_org_manager(uuid)') is null then
    raise exception 'is_org_manager(uuid) is missing — run the Tier A RLS migration first.';
  end if;
  if to_regprocedure('public.current_org_ids()') is null then
    raise exception 'current_org_ids() is missing.';
  end if;
  if to_regclass('public.staff_leaves') is not null
     or to_regclass('public.staff_incentives') is not null then
    raise exception 'staff_leaves / staff_incentives already exist — this migration has already run.';
  end if;
end $$;

create table public.staff_leaves (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  staff_id    uuid not null references public.staff(id) on delete cascade,
  leave_type  text not null
              check (leave_type in ('casual', 'sick', 'paid', 'unpaid', 'other')),
  from_date   date not null,
  to_date     date not null,
  days        numeric not null check (days > 0),
  status      text not null default 'approved'
              check (status in ('requested', 'approved', 'rejected')),
  reason      text,
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now(),
  check (to_date >= from_date)
);
create index staff_leaves_org_staff_idx on public.staff_leaves (org_id, staff_id, from_date);

create table public.staff_incentives (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  staff_id    uuid not null references public.staff(id) on delete cascade,
  kind        text not null check (kind in ('overtime', 'incentive', 'bonus')),
  entry_date  date not null default current_date,
  order_id    text,
  hours       numeric check (hours is null or hours > 0),
  amount      numeric not null check (amount > 0),
  note        text,
  paid        boolean not null default false,
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now()
);
create index staff_incentives_org_staff_idx on public.staff_incentives (org_id, staff_id, entry_date);

alter table public.staff_leaves enable row level security;
alter table public.staff_incentives enable row level security;

create policy staff_leaves_select on public.staff_leaves
  for select using (org_id in (select current_org_ids()));
create policy staff_leaves_insert on public.staff_leaves
  for insert with check (is_org_manager(org_id));
create policy staff_leaves_update on public.staff_leaves
  for update using (is_org_manager(org_id)) with check (is_org_manager(org_id));
create policy staff_leaves_delete on public.staff_leaves
  for delete using (is_org_manager(org_id));

create policy staff_incentives_select on public.staff_incentives
  for select using (org_id in (select current_org_ids()));
create policy staff_incentives_insert on public.staff_incentives
  for insert with check (is_org_manager(org_id));
create policy staff_incentives_update on public.staff_incentives
  for update using (is_org_manager(org_id)) with check (is_org_manager(org_id));
create policy staff_incentives_delete on public.staff_incentives
  for delete using (is_org_manager(org_id));

-- Postflight: assert the constructs, inside the transaction.
do $$
declare
  t text;
  v_rls boolean;
  v_pols int;
  v_gen int;
begin
  foreach t in array array['staff_leaves', 'staff_incentives'] loop
    select relrowsecurity into v_rls from pg_class where oid = ('public.' || t)::regclass;
    if not coalesce(v_rls, false) then
      raise exception 'RLS is off on %', t;
    end if;
    select count(*) into v_pols from pg_policies
     where schemaname = 'public' and tablename = t
       and cmd in ('SELECT', 'INSERT', 'UPDATE', 'DELETE');
    if v_pols <> 4 then
      raise exception '% has % command policies, expected 4', t, v_pols;
    end if;
    if exists (select 1 from pg_policies
                where schemaname = 'public' and tablename = t and cmd = 'ALL') then
      raise exception '% has a FOR ALL policy, which would widen writes', t;
    end if;
    select count(*) into v_gen from information_schema.columns
     where table_schema = 'public' and table_name = t and is_generated <> 'NEVER';
    if v_gen <> 0 then
      raise exception '% has % generated columns; none were intended', t, v_gen;
    end if;
  end loop;
end $$;

commit;
