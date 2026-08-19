-- ============================================================
-- supabase/20260816_invite_codes.sql
--
-- Closed-beta gate for self-signup. Signup is live but the CFT
-- catalogue is still APC-shaped, so every new tenant today gets a
-- product that doesn't fit a non-APC business.
--
-- TWO enforcement points, by design:
--   1. is_invite_code_valid(p_code) — anon-callable, boolean only. Called
--      from SignupPageWidget BEFORE auth.signUp(), so a blank/wrong code
--      never gets as far as creating an auth account at all. This is a
--      convenience check, not the real gate — it can race two people
--      onto the last use of a single-use code.
--   2. create-org (Edge Function, supabase/functions/create-org/index.ts)
--      — the real, atomic gate. Validates + consumes the code as part of
--      the same request that creates the org, so the race above always
--      resolves correctly (one of the two gets create-org's 403) even
--      though the RPC already said "valid" to both.
-- is_invite_code_valid is rate-limited 20/IP/10min (see
-- invite_code_rate_limit below) — it's anon-callable and unauthenticated
-- by necessity, which makes it a low-value but real code-guessing oracle.
-- A user who gets through auth.signUp() with a code that then loses the
-- race at create-org is NOT stranded silently — vendor_org_resolver.dart
-- (the shared "confirmed but no org yet" recovery path every login goes
-- through) surfaces create-org's real error message on next login
-- attempt, via extractFunctionErrorMessage (edge_function_errors.dart).
--
-- DEPLOY ORDER: run this FIRST, then
-- `supabase functions deploy create-org`, matching that file's own
-- header comment. Deploying the function first would 500 every signup
-- (querying tables that don't exist yet).
--
-- REVERSIBLE IN ONE CONFIG CHANGE when Item 12 (CFT catalogue) ships —
-- no redeploy of anything, just:
--   update platform_settings set value = 'false'::jsonb
--     where key = 'signup_requires_invite';
-- Both create-org and is_invite_code_valid read this same row, so
-- there's exactly one flag to flip, not two. NOTE (17 Aug 2026): the
-- signup form's invite-code field is marked required client-side
-- regardless of this flag — flipping it off stops the gate from
-- rejecting codes, but the form will still ask for *something* to be
-- typed until that validator is revisited too (see
-- signup_page_widget.dart's comment on the field).
--
-- RLS: both tables enabled with NO policies, deliberately. Only
-- SECURITY DEFINER functions (is_invite_code_valid) and the service
-- role (create-org) ever touch them — this just guarantees the anon/
-- authenticated client can never read codes, usage counts, or the
-- gating flag directly over PostgREST.
-- ============================================================

create table if not exists platform_settings (
  key         text primary key,
  value       jsonb not null,
  updated_at  timestamptz not null default now()
);

alter table platform_settings enable row level security;

insert into platform_settings (key, value) values
  ('signup_requires_invite', 'true'::jsonb)
on conflict (key) do nothing;

create table if not exists invite_codes (
  code            text primary key,
  active          boolean not null default true,
  max_uses        integer,              -- null = unlimited
  used_count      integer not null default 0,
  issued_to       text,                 -- who this code was handed to, e.g. 'Ramesh - ABC Movers'
  expires_at      timestamptz,          -- null = never expires
  used_by_org_id  uuid references organizations(id),  -- set by create-org on first successful use
  note            text,
  created_at      timestamptz not null default now()
);

alter table invite_codes enable row level security;

-- Per-IP rate limit for is_invite_code_valid below. This RPC is
-- anon-callable and unauthenticated by necessity (it runs before a
-- session exists) — that makes it a code-guessing oracle even though it
-- only returns a boolean. Real-world risk is low (codes are random
-- 10-char strings), but the guard is nearly free, so it's in. One row
-- per IP ever seen (bounded, no cleanup needed) rather than one row per
-- attempt.
create table if not exists invite_code_rate_limit (
  ip                 text primary key,
  attempts           integer not null default 0,
  window_started_at  timestamptz not null default now()
);

alter table invite_code_rate_limit enable row level security;

-- Boolean-only, anon-callable — deliberately exposes nothing else about
-- a code (not active/max_uses/used_count/issued_to), so this can't be
-- used to enumerate or fingerprint real codes.
create or replace function is_invite_code_valid(p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requires boolean;
  v_row invite_codes%rowtype;
  v_ip text;
  v_attempts integer;
  v_window_start timestamptz;
begin
  -- 20 checks per IP per 10-minute window, then fail closed (same
  -- outcome as an invalid code — this RPC's contract is a bare boolean,
  -- so there's no separate "rate limited" signal to leak either).
  -- x-forwarded-for is the same header sign-document/track-order already
  -- trust for best-effort audit logging; PostgREST exposes request
  -- headers as a GUC, so no separate Edge Function is needed just for
  -- this. Falls back to a single shared 'unknown' bucket if the header
  -- is ever missing/unparseable, rather than erroring the whole check.
  begin
    v_ip := coalesce(
      current_setting('request.headers', true)::json ->> 'x-forwarded-for',
      'unknown'
    );
  exception when others then
    v_ip := 'unknown';
  end;
  v_ip := split_part(v_ip, ',', 1);

  select attempts, window_started_at into v_attempts, v_window_start
  from invite_code_rate_limit where ip = v_ip for update;

  if not found then
    insert into invite_code_rate_limit (ip, attempts, window_started_at)
    values (v_ip, 1, now());
  elsif now() - v_window_start > interval '10 minutes' then
    update invite_code_rate_limit
      set attempts = 1, window_started_at = now()
      where ip = v_ip;
  else
    if v_attempts >= 20 then
      return false;
    end if;
    update invite_code_rate_limit set attempts = attempts + 1 where ip = v_ip;
  end if;

  select (value = 'true'::jsonb) into v_requires
  from platform_settings where key = 'signup_requires_invite';
  if v_requires is null then
    v_requires := true; -- missing row = fail closed
  end if;
  if not v_requires then
    return true;
  end if;

  if p_code is null or btrim(p_code) = '' then
    return false;
  end if;

  select * into v_row from invite_codes where code = btrim(p_code);
  if not found then
    return false;
  end if;
  if not v_row.active then
    return false;
  end if;
  if v_row.expires_at is not null and v_row.expires_at < now() then
    return false;
  end if;
  if v_row.max_uses is not null and v_row.used_count >= v_row.max_uses then
    return false;
  end if;
  return true;
end;
$$;

grant execute on function is_invite_code_valid(text) to anon, authenticated;

-- Seed per-member single-use codes for the IPAMTOA closed beta. Replace
-- the placeholder rows below with real codes/names before running this
-- — max_uses 1 each, so every code maps to exactly one signup and
-- used_by_org_id (set by create-org) tells you which org it became.
insert into invite_codes (code, max_uses, issued_to, note) values
  ('IPAMTOA-PLACEHOLDER-01', 1, 'REPLACE ME', 'IPAMTOA closed beta')
on conflict (code) do nothing;

-- Verify after running:
--   select code, active, max_uses, used_count, issued_to, used_by_org_id
--   from invite_codes;
--   select * from platform_settings;
--   select * from invite_code_rate_limit;  -- empty until someone calls the RPC
