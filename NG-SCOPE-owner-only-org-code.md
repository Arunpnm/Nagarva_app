# Scope — org code becomes owner-only; staff bind by invite

Decision taken by Arun, 19 Aug 2026. **Nothing built.** This is the plan
and the numbers behind it.

Live figures used throughout, read 19 Aug 2026:

| Fact | Value |
|---|---|
| APC active staff with a PIN | 8 |
| APC owner PINs | 1 |
| PIN pool searched per org-code guess | **9** |
| Invites ever redeemed (all orgs, all time) | 4 |
| Distinct devices that ever redeemed one | **3** |
| Live unused invites right now | **0** |
| Orgs currently locked out | 0 |

Those last three drive the whole migration plan: **the invite path is
barely used.** Almost every device in the field today is org-bound, and
right now there is not a single unused invite for anyone to redeem. A
hard cutover locks out essentially the entire staff base at once.

---

## 4. PIN rate limiting — what is enforced TODAY (do this first)

This is live right now and is worth fixing regardless of the binding
decision, because it is the control that stands between a public org
slug and a 4-digit secret.

### There are two limiters, one per path

**A. `pin-login` → `verify_org_pin()` → `org_pin_attempts`**
(`supabase/20260728_org_pin_login.sql`)

- Table is `org_id primary key`, `failed_attempts`, `locked_until` —
  the counter is **per ORG**, one row for the whole tenant.
- 5 consecutive failures → **15-minute lockout**.
- The lockout is checked *before* any bcrypt compare, so a locked-out
  caller cannot learn anything from response timing. That part is right.
- A PIN collision (a staff PIN equal to the owner's, which the guard
  refuses) is deliberately **not** counted as a failure and does not
  trip the lockout. Also right — the user has done nothing wrong.

**B. `staff-login` → `verify_staff_pin()` → `staff.failed_pin_attempts`
/ `staff.pin_locked_until`** (`supabase/20260725_staff_pin_rate_limit.sql`)

- Counter is **per staff row**. Same policy, 5 → 15 minutes.
- Added 25 Jul 2026. Before that this path had **no lockout at all** —
  a bcrypt compare in an unlimited loop.

### Four gaps, in severity order

**1. The per-org counter is a free tenant-wide denial of service.**
The org slug is public (`resolve_org_by_slug` is anon-callable and the
slug appears in customer-facing links). Five wrong PINs from anyone,
anywhere, locks out **the owner and all 8 staff simultaneously** for 15
minutes — repeatable indefinitely at a cost of 5 HTTP requests per
quarter hour. The lockout punishes the victim, not the attacker. On a
moving day, with crews trying to sign in on site, that is an outage.

**2. The counter resets to 0 when it trips**, so the lockout is not
cumulative:

```
failed_attempts = case when failed_attempts + 1 >= 5 then 0
                       else failed_attempts + 1 end
```

Sustained guessing therefore runs at a steady **5 attempts / 15 min =
480 per day**, forever, with no escalation.

Against the org-code pool that matters more than it looks, because
**each guess is tested against all 9 PINs at once**. Expected guesses to
hit *some* account ≈ 10,000 / 9 ≈ 1,111 → roughly **2.3 days** of
unattended traffic to compromise an account on a tenant whose slug is
public. That is a real number, not a hypothetical.

This is also the strongest technical argument for the decision Arun has
already taken: **owner-only collapses that pool from 9 to 1**, moving
expected time to ~21 days and removing every staff PIN from the
reachable set entirely. The binding change *is* a rate-limiting fix.

**3. Neither limiter has a source dimension.** Both key on the target
(org row / staff row), never on IP or device, so an attacker is never
the one throttled. The codebase already has the pattern to fix this —
`invite_code_rate_limit` counts per IP off the PostgREST
`request.headers` GUC — so no new infrastructure is needed.

**4. No visibility.** Nothing records or surfaces that an org was locked
out, so a sustained attack is invisible to the owner and to us.

### Proposed changes (point 4 only, shippable on its own)

- Add a **per-IP + per-org** counter alongside the per-org one and lock
  the *source* first; only fall back to locking the org if a single org
  is being hit from many IPs. Reuse `invite_code_rate_limit`'s GUC read.
- **Escalating backoff instead of reset-to-zero**: 5 fails → 15 min,
  next 5 → 1 hour, next 5 → 24 hours, decaying after a clean day. Turns
  480 guesses/day into a few dozen.
- Count the **owner pool and the staff pool separately**, so staff
  fat-fingering cannot lock the owner out of their own tenant.
- Write a row on every lockout and surface it to the owner (ties into
  the device register in point 2).

---

## 1. Migration path — nobody gets locked out mid-shift

The constraint is the data above: 3 devices have ever used an invite,
and there are **0 live unused invites**. A flag flip would strand every
staff member in the field.

Three phases, and the enforcement gate is **server-side and per-org**,
never an app version — an old APK in the field must not be able to
bypass it by not being updated.

**Phase A — build the rails, enforce nothing.**
Ship the device register (point 2), bulk invite generation, and the
offboarding flow (point 3). Every existing org-bound staff device keeps
working exactly as today. Nothing a vendor sees changes except new
screens appearing. This phase is where we first learn *who is actually
on what*, which we cannot see today at all.

**Phase B — grace period, visible and dated.**
`verify_org_pin` still searches the staff pool, but returns a
`needs_rebind` flag alongside the session. The app shows a persistent,
non-blocking banner on that device: *"This phone needs to be registered
to you. Ask your owner for a code — this login stops working on
<date>."* The owner's Users page shows every staff member not yet
bound by invite with a one-tap **Send invite code** next to each.

Grace length: **30 days**, and the date is stored per-org so Arun can
extend a specific tenant rather than delaying everyone.

**Phase C — enforce, per-org flag.**
`verify_org_pin` stops iterating the staff pool; Pool 2 disappears and
the function becomes genuinely owner-only, matching what
`device_org_binding.dart`'s comment claimed all along. Flip APC first,
watch it, then tenants.

**Escape hatches that must exist before Phase C:**
- The **owner** can always bind by org code — that path is unchanged and
  is what stops a tenant locking itself out.
- The owner can generate an invite from their own phone, standing next
  to the employee. No desktop, no email round-trip.
- Email/password login remains for the owner as the last resort.
- An owner with no working device can still get in via password reset.

**Open question for Arun:** should a *manager* keep org-code access, or
is the boundary strictly owner? Managers are the people most likely to
onboard crew on site. Strict owner-only is the cleaner rule; manager
inclusion is the kinder one. Not assumed either way.

---

## 2. Device register — what the owner sees

`staff_invites.used_by_device` is written at redemption and never read
again. It is a starting point but **not sufficient**, for a reason worth
being explicit about: it only knows about invite-bound devices.
Org-bound devices never touch the server at bind time at all — binding
is a local `SharedPreferences` write after an anon RPC — so today they
are completely invisible.

**So the register must be written at LOGIN, not at binding.** Every
successful `pin-login` / `staff-login` already mints a session in an
Edge Function; that is the chokepoint.

**New table `device_bindings`:**

| column | purpose |
|---|---|
| `org_id`, `device_id` | composite key |
| `staff_id` | null for an owner device |
| `kind` | `owner` \| `staff` |
| `label` | model/name, editable by the owner |
| `first_seen`, `last_seen` | populated every login |
| `revoked_at`, `revoked_by` | the kill switch |

**Client change required:** the app must send `DeviceOrgBinding.deviceId`
on login. It already generates and persists one, but currently only
sends it to `staff-invite-redeem`.

**What this buys that does not exist today: remote revocation.**
`unbind()` is a local call — it can only be triggered from the device
you are trying to cut off, which is useless for a phone that has left
the building. With the register, both verify functions refuse a revoked
`device_id`, and revoke becomes a real button.

**Owner UI:** Settings → **Devices**. One row per device — person,
label, last seen, and Revoke. Plus the lockout events from point 4, so
"someone is guessing PINs against your company" is visible.

**State the limitation honestly in the UI copy:** `device_id` is
client-generated and not attested. Reinstalling the app yields a new
id, so revoke stops *that install*, not that person. The person-level
boundary is still `staff.active`. The register is an operational tool
and an audit trail — it is not a security boundary, and nobody should
be led to believe it is.

---

## 3. Offboarding — where "this person left" lives

Deactivation is the only real boundary and it works: `staff-deactivate`
sets `active = false` and calls `auth.admin.signOut()`, and every entry
point refuses an inactive row. The failure is that nothing makes it
happen and nothing notices when it does not.

**One explicit action, not four.** Today an owner would have to
deactivate, then somehow deal with devices, invites and open work. Add
**Offboard** on the staff row, behind a confirm that names the
consequences, performing in one server-side step:

1. `staff.active = false` + revoke live sessions (existing function)
2. revoke every `device_bindings` row for that person
3. revoke their unused `staff_invites`
4. surface their open orders/leads/tasks and offer reassignment —
   otherwise branch-scoped rows silently become owner-only and drop off
   every other screen

**Make the product raise it, rather than relying on memory.** The Users
page grows a **Dormant** section: anyone active with no login for 45+
days (`device_bindings.last_seen` makes this computable for the first
time), prompting *"Still working here?"* → Keep / Offboard. That is the
thing that converts a remembered admin step into something the product
asks about on a normal Tuesday.

**Ordering note:** offboarding should ship in Phase A, *before*
enforcement. It is the control that actually closes the re-entry hole;
the binding change narrows the door, deactivation is what locks it.
