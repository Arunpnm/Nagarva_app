-- ============================================================================
-- Nagarva Supabase (hqqcapifefsaqvotqvlt) — Phase 1: add org_id everywhere
-- ============================================================================
-- CLAUDE.md "Multi-tenancy status": org_id exists on only `staff` and
-- `org_members` today. This migration adds it to the rest of the core
-- business tables so the client-side org_id filters added in this session
-- (see lib/*_page/*_widget.dart — search "AppSession.instance.currentOrgId")
-- actually work instead of erroring with "column org_id does not exist".
--
-- RUN THIS BEFORE re-running/updating views_dashboard_and_ops.sql, and
-- BEFORE reloading any page that now filters by org_id (orders, leads,
-- expenses, vehicles, attendance, staff_advances, vehicle_trips, reminders,
-- quotations, materials, settings, complaints, order_staff, order_tracking,
-- pricing_config, transactions) — those pages will throw PGRST errors until
-- this runs.
--
-- ASSUMPTIONS (verify before running):
--  1. APC (Arun Packers and Couriers) is already seeded as a row in
--     `public.organizations` with slug = 'apc'. If your slug differs, edit
--     the `apc_slug` value in the DO block below before running.
--  2. This does NOT add RLS policies or NOT NULL constraints yet — that is
--     still tracked as a separate Phase 0 task (RLS policies per org). This
--     migration only adds the column, backfills existing rows to APC, and
--     indexes it, so client-side filtering (the interim approach already in
--     use everywhere else) works uniformly.
--  3. If a table already has org_id (e.g. a prior partial migration), the
--     `add column if not exists` guards make this safe to re-run.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Add the column (nullable for now — see assumption #2 above)
-- ---------------------------------------------------------------------------
alter table public.orders          add column if not exists org_id uuid references public.organizations(id);
alter table public.leads           add column if not exists org_id uuid references public.organizations(id);
alter table public.expenses        add column if not exists org_id uuid references public.organizations(id);
alter table public.vehicles        add column if not exists org_id uuid references public.organizations(id);
alter table public.attendance      add column if not exists org_id uuid references public.organizations(id);
alter table public.staff_advances  add column if not exists org_id uuid references public.organizations(id);
alter table public.vehicle_trips   add column if not exists org_id uuid references public.organizations(id);
alter table public.reminders       add column if not exists org_id uuid references public.organizations(id);
alter table public.quotations      add column if not exists org_id uuid references public.organizations(id);
alter table public.materials       add column if not exists org_id uuid references public.organizations(id);
alter table public.settings        add column if not exists org_id uuid references public.organizations(id);
alter table public.complaints      add column if not exists org_id uuid references public.organizations(id);
alter table public.order_staff     add column if not exists org_id uuid references public.organizations(id);
alter table public.order_tracking  add column if not exists org_id uuid references public.organizations(id);
alter table public.pricing_config  add column if not exists org_id uuid references public.organizations(id);
alter table public.transactions    add column if not exists org_id uuid references public.organizations(id);

-- ---------------------------------------------------------------------------
-- 2. Backfill existing rows to APC (tenant #1) so nothing already in the
--    database becomes invisible to the app once client-side filtering by
--    org_id goes live.
-- ---------------------------------------------------------------------------
do $$
declare
  apc_slug text := 'apc';   -- EDIT if APC's real slug/name differs
  apc_org_id uuid;
begin
  select id into apc_org_id from public.organizations where slug = apc_slug limit 1;

  if apc_org_id is null then
    raise notice 'No organization found with slug = %. Backfill skipped — '
                  'set org_id manually once you know APC''s org row id.', apc_slug;
    return;
  end if;

  update public.orders         set org_id = apc_org_id where org_id is null;
  update public.leads          set org_id = apc_org_id where org_id is null;
  update public.expenses       set org_id = apc_org_id where org_id is null;
  update public.vehicles       set org_id = apc_org_id where org_id is null;
  update public.attendance     set org_id = apc_org_id where org_id is null;
  update public.staff_advances set org_id = apc_org_id where org_id is null;
  update public.vehicle_trips  set org_id = apc_org_id where org_id is null;
  update public.reminders      set org_id = apc_org_id where org_id is null;
  update public.quotations     set org_id = apc_org_id where org_id is null;
  update public.materials      set org_id = apc_org_id where org_id is null;
  update public.settings       set org_id = apc_org_id where org_id is null;
  update public.complaints     set org_id = apc_org_id where org_id is null;
  update public.order_staff    set org_id = apc_org_id where org_id is null;
  update public.order_tracking set org_id = apc_org_id where org_id is null;
  update public.pricing_config set org_id = apc_org_id where org_id is null;
  update public.transactions   set org_id = apc_org_id where org_id is null;

  -- staff/org_members already have org_id per CLAUDE.md, but backfill any
  -- stray nulls too so SalaryPage's org_id filter doesn't hide legacy rows.
  update public.staff set org_id = apc_org_id where org_id is null;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Index org_id on every table it was just added to (client-side filters
--    turn into `where org_id = $1` on every one of these — this is the
--    highest-value index in a multi-tenant schema).
-- ---------------------------------------------------------------------------
create index if not exists idx_orders_org_id          on public.orders(org_id);
create index if not exists idx_leads_org_id            on public.leads(org_id);
create index if not exists idx_expenses_org_id         on public.expenses(org_id);
create index if not exists idx_vehicles_org_id         on public.vehicles(org_id);
create index if not exists idx_attendance_org_id       on public.attendance(org_id);
create index if not exists idx_staff_advances_org_id   on public.staff_advances(org_id);
create index if not exists idx_vehicle_trips_org_id    on public.vehicle_trips(org_id);
create index if not exists idx_reminders_org_id        on public.reminders(org_id);
create index if not exists idx_quotations_org_id       on public.quotations(org_id);
create index if not exists idx_materials_org_id        on public.materials(org_id);
create index if not exists idx_settings_org_id         on public.settings(org_id);
create index if not exists idx_complaints_org_id       on public.complaints(org_id);
create index if not exists idx_order_staff_org_id      on public.order_staff(org_id);
create index if not exists idx_order_tracking_org_id   on public.order_tracking(org_id);
create index if not exists idx_pricing_config_org_id   on public.pricing_config(org_id);
create index if not exists idx_transactions_org_id     on public.transactions(org_id);
create index if not exists idx_staff_org_id            on public.staff(org_id);

-- ============================================================================
-- After running: re-run (or run for the first time) the updated
-- supabase/views_dashboard_and_ops.sql, which now selects org_id through so
-- the app can filter dashboard_kpis_view/branch_kpis_view by org too.
-- ============================================================================
