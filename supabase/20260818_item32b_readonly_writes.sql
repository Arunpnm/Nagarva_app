-- ============================================================
-- supabase/20260818_item32b_readonly_writes.sql
--
-- Item 32, addendum — make read-only actually mean read-only.
--
-- The main Item 32 migration (20260818_item32_plan_enforcement.sql)
-- attached assert_org_writable() to only two tables, `orders` and
-- `staff`, because those were where the COUNTED limits lived. But the
-- trial banner promises "You can still view and export everything —
-- upgrade to add new records", and a read-only org could still insert
-- leads, quotations, expenses, customers and more. The copy was making a
-- promise the enforcement didn't keep. This closes that.
--
-- RUN AFTER 20260818_item32_plan_enforcement.sql — depends on
-- assert_org_writable() and org_effective_plan() existing.
--
-- ---- WHAT IS BLOCKED (creates only, once trial + grace have passed)
--   leads, quotations, customers, vendors, materials, trips, tasks,
--   vendor_bills, expenses
--   (+ orders and staff, already covered by the main migration)
--
-- ---- WHAT IS DELIBERATELY NOT BLOCKED, and why
--
-- 1. `payment_entries` and `receipts` — Arun's call, 18 Aug 2026, and
--    the reasoning is worth preserving verbatim because a future session
--    WILL be tempted to "complete" this list: blocking these would stop a
--    vendor recording money they have ALREADY BEEN PAID against an
--    existing job. That corrupts their books to apply commercial
--    pressure — it punishes them for their customer's payment. Never do
--    that. Money already received must always be recordable.
--
-- 2. System/audit tables — audit_log, notification_log, order_tracking,
--    order_status_history, document_signatures. These are written by the
--    app on behalf of actions, not by a user creating a business record.
--    Blocking audit writes would break the trail exactly when it's most
--    wanted, and several are written by SECURITY DEFINER paths anyway.
--
-- 3. Config tables — settings, app_settings, pricing_config,
--    number_series, org_members, organizations. A locked-out vendor
--    fixing their GSTIN or their slab table is doing harmless work;
--    blocking it is friction with no commercial upside. They still can't
--    create a single job.
--
-- 4. UPDATEs generally — a DECISION, not an omission. Ratified by Arun,
--    18 Aug 2026: "UPDATE stays unguarded. A vendor whose trial lapses
--    mid-job has to close out work already running. 'No new work' is the
--    lever, not 'your business is frozen.'" Same principle as the
--    payment_entries carve-out above: the lock exists to stop NEW
--    business being booked, never to strand work already in flight or to
--    hold a vendor's own operations hostage.
--
--    Concretely, a locked org can still: mark a running job delivered,
--    correct a typo, close an order, record a delivery. It cannot book
--    the next one. DO NOT "tighten" this to UPDATE later without
--    revisiting that reasoning — the only UPDATE guarded anywhere is
--    staff.branch, and that is the multi_branch limit doing its job, not
--    a read-only rule.
--
-- Safe to re-run: every trigger is dropped and recreated.
-- ============================================================

begin;

-- One shared guard, attached to every blocked table, so read-only
-- behaviour is defined in exactly one place and can't drift per table.
create or replace function public.enforce_org_writable()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- A row with no org_id can't be resolved to a plan; leave it to the
  -- org_isolation RLS policy to reject, rather than raising a confusing
  -- billing message for what is actually a scoping bug.
  if new.org_id is null then
    return new;
  end if;
  perform public.assert_org_writable(new.org_id);
  return new;
end;
$$;

comment on function public.enforce_org_writable() is
  'Item 32b: blocks CREATES on business records once an org is locked '
  '(expired trial past grace, or suspended). Reads are never affected — '
  'a BEFORE INSERT trigger cannot fire on SELECT, so exports keep '
  'working forever, which is deliberate and must stay true. '
  'payment_entries/receipts are excluded on purpose: money already '
  'received must always be recordable.';

do $$
declare
  t text;
  -- orders and staff are NOT in this list — they already carry their own
  -- limit-enforcing triggers from the main migration, which call
  -- assert_org_writable() first. Adding a second trigger there would
  -- just run the same check twice.
  blocked text[] := array[
    'leads', 'quotations', 'customers', 'vendors', 'materials',
    'trips', 'tasks', 'vendor_bills', 'expenses'
  ];
begin
  foreach t in array blocked loop
    execute format('drop trigger if exists trg_org_writable on public.%I', t);
    execute format(
      'create trigger trg_org_writable before insert on public.%I '
      'for each row execute function public.enforce_org_writable()', t);
  end loop;
end $$;

commit;

-- ============================================================
-- VERIFY (read-only)
--
--   select c.relname as table_name, t.tgname
--     from pg_trigger t join pg_class c on c.oid = t.tgrelid
--    where not t.tgisinternal
--      and t.tgname in ('trg_org_writable', 'trg_enforce_order_limit',
--                       'trg_enforce_staff_limit')
--    order by c.relname;
--   -- expect 11 rows: 9 trg_org_writable + orders + staff
--
-- LIVE-FIRE TEST, using the same SET LOCAL pattern that proved branch
-- scoping (no token needed):
--
--   begin;
--   set local role authenticated;
--   set local request.jwt.claims = '{"sub":"<an owner auth_user_id>"}';
--
--   -- 1. Reads must ALWAYS work, even when locked. This is the
--   --    export guarantee — if this ever fails, that is a release
--   --    blocker, not a bug report.
--   select count(*) from leads;
--
--   -- 2. With the org NOT locked, this should succeed:
--   insert into leads (org_id, customer, branch)
--     values ('<org_id>', 'ZZZ writable test', 'Chennai');
--
--   rollback;
--
--   -- Then force the lock (on a THROWAWAY org, never APC):
--   --   update organizations
--   --      set plan_status = 'trial',
--   --          trial_ends_at = now() - interval '99 days'
--   --    where id = '<throwaway org_id>';
--   -- and repeat: the select still works, the insert now raises
--   -- 'Your trial has ended...'. Remember to restore plan_status.
-- ============================================================
