# Wipe recovery — restoring platform admin

**Written 27 Aug 2026, BEFORE the step-4 wipe. Keep this file until the
real orgs are live and Super Admin has been confirmed working.**

## Why this file exists

The wipe deletes `arunpackersandcouriers@gmail.com`'s auth user. Signing
up again produces a **NEW uuid**, and `platform_admins` is keyed on the
old one. Until the row is restored:

- Super Admin is unreachable (`is_platform_admin()` returns false).
- **`delete_org()` refuses to run** — it requires `p_actor` to be a
  platform admin.
- Orgs #2 and #3 cannot be created: the `p_intent = 'create_additional'`
  path is Super-Admin-only by design.

There is **no in-app path** to grant platform admin. It is a direct
table write, and `platform_admins` has **no INSERT policy** — only
`admins_select USING (user_id = auth.uid())` for reads. So restoration
must be done from the **Supabase SQL editor** (postgres/service_role).
An authenticated session cannot do it over PostgREST, by design.

Verified live 27 Aug 2026 before the wipe.

---

## Table shape (verified, not assumed)

`public.platform_admins` — three columns, PK on `user_id`:

| column | type | null | default |
|---|---|---|---|
| `user_id` | uuid | NOT NULL | — (PRIMARY KEY) |
| `note` | text | nullable | none |
| `created_at` | timestamptz | NOT NULL | `now()` |

The pre-wipe row was:

```json
{ "user_id": "26bf3ecd-4524-4c5d-b784-1aa5ca8a75a1",
  "note": null,
  "created_at": "2026-07-26T18:54:47.020839+00:00" }
```

`note` was null and `created_at` defaulted. **Only `user_id` actually
needs supplying.**

---

## Step 1 — find the NEW uuid after re-signup

Sign up through the app first (email + invite code), then:

```sql
select id::text as new_user_id, email, created_at,
       email_confirmed_at is not null as confirmed
from auth.users
where email = 'arunpackersandcouriers@gmail.com';
```

If `confirmed` is false, confirm the email before continuing — an
unconfirmed user can still be granted admin, but the signup flow will
not have finished creating the org.

If this returns **no rows**, the signup did not complete. Do not proceed
to step 2; fix signup first.

---

## Step 2 — restore the platform_admins row

Substitute the uuid from step 1. `ON CONFLICT` makes it safe to re-run.

```sql
insert into platform_admins (user_id, note)
values ('PASTE-NEW-UUID-HERE'::uuid,
        'Restored after the 27 Aug 2026 wipe. Original uuid was '
        '26bf3ecd-4524-4c5d-b784-1aa5ca8a75a1.')
on conflict (user_id) do nothing;
```

Or, avoiding the copy/paste entirely — resolves the uuid by email in one
statement, which is safer:

```sql
insert into platform_admins (user_id, note)
select u.id,
       'Restored after the 27 Aug 2026 wipe. Original uuid was '
       '26bf3ecd-4524-4c5d-b784-1aa5ca8a75a1.'
from auth.users u
where u.email = 'arunpackersandcouriers@gmail.com'
on conflict (user_id) do nothing;
```

**Verify:**

```sql
select pa.user_id::text, pa.note, pa.created_at, u.email
from platform_admins pa join auth.users u on u.id = pa.user_id;
```

Expect exactly one row, with the new uuid and the correct email.

---

## Step 3 — what else references the old uuid?

Checked exhaustively across every table that SURVIVES the wipe
(`delete_org`'s `v_keep` list plus `platform_settings`,
`subscription_plans`, `invite_codes`). Only two places hold it:

### `platform_admins.user_id` — restored in step 2. That is the only one that matters.

### `audit_log.actor` — 17 of 21 rows. **LEAVE THESE ALONE.**

They record what the OLD user did, including the wipe itself. Rewriting
them to the new uuid would falsify history: it would claim a user that
did not exist at the time performed those actions. `audit_log.actor` has
no FK to `auth.users` (verified: **no table in `public` has one**), so a
dangling reference here is expected and harmless.

### Nothing else.

**59 RLS policies call `is_platform_admin()`** — but they call the
*function*, which reads the `platform_admins` table. **None hardcodes a
uuid.** So restoring the one row fixes all 59 at once; no policy needs
editing.

Surviving tables and their row counts pre-wipe: `audit_log` 21,
`subscription_plans` 5, `billing_events` 1, `invite_codes` 1,
`platform_settings` 1. All others in the keep list are empty. The single
`billing_events` row references an org that is being deleted; it is a
platform ledger entry and is not part of admin restoration.

---

## Order of operations — DO NOT GET THIS WRONG

**Delete your own auth user LAST**, after all four orgs are gone.
`delete_org()` checks `platform_admins` for `p_actor`, so deleting
yourself first locks you out of the very function that performs the
wipe — with orgs still present and no admin able to remove them.

Correct order:

1. Run the four `delete_org(...)` calls (dry run, then real).
2. Delete the staff shadow users and Ponci's owner.
3. Delete your own auth user.
4. `validate constraint number_series_prefix_format`.
5. Sign up fresh, then **this file, steps 1 and 2**.
6. Confirm Super Admin opens in the app before creating orgs #2 and #3.

---

## Fallback if you are locked out anyway

Everything here is doable from the Supabase SQL editor, which runs as
`postgres` and is not subject to RLS or to `platform_admins`. As long as
you can reach the SQL editor for project `hqqcapifefsaqvotqvlt`, you can
always re-insert the row. **The lockout is recoverable; it is not
permanent.** What would make it permanent is losing access to the
Supabase dashboard itself.
