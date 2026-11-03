-- BUG-021 (full test, 1 Nov 2026): a PIN already used by another person in
-- the same company was accepted (Supervisor Ravi and Driver Kumar both on
-- 1111). PIN login sends only {org, PIN} (verify_org_pin checks the owner
-- pool AND every active staff member of the org), so two people on one PIN
-- either log in as the wrong person or hit "pin_collision" for both.
--
-- Rule enforced here: a PIN must be unique across the WHOLE company
-- (owners + active staff), not just the branch — the PIN pad does not know
-- the branch, so branch-level uniqueness would still collide at login.
--
-- PINs are bcrypt-hashed (salted), so a unique index is impossible; the
-- hashing triggers compare the new plaintext PIN against every other hash
-- in the org before hashing it. ~1 bcrypt compare per person, only when a
-- PIN is being set.
--
-- Existing duplicates cannot be found (no plaintext is stored). They are
-- caught at login by verify_org_pin's existing collision guard; the owner
-- resets one of the two PINs and this check prevents it from recurring.
--
-- NOT APPLIED — Arun runs this.

begin;

create or replace function public.pin_in_use_in_org(
  p_org_id uuid,
  p_pin text,
  p_except_staff_id uuid default null,
  p_except_user_id uuid default null
) returns boolean
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  r record;
begin
  for r in
    select s.pin_hash as h
      from public.staff s
     where s.org_id = p_org_id
       and coalesce(s.active, true)
       and s.pin_hash is not null
       and (p_except_staff_id is null or s.id <> p_except_staff_id)
    union all
    select om.pin_hash
      from public.org_members om
     where om.org_id = p_org_id
       and om.pin_hash is not null
       and (p_except_user_id is null or om.user_id <> p_except_user_id)
  loop
    if r.h = extensions.crypt(p_pin, r.h) then
      return true;
    end if;
  end loop;
  return false;
end;
$$;

revoke all on function public.pin_in_use_in_org(uuid, text, uuid, uuid) from public, anon, authenticated;

-- Staff: same hashing as before, plus the uniqueness check.
create or replace function public.staff_hash_pin()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
begin
  if new.pin is not null and new.pin <> ''
     and (tg_op = 'INSERT' or new.pin is distinct from old.pin) then
    if public.pin_in_use_in_org(new.org_id, new.pin, new.id, null) then
      raise exception 'This PIN is already used by someone else in your company. Choose a different PIN.'
        using errcode = 'unique_violation';
    end if;
    new.pin_hash := extensions.crypt(new.pin, extensions.gen_salt('bf'));
    new.pin := null; -- never store plaintext, not even transiently
  end if;
  return new;
end;
$$;

-- Owner PIN (org_members): same check against staff and other members.
create or replace function public.org_members_hash_pin()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
begin
  if new.pin is not null and new.pin <> '' then
    if public.pin_in_use_in_org(new.org_id, new.pin, null, new.user_id) then
      raise exception 'This PIN is already used by someone else in your company. Choose a different PIN.'
        using errcode = 'unique_violation';
    end if;
    new.pin_hash := extensions.crypt(new.pin, extensions.gen_salt('bf'));
    new.pin := null; -- never store plaintext, not even transiently
  end if;
  return new;
end;
$$;

commit;

-- Check after running (TEST Movers): editing Driver Kumar's PIN to 1111
-- while Supervisor Ravi has 1111 must fail with the message above.
