-- =============================================================
-- Migration: 20260716_default_trial_plan.sql
-- Fix: plan_id left NULL on new org signup
-- Approach: BEFORE INSERT trigger assigns the default trial plan
--           + 14-day trial_ends_at, so EVERY insert path is safe
--           (app signup, admin console, future RPCs).
-- Also backfills existing orgs that already have NULL plan_id.
-- Convention: commit to repo (supabase/migrations/) BEFORE applying.
-- =============================================================

-- 0) Safety: ensure exactly one default trial plan exists.
--    (Adjust name/limits to match your subscription_plans schema
--     if column names differ.)
do $$
begin
  if not exists (
    select 1 from public.subscription_plans where is_default_trial = true
  ) then
    raise exception
      'No subscription_plans row has is_default_trial = true. Mark your trial plan first.';
  end if;

  if (select count(*) from public.subscription_plans where is_default_trial = true) > 1 then
    raise exception
      'More than one plan has is_default_trial = true. Exactly one is required.';
  end if;
end $$;

-- 1) Trigger function (security definer so it works regardless of
--    the inserting user's RLS visibility into subscription_plans).
create or replace function public.assign_default_trial_plan()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_trial_plan_id uuid;
begin
  if new.plan_id is null then
    select id into v_trial_plan_id
    from public.subscription_plans
    where is_default_trial = true
    limit 1;

    new.plan_id := v_trial_plan_id;
  end if;

  if new.trial_ends_at is null then
    new.trial_ends_at := now() + interval '14 days';
  end if;

  return new;
end;
$$;

-- 2) Attach trigger to organizations.
drop trigger if exists trg_assign_default_trial_plan on public.organizations;

create trigger trg_assign_default_trial_plan
  before insert on public.organizations
  for each row
  execute function public.assign_default_trial_plan();

-- 3) Backfill: repair any existing orgs stuck with NULL plan_id.
--    Their 14-day trial starts from their created_at (fair), not today.
update public.organizations o
set
  plan_id = (
    select id from public.subscription_plans
    where is_default_trial = true limit 1
  ),
  trial_ends_at = coalesce(o.trial_ends_at, o.created_at + interval '14 days')
where o.plan_id is null;

-- =============================================================
-- VERIFICATION (run after applying)
-- =============================================================
-- a) No org should have NULL plan_id:
--    select id, name, plan_id, trial_ends_at
--    from organizations where plan_id is null;   -- expect 0 rows
--
-- b) Trigger smoke test (rolls itself back):
--    begin;
--      insert into organizations (name) values ('__trigger_test__');
--      select name, plan_id, trial_ends_at
--      from organizations where name = '__trigger_test__';
--      -- expect plan_id = trial plan uuid, trial_ends_at ≈ now()+14d
--    rollback;
--
-- c) APC (tenant #1) sanity — should be untouched if it already
--    had a plan:
--    select plan_id, trial_ends_at from organizations
--    where id = '11111111-1111-4111-8111-111111111111';
-- =============================================================
