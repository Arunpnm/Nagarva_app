-- ============================================================
-- 20261021_org_plan_column_lockdown.sql
--
-- Finishes what 20260808_tierB_org_billing_rls.sql item 1 meant to do:
-- no app-side write to an organization's plan or tenancy columns, not
-- even by the owner.
--
-- WHY TIER B'S REVOKE DID NOTHING. It ran
--     revoke update (plan_id, plan_status, trial_ends_at, active)
--       on organizations from authenticated;
-- while `authenticated` (and `anon`) still held table-level UPDATE.
-- Postgres checks table-level privileges first; a column-level REVOKE
-- removes only a column-level grant, of which there was none, so the
-- statement succeeded and changed nothing. Verified live 21 Oct 2026
-- with has_column_privilege(): all four columns, plus the new
-- trial_fallback_plan_id, read UPDATE = true for authenticated AND anon.
-- With Tier B's row policy (org_update: is_org_owner(id) or
-- is_platform_admin()) that means any owner could move their own org to
-- Pro, push trial_ends_at out, or clear a fallback — the exact
-- self-escalation Tier B existed to close.
--
-- THE FIX. Take table-level UPDATE away from authenticated and anon, then
-- give authenticated UPDATE back column by column on every column EXCEPT
-- the protected ones. anon gets no UPDATE at all (it never had a row it
-- could update under RLS; this removes the grant too).
--
-- Protected (no app-side write):
--   id, created_at                   — identity, never edited
--   plan_id, plan_status,
--   trial_ends_at, active,
--   trial_fallback_plan_id           — billing/tenancy state
--
-- Who still writes the protected columns, and why they are unaffected:
--   * admin-update-org (Super Admin plan change, suspend, trial date)
--     and create-org run as service_role, which does not go through
--     these grants.
--   * review_vendor_signup(), choose_signup_plan(),
--     create_org_with_owner() are SECURITY DEFINER owned by postgres.
-- No Dart code writes them directly (checked 21 Oct 2026:
-- org_setup_page writes gstin; business_settings_section and
-- logo_upload_card write profile/branding fields; every plan change in
-- the app goes through admin-update-org).
--
-- CONSEQUENCE FOR FUTURE COLUMNS: a column added to organizations later
-- is NOT updatable from the app until it is granted explicitly. That is
-- the safe default for this table; add a `grant update (col)` with the
-- migration that adds the column if owners should edit it.
--
-- HANDED OVER, NOT RUN. One transaction; the postflight raises and rolls
-- everything back unless every protected column reads UPDATE = false and
-- every other column reads UPDATE = true for authenticated.
-- ============================================================

begin;
set local search_path = public;

-- ---------- preflight ----------
do $$
declare
  v_missing text;
begin
  select string_agg(c, ', ') into v_missing
    from unnest(array['id','created_at','plan_id','plan_status','trial_ends_at',
                      'active','trial_fallback_plan_id']) c
   where not exists (select 1 from information_schema.columns
                      where table_schema = 'public' and table_name = 'organizations'
                        and column_name = c);
  if v_missing is not null then
    raise exception 'organizations is missing column(s): % — run 20261021_vendor_signup_approval.sql first', v_missing;
  end if;

  -- The row policy is half of the control; this migration is the other.
  if not exists (select 1 from pg_policy
                  where polrelid = 'public.organizations'::regclass
                    and polname = 'org_update') then
    raise exception 'organizations has no org_update policy — run 20260808_tierB_org_billing_rls.sql first';
  end if;
end $$;

-- ---------- the fix ----------
revoke update on public.organizations from authenticated, anon;
revoke insert, delete, truncate on public.organizations from anon;

do $$
declare
  v_cols text;
begin
  select string_agg(quote_ident(column_name), ', ' order by ordinal_position)
    into v_cols
    from information_schema.columns
   where table_schema = 'public' and table_name = 'organizations'
     and column_name not in ('id','created_at','plan_id','plan_status',
                             'trial_ends_at','active','trial_fallback_plan_id');
  execute format('grant update (%s) on public.organizations to authenticated', v_cols);
end $$;

-- ---------- postflight ----------
do $$
declare
  r record;
  v_granted int := 0;
begin
  for r in
    select column_name c,
           column_name in ('id','created_at','plan_id','plan_status',
                           'trial_ends_at','active','trial_fallback_plan_id') as protected,
           has_column_privilege('authenticated', 'public.organizations', column_name, 'UPDATE') as auth_upd,
           has_column_privilege('anon', 'public.organizations', column_name, 'UPDATE') as anon_upd
      from information_schema.columns
     where table_schema = 'public' and table_name = 'organizations'
  loop
    if r.anon_upd then
      raise exception 'postflight: anon can still UPDATE organizations.%', r.c;
    end if;
    if r.protected and r.auth_upd then
      raise exception 'postflight: authenticated can still UPDATE protected column organizations.%', r.c;
    end if;
    if not r.protected and not r.auth_upd then
      raise exception 'postflight: authenticated lost UPDATE on profile column organizations.% — the app could no longer save it', r.c;
    end if;
    if not r.protected then v_granted := v_granted + 1; end if;
  end loop;

  if v_granted = 0 then
    raise exception 'postflight: no updatable columns found — nothing was checked';
  end if;

  -- Table-level UPDATE must be gone, or the column grants above are
  -- decorative again (the original Tier B failure).
  if has_table_privilege('authenticated', 'public.organizations', 'UPDATE')
     and exists (select 1 from information_schema.role_table_grants
                  where table_schema = 'public' and table_name = 'organizations'
                    and grantee = 'authenticated' and privilege_type = 'UPDATE') then
    raise exception 'postflight: authenticated still holds table-level UPDATE on organizations';
  end if;

  raise notice 'postflight ok: % profile columns updatable, 7 protected', v_granted;
end $$;

commit;
