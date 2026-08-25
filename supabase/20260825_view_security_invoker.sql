-- =====================================================================
-- 20260825_view_security_invoker.sql
--
-- CRITICAL — cross-tenant read path. Closes a leak that is reachable
-- with the anon key that ships inside the APK.
--
-- WHAT IS WRONG
-- -------------
-- 12 of the 15 views in `public` were created without
-- `security_invoker`, so they run with the OWNER's rights (postgres).
-- postgres owns the base tables, and those tables have RLS ENABLED but
-- not FORCED — so the owner bypasses RLS entirely. Each of these views
-- then groups/returns rows for EVERY organisation.
--
-- Both `anon` and `authenticated` hold SELECT on all 12. The anon key
-- is public by construction (it is in lib/backend/supabase/supabase.dart
-- and therefore in every build), so this is not merely an
-- authenticated-user issue.
--
-- Worst two, and the reason for the ordering below:
--   customer_360_view  — every tenant's customer names, phones,
--                        lifetime value and outstanding
--   trial_balance_view — every tenant's full trial balance
--
-- The app itself is NOT exploiting this: HomePage and friends filter
-- through OrgScope.read(). But that is a client-side filter over a
-- server-side leak, which is exactly the distinction LEAK_AUDIT.md
-- draws. The database must not depend on the client asking nicely.
--
-- WHY security_invoker IS THE RIGHT FIX
-- -------------------------------------
-- `branch_kpis_view`, `gstr1_b2b_view` and `low_stock_view` ALREADY
-- carry `security_invoker=on` and are correct today. This migration
-- brings the other 12 to parity — it is not a new mechanism, it is the
-- mechanism already proven in this schema.
--
-- Note `gstr1_b2b_view` has it and `gstr1_b2c_view` does not. A pair of
-- sibling views disagreeing is strong evidence this was an oversight
-- rather than a deliberate design, which is why every null view is
-- included rather than a hand-picked subset.
--
-- VERIFIED BEFORE WRITING (live pg_catalog, 25 Aug 2026)
--   * PostgreSQL 17.6 — security_invoker is PG15+, supported.
--   * Every table carrying `org_id` has RLS enabled WITH policies
--     (checked: 0 such tables with relrowsecurity = false). So invoker
--     rights actually constrain these views; there is no view whose
--     base tables would still be wide open afterwards.
--   * No Edge Function reads any of these 12 views, so nothing running
--     under service_role changes behaviour.
--   * lib/ reads 7 of the 12, all already via OrgScope.read() — their
--     result sets are unchanged for a correctly-scoped session.
--   * The remaining 5 (fleet_compliance, gstr1_b2c, itc_register,
--     lead_source_performance, trial_balance) are read by nothing yet.
--
-- REVIEW NOTE / EXPECTED BEHAVIOUR CHANGE
-- ---------------------------------------
-- After this runs, a session with no org membership (including anon)
-- gets ZERO rows from these views instead of every org's. That is the
-- point. If any screen suddenly renders empty, the bug is that the
-- screen was relying on the leak — fix the screen, do not revert this.
--
-- Hand-run by Arun. Not executed by an agent.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- PREFLIGHT — fail loudly rather than half-applying.
-- ---------------------------------------------------------------------
do $$
declare
  v_missing text;
  v_norls   text;
begin
  if current_setting('server_version_num')::int < 150000 then
    raise exception
      'PREFLIGHT: security_invoker requires PostgreSQL 15+; this server is %',
      current_setting('server_version');
  end if;

  -- All 12 target views must still exist under these exact names.
  select string_agg(v, ', ' order by v) into v_missing
  from unnest(array[
    'customer_360_view','trial_balance_view','dashboard_kpis_view',
    'advances_view','attendance_view','fleet_compliance_view',
    'gstr1_b2c_view','itc_register_view','lead_source_performance_view',
    'reminders_view','trip_pnl_view','trips_view'
  ]) as v
  where to_regclass('public.' || v) is null;

  if v_missing is not null then
    raise exception 'PREFLIGHT: view(s) missing: %', v_missing;
  end if;

  -- Invoker rights only help where the base tables enforce RLS.
  -- If any org-scoped table lost RLS, flipping these views would give
  -- a false sense of closure.
  select string_agg(c.relname, ', ' order by c.relname) into v_norls
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
    and c.relrowsecurity = false
    and exists (
      select 1 from pg_attribute a
      where a.attrelid = c.oid and a.attname = 'org_id'
        and a.attnum > 0 and not a.attisdropped
    );

  if v_norls is not null then
    raise exception
      'PREFLIGHT: org-scoped table(s) without RLS, invoker rights would not '
      'constrain views reading them: %', v_norls;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Priority 1 — customer PII and full accounting across tenants.
-- ---------------------------------------------------------------------
alter view public.customer_360_view            set (security_invoker = on);
alter view public.trial_balance_view           set (security_invoker = on);

-- ---------------------------------------------------------------------
-- Priority 2 — the tile source the dashboard redesign builds on.
-- ---------------------------------------------------------------------
alter view public.dashboard_kpis_view          set (security_invoker = on);

-- ---------------------------------------------------------------------
-- Priority 3 — the remainder. Included in the same migration so no
-- view is left as the one remaining way in.
-- ---------------------------------------------------------------------
alter view public.advances_view                set (security_invoker = on);
alter view public.attendance_view              set (security_invoker = on);
alter view public.fleet_compliance_view        set (security_invoker = on);
alter view public.gstr1_b2c_view               set (security_invoker = on);
alter view public.itc_register_view            set (security_invoker = on);
alter view public.lead_source_performance_view set (security_invoker = on);
alter view public.reminders_view               set (security_invoker = on);
alter view public.trip_pnl_view                set (security_invoker = on);
alter view public.trips_view                   set (security_invoker = on);

-- ---------------------------------------------------------------------
-- POSTFLIGHT — assert the product, not the intent.
--
-- Checks EVERY view in `public`, not just the 12 listed above, so a
-- view added between the introspection and this run cannot slip through
-- unnoticed. Accepts on/true since Postgres stores the literal spelling.
-- ---------------------------------------------------------------------
do $$
declare v_bad text;
begin
  select string_agg(c.relname, ', ' order by c.relname) into v_bad
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind in ('v', 'm')
    and not coalesce(
      array_to_string(c.reloptions, ',') ~* 'security_invoker=(on|true)',
      false
    );

  if v_bad is not null then
    raise exception
      'POSTFLIGHT: view(s) still running with owner rights: %', v_bad;
  end if;

  raise notice
    'POSTFLIGHT OK: every view in public now runs with invoker rights.';
end $$;

commit;

-- =====================================================================
-- VERIFY AFTER RUNNING (read-only, safe to paste separately)
--
--   select relname, reloptions
--     from pg_class c join pg_namespace n on n.oid = c.relnamespace
--    where n.nspname = 'public' and c.relkind in ('v','m')
--    order by relname;
--
-- Expect security_invoker=on on all 15.
--
-- Then the behavioural check that actually matters — confirm the leak
-- is closed rather than confirming the flag is set. As anon:
--
--   select count(*) from public.customer_360_view;   -- expect 0
--   select count(*) from public.dashboard_kpis_view; -- expect 0
--
-- and from a real logged-in session, confirm the Dashboard still shows
-- that org's own numbers. A flag that is set but untested proves the
-- SDK, not the wiring.
-- =====================================================================
