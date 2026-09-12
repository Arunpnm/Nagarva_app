-- =====================================================================
-- 20260912_drop_zzz_test_plan.sql
--
-- Removes 'ZZZ Test Plan (delete me)' from subscription_plans.
--
-- Residue from the 17 Aug 2026 Item 11 device-verification pass, which
-- built a throwaway org and left its plan behind. It has sat in the live
-- plan list since — visible to Super Admin's plan picker, and one
-- mis-click from being assigned to a real tenant.
--
-- VERIFIED BEFORE WRITING THIS, not assumed. subscription_plans has TWO
-- inbound foreign keys, and both were counted:
--   organizations.plan_id      -> 0 orgs on this plan
--   org_subscriptions.plan_id  -> 0 rows on this plan (0 rows in the
--                                 whole table)
-- The preflight re-counts both at run time rather than trusting those
-- numbers, because they were taken on 12 Sept 2026 and a delete guarded
-- by a stale count is not guarded at all.
--
-- A PLAIN DELETE, NOT A DEACTIVATION. `active = false` would keep a row
-- named "delete me" in a table the Super Admin plan editor reads, which
-- is the state being removed. Nothing references it, so there is no
-- history to preserve -- unlike `starter`, which was UPDATED in place to
-- Basic precisely because organizations.plan_id referenced it.
--
-- APPLIED 12 Sept 2026. The preflight re-counted both inbound foreign
-- keys at run time (0 orgs, 0 subscriptions), one row was deleted, and
-- the postflight passed: survivors are exactly basic, growth, pro,
-- trial, with exactly one is_default_trial.
-- =====================================================================

begin;

set local search_path = public, pg_catalog;

-- ---------------------------------------------------------------------
-- PREFLIGHT. Raises; never skips.
-- ---------------------------------------------------------------------
do $$
declare
  v_id    uuid;
  v_orgs  int;
  v_subs  int;
begin
  select id into v_id from subscription_plans where code = 'zzz-test';

  if v_id is null then
    -- The expected response to a RE-RUN, not a fault. This raise is
    -- what stops a second run reporting success over a no-op.
    --
    -- The message said "this file can be deleted" until 12 Sept 2026,
    -- which was wrong and got shown to the operator on the very first
    -- re-run: applied migrations are KEPT in this repo as the record of
    -- what was done, and the header above already says APPLIED. Telling
    -- someone to delete a migration because it succeeded is the
    -- opposite of what this directory is for.
    raise exception
      'no plan with code zzz-test exists, so this migration has ALREADY '
      'RUN -- see the APPLIED note in the header. Nothing to do, nothing '
      'is wrong, and nothing was changed by this attempt. Keep the file.';
  end if;

  select count(*) into v_orgs from organizations     where plan_id = v_id;
  select count(*) into v_subs from org_subscriptions where plan_id = v_id;

  if v_orgs > 0 or v_subs > 0 then
    raise exception
      'zzz-test is REFERENCED -- % organization(s) and % subscription(s) '
      'point at it. Move them to a real plan first; deleting now would '
      'either fail on the foreign key or strand a live tenant with no '
      'plan.', v_orgs, v_subs;
  end if;

  -- A test plan must never have been the default any org inherits.
  if exists (select 1 from subscription_plans
              where code = 'zzz-test' and is_default_trial) then
    raise exception
      'zzz-test is flagged is_default_trial. Deleting it would leave new '
      'signups with no trial plan to inherit. Move that flag to the real '
      'Trial plan first.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- THE DELETE
-- ---------------------------------------------------------------------
delete from public.subscription_plans where code = 'zzz-test';

-- ---------------------------------------------------------------------
-- POSTFLIGHT
--
-- Asserts the row is gone AND that the real plans are untouched --
-- a delete that took more than its target must not commit.
-- ---------------------------------------------------------------------
do $$
declare
  v_left    int;
  v_codes   text;
  v_default int;
begin
  select count(*) into v_left
    from subscription_plans where code = 'zzz-test';
  if v_left <> 0 then
    raise exception 'zzz-test is still present after the delete.';
  end if;

  select string_agg(code, ',' order by code) into v_codes
    from subscription_plans;
  if v_codes is distinct from 'basic,growth,pro,trial' then
    raise exception
      'the surviving plan codes are "%" -- expected exactly '
      '"basic,growth,pro,trial". Something other than the test plan was '
      'removed.', v_codes;
  end if;

  select count(*) into v_default
    from subscription_plans where is_default_trial;
  if v_default <> 1 then
    raise exception
      '% plans carry is_default_trial -- exactly one must, or signup '
      'either finds no trial plan or picks arbitrarily.', v_default;
  end if;

  raise notice
    'zzz-test removed. Four plans remain (basic, growth, pro, trial) with '
    'exactly one default trial.';
end $$;

commit;

-- =====================================================================
-- ROLLBACK
--   insert into public.subscription_plans (code, name, price_inr,
--     billing_period, active, is_default_trial)
--   values ('zzz-test', 'ZZZ Test Plan (delete me)', 0, 'monthly',
--           true, false);
--   A new id is generated, which is harmless precisely because nothing
--   referenced the old one.
-- =====================================================================
