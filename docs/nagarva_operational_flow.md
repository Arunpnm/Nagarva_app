# Nagarva — Operational Flow Specification

Companion to `nagarva_master_build_brief.md`. This document defines **how the business actually runs**, as described by the owner. Where the brief lists features, this defines the flow they must serve. Where the two disagree, this wins.

---

## Part 1 — The lead-to-completion flow

### 1.1 Lead stage

```
Create lead → follow-up (repeatable) → [survey] → quote → follow-up (repeatable)
     → confirmed → ORDER
     → not confirmed → revised quote → still no → LOST
```

- **Lead created** manually, from the public enquiry link (Item 13), or from a referral/marketing source.
- **Follow-ups are repeatable at every stage** — not a single "next date" field. Each follow-up logs channel, outcome, notes, and optionally chains the next reminder (Item 10).
- **Survey is optional.** Two valid paths to a quote:
  - **With survey:** physical or customer-self survey → CFT items captured → quote generated from CFT + slabs.
  - **Without survey:** direct quote (small moves, repeat customers, phone estimates). The flow must not force a survey.
- **Quote → follow-up → outcome:**
  - *Accepted* → converts to **Order**.
  - *Not accepted* → **revised quote** (see 1.2) → follow-up again.
  - *Still declined* → **Lost**, with a mandatory reason (price / timing / competitor / no response / postponed).

### 1.2 Quote revisions — versioning, not overwriting

A revised quote must be a **new version**, not an edit of the old one.

- `quotations` gets `version int` and `parent_quote_id`, or a `quote_revisions` child table.
- Every version keeps its own items, charges, totals, and sent/viewed timestamps.
- The customer's public link always resolves to the **latest** version; older versions stay visible internally.
- Why: a customer holding the first PDF and quoting a number back must be answerable. Overwriting destroys that.
- Revision reason captured (discount given / scope changed / customer negotiated) — over time this tells the vendor where their pricing is soft.

### 1.3 Lost leads → remarketing pool

- Lost leads are **not deleted** — they move to a `lost` status with a reason and stay queryable.
- **Remarketing list:** filter lost + past customers by city, date, service type → send promotional WhatsApp campaigns (festival offers, seasonal discounts).
- `postponed` deserves its own treatment: capture the *expected future date* and auto-create a reminder for a month before it. A postponed move is the highest-converting lead a mover has.
- Respect opt-out — a `marketing_opt_out` flag per customer, honoured across all campaigns (DPDP relevant).

### 1.4 Order stage

```
ORDER confirmed → supervisor assigned → notify supervisor + customer (team assigned)
   → supervisor reaches customer location on scheduled date
   → executes job → marks complete with photos → LOCKED
```

- **On confirmation:** advance payment captured (if any), order number issued (NGV-XXXX), scheduled date locked in.
- **Supervisor assignment** triggers notification to:
  - the **supervisor** (job details, address, customer contact, scheduled date), and
  - the **customer** (team assigned, supervisor name and phone, expected arrival) — this is a trust moment; a customer who knows who's coming is a customer who doesn't call three times.
- **Documents generated from a confirmed order:**
  | Document | When | Notes |
  |---|---|---|
  | **LR / Consignment Note** | On dispatch | Legally required (Item 22), sequential per org/FY |
  | **PL — Packing List** | At loading | Item-wise list of goods with counts; customer signs |
  | **Loading Slip** | At loading | Materials used + vehicle + crew; internal record |
  | **Money Receipt** | On any payment | Sequential numbering, per org/FY |
  | **Invoice (GST)** | On completion/billing | Existing SAC 996719 logic |
  | **POD** | At delivery | Signature + condition confirmation (Item 15) |

- **Completion:** supervisor marks complete, attaching **packing (loading) photos and unpacking (delivery) photos** (Item 14). Completion without photos should be blocked, or at minimum require an explicit override reason — the photos are the whole dispute defence.
- **Lock on completion:** once marked complete, the supervisor **loses edit access** to that order.

### 1.5 Unlock path (gap — must be designed)

"Cannot edit after complete" is correct, but genuine mistakes happen — wrong staff ticked, diesel amount mistyped, a photo missed.

- Supervisor can raise an **edit request** with a reason.
- **Owner or Manager approves**, which reopens the order for a limited window (e.g. 24h) or lets the manager edit directly.
- Every unlock and subsequent change writes to `audit_log` (already created in the 28 Jul migration).
- Without this, the only workaround is giving supervisors permanent edit rights — which defeats the lock entirely.

---

## Part 2 — Supervisor view and access model

The supervisor app is deliberately narrow. Everything below is **default** behaviour, overridable by the vendor through RBAC (Part 5).

### 2.1 What a supervisor can see

- **Completed orders — only their own**, with the full record of who worked on each.
- **Future assigned orders** — visible but **read-only** before the shifting date.
- Not visible: other supervisors' jobs, customer pricing beyond what's needed, leads, quotes, P&L, other staff's salary.

### 2.2 What unlocks on the shifting date

On the scheduled date, the supervisor gains edit access to that order to record:

1. **Staff attendance** — which labour actually came with him (drives attendance and salary — see 2.3).
2. **Vehicle selection** — which vehicle was used.
3. **Expenses** — diesel, packing material, addon services, toll, food/bata, parking, loading charges, and other.
4. **Photos** — loading and unloading.
5. **Completion** — with customer signature/OTP.

**Gap — multi-day and interstate jobs.** A Chennai→Delhi move loads on day 1 and delivers on day 4. "Access only on the shifting date" breaks this.

**Fix:** the access window runs from the **scheduled start date** until **completion + a grace period** (default 48h, configurable). For multi-day jobs, capture `load_date` and `delivery_date` separately; access spans both.

Also handle:
- **Job starts late at night / crosses midnight** — window should be date-range based, not a single calendar date.
- **Reassignment** — if a supervisor changes mid-job, the outgoing one's access closes and the incoming one inherits, with both recorded.

### 2.3 Attendance is derived, not double-entered

Marking staff on a job **is** the attendance record for that day. Do not make anyone enter attendance separately — the existing auto-attendance logic from PackNPay applies here.

- One staff member on two jobs the same day should not double-count as two days' wages — define the rule (per-day wage regardless of job count, or per-job rate) per org in Settings.
- Absent/leave marking stays with the manager, not the supervisor.

### 2.4 Salary, credit/debit, and calendar (supervisor's own view)

- **Staff salary balance** for the crew he supervises — what's earned, what's advanced, what's payable.
- **Credit and debit ledger:** wages earned (credit), advances taken, deductions, fines (debit), settlements paid.
- **Calendar view:** days worked in the month, per staff member, tying back to attendance in 2.3.
- **Gap to decide:** should a supervisor see *other* staff's salary at all, or only his own plus a headcount? This is a common vendor sensitivity — default to **his own salary in full, crew members' days-worked only** (no amounts), and let RBAC open it up if the vendor wants.

### 2.5 Cash imprest (gap)

Supervisors carry cash for diesel, toll, and food. Without tracking, every job settlement is a WhatsApp argument.

- **Advance issued** to supervisor before job (cash/UPI), recorded.
- Expenses logged against that advance during the job.
- **Settlement on completion:** advance − expenses = returned or reimbursed, with the balance visible to both sides.
- Running imprest balance per supervisor.

---

## Part 3 — Materials / stock management (Item 6 in owner's list)

Track **which materials were used on which order**, so consumption is attributable and stock stays accurate.

### 3.1 Stock model

- **`materials`** master: name (carton, bubble wrap, stretch film, tape, wooden crate, blanket), unit (nos/roll/kg/metre), current stock, reorder level, unit cost, per branch.
- **`material_transactions`**: `type` (`purchase` | `issue` | `consume` | `return` | `damage` | `transfer`), quantity, order_id (for issue/consume/return), branch, staff, timestamp, cost.

### 3.2 The issue → consume → return cycle

This is the part that's usually got wrong:

1. **Issue** — materials taken from stock for a job (may exceed what's needed; supervisors carry spare).
2. **Consume** — what was actually used, recorded by the supervisor at completion.
3. **Return** — unused material goes back to stock. **Without this step stock drains to zero on paper while cartons sit in the warehouse.**
4. **Damage/loss** — written off explicitly, not silently absorbed.

Reconciliation: `issued − consumed − returned = shortage`, flagged for review.

### 3.3 Reporting

- **Material cost per order** → feeds job costing (Part 6) and P&L.
- **Consumption vs quoted** — if the quote priced 20 cartons and 32 were used, that's margin leaking; surface it.
- **Low stock alerts** at reorder level, per branch.
- **Purchase entries** with supplier and cost, feeding expenses.
- Branch-to-branch transfers with in-transit state (ties to Item 28).

---

## Part 4 — Vehicle tracking: diesel, km, mileage, service (Item 7 in owner's list)

### 4.1 Two separate logs — this is the core of the design

Mileage and daily utilisation are **different measurements** and must not be forced into one entry.

**Log A — `fuel_entries` (one row per filling, whenever it happens):**

| Field | Notes |
|---|---|
| `vehicle_id` | |
| `filled_at` | timestamp |
| `odometer_at_fill` | **km reading at the moment of filling** — mandatory |
| `litres` | **mandatory** — mileage cannot be derived from rupees |
| `amount` | |
| `rate_per_litre` | auto-computed = amount ÷ litres; catches typos |
| `is_full_tank` | boolean, default true — tank-to-tank maths requires it |
| `filled_by` | staff/supervisor |
| `pump_name`, `location` | optional |
| `odometer_photo` | photo of the meter — prevents the most common fudge |
| `bill_photo` | optional |
| `order_id` / `trip_id` | if attributable to a job |

**Log B — `daily_vehicle_log` (one row per vehicle per day, driver-entered twice):**

| Field | Notes |
|---|---|
| `vehicle_id`, `log_date` | |
| `opening_km` | **entered by the driver in the morning** before starting |
| `opening_at` | timestamp of that entry |
| `closing_km` | **entered when he reaches back** to the office/room at end of day |
| `closing_at` | timestamp |
| `km_run` | computed = closing − opening |
| `driver_id`, `order_ids[]` | jobs run that day |
| `opening_photo`, `closing_photo` | odometer photos on both entries |

Both readings are typed by the driver, not carried over automatically. That's deliberate — it makes each entry an independent observation rather than an assumption, and it produces the check in 4.3.

**Day starts open, ends closed.** The morning entry opens the day; the evening entry closes it. An open day with no closing reading by a cutoff time (configurable, e.g. 11pm) is flagged to the manager — that's a driver who hasn't reported back.

### 4.2 How mileage is actually computed (tank-to-tank)

Mileage is calculated **between two consecutive full-tank fills**, not per day and not per fill in isolation:

```
mileage (km/l) = (odometer_at_fill[current] − odometer_at_fill[previous])
                 ÷ litres[current]
```

Worked example:

| Fill | Odometer | Litres | Computed |
|---|---|---|---|
| 1 Aug | 45,200 | 60 L | — (baseline) |
| 8 Aug | 45,680 | 62 L | 480 km ÷ 62 = **7.74 km/l** |
| 15 Aug | 46,150 | 58 L | 470 km ÷ 58 = **8.10 km/l** |

Rules that make this reliable:

- **The first fill is a baseline only** — no mileage until the second fill. Show "baseline recorded," not a wrong number.
- **Partial fills** (`is_full_tank = false`) don't close a mileage cycle. Carry the litres forward and compute across to the next full tank.
- **Rolling average** per vehicle over the last 5 fills is the number to display — single-fill figures swing on driving conditions and are misleading.
- **Flag anomalies:** a fill where odometer went *backwards*, litres exceed tank capacity, or mileage deviates more than ~25% from the rolling average. Each is either a data-entry error or something worth a conversation.

### 4.3 Why both logs, not one

- **Fuel entries** give mileage and fuel cost — irregular, whenever the tank is filled.
- **Daily closing reading** gives utilisation, idle days, and service-due tracking — regular, every day, even on days with no fill.

Filling and end-of-day are different moments, and a truck often runs three days on one tank. Merging them would either force a fake fuel entry daily or lose the daily km.

**Cross-check 1 — the overnight gap.** Because the morning reading is entered independently rather than carried forward, compare it against **yesterday's closing**:

- **Equal** → normal. Vehicle sat overnight as expected.
- **Higher** → the vehicle moved after being logged in. Could be legitimate (a late trip, moved to the yard, driver took it home) or not. Show the difference to the manager rather than absorbing it silently — this is the single most useful number this design produces, and auto-filling the morning reading would destroy it.
- **Lower** → data-entry error, or the odometer was tampered with. Block and require correction.

Track unexplained overnight km as a running figure per vehicle and per driver. Over a month it tells the owner something no other report will.

**Cross-check 2 — daily km vs fuel cycle.** The sum of `km_run` between two fills should match the fill-to-fill odometer difference. A mismatch means a missed daily entry or an unrecorded trip — surface it rather than silently averaging over it.

### 4.4 Derived metrics

- **Mileage (km/l)** per cycle + rolling average. A vehicle whose average drops is a vehicle needing service — that's the alert worth having.
- **Cost per km** = (fuel + maintenance + toll + hire) ÷ km. The number that tells a vendor which truck to retire.
- **Service due** on **both** km-since-last-service and time-since-last-service, whichever comes first. Daily closing km makes this automatic.
- **Idle days** — days with no `km_run`, i.e. vehicles earning nothing.
- **Fuel cost per job** — attributable where fills are linked to orders, feeding job costing (6.1).

### 4.5 Practical capture notes

- **Two taps a day, one number each.** Morning: open the vehicle, type the reading, photo. Evening on return: type the reading, photo. Nothing else should be mandatory — anything heavier and drivers stop doing it.
- Show yesterday's closing on the morning screen **for reference only**, greyed out, not pre-filled into the field. The driver reads the meter and types what he sees; showing the expected value helps him spot a mistake without letting him copy it blindly.
- **Block** a closing reading lower than the opening (or require an explicit correction with reason) — the most common data-entry error.
- **Multi-day / outstation trips:** the driver isn't back at the office at night. Allow the day to close wherever he is, or mark the day as `on_trip` and capture readings at the next stop. Don't force an office return that isn't happening on a Chennai→Delhi run.
- Odometer photo on morning, evening, and every fill: cheap to capture, and it settles disputes.
- Offline-capable (Item 18) — yards, pumps, and highways frequently have no signal.
- Reminder notification if the morning reading isn't entered by a set time, and if the evening one isn't in by the cutoff.

### 4.6 Compliance (ties to Item 25)

FC, insurance, permit, PUC, road tax expiry alerts at 30/15/7 days. An expired FC stops a truck at a checkpoint mid-move.

### 4.7 Attached / hired vehicles

Most Indian movers run a mix. For non-owned vehicles track owner name, contact, hire rate or commission, and payable balance. Mileage tracking is usually irrelevant where hire is inclusive of fuel — make fuel logging optional per vehicle based on an `ownership` flag, so drivers of hired vehicles aren't nagged for entries that don't apply.

---

## Part 5 — RBAC (Item 5 in owner's list)

Staff and labour creation sits with the **vendor (owner) or manager**. Supervisors never create staff. But the whole permission set is **vendor-configurable** — Nagarva ships sensible defaults, the vendor adjusts.

### 5.1 Default roles

| Role | Scope |
|---|---|
| **Owner** | Everything, including settings, P&L, salary, deletes |
| **Manager** | Branch-scoped: leads, orders, staff, expenses, approvals; no org settings |
| **Sales / Telecaller** | Leads, follow-ups, quotes; own records only by default |
| **Surveyor** | Assigned surveys, CFT capture, quote creation |
| **Supervisor** | As defined in Part 2 |
| **Accounts** | Payments, invoices, receivables, GST, reports; no lead/order editing |
| **Driver** | Trip sheet, odometer, fuel entry only |

### 5.2 Matrix

Per module (leads, quotes, orders, payments, expenses, materials, vehicles, staff, salary, reports, settings) × action (view / create / edit / delete / approve), stored per org and editable in Settings.

### 5.3 Non-negotiables

- **Enforced server-side in RLS**, not only in the UI. Client-side gating is not a permission system.
- **Data scoping** as a separate axis from permissions: branch-level (Chennai manager sees Chennai) and own-records-only (telecaller sees own leads).
- **Salary and customer contact export** restricted by default — the most common vendor fear is staff leaving with the customer list.
- Ties to Item 11's delete rules and the Part 7 PIN login model.

---

## Part 6 — Gaps not in the owner's list (Item 8: "anything important I missed")

These are ordered by how much money or trust they protect.

### 6.1 Job costing — actual vs quoted (highest value)

The quote says the job costs X. Actual = labour + diesel + materials + toll + vehicle cost + addons. **Per-order profitability** is the number that tells a vendor which jobs, routes, and customers actually make money.

Every input already exists once Parts 2–4 are built — this is assembly, not new capture. Surface it on the order screen and as a report (Item 29).

### 6.2 Cancellation after confirmation

A customer cancelling the day before is common and currently unhandled. Needs: cancellation status distinct from Lost, reason, **cancellation charge** if applicable, refund of advance (partial or full), and release of the assigned vehicle and crew back to availability.

### 6.3 Rescheduling

Equally common. Date change must carry the assignment, notify supervisor and customer, and free the original slot. Track reschedule count per order — a customer who has moved the date three times is a risk flag.

### 6.4 Expense approval flow

Supervisor enters expenses; manager or owner **approves** before they hit P&L. Without approval, P&L is whatever staff typed. Set a per-org auto-approve threshold (e.g. under ₹500 auto, above needs approval) so it doesn't become bureaucracy.

### 6.5 Customer feedback after completion

Automated WhatsApp request post-POD: rating + comment. Feeds a Google review request for high scores, and an internal alert for low ones. Cheap to build, directly drives the referral business that this industry runs on.

### 6.6 Escalation and SLA alerts

- Supervisor hasn't marked started by X hours after scheduled time → alert manager.
- Order past scheduled delivery date, still in transit → alert.
- Quote sent, no follow-up logged in N days → alert (ties to Item 10).
- Payment overdue past terms → alert (ties to Item 24).

### 6.7 Partial and shared loads

Two customers' goods on one vehicle (common on long routes). Needs: multiple orders linked to one trip, cost apportionment by CFT, and separate LRs per consignment.

### 6.8 Storage in the flow

If goods go to storage between load and delivery, the order state must reflect it (Item 27) — the order isn't "in transit," it's "in storage," with charges accruing daily.

### 6.9 Advance and balance payment gates

Define per org: is an advance mandatory before dispatch? Is full payment required before unloading? A configurable rule with an owner override, rather than each supervisor deciding on the doorstep.

### 6.10 Duplicate lead detection

Same phone number entering from multiple sources (enquiry link, phone call, referral) must merge or flag, not create three leads that three telecallers chase separately.

### 6.11 Document numbering integrity

LR, invoice, money receipt, and PL all need per-org, per-FY sequential numbering with **no gaps and no duplicates**, including under concurrent generation. Use a DB sequence or `select … for update` on a counter row — not a client-side max+1, which will collide the first time two people generate simultaneously.

---

## Part 7 — Suggested build order for this flow

1. **Quote versioning** (1.2) — small, and it protects every negotiation from today onward.
2. **Supervisor access window fix** (2.2) — the current single-date rule breaks on every interstate job.
3. **Materials issue/consume/return** (Part 3) — stock accuracy degrades daily until this exists.
4. **Fuel entries with litres + odometer, and daily closing km** (4.1) — two small tables, and without them mileage can never be computed retrospectively.
5. **Unlock/edit-request path** (1.5) — needed before the completion lock is enforced in anger.
6. **Cash imprest** (2.5) and **expense approval** (6.4) — together they make settlement arguments disappear.
7. **Job costing** (6.1) — assembly of the above; highest-value output.
8. **RBAC matrix** (Part 5) — do once, properly, server-side.
9. Cancellation/reschedule (6.2, 6.3), feedback (6.5), escalations (6.6).

**Two things worth capturing from day one even if the features come later:** diesel **litres** (4.1) and material **returns** (3.2). Both are impossible to reconstruct after the fact — every day without them is a day of data you can never analyse.
