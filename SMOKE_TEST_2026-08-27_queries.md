# Full-flow smoke test — DB verification queries

Companion to the 34-step device run, 27 Aug 2026. Drive the UI on the
device; run these after each phase to check what actually landed.

Project: `hqqcapifefsaqvotqvlt`. Disposable test data.

## Org ids — paste once, reuse

```sql
select slug, id::text from organizations order by created_at;
```

Referred to below as `<TN>`, `<KA>`, `<AP>`.

---

## PHASE 0 — staff isolation

**NOTE: the column is `staff.branch` (text), NOT `branch_id`.** It is the
composite natural key `(org_id, branch) -> branches(org_id, name)`.

```sql
select o.slug, s.name, s.role, s.branch, s.active,
       s.pin_hash is not null as has_pin
from staff s join organizations o on o.id = s.org_id
order by o.slug, s.name;
```

**Expect 6 rows, exactly 2 per org.** `has_pin` true for anyone whose PIN
you set. Any name appearing under the wrong slug is a cross-tenant leak
and the run stops there.

---

## PHASE 1 — lead

```sql
-- step 3: follow-up logged?
select l.customer, l.status, l.branch, l.survey_data is not null as has_survey,
       (select count(*) from follow_up_logs f where f.lead_id = l.id) as follow_ups
from leads l where l.org_id = '<TN>';
```

Expect status `follow_up`, branch set, `follow_ups >= 1`.
After step 5, `has_survey` true.

---

## PHASE 2 — quote + prefix test 1

```sql
select doc_type, prefix, last_number, fy from number_series
where org_id = '<TN>' and doc_type = 'quotation';
```

**Expect `last_number` 0 -> 1.** Compare against the number on screen.

`next_doc_number` returns `prefix || lpad(n, padding) || suffix` — so the
FY is **not** in the number. Expect **`TN/0001`**, not `TN/2026-27/1`.
If the screen shows an FY segment, something is prepending it (that was a
real bug once — see CLAUDE.md, migration 009).

```sql
-- step 8/9: did a signature row appear despite the dead link?
select id, document_type, status, expires_at from document_signatures
where org_id = '<TN>';

select quotation_no, total, signature_png is not null as signed,
       signer_name, signed_at
from quotations where org_id = '<TN>';
```

Expect `signed` false, `signer_name`/`signed_at` NULL. A
`document_signatures` row MAY still exist — minting the token succeeds
even though the page cannot serve it. Record which.

---

## PHASE 3 — order + supervisor

```sql
select id, customer, status, branch, quotation_id is not null as from_quote,
       supervisor_id is not null as has_supervisor, assigned_at
from orders where org_id = '<TN>';
```

`id` must be TEXT in `NGV-XXXX` form.

```sql
select s.name, os.salary_amount
from order_staff os join staff s on s.id = os.staff_id
where os.org_id = '<TN>';

-- step 14
select order_id, completion_method, received_by_name,
       signature_data is not null as has_signature, created_at
from pod_records where org_id = '<TN>';
```

`has_signature` true — this path works, unlike the quote signature.

---

## PHASE 4 — expenses

```sql
select 'expenses' t, count(*) n from expenses where org_id='<TN>'
union all select 'job_expense_float_entries', count(*)
  from job_expense_float_entries where org_id='<TN>'
union all select 'ledger_entries', count(*) from ledger_entries where org_id='<TN>'
union all select 'journal_lines', count(*) from journal_lines where org_id='<TN>';
```

Step 17 asks WHICH the approval wrote to. If both are 0, approval posts
nothing — record that as the finding rather than hunting for it.

```sql
-- do the journals balance?
select je.id, sum(jl.debit) as dr, sum(jl.credit) as cr,
       sum(jl.debit) - sum(jl.credit) as diff
from journal_entries je join journal_lines jl on jl.journal_entry_id = je.id
where je.org_id = '<TN>' group by je.id having sum(jl.debit) <> sum(jl.credit);
```

**Any row returned is an unbalanced entry.** Empty result = balanced.

---

## PHASE 5 — vehicle + mileage

```sql
select 'vehicles' t, count(*) n from vehicles where org_id='<TN>'
union all select 'vehicle_trips', count(*) from vehicle_trips where org_id='<TN>'
union all select 'trips', count(*) from trips where org_id='<TN>'
union all select 'trip_expenses', count(*) from trip_expenses where org_id='<TN>'
union all select 'vehicle_service_logs', count(*) from vehicle_service_logs where org_id='<TN>';
```

`vehicle_trips` is 1:1 with an order; `trips` is the separate part-load
model. Note which the UI wrote to — they are different features.

**Mileage: there is no mileage engine.** NG-019 is unbuilt (`grep mileage
lib/` returns nothing). If a figure appears on screen it is computed
inline somewhere; if none appears, that is expected, not a failure.

---

## PHASE 6 — accounts

```sql
select 'chart_of_accounts' t, count(*) n from chart_of_accounts where org_id='<TN>'
union all select 'payment_entries', count(*) from payment_entries where org_id='<TN>'
union all select 'receipts', count(*) from receipts where org_id='<TN>'
union all select 'staff_advances', count(*) from staff_advances where org_id='<TN>';
```

**`chart_of_accounts` is NOT in `create_org_with_owner`'s seed list** —
only `number_series`, `document_settings`, `pricing_config` and
`default_branch`. Expect **0** unless the UI seeds it on first open.

```sql
select doc_type, prefix, last_number from number_series
where org_id='<TN>' and doc_type='receipt';
```

Expect `TN/0001`, counter 0 -> 1.

---

## PHASE 7 — invoice + prefix isolation (the main event)

```sql
-- after EACH invoice
select doc_type, prefix, last_number from number_series
where doc_type='invoice' and org_id in ('<TN>','<KA>','<AP>');
```

| after | TN | KA | AP |
|---|---|---|---|
| 1st TN invoice | 1 | **0** | **0** |
| 2nd TN invoice | 2 | **0** | **0** |
| 1st KA invoice | 2 | **1** | **0** |

**KA must be 0 until you raise one there.** Any movement in KA or AP
while working in TN is the isolation failure this whole phase exists to
catch.

```sql
select id, invoice_no, invoice_issued_at, total from orders
where org_id in ('<TN>','<KA>') and invoice_no is not null;
```

### What the invoice header will show

`organizations.phone / address / state / state_code` are **all NULL** in
every org. `OrgProfile` falls back to `settings.business_profile`, which
is also empty post-wipe. So expect **blanks**, not placeholders — and
blank is the correct behaviour. If a fake `+91 44 XXXX XXXX` appears, it
is hardcoded somewhere and that is a finding.

**GST split with `state_code` NULL:** the app decides interstate vs
intrastate from a city->state lookup defaulting unknown cities to Tamil
Nadu. A Chennai->Bengaluru move is genuinely interstate, so **IGST is
correct**. If it renders CGST/SGST, note it — that is the contradiction
`20260825_gst_treatment_and_display.sql` (still UNRUN) exists to fix.

---

## PHASE 8 — P&L

```sql
select o.slug,
  (select coalesce(sum(x.total),0) from orders x
    where x.org_id=o.id and x.invoice_no is not null) as invoiced,
  (select coalesce(sum(e.amount),0) from expenses e where e.org_id=o.id) as expenses,
  (select coalesce(sum(sa.amount),0) from staff_advances sa where sa.org_id=o.id) as advances
from organizations o order by o.created_at;
```

**A staff advance is a receivable, not an expense.** If P&L subtracts it,
that is a real finding.

Cross-check the KA P&L shows only its single invoice.

---

## Final: every document number generated

```sql
select o.slug, ns.doc_type, ns.prefix, ns.last_number
from number_series ns join organizations o on o.id = ns.org_id
where ns.last_number > 0 order by o.created_at, ns.doc_type;
```

Anything with `last_number > 0` in an org you did not work in is a leak.
