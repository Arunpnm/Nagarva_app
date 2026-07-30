-- ============================================================================
-- 20260730_staff_invites.sql
--
-- Auth plan REVISED, build-order item 3: remote staff onboarding.
--
-- Arunkumar runs Chennai, Bengaluru and Coimbatore and cannot be present to
-- set up a supervisor's phone. Onboarding must be remote and must not
-- involve handing over anything of his. So: owner generates a single-use
-- invite, sends it on WhatsApp, staff taps it on their OWN phone, and the
-- device binds to that specific staff_id.
--
-- WHY THIS IS THE SECURITY FIX, not just convenience:
-- Today a staff device is bound to an ORG, so PIN login has to search the
-- whole org for a matching PIN — which is what let a staff PIN equal to the
-- owner's mint an owner session. Binding to a staff_id removes the premise
-- entirely: the device knows exactly who it is, calls staff-login with
-- {staff_id, pin}, and can never reach the owner pool. The collision guard
-- in 20260729 is the stopgap; this is the structural fix.
--
-- Codes are SHORT (8 chars) because they get read aloud and typed on a
-- phone, so they are single-use, expiring, revocable, and rate-limited on
-- redemption. A long random token is safer per-guess but unusable over a
-- phone call, and an unusable flow gets worked around in ways that are
-- worse than a short code.
--
-- Note: the code is stored HASHED, not in plaintext. An invite grants the
-- ability to bind a device to a staff identity, so a leaked database
-- backup should not hand over live invites. The owner sees the plaintext
-- exactly once, at generation.
-- ============================================================================

begin;

create table if not exists public.staff_invites (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  staff_id uuid not null references public.staff(id) on delete cascade,

  -- sha256 of the uppercased code. Never store the code itself.
  code_hash text not null,

  -- Short prefix kept in clear ONLY so the owner can tell two outstanding
  -- invites apart in a list ("ABCD…"). Not enough to redeem.
  code_hint text,

  expires_at timestamptz not null default (now() + interval '7 days'),
  used_at timestamptz,
  used_by_device text,          -- opaque device id, for support questions
  revoked_at timestamptz,
  created_by uuid,              -- auth.users.id of the owner who generated it
  created_at timestamptz not null default now()
);

create unique index if not exists staff_invites_code_hash_key
  on public.staff_invites (code_hash);

-- Redemption looks up by hash; the owner's list is by staff.
create index if not exists staff_invites_staff_idx
  on public.staff_invites (org_id, staff_id, created_at desc);

-- At most ONE live invite per staff member. Generating a new one must
-- supersede the old, otherwise revoking the one you know about leaves
-- another working. Partial unique index enforces it in the database
-- rather than in app logic.
create unique index if not exists staff_invites_one_live_per_staff
  on public.staff_invites (staff_id)
  where used_at is null and revoked_at is null;

alter table public.staff_invites enable row level security;
drop policy if exists org_isolation on public.staff_invites;
create policy org_isolation on public.staff_invites
  for all to authenticated
  using (org_id in (select current_org_ids()) or is_platform_admin())
  with check (org_id in (select current_org_ids()) or is_platform_admin());

-- Redemption happens PRE-AUTH — the staff member has no session yet, that
-- is the whole point — so it cannot go through RLS. It runs in the
-- staff-invite-redeem Edge Function under the service role, which is also
-- where rate limiting lives. anon is granted nothing here.

-- ---------------------------------------------------------------------------
-- Redemption attempt tracking. Same shape and reasoning as
-- org_pin_attempts: an 8-char code is brute-forceable given enough
-- attempts, and there is no session to attribute a failure to, so the
-- counter is per-device.
-- ---------------------------------------------------------------------------
create table if not exists public.invite_redeem_attempts (
  device_id text primary key,
  failed_attempts integer not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.invite_redeem_attempts enable row level security;
-- No policies: service-role only, like app_defaults.

commit;

-- Verify after running:
--   \d staff_invites
--   \d invite_redeem_attempts
--   select indexname from pg_indexes
--    where tablename = 'staff_invites' order by indexname;
--   -- expect staff_invites_code_hash_key,
--   --        staff_invites_one_live_per_staff,
--   --        staff_invites_staff_idx, plus the pkey
--
--   -- the one-live-per-staff guard actually bites:
--   -- insert two unused invites for the same staff_id -> second must fail
--   --   with duplicate key on staff_invites_one_live_per_staff
