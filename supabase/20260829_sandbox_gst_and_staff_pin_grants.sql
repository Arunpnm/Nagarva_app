-- =====================================================================
-- 29 Aug 2026 — two unrelated changes, deliberately in one block because
-- they are both prerequisites for the same seeding run.
--
-- 1. SANDBOX GST SETUP (data, sandbox org only)
--    Gives f12f1dd5 a Karnataka GSTIN + state_code 29 so the invoice
--    path exercises a real intrastate/interstate decision instead of
--    falling through the city->state default. Touches the SANDBOX ONLY —
--    APC (b2c0c816, GSTIN 33ARLPA3366M1ZO) is not referenced anywhere
--    in this file.
--
-- 2. staff.pin COLUMN GRANTS (security, all orgs)
--    a. authenticated has INSERT+SELECT but NOT UPDATE on staff.pin, so
--       an owner can create a staff member with a PIN and can never
--       change it. PIN reset from the app is impossible today.
--       GRANT UPDATE is safe because RLS already restricts it: the
--       `staff_update` policy is
--         USING/WITH CHECK (is_org_owner(org_id) OR is_platform_admin())
--       so the column privilege widens WHO can be targeted not at all —
--       it only stops Postgres refusing the column outright. Verified
--       against pg_policy before writing this.
--
--    b. anon holds SELECT, INSERT and UPDATE on staff.pin — strictly
--       WIDER than authenticated, on the column that becomes a login
--       credential. Nothing needs it: every Edge Function that touches
--       staff (staff-invite-redeem, staff-login, staff-deactivate,
--       staff-invite) runs under SERVICE_ROLE, which bypasses both RLS
--       and column grants, so revoking anon cannot affect them.
--       Only RLS stands behind these today, which is one control where
--       there should be two.
--
--       SELECT on the plaintext column is the sharpest of the three:
--       staff_hash_pin nulls it on write, so it should always be NULL —
--       but a grant that lets anyone read a plaintext PIN column is not
--       something to leave standing on the argument that the column
--       happens to be empty.
--
-- pin_hash is NOT touched here. Its grants are the same shape and the
-- same problem, but revoking them needs verify_org_pin/verify_staff_pin
-- re-checked first (both are SECURITY DEFINER and should be unaffected,
-- but "should be" is not "checked"). Separate pass, deliberately.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- PREFLIGHT
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from public.organizations
                  where id = 'f12f1dd5-9fb0-4060-8d10-6356d6bd57c9') then
    raise exception 'PREFLIGHT: sandbox org f12f1dd5 does not exist';
  end if;

  if not exists (select 1 from public.branches
                  where org_id = 'f12f1dd5-9fb0-4060-8d10-6356d6bd57c9') then
    raise exception 'PREFLIGHT: sandbox org has no branch to set state_code on';
  end if;

  -- Guard against this file ever being pointed at the real org.
  if exists (select 1 from public.organizations
              where id = 'f12f1dd5-9fb0-4060-8d10-6356d6bd57c9'
                and gstin = '33ARLPA3366M1ZO') then
    raise exception 'PREFLIGHT: refusing to run — target carries APC''s GSTIN';
  end if;

  if not exists (
    select 1 from pg_policy
     where polrelid = 'public.staff'::regclass and polname = 'staff_update'
  ) then
    raise exception
      'PREFLIGHT: staff_update policy missing — do not grant UPDATE on '
      'staff.pin without the owner-only RLS behind it';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. Sandbox GST identity
-- ---------------------------------------------------------------------
update public.organizations
   set gstin      = '29AAAAA0000A1Z5',
       state      = coalesce(state, 'Karnataka'),
       state_code = '29'
 where id = 'f12f1dd5-9fb0-4060-8d10-6356d6bd57c9';

update public.branches
   set state_code = '29',
       state      = coalesce(state, 'Karnataka')
 where org_id = 'f12f1dd5-9fb0-4060-8d10-6356d6bd57c9';

-- ---------------------------------------------------------------------
-- 2a. Let an owner reset a staff PIN. RLS keeps this owner-only.
-- ---------------------------------------------------------------------
grant update (pin) on public.staff to authenticated;

-- ---------------------------------------------------------------------
-- 2b. anon has no business with a credential column.
-- ---------------------------------------------------------------------
revoke select (pin), insert (pin), update (pin) on public.staff from anon;

-- ---------------------------------------------------------------------
-- 2c. Same for pin_hash — anon only.
--
-- Both verifiers are SECURITY DEFINER (checked: verify_org_pin and
-- verify_staff_pin both prosecdef = true), so they are immune to role
-- grants and this cannot affect login.
--
-- `authenticated` is deliberately NOT revoked on pin_hash, and this is
-- the important note. It SHOULD be: `staff_select` is org-wide
-- (org_id in (select current_org_ids())), so today any org member can
-- read every colleague's hash, and bcrypt at cost 6 over a 10,000-value
-- keyspace is not protection.
--
-- It cannot be revoked yet because SupabaseTable._select() issues a bare
-- `.select()` — SELECT * — so every StaffTable query would fail with
-- "permission denied for column pin_hash" and take the users page, staff
-- pickers and crew assignment with it. Nothing in lib/ actually READS
-- pin_hash; it is pure SELECT * collateral.
--
-- LOGGED FOR A LATER PASS (Arun, 29 Aug 2026) — the agreed fix is NOT to
-- narrow _select() or add a staff_safe view, but to move the credential
-- columns out of `staff` entirely:
--
--   staff_credentials(staff_id pk, pin, pin_hash, failed_pin_attempts,
--                     pin_locked_until, pin_lock_level)
--   granted to service_role ONLY.
--
-- Nothing in lib/ reads those columns, so SELECT * keeps working and no
-- call site changes. staff_hash_pin and verify_staff_pin move with them.
-- Raise the bcrypt cost above 6 in the same pass — gen_salt('bf') with
-- no argument is cost 6 in both hash functions today.
-- ---------------------------------------------------------------------
revoke select (pin_hash), insert (pin_hash), update (pin_hash)
  on public.staff from anon;

-- ---------------------------------------------------------------------
-- POSTFLIGHT — roll back if any of it failed to take.
-- ---------------------------------------------------------------------
do $$
declare
  v_gstin text;
  v_state_code text;
  v_anon int;
  v_auth_update int;
begin
  select gstin into v_gstin from public.organizations
   where id = 'f12f1dd5-9fb0-4060-8d10-6356d6bd57c9';
  if v_gstin is distinct from '29AAAAA0000A1Z5' then
    raise exception 'POSTFLIGHT: sandbox gstin is % not 29AAAAA0000A1Z5', v_gstin;
  end if;

  select state_code into v_state_code from public.branches
   where org_id = 'f12f1dd5-9fb0-4060-8d10-6356d6bd57c9' limit 1;
  if v_state_code is distinct from '29' then
    raise exception 'POSTFLIGHT: branch state_code is % not 29', v_state_code;
  end if;

  select count(*) into v_anon
    from information_schema.column_privileges
   where table_schema='public' and table_name='staff'
     and column_name in ('pin','pin_hash') and grantee='anon';
  if v_anon > 0 then
    raise exception
      'POSTFLIGHT: anon still holds % privilege(s) on staff.pin/pin_hash', v_anon;
  end if;

  -- Guard the deferral: authenticated MUST retain SELECT on pin_hash
  -- until _select() stops asking for it, or every staff query 500s.
  if not exists (
    select 1 from information_schema.column_privileges
     where table_schema='public' and table_name='staff'
       and column_name='pin_hash' and grantee='authenticated'
       and privilege_type='SELECT'
  ) then
    raise exception
      'POSTFLIGHT: authenticated lost SELECT on staff.pin_hash — '
      'SupabaseTable._select() is SELECT *, so every staff query would fail';
  end if;

  select count(*) into v_auth_update
    from information_schema.column_privileges
   where table_schema='public' and table_name='staff'
     and column_name='pin' and grantee='authenticated'
     and privilege_type='UPDATE';
  if v_auth_update <> 1 then
    raise exception 'POSTFLIGHT: authenticated lacks UPDATE on staff.pin';
  end if;
end $$;

commit;

-- =====================================================================
-- VERIFICATION — paste the output back.
-- =====================================================================
select 'org' as scope, o.slug as detail, o.gstin, o.state, o.state_code
  from public.organizations o
 where o.id = 'f12f1dd5-9fb0-4060-8d10-6356d6bd57c9'
union all
select 'branch', b.name, null, b.state, b.state_code
  from public.branches b
 where b.org_id = 'f12f1dd5-9fb0-4060-8d10-6356d6bd57c9'
union all
select 'APC untouched', o.slug, o.gstin, o.state, o.state_code
  from public.organizations o
 where o.id = 'b2c0c816-f282-44db-a8b4-9c0fc7478aee'
union all
select 'grant: '||grantee, privilege_type, null, null, null
  from information_schema.column_privileges
 where table_schema='public' and table_name='staff' and column_name='pin'
   and grantee in ('anon','authenticated');
