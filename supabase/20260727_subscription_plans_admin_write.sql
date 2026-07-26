-- ============================================================================
-- 20260727_subscription_plans_admin_write.sql
-- Super-admin console, Step 1 (plan management UI).
--
-- NOT YET RUN — paste into the Supabase SQL editor when convenient.
-- Idempotent — safe to re-run.
--
-- BUG FOUND live-testing the new Plans tab in /super-admin: editing a
-- plan's price (or anything else) closes the sheet with no error and the
-- list even shows the new value — but a fresh page reload shows the OLD
-- value again. Root cause: supabase/migrations/20260715_rls_v1.sql gave
-- subscription_plans a SELECT-only RLS policy, header-commented
-- "read-only, managed via dashboard" — a deliberate decision at the time,
-- since nothing but the SQL editor was ever meant to write this table.
-- The super-admin console's whole point is to change that, so RLS needs
-- an INSERT/UPDATE policy gated on is_platform_admin(), same pattern
-- already used for `organizations` in that same migration (select/insert/
-- update, no delete — this mirrors that shape exactly, not inventing a
-- new pattern).
--
-- Until this runs, the Plans tab's list/edit-sheet/pre-fill UI all work
-- correctly (confirmed live) but every save is a silent no-op — RLS
-- filters the UPDATE's row set to zero without PostgREST treating that as
-- an error, so the app has no way to detect it client-side either. Not
-- fixable in app code; this is the actual fix.
-- ============================================================================

drop policy if exists plans_insert on public.subscription_plans;
create policy plans_insert on public.subscription_plans for insert
  to authenticated
  with check (is_platform_admin());

drop policy if exists plans_update on public.subscription_plans;
create policy plans_update on public.subscription_plans for update
  to authenticated
  using (is_platform_admin())
  with check (is_platform_admin());

-- ============================================================================
-- POST-RUN VERIFICATION:
--   As the platform-admin-seeded owner account, edit a plan's price via
--   /super-admin's Plans tab, then reload the page — the new price should
--   persist. As any other authenticated (non-platform-admin) account, the
--   same edit should fail (RLS denies it, is_platform_admin() is false).
-- ============================================================================
