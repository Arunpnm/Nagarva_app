-- Tier B — Billing & tenancy (NG-BRIEF-rls-remediation.md §3 Tier B).
-- Handed over for Arun to review and run — not executed from this session.
-- Scope: organizations, org_subscriptions, billing_events,
-- platform_invoices, org_usage.
--
-- Sequencing: run AFTER Tier A (supabase/20260808_tierA_staff_credentials_rls.sql)
-- and AFTER shipping + confirming the Dart/Edge-Function changes this pass
-- also makes (see item 0 below) — the column REVOKE in item 1 breaks the
-- app's plan-change/suspend tools immediately if those haven't rolled out
-- yet. Same "ship code first, confirm rollout, then run SQL" ordering
-- Phase 0's own header documents for set_staff_pin().
--
-- ============================================================================
-- Pre-flight report:
-- ============================================================================
--
-- Live schema pulled directly (Supabase MCP, read-only: list_tables +
-- pg_proc/pg_policies via execute_sql — no writes issued from this
-- session). organizations has 41 columns; the 4 the brief calls
-- plan/subscription state are plan_id, plan_status, trial_ends_at, active.
-- Everything else is profile/branding. org_subscriptions, billing_events,
-- platform_invoices, org_usage all exist live, all 0 rows, all currently
-- carry one `org_isolation` FOR ALL policy (same shape as every Tier A/
-- pre-Tier-A table). organizations currently has 3 policies from
-- 20260715_rls_v1.sql: org_select (SELECT, unchanged by this migration),
-- org_insert (INSERT, WITH CHECK true), org_update (UPDATE, id-scoped only
-- — no column distinction).
--
-- Every Dart write to `organizations`, confirmed by grep of lib/
-- (OrganizationsTable().*):
--   1. lib/super_admin_page/super_admin_page_widget.dart _changePlan() —
--      wrote {'plan_id': chosen} directly. REWIRED this pass to call the
--      new supabase/functions/admin-update-org Edge Function instead (see
--      that file's header for why a Razorpay-webhook writer doesn't apply
--      here — org_subscriptions/billing_events/platform_invoices/org_usage
--      are all live-but-empty with zero Dart references anywhere, so
--      nothing existing was already the "legitimate writer" the brief
--      guessed at).
--   2. lib/super_admin_page/tenant_detail_page.dart _toggleActive() —
--      wrote {'active': goingActive} directly. Same fix, same Edge
--      Function, {'org_id':..., 'active':...}.
--   3. lib/org_setup_page/org_setup_page_widget.dart — writes {'gstin':
--      gstin} once, during onboarding, immediately after create-org's
--      create_org_with_owner() RPC has already given the caller an
--      org_members row with role='owner' for this exact org. Not a plan
--      column. Still works under owner-only UPDATE — the caller IS the
--      owner at this point by construction.
--   4. lib/components/logo_upload_card.dart — writes {'logo_url': url}.
--      Only ever rendered from org_setup_page_widget.dart (grepped —
--      zero other call sites), i.e. the same onboarding-owner context as
--      #3. Not a plan column, works under owner-only UPDATE.
--   5. lib/settings_page/business_settings_section.dart — TWO writes: an
--      _allOrgFields map (gstin, business_type, address/city/state/
--      pincode/pan/cin, website/support_email/tagline/primary_color,
--      google_review_url, bank/UPI fields, the phone_secondary/tertiary/
--      quaternary/landline/udyam_no/affiliation_text/branch_list_text
--      document-header fields) and a separate {'logo_url': url} write.
--      Neither touches a plan column, so both survive the column REVOKE
--      untouched.
--
-- Does BusinessSettingsSection still work for an OWNER under the new
-- owner-only UPDATE row policy? Yes — is_org_owner(org_id) is true for a
-- genuine vendor/owner Auth session, which is who reaches SettingsPage
-- via the normal route in the overwhelmingly common case.
--
-- Did it still work for a MANAGER? NO — same shape of regression as
-- Tier A, found independently here rather than assumed from that
-- precedent. lib/settings_page/settings_page_widget.dart:307/314 gates
-- the PIN-setting card and the Recycle Bin on `AppSession.instance.
-- currentStaffId == null` (i.e. owner/vendor-only) with a comment
-- claiming "Staff-only sessions never reach this page's normal route
-- (SettingsPage isn't in the staff nav set)" — but that's not what
-- lib/nav_items.dart actually does: `isOwnerOrManagerSession` is true for
-- BOTH a vendor session AND a manager-role staff PIN session, SettingsPage
-- is in `kOwnerManagerNavItems`, and presetFor('manager') grants full
-- access to the 'settings' permission module — so a manager session DOES
-- reach SettingsPage today. `BusinessSettingsSection` itself had no
-- additional gate of its own.
--
-- UI-level gate: ADDED, as its own change (lib/settings_page/
-- business_settings_section.dart's `_isOwnerSession` getter — same
-- `AppSession.instance.currentStaffId == null` check as Tier A's
-- users_page_widget.dart gate), so a manager sees a disabled, lock-icon
-- "Owner only" button on both Save Letterhead and Upload/Change Logo
-- instead of a raw Postgres error. `_saveOrgProfile`/`_pickLogo` also
-- guard internally (SnackBar + early return) as a backstop. `_saveProfile`
-- (invoice terms) and `_drawSignature` are untouched — both write to
-- `settings`, not `organizations`, and Tier B doesn't restrict `settings`.
-- SAME ORDERING RULE AS PHASE 0/TIER A: this Dart change ships in the APK
-- and is confirmed live on devices BEFORE this SQL file runs.
--
-- org_insert (WITH CHECK: true) — confirmed: NO file in lib/ calls
-- OrganizationsTable().insert(...) anywhere (grepped, zero hits).
-- supabase/functions/create-org/index.ts is the only real creation path,
-- and it never inserts into `organizations` directly either — it calls
-- create_org_with_owner() (20260731_create_org_with_owner.sql) via RPC
-- under the SERVICE ROLE, which bypasses RLS entirely regardless of
-- whether org_insert exists. So org_insert has zero legitimate use today
-- and is pure attack surface (any authenticated session can currently
-- create an organizations row with no membership anywhere). Dropped
-- entirely below, per the brief's own suggestion — no replacement INSERT
-- policy for `authenticated` is added.
--
-- org_subscriptions/billing_events/platform_invoices/org_usage: zero Dart
-- readers OR writers found anywhere (grepped for the table names and the
-- Row/Table class names — no generated Dart classes even exist for these
-- yet). Their current org_isolation FOR ALL policy is therefore pure
-- unused attack surface too. Replaced below with SELECT-only (org-scope,
-- for whenever an org-facing "my subscription/usage" screen gets built)
-- and no write policy for `authenticated` at all — nothing legitimate
-- writes these from the app, and the only thing that ever will (a future
-- Razorpay webhook, admin-update-org, or similar) will use the service
-- role and bypass RLS regardless of what policy exists here.
begin;

-- ============================================================================
-- 1. organizations — column GRANT for the 4 plan/subscription columns,
--    plus per-command policies replacing org_insert/org_select/org_update.
-- ============================================================================
-- Table-level UPDATE grant to `authenticated` is untouched (unlike Phase
-- 0's staff migration, which did a full revoke-then-regrant) — this narrows
-- ONLY the 4 named columns; every other column keeps whatever broad grant
-- already existed from initial schema setup. No re-GRANT statement is
-- needed or added for these 4: per the brief, "no app-side write at all" —
-- not even for the owner. Both admin-update-org's writes and
-- create_org_with_owner()'s initial seed of plan_id/plan_status/
-- trial_ends_at run under the service role, which is a superuser-derived
-- role and is not subject to this REVOKE (REVOKE only removes a privilege
-- FROM the named role, `authenticated`; the service role was never granted
-- through it and bypasses grants the same way it bypasses RLS).
--
-- plan_status/trial_ends_at, confirmed (not assumed) to have no live
-- writer beyond that one-time creation seed: grepped every Dart reference
-- to both columns (`plan_status`, `trial_ends_at`, `planStatus`,
-- `trialEndsAt`) across lib/ — every hit is a READ (app_session.dart's
-- isTrialExpired gate, main.dart/signup_page_widget.dart populating
-- AppSession from create-org's/session-restore's response). PlanPageWidget's
-- "Upgrade Plan" button is a bare SnackBar stub ("Upgrade flow coming
-- soon — Razorpay integration in Phase 3") — it writes nothing. So
-- admin-update-org deliberately does NOT expose these two: there is
-- nothing today to replace, and the eventual Razorpay webhook will also
-- run under the service role, unaffected by this REVOKE regardless of
-- when it's built. If a manual "extend trial" or "override plan_status"
-- admin action is ever added, extend admin-update-org then, not here.
revoke update (plan_id, plan_status, trial_ends_at, active)
  on public.organizations from authenticated;

drop policy if exists org_insert on public.organizations;
drop policy if exists org_select on public.organizations;
drop policy if exists org_update on public.organizations;

-- SELECT unchanged in substance from the old org_select (still org-scope
-- + platform admin) — recreated under the same name for continuity since
-- nothing about it needed to change.
create policy org_select on public.organizations
  for select
  using (id in (select current_org_ids()) or is_platform_admin());

-- No org_insert policy recreated — see pre-flight report above. A direct
-- client INSERT into organizations is now refused outright; the only path
-- is create-org's service-role RPC, which was already the only path in
-- practice.

-- Row-level owner-only UPDATE. This does not by itself make the 4 plan
-- columns writable again for an owner — the column REVOKE above blocks
-- those unconditionally, for every role including this policy's own
-- is_org_owner() passers. The two mechanisms are independent by design
-- (brief §1): this policy governs the remaining ~37 profile/branding
-- columns.
create policy org_update on public.organizations
  for update
  using (is_org_owner(id) or is_platform_admin())
  with check (is_org_owner(id) or is_platform_admin());

-- ============================================================================
-- 2. org_subscriptions / billing_events / platform_invoices / org_usage —
--    SELECT-only for authenticated, replacing FOR ALL org_isolation.
-- ============================================================================
-- No INSERT/UPDATE/DELETE policy for `authenticated` on any of the four —
-- see pre-flight report: nothing in the app writes these tables today, and
-- their only legitimate future writer (a Razorpay webhook, or
-- admin-update-org-style Edge Function) runs under the service role and
-- is unaffected by the absence of a policy here.
drop policy if exists org_isolation on public.org_subscriptions;
create policy org_subscriptions_select on public.org_subscriptions
  for select
  using (org_id in (select current_org_ids()) or is_platform_admin());

drop policy if exists org_isolation on public.billing_events;
create policy billing_events_select on public.billing_events
  for select
  using (org_id in (select current_org_ids()) or is_platform_admin());

drop policy if exists org_isolation on public.platform_invoices;
create policy platform_invoices_select on public.platform_invoices
  for select
  using (org_id in (select current_org_ids()) or is_platform_admin());

drop policy if exists org_isolation on public.org_usage;
create policy org_usage_select on public.org_usage
  for select
  using (org_id in (select current_org_ids()) or is_platform_admin());

commit;

-- ============================================================================
-- Test gate (NG-BRIEF-rls-remediation.md §4) — direct PostgREST calls with
-- real tokens, not through the app:
--
--   As a non-owner org member (staff or manager PIN session):
--     - PATCH .../organizations?id=eq.<own-org> with any of
--       {plan_id, plan_status, trial_ends_at, active} -> must fail even
--       though it never worked for them before either (no regression to
--       check here, just confirm the column REVOKE holds).
--     - PATCH .../organizations?id=eq.<own-org> with {gstin: "..."} (or
--       any profile column) -> must now fail for a MANAGER specifically
--       (this is the regression flagged above — confirm it's real, not
--       just theorized).
--
--   As OWNER:
--     - PATCH .../organizations?id=eq.<own-org> with a plan/active column
--       -> must fail (column grant blocks everyone, owner included — this
--       IS the point, confirm the owner-only ROW policy doesn't
--       accidentally paper over the column-level block).
--     - PATCH .../organizations?id=eq.<own-org> with {gstin,address,...}
--       -> must still succeed.
--     - POST .../organizations (any body) -> must fail (org_insert
--       dropped, no replacement).
--
--   As PLATFORM ADMIN (a platform_admins row, not necessarily a member of
--   the target org):
--     - Call admin-update-org with {org_id, plan_id} and separately
--       {org_id, active} against a tenant they are NOT an org_member of
--       -> both must succeed (service role, is_platform_admin() gate at
--       the function level, not RLS).
--     - Direct PATCH .../organizations?id=eq.<any-org> with {plan_id} or
--       {active} using the platform admin's own PostgREST token (not the
--       Edge Function) -> must still FAIL — the column grant has no
--       platform-admin carve-out, by design; only the service-role path
--       works.
--     - Confirm both super_admin_page_widget.dart's "Change plan" and
--       tenant_detail_page.dart's "Suspend/Reactivate" now go through
--       admin-update-org and still work end-to-end from the app.
--     - Confirm a billing_events row lands with the right event_type
--       ('plan_changed' / 'suspended' / 'reactivated') and detail.from/to
--       after each.
--
--   Through the app: SettingsPage's business-profile save and logo upload
--   as owner (must work) and as a manager if one is available to test
--   with (must now fail with a visible error — see regression note above).
--
--   Edge Functions unaffected (service role, verify not assume):
--   create-org, admin-update-org (new).
--
-- Report §4.1 results explicitly per the brief's instruction — a write
-- that still succeeds when it shouldn't is the finding that matters.
