# Nagarva — Staff Pay, Crew Sheet, Expenses & Settlement

**Build brief section**
Prepared 1 Sept 2026 · Source: APC field diary, 16–30 Aug 2026

---

## 1. Why this section exists

APC's expenses and staff pay are currently maintained in a handwritten diary. That diary is the ground truth for this module — it is what the vendor already does correctly every night, and the app must reproduce it in less time.

The diary has three parts, and this brief covers all three:

1. **Daily entries** — jobs and expenses for the day
2. **Wage grid** — staff × date, amounts earned
3. **Settlement page** — old balance + new earnings − advances taken = balance payable

**Governing principle:** the app must be faster than paper. Every field that requires typing is a field that risks sending the vendor back to the diary. Default what can be defaulted, capture once, never ask for the same number twice.

---

## 2. Staff record — pay type

Pay type is set on the staff record and determines how that person earns. Three types:

| Pay type | Earns from | Appears on crew sheet | Carries balance |
|---|---|---|---|
| **Monthly fixed** | Fixed monthly salary | No | Yes — advances only |
| **Dynamic** | Per job, amount entered per assignment | Yes | Yes — full ledger |
| **Temporary** | Per job, settled same day | Yes | No — closes to zero |

### Monthly fixed
Office staff, managers, accountants. They do not appear on the crew sheet at all and never earn a job wage on top of their salary. They draw advances against their monthly figure; settlement nets those advances against salary.

### Dynamic
Loading crew and drivers. This is the majority of APC's staff. They appear on every job they work, with the amount entered per assignment. Balance carries forward across months, and may be negative (the diary shows a staff member at −7550 carried forward on 16/8).

### Temporary
Casual hands hired for a single shift. They appear on the job, are paid, and close to zero the same day. No carry-forward, no running ledger — a payment record, not a balance.

**Creation from within the job screen.** A temporary staff member must be creatable in two fields (name, phone) from inside the job screen itself, without navigating away. A helper who turns up on the morning of a job is the most time-critical moment in the whole flow; if the vendor has to leave the job to add him, the app gets abandoned.

**Conversion.** A temporary hand who keeps returning must be convertible to dynamic on the existing staff record, preserving history. Never force the vendor to create a second person for the same man.

---

## 3. Wage amounts are entered, not calculated

Wages are decided by the vendor and typed in per assignment. The app does **not** suggest, derive, or auto-fill wage amounts.

This was an explicit decision. The diary shows rates moving with job type and role — 800 for a plain local load, 1500–2000 for outstation or a full load-and-unload day, with the driver taking roughly 400 above the crew — but the pattern is not reliable enough to automate. An auto-suggested rate the vendor has to correct on every job is slower than typing the right number once.

**The app's job is arithmetic and memory, not judgement.** Capture what the vendor types, total it correctly, carry it forward, never ask for it twice.

---

## 4. The crew sheet

The crew sheet is the per-job staff record. It is filled at day close by the supervisor.

Each staff row on a job carries:

| Field | Notes |
|---|---|
| Staff | Dynamic and temporary staff only |
| Amount | Typed by vendor/supervisor |
| Driver tag | Exactly one per job |
| A/C work | Additive line — see §5 |

### Driver tag
The driver premium is a property of the **assignment, not the person**. A crew may contain two or three licensed drivers; the app must record who actually drove on that specific job. A man may be crew today and driver tomorrow.

**Validation:** a job cannot be saved with zero drivers tagged, or with more than one.

The tag does not affect the amount (the vendor types that), but it must be captured for records and reporting.

### A/C work
A/C uninstall is separate work with separate pay. See §5.

---

## 5. A/C work

A/C is a **task, not a pay tier**. In the diary it appears two ways: circled beside a staff name, and as a cash amount (750 on 25/8; 500×2 on 27/8; 1450 on 22/8).

Implementation: a tick on the crew row — *did this man do A/C work* — which adds an A/C amount to his earning for that job. It is **additive**, so a man who drove and also uninstalled an A/C earns both.

A/C must report as its own line, never absorbed into the wage figure.

**Open question:** the 500×2 entry on 27/8 suggests the A/C amount may be **per unit** rather than per man. To confirm with the vendor before build.

---

## 6. Job record

Each job carries:

| Field | Purpose |
|---|---|
| Job type | Only loading / unloading / local shifting / outstation |
| City / route | Salem, CBE, Tirupur, Nagercoil, Madurai, CBE→Chennai, CBE→Mettur |
| Crew size | Recorded in the diary as a circled number |
| Customer vs personal | The diary flags some jobs as "personal" |
| Order value, advance, net | Order value − advance = net collected |

Job type and city are captured for **P&L and reporting only** — they do not drive pay.

Multiple jobs per day are normal (usually two, sometimes across different cities on the same day). The day-close screen must handle several jobs without repetition of staff or expense entry.

---

## 7. Expense capture

### Expense heads observed in the diary

Diesel · Petrol · Material · Food (lunch / tea / dinner / breakfast) · Auto · Rapido · A/C · Box · Bulb · FASTag · Police · Oil service · Porter commission · External vehicle hire

The head list must be **editable per vendor** — every firm has its own vocabulary — but ships with these as defaults.

### Shared expenses split by headcount

The diary consistently writes shared costs as `amount / headcount`: 620/5, 470/4, 180/2, 260/3, 500/5, 250/5.

This split is what produces the per-person expense column at settlement (985, 1195, 1675, 950, 1950). The app must support it directly:

> Tap expense head → enter amount → tap **split** → divides across whoever is already marked present on the job.

This single feature removes all the mental arithmetic the vendor currently does nightly.

### External vehicle hire

A distinct and material cost line — 17000 on 27/8, 7000 on 29/8 (Malini Packers), 1800 on 23/8, 1400 on 21/8. It sits outside diesel and material and must be its own head.

**Open question:** should external vehicle hire attach to the specific job it was hired for, rather than sitting as a day-level expense? Attaching it gives true per-job margin in the P&L. To confirm with the vendor.

---

## 8. Advance ledger

Separate from wages. The diary maintains a **second grid** — staff × date — recording what each man drew (230, 500, 200, 460, 800…).

Rules:

- Advances are recorded per staff, per date, independent of any job
- Balances carry forward across months
- Balances may be **negative** — a staff member can be overdrawn
- Applies to monthly fixed and dynamic staff
- Does **not** apply to temporary staff, who close to zero the same day

---

## 9. Settlement

The settlement page is generated, not entered. It reproduces the diary's third page:

```
Old balance  +  New earnings  −  Advances/expenses taken  =  Balance payable
```

Worked example from the diary (25–29 Aug):

| Staff | Old | New | Total | Taken | Balance |
|---|---|---|---|---|---|
| Dinesh | 3020 | 5900 | 8920 | 985 | 7935 |
| Sho | 2310 | 5600 | 7910 | 1195 | 6715 |
| Sadham | 1160 | 4900 | 6060 | 1675 | 4385 |
| Poo | — | 3600 | 3600 | 1950 | 1650 |
| Kannan | — | 3600 | 3600 | 950 | 2650 |

The wage grid, the per-person expense column, and this settlement table all become **reports**. The vendor stops writing them entirely.

---

## 10. The day-close flow

One screen. Supervisor opens it at end of day.

1. **Jobs** — pre-filled from the order module. Confirm collected amount; order value and advance are already known, so net is automatic.
2. **Crew** — staff list with present/absent toggle. Tap one name as driver. Tick A/C on whoever did it. Type each amount.
3. **Expenses** — chips for each head. Tap → amount → done. Tap *split* for shared costs, which divides across present staff.

Everything else — the wage grid, per-person expense totals, settlement balances — the app builds with no further input.

---

## 11. Validation rules

- A job cannot be saved with zero drivers tagged, or with more than one
- A monthly-fixed staff member cannot be added to a crew sheet
- A temporary staff member cannot carry a balance past the day of the job
- A shared expense split cannot be applied before staff are marked present on the job
- Advance balances must permit negative values

---

## 12. Open questions for the vendor

1. Is the A/C amount **per unit** or per man? (27/8 reads 500×2)
2. Should external vehicle hire attach to a **specific job**, or stay a day-level expense?
3. Can a temporary staff member be paid partly in cash and partly carried, or is same-day close absolute?

---

# Part 2 — Materials & Stock

Added 1 Sept 2026

---

## 13. Why materials need their own module

The diary records material only as a rupee amount — 2435 on 26/8, 2250 on 21/8, 1780 on 30/8, plus Box 1260 and Bulb 140. That captures spend but not consumption. There is no way to know what was used, what remains, or which job over-consumed.

**Materials tracking is vendor-facing only.** It is never shown to the customer and never billed. Its sole purpose is so the vendor knows how much material was actually used and what the real profit is after that cost.

Consequently there is **one cost rate per item** — no markup rate, no customer rate.

---

## 14. Item master

Held **per branch**. APC operates three states with separate staff and vehicles; stock is never pooled across them.

Every item belongs to one of two classes:

| Class | Behaviour | Examples |
|---|---|---|
| **Consumable** | Deducts permanently when used | Cartons, tape, bubble wrap, stretch film, corrugated roll |
| **Returnable** | Goes out and comes back; never deducts | Blankets, straps, ropes, trolleys |

Each item carries a reorder level for low-stock alerts.

---

## 15. Stock valuation — weighted average

Stock is a single pool with a single value. Every purchase re-averages the rate.

Worked example:

| Event | Qty on hand | Stock value | Rate |
|---|---|---|---|
| Buy 100 boxes @ ₹40 | 100 | ₹4,000 | ₹40.00 |
| Used 30 across 3 orders | 70 | ₹2,800 | ₹40.00 |
| Buy 50 boxes @ ₹45 | 120 | ₹5,050 | ₹42.08 |
| Next job uses 20 | 100 | ₹4,208 | ₹42.08 |

**Rules:**

- The rate changes only on **purchase**, never on usage
- Jobs already closed are **never recalculated** — the 3 orders above stay charged at ₹40
- The vendor never enters a rate for a job. He enters purchases with quantity and amount; the app maintains the value and charges usage from it

This keeps P&L history stable while keeping current cost honest.

---

## 16. Tracking mode — vendor's choice

A setting chosen once at vendor setup. Nagarva ships **both**; the vendor picks which suits their operation.

| Mode | Stock held at | Behaviour at day close |
|---|---|---|
| **Branch-wise** | Branch godown only | Report used quantity; unused returns to godown |
| **Vehicle-wise** | Branch godown + each vehicle | Report used quantity; unused stays on the vehicle |

Vehicle-wise means each vehicle carries its own running stock — issue moves godown → vehicle, and unused material stays loaded for the next day rather than being unloaded nightly. More accurate, one extra step at close.

Branch-wise suits a single-vehicle operator. APC, with three states and multiple vehicles per branch, will likely run vehicle-wise.

---

## 17. Stock movements

### 17.1 Purchase
Quantity and amount entered. Adds to branch stock and re-averages the rate. This replaces the diary's bare "Material 2435" — the only change is that a quantity accompanies the rupees.

### 17.2 Issue to job
Supervisor loads the vehicle. Stock moves to **on job** (or to the vehicle, in vehicle-wise mode). It does **not** deduct at this point.

This matters because the crew always loads more than the job needs. Deducting at loading would make every job look over-consumed and the surplus would vanish from the count.

**Speed rule:** issue quantities default from the previous similar job. A 2BHK local shift uses roughly the same kit every time, so the supervisor confirms rather than types.

### 17.3 Day close — actual usage
Supervisor reports the **used** quantity. The app computes:

- **Consumables:** `issued − used = returned to stock`
- **Returnables:** `issued − returned = loss`, flagged for the vendor to confirm as damage or write-off

Returnable loss is where blankets and straps quietly disappear; surfacing it is a core benefit of the module.

### 17.4 Top-up buying on the day
The supervisor buys mid-job. One entry — quantity and amount — with a single tick:

- **Fully used on this job** → costs straight to the job, no stock movement
- **Balance to stock** → remainder lands in branch stock and re-averages the rate

The common case stays one tap while the count remains honest.

---

## 18. Per-job profit

Material consumption is what makes real per-job margin possible:

```
Collected
 − Staff wages (crew sheet)
 − A/C work
 − Day expenses (diesel, food, tolls, external vehicle hire…)
 − Material consumed × weighted-average rate
 = Real profit
```

The final line is the one the diary cannot produce today, because material sits as a lump daily figure rather than attaching to a job.

---

## 19. Validation rules — materials

- Stock is held per branch; never pooled across branches
- Consumables deduct on **reported usage**, never on issue
- Returnables never deduct; unreturned quantity raises a loss flag
- Purchases re-average the stock rate; closed jobs are never repriced
- Materials data is vendor-facing only and must not appear on any customer-facing document or quote

---

# Part 3 — Vehicles

Added 1 Sept 2026

---

## 20. Why vehicles need their own module

Diesel is the single largest daily cost in the diary — ₹6,000 on 23/8, ₹4,000 on 27/8, ₹6,000 on 30/8 — recorded as a bare amount with no vehicle attached and no odometer reading. There is currently no way to distinguish heavy running from leakage.

**The odometer is the field that changes everything.** Captured at each diesel fill, it derives km run, mileage per litre, and cost per km — per vehicle and per driver. A vehicle drifting from 5 kmpl to 3.5 kmpl becomes visible immediately.

APC does not record odometer readings today and intends to start.

---

## 21. Three vehicle relationships

| Relationship | Payment | Held in | Example |
|---|---|---|---|
| **Own** | None | Vehicle master | Own vehicles |
| **Rent** | Fixed monthly rent | Vehicle master | ₹24,000/month agreement |
| **External hire** | Per trip | Cost line + hire vendor list | Malini Packers ₹7,000 |

External per-trip hire is **not** a vehicle in the master — it is an expense head with a hire-vendor name. A hire vendor list should be maintained so the vendor can see who they rely on and at what rate.

---

## 22. Cost responsibility matrix

Cost responsibility is **configurable per vehicle**, not fixed by type. Every rental agreement is negotiated differently, and other Nagarva vendors will have different terms.

APC's current rental agreement, which loads as the Rent default:

| Cost head | Vendor's | Owner's |
|---|---|---|
| Driver | ✓ | |
| Diesel | ✓ | |
| Oil service (every 10,000 km) | ✓ | |
| Minor expenses | ✓ | |
| Tyre | | ✓ |
| Insurance | | ✓ |
| FC | | ✓ |

**Rules:**

- Own defaults to every head ticked
- Rent loads a default split, editable per vehicle
- Any head marked owner's never appears as a cost entry on that vehicle and never touches vendor P&L
- If oil service is the vendor's, the km interval is set here (APC: 10,000 km)

This makes the odometer **contractual, not optional** — the service obligation triggers on km, and on a rented vehicle a missed service is a dispute with the owner. Alert at 9,500 km since last service; show km-to-next on the vehicle card.

---

## 23. Vehicle setup flow

1. Select type — Own or Rent
2. If Rent — monthly rent, owner name and contact, agreement start/end
3. If financed — EMI amount, lender, tenure
4. Tick the cost responsibility matrix
5. If oil service is vendor's, set the km interval

---

## 24. Vehicle record — full field list

### Identity
Registration number · vehicle type (tempo / truck / LCV) and capacity · make, model, year · branch · active/inactive status

### Ownership & commercials — *admin-visible only*
Type (Own / Rent) · monthly rent · owner name and contact · agreement start and end · EMI amount, lender, tenure · purchase date and value

### Documents — with expiry alerts
Insurance · FC · permit · national permit · PUC · road tax
Each with expiry date and document upload. Alerts at 30 and 7 days.

### Running entries
- **Diesel** — date, amount, litres, **odometer**, filled by whom
- **FASTag / tolls** — spend and recharges
- **Service log** — date, odometer, service type, cost
- **Tyre, mechanic, breakdown**
- **Police / checkpost**

Every entry is tagged to the vehicle, and to a job where applicable.

### Assignment
Vehicle on job with driver tagged (from the crew sheet) · current status: available / on job / under service · vehicle-wise material stock where that mode is enabled

### Derived — no input required
km run · kmpl · cost per km · km since last service and km to next · per-vehicle P&L (revenue from its jobs − its own costs) · rent or EMI applied

### Alerts
Document expiring · service due · mileage dropped versus that vehicle's own running average

---

## 25. Odometer capture — design for adoption

Since APC is starting fresh, the field must be designed so it actually gets entered:

- Lives on the **diesel entry screen only**, nowhere else
- Pre-filled with the last reading — a small edit, not a fresh type
- Shows derived mileage immediately on entry: *"4.8 kmpl — last fill 5.1"*. The person entering sees the payoff at the moment of entry, which is what makes the habit stick
- Required for owned, rented and financed vehicles; the vendor pays diesel on all three
- First entry is simply a baseline; no back-history required

---

## 26. Additional vehicle features

- **Fuel bunk credit account** — most operators fill on credit at a fixed bunk and settle monthly. Needs a bunk vendor, running credit balance, and monthly settlement, or diesel entries never reconcile against the bunk bill.
- **FASTag balance and recharge** — recharges as well as spend, so the balance is visible before a vehicle is stopped at a plaza.
- **Trip sheet** — start km, end km, route, per trip. This is what makes odometer data trustworthy rather than a typed number.
- **e-challan and fines** — tagged to both vehicle and driver, to surface recurring offenders.
- **Driver documents** — licence and badge expiry, same alert model as vehicle papers.
- **Depreciation** — owned vehicles are assets; without it per-vehicle P&L overstates profit and the books will not reconcile.
- **Utilisation report** — running days versus idle days. The key metric for deciding whether to keep a rented vehicle.
- **Inter-branch transfer** — a vehicle moving between states carries its full history.
- **Accident and insurance claims** — date, damage, claim status, recovery.

---

## 27. Vehicle RBAC

Commercial terms are the sensitive data here. A driver or supervisor must never see the rent figure.

| Role | Can see | Can do |
|---|---|---|
| **Driver** | His assigned vehicle only | Enter diesel + odometer, report breakdown |
| **Supervisor** | Branch vehicles, running costs | Assign vehicle to job, enter running expenses |
| **Branch manager** | Full costs, his branch only | Add vehicles, edit cost matrix |
| **Vendor admin** | All branches, all terms | Everything including rent and agreements |
| **Accountant** | All financials | Read only, no assignment |

- Rent, EMI and agreement terms are **admin-visible only**
- The cost responsibility matrix is editable by manager and above — never by supervisors, since unticking a head silently removes costs from P&L
- Branch scoping applies throughout: a Karnataka manager never sees Tamil Nadu vehicles

---

## 28. Open question — rent allocation

Should monthly rent (₹24,000) be:

- **(a)** spread across the jobs that vehicle ran, so per-job profit carries its share — truer job margin, but a slow month makes every job look worse; or
- **(b)** held as monthly overhead below job margin — the more common operator view

**Not yet decided.** This changes what "real profit" means on every job.

---

# Part 4 — ERP Scope Gaps

Added 1 Sept 2026

These are features Nagarva needs as a genuine ERP. Some may already sit in the 30-item master build brief; this list should be reconciled against it.

---

## 29. Audit trail — mandatory

Confirmed as a **must-have**.

An ERP where supervisors and managers edit money requires a complete, tamper-evident record of change.

**What is logged:**

- Who, what, when, from what value to what value
- Every financial edit: wages, expenses, collections, material quantities, stock rates, vehicle costs
- Every master-data change: staff pay type, cost responsibility matrix, item rates, RBAC role changes
- Deletions and cancellations, including the reason
- Login events and failed access attempts

**Rules:**

- Append-only. Log entries can never be edited or deleted, by any role including vendor admin
- Retained for the life of the tenant, never purged
- Viewable by vendor admin and accountant; not by supervisors
- Every record shows its own change history inline, so an edited wage or expense displays its trail without leaving the screen
- Super-admin actions on a tenant are logged in the same trail and visible to that vendor

---

## 30. Further scope gaps

- **Transit insurance & customer damage claims** — core for packers and movers, not optional. Claim registration, assessment, deduction, settlement, and any legal escalation.
- **Receivables ageing** — who owes, how much, how long. The diary tracks collection but not outstanding.
- **Payables** — hire vendors (Malini and similar), material suppliers, fuel bunk credit.
- **Purchase orders** for materials, so buying is authorised rather than ad-hoc.
- **Storage / warehousing** — monthly godown space rented to customers; an entirely separate revenue line.
- **Accounting export** — Tally-compatible and GST-ready output. Vendors will not run two systems in parallel.

---

# Part 5 — Accounts

Added 1 Sept 2026

---

## 31. Scope decision — operational accounts

**Decision: operational accounts, not full double-entry.** Statutory books and GST returns stay outside Nagarva; a Tally export is provided as an optional module.

**Important qualifier:** not all vendors in this market file IT or GST returns. Many have no accountant and no Tally at all. Therefore operational accounts must be **complete and standalone** — for most of the market it *is* the accounting system, not a feeder into one.

This makes Tally export a low-priority optional module, built once and off by default.

**Design hedge:** post operational transactions to internal ledgers from day one, without exposing journals or a trial balance. The data model stays double-entry-ready, so full accounting can be surfaced later without a rewrite.

---

## 32. Core principle — generated, not typed

The diary is already a cash book with a receivables column. Accounts must be **generated from operations**, never re-entered.

Automatic inflows to accounts:

| Source module | Posts to |
|---|---|
| Job collections | Receivables, cash/bank |
| Crew sheet | Wages payable, staff advance ledger |
| Day expenses | Expense ledgers, cash out |
| Material usage | Cost of goods, at weighted-average rate |
| Vehicle costs | Per-vehicle expense, rent, EMI |
| Porter commission | Payable to Porter, P&L deduction |

The vendor's only direct entries are bank transactions and adjustments.

---

## 33. What accounts holds

- **Cash and bank per branch** — the three states run separate accounts; ledgers are branch-scoped with consolidation above
- **Receivables with ageing** — who owes, how much, how long. The diary tracks collection but never outstanding.
- **Payables** — hire vendors (Malini and similar), material suppliers, fuel bunk credit, vehicle owners' rent
- **Day book** — direct replacement for the diary page, auto-built
- **P&L at four levels** — per job, per vehicle, per branch, consolidated
- **Bank reconciliation**

---

## 34. Personal versus business

The diary flags some jobs as personal — 12000 local personal on 21/8, 5000 personal pending on 26/8.

These must be tagged at job level and **excluded from business P&L**, while still appearing in the cash book. Without this the margin figure is wrong.

---

## 35. GST — a per-tenant and per-branch toggle

GST is optional, not assumed.

| Vendor state | Billing | Screens |
|---|---|---|
| Registered | GSTIN, tax invoice, SAC/HSN, GST reports | Tax fields visible |
| Unregistered | Plain bill or cash receipt | No tax fields anywhere |

**Rules:**

- An unregistered vendor must never see a GST field. Forcing tax UI on someone who doesn't understand it is exactly the friction that sends them back to a diary.
- The toggle sits at **branch** level as well as tenant level. APC is the mixed case — registered in Tamil Nadu, not in Karnataka or Andhra.
- The switch must be **flippable mid-life**. A vendor crossing the turnover threshold registers and begins issuing tax invoices; invoice numbering and history must survive the change without restarting or breaking.

### GSTIN per branch — decided

**Decision: GSTIN sits at branch level, not tenant level.**

Compliance is the **vendor's responsibility**. Each vendor consults their own CA and configures Nagarva accordingly. CAs differ in their interpretations, so hard-coding any single reading into the platform is the real risk.

Per-branch is a **superset** of per-tenant: a vendor with one registration is simply a business with one branch. Per-tenant cannot be stretched the other way — it could never support a vendor holding registrations in several states.

Accordingly:

- GSTIN, rates, SAC codes and tax treatment are **vendor-set configuration fields**, never fixed values in code
- A vendor may have registered and unregistered branches simultaneously, as APC currently does
- **The software calculates and records. It does not advise, validate, or block.**

**Legal note:** because Nagarva generates invoices, the terms of service should place compliance responsibility on the vendor and state explicitly that the platform provides no tax advice. To be drafted with a lawyer alongside the terms of service.

**Forward view:** GST enforcement has been tightening. Vendors who don't file today may be required to within a few years. Designing GST as a first-class toggle rather than an afterthought lets Nagarva grow with them rather than being abandoned at the moment they register.

---

## 36. Registration and access

**No user can log in to Nagarva without registering.** A closed system is a prerequisite for the audit trail — an append-only log is worthless if actions cannot be traced to a person.

"Registration" here means a **Nagarva account**, not business or GST registration. Unregistered firms are welcome as vendors.

Two paths, deliberately different:

| Who | How |
|---|---|
| **Vendor** | Self-registers with business details and branch; invite code or approval gates org creation |
| **Staff** | Never self-register. The vendor creates them and issues a PIN. |

A driver or supervisor cannot sign himself up, which keeps the staff list matching who actually works there.

### Shared-login risk

In this industry one supervisor's login gets passed around the branch. When that happens the audit trail records the wrong person and the entire accountability layer becomes fiction.

Mitigations to decide on:

- Enforce single active session per PIN, or
- Flag concurrent logins to the vendor

Related: PINs must be **unique within a branch**. Two staff sharing a PIN makes identity ambiguous before the audit log is even reached.

---

# Part 6 — Warehouse / Storage Income

Added 1 Sept 2026

---

## 37. Storage sits inside the order

Storage is **not a separate module or a separate order**. It is a revenue line within the existing order, alongside shifting, packing and A/C work. One customer, one order, multiple revenue lines.

This matters because the same goods flow through: move in → stored → moved out. Splitting storage into its own order would break that chain and lose the link between the inbound job, the storage period, and the outbound delivery.

---

## 38. Rate structure

Rates are set by **storage size** and **city**. APC's current structure (Chennai, Coimbatore, Bengaluru):

| Size | Per day | 15-day minimum | Per month (30 days+) |
|---|---|---|---|
| Tata Ace | ₹300 | ₹4,500 | ₹4,200 |
| Pickup | ₹350 | ₹5,250 | ₹5,300 |
| 407 | ₹400 | ₹6,000 | ₹6,400 |
| 14 feet | ₹450 | ₹6,750 | ₹7,500 |
| 17 feet | ₹500 | ₹7,500 | ₹8,500 |
| 20 feet | ₹600 | ₹9,000 | ₹9,800 |

**Prices will differ by vendor and by city — this is the structure, not fixed values.** Rates live in the Rate Cards module, scoped per city.

### Billing modes

| Mode | Applies | Basis |
|---|---|---|
| Short-term | 15 to 29 days | Per day, with a 15-day minimum floor |
| Monthly | 30 days and above | Per month |
| Custom | Any negotiated arrangement | Vendor-defined |

**Minimum storage period is 15 days.** A stay of 8 days still bills 15.

---

## 39. Plan is locked at booking — no automatic crossover

**Decided.** The customer chooses daily or monthly at booking, and that choice holds for the entire stay. The system never converts one to the other.

**Rules:**

- **Daily means daily.** A stay booked on the daily plan bills per day for its whole duration, however long it runs. It does not become monthly at 30 days.
- **Monthly means monthly.** Early collection is permitted, but the full month is charged. No pro-rata refund.
- **The plan is chosen at booking**, not derived from actual duration.

### Why the customer chooses, not the system

Availability drives the decision. A vendor holds different sizes at different locations, and what can be offered depends on what is free at that location. The plan is part of the booking conversation, not a billing calculation.

### Critical — no assumed relationship between rates

**The system must never assume monthly is cheaper than daily.** In APC's own sample structure it is cheaper for a Tata Ace (₹4,500 for 15 days vs ₹4,200 monthly) but more expensive for a Pickup (₹5,250 vs ₹5,300). Other vendors will price differently again.

Daily rate and monthly rate are **independent values**. No comparison, no "best rate" suggestion, no automatic switching. Whatever the vendor enters is what bills.

### Disclosure

Because early collection on a monthly plan forfeits the balance of the month, the plan terms must be shown at booking and printed on the customer's document. This is the main dispute risk in the module and is handled by disclosure, not by billing logic.

---

## 40. Storage record — fields

### On the order
- Storage size (Ace / Pickup / 407 / 14ft / 17ft / 20ft)
- Warehouse / branch location
- Start date (goods in)
- Expected end date, if known
- Actual end date (goods out) — set at delivery
- Billing mode: short-term / monthly / custom
- Rate applied, from the city rate card
- Status: in storage / partially delivered / closed

### Charged separately
Loading and unloading are **extra** and billed separately from storage rent. They are ordinary job lines using the existing crew sheet and wage logic.

### Goods record
- Item list or lot description
- Number of packages
- Photographs at intake
- Location within the warehouse (bay / rack / container ID)
- Condition noted at intake and at release

Photographs at intake matter — they are the vendor's protection when a customer claims damage after a long stay.

---

## 41. Billing behaviour

- Storage **accrues** — the charge grows while goods remain. It is not a one-time invoice at booking.
- For monthly stays, generate a **recurring invoice** each period rather than one bill at the end. A six-month stay billed only on release becomes a large receivable the customer may dispute.
- Final billing is triggered when goods are released.
- Partial delivery is possible: the customer collects some goods and leaves the rest. Storage size may then reduce, changing the rate going forward.

**Alerts:**
- Approaching the 30-day crossover
- Storage unbilled beyond one period
- Long-staying goods with no customer contact — dead stock risk

---

## 42. Link to operations

When a customer requests delivery out of storage, a vehicle is assigned — either the vendor's own or a hire vendor's. This flows through the existing Operations, Fleet and Trips modules and remains linked to the original order.

The full chain on one order:

```
Inbound job (move in)
  → Storage period (accruing rent)
    → Outbound job (delivery, vehicle assigned)
      → Final billing
```

---

## 43. Resolved — expense classification and rent allocation

The vendor confirmed that office rent, vehicle maintenance and EMI are **not linked to orders**.

This resolves the open question at §28. P&L has two levels:

```
Order revenue − order-linked costs        = Job margin
Job margin    − overheads (rent, EMI, office) = Net profit
```

**Therefore vehicle rent (₹24,000/month) is an overhead, not spread across jobs.**

Every expense entry carries one flag: **order-linked** or **overhead**. Order-linked costs are wages, material, diesel for that job, hire vendors, A/C work. Overheads are office rent, vehicle rent and EMI, salaries of monthly-fixed staff, and general maintenance.

---

## 44. Storage rate cards — ownership and editing

The rate table at §38 is APC's current structure, shared as a **sample design**. Prices, plans and sizes are all vendor-editable.

### Who can edit

| Role | Storage rates |
|---|---|
| **Vendor admin** | Create and edit rates, plans, sizes |
| **Branch manager** | View; edit only if admin grants the permission |
| **Supervisor** | View only |
| **Platform admin** | Never edits vendor pricing |

### Rules protecting live bookings

- **Rate changes apply forward only.** Goods already in storage keep the rate agreed at intake until that stay closes. Without this, a price revision silently re-bills every existing customer.
- **Each storage record stores the rate it was booked at**, not a pointer to the current rate card.
- **Rate history is retained.** When a customer queries a bill months later, the vendor can show what was agreed and when it changed.

### Vendor-defined sizes

Storage sizes must be a **vendor-defined list, not a hard-coded set**. APC prices by vehicle and container size (Ace, Pickup, 407, 14ft, 17ft, 20ft), but another vendor may price by square feet, by room count, or by pallet. The module ships with APC's list as a default template that any vendor can replace.

Plans are likewise vendor-defined. APC currently runs three — 7 days, 15 to under 30 days, and customised — but the count and naming are theirs to set.

---

## 45. Session policy — one PIN, one device

**Decided.** A PIN holds a single active session. When a user logs in on a new device, the previous device is logged out immediately.

This is what makes the audit trail trustworthy. If a supervisor lends his PIN, he is logged out himself the moment it is used — PIN sharing becomes self-defeating rather than merely discouraged.

### Requirements

- **The logged-out device must show the reason** — "Logged in on another device at 4:12pm". A silent logout reads as a bug; a stated reason exposes sharing immediately and gives the user something to report.
- **Drafts save continuously.** A supervisor mid-way through day close must not lose half-entered wages and expenses to a forced logout. Losing work once sends him back to the diary permanently.
- **Device change is an admin action.** Lost and replaced phones are routine. Vendor admin re-registers the device; staff cannot self-register a new one.
- **Login events are logged** to the audit trail — device, time, and any forced logout — so repeated device switching is visible to the vendor as a sharing signal.

### Offline handling

Crews work in basements, lifts and stairwells with no signal. Session validation must occur **on reconnection, not as a blocking check**. A user must never be logged out or prevented from working because of poor coverage; the session is verified when the device next reaches the network, and any conflict is resolved then.

---

# Part 7 — Invoice, Receipt & Document Structure

Added 1 Sept 2026
Source: APC live customer documents — Bill 2026/0032 and Money Receipt 2026/0028

---

## 46. Document numbering

APC runs **separate year-prefixed series per document type**:

| Document | Example |
|---|---|
| Quotation | 2026/0059 |
| Money Receipt | 2026/0028 |
| Bill (Tax Invoice) | 2026/0032 |

Nagarva must reproduce this: an independent counter per document type, per financial year, per branch, with no gaps. Numbers are never reused and never re-sequenced after issue.

---

## 47. Bill (Tax Invoice) — structure

### Header
Company name, logo, tagline · registered address · GSTIN and PAN · phone numbers and telephone · website and email · branch list · affiliation and UDYAM number

### Bill details
Bill number · billing date · delivery date · vehicle number · moving path (e.g. By Road) · type of shipment (e.g. Household Goods) · from city · to city

### Bill To
Name · phone · GST number (optional, blank for individuals) · country · address · city, state with state code, PIN

### Move From / Move To
Two separate blocks, each with name, phone, GST number, country, full address, city, state with code, PIN. The Move To party may differ from the billed party.

### Consignment details
Package count · packages and goods description · total weight or volume · **HSN/SAC code** · payment remark · remark

### Charge lines

| Line | Notes |
|---|---|
| Freight | |
| Packing Staff Charge | |
| Un Packing Staff Charge | May be "Included" |
| Loading Charge | |
| Un Loading Charge | |
| Pack. Material Charge | |
| **Sub Total** | |
| SGST | Rate configurable |
| CGST | Rate configurable |
| FOV / Insurance Charge | May be "Optional" |
| **Total Amount** | |

Plus: total in words · GST Paid By (consignor / consignee) · Reverse Charge (yes/no)

### Footer
Prohibited-items note · terms and conditions acknowledgement with receiver signature block, name, phone, date and time · authorised signatory · bank details (beneficiary, bank, account number, IFSC) · UPI and PhonePe/GPay · computer-generated document note · query contact numbers · PAID watermark when settled

---

## 48. Two behaviours the charge lines require

### 48.1 A line can be text, not a number
"Un Packing Staff Charge: **Included**" and "FOV/Insurance Charge: **Optional**" are live examples.

Each charge line must accept either an amount or a status label (Included / Optional / Nil / Not Applicable). Status labels contribute zero to the sub-total but still print, because they tell the customer the service is covered rather than omitted.

### 48.2 Insurance is a percentage of declared value
APC's note reads: *insurance charge @3% on declaration value of goods*.

This requires:

- A **declared value** field on the order
- An insurance percentage, vendor-configurable
- Insurance amount derived from the two, not typed
- The ability to leave it as "Optional" when the customer declines

Declared value also feeds the Insurance module and any damage claim, so it belongs on the order rather than only on the invoice.

---

## 49. Money Receipt — structure

A separate document type with its own series.

**Fields:** receipt number · date · received from (name) · phone · what it is towards (final payment / advance / part payment) · **linked quotation or bill number and its date** · from city · to city · payment mode (UPI, cash, bank transfer) · transaction reference numbers, allowing more than one · amount in words · amount in figures · authorised signatory

The link to the quotation or bill number is what ties collection to the order and feeds receivables. A receipt must never exist without that link.

---

## 50. Configurability

Every element above is **vendor-configurable**, since this is APC's template and other vendors bill differently:

- Charge line names and which lines appear
- Tax rates and whether tax appears at all (per the GST toggle at §35)
- Insurance percentage
- Terms and conditions text, prohibited-items note
- Bank and payment details
- Logo, colours, header and footer content

APC's structure ships as the default template.

---

## 51. Observations on the current documents

Raised for the vendor's own review with his CA. These are document-level observations, independent of the registration question.

1. **HSN/SAC code is blank** on the tax invoice. Normally a mandatory field on a tax invoice.
2. **"GST Paid By: Consignee" appears alongside SGST and CGST charged on the same invoice, with Reverse Charge marked NO.** These statements appear to conflict.
3. **The letterhead address is Bangalore, Karnataka, while the GSTIN begins 33 (Tamil Nadu).** An invoice showing one state's address under another state's GSTIN invites a question regardless of how the registration matter is resolved.

Nagarva should make HSN/SAC a required field on any tax invoice, so this cannot recur for any vendor.

---

# Part 8 — Product-Wide Pricing Principle

Added 1 Sept 2026

---

## 52. No price is ever pre-filled, anywhere

**Every rate, wage, charge, price and amount in Nagarva opens at zero or empty. The vendor decides.**

Nagarva is a SaaS product. Prices differ by vendor and by city, and no default the platform supplies can be right for more than one of them. A suggested figure the vendor must correct on every entry is slower than typing the correct one once — which is the opposite of the product's core principle at §1.

### All APC figures in this brief are illustrative only

Every rupee value in this document is drawn from Arun Packers and Couriers' own diary, invoice and storage flyer. They are shown to convey **structure**, never as values to ship:

| Section | Figures shown | Status |
|---|---|---|
| §3 | Wage rates (800, 1200, 1500, 2000) | Illustrative |
| §22 | Rental cost split, ₹24,000 rent, 10,000 km service | Illustrative |
| §38 | Storage rate table, all sizes | Illustrative |
| §47 | Invoice charge amounts | Illustrative |
| §48 | 3% insurance on declared value | Illustrative |

Structures ship as empty templates. Values never ship.

### Applies to

- Staff wages — no derivation from monthly salary, no per-day rate, no carry-over from the last job
- A/C rate per unit — varies job to job even within one vendor (₹750 and ₹500 in the same week)
- Material cost rates — set by actual purchase, then weighted average (§15)
- Storage rates — vendor-set per city and size (§44)
- Invoice charge lines — vendor-set per job
- Insurance percentage, tax rates, commission rates

### The one permitted exception

**Recalling a figure the same human just typed, within the same screen.** Offering the A/C rate entered a moment ago as the default for the next tick is memory of the vendor's own number, not a value the platform invented. This is not a suggested price.

### Statutory values are not prices

Percentages fixed by law rather than by the vendor — TDS rates, for example — may carry a default, since they are not a commercial decision. They remain editable.

### Known violation to remove

`CrewSyncService._dayRate` derives a wage as `staff.salary / 26` and seeds `order_staff.salary_amount`; Add Labour pre-fills the same figure. Both predate this principle and must return zero. Safe to change while `orders` and `order_staff` hold no rows; after live data exists this would re-price real jobs.
