-- ============================================================
-- 20260723_staff_auth_link_v2.sql  (CORRECTED)
-- Fix vs v1: Supabase installs pgcrypto into the `extensions`
-- schema, so all crypt()/gen_salt() calls are now schema-
-- qualified and function search_path includes `extensions`.
-- Idempotent — safe to re-run.
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

-- 1. Columns ---------------------------------------------------
alter table public.staff add column if not exists auth_user_id uuid;
alter table public.staff add column if not exists pin_hash text;

create unique index if not exists staff_auth_user_id_key
  on public.staff (auth_user_id)
  where auth_user_id is not null;

-- 2. Backfill hashes from existing plaintext PINs --------------
update public.staff
set pin_hash = extensions.crypt(pin, extensions.gen_salt('bf'))
where pin is not null
  and pin <> ''
  and pin_hash is null;

-- 3. Auto-hash trigger (fires when app inserts/updates `pin`) --
create or replace function public.staff_hash_pin()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  if new.pin is not null and new.pin <> ''
     and (tg_op = 'INSERT' or new.pin is distinct from old.pin) then
    new.pin_hash := extensions.crypt(new.pin, extensions.gen_salt('bf'));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_staff_hash_pin on public.staff;
create trigger trg_staff_hash_pin
  before insert or update of pin on public.staff
  for each row execute function public.staff_hash_pin();

-- 4. Server-side PIN verification ------------------------------
create or replace function public.verify_staff_pin(p_staff_id uuid, p_pin text)
returns table (ok boolean, org_id uuid, role text, name text, auth_user_id uuid)
language sql
security definer
set search_path = public, extensions
as $$
  select
    (s.pin_hash is not null
     and s.pin_hash = extensions.crypt(p_pin, s.pin_hash)) as ok,
    s.org_id,
    s.role,
    s.name,
    s.auth_user_id
  from staff s
  where s.id = p_staff_id
    and coalesce(s.active, false) = true;
$$;

-- Lock it down: only service_role (Edge Function) may call it
revoke all on function public.verify_staff_pin(uuid, text) from public;
revoke all on function public.verify_staff_pin(uuid, text) from anon;
revoke all on function public.verify_staff_pin(uuid, text) from authenticated;
grant execute on function public.verify_staff_pin(uuid, text) to service_role;

-- ============================================================
-- CLEANUP — DO NOT RUN NOW.
-- Only after the Flutter app no longer reads staff.pin:
--   update public.staff set pin = null;
--   -- optionally later: alter table public.staff drop column pin;
-- ============================================================
