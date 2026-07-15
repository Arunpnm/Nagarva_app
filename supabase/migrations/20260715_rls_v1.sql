-- ============================================================
-- NAGARVA RLS MIGRATION V1 — Tenant isolation
-- Applied to nagarva-demo (hqqcapifefsaqvotqvlt) on 2026-07-15
-- Replay on any new environment (e.g. production) as-is.
-- ============================================================

-- 1. HELPERS (security definer avoids policy recursion)
create or replace function public.current_org_ids()
returns setof uuid
language sql security definer set search_path = public stable
as $$ select org_id from org_members where user_id = auth.uid() $$;

create or replace function public.is_platform_admin()
returns boolean
language sql security definer set search_path = public stable
as $$ select exists (select 1 from platform_admins where user_id = auth.uid()) $$;

-- 2. ORG-SCOPED TABLES (everything with org_id)
do $$
declare
  t text;
  tables text[] := array[
    'attendance','complaints','customer_surveys','expenses','leads',
    'materials','order_staff','order_tracking','orders','pricing_config',
    'quotations','reminders','settings','staff','staff_advances',
    'transactions','vehicle_trips','vehicles'];
begin
  foreach t in array tables loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists org_isolation on public.%I', t);
    execute format(
      'create policy org_isolation on public.%I for all to authenticated
       using (org_id in (select current_org_ids()) or is_platform_admin())
       with check (org_id in (select current_org_ids()) or is_platform_admin())', t);
  end loop;
end $$;

-- 3. ORGANIZATIONS
alter table public.organizations enable row level security;
drop policy if exists org_select on public.organizations;
drop policy if exists org_insert on public.organizations;
drop policy if exists org_update on public.organizations;
create policy org_select on public.organizations for select to authenticated
  using (id in (select current_org_ids()) or is_platform_admin());
create policy org_insert on public.organizations for insert to authenticated
  with check (true);
create policy org_update on public.organizations for update to authenticated
  using (id in (select current_org_ids()) or is_platform_admin());

-- 4. ORG_MEMBERS
alter table public.org_members enable row level security;
drop policy if exists members_select on public.org_members;
drop policy if exists members_insert on public.org_members;
create policy members_select on public.org_members for select to authenticated
  using (user_id = auth.uid() or is_platform_admin());
create policy members_insert on public.org_members for insert to authenticated
  with check (user_id = auth.uid());

-- 5. SUBSCRIPTION_PLANS (read-only, managed via dashboard)
alter table public.subscription_plans enable row level security;
drop policy if exists plans_select on public.subscription_plans;
create policy plans_select on public.subscription_plans for select
  to authenticated, anon using (active = true);

-- 6. PLATFORM_ADMINS
alter table public.platform_admins enable row level security;
drop policy if exists admins_select on public.platform_admins;
create policy admins_select on public.platform_admins for select to authenticated
  using (user_id = auth.uid());

-- 7. VIEWS: respect RLS of underlying tables
alter view public.advances_view set (security_invoker = on);
alter view public.attendance_view set (security_invoker = on);
alter view public.branch_kpis_view set (security_invoker = on);
alter view public.dashboard_kpis_view set (security_invoker = on);
alter view public.reminders_view set (security_invoker = on);
alter view public.trips_view set (security_invoker = on);

-- ============================================================
-- SEED (run once per environment, adjust IDs to that environment):
-- Link the org owner's auth user to their organization.
-- insert into org_members (org_id, user_id, role)
-- values ('<org_id>', '<owner_auth_user_id>', 'owner');
--
-- KNOWN GAPS (fixed in V2): public quotation/survey token access,
-- member invites, organizations.active enforcement, trial expiry,
-- role-aware finance policies, platform_admins seeding.
-- ============================================================