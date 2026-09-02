-- Let an owner actually save their own PIN.
--
-- THE BUG. `org_members` has RLS enabled with exactly two policies,
-- members_select and members_insert. There is NO UPDATE policy. So
-- saveOwnerPin()'s update matched zero rows, PostgREST returned success
-- with no error, and the app said "PIN updated." having written nothing.
--
-- Found 2 Sep 2026 by reading org_members.pin_hash back after setting a
-- PIN through the first-run screen: APC Bengaluru still had pin_set =
-- false. It affects every owner and every org - the parent APC row only
-- has a PIN because it was set before this path existed. A vendor sets a
-- PIN at first run, is told it worked, and can never PIN-log-in; there
-- is no error anywhere to explain it.
--
-- WHY THE COLUMN REVOKE IS MANDATORY, NOT HARDENING. `authenticated`
-- already holds table-wide UPDATE on org_members, including `role`,
-- `pin_hash`, `org_id` and `user_id`. That grant is inert TODAY only
-- because RLS denies every UPDATE. Adding a row policy without narrowing
-- the grant would, in the same statement, let any member set their own
-- role to 'owner' and write pin_hash directly - bypassing bcrypt. The
-- grant and the policy must land together.
--
-- Same shape as the Phase 0 staff-credential lockdown: a column GRANT
-- for what may be written, a row policy for which row.

begin;

-- ---------------------------------------------------------- PREFLIGHT --
do $pre$
begin
  if to_regclass('public.org_members') is null then
    raise exception 'PREFLIGHT: public.org_members is missing.';
  end if;

  if exists (select 1 from pg_policies
              where tablename = 'org_members' and cmd = 'UPDATE') then
    raise exception
      'PREFLIGHT: an UPDATE policy already exists on org_members. Review it before adding another.';
  end if;

  -- The PIN is written as PLAINTEXT to org_members.pin and bcrypted into
  -- pin_hash by this trigger, which also nulls the plaintext column. No
  -- trigger means enabling pin writes would store PINs in the clear.
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.org_members'::regclass
                    and tgname  = 'org_members_hash_pin_trigger'
                    and not tgisinternal
                    and tgenabled <> 'D') then
    raise exception
      'PREFLIGHT: org_members_hash_pin_trigger is missing or disabled. Enabling pin writes without it would store plaintext PINs.';
  end if;

  raise notice 'PREFLIGHT ok: no UPDATE policy yet, hashing trigger live.';
end;
$pre$;

-- ------------------------------------------------------------- GRANT --
-- Narrow first, so there is no window in which the policy below is live
-- against the table-wide grant.
revoke update on public.org_members from authenticated;
grant  update (pin) on public.org_members to authenticated;

-- ------------------------------------------------------------ POLICY --
-- Own row only. `role` cannot be touched because the grant does not
-- include it, and pin_hash is written by the trigger, not the caller.
create policy members_update_own_pin on public.org_members
  for update to authenticated
  using      (user_id = auth.uid())
  with check (user_id = auth.uid());

comment on policy members_update_own_pin on public.org_members is
  'Lets a signed-in user set the PIN on their OWN membership row. Paired with a column GRANT of UPDATE(pin) only - without that grant this policy would also permit self-escalation via role.';

-- --------------------------------------------------------- POSTFLIGHT --
do $post$
declare
  v_cols text;
begin
  if not exists (select 1 from pg_policies
                  where tablename = 'org_members'
                    and policyname = 'members_update_own_pin') then
    raise exception 'POSTFLIGHT(a): members_update_own_pin was not created.';
  end if;

  select string_agg(column_name::text, ',' order by column_name::text)
    into v_cols
    from information_schema.column_privileges
   where table_name = 'org_members'
     and grantee = 'authenticated'
     and privilege_type = 'UPDATE';

  -- Exactly one updatable column. If `role` is in this list the migration
  -- has opened privilege escalation and must not commit.
  if coalesce(v_cols, '') <> 'pin' then
    raise exception
      'POSTFLIGHT(b): authenticated can UPDATE columns [%] on org_members; expected exactly [pin].',
      coalesce(v_cols, '<none>');
  end if;

  raise notice 'POSTFLIGHT ok: own-row PIN updates allowed, and only the pin column is writable.';
end;
$post$;

commit;

-- AFTER RUNNING: set each org's owner PIN through the app (Settings ->
-- App PIN, or the first-run screen), then verify the write actually
-- landed rather than trusting the success message that caused this bug:
--
--   select o.slug, (m.pin_hash is not null) as pin_set
--     from org_members m join organizations o on o.id = m.org_id
--    order by o.created_at;
