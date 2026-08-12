# Brief — Vendor onboarding & auth flow

**For:** Claude Code
**Why:** 10 signups, near-zero retention. Two causes, both in the front door:
1. Since "Confirm email" was turned on (between 15 Jul and 1 Aug), `create-org` is never
   called for a confirming user — `krish8464@gmail.com` is a real vendor with a confirmed
   account and no org, permanently locked out.
2. A new vendor's first screen asks them to choose Vendor/Staff, then demands an
   **organization code** they do not have.

Fix both in one pass. **The routing fix (§2) is the one that matters — ship it even if the
screen work slips.**

> **Verify before editing.** File names and behaviours below come from session reports, not
> from reading the current tree. Introspect first; where the code disagrees, follow the code
> and say so.

---

## 1. Decisions already taken — do not revisit

| Decision | Value |
|---|---|
| Routing model | **Option B** — the app decides from device state. No binding → vendor email/password. Bound → PIN. |
| Vendor first login | **Email + password.** Not phone/OTP. |
| Vendor subsequent logins | **PIN**, once the device is bound. |
| Staff / supervisor flow | **Unchanged.** Org code, invite code, PIN. It works; don't touch it. |
| Device binding | **Silent**, after first successful vendor login. Never a screen a vendor must complete. |
| Staff entry point | The invite link, which already carries the org. |

---

## 2. The routing fix — highest priority

### 2a. Create the org after email confirmation

`_handleSignup()` calls `auth.signUp()`, gets `session == null` because confirmation is now
required, returns early with "Account created — please confirm your email, then log in", and
**never calls `create-org`**. The user confirms, logs in, and hits "This account is not linked
to any organization." `nav.dart` then bounces them to `/login` because
`AppSession.isAuthenticated` requires a non-null `currentOrgId`. A closed loop.

**Fix in `_handleVendorLogin`:** when the `org_members` lookup returns nothing, do not throw.
Call `create-org` for that authenticated user, then continue into the app.

`create-org` is already idempotent, so this single change:
- completes signup for every user who confirms by email
- recovers every already-orphaned account, including krish, with no data repair
- removes the need for a separate recovery script

Check whether the email-confirmation deep link lands somewhere other than the login handler.
If it does, that path needs the same treatment.

### 2b. The signup form must carry org details through confirmation

The org name (and owner name, §3) are collected at signup but the user may confirm hours
later, on another device, with the app closed. `create-org` needs them at login time.

Report how you'd carry them. Options: `auth.signUp()`'s `data` metadata (survives on the
user record, available after confirmation — likely the cleanest), or re-prompt at first
login if absent. **Do not silently default the org name to the email address.**

### 2c. Distinguish "needs confirmation" from "already registered"

Supabase's anti-enumeration returns 200 with `session == null` for an existing address, which
currently shows "please confirm your email" for an email that will never arrive. Detect and
show "You already have an account — log in instead."

---

## 3. Registration screen

Fields, in order:

1. **Owner name** — new. Currently not captured at all; it's the dashboard greeting and
   appears on documents.
2. **Business name** — the org name.
3. **Email**
4. **Password**
5. **Confirm password** — new. Match validated client-side before submit, inline error on
   mismatch, not a post-submit failure.
6. **Terms & Conditions checkbox** — new, required, button disabled until ticked. Needed for
   the Play Store listing regardless. Link to the hosted terms.

Keep the existing password strength rules if any; report what they are.

---

## 4. Root routing

`nav.dart`'s `_initialize` currently does `DeviceOrgBinding.isBound ? PinLoginPage :
OrgBindingPage`. That second branch is the problem: a brand-new vendor is asked for an
organization code they cannot possibly have.

New shape:

```
DeviceOrgBinding.isBound   → PinLoginPage        (unchanged)
not bound                  → VendorAuthPage      (was OrgBindingPage)
```

**`VendorAuthPage`** — the new fresh-install screen:
- Logo, "Log in" / "Register" toggle or two clear actions
- Email + password
- Registration fields per §3
- One small secondary link at the bottom: **"Joining a team? Use an org or invite code"** →
  the existing `OrgBindingPage`, entirely unchanged

Staff normally arrive via the invite link and never see this screen. The link is the fallback
for a staff member who installed the app manually.

**Do not modify `OrgBindingPage`, `PinLoginPage`, or the invite/redeem flow.** They work.

---

## 5. Silent device binding

After a successful vendor email/password login, bind the device to that org in the background.
No screen, no prompt. Next launch, `isBound` is true and they get the PIN screen.

Two things to resolve and report before building:

- **Does a vendor have a PIN?** Staff PINs live in `staff.pin_hash`; the owner's is on
  `org_members`. Confirm a vendor who has only ever used email/password actually has one — if
  not, either prompt to set a PIN once after first login, or keep email/password for vendors
  until they set one. **Do not bind the device if it would strand the vendor on a PIN screen
  they cannot pass.** This is the single biggest risk in this brief.
- **What does "Switch device" do to the binding**, and does the new flow still reach it?

---

## 6. Not in scope

- Phone/OTP login — considered and rejected for now (DLT registration, per-message cost).
- Any change to staff, supervisor, or field-staff auth.
- The Auth "Confirm email" setting — Arun's call, unchanged here. §2 makes signup work
  whether it is on or off, which is the point.

---

## 7. Report before writing

1. How org name and owner name will survive the confirmation gap (§2b).
2. Whether vendors have a PIN today (§5) — this determines whether silent binding is safe.
3. Whether the email-confirmation deep link bypasses `_handleVendorLogin`.
4. Anything here the code contradicts.

Then build §2 first and confirm it independently — krish's account logging in successfully is
the test. The screen work follows.
