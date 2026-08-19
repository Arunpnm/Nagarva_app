# Scope — Item 27, Warehousing & storage billing

**Status: SCOPED, NOT BUILT.** 18 Aug 2026. Business rules from Arun;
schema facts read from the live database, not the brief.

---

## 0. The headline: most of this already exists, and three parts of it
## contradict your rules

Four tables are already in the schema — `warehouses`, `storage_jobs`,
`storage_items`, `storage_billing_cycles`. They were built speculatively
(0 rows, no UI, no Dart classes) and were on the "leave for their own
module" list in the Item 11 sweep. That module is now this one.

**What they get right, and saves real work:**

- `storage_items` has **per-item `in_date` and `out_date`**. This is the
  single most important thing — it is exactly the primitive partial
  release needs, and it means your 40-items/15-released example is
  computable without any schema change.
- `storage_jobs` already has `handling_in_charge`, `handling_out_charge`,
  `security_deposit`, `order_id`, `customer_id`, `warehouse_id`, and full
  soft-delete columns.
- `storage_billing_cycles` already models **billing periods** —
  `period_start`, `period_end`, `billable_days`, `invoice_no`, `status`,
  `invoiced_at` — which is the monthly-while-stored shape you asked for.

**What contradicts your rules and must change:**

1. **`storage_jobs.rate` is a single rate for the whole job**, with
   `billing_mode` as `per_day | per_month`. You want **item-wise rates**.
   One rate per job cannot express that. The rate has to move down to
   the item (or to an item-type rate card the item resolves against).
2. **`storage_jobs.min_billing_days` exists.** You said no minimum
   period, daily pro-rata from day 1. I'd default it to 0 and never
   surface it — but flagging it rather than silently ignoring it,
   because a column named that will tempt a future session to enforce
   it.
3. **`storage_billing_cycles.rate` and `billable_days` are single
   scalars.** With item-wise rates and partial release, one cycle has
   *many* rates and *many* day-counts. A cycle needs child lines, not
   two numbers.

Missing outright: an **insurance charge** column (there's
`insurance_policy_id` and `declared_value`, but no chargeable amount),
and on `warehouses`, **ownership and monthly rent** — nothing there
tracks the cost of a rented warehouse.

---

## 1. Your question: nightly job or on-demand accrual?

**On-demand from movement history — with one exception that matters.**

Your instinct is right, and the reason is stronger than "a missed job
under-bills". The deeper problem is that a nightly job makes the
*accrual* the source of truth, when the actual source of truth is the
movement history. Those drift the moment anything is recorded late.

Concretely: an item is released on the 8th but the office records it on
the 12th. With on-demand accrual, correcting `out_date` to the 8th fixes
every figure instantly, because every figure is derived. With a nightly
job you have four days of already-accrued rows that are now wrong, and
you need detection-and-replay logic to fix them — which is a second
system to get right.

The computation is a pure function of facts you already store:

```
billable_days(item, period) =
    least(coalesce(item.out_date, period_end + 1), period_end + 1)
  - greatest(item.in_date, period_start)
```

`out_date` is **exclusive** — the release date itself is not billed,
which is what "accrual drops from the release date" means. Checking it
against your example, a 31-day month, 40 items in before the 1st, 15
released on the 12th:

- the 25 that stayed: `31 + 1 − 1 = 31`… no — they run the whole month, but your figure of 20 days applies to the *post-release* segment. Splitting it the way you'd bill it: days 1–11 all 40 items (**11 days × 40**), days 12–31 the remaining 25 (**20 days × 25**). The formula produces exactly that: the released 15 get `12 − 1 = 11` days, the retained 25 get `32 − 1 = 31` days, and `31 = 11 + 20`. Same money, expressed per item rather than per segment.

**Cost:** a sum over that job's items per view. At realistic volume —
tens of live jobs, hundreds of items — this is a few hundred rows and
completely free. It only becomes a question at thousands of concurrent
stored lots, which is years away and would be solved with a materialised
view, not a cron.

**The exception: freeze at invoice time.** Pure on-demand has one real
flaw — an invoice you already sent could silently change if someone
edits an `in_date` months later. So:

- **Un-invoiced periods**: always computed live. Nothing stored.
- **At invoice generation**: snapshot the computed lines into
  `storage_billing_cycles` + a new `storage_billing_cycle_lines`, and
  from then on that period reads from the snapshot, never recomputes.

That gives live accuracy where it helps and immutability where it's
legally required. A correction after invoicing becomes a credit note —
the same way every other invoice in this system already works.

---

## 2. Your question: how this reuses existing plumbing

| Concern | Reuses | Notes |
|---|---|---|
| **Invoice numbering** | `next_doc_number(org, 'invoice', null, fy)` | Same series as every other invoice, per your rule. **Inherits the March 2027 FY-rollover dependency** — storage invoices break that morning too. |
| **Customer** | `storage_jobs.customer_id → customers` | Already wired. |
| **Invoice PDF** | `InvoicePdf` + `PdfBranding`/`OrgProfile` | Storage lines render as ordinary charge lines. |
| **Soft delete** | `storage_jobs` already has all three columns | Add to `kSoftDeleteTables` **and** `_kBins` — the assertion added 17 Aug will fail loudly if only one is done. |
| **Org/branch scoping** | `OrgScope` + the branch RLS from Item 30 | `warehouses.branch` already exists. |
| **Plan enforcement** | Item 32's `enforce_org_writable()` | `storage_jobs` needs adding to 32b's trigger list — a locked tenant shouldn't book new storage. |
| **Item-wise rate card** | `pricing_config.config` jsonb | Same decision as Item 12: `config.storage_rates` as `[{item_type, rate_per_day}]`, editable in the same Survey & Pricing screen. No new tables. |

**Two places reuse does NOT work cleanly, and both need your call:**

1. **`payment_entries.order_id` is text and references `orders`.** A
   storage deposit or a storage invoice payment has no order. Either add
   a nullable `storage_job_id` to `payment_entries`, or require every
   storage job to have a shadow order (bad — it would pollute order
   counts, plan limits and P&L). I'd add the column.

2. **GST SAC code.** Transport is 996719, hardcoded as `kGstSac`.
   **Warehousing/storage is a different SAC** and I'm not going to
   invent the number. This needs your CA, and it makes SAC a per-charge
   value rather than one app-wide constant.

---

## 3. Your question: does storage link back to a move order?

**Yes, and it already does** — `storage_jobs.order_id` exists.

It must stay **nullable**: walk-in storage with no move is a real case,
and forcing a fake order to satisfy a foreign key would corrupt order
counts, monthly plan limits and P&L. When it *is* set, the storage job
should surface on Order Details as its own section, next to Documents
and Payment History.

Worth noting the sequencing this implies: storage usually *follows* a
shifting job, so the natural entry point is a "Move to storage" action
on a delivered order, pre-filling customer, items and CFT from the order
— not a blank storage form the office re-keys.

---

## 4. Schema changes needed

```
storage_items       + rate_per_day numeric        -- item-wise, frozen at check-in
                    + item_type text              -- resolves against the rate card
storage_jobs        + insurance_charge numeric    -- separate line, not bundled
                    + deposit_adjusted numeric    -- how much of the deposit is used
                    ~ min_billing_days            -- default 0, never surfaced
warehouses          + ownership text              -- owned | rented
                    + monthly_rent numeric        -- rented cost, for margin
NEW storage_billing_cycle_lines
                      cycle_id, storage_item_id, item_name, qty,
                      rate_per_day, billable_days, amount
payment_entries     + storage_job_id uuid null    -- see §2
pricing_config      config.storage_rates jsonb    -- item-type rate card
```

**Rates freeze at check-in.** `storage_items.rate_per_day` is copied
from the rate card when the item is checked in, not looked up at billing
time — exactly the lesson from Item 12's 0-CFT bug and the
suggested/chosen columns. Editing the rate card must never retroactively
change what a stored lot is being billed.

---

## 5. "What's in storage right now"

The daily operational view, two cuts off one query
(`storage_items where out_date is null`):

- **Per customer** — lots, item count, days stored so far, accrued
  charge to date, deposit held.
- **Per warehouse** — occupancy as `sum(cft)` against
  `warehouses.capacity_cft`, which already exists, plus a rented-vs-owned
  margin line (storage revenue accrued this month against
  `monthly_rent`).

That second one is the answer to your margin question, and it's why
`ownership`/`monthly_rent` are in §4 rather than deferred.

---

## 6. Open decisions for you

1. **Storage SAC code** — needs your CA (§2).
2. **Monthly billing date** — calendar month-end for everyone, or each
   lot billed on its own check-in anniversary? Calendar month-end is
   simpler and matches how a vendor thinks about a billing run; anniversary
   billing spreads the work but complicates the "what do I invoice today"
   question.
3. **Insurance charge basis** — flat per lot, per month, or % of
   `declared_value`? `declared_value` exists, so % is available.
4. **Does a partial release trigger an interim invoice**, or does it just
   change the accrual until the next monthly run? Your rules imply the
   latter; confirming because it changes the release UI.
5. **`min_billing_days`** — confirm I should default it to 0 and hide it,
   rather than dropping the column.

---

## 7. Phasing

- **27A — records and the live view.** Warehouses CRUD (with ownership
  and rent), check-in/check-out with per-item dates, the "in storage now"
  screens, accrued-to-date display. No invoicing. This is most of the
  operational value.
- **27B — billing.** Cycles, monthly invoice generation through
  `next_doc_number`, deposit adjustment, final settlement, credit notes
  for post-invoice corrections.
- **27C — margin and photos.** Rented-warehouse cost against revenue;
  condition photos at check-in/out, which **depends on Items 14+15's
  photo plumbing** and should not be attempted before it.

27A is the natural first build and is independently useful — a vendor
can run storage operations off it while still invoicing manually.
