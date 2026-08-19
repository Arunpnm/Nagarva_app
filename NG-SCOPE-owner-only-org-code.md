# Scope — org code becomes owner + manager; other staff bind by invite

Decision taken by Arun, 19 Aug 2026. **Nothing built.** This is the plan
and the numbers behind it.

**Scope of the org-code path after this change: owner + managers.** Not
owner-only. Arun, 19 Aug 2026: *"The person onboarding four packers at
6am in a warehouse is the branch manager. A rule that forces me
personally into every onboarding gets worked around by sharing my
password, which is worse than what we're fixing."*

That is the right call and it barely costs anything: the searched pool
goes from 9 to **2 or 3**, not to 1. The security benefit was never
linear in pool size — it came from removing the long tail of packers,
drivers and helpers whose PINs are the ones most likely to be weak,
shared, or still active after someone leaves.

**Implementation note for Phase C:** Pool 2 does not disappear, it
narrows. The filter becomes `s.role in ('admin', 'manager')` — using
the vocabulary `permissions.dart` actually uses, where `'admin'` is the
owner-equivalent role the staff form offers, not a literal `'owner'`
row. `is_org_manager()` already encodes exactly this set
(`role in ('owner','admin','manager')`), so reuse it rather than
writing the list a second time.

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

The binding change is therefore also a rate-limiting fix: restricting
the org-code path to owner + managers collapses that pool from **9 to 2
or 3**, moving expected time from ~2.3 days to roughly a week and, more
importantly, removing the long tail of packer/driver/helper PINs from
the reachable set. But it is not a substitute for the fixes below, and
it ships second.

**3. Neither limiter has a source dimension.** Both key on the target
(org row / staff row), never on IP or device, so an attacker is never
the one throttled. The codebase already has the pattern to fix this —
`invite_code_rate_limit` counts per IP off the PostgREST
`request.headers` GUC — so no new infrastructure is needed.

**4. No visibility.** Nothing records or surfaces that an org was locked
out, so a sustained attack is invisible to the owner and to us.

### BUILT — `supabase/20260819_pin_rate_limit_hardening.sql`

Written and handed over unrun, 19 Aug 2026. Ships on its own, before
any binding work.

- **`pin_ip_attempts` (org_id, client_ip)** is now the primary limiter,
  at **10 failures** per step. Deliberately more forgiving than the old
  per-org 5, because a whole crew on one warehouse hotspot shares a
  public IP — and any single success from that IP clears the bucket,
  which is what makes the shared-NAT case self-healing.
- **Escalating backoff** via one shared `pin_lock_duration(level)`:
  15 min → 1 hour → 24 hours, decaying after a clean 24 hours. Replaces
  reset-to-zero on both the org path and the staff path.
- **`org_pin_attempts` split by pool** (`owner` / `staff`, new composite
  PK) and re-tuned to **50 failures** — a distributed-attack backstop
  only. A packer mistyping five times now trips nothing org-wide, so it
  can no longer lock the owner out. Each pool gets its own lock
  duration; an owner-pool trip must never extend the staff lock.
- **`pin_lockout_events`** records every lockout, readable by owner and
  managers under RLS.

**One finding that would have made this useless.** The GUC pattern from
`invite_code_rate_limit` works there because Dart calls that RPC
directly over PostgREST. `verify_org_pin` is called by the `pin-login`
Edge Function under service_role, so the GUC carries the EDGE
FUNCTION's IP — every vendor would share one bucket and the limiter
would look like it worked while enforcing nothing. So the function
takes `p_client_ip` and the Edge Function must forward it. The
parameter defaults to null, so the migration is safe to run before the
function is redeployed; the exact Edge Function diff is at the bottom
of the migration file.

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
`verify_org_pin`'s Pool 2 stops iterating *all* active staff and
narrows to `role in ('admin','manager')`. Everyone else must be on an
invite-bound device by then. Flip APC first, watch it, then tenants.

**Escape hatches that must exist before Phase C:**
- The **owner** can always bind by org code — that path is unchanged and
  is what stops a tenant locking itself out.
- The owner can generate an invite from their own phone, standing next
  to the employee. No desktop, no email round-trip.
- Email/password login remains for the owner as the last resort.
- An owner with no working device can still get in via password reset.

**Settled 19 Aug 2026: managers keep org-code access.** See the top of
this document for the reasoning. The rule to implement is "owner and
managers may sign in on an org-bound device; everyone else must bind by
invite".

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

**The limitation goes in the UI, not only in this document.** Arun,
19 Aug 2026: *"an owner who thinks it removes the person will make a
bad assumption at exactly the wrong moment."*

`device_id` is client-generated and not attested, so reinstalling the
app yields a new id. Revoke stops *that install*; it does not stop that
person. Required copy, at the point of action rather than buried in
help:

- The confirm dialog reads **"Revoke removes this install"**, and says
  in the body that the person can sign in again on a new install unless
  their account is deactivated.
- That dialog offers **Offboard instead** as a direct action, so the
  owner reaching for the wrong control lands on the right one.
- The Devices screen carries a one-line footer: *"Revoking a device
  signs out that install. To stop someone working entirely, offboard
  them."*

The person-level boundary is still `staff.active`. The register is an
operational tool and an audit trail — it is not a security boundary,
and the interface must not imply otherwise.

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
