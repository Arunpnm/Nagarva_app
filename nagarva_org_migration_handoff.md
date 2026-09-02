# Nagarva — new company setup + safe deletion of the three empty orgs

Repo: `Arunpnm/Nagarva_app` · Supabase project: `hqqcapifefsaqvotqvlt`

## Situation

The owner account currently holds three orgs, all empty (zero orders, leads, staff). The plan
is to create one new company and delete the three old ones.

Deleting first is unsafe. With zero memberships, the next login takes the recovery path in
`vendor_org_resolver.dart`, which prompts for a business name and then reads `invite_code`
from auth metadata to call the `create-org` edge function. Confirmed state:

| check | value |
|---|---|
| `signup_requires_invite` | `true` |
| `invite_code` in owner user metadata | absent |

`create-org` enforces the gate, so the call is rejected: valid account, no org, no route back
in through the app. Two invite codes exist, but the recovery path never prompts for one —
only `SignupPage` does.

## Constraint that determines the order

The new company must be created **on the existing owner account**, not a fresh signup.

Creating it through the real signup flow uses a new email, which is a separate auth user. That
leaves the original account exactly as exposed as before — so it does not make the deletion
safe. Exercising the signup flow end to end is worth doing, but as a separate test, not as the
recovery mechanism.

Use `create_org_with_owner()`, which has no invite gate.

## Do not disable the invite gate

```sql
-- do not run as part of this work
update platform_settings set value = 'false'::jsonb where key = 'signup_requires_invite';
```

The edit is one line and reversible, but while it is set, org creation is open platform-wide on
a live domain. Not needed for this sequence.

## Sequence

### 1. Fix the org picker (do this first)

`lib/components/org_switcher_sheet.dart:57`

```dart
onTap: () => Navigator.of(ctx).pop(isCurrent ? null : org.orgId),
```

The sheet was written as a **switcher** (Settings), where returning `null` for "tapped the org
you're already in" is correct. `resolveActiveOrg` reuses it as a **chooser** at login, where
`null` means *declined* — the loop re-shows it up to 5 times, then signs the user out with
"Choose an organization to continue, or sign in again."

Result: whenever `currentOrgId` is already set as the login picker appears, tapping your own
org does nothing five times, then ejects you.

Fix so both callers keep correct semantics — either pass a mode flag to the sheet, or have
`resolveActiveOrg` treat `null` as "keep current" rather than "declined". Do **not** simply
always return `org.orgId`; that breaks the switcher's no-op case.

This has to land before step 2, because step 2 puts four orgs on the account and makes the
picker appear.

### 2. Create the new company

`create_org_with_owner()` against the existing owner account. Confirm the org exists and the
owner has a membership row.

### 3. Verify access with four orgs

Sign in, confirm the picker appears, confirm selecting the new org enters it, and confirm
selecting the currently-active org no longer ejects after five taps.

Note: single-org accounts skip the picker entirely via path 4, so deleting down to one org
would mask the bug rather than fix it. Verify at four.

### 4. Delete the three old orgs

Only after step 3 passes. They hold no data, so this costs nothing.

## Separate, later

Run the full signup flow end to end (new email, password, invite code, PIN) as its own test.
That is the flow worth exercising — it just must not be the thing the recovery depends on.
