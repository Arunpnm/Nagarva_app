-- ============================================================================
-- 20260728_reminders_and_soft_delete.sql
--
-- Items 10 (follow-ups / reminders / call log) and 11 (soft delete app-wide).
-- One file, as requested. Idempotent — safe to re-run.
--
-- ---------------------------------------------------------------------------
-- READ THIS BEFORE RUNNING — three places the brief's spec and the live
-- schema disagree, resolved in favour of the live schema:
--
--  1. `reminders` ALREADY EXISTS. The brief describes it as a new table.
--     It is not: it has (id, org_id, lead_id, order_id, title, description,
--     due_date, done, completed, reminder_type, created_by, created_at) and
--     is read by CalendarPage through `reminders_view`. This migration
--     EXTENDS it rather than creating a second reminders table, and keeps
--     the old columns working so CalendarPage and the view do not break.
--       - The brief's `note`      -> the existing `description` column.
--       - The brief's `due_at`    -> the existing `due_date` column.
--       - The brief's `status`    -> new column, kept in sync with the
--         existing `done` boolean by a trigger (both directions), so old
--         readers and new readers agree without a Dart change.
--
--  2. Table names. The brief says `quotes`, `payments`, `fleet`. The live
--     tables are `quotations`, `payment_entries`, `vehicles`. Used the real
--     names. There is no `quotes`/`payments`/`fleet` table to alter.
--
--  3. There is no `audit_log` table. The brief says "if not, propose the
--     table" — created below.
--
-- ---------------------------------------------------------------------------
-- entity_id is TEXT throughout, deliberately: it holds either a
-- leads.id / quotations.id (uuid-as-text) or an orders.id (NGV-XXXX), so it
-- cannot be typed uuid. Any join back to a uuid PK needs `::text` on the
-- uuid side.
-- ============================================================================

begin;

-- ===========================================================================
-- ITEM 10 — reminders (EXTEND existing) + follow_up_logs (new)
-- ===========================================================================

alter table public.reminders
  add column if not exists entity_type  text,
  add column if not exists entity_id    text,
  add column if not exists status       text,
  add column if not exists completed_at timestamptz,
  add column if not exists assigned_to  uuid;

-- Backfill the polymorphic pair from the existing FK columns. order_id is
-- already text; lead_id is uuid, hence the cast.
update public.reminders
   set entity_type = case
         when order_id is not null then 'order'
         when lead_id  is not null then 'lead'
         else coalesce(entity_type, 'lead')
       end,
       entity_id = coalesce(entity_id, order_id, lead_id::text)
 where entity_type is null or entity_id is null;

-- Backfill status from whichever completion flag the row was using.
-- `done` and `completed` both exist on this table; treat either as done.
update public.reminders
   set status = case
         when coalesce(done, false) or coalesce(completed, false) then 'done'
         else 'open'
       end
 where status is null;

alter table public.reminders
  alter column status set default 'open';

do $$
begin
  if not exists (select 1 from pg_constraint
                 where conname = 'reminders_status_check') then
    alter table public.reminders
      add constraint reminders_status_check
      check (status in ('open', 'done', 'cancelled'));
  end if;
  if not exists (select 1 from pg_constraint
                 where conname = 'reminders_entity_type_check') then
    alter table public.reminders
      add constraint reminders_entity_type_check
      check (entity_type in ('lead', 'quote', 'order'));
  end if;
end $$;

-- Keeps `status` and the legacy `done`/`completed` booleans consistent
-- whichever one a writer sets. Without this, CalendarPage (which reads
-- `done` via reminders_view) would silently disagree with the new
-- Reminders UI (which reads `status`).
create or replace function public.reminders_sync_status()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    if new.status is null then
      new.status := case when coalesce(new.done, new.completed, false)
                         then 'done' else 'open' end;
    end if;
  elsif new.status is distinct from old.status then
    -- status is the one that moved: push it down to the booleans.
    null;
  elsif coalesce(new.done, false) is distinct from coalesce(old.done, false)
     or coalesce(new.completed, false) is distinct from coalesce(old.completed, false)
  then
    -- a boolean moved: pull it up into status.
    new.status := case when coalesce(new.done, new.completed, false)
                       then 'done' else 'open' end;
  end if;

  -- Whatever moved, make the booleans agree with status.
  new.done      := (new.status = 'done');
  new.completed := (new.status = 'done');

  if new.status = 'done' and new.completed_at is null then
    new.completed_at := now();
  elsif new.status <> 'done' then
    new.completed_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists reminders_sync_status_trigger on public.reminders;
create trigger reminders_sync_status_trigger
  before insert or update on public.reminders
  for each row execute function public.reminders_sync_status();

create index if not exists reminders_entity_idx
  on public.reminders (org_id, entity_type, entity_id);
-- Drives the due-today / overdue dashboard counts.
create index if not exists reminders_due_idx
  on public.reminders (org_id, status, due_date);

alter table public.reminders enable row level security;
drop policy if exists org_isolation on public.reminders;
create policy org_isolation on public.reminders
  for all to authenticated
  using (org_id in (select current_org_ids()) or is_platform_admin())
  with check (org_id in (select current_org_ids()) or is_platform_admin());

-- ---- follow_up_logs (genuinely new) ----
create table if not exists public.follow_up_logs (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  entity_type text not null check (entity_type in ('lead', 'quote', 'order')),
  entity_id text not null,
  reminder_id uuid references public.reminders(id) on delete set null,
  channel text not null default 'call'
    check (channel in ('call','whatsapp','sms','email','visit','other')),
  outcome text
    check (outcome in ('connected','no_answer','busy','callback_requested',
                       'not_interested','converted')),
  notes text,
  next_action_at timestamptz,
  logged_by uuid,
  logged_at timestamptz not null default now()
);

create index if not exists follow_up_logs_entity_idx
  on public.follow_up_logs (org_id, entity_type, entity_id, logged_at desc);

alter table public.follow_up_logs enable row level security;
drop policy if exists org_isolation on public.follow_up_logs;
create policy org_isolation on public.follow_up_logs
  for all to authenticated
  using (org_id in (select current_org_ids()) or is_platform_admin())
  with check (org_id in (select current_org_ids()) or is_platform_admin());

-- ===========================================================================
-- ITEM 11 — soft delete
-- ===========================================================================

-- Real table names, not the brief's (see header note 2).
do $$
declare t text;
begin
  foreach t in array array[
    'leads', 'quotations', 'orders', 'payment_entries',
    'expenses', 'materials', 'vehicles'
  ] loop
    execute format(
      'alter table public.%I
         add column if not exists deleted_at    timestamptz,
         add column if not exists deleted_by    uuid,
         add column if not exists delete_reason text', t);
    -- Partial index: only live rows, which is what every list query wants.
    execute format(
      'create index if not exists %I on public.%I (org_id) where deleted_at is null',
      t || '_live_idx', t);
  end loop;
end $$;

-- ---- audit_log (did not exist) ----
create table if not exists public.audit_log (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  entity_type text not null,
  entity_id text not null,
  action text not null,           -- 'delete' | 'restore' | 'cancel' | ...
  actor uuid,
  actor_name text,                -- staff PIN sessions have no auth uid
  reason text,
  created_at timestamptz not null default now()
);

create index if not exists audit_log_entity_idx
  on public.audit_log (org_id, entity_type, entity_id, created_at desc);

alter table public.audit_log enable row level security;
drop policy if exists org_isolation on public.audit_log;
create policy org_isolation on public.audit_log
  for all to authenticated
  using (org_id in (select current_org_ids()) or is_platform_admin())
  with check (org_id in (select current_org_ids()) or is_platform_admin());

-- ---- Guard function: can this order be deleted? ----
-- Returns the decision AND the reason, so the UI can explain *why* it is
-- blocked and offer the right alternative, rather than just greying a
-- button out. Not a boolean, for exactly that reason.
drop function if exists public.can_delete_order(text);

create or replace function public.can_delete_order(p_order_id text)
returns table (allowed boolean, reason text, alternative text)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_invoice text;
  v_paid numeric;
  v_advance numeric;
begin
  -- Column aliases avoid the OUT-parameter ambiguity (42702) that bit
  -- verify_org_pin() live.
  select o.invoice_no, coalesce(o.paid_total, 0), coalesce(o.advance_paid, 0)
    into v_invoice, v_paid, v_advance
  from public.orders o
  where o.id = p_order_id;

  if not found then
    return query select false, 'Order not found'::text, null::text;
    return;
  end if;

  -- GST records must be retained — an invoiced order is never deletable,
  -- and this is checked first so the message names the real blocker when
  -- both apply.
  if v_invoice is not null and length(trim(v_invoice)) > 0 then
    return query select false,
      format('A GST invoice (%s) has been issued. Tax records must be retained.', v_invoice)::text,
      'cancel_order'::text;
    return;
  end if;

  if (v_paid + v_advance) > 0 then
    return query select false,
      'Payments have been recorded against this order.'::text,
      'cancel_order'::text;
    return;
  end if;

  if exists (select 1 from public.payment_entries pe
              where pe.order_id = p_order_id
                and pe.deleted_at is null) then
    return query select false,
      'Payment entries exist for this order.'::text,
      'cancel_order'::text;
    return;
  end if;

  return query select true, null::text, null::text;
end;
$$;

revoke all on function public.can_delete_order(text) from public;
revoke all on function public.can_delete_order(text) from anon;
grant execute on function public.can_delete_order(text) to authenticated;
grant execute on function public.can_delete_order(text) to service_role;

commit;

-- ===========================================================================
-- STEP 2 — run this ONLY after the transaction above succeeds.
--
-- Rebuilds reminders_view to carry the new columns and to exclude
-- soft-deleted parents. Separate because CLAUDE.md records a live 42P16:
-- a view column's type cannot change under CREATE OR REPLACE, so the view
-- must be dropped first. Kept out of the main transaction so a failure
-- here does not roll back everything above.
-- ===========================================================================

drop view if exists public.reminders_view;

create view public.reminders_view as
select r.id,
       r.org_id,
       r.lead_id,
       r.order_id,
       r.entity_type,
       r.entity_id,
       r.title,
       r.description,
       r.reminder_type,
       r.due_date,
       r.status,
       r.done,
       r.completed_at,
       r.assigned_to,
       r.created_by,
       l.customer as lead_customer,
       o.customer as order_customer
from public.reminders r
left join public.leads  l on l.id = r.lead_id  and l.deleted_at is null
left join public.orders o on o.id = r.order_id and o.deleted_at is null;

-- ===========================================================================
-- Verify after running:
--   \d reminders                 -- entity_type, entity_id, status,
--                                   completed_at, assigned_to present
--   \d follow_up_logs
--   \d audit_log
--   select entity_type, status, count(*) from public.reminders
--    group by 1,2;               -- expect no NULLs in either column
--   select count(*) from public.reminders where done <> (status = 'done');
--                                -- expect 0 (trigger keeps them in sync)
--   select * from public.can_delete_order('NGV-1007');
--   select table_name from information_schema.columns
--    where column_name = 'deleted_at' and table_schema = 'public'
--    order by 1;                 -- expect the 7 tables listed above
-- ===========================================================================
