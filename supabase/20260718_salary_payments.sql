-- 20260718_salary_payments.sql
-- Week 3b: staff ledger — salary payouts.
--
-- The ledger reads from three places:
--   * order_staff.salary_amount  → EARNED (attributed to the month of the
--     linked order's move_date)
--   * salary_payments (this file) → PAID OUT
--   * staff_advances (existing)   → ADVANCE BALANCE (status='pending')
-- Balance to pay = earned - paid, per month. Settling an advance flips its
-- status to 'settled' (existing semantics kept).
--
-- staff.id is uuid in this schema (verified — the notifications FK on it
-- ran clean); orders.id is text (learnt that the hard way in the
-- payment_entries migration).
--
-- Convention: commit first, then run in the Supabase SQL editor. Re-runnable.

create table if not exists public.salary_payments (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references public.organizations(id),
  staff_id   uuid not null references public.staff(id),
  amount     numeric not null check (amount > 0),
  note       text,
  paid_date  date not null default current_date,
  created_at timestamptz not null default now()
);

create index if not exists salary_payments_staff_idx
  on public.salary_payments (staff_id, paid_date desc);
create index if not exists salary_payments_org_date_idx
  on public.salary_payments (org_id, paid_date desc);

alter table public.salary_payments enable row level security;
drop policy if exists org_isolation on public.salary_payments;
create policy org_isolation on public.salary_payments for all to authenticated
  using (org_id in (select current_org_ids()) or is_platform_admin())
  with check (org_id in (select current_org_ids()) or is_platform_admin());

-- Nice-to-have for future attribution/auditing of labour entries:
alter table public.order_staff
  add column if not exists created_at timestamptz not null default now();
