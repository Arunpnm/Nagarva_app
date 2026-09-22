# Design — Supervisor field operations (step 2)

**Status:** design only. No migrations, no Dart, nothing run. Responds to
`NG-BRIEF-supervisor-field-operations.md` per the step-1 introspection report and Arun's
review of it (both same session, 2026-08-07). Everything below is grounded in the live
schema/tree as confirmed in step 1 — see that report for the evidence; this file states
conclusions and open decisions, not the investigation again.

---

## 1. State machine

**New column, `orders.job_stage` (text, CHECK-constrained)**, alongside the existing coarse
`orders.status` — the same relationship `supervisor_status` already has to `status` today.
Plain text + CHECK, not a native Postgres enum: every other status-shaped column in this
schema (`status`, `supervisor_status`, `staff.role`, `addons.status`, `org_members.role`) is
plain text, and there's no reason for this one to be the first exception.

**Not every stage gets a dedicated `orders` column.** Only stages with an existing external
consumer keep one — the rest live solely as rows in the extended `order_status_history` (§2).
Adding six more single-purpose timestamp columns to a 120-column table for data the event log
already captures structurally would be exactly the kind of duplication step 1 flagged.

| §2 stage | `orders.job_stage` value | Timestamp source |
|---|---|---|
| assigned | `assigned` | `assigned_at` — **reused**, already written today |
| accepted | `accepted` | `accepted_at` — **reused** |
| departed_base | `departed_base` | net-new, event log only. Odometer start reuses `vehicle_trips.km_start` (already exists, 1:1 with the order per the earlier odometer work) — no new column needed |
| at_pickup | `at_pickup` | net-new, event log only (GPS in the event row) |
| pre_move_documented | `pre_move_documented` | net-new, event log only. **Required gate** — the transition function (§1, brief) refuses `packing` without at least one `pre_existing_damage`-category photo logged against this stage's event row |
| packing | `packing` | net-new, event log only |
| loading | `loading` | `loading_started_at` / `loading_completed_at` — **reused**, already a start+complete pair, good match |
| in_transit | `in_transit` | `transit_started_at` — **reused**. No special multi-day handling needed here — the stage can simply span multiple calendar days; see §6 for why the *wage* side needs day-awareness, not this state machine |
| at_drop | `at_drop` | net-new, event log only (GPS) |
| unloading | `unloading` | `unloading_started_at` — **reused** |
| unpacking | `unpacking` | net-new, event log only |
| job_complete | `job_complete` | `delivered_at` — **reused**, this is what `_verifyAndComplete` already stamps. Odometer end reuses `vehicle_trips.km_end` |
| pending_verification | `pending_verification` | `supervisor_status = 'completed_pending'` — **exact existing match**, no new column |
| verified | `verified` | `supervisor_status = 'approved'` — **exact existing match**. See the call-out below: this currently happens in the same click as settlement and needs splitting |
| settled | `settled` | `closed_at` — **reused** |

**Real gap, flagged rather than papered over**: today, "owner cross-checks and approves" and
"wages posted, order closed" are **one action** — Close Order flips `status→closed` and
`supervisor_status→approved` in the same update, with no wage-entry step in between (Session 1
built Close Order before per-order wages were a decision). §7 wants two distinct steps:
verify (approve chargeable events, enter wages) then settle (reconcile float + cash, close).
This design splits them: a **new** verification screen sets `job_stage='verified'`
(`supervisor_status='approved'`, unchanged) without closing the order; a **retired-and-rebuilt**
settlement action (replacing today's Close Order button, not sitting alongside it — per the
brief's own "must absorb" instruction) sets `job_stage='settled'` and stamps `closed_at`/
`status='closed'` as today. One path to close an order, not two.

**Exception paths.** `on_hold` and `aborted` are `job_stage` values too, not a side flag —
reachable from any active stage. Two new columns:

- `orders.hold_reason_code` (text, CHECK against the brief's §5 list: `customer_not_home`,
  `wrong_address`, `goods_dont_fit`, `customer_cancelled`, `vehicle_breakdown`,
  `damage_occurred`)
- `orders.hold_reason_note` (text, free text)

`on_hold` is resumable — the owner decides the next `job_stage` (could return to where it
was, or move forward/back). `aborted` is terminal. Evidence photo for the hold goes through
the same event-log/photo mechanism as every other stage, not a separate path.

---

## 2. `order_status_history` extension

Current columns (confirmed live): `id, org_id, order_id(text), status, note, changed_at,
changed_by(uuid)`.

**New columns:**

| Column | Type | Purpose |
|---|---|---|
| `job_stage` | text, nullable | The fine-grained value from §1. Existing writers (`TrackingService.logStatus`) keep writing only `status` as today — fully backward compatible. The new field-ops flow populates **both** `status` (coarse) and `job_stage` (fine-grained) on the same row, one write path serving both consumers |
| `device_at` | timestamptz, nullable | Client-captured "moment of action" time. `changed_at` continues to mean server receipt time, unchanged — no rename, nothing existing breaks |
| `latitude`, `longitude` | numeric, nullable | GPS stamp, same names/types as `pod_records` for consistency |
| `photo_refs` | jsonb, not null default `'[]'` | Array of `{category, path, taken_at}` — `category` from the brief's §4.1 nine-value list, `path` is the storage object path (§4), `taken_at` is per-photo device time (a multi-photo event can have photos seconds apart) |
| `metadata` | jsonb, not null default `'{}'` | Stage-specific structured data that doesn't warrant its own column: item counts + variance at unloading, chargeable-event references, `hold_reason_code` duplicate-for-convenience, etc. Matches the jsonb-for-variable-shape convention already used by `field_expenses`/`job_team`/`quote_charges` |
| `customer_visible` | boolean, not null default `false` | See below |

**Device/server divergence** (§6 of the brief: "flag significant divergence... at
verification") is **not** a stored column — compute `changed_at - device_at` at read time in
the verification screen. Storing a derived boolean risks drifting from whatever threshold
Arun eventually picks; computing it at query time means changing the threshold later doesn't
need a backfill.

**Customer visibility — explicit, not implicit, per your instruction.** `customer_visible` is
stamped **at write time** by the app-side logging helper, from a hardcoded allowlist keyed on
`job_stage`, not computed later by the RPC. This matters for history: if the allowlist logic
ever changes, old rows keep the visibility decision that was actually true when they were
written, rather than a policy change silently rewriting what a customer can see on a job from
six months ago.

Proposed allowlist (Arun's to adjust, not mine to finalize):
- **Visible**: `accepted, departed_base, at_pickup, packing, loading, in_transit, at_drop,
  unloading, job_complete, on_hold, aborted` (on_hold/aborted visible because the customer
  needs to know their move stopped — but see below, the reason text is filtered separately)
- **Not visible**: `assigned` (nothing to tell the customer yet), `pre_move_documented` (raises
  "why is someone photographing my damaged furniture" before the customer has heard about a
  claim), `unpacking` (optional, low value, your call), `pending_verification, verified,
  settled` (internal/administrative, happen after the customer's part is done)

**Independent of the flag**: `note`, `metadata`, `photo_refs`, `latitude`/`longitude`,
`device_at` are **never** returned by the customer-facing RPC, regardless of
`customer_visible`. That flag controls whether a stage *milestone* (the label + `changed_at`)
appears on the timeline at all — it does not widen what fields are exposed once it's true.
This is what directly closes your crew-changes/odometer/exception-reasons/internal-notes
concern: those live in columns the customer RPC doesn't select from, full stop, not columns
gated by a flag that a future bug could flip wrong.

---

## 3. Float table — new

`staff_advances` confirmed wrong shape in step 1 (no `order_id`, built for payroll-deduction
loans with `recovery_per_month`). Two new tables:

**`job_expense_floats`** — one row per float issued for a job:
```
id            uuid pk
org_id        uuid
order_id      text          -- not null; per-order, matching the per-order-wages decision
staff_id      uuid          -- the supervisor
issued_amount numeric
issued_at     timestamptz
issued_by     uuid          -- owner who issued it
status        text          -- check: 'open', 'reconciled'
reconciled_amount numeric   -- computed from entries at reconciliation, stored for the record
reconciled_at timestamptz
reconciled_by uuid
notes         text
```

**`job_expense_float_entries`** — spend against a float:
```
id           uuid pk
float_id     uuid fk -> job_expense_floats
org_id       uuid
expense_type text      -- fuel / toll / batta / other, same vocabulary shape as trip_expenses
amount       numeric
spent_at     timestamptz
location     text
receipt_url  text       -- photo of the receipt, same storage bucket as job photos
note         text
created_at   timestamptz
```

Balance owed back = `issued_amount - sum(entries.amount)`, computed at read time; not stored
except as the snapshot in `reconciled_amount` once reconciliation happens.

**Relation to `trip_expenses` and `orders.field_expenses` — this needs a decision, not just a
description.** Three places job-related cost can land today or under this design:

1. `trip_expenses` — trip-scoped (vehicle/multi-order circuit level), pre-existing, stays as-is
   for vehicle-level costs not attributable to one supervisor's float (e.g. fuel for a truck
   doing three deliveries in one run).
2. `orders.field_expenses` (jsonb) — currently what the P&L card reads for ad hoc job costs.
3. `job_expense_float_entries` (new) — supervisor's float spend, order-scoped.

**Recommendation: the new float-entries table supersedes `orders.field_expenses` going
forward.** Once this module ships, supervisors log spend against their float, not into the
`field_expenses` jsonb blob — one source of truth for order-level field costs instead of two.
`trip_expenses` is unaffected; it's answering a different question (vehicle cost, not
supervisor cash). This means `order_pnl_section.dart` needs to read the new table instead of
(or during a transition, in addition to) `field_expenses` — that's a build-step change, not
this design pass, flagged here so step 8 (reporting/P&L reconciliation) doesn't get surprised
by it.

---

## 4. Storage

**Bucket: `job-photos`, private** (not public like `org-logos` — these are photos of a
customer's home and belongings, DPDP-relevant per the brief's own §4.1 note).

**Path convention**: `{org_id}/{order_id}/{category}/{yyyymmddThhmmss}_{6-char-random}.jpg`
e.g. `550e8400-.../NGV-1003/pre_existing_damage/20260807T143022_a1b2c3.jpg`.

Reasoning: `org_id` as the top path segment lets Supabase Storage's own path-prefix RLS
policies enforce org isolation the same way table RLS does (a staff session's storage policy
can check `(storage.foldername(name))[1] = current org`), and makes retention/erasure
(`retention_policies`/`erasure_log`, per §4.1) a single prefix delete — remove everything
under `{org_id}/{order_id}/` when a retention period expires or an erasure request lands,
rather than hunting down scattered rows.

**Photo rows reference storage via `order_status_history.photo_refs`** (§2) — each element's
`path` is the object path above, resolved to a signed/public URL at read time depending on
whatever access pattern the supervisor/owner screens need.

**`pod_records.photo_urls` — decision: superseded, not extended.** It's confirmed always null
today (step 1). Cramming all nine photo categories across the whole job lifecycle into a
single array on a table that's specifically about the *delivery* moment would misrepresent
when/where each photo was taken. `order_status_history.photo_refs` — one array per stage
event — is the correct home for every job photo including the POD ones. `pod_records` keeps
the `photo_urls` column (harmless to leave), but nothing should ever write to it going
forward. Listed as a drop candidate below rather than argued for outright, since dropping a
column already in a generated Dart class is a bigger commitment than just not writing to it.

---

## 5. `supervisor_order_detail()` RPC

```sql
create or replace function public.supervisor_order_detail(p_order_id text)
returns table (
  id text,
  status text,
  job_stage text,
  move_date date,
  packing_date date,
  delivery_date date,
  from_address text,
  from_city text,
  from_floor integer,
  from_has_lift boolean,
  to_address text,
  to_city text,
  to_floor integer,
  to_has_lift boolean,
  vehicle_id uuid,
  vehicle_no text,
  vehicle_type text,
  crew jsonb,              -- [{staff_id, name, role}], joined from job_team + staff
  notes text,              -- "special instructions" — closest existing field, see caveat below
  materials jsonb,         -- from the linked survey's rooms, via the existing SurveyLine/
                            -- parseSurveyRooms utility, not a new parsing mechanism
  customer_name text,      -- PII — null unless unlocked, see condition below
  customer_phone text      -- PII — null unless unlocked
)
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$ ... $function$;
```

**Row-level scoping the function must do itself** (SECURITY DEFINER bypasses table RLS, so
this has to replicate it): return nothing at all — not even the always-visible fields —
unless the caller is the order's assigned supervisor (`job_team` contains
`current_staff_id()`, or `supervisor_id = current_staff_id()`), the org owner
(`is_org_owner()`), or a manager (`is_org_manager()`, **Tier A dependency**, doesn't exist
yet). An order outside the caller's scope isn't "PII-redacted," it's invisible.

**PII condition**: `customer_name`/`customer_phone` null unless
`is_org_owner(org_id) OR is_org_manager(org_id) OR (<today, org-local> >= move_date - 1)`.
Flagging a real correctness risk: "today" must be computed in the org's local date
(`(now() at time zone 'Asia/Kolkata')::date`), not the Postgres session's default timezone —
a plain `current_date` comparison risks the 1-day unlock flipping a few hours early or late
around midnight IST versus UTC. Single-region app today, but worth getting right once rather
than debugging a day-boundary complaint later.

**Caveat, not resolved here**: the brief's §3 says "scheduled date and time slot" — I could
not find a time-of-day column anywhere in the 120-column `orders` dump (only `move_date`,
`packing_date`, `delivery_date`, all `date` type, no time component). Either a time slot lives
somewhere I haven't found, or it doesn't exist yet and needs a new column. Flagging rather
than inventing one.

---

## 6. Wage entry — `order_staff` confirmed sufficient, one addition needed elsewhere

`order_staff` (`order_id, staff_id, salary_amount, is_half_day, team_type, org_id`) **does
cover §7** as suggested in step 1 — no new table. It already supports per-order,
per-person, editable amounts, and `CrewSyncService` already keeps it in sync with `job_team`.

**Default day rates per role — needs a home, doesn't have one.** Recommend `app_settings`
(the existing per-org jsonb config table, already used for document boilerplate) over a new
table: category `'wages'`, keys `day_rate_driver` / `day_rate_helper` / `day_rate_supervisor`.
At verification-screen load, prefill each `order_staff.salary_amount` from the role lookup —
**only when the row is still at its `CrewSyncService`-stamped default**, reusing the exact
"was it edited" comparison `CrewSyncService` already does elsewhere (`untouched = (row.
salaryAmount ?? 0) == defaultRate`) so a manually entered amount is never silently overwritten.

**Multi-day gap, flagged not solved**: `order_staff` holds one flat amount and a single
`is_half_day` boolean per person per order — no day-by-day breakdown. For a 3-day interstate
job with batta/night-halt accruing per day (§5), the owner still has to arrive at one correct
total themselves; the design doesn't force day-granular entry (would complicate the schema
for a case that's currently 0 live orders — see the multi-day attendance finding), but the
**default-prefill** for a multi-day job needs a day-count from somewhere to multiply the base
rate by. Recommend deriving it from `order_status_history` (count of distinct calendar dates
the order held an active `job_stage`) rather than adding a day-count column to `order_staff` —
keeps the wage table simple, treats the event log as the source of truth for "how many days
did this job actually run." Arun's call whether that's precise enough or whether an explicit
day-count column is worth adding later.

---

## Dead columns — candidates for the same migration

Confirmed dead in step 1 (zero Dart references, or in `submitted_at`'s case zero references
**and** zero non-null rows):

- `orders.loading_signature`, `orders.delivery_signature`
- `orders.loading_photos`, `orders.delivery_photos`
- `orders.submitted_at`

Plus one from this design pass, different in kind (not dead today, but the design
deliberately retires it going forward — see §4):

- `pod_records.photo_urls` — leave the column, stop writing to it

Presented as candidates, not a decision — dropping a column already in a generated Dart class
is a bigger commitment than leaving it unused, and that's Arun's call before any migration
touches it.

---

## Open items this design surfaces, not resolved here

1. Time-of-day slot for §3's "scheduled date and time slot" — column not found, need confirms
   whether it exists elsewhere or is net-new (§5).
2. Whether the retired Close Order button becomes the new settlement action, or a genuinely
   new screen replaces it (§1).
3. Whether multi-day wage entry stays a single owner-computed total or gets a day-count column
   (§6).
4. The `customer_visible` allowlist itself (§2) is a proposal, not a final list.

Design back to Arun before any of §1-§6 becomes a migration.
