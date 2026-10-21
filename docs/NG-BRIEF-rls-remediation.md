# Security brief — RLS remediation (tiered lockdown)

**For:** Claude Code
**Origin:** the `staff` RLS investigation. ~90 tables carry a single `FOR ALL` policy scoped
only to `org_id in (select current_org_ids())`, so any authenticated org member — owner or
lowest-privilege staff alike — can insert, update or delete any row in their org.
**Decision taken:** Option 2 — owner-vs-staff split plus sensitive-table lockdown. Not a full
DB-side mirror of the Dart permission model.
**Sequencing:** lands **before** Accounts depth.

---

## 0. Why this shape, so you don't over- or under-build

The app's permission model (`StaffPermissions.presetFor()`, `canActive()`, `isOwnerOrManagerSession`)
lives entirely in Dart. The anon key ships inside the APK, so anyone who extracts it and holds
a valid staff session can call PostgREST directly and bypass every gate the UI renders. RLS is
the only real control.

Mirroring the full module-level model into RLS would mean maintaining the same rules twice.
They would drift, and a drift bug in RLS locks legitimate users out of their own records —
a worse failure than the current one. So:

- **In scope:** make catastrophic actions impossible — impersonation, self-escalation, free
  plan upgrades, ledger tampering, salary edits, pricing rewrites, audit-trail erasure.
- **Explicitly out of scope:** module-level permissions stay unenforceable at the database. A
  staff member bypassing the app can still touch operational data the UI hides from them. That
  is an accepted trade, not an oversight. Do not try to close it in this pass.

---

## 1. Two mechanisms, not one

RLS filters **rows**. It cannot say "this user may edit their own name but not their own
`role`." That needs **column-level GRANTs**, which operate independently of policies:

```sql
revoke update on staff from authenticated;
grant  update (name, phone, email, address) on staff to authenticated;
```

Both mechanisms are required throughout this brief. Where a rule is about *which rows*, use a
policy; where it is about *which columns*, use a GRANT.

**Critical practical warning — read before writing any GRANT.** PostgREST rejects the entire
request if the client sends a column it lacks UPDATE privilege on, **even when the value is
unchanged**. FlutterFlow-generated update calls frequently send the full row. So a column
GRANT can break working update paths that never intended to touch the restricted field.

Before applying any column GRANT, audit every Dart write to that table and report which ones
send full-row payloads. Those call sites must be narrowed to changed columns first. Treat this
as a blocking prerequisite, not a follow-up.

---

## 2. Phase 0 — same-day hotfix

Two issues are one-statement exploits and should not wait for the full pass. Separate
migration, run first.

### 0a. Staff credential columns

`UPDATE staff SET pin = '0000' WHERE id = <colleague>` grants immediate login as that
colleague. There is no dedicated set-PIN RPC — that plain UPDATE is the intended path, and the
`FOR ALL` policy is the only control. `failed_pin_attempts` and `pin_locked_until` are equally
writable, so the 5-attempt lockout is clearable at will against a 4-digit PIN.

Lock the sensitive columns by GRANT:

```sql
revoke update on staff from authenticated;
grant update (<safe columns only>) on staff to authenticated;
```

Restricted set must include at minimum: `pin`, `pin_hash`, `auth_user_id`, `role`, `active`,
`failed_pin_attempts`, `pin_locked_until`, `salary`, `advance`, `pan`, `bank_account`,
`bank_ifsc`, and the `pf_*` / `esic_*` fields.

Determine the safe list from the live 30-column schema and report it before applying — do not
infer it from this brief.

Then provide the legitimate paths that this removes:

- **`set_staff_pin(p_staff_id uuid, p_new_pin text)`** — SECURITY DEFINER. Permits the call
  only if the caller is the org owner, or is that staff member changing their own PIN. Must
  null the plaintext after hashing (see 0b).
- **Activate / deactivate** — check first whether the existing staff-deactivate Edge Function
  already covers this. Edge Functions use the service role and bypass RLS, so if it does,
  nothing further is needed. Report before building anything new.
- **`verify_staff_pin()`** already runs SECURITY DEFINER, so its writes to
  `failed_pin_attempts` / `pin_locked_until` continue to work. Confirm this rather than assume.

### 0b. Plaintext PINs at rest

The `staff_hash_pin` BEFORE trigger hashes `pin` into `pin_hash` but — unlike
`org_members_hash_pin` — does not null the plaintext back out. Staff PINs are sitting in
cleartext in a table every org member can currently read.

1. Fix the trigger to null `pin` after hashing, mirroring `org_members_hash_pin`.
2. One-time `update staff set pin = null where pin is not null` to clear existing values.

Report how many rows currently hold a non-null `pin` before running the cleanup.

---

## 3. Phase 1 — tiered lockdown

Apply per tier, **one migration per tier**, in the order below. Tier A first is not arbitrary:
it is what makes `staff.role` trustworthy enough for the later tiers to gate on.

Helper functions — extend the pair added in the notifications follow-up, same SECURITY DEFINER
style as `current_org_ids()`:

- `current_staff_id()` — already exists, returns `setof uuid`
- `is_org_owner(p_org_id uuid)` — already exists
- `is_org_manager(p_org_id uuid)` — **new**: true when the caller's `staff.role` is `owner` or
  `manager`, or when `is_org_owner()` is true

Default policy shape for every tier below — per-command, never `FOR ALL`:

```
SELECT  org-scope                                  (unchanged from today)
INSERT  org-scope, or tier-specific restriction
UPDATE  tier-specific
DELETE  tier-specific
```

### Tier A — Credentials & identity
`staff`, `staff_invites`

UPDATE and DELETE owner-only, plus the Phase 0 column GRANTs. `org_members` and
`platform_admins` were confirmed already safe — do not touch them.

### Tier B — Billing & tenancy
`organizations`, `org_subscriptions`, `billing_events`, `platform_invoices`, `org_usage`

`organizations.org_update` currently allows any org member to rewrite `plan_id`,
`plan_status`, `trial_ends_at`, `active`. That is Nagarva's subscription model sitting in a
row anyone can edit.

- Plan and subscription columns: **no app-side write at all.** Revoke via column GRANT; route
  changes through an Edge Function using the service role. Coordinate with the Razorpay
  webhook work, which is the legitimate writer.
- Remaining profile columns (gstin, contact, address): owner-only UPDATE.
- `org_insert` is `WITH CHECK: true` — any authenticated session can create an organisation,
  including one with no membership anywhere. Presumably deliberate for self-serve signup,
  which creates the org before `org_members` exists. Report how the `create-org` Edge Function
  interacts with it and whether the direct-insert path can now be dropped entirely — this ties
  into the long-pending `create-org` hardening step 4.

### Tier C — Financial ledger
`journal_entries`, `journal_lines`, `ledger_entries`, `chart_of_accounts`, `account_groups`,
`account_transfers`, `payment_entries`, `receipts`, `credit_notes`, `vendor_bills`,
`vendor_payments`, `bank_accounts`, `bank_statements`, `bank_statement_lines`,
`salary_payments`, `payroll_runs`, `payslips`, `staff_advances`, `staff_advance_entries`,
`tds_entries`, `transactions`, `gst_returns`

- `journal_entries` and `journal_lines`: **INSERT and SELECT only. No UPDATE policy, no DELETE
  policy at all.** Corrections happen by reversal, per the Accounts brief. This supersedes
  §8's RLS paragraph in `NG-BRIEF-accounts-depth.md` — the immutability guarantee there is
  meaningless without it.
- Payroll and salary tables: owner-only UPDATE/DELETE. A staff member editing a colleague's
  payslip is the sharpest edge here.
- The rest: `is_org_manager()` for UPDATE, owner-only for DELETE.

### Tier D — Pricing & numbering
`rate_cards`, `rate_card_charges`, `rate_card_floor_charges`, `rate_card_multipliers`,
`rate_card_rules`, `pricing_config`, `discount_policies`, `addons`, `number_series`, `settings`

`is_org_manager()` for write. `number_series` and `settings` carry the invoice sequence
counter — tampering there produces duplicate invoice numbers, which is a statutory problem,
not just a data one. Treat those two as owner-only.

While here: `settings` has two redundant legacy policies (`org members read own settings`,
`org members write own settings`) that duplicate `org_isolation` via a direct `org_members`
subquery. Drop them as part of this tier.

### Tier E — Append-only / audit
`audit_log`, `order_status_history`, `document_signatures`, `consent_records`, `erasure_log`,
`breach_incidents`, `sla_events`, `notification_log`

INSERT and SELECT only. **No UPDATE or DELETE policy.** DPDP compliance depends on
`consent_records` and `erasure_log` being tamper-evident, and an audit log a staff member can
edit is not an audit log.

### Tier F — Operational — unchanged
Orders, leads, surveys, materials, trips, tasks, customers, vendors, documents and the rest
keep the existing `FOR ALL` org-scope pattern. Within-org operational data in a small
business; the churn is not justified. **Do not modify these.**

---

## 4. Test gate

The app is the thing being bypassed, so **testing through the app proves nothing.** Every tier
must be verified with direct PostgREST calls using the anon key and a real staff session token,
exactly as an attacker would.

Per tier:

1. As a **staff** session, attempt each newly-forbidden write directly against the REST
   endpoint. Each must return a permission error, not succeed silently.
2. As an **owner** session, confirm every legitimate write still succeeds.
3. Through the **app**, exercise the normal flows for that tier and confirm nothing broke —
   particularly any full-row update payloads flagged in §1.
4. Confirm Edge Functions still work. They use the service role and bypass RLS, so they should
   be unaffected — verify rather than assume.

Specific regression risks to check by name: staff PIN login, staff invite acceptance,
supervisor OTP completion, quote and invoice generation (number series), and the notifications
bell fixed earlier this session.

Report §4.1's results per tier explicitly. A write that still succeeds is the finding that
matters; do not summarise it away.
