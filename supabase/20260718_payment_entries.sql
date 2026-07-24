-- 20260718_payment_entries.sql
-- Week 3a: real payment collection (part-payments with mode), replacing the
-- old flow that overwrote orders.advance_paid with whatever was typed.
--
-- Model (matches how APC actually operates — receipts, partial payments):
--   * payment_entries: one row per collection (amount, mode cash/upi/bank,
--     note, received_at). Source of truth for money collected after the
--     booking advance.
--   * orders.paid_total: denormalised sum of that order's entries, kept
--     correct by trigger, so dashboards/lists don't need a join.
--   * orders.payment_status: auto-maintained by the same trigger —
--     'paid' when advance + collected >= amount, 'partial' when something
--     was collected, 'pending' otherwise. Manual status picking is gone.
--
-- Convention: commit first, then run in the Supabase SQL editor
-- (nagarva project hqqcapifefsaqvotqvlt). Safe to re-run.

-- 1. Table ------------------------------------------------------------------
create table if not exists public.payment_entries (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id),
  -- orders.id is TEXT in this schema (human-readable ids like NGV-1001),
  -- not uuid — the first version of this file declared uuid and the FK
  -- failed with 42804. Matched to the real column type now.
  order_id    text not null references public.orders(id),
  amount      numeric not null check (amount > 0),
  mode        text not null default 'cash',   -- cash | upi | bank
  note        text,
  received_at date not null default current_date,
  created_at  timestamptz not null default now()
);

create index if not exists payment_entries_order_idx
  on public.payment_entries (order_id);
create index if not exists payment_entries_org_date_idx
  on public.payment_entries (org_id, received_at desc);

-- 2. RLS — same org_isolation pattern as rls_v1 -----------------------------
alter table public.payment_entries enable row level security;
drop policy if exists org_isolation on public.payment_entries;
create policy org_isolation on public.payment_entries for all to authenticated
  using (org_id in (select current_org_ids()) or is_platform_admin())
  with check (org_id in (select current_org_ids()) or is_platform_admin());

-- 3. orders.paid_total ------------------------------------------------------
alter table public.orders
  add column if not exists paid_total numeric not null default 0;

-- 4. Trigger: keep paid_total + payment_status correct ----------------------
create or replace function public.sync_order_paid_total()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
  v_order_id text;
  v_paid numeric;
  v_amount numeric;
  v_advance numeric;
begin
  v_order_id := coalesce(new.order_id, old.order_id);
  select coalesce(sum(amount), 0) into v_paid
    from payment_entries where order_id = v_order_id;
  select coalesce(amount, 0), coalesce(advance_paid, 0)
    into v_amount, v_advance
    from orders where id = v_order_id;
  update orders set
    paid_total = v_paid,
    payment_status = case
      when v_amount > 0 and (v_paid + v_advance) >= v_amount then 'paid'
      when (v_paid + v_advance) > 0 then 'partial'
      else 'pending'
    end
  where id = v_order_id;
  return coalesce(new, old);
end $$;

drop trigger if exists trg_sync_order_paid_total on public.payment_entries;
create trigger trg_sync_order_paid_total
  after insert or update or delete on public.payment_entries
  for each row execute function public.sync_order_paid_total();

-- 5. Backfill: recompute paid_total for existing orders (no-op on fresh DB) -
update public.orders o set paid_total = coalesce(p.total, 0)
from (select order_id, sum(amount) as total
        from public.payment_entries group by order_id) p
where p.order_id = o.id;

-- 6. Fix the same type bug in notifications (20260717 file declared the
--    ref columns uuid; orders.id is text, so the supervisor-assignment
--    trigger would have errored the first time it fired). Text accepts
--    uuid values via implicit cast, so converting both is safe either way.
alter table public.notifications
  alter column ref_order_id type text using ref_order_id::text;
alter table public.notifications
  alter column ref_lead_id type text using ref_lead_id::text;
