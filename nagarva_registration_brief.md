# Nagarva — registration build brief

31 Jul 2026. SMTP is live and verified. This is the next build.

Read `nagarva_auth_plan_REVISED.md` first for the wider auth model. This
brief covers vendor self-registration only.

---

## Prerequisites — all done, do not redo

- **Custom SMTP is live and tested.** Resend, `smtp.resend.com:465`, user
  `resend`, sender `noreply@nagarva.in` / "Nagarva". A password-recovery
  test landed in Gmail's inbox (not spam) in under two minutes and passed
  the domain's `p=reject` DMARC.
- **DNS verified** — `resend._domainkey` DKIM on root, SPF and MX on
  `send.nagarva.in`. The root SPF still points at `secureserver.net` for
  GoDaddy email and must not be touched.
- **"Allow new users to sign up" is currently OFF** in Supabase Auth. See
  the decision on this below.
- **"Confirm email" is currently OFF.** Turn it ON as part of this build,
  once registration exists.
- Staff invites, session revoke, and the `verify_org_pin` ambiguity guard
  shipped last night. Not device-tested.

---

## Decisions already made

- **Self-serve, not approval-gated.** Two orgs exist today; the problem is
  too few vendors, not too many. Add an approval gate later if junk signups
  appear — it is one status field and one screen.
- **Email only. No phone OTP.** Cost per SMS plus retries, and Indian DLT
  sender/template registration is a multi-day process. Email is free and
  proven working. WhatsApp via AiSensy is the future channel for
  *operational* alerts, not for auth.
- **Owner PIN stays device-bound** (see the revised auth plan). Not part of
  this build.

---

## Screens

### 1. Registration

One screen. Six fields, one checkbox. Resist adding more — GST, branches
and logo come after they are inside.

- Business name → becomes `organizations.name`
- Full name (owner)
- Mobile number
- Email
- Password — min 8 chars, strength indicator, show/hide toggle
- Confirm password — inline mismatch validation before submit. Without
  this, a typo on signup silently creates an account the user can't log
  into, with no signal about why. (This is the "sixth field" the count
  above already implied but the list omitted.)
- Checkbox: accept Terms and Privacy Policy. **Required.** DPDP Act.
  Note: the privacy policy page still does not exist (master brief Item 21).
  Link to it anyway; it is also a Play Store blocker.

Errors to handle explicitly: email already registered (offer login), weak
password, invalid mobile, network failure mid-signup, and password/confirm
mismatch.

**Status of this screen (1 Aug 2026):** `signup_page_widget.dart`'s
create-org wiring is done (calls the Edge Function, gates on
`caller_role == 'owner'` standalone). The screen redesign itself —
owner-name field, confirm-password field, T&C checkbox — is still open.
Deliberately not started yet: owner wants the device test and Supabase's
step 4 (Confirm email / redirect URLs) done first.

### 2. Check your inbox

Resend button with a 60-second cooldown — Supabase enforces
`Minimum interval per user: 60 seconds`, so a faster button silently does
nothing and looks broken.

Handle expired verification links with a clear re-send path.

### 3. First-run setup (after verification)

A vendor landing in an empty app does not come back. Prompt for:

- Business address
- GST number
- At least one branch

Then push them to create their first lead.

---

## Server side

### Order of operations

1. `supabase.auth.signUp()` creates the auth user
2. An Edge Function running as **service role** creates everything else

**The org must not be created client-side.** The client cannot be trusted to
set `org_id` or `role` — if it could, anyone could make themselves owner of
an existing org.

### `create-org` Edge Function

Creates, in one transaction:

- `organizations` row — name, mobile, `plan_status = 'trial'`,
  `trial_ends_at = now() + 7 days`, `active = true`
- `org_members` row — `user_id`, `org_id`, `role = 'owner'`
- `pricing_config` row — seeded from the APC defaults
  (`20260728_pricing_config_survey_seed.sql`)

**Must be idempotent.** If the vendor's connection drops after `signUp()`
and they retry, the result must be one org, not two. Key off `user_id`:
if an `org_members` row already exists for that user, return the existing
org rather than creating another.

Introspect `organizations` before writing this — the generated Dart mirror
shows `plan_id`, `plan_status`, `trial_ends_at`, `active`, but the mirror is
hand-maintained and has been wrong before. There is no `suspended` column;
`active` plus `plan_status` are what exist.

### Supabase settings to change

- **"Allow new users to sign up" → ON.** It was turned off last night
  because signup was reachable with the published anon key while no
  registration flow existed. It must be on for `signUp()` to work.
- **"Confirm email" → ON.** Only after the flow is built and tested.
- **URL Configuration** — add the app's deep link and the site URL to
  allowed redirect URLs, or verification links will fail.

---

## Also required

**Trial expiry enforcement.** The landing page promises a 7-day free trial.
Registration sets `trial_ends_at`; something must check it on login and
decide what day eight looks like — read-only, paywall screen, or grace
period. The super-admin console already has plan-override, so the field
exists; enforcement may not.

**Suspended / inactive org login.** If `active = false`, login must show a
clear message, not drop the user into an empty broken app.

**Deep links.** Verification and password-reset links must open the
installed app, and fall back to a web page if it is not installed.

**Password reset.** Standard Supabase flow. Always show the same
confirmation message whether or not the email exists, so the screen cannot
be used to enumerate registered addresses. After a reset, invalidate stored
PIN tokens on all devices.

---

## Build order

1. Introspect `organizations`, `org_members`, `pricing_config`
2. `create-org` Edge Function (service role, idempotent)
3. Registration screen
4. Turn "Allow new users to sign up" ON; configure redirect URLs
5. Check-your-inbox screen + deep links
6. Turn "Confirm email" ON
7. Email + password login screen — confirm what the Part 7 login screen
   already renders before building a second one
8. Password reset
9. First-run setup prompts
10. Trial expiry + inactive-org handling

Steps 1 to 7 are the shippable increment: a vendor can register and get in.

---

## Standing rules

- Arunkumar executes all SQL manually — hand him migrations, do not assume
  DB access
- Complete file replacements, not patches
- `orders.id` is TEXT (NGV-XXXX), needs `::text` casts in joins
- Changing a function's return type needs explicit `DROP` before
  `CREATE OR REPLACE`
- RLS policies use `in (select current_org_ids())`, not `= any(...)`
- Nothing from the last two sessions is device-tested
