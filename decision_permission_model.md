# Decision — Permission Model (supersedes Users Kickoff §1)

**Context:** Step 0 investigation found `lib/permissions.dart` already implements a full permission model, structurally different from the 14-key spec in the kickoff brief.

**Decision: KEEP the existing nested model. Do not replace it. Do not build a parallel system.**

The kickoff's flat 14-key list was copied from APC, a single-tenant React app with 19 modules. It was specified without checking what Nagarva already had. That was an error in the brief, not in the code.

---

## Why the existing model wins

**1. It scales; the flat list does not.**
Nagarva is heading to roughly 47 modules. A flat key list needs one key per module-action pair — 47 modules × 4 actions is 188 hand-maintained constants. The nested `{module: {action: bool}}` shape expresses the same thing structurally and grows without edits to a key list.

**2. APC's flat list is already module × action, just inconsistently flattened.**
`viewOrders / createOrders / editOrders / deleteOrders` is `orders × {view, create, edit, delete}`. `viewExpenses / createExpenses / deleteExpenses` is expenses with edit missing for no reason. `manageleads` and `createQuotation` are coarse single keys with no action breakdown. It is the same model, denormalised and with gaps.

**3. It is already wired.**
`main.dart:427` reads it for nav filtering; `staff_form_sheet.dart` is the editor UI. Replacing means rewriting working code to land in a worse place.

**Conclusion:** APC parity was always about *features* — what the app can do. It was never about internal architecture. Where Nagarva's internals are better, they stay.

---

## Three defects that must be fixed

### Defect 1 — `effective()` is all-or-nothing (permissions.dart:165–172)

Current behaviour: if a staff row has **any** saved permissions, the role preset is discarded entirely. Modules absent from the saved matrix are silently dropped rather than inheriting their role default.

**Real-world consequence:** grant a supervisor one extra permission and they instantly lose every other permission their role had. The failure is silent and looks like a data bug.

**Required behaviour — layered merge, per action, not per module:**

```dart
Map<String, Map<String, bool>> effective(String role, Map? saved) {
  final base = presetFor(role);              // role preset as foundation
  if (saved == null || saved.isEmpty) return base;

  final result = <String, Map<String, bool>>{};
  for (final module in {...base.keys, ...saved.keys}) {
    result[module] = {
      ...?base[module],                       // role default first
      ...?saved[module],                      // saved override wins per action
    };
  }
  return result;
}
```

The merge must be at **action** level. Saving `{"orders": {"delete": true}}` must not wipe `orders.view` — it overrides only `delete`.

### Defect 2 — role vocabulary is inconsistent across three places

| Location | Values |
|---|---|
| `org_members.role` (CHECK constrained) | `owner`, `staff`, `manager` — `manager` never written |
| `staff.role` | `manager`, `supervisor`, `driver`, `helper`, `packer`, `admin` |
| `permissions.dart` `presetFor()` | `admin`, `supervisor`, `driver`, `helper`, `packer` |

Three overlapping vocabularies. `admin` and `owner` appear to mean the same thing; `manager` exists in two schemas and no preset.

**Required — one canonical role list in `permissions.dart`, used everywhere:**

`owner` · `manager` · `supervisor` · `driver` · `packer` · `helper`

- `admin` becomes an alias for `owner` (map it on read; do not migrate data yet)
- `manager` gets a real preset — currently it has none, so any manager falls through to an empty map
- `owner` short-circuits before any lookup and never consults the matrix

Report back what a data migration for `staff.role = 'admin'` would touch before running one.

### Defect 3 — enforcement is nav-only

`StaffPermissions.activeStaffPages` filters which pages appear. Nothing gates an individual button or card. `grep` for `.can` / `.effective` outside `permissions.dart` hits only `staff_form_sheet.dart`.

**Consequence:** a supervisor who reaches an order detail screen sees the P&L card, salary figures, and Delete — every gate in the kickoff's Step 4 is currently unenforced.

Apply Step 4 of the kickoff brief using the **existing** `StaffPermissions.can(module, action)` API, not new flat keys:

| Element | Gate |
|---|---|
| Order — Delete | `can('orders', 'delete')` |
| Order — Edit | `can('orders', 'edit')` |
| Order — P&L card | `can('reports', 'view')` |
| Order — Staff & Salary list | `can('salary', 'view')` |
| Order — Quick Payment Update | `can('orders', 'edit')` |
| Order — Duplicate | `can('orders', 'create')` |
| Expenses — delete | `can('expenses', 'delete')` |
| Salary screens | `can('salary', 'view')` / `can('salary', 'edit')` |
| Leads — all | `can('leads', 'view')` |
| Quote builder | `can('quotations', 'create')` |

Map to whatever the actual module keys are in `presetFor()` — the names above are indicative. **Absent, not greyed:** a supervisor must not see a disabled P&L card, they must see no card.

---

## The "manager" nav gate question — answered

**Check `staff.role`, not `org_members.role`.**

The two tables answer different questions:

- **`org_members`** — "which org does this auth user belong to, and are they the owner?" It is the RLS anchor. Its `role` stays coarse: `owner` vs `staff`. `manager` in its CHECK constraint is forward-compatibility that was never used.
- **`staff`** — "who is this person and what may they do?" This is where real roles and the permission matrix live.

So the kickoff's "users and settings → owner or manager only" resolves to:

```dart
staff.role == 'owner' || staff.role == 'manager'
```

Leave `org_members.role` alone. Do not start writing `manager` into it — that would split the source of truth across two tables and both would drift.

---

## Revised Step 1 acceptance criteria

- [ ] `lib/permissions.dart` retained; no parallel permission system introduced
- [ ] `effective()` merges role preset with saved overrides at **action** level
- [ ] Granting one permission no longer drops the rest
- [ ] Canonical role list: owner / manager / supervisor / driver / packer / helper
- [ ] `admin` aliases to `owner` on read
- [ ] `manager` has a real preset
- [ ] `owner` short-circuits before matrix lookup
- [ ] Nav gates read `staff.role`
- [ ] `org_members.role` untouched
- [ ] Step 4 enforcement applied via `can(module, action)`
- [ ] Supervisor sees no P&L card and no salary figures — absent, not disabled
- [ ] Data migration for `staff.role = 'admin'` reported before execution

---

## Note on the rest of the kickoff

Steps 2 (navigation), 3 (Users screens) and 4 (enforcement sweep) stand as written. Only §1 — the permission model shape — is superseded by this document. The nav structure, route guard, Users list/detail/invite/PIN-reset screens and the enforcement targets are all unchanged.
