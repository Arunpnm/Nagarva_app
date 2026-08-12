# Module brief — Supervisor field operations

**For:** Claude Code
**Scope:** the complete supervisor job lifecycle from assignment to settlement, plus owner
verification, per-order wages, per-order P&L, and the supervisor's own earnings view.
**Size:** this is a module cluster, not a feature. Assign new NG numbers in
`nagarva_module_register.md` and expect several sessions.

> **Introspect before designing.** Several pieces already exist — supervisor OTP completion,
> POD capture, customer signature, attendance auto-marking from order assignment, `order_staff`,
> `trip_expenses`, `staff_advances`, materials `stock_movements`, the Order Details P&L card,
> `addons` and rate cards. **This flow must absorb them, not sit alongside them.** Two ways to
> complete an order is a bug. Report what exists and what it maps to before writing anything.

---

## 0. Decisions already taken — do not revisit

| Decision | Value |
|---|---|
| Staff pay model | **Per-order wages, varying by staff role.** No monthly salary component. |
| Customer PII visibility | Hidden from **everyone except owner and manager**, until **1 day before the booking date**. |
| Connectivity | **Queue writes, cache reads.** Not full offline-first. See §6. |
| Supervisor earnings visibility | Own earnings in full; per-order wages **only for crew on orders he supervised**; own expense float in full. **No org-wide payroll visibility.** |

---

## 1. This module changes the RLS plan — read this first

`NG-BRIEF-rls-remediation.md` puts `orders` and `customers` in **Tier F — unchanged**, keeping
the org-scope `FOR ALL` pattern. The PII rule above is incompatible with that.

Customer name and phone cannot be hidden client-side. The anon key ships in the APK, so any
staff member can query `orders` and `customers` directly and read them regardless of what the
UI renders. **PII gating must be enforced in the database.**

Two viable shapes — evaluate both and recommend one:

- **Restricted view + column revoke.** `revoke select (customer_name, customer_phone, …)` on the
  underlying tables from `authenticated`, and expose a `supervisor_order_view` that returns
  those columns as `null` unless the caller is owner/manager or the booking date is within one
  day. The app reads the view.
- **RPC-only access.** Supervisor screens fetch order data exclusively through a SECURITY
  DEFINER function that applies the same rule.

Either way, `orders` and `customers` move out of Tier F. Flag this to Arun as an amendment to
the RLS brief rather than a silent change.

Same reasoning applies to the earnings scoping in §8 — it is a policy, not a UI filter.

---

## 2. Job lifecycle state machine

Statuses are ordered and the transitions are enforced server-side. A supervisor cannot skip a
stage, and cannot move backwards except through the exception path in §5.

```
assigned
  → accepted            (or declined → back to owner for reassignment)
  → departed_base       odometer_start, crew photo, vehicle photo
  → at_pickup           GPS stamp
  → pre_move_documented pre-existing damage photos  ← REQUIRED GATE
  → packing             packing photos, materials consumed
  → loading             item count at load, loaded photos
  → in_transit          departed pickup
  → at_drop             GPS stamp
  → unloading           item count at unload, variance vs load
  → unpacking           unpacking photos
  → job_complete        odometer_end, crew+vehicle photo, expenses, cash collected,
                        customer signature / OTP  ← absorbs the existing OTP+POD flow
  → pending_verification
  → verified            owner cross-checks, enters wages
  → settled
```

**Scheduling rule.** The shifting date must be today or a future date. A past date is rejected
at acceptance and at any reschedule. Enforce in the database, not just the picker.

**`pre_move_documented` is a required gate and the most valuable step in the flow.** Photographs
of existing damage — the torn sofa, the dented fridge — taken *before* anything is touched, are
what defend a damage claim. Without them every claim is the customer's word against yours. Wire
this to the existing claims module so a claim can pull the pre-move set directly.

---

## 3. What the supervisor sees, and when

**Always visible on an assigned job:** materials list from the survey, pickup and drop addresses
**with floor number and lift availability**, vehicle assigned, crew assigned, scheduled date and
time slot, special instructions.

**Hidden until 1 day before the booking date:** customer name, customer phone, and any other
direct identifier. Enforced per §1.

**Crew display.** Every crew name must render **with the staff member's role** — "Dinesh
(Driver)", "Balaji (Helper)". Two people with the same first name is common and the supervisor
needs to pick correctly. Applies to the crew picker, the assigned-crew list, and the wage entry
screen.

---

## 4. Data captured during the job

### 4.1 Photos

Categories: `pre_existing_damage`, `packing`, `loading`, `crew_departure`, `vehicle_departure`,
`unpacking`, `crew_return`, `vehicle_return`, `pod`.

- **Compress client-side before upload** — longest edge ~1600px, JPEG quality ~80. Roughly
  fifteen photos per order across every tenant is a real storage cost otherwise.
- Store `taken_at` (device) and `uploaded_at` (server) separately — see §6.
- **These are personal data.** Interior shots of a customer's home and belongings fall under
  DPDP. Wire retention to the existing `retention_policies`, and make sure `erasure_log` covers
  photo deletion. Propose a default retention period and ask Arun to confirm it — do not pick
  one silently.

### 4.2 Item counts

Count at load, count at unload, and the variance between them, surfaced to the supervisor at the
drop location **while the vehicle is still there**. A missing item discovered three days later
is a dispute; discovered at the drop it is a search. Compare both against the survey's expected
item list.

### 4.3 Odometer

Reading at departure from base **and** at job completion. Without the closing reading there is
no trip distance, so no fuel reconciliation and no per-km vehicle cost.

### 4.4 Materials consumed

Actual packing material used, recorded against the order, posting through the existing
`stock_movements` path. This is both a stock decrement and a cost line.

### 4.5 Chargeable events

The margin leak. Record at the moment they happen:

- Lift not working / goods carried down N floors
- Waiting time beyond the included allowance (customer not ready)
- Extra packing material beyond the quote
- Extra manpower called in
- Long carry distance from door to vehicle

Each links to an `addons` or rate-card charge so the owner can bill it at verification rather
than absorb it. If the supervisor cannot record these in the moment, they get absorbed silently.

### 4.6 Cash collected

Supervisors routinely take balance payment in cash at the drop. Record amount and time at the
point of collection, mark it as held by that supervisor, and reconcile on handover to the
office. Until then it is your money in someone's pocket with no record.

### 4.7 Expense float

Issue a float to the supervisor before the job (fuel, tolls, batta), record spend against it,
and compute the balance owed back. Use `staff_advances` rather than a new table if the shape
fits — check first. Without this, "expenses" is a number nobody balances against cash issued.

---

## 5. Exception paths

The flow as described only covers success. Each of these needs a way to halt, record a reason
with a photo, and hand back to the owner:

- Customer not home
- Wrong or unreachable address
- Goods do not fit the assigned vehicle
- Customer refuses / cancels at the door
- Vehicle breakdown in transit
- Damage occurred during the move (create a claim directly from here)

Status becomes `on_hold` with a reason code and free text, or `aborted`. The owner decides what
happens next. A job that stops must never be left in an ambiguous state.

**Crew changed on the day.** Planned crew and actual crew are separate fields. Someone doesn't
show, a replacement goes. **Wages and attendance follow actual, never planned.**

**Multi-day and interstate jobs.** Chennai to Bengaluru is an overnight minimum — load day one,
transit day two, unload day three. The state machine must tolerate `in_transit` spanning
multiple calendar days, attendance must mark **every day the crew is engaged**, and driver batta
and night halt accrue per day. Design this in now; retrofitting it is expensive.

---

## 6. Connectivity — queued writes, cached reads

Supervisors work in basements, stairwells, lifts and thick-walled buildings, and interstate runs
cross patchy coverage. If a status update fails for lack of signal the supervisor will not wait
— they will finish the job and backfill from memory, which destroys the timestamps and photos
this module exists to capture.

Full offline-first is not needed. A supervisor's job data is **single-writer** — nobody else
edits that order's field data concurrently — so sync is append-only with no merge conflicts.

Build:

- **Prefetch on acceptance** — order details, materials list, addresses, crew, rate card
  fragments needed for chargeable events. Cached locally.
- **Local outbox** for every field write: status transitions, photos, odometer, counts,
  materials, expenses, cash, chargeable events. Uploads when connectivity returns, in order.
- **Timestamps captured at the moment of action.** Record both the device time and the server
  receipt time on every event.
- **Device clocks are not trustworthy** — they drift and can be changed deliberately. Flag
  significant divergence between device and server time for the owner at verification.
- Visible sync state in the UI: what is queued, what has uploaded, what failed.

Recommend the local store (`drift`, `sqflite`, or a simple serialised queue) with reasoning
before building.

---

## 7. Owner / manager verification and settlement

`pending_verification` → owner reviews everything: photos, counts and variance, odometer,
materials, expenses, chargeable events, cash collected, actual crew, timing.

Then:

- **Approve chargeable events** into billable additions, or waive them.
- **Enter wages per staff member for that order.** Pre-fill from a per-org **default day rate
  per role** (driver / helper / supervisor), editable per order and per person. Hand-typing every
  amount is slow and produces inconsistency; the default makes settlement a review rather than
  data entry.
- **Reject back to the supervisor with a reason** if something is wrong. The flow needs a path
  backwards — currently it only goes forwards.
- Reconcile the expense float and the cash collected.
- Mark `settled`.

Wage rows post to payroll. Per §1 of the RLS brief's Tier C, wage entry is owner-only.

---

## 8. Reporting

**Per order, after settlement:** who went (actual crew, with roles), what was done (event
timeline with photos), materials consumed, expenses, chargeable events billed, wages paid,
revenue, and net profit. Reconcile this against the existing Order Details P&L card — **a
mismatch between the two is a bug in one of them**, and that reconciliation is the best test of
whether this module's cost capture is correct.

**Supervisor's own view:**

- His own earnings in full — per-order wages, history, advances, outstanding balance.
- His own expense float — issued, spent, owed back. He needs this visible at any time or
  reconciliation becomes a surprise.
- Per-order wages **for crew on orders he supervised only.** Enough to confirm his team was
  settled correctly and flag it if not.
- **No org-wide payroll.** No colleagues' advances, no balances for staff he has not worked
  with. Pay disparity between crew members is a common source of friction, and it lands on the
  supervisor because he stands next to them.

Enforce this scoping in RLS, not in the UI.

---

## 9. Attendance calendar

Replace the supervisor's list view with a **month calendar grid** matching the web app: weekday
columns, one cell per date, `P` / `A` marker per day, month navigation arrows, and a
present/absent total beneath. Attendance stays auto-derived from order assignment — extended per
§5 so multi-day jobs mark every engaged day, not just the start.

---

## 10. Open items needing Arun's decision

Do not resolve these unilaterally.

1. **GPS stamping on status transitions.** Proves the supervisor was at the location when they
   marked arrival — the difference between a timestamp and evidence. Weigh against staff-tracking
   sensitivity and DPDP consent. Recommend, but let Arun decide.
2. **Photo retention period.** Propose a default; Arun confirms.
3. **Waiting-time allowance** — how many free minutes before it becomes chargeable.
4. **Whether a supervisor may decline an assignment**, or only the owner may reassign.

---

## 11. Build order

1. Introspection report — what already exists, what it maps to, what conflicts
2. §1 PII gating decision + RLS amendment (blocks everything else)
3. Schema: job events (append-only), photos, item counts, chargeable events, wages, float
4. State machine + server-side transition enforcement
5. Supervisor screens against a live connection
6. Local outbox and prefetch (§6)
7. Owner verification and settlement (§7)
8. Reporting and P&L reconciliation (§8)
9. Attendance calendar (§9)

Steps 1 and 2 come back to Arun before step 3 starts.
