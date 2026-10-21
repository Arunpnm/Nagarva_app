# PART 7 — LOGIN SCREEN: exact port from the React app

Append this to the parity brief. Reference source: `reference/apc_web_App.jsx`,
`LoginScreen` at line ~1341, `OWNER_PIN` at line 255, staff lookup at line 1351,
staff PIN management at lines ~6515–6620.

## The screen — match it exactly

Port `LoginScreen` faithfully. Every visible and interactive detail below comes
from the React source and must be reproduced:

- **Four separate single-digit boxes**, not one text field. 58×66px, 12px
  radius, centred text at 26px weight 700, JetBrains Mono.
- `type=password`, `inputMode=numeric`, `maxLength=1` per box.
- Border is `T.border` when empty, `T.accent` when filled, 2px, with a 0.15s
  colour transition.
- **Auto-advance**: entering a digit moves focus to the next box.
- **Backspace on an empty box** moves focus back and clears the previous digit.
- **Auto-submit** the moment all four digits are entered — no submit button.
- **On-screen numpad** below the boxes, including a `⌫` key. `⌫` clears the last
  filled digit and returns focus there. Number keys fill the first empty box.
- **Shake animation on wrong PIN**, boxes cleared, error text
  "Wrong PIN. Try again."
- Subtitle: "Enter your 4-digit PIN".
- Busy state while checking.

Same layout, same spacing, same behaviour. A user moving between the web app and
Nagarva should not notice a difference.

## No email, no password, no phone entry

The login screen asks for four digits and nothing else. There is no vendor
email/password step in front of it, and no phone number field. Owner and staff
use the same screen — each types their own PIN.

## Org scoping — the one implementation difference

The React app is single-tenant, so `.eq("pin", p)` against the whole staff table
is unambiguous. Nagarva is multi-tenant, so the same query would match a PIN
belonging to a different vendor. The PIN must therefore be resolved **within one
org**, and the org comes from the device, not from the user's input:

- On first launch (or via a vendor-specific link such as `nagarva.in/apc`), the
  device is bound to one org and stores that org id locally.
- Thereafter the login screen shows only the four PIN boxes. The org is already
  known; the user never sees or types it.
- If no org is bound yet, show a one-time org selection / vendor-code entry
  before the PIN screen, then never again on that device. Provide a way to
  re-bind (e.g. long-press the logo, or a link under the numpad) for a device
  that changes hands.

This is invisible after first setup. The everyday experience is identical to the
web app: open app, type four digits, in.

## Credential storage

Owner and staff PINs both verify through the existing `staff-login` Edge
Function against `pin_hash` (bcrypt), with the 5-attempt / 15-minute lockout from
`20260725_staff_pin_rate_limit.sql`. Do NOT:

- hardcode an owner PIN in the client as `OWNER_PIN = "1991"` (line 255)
- query `.eq("pin", p)` against a plaintext column (line 1351)
- render PINs in plaintext in the user management table (lines 6567, 6593)

The owner's own PIN keeps whatever value he sets — including 1991 — it is simply
stored hashed and checked server-side rather than compared against a string in
the JS bundle.

## Staff/user management

Port the Add/Edit user sheet from lines ~6515–6620: name, phone, role, branch,
4-digit PIN, with the "PIN must be exactly 4 digits" validation. The PIN field
is write-only — setting a new PIN works, but existing PINs are never read back
for display (Nagarva already fixed `staff_form_sheet.dart` for this; keep it
that way).

## Verify

- Fresh device: org binding prompt appears once, then the PIN screen.
- Owner PIN logs in as owner with full access.
- Staff PIN logs in as that staff member, sidebar filtered by the permission
  matrix.
- Wrong PIN shakes, clears, shows the error, increments `failed_pin_attempts`.
- Five wrong PINs produce the lockout message with a retry time.
- A PIN belonging to a staff member of a different org does NOT log in.
