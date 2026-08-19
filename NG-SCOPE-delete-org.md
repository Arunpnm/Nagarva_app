# Scope — `delete_org(p_org_id)` tenant deletion

**Status: BUILT, HANDED BACK UNRUN (18 Aug 2026).**
- `supabase/20260818_delete_org.sql` — the function.
- `supabase/functions/admin-delete-org/index.ts` — the Edge Function that
  completes the job (auth users + storage). **Not deployed.**

Arun runs the dry run first, on the test org. Nothing has been deleted by
this session — the first real run is his, deliberately.

Three changes he made to the scope below, now reflected in the code:
1. **`invite_codes` joins the keep list** — the code is his issuance
   record (which IPAMTOA member, whether used), which is *his* data, not
   the tenant's. The reference is nulled, the row survives. (It has no
   `org_id` column, so it never appears in the coverage check; the
   function handles it explicitly.)
2. **auth.users and Storage are in this pass, not a later one** — "a
   tenant delete that leaves the owner's email in auth.users hasn't
   erased anything that matters legally."
3. **The coverage check is mandatory**, not optional.

Original scope follows. Written at Arun's request,
after an orphaned `expenses` row (left by a test-org cleanup) revealed
that only **12 of 116** org-scoped tables carry a foreign key on
`org_id` — so deleting a tenant today strands rows across the other 104
silently.

Arun's decision: **do not add 104 foreign keys.** One tested function
beats 104 constraints each with its own failure mode. The function is
needed regardless for the pre-launch wipe, for real churn when a vendor
leaves, and for DPDP erasure requests.

Nothing here runs until the table list and order below are approved.

---

## 1. What is NOT deleted, and why

Nine tables are deliberately excluded. These are the ones where deleting
alongside the tenant destroys the very record that exists to survive the
tenant.

| Table | Why it stays |
|---|---|
| `audit_log` | Erasing the audit trail with the tenant defeats its purpose. If a deletion is ever disputed — by the vendor, or by a regulator — this is the only record of what happened. |
| `consent_records` | Proof of what the vendor consented to, and when. Needed *because* they left, not despite it. |
| `data_requests` | The erasure request itself. Deleting it removes the evidence that erasure was lawfully requested. |
| `erasure_log` | The record of what was erased. Self-defeating to erase. |
| `breach_incidents` | Statutory retention; a breach record outlives the account it concerned. |
| `billing_events` | What they were charged and when. Needed for accounting, disputes and tax records long after churn. |
| `platform_invoices` | **Nagarva's own** revenue records — not the tenant's data. Deleting these destroys your books, not theirs. |
| `org_subscriptions` | Subscription history behind those invoices. |
| `org_usage` | Aggregate usage backing billing disputes. |

**The distinction that matters:** DPDP erasure covers the vendor's
*personal and business data*, not the platform's lawful records of the
commercial relationship. `platform_invoices` is Nagarva's financial
record; `orders` is the vendor's data. Those are different things and
this list keeps them apart.

**Design consequence:** these nine reference `org_id` for an org row
that will be gone. That's intentional and must not be "fixed" later by
adding FKs to them — an FK would force either cascade (destroying the
records) or restrict (making deletion impossible). Keep them
FK-free and treat the dangling `org_id` as a historical marker.

Two of them (`audit_log`, `erasure_log`) should receive a **new row
recording the deletion itself**, written by the function before it
returns.

---

## 2. Cycles — why a plain ordered delete is not enough

Three foreign-key cycles exist among the org-scoped tables. A pure
topological sort is impossible; any implementation that assumes one will
fail on real data.

1. **`customers` ↔ `rate_cards`**
   `customers.rate_card_id` → `rate_cards`, `rate_cards.customer_id` → `customers`
2. **`claims` ↔ `complaints`**
   `claims.complaint_id` → `complaints`, `complaints.claim_id` → `claims`
3. **`orders` ↔ `quotations` ↔ `customer_surveys` ↔ `lr_register` ↔ `eway_bills` ↔ `insurance_policies`** (six-table cycle)
   `orders.quotation_id`/`lr_id`/`eway_bill_id`/`insurance_policy_id`,
   `quotations.survey_id`, `customer_surveys.converted_to_order_id`,
   and the reverse `*.order_id` columns.

**Resolution: break the cycles first with targeted `UPDATE ... SET <fk>
= NULL`, then delete in order.** Verified 18 Aug 2026 that **all 15
columns involved are nullable**, so this works without schema changes:

```
orders.quotation_id, orders.lr_id, orders.eway_bill_id,
orders.insurance_policy_id, orders.contract_id, orders.trip_id,
quotations.survey_id, customer_surveys.converted_to_order_id,
claims.complaint_id, complaints.claim_id,
customers.rate_card_id, rate_cards.customer_id,
insurance_policies.order_id, eway_bills.order_id, lr_register.order_id
```

Do NOT reach for `session_replication_role = 'replica'` or deferred
constraints instead. Both disable integrity checking wholesale for the
session, which turns a bug in this function into silent corruption
rather than a loud failure.

---

## 3. Delete order — 109 tables, children first

Computed by Tarjan SCC + Kahn's algorithm over the live FK graph, not by
hand. Cycle members (marked ⟳) are deleted as a group after their FKs
are nulled.

```
 1 account_transfers          38 notification_log            75 grn
 2 activities                 39 notification_tokens         76 purchase_orders
 3 tasks                      40 notification_prefs          77 materials
 4 addons                     41 notifications               78 storage_billing_cycles
 5 app_settings               42 number_series               79 storage_items
 6 attendance                 43 onboarding_progress         80 storage_jobs
 7 backup_registry            44 order_item_counts           81 warehouses
 8 bank_statement_lines       45 order_staff                 82 surveys
 9 bank_statements            46 order_tracking              83 tds_entries
10 claim_items                47 order_vendors               84 vendor_payments
11 claims ⟳                   48 org_members                 85 bank_accounts
12 complaints ⟳               49 org_pin_attempts            86 vendor_bills
13 credit_notes               50 payment_entries             87 transactions
14 customer_addresses         51 receipts                    88 trip_expenses
15 customer_contacts          52 pod_records                 89 trip_orders
16 discount_policies          53 pricing_config              90 vehicle_service_logs
17 document_signatures        54 purchase_order_items        91 vehicle_trips
18 documents                  55 quote_approvals             92 customer_surveys ⟳
19 eway_consolidated          56 quote_outcomes              93 eway_bills ⟳
20 eway_vehicle_updates       57 quote_versions              94 insurance_policies ⟳
21 expenses                   58 rate_card_charges           95 lr_register ⟳
22 export_jobs                59 rate_card_floor_charges     96 orders ⟳
23 follow_up_logs             60 rate_card_multipliers       97 quotations ⟳
24 reminders                  61 rate_card_rules             98 staff
25 gst_returns                62 referrals                   99 trips
26 job_expense_float_entries  63 retention_policies         100 vehicles
27 job_expense_floats         64 reviews                    101 vendors
28 job_photos                 65 salary_payments            102 contracts
29 order_status_history       66 saved_reports              103 wa_messages
30 journal_lines              67 settings                   104 wa_contacts
31 journal_entries            68 sla_events                 105 leads
32 chart_of_accounts          69 staff_advance_entries      106 customers ⟳
33 account_groups             70 payslips                   107 rate_cards ⟳
34 ledger_entries             71 payroll_runs               108 lead_sources
35 lr_copies                  72 staff_advances             109 wage_rate_defaults
36 lr_series                  73 staff_invites
37 marketing_spend            74 stock_movements
```

Then finally `organizations` itself.

**This order is derived, not authored.** If the schema gains a table or
an FK, it must be recomputed rather than patched by hand — the function
should ideally assert its own coverage (see §6).

---

## 4. Signature and dry-run

```sql
delete_org(p_org_id uuid, p_dry_run boolean default true)
returns table(table_name text, rows_affected bigint)
```

- **`p_dry_run` defaults to TRUE.** Calling it with one argument
  reports and changes nothing. Deleting requires deliberately typing
  `false` — the destructive path is never the default.
- Dry run returns exactly the same rows the real run would delete, by
  `count(*)`-ing each table with the same predicate, in the same order.
- Real run wraps everything in a single transaction: all tables, or
  none. A partial tenant deletion is worse than none.
- Returns one row per table with a non-zero count, plus a final
  `('TOTAL', n)`, so the caller sees a receipt rather than a bare "ok".

---

## 5. Safety guards

1. **Refuse `plan_status = 'active'`** unless a `p_force` flag is passed.
   A paying tenant should never be deletable by a typo'd uuid.
2. **Refuse the APC org id outright** (`11111111-1111-4111-8111-111111111111`),
   force flag or not. It is tenant #1 and the owner's live business; no
   automated path should be able to remove it.
3. **`security definer`, and callable only by a platform admin**
   (`is_platform_admin()`), never by an org owner. A vendor deleting
   their own tenant is a support request, not a button.
4. **Write the audit row before deleting**, not after — if the
   transaction fails the audit entry rolls back with it, but if the
   process dies mid-way the intent is already recorded.

---

## 6. Known gaps this function will NOT cover

Flagging now so they aren't discovered during a real erasure request.

- **Supabase Auth users.** The owner's `auth.users` row and every staff
  shadow user (`staff-<uuid>@staff.nagarva.in`) live outside these
  tables. They need `auth.admin.deleteUser()` from an Edge Function —
  SQL alone cannot do it. **For a DPDP erasure this is the part that
  actually matters most**, since it holds the email address.
- **Storage objects.** `organizations.logo_url` and any uploaded files
  point at Supabase Storage buckets, which this function does not touch.
- **`platform_settings` / `invite_codes`.** Not org-scoped, but
  `invite_codes.used_by_org_id` will dangle. Harmless; worth nulling.
- **Coverage drift.** The 109-table list is a snapshot. The function
  should compare its own list against
  `information_schema.columns where column_name='org_id'` at runtime and
  RAISE if a table exists that it doesn't know about — otherwise the
  next migration silently reintroduces exactly the orphan problem this
  was built to solve.
