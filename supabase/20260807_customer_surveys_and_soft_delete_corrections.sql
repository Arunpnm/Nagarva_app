-- Corrections session (NG-BRIEF-corrections-session.md), items A1 + A2 + B2.
-- Handed over for Arun to review and run — not executed from this session.
--
-- Whole file wrapped in one transaction (Arun's review, round 2): DDL is
-- transactional in Postgres, so a failure partway through — e.g. B2's
-- policy creation failing after the old org_isolation policy has already
-- been dropped — would otherwise leave notifications with RLS enabled and
-- zero policies, which reads as "nobody can see any notification"
-- (total lockout) rather than a clean no-op. begin/commit makes the whole
-- file all-or-nothing.

begin;

-- ============================================================================
-- A1. customer_surveys.converted_to_order_id: uuid -> text
-- ============================================================================
-- orders.id is text (see orders_pkey below); this column was uuid, so the
-- join was never possible as written.
--
-- Verified live before writing this (7 Aug 2026):
--   - customer_surveys: 2 total rows, 0 with a non-null
--     converted_to_order_id — nothing to null out, no orphaned uuids exist.
--   - No FK constraint on this column exists at all today (pg_constraint on
--     customer_surveys shows only customer_surveys_lead_id_fkey, the
--     primary key, and the token unique constraint) — the DROP below is a
--     defensive no-op, kept per instruction rather than assuming there was
--     never a constraint to begin with.
--   - orders carries a real primary key (orders_pkey, PRIMARY KEY (id)), so
--     the new FK below has a valid target — checked rather than added
--     unilaterally.
alter table customer_surveys
  drop constraint if exists customer_surveys_converted_to_order_id_fkey;

alter table customer_surveys
  alter column converted_to_order_id type text
  using converted_to_order_id::text;

alter table customer_surveys
  add constraint customer_surveys_converted_to_order_id_fkey
  foreign key (converted_to_order_id) references orders(id) on delete set null;

-- ============================================================================
-- A2. Soft-delete column uniformity on trips and tasks
-- ============================================================================
-- vendors/vendor_bills/vendor_payments/customers carry the full deleted_at/
-- deleted_by/delete_reason triple; trips and tasks carry only deleted_at
-- (verified live), which is why SoftDeleteService.softDelete would throw
-- against them and they were deliberately left out of kSoftDeleteTables.
--
-- Schema fix only. This does NOT add trips/tasks to kSoftDeleteTables and
-- does NOT change their retire-action UX (status -> 'cancelled' stays the
-- app-facing behaviour for now) — whether to switch them to soft-delete is
-- a product decision for Arun, not made here. Column types match the live
-- vendors table (deleted_by text, delete_reason text) for consistency.
alter table trips
  add column if not exists deleted_by text,
  add column if not exists delete_reason text;

alter table tasks
  add column if not exists deleted_by text,
  add column if not exists delete_reason text;

-- ============================================================================
-- B2. notifications: recipient-scoped policies
-- ============================================================================
-- Confirmed before writing this: staff PIN sessions get their own, separate
-- Supabase auth user each (supabase/functions/staff-login/index.ts mints a
-- deterministic staff-<staff_id>@staff.nagarva.in shadow user per staff
-- member, linked via staff.auth_user_id — verified live, 3 staff rows with
-- 3 distinct auth_user_id values, no sharing). So the anon-key query
-- NotificationBell issues today (org-scoped only, filtered to "is this row
-- mine" client-side afterward) really does put every colleague's
-- notification row on the wire to every staff session in the org.
--
-- Current live policy on notifications (checked via pg_policies before
-- writing this, not assumed): exactly one, "org_isolation", FOR ALL,
-- using/with_check both `org_id in (select current_org_ids()) or
-- is_platform_admin()`. No recipient scoping anywhere today.
--
-- Round 2 corrections from review, all applied below:
--   1. Whole-file transaction — see top of file.
--   2. current_staff_id() / is_org_owner() SECURITY DEFINER helpers,
--      matching current_org_ids()'s own style, instead of inlining the
--      staff/org_members subqueries directly in the policy. Checked live:
--      staff's own RLS policy is `org_id in (select current_org_ids()) or
--      is_platform_admin()` and org_members' SELECT policy is `user_id =
--      auth.uid() or is_platform_admin()` — an inlined subquery against
--      either table runs under the CALLING session's own RLS, not the
--      policy-definer's, so a future tightening of either table's policy
--      could silently make notifications_select see nothing for staff
--      sessions. SECURITY DEFINER sidesteps that the same way
--      current_org_ids() already does for org_members.
--   3. recipient_staff_id = (scalar subquery) -> recipient_staff_id in
--      (SETOF-returning function). Checked live: staff.auth_user_id has NO
--      unique constraint (only staff_pkey on id) — nothing stops two staff
--      rows from sharing an auth_user_id, which would make the scalar form
--      throw "more than one row returned by a subquery used as an
--      expression" on every read. current_staff_id() returns setof uuid,
--      matching current_org_ids()'s own pattern, and the policy uses IN.
--   4. notifications_update's USING clause now matches
--      notifications_select's predicate exactly, instead of being
--      org-scope-only — previously a staff session could mark a
--      colleague's notification read despite never being able to see it.
--      WITH CHECK is left at org-scope-only per the specific instruction
--      (mark-as-read never reassigns recipient_staff_id, so this doesn't
--      reopen anything).
--
-- Writes stay exactly as permissive as today (org-scope only, per
-- notifications_insert/notifications_delete below) — staff routinely
-- insert a notification addressed to someone else. Concretely:
-- supervisor_job_page_widget.dart's OTP-completion flow inserts a
-- `notifications` row with recipient_staff_id left unset (defaults to
-- NULL — the column has no column default, so an insert that omits it is a
-- plain NULL), org_id = the supervisor's own org, done from the
-- supervisor's own authenticated session (a 'staff'-role org_members row,
-- not 'owner'). That write is addressed to the owner and must keep
-- working — it does, because INSERT is not recipient-restricted, only
-- SELECT/UPDATE are. (DB triggers that insert notifications run as table
-- owner and bypass RLS entirely regardless, per Arun's own note — only
-- this one app-side authenticated write actually goes through RLS.)
--
-- The owner test is derived from org_members.role, not any app-side flag:
-- staff-login's org_members insert always writes role='staff' regardless
-- of the staff member's own staff.role (owner/manager/supervisor/driver/…
-- in the `staff` table are a separate vocabulary from org_members.role,
-- which only ever has 'owner' or 'staff' — confirmed live, `select role,
-- count(*) from org_members group by role` returned exactly those two
-- values). So org_members.role = 'owner' correctly identifies only a
-- genuine owner/vendor session — a manager's staff-PIN session is 'staff'
-- in org_members just like any other staff role, and is correctly
-- excluded from owner-addressed (recipient_staff_id is null) rows,
-- matching NotificationBell's existing client-side `_isStaffSession`
-- check exactly (it treats ANY session with a non-null currentStaffId,
-- managers included, as "only show my own rows").

-- All staff row ids linked to the calling auth user. setof, not a scalar,
-- because staff.auth_user_id carries no unique constraint (see point 3
-- above) — a caller should never legitimately map to more than one staff
-- row, but nothing in the schema enforces that today.
create or replace function public.current_staff_id()
returns setof uuid
language sql
stable security definer
set search_path to 'public'
as $function$
  select id from staff where auth_user_id = auth.uid()
$function$;

-- True if the calling auth user is a real owner/vendor member (not a
-- staff-PIN session) of the given org. SECURITY DEFINER so this evaluates
-- against org_members without going through org_members' own
-- caller-restricted SELECT policy (point 2 above).
create or replace function public.is_org_owner(p_org_id uuid)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $function$
  select exists (
    select 1 from org_members
    where org_id = p_org_id
      and user_id = auth.uid()
      and role = 'owner'
  )
$function$;

drop policy if exists org_isolation on notifications;

create policy notifications_insert on notifications
  for insert
  with check (org_id in (select current_org_ids()) or is_platform_admin());

create policy notifications_delete on notifications
  for delete
  using (org_id in (select current_org_ids()) or is_platform_admin());

create policy notifications_select on notifications
  for select
  using (
    is_platform_admin()
    or (
      org_id in (select current_org_ids())
      and (
        recipient_staff_id in (select current_staff_id())
        or (recipient_staff_id is null and is_org_owner(org_id))
      )
    )
  );

-- USING mirrors notifications_select exactly (point 4 above) — a staff
-- session can only mark its own (or, for an owner, org-wide) rows read.
-- WITH CHECK stays org-scope-only: the app's only UPDATE is mark-as-read,
-- which never changes recipient_staff_id, so there is nothing for a
-- recipient-scoped WITH CHECK to additionally guard against here.
create policy notifications_update on notifications
  for update
  using (
    is_platform_admin()
    or (
      org_id in (select current_org_ids())
      and (
        recipient_staff_id in (select current_staff_id())
        or (recipient_staff_id is null and is_org_owner(org_id))
      )
    )
  )
  with check (org_id in (select current_org_ids()) or is_platform_admin());

-- Every policy above filters on (org_id, recipient_staff_id) together —
-- no index existed on that pair before this.
create index if not exists idx_notifications_org_recipient
  on notifications (org_id, recipient_staff_id);

commit;
