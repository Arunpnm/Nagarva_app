-- Corrections session (NG-BRIEF-corrections-session.md), items A1 + A2 + B2.
-- Handed over for Arun to review and run — not executed from this session.

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
-- B2. notifications: recipient-scoped SELECT policy
-- ============================================================================
-- Confirmed before writing this: staff PIN sessions get their own, separate
-- Supabase auth user each (supabase/functions/staff-login/index.ts mints a
-- deterministic staff-<staff_id>@staff.nagarva.in shadow user per staff
-- member, linked via staff.auth_user_id — verified live, 3 staff rows with
-- 3 distinct auth_user_id values, no sharing). So the anon-key query
-- NotificationBell issues today (org-scoped only, filtered to "is this row
-- mine" client-side afterward) really does put every colleague's
-- notification row on the wire to every staff session in the org — this is
-- the real branch, not the "shared identity, filter is the only option"
-- branch.
--
-- Current live policy on notifications (checked via pg_policies before
-- writing this, not assumed): exactly one, "org_isolation", FOR ALL,
-- using/with_check both `org_id in (select current_org_ids()) or
-- is_platform_admin()`. No recipient scoping anywhere today.
--
-- Split into per-command policies rather than one FOR ALL, because a single
-- PERMISSIVE policy that also covers SELECT would OR together with a
-- separate SELECT-only policy and silently make the recipient restriction a
-- no-op (Postgres ORs multiple permissive policies for the same command).
--
-- Writes stay exactly as permissive as today (org-scope only) — staff
-- routinely insert a notification addressed to someone else. Concretely:
-- supervisor_job_page_widget.dart's OTP-completion flow inserts a
-- `notifications` row with recipient_staff_id left unset (defaults to
-- NULL — confirmed: the column has no column default, so an insert that
-- omits it is a plain NULL), org_id = the supervisor's own org, done from
-- the supervisor's own authenticated session (a 'staff'-role org_members
-- row, not 'owner'). That write is addressed to the owner and must keep
-- working — it does under this policy, because INSERT is not
-- recipient-restricted, only SELECT is. (DB triggers that insert
-- notifications run as table owner and bypass RLS entirely regardless, per
-- Arun's own note — only this one app-side authenticated write actually
-- goes through RLS.)
--
-- The owner test is derived from org_members.role, not any app-side flag:
-- staff-login's org_members insert always writes role='staff' regardless
-- of the staff member's own staff.role (owner/manager/supervisor/driver/…
-- in the `staff` table are a separate vocabulary from org_members.role,
-- which only ever has 'owner' or 'staff' — confirmed live, `select role,
-- count(*) from org_members group by role` returned exactly those two
-- values). So org_members.role = 'owner' correctly identifies only a
-- genuine owner/vendor session (logged in via email/password, no staff PIN
-- involved) — a manager's staff-PIN session is 'staff' in org_members just
-- like any other staff role, and is correctly excluded from
-- owner-addressed (recipient_staff_id is null) rows, matching
-- NotificationBell's existing client-side `_isStaffSession` check exactly
-- (it treats ANY session with a non-null currentStaffId, managers
-- included, as "only show my own rows").
drop policy if exists org_isolation on notifications;

create policy notifications_insert on notifications
  for insert
  with check (org_id in (select current_org_ids()) or is_platform_admin());

create policy notifications_update on notifications
  for update
  using (org_id in (select current_org_ids()) or is_platform_admin())
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
        recipient_staff_id = (
          select id from staff where auth_user_id = auth.uid()
        )
        or (
          recipient_staff_id is null
          and exists (
            select 1 from org_members om
            where om.org_id = notifications.org_id
              and om.user_id = auth.uid()
              and om.role = 'owner'
          )
        )
      )
    )
  );
