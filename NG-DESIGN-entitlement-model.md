# Entitlement model — design brief

**Status:** design only, nothing implemented. Written after three decisions from Arun (11 Aug 2026):
1. Trial read-only = `create` blocked; `edit`/`delete` allowed. Correct an existing order, fix a phone number — fine. Book a new job — not, until they pay.
2. Asymmetric enforcement, on purpose. Seat cap is server-side (trigger). Feature flags and trial read-only stay client-side for now — a known, accepted gap, not an oversight. Revisit if an enterprise tenant asks.
3. Tier F (`NG-BRIEF-rls-remediation.md`) stays unchanged — no entitlement logic in RLS on operational tables. The seat trigger lives on `staff`, which is already Tier A's table.

Schema check against `hqqcapifefsaqvotqvlt` confirmed `org_id` exists on `orders`, `leads`, `staff`, `quotations`, `org_members` — the columns this design needs are already there. `organizations` uses `name`, not `business_name`, and has no `email` column (noted only because the other Supabase project's equivalent schema differs on exactly these two points — irrelevant to this design, relevant to the consolidation work later).

---

## 1. `subscription_plans` — new `limits`/`features` content

No schema change. Both columns are already `jsonb` and already flow end-to-end into `AppSession.planLimits`/`planFeatures` via `setVendorSession`/`setOrgOnly`/session-restore. This is new *content* for the existing 4 rows (`trial` stays, `starter`→`basic`, `pro` is renamed conceptually to sit at the top, `growth` is new).

**Required data fix, not just a rename:** the live `pro`/`starter`/`trial` rows all carry `max_orders_per_month` (100000 / 300 / 50). That directly contradicts "orders stay unlimited on every tier" — it has to be dropped from `limits` on all four rows, not just raised. Flagging this now so it isn't missed when this gets built — it's a real behavior change (removing a cap), not cosmetic.

```jsonc
// trial — full functional access during the trial window, same as the
// reference web app's own "trial = full access" rule. Recommend NOT
// seat-starving a prospect while they're evaluating; mirror Pro's seat
// cap here rather than Basic's. Arun's call to confirm, not decided here.
{
  "code": "trial",
  "limits":   { "max_staff": -1 },
  "features": { "accounts_gl": true, "gst_returns": true, "payroll": true,
                "multi_branch": true, "eway_bill": true, "storage": true,
                "contracts": true, "api": true }
}

// basic — ₹299
{
  "code": "basic",
  "limits":   { "max_staff": 5 },
  "features": { "accounts_gl": false, "gst_returns": false, "payroll": false,
                "multi_branch": false, "eway_bill": false, "storage": false,
                "contracts": false, "api": false }
}

// growth — ₹599. Seat count is a placeholder — pricing call, not an
// engineering one. 15 sits between Basic's 5 and Pro's unlimited.
{
  "code": "growth",
  "limits":   { "max_staff": 15 },
  "features": { "accounts_gl": true, "gst_returns": true, "payroll": true,
                "multi_branch": false, "eway_bill": false, "storage": false,
                "contracts": false, "api": false }
}

// pro — ₹999
{
  "code": "pro",
  "limits":   { "max_staff": -1 },
  "features": { "accounts_gl": true, "gst_returns": true, "payroll": true,
                "multi_branch": true, "eway_bill": true, "storage": true,
                "contracts": true, "api": true }
}
```

`-1` is the existing "unlimited" sentinel (`AppSession.isOverLimit`/`getLimit` already special-case it) — used instead of a large finite number so "unlimited" reads as unlimited in the data, not as a guess at a ceiling nobody will hit.

**Six of these eight feature keys have nowhere to attach yet.** `accounts` (→`AccountsPage`) and `salary` (→`SalaryPage`, i.e. payroll) are real `PermModule`s today — `gst_returns`, `eway_bill`, `storage`, `contracts`, `api` are not. `eway_bills`/`storage_jobs`/`warehouses`/`contracts` exist as live tables with zero Dart pages, and GST-return-filing and API access aren't page-shaped at all. Storing the flags now is free and forward-compatible; enforcing them needs the page/module to exist first (§3), or — for `multi_branch` and `api`, which are capabilities rather than pages — a direct `planFeatures[...]` check wherever that specific capability is exercised (e.g. wherever "add a branch" UI eventually lives), not the generic module mechanism below.

---

## 2. Seat cap — `BEFORE INSERT` trigger on `staff`

The only piece of this getting real server-side enforcement, per Arun's decision. Today `users_page_widget.dart`'s `_addStaff()` checks `AppSession.isOverLimit('max_users', count)` client-side only, and Tier A leaves `staff` INSERT at org-scope for any org member — nothing stops a raw PostgREST insert past the cap. A trigger is the right shape rather than a wrapper RPC, because it catches every insert path including ones that don't exist yet (the same reasoning `staff_hash_pin` already uses for its own guarantee).

```sql
-- Design sketch — NOT for this pass. Lands as its own addition when Arun
-- says build, most likely appended to supabase/20260808_tierA_staff_credentials_rls.sql
-- (staff is already that migration's table) rather than a new file, but
-- that's a build-time call, not decided here.
create or replace function public.enforce_staff_seat_cap()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  v_cap integer;
  v_count integer;
begin
  select coalesce((sp.limits->>'max_staff')::int, -1)
    into v_cap
  from public.organizations o
  join public.subscription_plans sp on sp.id = o.plan_id
  where o.id = new.org_id;

  if v_cap = -1 then
    return new; -- unlimited
  end if;

  select count(*) into v_count
  from public.staff
  where org_id = new.org_id;

  if v_count >= v_cap then
    raise exception 'Staff seat limit reached for this plan (% of %)', v_count, v_cap
      using errcode = 'P0001';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_staff_seat_cap on public.staff;
create trigger trg_staff_seat_cap
  before insert on public.staff
  for each row
  execute function public.enforce_staff_seat_cap();
```

Notes for whoever builds this:
- Counts **all** staff rows (active + inactive), matching the existing client-side check's own reasoning in `users_page_widget.dart` — an inactive row still occupies a seat until the org upgrades or the row is actually gone.
- `v_cap = -1` (missing key resolves to `-1` via `coalesce`) short-circuits before the count query — Pro/trial never pay the extra read.
- The client-side `isOverLimit` check in `_addStaff()` stays too, for the instant "upgrade to add more staff" message instead of a round-trip Postgres error. The trigger is the real boundary; the Dart check is UX.
- `P0001` with a plain message, same convention `create_org_with_owner()` already uses for its own "no default trial plan" error — surfaces as a normal PostgREST error the existing try/catch in `_addStaff`/`StaffFormSheet` already handles.

---

## 3. Feature-flag gate — where it ANDs into `canActive()`

`permissions.dart`'s `StaffPermissions.canActive(moduleKey, action)` is the one call site every module-visibility check in the app already goes through. The plan-feature check adds a new condition **before** the existing owner bypass — an owner on Basic still doesn't see Payroll; the module doesn't exist for their plan, it isn't that they lack permission for it.

```dart
// permissions.dart — design sketch, not implemented.

// Modules exempt from plan-tier gating entirely — daily workflow and
// anything a vendor's customer sees. Never consult planFeatures for these.
const kAlwaysUnlimitedModules = <String>{
  'leads', 'surveys', 'survey_quote', 'quotations', 'orders', 'lr_register',
  // invoices/receipts are actions inside 'orders' (Generate Invoice etc.),
  // not their own PermModule — already covered by 'orders' being exempt.
};

// Module key -> the subscription_plans.features flag that gates it.
// Only modules with a real plan-tier restriction appear here; everything
// else (dashboard, operations, settings, fleet, materials, ...) is
// ungated by plan, same as today.
const kModuleFeatureFlag = <String, String>{
  'accounts': 'accounts_gl',
  'salary': 'payroll',
  // 'reports' deliberately NOT mapped to gst_returns — Reports today is
  // general P&L/volume reporting, not GST-return filing specifically.
  // gst_returns has no page to attach to yet (§1) — add the mapping when
  // that page exists, don't force it onto an unrelated module now.
};

static bool canActive(String moduleKey, String action) {
  if (action == 'create' && !AppSession.instance.orgWritesAllowed) {
    return false; // §4 — trial-expired-unpaid: no new records, any role.
  }
  if (!kAlwaysUnlimitedModules.contains(moduleKey)) {
    final flag = kModuleFeatureFlag[moduleKey];
    if (flag != null && !AppSession.instance.hasFeature(flag)) {
      return false; // plan doesn't include this module — role is irrelevant.
    }
  }
  if (AppSession.instance.currentStaffId == null) return true; // owner bypass, unchanged
  return can(activePerms ?? const {}, moduleKey, action);
}
```

`hasFeature()` already exists on `AppSession` (`planFeatures[key] == true`) — no new plumbing needed there, just the two new lookup tables and the two new conditions ahead of the existing logic. `allowedPageNames()` (drives the sidebar) reads through `canActive`-equivalent logic too, so a plan-gated module drops out of nav automatically once this lands — no separate nav-filtering change needed.

---

## 4. `orgWritesAllowed` — the trial-read-only gate

New getter on `AppSession`, sibling to the existing `isTrialExpired`:

```dart
// app_session.dart — design sketch, not implemented.

/// True once the org may create new records — paid, or still inside the
/// trial window. False only for a trial that has run out and never
/// upgraded (plan_status stays 'trial' — see isTrialExpired's own
/// comment on why an upgraded org is never caught by this).
bool get orgWritesAllowed => !isTrialExpired;
```

Trivial by construction — it's just `isTrialExpired`'s inverse, kept as its own named getter because `canActive` reads more clearly as "writes allowed" than "not trial expired," and because the two getters answer different questions even though one is currently the other's negation (`isTrialExpired` also drives messaging/UI copy independently of the create-gate).

**Required change when this ships, not just an addition:** `main.dart`'s `_buildLockScreen`, triggered by `isTrialExpired`, is today's *hard* paywall — full lock, nothing usable. That has to be retired for the trial-expiry case specifically, or every expired-trial org keeps hitting the old hard lock regardless of this new read-only gate, contradicting the decision it exists to implement. `isSuspended` (platform-admin suspension via `organizations.active`) is unrelated and must keep its hard lock exactly as-is — a suspended tenant is a deliberate platform action, not an unpaid trial, and stays fully locked out.

**Scope of the block, precisely:** only `action == 'create'` is affected, per decision #1. `view`/`edit`/`delete` are untouched by this gate — an expired-trial owner can still open, correct, and even delete an existing order; they just can't hit "New Order." This means `canActive` is the only choke point that needs the new condition — the concept doesn't need a separate "read-only mode" flag threaded through the UI, since every create action in the app already asks `canActive(module, 'create')` (directly, or via the owner-bypass path this same function short-circuits today).

**What this does *not* cover, on purpose (decision #2/#3):** none of this is enforced at the database. An expired-trial org's client, or a bypassing raw PostgREST call, could still insert an order directly — `Tier F` stays untouched, no RLS change. This is the accepted asymmetry: seats get the hard boundary because they're the revenue lever worth defending; trial-expiry and plan features are conversion/UX mechanisms, not security boundaries, and get the cheaper client-side implementation until real money says otherwise.
