# Nagarva — auth plan (REVISED, supersedes earlier version)

30 Jul 2026. Revised after establishing that **every staff member has their
own personal phone** — no shared branch handsets.

Read alongside Item 16 (self-signup) and Item 30 (roles matrix) in
`nagarva_master_build_brief.md`.

---

## The correction that changes everything

An earlier draft implied staff would need the owner's email and password on
their device. That was wrong. **Staff devices never receive any owner
credential.**

Arunkumar runs branches in Chennai, Bengaluru and Coimbatore and cannot be
physically present to set up a supervisor's phone. Onboarding must be
remote, and it must not involve sharing anything of his.

---

## The model

**One device, one person, one identity.**

| Role | Credential | How the device is set up |
|---|---|---|
| Owner | Email + password, then device-bound PIN | Self, on own phone |
| Manager | Email + password, then device-bound PIN | Self, on own phone |
| Supervisor / staff | PIN only | Owner sends an invite; device binds to that `staff_id` |

### Staff onboarding, remote

1. Owner: Settings → Staff → select member → **Generate invite**
2. App produces a single-use, expiring link or short code
3. Owner sends it over WhatsApp
4. Staff taps it on their own phone — device binds to **that specific
   `staff_id`**, not just the org
5. Staff sets or enters their PIN
6. Thereafter: open app, enter PIN, working

The owner never touches the phone and never shares a credential. The invite
is single-use, expires, and is revocable before use.

---

## Why this also closes the privilege-escalation hole

The earlier plan flagged that `verify_org_pin` checks owner and staff PINs
in one org-wide pool, and that every staff device holds `org_id` — so a
supervisor had one of the two factors needed to authenticate as owner, and
only a 4-digit space in the way.

**Binding the device to `staff_id` removes the premise.** A staff device
knows exactly who it belongs to, so it calls the existing **`staff-login`**
function with `{staff_id, pin}`. It never calls `pin-login`, never searches
the org for a PIN match, and cannot reach the owner pool at all.

`pin-login`'s org-wide pool was solving a problem that does not exist once
onboarding is done properly. Consequences:

- **Use `staff-login` for staff.** It already takes exactly what a
  person-bound device knows and is the already-tested path.
- **`pin-login` becomes owner-only, or is retired.** If owner PIN goes
  device-bound (below), it can be retired entirely.
- **Still add the ambiguity guard to `verify_org_pin`** as defence in depth:
  if a PIN matches more than one row in the org, return `ok = false`. Cheap,
  and protects against any future caller reintroducing the pool.

---

## Owner PIN: device-bound

Since no other person's device can ever mint an owner session, the owner PIN
only needs to protect the owner's own phone. So it should not be a
server-validated credential at all:

1. Owner logs in with email + password
2. Sets a PIN; app stores the Supabase **refresh token** in Android Keystore
   (`flutter_secure_storage`), encrypted with a key derived from the PIN
3. Next launch, the PIN decrypts the token locally and exchanges it for a
   session — no network call validates the PIN
4. 5 wrong attempts **wipes** the stored token and forces email login. Not a
   timed lockout — the PIN protects a local secret, so if someone is
   guessing, the secret goes
5. A new phone always needs email + password once, then a new PIN
6. Always show "Use email instead" as an escape hatch

Nothing to brute-force remotely. Works offline until the refresh token
expires. Biometric unlock can sit alongside it using the same mechanism.

---

## Revocation — the item that matters most with personal phones

When a supervisor leaves, **their personal phone walks out of the business
still holding a valid session.** Deactivating the staff row is not enough:
`staff-login` checks active status at login, but an already-minted JWT stays
valid until it expires.

Required:

- On deactivation, a service-role Edge Function calls
  `admin.auth.admin.signOut(user_id, 'global')`
- Shorter refresh-token lifetime for staff than for owners
- Owner-initiated PIN reset (staff have no email to recover through)
- Owner notified after repeated failed PIN attempts on a staff member

Move this **above** the PIN work in priority. It is a live exposure on every
personal device already in the field.

---

## Also carried forward

- **`listUsers({ perPage: 1000 })`** in both Edge Functions' error paths
  breaks silently past 1000 auth users across all tenants. Query
  `auth.users` by email instead. Not urgent; will be baffling later.
- **Custom SMTP before any registration ships.** Supabase's built-in mailer
  is rate-limited to a handful per hour and is development-only.
  Verification emails will stop on launch day. Resend or SES.
- **Registration does not exist yet.** Owner accounts were seeded by hand.
  This is Item 16 in the master brief.

---

## Build order

1. **Staff session revoke on deactivation** — live exposure, smallest fix
2. **`verify_org_pin` ambiguity guard** — one-line defence in depth
3. **Staff invite flow** (generate, send, bind device to `staff_id`, revoke)
4. **Point staff login at `staff-login`**, retire the `pin-login` staff branch
5. Custom SMTP + Supabase Auth configuration
6. Registration screen + org-creation Edge Function (service role, idempotent)
7. Email verification + deep links
8. Email + password login
9. Owner device-bound PIN with secure storage
10. Forgot password / forgot PIN
11. Trial state, suspended-org message, org picker

Steps 1 to 4 harden what is already live. Steps 5 to 8 are the shippable
registration increment. 9 onward is convenience.

---

## Open decisions

1. **Does `manager` exist as a distinct role in `org_members`?** Managers
   touch pricing and P&L — office-level privilege that deserves email, not a
   field PIN.
2. **Phone OTP alongside email for owners?** Vendors live on WhatsApp and may
   not check email. Fits the market, costs per SMS, adds a dependency.
3. **Self-serve registration or approval-gated?** Self-serve grows faster;
   approval suits IPAMTOA-led adoption where you already know everyone.
4. **PIN keypad digit shuffling — raised and rejected (1 Aug 2026).**
   Randomising key positions per session was floated as a shoulder-surfing
   deterrent, but explicitly not implemented: it fights the muscle memory
   staff build entering a PIN many times a day on `PinLoginPageWidget`
   (`lib/login_page/pin_login_page_widget.dart`), and the actual bug found
   the same day — a 4-wide keypad grid instead of the standard 3-wide
   dialpad layout — was the real usability problem, not the fixed layout
   itself. Left here as a possible future **per-org security setting**
   (opt-in, not a default) if a specific customer ever asks for it —
   nothing to build unless that happens.

---

## Must confirm before building

- `verify_org_pin` source — collision behaviour and pool order
- `lib/backend/device_org_binding.dart` — how the device learns `org_id`
  today; is there any invite path or only manual entry?
- `lib/app_session.dart` — how sessions are held, what `isSupervisorSession`
  keys off
- `org_members.role` values in use
- Whether trial/subscription columns exist on `orgs`
- Supabase Auth settings: email confirmation, SMTP, token lifetimes,
  allowed redirect URLs
