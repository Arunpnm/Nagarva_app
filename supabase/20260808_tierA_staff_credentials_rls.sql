-- Tier A — Credentials & identity (NG-BRIEF-rls-remediation.md §3, Tier A).
-- Handed over for Arun to review and run — not executed from this session.
-- Scope: staff, staff_invites. org_members and platform_admins confirmed
-- already safe per the brief — not touched here.
--
-- Pre-read done before writing this: NG-BRIEF-rls-remediation.md §3 Tier A,
-- and Phase 0 (supabase/20260807_phase0_staff_credential_lockdown.sql),
-- which deliberately left role/salary/pf_applicable/esic_applicable/
-- permissions column-writable by any org member because a column GRANT
-- can't distinguish "owner editing a colleague" from "colleague editing
-- themselves" — that's exactly what this migration's row-level split now
-- provides. Phase 0's own column GRANT list is reused as-is below (see
-- item 4) — nothing about it needs to change.
--
-- Wrapped in one transaction: creating is_org_manager() and rewriting the
-- staff/staff_invites policies must land together or not at all — a
-- mid-file failure that left staff's UPDATE policy owner-only but
-- is_org_manager() undefined would break every later tier that calls it,
-- and one that left the old org_isolation policy dropped with no
-- replacement created would lock the table entirely (same reasoning as
-- 60110b4 and 20260807_phase0).
--
-- ============================================================================
-- Pre-flight report (per the brief's "before writing anything, report"):
-- ============================================================================
--
-- Every Dart write to `staff`, confirmed by grep of lib/ (StaffTable().*,
-- excluding OrderStaffTable() which matches the same substring):
--   1. lib/users_page/staff_form_sheet.dart:222 — StaffTable().update(...),
--      matchingRows OrgScope.write(q).eq('id', ...). This is the edit path,
--      sends {name, phone, role, branch, salary, pf_applicable,
--      esic_applicable, permissions} every save (date_of_joining is in
--      Phase 0's grant list but this form never sends it — harmless, a
--      grant on an unreferenced column is a no-op for that request).
--   2. lib/users_page/staff_form_sheet.dart:232 — StaffTable().insert(...),
--      new-staff path: OrgScope.stamp() + the same data map + {active, pin}.
--   No other file writes `staff`. No file anywhere writes `staff_invites`
--   directly — its only writers are the staff-invite (generate/revoke) and
--   staff-invite-redeem Edge Functions, both service-role, both already
--   bypass RLS entirely and are unaffected by anything below.
--
-- Does staff_form_sheet.dart's update still work for an OWNER under the
-- new policies? Yes, unchanged — the owner's `auth.uid()` has an
-- org_members row with role='owner' for this org, so is_org_owner(org_id)
-- is true and the new staff_update policy's USING/WITH CHECK both pass.
-- Column-wise nothing changes either: Phase 0's grant already covers every
-- field this form sends.
--
-- Does it still work for a MANAGER? NO — and this is the one real
-- regression this migration introduces, flagged rather than silently
-- shipped. lib/permissions.dart's presetFor('manager') returns
-- fullAccess(), which includes 'staff': {view, create, edit, delete} —
-- and lib/users_page/users_page_widget.dart gates nothing on role before
-- calling StaffFormSheet.show() (no canActive/isOwnerOrManagerSession
-- check found in that file). So today a manager-role staff session CAN
-- open "Edit Staff" for a colleague and successfully save. Tier A's own
-- spec is explicit ("UPDATE and DELETE owner-only" — no is_org_manager()
-- exception, unlike Tier C/D below it) and org_members.role for a staff
-- PIN session is always 'staff', never 'owner' (confirmed in
-- 20260807_customer_surveys_and_soft_delete_corrections.sql's own note on
-- is_org_owner), so is_org_owner(org_id) is false for every staff PIN
-- session including a manager's. After this migration, a manager's Save
-- on that sheet gets a Postgres permission-denied error back from
-- PostgREST, which _save()'s existing try/catch surfaces as inline red
-- text (not a crash — but a real behaviour change from "silently
-- succeeds" to "fails with an error message"). This is Tier A's whole
-- point (the brief's own §0: self-escalation is explicitly in scope to
-- close, and a manager editing another staff member's role/permissions/
-- salary is exactly that shape of risk).
--
-- UI-level gate: ADDED, as its own change (lib/users_page/
-- users_page_widget.dart's _editStaff, gated on
-- AppSession.instance.currentStaffId == null — the exact client-side
-- mirror of is_org_owner()'s org_members.role='owner' check) — so a
-- manager sees a lock icon and an explanatory message instead of a raw
-- Postgres error. SAME ORDERING RULE AS PHASE 0's set_staff_pin(): this
-- Dart change ships in the APK and devices confirm they've picked it up
-- BEFORE this SQL file runs, not the other way around. Running this
-- migration against an old build skips the friendly message (a manager
-- would still just see the try/catch's raw error text) but does not
-- break anything — the gate is a UX improvement layered on top of the
-- DB-level restriction, not a dependency of it.
--
-- staff_invites INSERT — the brief's Tier A text only says "same
-- treatment" without spelling out INSERT explicitly. Decision made here:
-- owner-only, not left at org-scope. Reasoning, not overstated: redeeming
-- a forged invite does NOT itself grant login — staff-login/pin-login
-- still require the real bcrypt-verified PIN regardless of how the device
-- got bound, so this is not a credential bypass. But it is free,
-- zero-cost hardening (there is no live Dart writer to protect — every
-- legitimate INSERT already goes through the owner-gated staff-invite
-- Edge Function's service role, which bypasses RLS and is unaffected by
-- this policy either way) against directly forging a staff_invites row
-- over raw PostgREST with a self-chosen code_hash, which today's
-- org-scope-only org_isolation policy allows any org member to do. Costs
-- nothing to close, so closed.
begin;

-- ============================================================================
-- 1. is_org_manager(p_org_id) helper.
-- ============================================================================
-- Same SECURITY DEFINER style as current_org_ids()/is_org_owner() (see
-- 20260807_customer_surveys_and_soft_delete_corrections.sql). Not used by
-- any policy in THIS migration — staff/staff_invites are owner-only, not
-- manager-eligible, per the brief's own Tier A spec — but it has to be
-- created now because it depends on staff.role being trustworthy, which is
-- only true once this same migration makes staff.role owner-writable-only
-- at the row level (see item 2 below). Later tiers (C/D) reference this
-- function; defining it here (rather than in whichever tier first calls
-- it) keeps its precondition and its guarantee in the same transaction.
--
-- True for a genuine owner session (is_org_owner) OR a staff-PIN session
-- whose own staff row is owner-tier or manager-tier.
--
-- Role vocabulary reconciled against live data (Arun's follow-up, read-only
-- Supabase MCP query run and reported before writing this):
--   select role, count(*) from staff group by role
--   -> driver 2, helper 1, manager 1, packer 2, supervisor 2. Zero 'owner'
--   and zero 'admin' rows exist today (8 total, matching Phase 0's own
--   count). So the gap flagged in the first draft of this function is
--   currently latent, not active — but "match reality" means matching the
--   vocabulary the app can actually produce, not just today's snapshot.
--   staff_form_sheet.dart's role dropdown (`roles` constant) offers
--   manager/supervisor/driver/helper/packer/admin — 'owner' is NOT a
--   selectable value there (the real org owner is never a `staff` row at
--   all; they authenticate via org_members.role='owner', a separate
--   Supabase Auth session, which is what is_org_owner() already checks).
--   'admin' IS selectable and, per lib/permissions.dart's isOwnerRole()/
--   _normalizeRole() ('admin' -> 'owner', with an explicit comment that
--   new rows should write 'owner'/'manager' directly going forward, 'admin'
--   being the legacy value kept as a read-alias), is the value this app's
--   own permission model treats as full/owner-equivalent access
--   (presetFor('admin') resolves to presetFor('owner') = fullAccess()).
--   So the literal 'owner' branch below is defensive for if/when a staff
--   row is ever written with that value directly (the vocabulary decision
--   points that way but no migration has done it yet), and 'admin' is
--   added because it's the value that ACTUALLY carries owner-equivalent
--   meaning in staff.role today. Not extending this would mean an
--   'admin'-role staff PIN session reads as manager-tier-or-below to
--   is_org_manager() while the app's own UI treats them as full-access —
--   exactly the kind of drift this helper exists to avoid for Tier C/D and
--   the planned supervisor customer-PII gate (NG-BRIEF-supervisor-field-
--   operations.md §1, "hidden from everyone except owner and manager" —
--   that gate will need this function, or one built the same way, to be
--   right about who counts as a manager).
create or replace function public.is_org_manager(p_org_id uuid)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $function$
  select
    public.is_org_owner(p_org_id)
    or exists (
      select 1
      from public.staff
      where id in (select public.current_staff_id())
        and org_id = p_org_id
        and role in ('owner', 'admin', 'manager')
    )
$function$;

-- ============================================================================
-- 2. staff — per-command policies, replacing the single FOR ALL
--    org_isolation policy.
-- ============================================================================
-- SELECT stays exactly as permissive as before (org-scope). INSERT stays
-- org-scope too — deliberately NOT restricted, per the pre-flight report
-- above: a freshly inserted staff row has no auth_user_id, so it cannot
-- log in as itself without a separately owner-gated invite (staff-invite's
-- Edge Function checks org_members.role = 'owner' independently of
-- whatever staff.role the new row was given), and restricting it would
-- break the manager "add staff" path the app's own permission model
-- already grants (presetFor('manager') includes 'staff': create) with no
-- upside — there is no self-escalation shape for INSERT the way there is
-- for UPDATE. UPDATE and DELETE are owner-only, per the brief.
drop policy if exists org_isolation on public.staff;

create policy staff_select on public.staff
  for select
  using (org_id in (select current_org_ids()) or is_platform_admin());

create policy staff_insert on public.staff
  for insert
  with check (org_id in (select current_org_ids()) or is_platform_admin());

create policy staff_update on public.staff
  for update
  using (is_org_owner(org_id) or is_platform_admin())
  with check (is_org_owner(org_id) or is_platform_admin());

create policy staff_delete on public.staff
  for delete
  using (is_org_owner(org_id) or is_platform_admin());

-- ============================================================================
-- 3. staff_invites — same treatment, plus INSERT owner-only (see pre-flight
--    report above for why INSERT is included here, not left at org-scope).
-- ============================================================================
drop policy if exists org_isolation on public.staff_invites;

create policy staff_invites_select on public.staff_invites
  for select
  using (org_id in (select current_org_ids()) or is_platform_admin());

create policy staff_invites_insert on public.staff_invites
  for insert
  with check (is_org_owner(org_id) or is_platform_admin());

create policy staff_invites_update on public.staff_invites
  for update
  using (is_org_owner(org_id) or is_platform_admin())
  with check (is_org_owner(org_id) or is_platform_admin());

create policy staff_invites_delete on public.staff_invites
  for delete
  using (is_org_owner(org_id) or is_platform_admin());

-- ============================================================================
-- 4. GRANT adjustment for the five deferred columns.
-- ============================================================================
-- None needed. Phase 0's column GRANT (name, phone, branch,
-- date_of_joining, role, salary, pf_applicable, esic_applicable,
-- permissions on staff, to authenticated) already covers all five —
-- it was never the thing blocking them, the missing row-level owner check
-- was. That's supplied by staff_update above; the two mechanisms compose
-- (GRANT says which columns are writable at all, RLS says by whom), so no
-- REVOKE/GRANT statement is added in this file. staff_invites never had a
-- column-level GRANT restriction (Phase 0 only touched staff), so nothing
-- to adjust there either — its table-level INSERT/UPDATE/DELETE grants
-- from the original schema setup are untouched; only the new row-level
-- policies above are new.

commit;

-- ============================================================================
-- Test gate (NG-BRIEF-rls-remediation.md §4) — run before/after applying,
-- as a real staff (non-owner) session and a real owner session, direct
-- against PostgREST with each session's own token:
--
--   As STAFF (e.g. a manager-role staff PIN session):
--     - PATCH .../staff?id=eq.<colleague-id> with any of
--       {role, salary, pf_applicable, esic_applicable, permissions, name}
--       -> must now fail (0 rows affected / permission error), where it
--       silently succeeded before this migration.
--     - DELETE .../staff?id=eq.<colleague-id> -> must fail.
--     - POST .../staff (new row, own org_id) -> must still succeed
--       (INSERT is unchanged).
--     - Confirm the manager's own staff_form_sheet.dart Save now shows the
--       inline error text described in the pre-flight report above,
--       instead of silently succeeding.
--
--   As OWNER:
--     - PATCH .../staff?id=eq.<any-staff-in-org> with
--       {role, salary, pf_applicable, esic_applicable, permissions} ->
--       must still succeed (staff_form_sheet.dart's normal edit flow).
--     - DELETE -> must succeed at the RLS layer (no Dart caller exercises
--       this today, but the policy itself must not block a legitimate
--       owner delete if one is added later).
--
--   Edge Functions (service role, should be unaffected — verify, don't
--   assume): staff-deactivate, staff-invite (generate/revoke),
--   staff-invite-redeem, staff-login, pin-login, verify_staff_pin(),
--   set_staff_pin().
--
--   Named regression risks per the brief: staff PIN login, staff invite
--   acceptance (both still Edge-Function-only, unaffected), supervisor OTP
--   completion (does not touch `staff`), quote/invoice numbering (no
--   `staff` dependency).
--
-- Report §4.1 results per the brief's instruction: a write that still
-- succeeds when it shouldn't is the finding that matters.
