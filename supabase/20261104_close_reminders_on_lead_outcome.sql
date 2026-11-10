-- 20261104_close_reminders_on_lead_outcome.sql  (4 Nov 2026, BUG-049)
--
-- WHAT WAS WRONG
-- A lead's follow-up reminders stayed "open" after the lead was confirmed
-- (became an order) or lost. They kept showing on the Calendar and Home
-- as calls to make for a customer who had already booked or said no.
-- Measured 4 Nov 2026: 7 such reminders (6 on confirmed leads, 1 on a
-- lost lead). A lead's status is changed from several screens (journey,
-- Lead Details, quote accept, convert), so the fix sits in ONE place: a
-- trigger on leads.
--
-- THE FIX
--   * When a lead's status changes TO 'confirmed' -> its open reminders
--     become 'done'. TO 'lost' -> 'cancelled'.
--   * Existing open reminders on confirmed/lost leads are closed the same
--     way, once.
--   * reminders_sync_status (already there) keeps done/completed_at in
--     step with status, so the Calendar view follows.
--   * Reopening a lead does NOT bring old reminders back -- the person
--     reopening sets a new follow-up.
-- A reminder belongs to a lead through reminders.lead_id OR
-- (entity_type = 'lead' and entity_id = the lead id); both are covered.
--
-- Run the WHOLE file. One transaction; any failed check rolls it all back.

begin;

-- ---------- preflight -------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.reminders'::regclass
                    and tgname = 'reminders_sync_status_trigger'
                    and tgenabled = 'O') then
    raise exception 'reminders_sync_status_trigger is missing or disabled -- closing by status alone would leave done/completed_at stale. Stop and check.';
  end if;
end $$;

-- ---------- trigger ---------------------------------------------------
-- SECURITY INVOKER: runs with the rights of whoever changed the lead, so it
-- can only close reminders that person's company owns.
create or replace function public.close_lead_reminders()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  update reminders
     set status = case when new.status = 'confirmed' then 'done' else 'cancelled' end
   where status = 'open'
     and org_id is not distinct from new.org_id
     and (lead_id = new.id
          or (entity_type = 'lead' and entity_id = new.id::text));
  return new;
end $$;

drop trigger if exists trg_close_lead_reminders on public.leads;
create trigger trg_close_lead_reminders
  after update of status on public.leads
  for each row
  when (new.status in ('confirmed', 'lost')
        and old.status is distinct from new.status)
  execute function public.close_lead_reminders();

-- ---------- one-time clean-up -----------------------------------------
update public.reminders r
   set status = case when l.status = 'confirmed' then 'done' else 'cancelled' end
  from public.leads l
 where r.status = 'open'
   and l.status in ('confirmed', 'lost')
   and r.org_id is not distinct from l.org_id
   and (r.lead_id = l.id
        or (r.entity_type = 'lead' and r.entity_id = l.id::text));

-- ---------- postflight ------------------------------------------------
do $$
declare n int;
begin
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.leads'::regclass
                    and tgname = 'trg_close_lead_reminders'
                    and tgenabled = 'O') then
    raise exception 'trg_close_lead_reminders was not created';
  end if;
  select count(*) into n
    from public.reminders r
    join public.leads l
      on (r.lead_id = l.id or (r.entity_type = 'lead' and r.entity_id = l.id::text))
   where r.status = 'open' and l.status in ('confirmed', 'lost');
  if n <> 0 then
    raise exception '% open reminders still sit on confirmed/lost leads', n;
  end if;
  -- the sync trigger did its part: nothing closed is still marked not done
  select count(*) into n from public.reminders
   where status in ('done', 'cancelled') and coalesce(done, false) = false;
  if n <> 0 then
    raise exception '% closed reminders still have done = false -- the sync trigger did not follow', n;
  end if;
end $$;

commit;
