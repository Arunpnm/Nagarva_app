# Claude Code Kickoff — Tier 1.1: Users & Permission Matrix

**Repo:** `Arunpnm/Nagarva_app`
**Stack:** Flutter 3.35.5 (pinned) · Supabase `hqqcapifefsaqvotqvlt`
**Reference specs:** `nagarva_master_parity_brief.md` §2, §3, §4 · `nagarva_part11_erp_completeness.md` §F4
**Human-in-the-loop:** Arunkumar executes all SQL and approves key decisions.

---

## Why this is first

Every other module's visibility, every screen's field-level gating, and the entire drawer/bottom-nav structure depend on the permission model. Building any other screen before this means retrofitting permission checks into it later. This is the cheapest thing to do first and the most expensive to retrofit.

Nagarva currently has no Users module. A tenant owner is therefore the only possible login — they cannot onboard their own manager, supervisor, or field staff. That is a hard blocker for every tenant beyond a solo operator.

---

## STEP 0 — Resolve this before writing any code

Nagarva has **two** tables that could be the login entity, and the relationship between them must be established from the existing code, not assumed:

| Table | Relevant columns |
|---|---|
| `org_members` | `org_id`, `user_id`, `role`, `pin`, `pin_hash` |
| `staff` | `org_id`, `auth_user_id`, `role`, `permissions`, `pin`, `pin_hash`, `failed_pin_attempts`, `pin_locked_until`, `active` |

Supporting: `staff_invites` (code_hash, code_hint, expires_at, used_at, used_by_device, revoked_at), `org_pin_attempts`, `invite_redeem_attempts`, `platform_admins`.

**Read the existing auth code first** — particularly the staff PIN bcrypt Edge Function that mints real Supabase sessions — and report back:

1. Which table represents a login account, and which represents a payroll subject?
2. Is `org_members` for owner/admin Supabase-auth logins, and `staff` for PIN-based field logins?
3. Does a supervisor exist in both tables, and if so what links them?
4. Where does `staff.permissions` (jsonb) currently get read? Is it already enforced anywhere?

**Do not proceed past Step 0 without confirming this with Arun.** Guessing wrong here means rebuilding the whole module.

---

## STEP 1 — The permission model

### 1.1 Permission keys (14 — exact list, do not add or rename)

```dart
const permKeys = [
  ('viewOrders',      'View Orders'),
  ('createOrders',    'Create Orders'),
  ('editOrders',      'Edit Orders'),
  ('deleteOrders',    'Delete Orders'),
  ('assignStaff',     'Assign Staff'),
  ('setSalary',       'Set Staff Salary'),
  ('viewExpenses',    'View Expenses'),
  ('createExpenses',  'Add Expenses'),
  ('deleteExpenses',  'Delete Expenses'),
  ('viewStaff',       'View Staff'),
  ('viewSalary',      'View Salary'),
  ('viewReports',     'View P&L'),
  ('manageleads',     'Manage Leads'),
  ('createQuotation', 'Create Quotations'),
];
```

Note the lowercase `l` in `manageleads` — that is the reference spelling. Keep it consistent rather than "correcting" it, or the permission lookup silently returns false.

### 1.2 Role defaults

| Permission | owner | manager | supervisor | driver / packer / helper |
|---|---|---|---|---|
| viewOrders | bypass | 1 | 1 | — |
| createOrders | bypass | 1 | 1 | — |
| editOrders | bypass | 1 | 1 | — |
| **deleteOrders** | bypass | 1 | **0** | — |
| assignStaff | bypass | 1 | 1 | — |
| **setSalary** | bypass | 1 | **0** | — |
| viewExpenses | bypass | 1 | 1 | — |
| createExpenses | bypass | 1 | 1 | — |
| **deleteExpenses** | bypass | 1 | **0** | — |
| viewStaff | bypass | 1 | 1 | — |
| viewSalary | bypass | 1 | 1 | — |
| **viewReports** | bypass | 1 | **0** | — |
| manageleads | bypass | 1 | 1 | — |
| createQuotation | bypass | 1 | 1 | — |

Field staff roles have an **empty** permission map. They reach their screens through role-specific navigation, not through permissions.

### 1.3 Resolution order — implement exactly

```dart
bool can(AppUser? user, String perm) {
  if (user == null || user.role == 'owner') return true;   // owner bypasses all
  final defaults = defaultPerms[user.role] ?? {};
  final merged = {...defaults, ...(user.permissions ?? {})}; // per-user overrides win
  return merged[perm] == true || merged[perm] == 1;
}
```

Three properties that must hold:
- Owner short-circuits before any lookup
- Role defaults form the base
- Per-user overrides from `staff.permissions` merge on top and win

Put this in a single shared location. Every gate in the app calls it. No screen implements its own check.

---

## STEP 2 — Navigation model

### 2.1 Owner / manager nav (19 entries, in this order)

`dashboard` · `leads` · `surveys` · `inbox` · `survey` · `calendar` · `orders` · `operations` · `reviews` · `payments` · `expenses` · `staff` · `fleet` · `materials` · `accounts` · `pl` · `reports` · `users` · `settings`

Gates per §2.1 of the Master Brief. Two specifics:
- `users` and `settings` → **owner or manager only**
- `staff` label is dynamic: `"Salary & Staff"` with `setSalary`, otherwise `"Team Attendance"`

Modules not yet built (`surveys`, `inbox`, `reviews`, `materials`, `reports`, `calendar`) should appear in the nav model now but route to a "Coming soon" placeholder. Wiring nav once is better than revisiting it six times.

### 2.2 Supervisor nav (5 + staff)

`sup-entry` (Job Entry) · `sup-jobs` (My Jobs) · `sup-team` (My Team) · `sup-sal` (My Earnings) · `sup-att` (My Attendance) · plus `staff` as "Team Attendance"

Home redirect: `sup-jobs`

### 2.3 Field staff nav (2 only)

`my-att` (My Attendance) · `my-sal` (My Earnings)

Home redirect: `my-sal`

### 2.4 Route guard — required

On **role change and every navigation event**: if the target route is not in the current role's allowed nav, redirect to the role's home page.

A supervisor who deep-links to `/pl` must be bounced, not shown an empty screen. Implement in the router, not per-screen.

---

## STEP 3 — Screens to build

### 3.1 Users list

- Rows: name, role badge, phone, last login, active toggle
- Filter by role, search by name/phone
- FAB → Add User
- Gated: owner and manager only

### 3.2 User detail / edit

- Fields: name, phone, email, role, branch, active
- **Permission matrix**: 14 toggles grouped into Orders / Staff & Salary / Expenses / Reports / Leads
- Toggles show the role default state; changing one writes a per-user override to `staff.permissions`
- A `Reset to role defaults` action clears the override map
- Owner role cannot have permissions edited (always all) — render the matrix disabled with an explanatory line

### 3.3 Invite / add user

Use the existing `staff_invites` table (`code_hash`, `code_hint`, `expires_at`, `used_by_device`, `revoked_at`).

- Generate invite code, show once, share via WhatsApp
- Set expiry
- Revoke pending invite
- Show pending invites with their `code_hint`

### 3.4 PIN reset

- Owner/manager resets a user's PIN
- Clears `failed_pin_attempts` and `pin_locked_until`
- Uses the existing bcrypt Edge Function — do not implement hashing client-side

### 3.5 Deactivate

- Soft toggle via `staff.active`
- Deactivated users cannot log in; existing sessions terminate on next request
- Warn if the user is a supervisor currently assigned to open orders

---

## STEP 4 — Enforcement sweep

Once `can()` exists, apply it across screens already built:

| Screen | Gate |
|---|---|
| Order detail — Delete | `deleteOrders` |
| Order detail — Edit | `editOrders` |
| Order detail — P&L card | `viewReports` |
| Order detail — Staff & Salary list | `viewSalary` |
| Order detail — Quick Payment Update | `editOrders` |
| Order detail — Duplicate | `createOrders` |
| Expenses — delete | `deleteExpenses` |
| Salary screens | `viewSalary` / `setSalary` |
| Leads — all | `manageleads` |
| Quote builder | `createQuotation` |

A supervisor opening an order must not see the P&L card or salary figures at all — not greyed, absent.

---

## Constraints

- **Complete file replacements**, not patches (Arun's standing preference)
- All queries scoped through `current_org_ids()`
- `orders.id` is TEXT — `::text` casts on every join
- Dropping a function's return type requires explicit `DROP` before `CREATE OR REPLACE`
- Any write must invalidate through the single fan-out provider, not per-widget refreshes
- No new SQL without Arun executing it — hand him a migration file, don't attempt writes

---

## Acceptance criteria

- [ ] Step 0 answered and confirmed with Arun before code was written
- [ ] `can()` implemented once, shared, with owner short-circuit and override merge
- [ ] All 14 permission keys present with exact spelling
- [ ] Role defaults match the table in §1.2
- [ ] Owner bypasses every check
- [ ] Per-user overrides beat role defaults
- [ ] Field staff resolve to no permissions
- [ ] Three nav sets render correctly per role
- [ ] `staff` label flips between "Salary & Staff" and "Team Attendance"
- [ ] Route guard redirects out-of-scope deep links
- [ ] Users list, detail, invite, PIN reset and deactivate all functional
- [ ] Permission matrix writes overrides and resets to defaults
- [ ] Enforcement sweep applied to all screens in Step 4
- [ ] Supervisor sees no P&L card and no salary figures anywhere
- [ ] Unbuilt modules appear in nav routing to a placeholder
- [ ] Everything scoped through `current_org_ids()`

---

## Report back

1. Answers to the four Step 0 questions
2. Which files were replaced
3. Any place where the existing code already implemented a permission check differently
4. A migration file if any schema change is needed
