-- 20260717_notifications_and_settings.sql
-- In-app notifications v1 + vendor Porter preference seed.
--
-- Covers two flows Arun asked for:
--   1. Vendor (owner) gets notified when a new lead arrives.
--   2. Supervisor gets notified when an order is assigned to them.
-- Delivery in v1 is in-app via Supabase Realtime (bell in the sidebar).
-- True push (FCM) is a Week-3 item — this table is designed so an edge
-- function can later fan the same rows out to FCM without schema changes.
--
-- Convention: commit first, then apply in the Supabase SQL editor
-- (nagarva project hqqcapifefsaqvotqvlt). Safe to re-run.

-- 1. Table ------------------------------------------------------------------
create table if not exists public.notifications (
  id                 uuid primary key default gen_random_uuid(),
  org_id             uuid not null references public.organizations(id),
  -- null recipient = for the org owner/vendor account; otherwise the staff
  -- member (e.g. supervisor) it is addressed to. Staff PIN login is a
  -- device-unlock layer on top of the vendor's Supabase Auth session, so
  -- row-level isolation is per-org; per-person filtering happens client-side
  -- on this column.
  recipient_staff_id uuid references public.staff(id),
  type               text not null,          -- 'new_lead' | 'order_assigned' | ...
  title              text not null,
  body               text,
  ref_lead_id        uuid,
  ref_order_id       uuid,
  read               boolean not null default false,
  created_at         timestamptz not null default now()
);

create index if not exists notifications_org_created_idx
  on public.notifications (org_id, created_at desc);

-- 2. RLS — same org_isolation pattern as rls_v1 -----------------------------
alter table public.notifications enable row level security;
drop policy if exists org_isolation on public.notifications;
create policy org_isolation on public.notifications for all to authenticated
  using (org_id in (select current_org_ids()) or is_platform_admin())
  with check (org_id in (select current_org_ids()) or is_platform_admin());

-- 3. Realtime ---------------------------------------------------------------
do $$
begin
  alter publication supabase_realtime add table public.notifications;
exception when duplicate_object then null;
end $$;

-- 4. Trigger: new lead → notify vendor/owner --------------------------------
create or replace function public.notify_new_lead()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into notifications (org_id, recipient_staff_id, type, title, body, ref_lead_id)
  values (
    new.org_id,
    null,  -- owner/vendor
    'new_lead',
    'New lead: ' || coalesce(new.customer, 'Unknown'),
    trim(coalesce(new.from_city, '') || ' → ' || coalesce(new.to_city, '')),
    new.id
  );
  return new;
end $$;

drop trigger if exists trg_notify_new_lead on public.leads;
create trigger trg_notify_new_lead
  after insert on public.leads
  for each row execute function public.notify_new_lead();

-- 5. Trigger: supervisor assigned → notify that supervisor ------------------
create or replace function public.notify_supervisor_assigned()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if new.supervisor_id is not null
     and (tg_op = 'INSERT' or new.supervisor_id is distinct from old.supervisor_id) then
    insert into notifications (org_id, recipient_staff_id, type, title, body, ref_order_id)
    values (
      new.org_id,
      new.supervisor_id,
      'order_assigned',
      'Order assigned to you',
      trim(coalesce(new.customer, '') || ' — ' ||
           coalesce(new.from_city, '') || ' → ' || coalesce(new.to_city, '')),
      new.id
    );
  end if;
  return new;
end $$;

drop trigger if exists trg_notify_supervisor_assigned on public.orders;
create trigger trg_notify_supervisor_assigned
  after insert or update of supervisor_id on public.orders
  for each row execute function public.notify_supervisor_assigned();

-- NOTE: column names verified against the generated Dart classes: leads has
-- customer/from_city/to_city, orders has customer/from_city/to_city/
-- supervisor_id. If a column is renamed later, adjust here.

-- 6. Seed: APC uses Porter → turn the dashboard card on for tenant #1 -------
insert into public.settings (org_id, key, value, updated_at)
values ('11111111-1111-4111-8111-111111111111', 'porter_enabled', '"true"'::jsonb, now())
on conflict (org_id, key)
  do update set value = '"true"'::jsonb, updated_at = now();
