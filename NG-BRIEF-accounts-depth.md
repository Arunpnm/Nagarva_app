# Architecture brief — Accounts depth (double-entry GL)

**For:** Claude Code
**From:** architecture/spec layer
**Scope:** `chart_of_accounts`, `journal_entries`, `journal_lines`, posting layer, period
control, reporting views. Touches every module that moves money.

---

## 0. Read this before writing any SQL or Dart

**Verify live schema first.** Every table and column name in this brief is inferred from
session reports, not from reading the database. Before writing a single migration, introspect
the live schema for: `orders`, whatever table holds invoices and money receipts,
`vendor_bills`, `vendor_payments`, `trip_expenses`, `claims` / `claim_items`, `expenses`,
and any payroll tables. Report actual column names and types. Where this brief names a
column that doesn't exist, follow the database, not the brief.

**`orders.id` is TEXT.** Every source-document reference in the GL must accommodate that.
This brief uses `text` for all source ids deliberately — do not "fix" it to uuid.

**Do not build this in one session.** The migration order in §8 is dependency-ordered and
each step is independently reviewable. Arun reviews and runs all SQL himself.

**Sequencing prerequisite — raise this before starting.** Historical rows created before the
posting layer exists will have no journal entries. Two ways out: backfill by replaying every
historical source row, or set an opening-balance cutover. Since the current data is test data
slated for deletion, the cheapest path by far is: **clear transactional test data first, then
build this, so every transaction from day one posts naturally and no backfill is ever needed.**
Confirm with Arun before proceeding. (The opening-balance RPC in §8 step 7 is still required
regardless — real tenants onboarding with existing books need it.)

---

## 1. Decisions that are NOT yours to make

Flag these to Arun and wait. Do not guess, and do not pick a default silently.

| Decision | Why it matters |
|---|---|
| **Accrual vs cash basis** | Determines whether a vendor bill posts on receipt or on payment. Recommendation: accrual (mercantile) — invoices and bills already exist as documents in the system, so accrual is the natural fit and is required for meaningful AR/AP. Needs confirmation. |
| **GTA / reverse-charge (RCM) applicability** | Goods Transport Agency services frequently fall under RCM, where the *recipient* pays GST. Whether APC (and tenants generally) charge forward GST or issue RCM invoices changes the invoice posting recipe entirely. This is a CA question, not an engineering one. |
| **TDS rates and thresholds** | 194C on transport contractors is rate-dependent on payee constitution and has annual/per-transaction thresholds. Do not hardcode a rate. |
| **Composition scheme** | If any tenant is registered under composition, they cannot claim input credit and the input-GST accounts don't apply to them. Affects whether the seed CoA is uniform across tenants. |
| **Fiscal year** | Assume Indian FY (1 April – 31 March) unless told otherwise, but confirm. |

Build the schema so these are configurable per-org rather than baked in.

---

## 2. Posting mechanism — DB triggers, not Dart

**Decision: posting happens in the database, via `AFTER` triggers on source tables that call
one shared posting function.**

Rationale: writes reach these tables from multiple paths — the Flutter app writing directly
through the Supabase client, SECURITY DEFINER RPCs serving the public site, Edge Functions,
and future imports. A Dart-side posting service would be bypassed by every path except the
app. Only the database sees all writes.

Rejected alternative: posting logic inline in each trigger. One shared function keeps the
recipes in a single greppable place and makes reversal symmetric.

Shape:

```
source table write
  → AFTER INSERT/UPDATE/DELETE trigger (one per source table, thin)
    → fn_post_journal(p_org_id, p_source_table, p_source_id, p_entry_date,
                      p_narration, p_lines jsonb, p_dimensions jsonb)
      → INSERT journal_entries + journal_lines
      → deferred constraint verifies balance at COMMIT
```

Because it runs in the same transaction as the source write, a posting failure rolls back the
source write too. That is the intended behaviour: an unpostable transaction should not be
recordable.

---

## 3. Schema

### 3.1 `chart_of_accounts`

```
id             uuid pk default gen_random_uuid()
org_id         uuid not null
code           text not null            -- '1100', '4000'
name           text not null
account_type   text not null            -- asset|liability|equity|income|expense
account_subtype text                    -- bank|receivable|payable|current_asset|...
parent_id      uuid null references chart_of_accounts(id)
is_system      boolean not null default false   -- seeded; cannot be deleted
is_active      boolean not null default true
created_at     timestamptz default now()

unique (org_id, code)
```

`is_system` protects accounts the posting recipes depend on. A tenant may rename or deactivate
them but never delete them — enforce with a `BEFORE DELETE` trigger.

### 3.2 `journal_entries`

```
id                uuid pk
org_id            uuid not null
entry_no          text not null              -- 'JE-2026-0001', per-org sequence
entry_date        date not null
narration         text
source_table      text                       -- 'vendor_bills', 'invoices', ...
source_id         text                       -- TEXT: orders.id is text
reverses_entry_id uuid null references journal_entries(id)
is_reversed       boolean not null default false
posted_at         timestamptz not null default now()
posted_by         uuid                       -- auth user
created_at        timestamptz default now()

unique (org_id, entry_no)
```

Idempotency guard — prevents double-posting on retry:

```sql
create unique index uq_je_source_active
  on journal_entries (org_id, source_table, source_id)
  where reverses_entry_id is null and is_reversed = false;
```

### 3.3 `journal_lines`

```
id             uuid pk
org_id         uuid not null
entry_id       uuid not null references journal_entries(id) on delete cascade
account_id     uuid not null references chart_of_accounts(id)
debit          numeric(14,2) not null default 0
credit         numeric(14,2) not null default 0
line_narration text

-- dimensional tags, all nullable
order_id       text null                 -- TEXT to match orders.id
trip_id        uuid null
customer_id    uuid null
vendor_id      uuid null
staff_id       uuid null

check (debit >= 0 and credit >= 0)
check (not (debit > 0 and credit > 0))
check (debit > 0 or credit > 0)
```

**`numeric(14,2)` throughout. Never float, never double precision.**

The dimensional tags are what let the GL answer "profit on order NGV-1043" without a parallel
P&L system — see §6.

### 3.4 Balance enforcement

A row-level `CHECK` cannot span rows, and lines are inserted one at a time. Use a **deferred
constraint trigger** that fires at `COMMIT`:

```sql
create constraint trigger trg_je_balanced
  after insert or update or delete on journal_lines
  deferrable initially deferred
  for each row execute function fn_assert_entry_balanced();
```

`fn_assert_entry_balanced()` raises unless, for the affected `entry_id`,
`sum(debit) = sum(credit)` and at least two lines exist.

### 3.5 `accounting_periods`

```
id          uuid pk
org_id      uuid not null
fy_label    text not null          -- 'FY 2026-27'
period_start date not null
period_end   date not null
is_locked   boolean not null default false
locked_at   timestamptz
locked_by   uuid

unique (org_id, period_start)
```

`fn_post_journal` rejects any entry whose `entry_date` falls in a locked period. Once a
period is locked, corrections go into the current open period as dated adjustments.

---

## 4. Immutability and correction

**Journal entries are never updated or deleted once posted.** This is not a style preference;
an auditable ledger requires it.

- Source row **updated** → reverse the existing entry, post a fresh one.
- Source row **soft-deleted / cancelled** → reverse only.
- Reversal = a new entry with sign-flipped lines, `reverses_entry_id` set, and the original
  flagged `is_reversed = true`.

Implement as `fn_reverse_journal(p_entry_id, p_reason)`. Never `DELETE FROM journal_lines`
outside of cascade.

---

## 5. Posting recipes

Verify account codes against the seeded CoA (§7) and column names against live schema before
implementing. GST split is CGST+SGST for intra-state, IGST for inter-state — driven by place
of supply, which for a moving company is the origin/destination pair already on the order.

**5.1 Tax invoice issued**
```
Dr  1100 Accounts Receivable        (invoice total incl. GST)
    Cr  4000/4010/4020/…            (taxable value, split by charge type)
    Cr  2200 Output CGST / 2201 Output SGST  — or —  2202 Output IGST
```
Dimensions: `order_id`, `customer_id`.

**5.2 Money receipt against invoice**
```
Dr  1000 Cash in Hand  /  1011 Bank
Dr  1110 TDS Receivable             (if the customer deducted TDS)
    Cr  1100 Accounts Receivable
```

**5.3 Advance received before invoice**
```
Dr  1000/1011
    Cr  2100 Customer Advances
```
On later invoice: `Dr 2100 → Cr 1100` to adjust.

**5.4 Vendor bill**
```
Dr  5000/5010/…  Expense            (taxable value)
Dr  1200/1201/1202 Input GST
    Cr  2000 Accounts Payable       (net of TDS)
    Cr  2300 TDS Payable            (if deducted)
```
Dimensions: `vendor_id`, plus `order_id`/`trip_id` where the bill is job-specific.

**5.5 Vendor payment**
```
Dr  2000 Accounts Payable
    Cr  1000/1011
```

**5.6 Trip expense** (fuel, toll, driver batta — typically cash paid by supervisor)
```
Dr  5010 Fuel / 5020 Toll / 5030 Driver Batta
    Cr  1000 Cash in Hand           (or 2000 if on credit)
```
Dimensions: `trip_id`, `order_id`, `staff_id`.

**5.7 Claim settlement**
```
Dr  5080 Claims & Damages
    Cr  1011 Bank                   (paid) — or — 2600 Claims Payable (accrued)
```

**5.8 Payroll**
```
Dr  6000 Salaries & Wages
Dr  6010 PF/ESI Employer Contribution
    Cr  2400 Salary Payable
    Cr  2410 PF Payable  /  2420 ESI Payable
    Cr  2300 TDS Payable
```

**5.9 Porter / agent commission**
```
Dr  5060 Porter Commission
    Cr  2500 Commission Payable     (or Cash if settled immediately)
```

**5.10 Rounding**

GST computation routinely produces ±0.01 discrepancies. Every recipe must be able to emit a
balancing line to **4910 Rounding Off** when |difference| ≤ 0.05. Larger differences must
raise, not silently absorb.

---

## 6. Reconciling GL with the existing operational P&L

`trip_pnl_view` and the Order Details P&L card compute profit directly from source tables.
Once the GL exists there are two candidate sources of truth. Resolve it explicitly:

- **The GL is authoritative for financial reporting** (P&L statement, balance sheet, trial
  balance, anything a CA or the tax department sees).
- **Operational views stay** for per-order and per-trip management reporting — they are faster
  and can include non-GL data like estimated vs actual CFT.
- The dimensional tags on `journal_lines` mean the GL can reproduce per-order profit
  independently. Build `order_pnl_gl_view` and have it reconcile against the existing
  operational view. **A mismatch is a bug in one of them** — that reconciliation is the single
  best test that the posting layer is correct.

---

## 7. Seed chart of accounts

Packers-and-movers specific. Seed as `is_system = true` for every new org at `create-org`
time. Codes are deliberately sparse to leave room for tenant additions.

**Assets (1000–1999)**
```
1000  Cash in Hand
1011  Bank — Current Account
1100  Accounts Receivable
1110  TDS Receivable
1200  Input CGST
1201  Input SGST
1202  Input IGST
1300  Vehicles
1310  Accumulated Depreciation — Vehicles   (contra)
1320  Packing Equipment
1400  Security Deposits
1500  Prepaid Insurance
```

**Liabilities (2000–2999)**
```
2000  Accounts Payable
2100  Customer Advances
2200  Output CGST
2201  Output SGST
2202  Output IGST
2210  RCM Payable
2300  TDS Payable
2400  Salary Payable
2410  PF Payable
2420  ESI Payable
2500  Porter / Agent Commission Payable
2600  Claims Payable
```

**Equity (3000–3999)**
```
3000  Owner's Capital
3100  Drawings
3200  Retained Earnings
```

**Income (4000–4999)**
```
4000  Freight Income
4010  Packing Charges
4020  Loading / Unloading Charges
4030  Transit Insurance Income
4040  Storage / Warehousing Income
4050  Unpacking / Rearrangement
4100  Other Income
4900  Discounts Allowed          (contra-income)
4910  Rounding Off
```

**Direct expenses (5000–5999)**
```
5000  Vehicle Hire / Lorry Freight
5010  Fuel & Diesel
5020  Toll & Parking
5030  Driver Batta / Allowance
5040  Loading / Unloading Labour
5050  Packing Materials Consumed
5060  Porter / Agent Commission
5070  Transit Insurance Premium
5080  Claims & Damages
5090  Warehouse Rent
```

**Indirect expenses (6000–6999)**
```
6000  Salaries & Wages
6010  PF / ESI Employer Contribution
6020  Office Rent
6030  Telephone & Internet
6040  Marketing & Advertising
6050  Software Subscriptions
6060  Professional Fees
6070  Bank Charges
6080  Vehicle Maintenance
6090  Vehicle Insurance
6100  Depreciation
6200  Miscellaneous Expenses
```

---

## 8. Migration order

One migration per step. Arun reviews and runs each before the next is written.

1. `chart_of_accounts` + seed function + `create-org` hook + delete-protection trigger
2. `accounting_periods` + period-lock helper
3. `journal_entries` + `journal_lines` + all constraints + deferred balance trigger + RLS
4. `fn_post_journal()` and `fn_reverse_journal()` — **no source triggers yet**
5. Posting triggers, **one migration per source module**, in this order:
   invoices → money receipts → vendor bills → vendor payments → trip expenses →
   claims → payroll → general expenses
6. Reporting views: `trial_balance_view`, `general_ledger_view`, `pnl_statement_view`,
   `balance_sheet_view`, `order_pnl_gl_view`
7. `fn_post_opening_balances()` RPC for tenants onboarding with existing books

Step 5 is deliberately fragmented so one bad recipe doesn't block the rest.

RLS on all three tables follows the existing pattern: `org_id in (select current_org_ids())`.
`journal_entries` and `journal_lines` are **insert-only** for application roles — no UPDATE,
no DELETE policy at all.

---

## 9. Test gate

Before any posting trigger is considered done:

1. Post one transaction of each recipe in §5 against a scratch org.
2. `select sum(debit) - sum(credit) from journal_lines where org_id = …` must be exactly `0`.
3. Trial balance must balance per account type: assets = liabilities + equity + (income −
   expenses).
4. Edit a source row; confirm reversal + repost, and that the trial balance still nets to zero.
5. Soft-delete a source row; confirm reversal only, no orphan entry.
6. Attempt a deliberately unbalanced insert; confirm it is rejected at COMMIT, not silently
   accepted.
7. `order_pnl_gl_view` for a test order must match the existing operational P&L view to the
   paisa. Investigate any difference before proceeding — that is the reconciliation test and
   it is the most informative one in this list.

Report §9.7's result explicitly. If the two P&L figures disagree, stop and report rather than
adjusting either side to match.
