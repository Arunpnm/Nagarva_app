-- subscription_plans SELECT — platform-admin carve-out for inactive plans.
-- Handed over for Arun to review and run — not executed from this session.
--
-- WHY: found while confirming subscription_plans' live RLS on request
-- (super-admin console report, 16 Aug 2026). Three policies exist:
--   plans_insert  INSERT  authenticated        is_platform_admin()
--   plans_update  UPDATE  authenticated        is_platform_admin()
--   plans_select  SELECT  anon, authenticated  active = true
-- INSERT/UPDATE are correctly gated — not a security hole, this pass
-- found nothing wrong there. The gap is SELECT: it has no platform-admin
-- carve-out at all, only the public `active = true` condition. RLS
-- policies for the same command are OR'd together, and there is no
-- second SELECT policy — so even a platform admin session (still just an
-- `authenticated` role user under RLS) can only ever see active plans
-- through this policy. plans_tab.dart's own read
-- (SubscriptionPlansTable().queryRows(queryFn: (q) => q.order(...))) has
-- no filter of its own to compensate.
--
-- This hasn't bitten yet because nothing in the app currently sets
-- `active: false` on an existing plan (plan_edit_sheet.dart's create path
-- always inserts `active: true`; there is no deactivate toggle). It will
-- bite the moment trial/starter/pro get retired in favour of
-- basic/growth/pro (Arun's stated next step) -- retiring a plan should
-- not make it invisible to the one console meant to manage it.
--
-- FIX: extend plans_select's USING clause with is_platform_admin(), same
-- function INSERT/UPDATE already use. Plain visitors (anon/authenticated,
-- non-admin) still only ever see active=true — this only adds visibility
-- for the platform-admin case, no other policy behaviour changes.
-- ALTER POLICY updates the clause in place; no DROP needed (that rule is
-- for CREATE OR REPLACE FUNCTION/VIEW signature/shape changes, not for a
-- policy's USING expression, which ALTER POLICY handles directly).

begin;

alter policy plans_select on public.subscription_plans
  using (active = true or is_platform_admin());

commit;

-- ============================================================================
-- Verify after running:
--
--   select policyname, cmd, qual
--     from pg_policies
--    where schemaname = 'public' and tablename = 'subscription_plans'
--      and policyname = 'plans_select';
--   -- expect qual = '(active = true) OR is_platform_admin()' (or
--   -- equivalent parenthesisation) -- the two other policies
--   -- (plans_insert/plans_update) are untouched by this migration.
--
--   -- As a platform admin (a session whose user_id has a platform_admins
--   -- row), the Plans tab should now list an active=false plan if one
--   -- exists; a plain authenticated/anon read should still only ever see
--   -- active=true rows -- spot-check both if you have a deactivated test
--   -- plan to hand.
-- ============================================================================
