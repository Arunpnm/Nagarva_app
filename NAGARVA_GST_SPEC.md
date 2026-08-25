# Nagarva — GST Treatment & Display

## Implementation spec for Quotation and Invoice

**Date:** 25 August 2026
**Reference:** Packers Bilty quotation screen (GST show/hide, GST %, GST type, total show/hide)
**Status:** Specification. No code written, no migration run.

---

## 1. Current live state

Verified by introspection of `hqqcapifefsaqvotqvlt`, not from memory or documentation.

### What exists

| Table | Column | Type | Default | Note |
|---|---|---|---|---|
| `quotations` | `gst_pct` | numeric | **5** | Reference UI defaults to 18 |
| `quotations` | `gst_amount` | numeric | 0 | |
| `quotations` | `subtotal` | numeric | 0 | |
| `quotations` | `total` | numeric | 0 | |
| `quotations` | `discount_pct` | numeric | 0 | |
| `quotations` | `discount_amount` | numeric | 0 | |
| `orders` | `quote_gst_pct` | numeric | — | |
| `orders` | `quote_gst_amount` | numeric | — | |
| `orders` | `quote_gst_mode` | text | — | **Already means intra/inter — see §1.2** |
| `orders` | `quote_subtotal` | numeric | — | |
| `orders` | `quote_total` | numeric | — | |
| `orders` | `hsn_sac_code` | text | `'996719'` | Correct SAC for P&M |
| `orders` | `billing_party_gstin` | text | — | |
| `organizations` | `gstin` | text | — | |
| `organizations` | `state` / `state_code` | text / integer | — | **Both NULL on both orgs — see §1.3** |

### 1.1 Legacy jsonb keys — the de facto current implementation

**Added 25 Aug 2026 after live introspection. The original §1 missed
these, and missing them made the §3 backfill wrong — see the correction
there.**

`quotations.charges` is a jsonb blob that already carries GST display
state. `survey_quote_page_widget.dart` writes it on every save:

| Key | Live values | Meaning |
|---|---|---|
| `_gstShowInPdf` | `"true"`, `"false"`, absent | **This is `gst_print` in all but name.** Whether GST figures print. |
| `_gstType` | `"auto"`, `"intra"`, absent | Maps to `gst_split`. `auto` = derive, `intra` = CGST/SGST. |
| `_billingMode` | jsonb object | Per-charge-head included/additional. Unrelated to GST; do not touch. |

Distribution across the 8 live rows: 4 rows (the oldest, `NGVQ-1001`
–`1003` and one 26 Jul row) have **all three absent** — they predate the
survey builder. The other 4 carry all three.

Two consequences:

1. **`_gstShowInPdf` is the authoritative source for `gst_print`**, not
   `gst_amount`. Two rows — `Test 1` (gst_amount 1440) and `Abi`
   (gst_amount 1540) — have `_gstShowInPdf: "false"`. They have real tax
   *and* deliberately suppressed display, a combination the original
   backfill rule could not represent.
2. The jsonb keys stay written after this feature ships. `quote_pdf.dart`
   and lead_detail's order snapshot read them, and pre-existing quotes
   have nothing else. Same reasoning as Item 12C's `_suggestedPackage`.

### What does not exist

- No column for GST **display** behaviour (show / rate-only / hidden)
- No column for GST **treatment** (exclusive / inclusive / exempt / extra)
- No column for **total show/hide** on PDF
- No **place of supply** state code on the order or quotation
- No per-charge-head GST rate (reference UI has a separate GST % on the insurance line)

### 1.2 Name collision warning

`orders.quote_gst_mode` is **already in use** and does not mean what this feature needs. Live values:

| Value | Rows |
|---|---|
| `'inter'` | 1 |
| `NULL` | 24 |

It currently encodes intra-state vs inter-state (i.e. CGST+SGST vs IGST). Do **not** repurpose it for display mode. Overloading it will produce a silent semantic collision that no analyzer will catch — the same failure class as the string-keyed `_tabs` lookups.

**Action:** rename it to `gst_split` for clarity, or leave it and add the new fields alongside. Do not reuse the name.

### 1.3 Blocker for IGST derivation

`organizations.state_code` is **NULL for both APC and Ponci**. Until org state code and a per-order place-of-supply state code are populated, CGST/SGST vs IGST cannot be derived and must fall back to a manual value with a visible warning.

---

## 2. Design principle

The reference UI's six options conflate **two independent dimensions**. Implementing them as a single six-value enum forces six special cases through the calculator, the quotation PDF, the invoice PDF, and the order conversion — and any seventh combination requested later becomes a new special case in all four places.

Model them as two orthogonal fields.

### Dimension A — `gst_treatment` (changes the arithmetic)

| Value | Meaning |
|---|---|
| `exclusive` | GST added on top of the taxable value. **Default.** |
| `inclusive` | The stated amount already contains GST; back-compute the tax component. |
| `exempt` | No GST charged. Supply is exempt; requires a stated reason. |
| `extra` | No GST in the total. Prints "GST extra as applicable". |
| `none` | No GST, no mention anywhere. |

Only `exclusive` and `inclusive` produce non-zero tax. `exempt`, `extra` and `none` are arithmetically identical and differ **only** in what is printed.

### Dimension B — `gst_print` (changes the PDF only)

| Value | Meaning |
|---|---|
| `full` | Rate and tax amount both shown. |
| `rate_only` | Rate shown, tax amount suppressed. |
| `note_only` | No figures; a declaration line only (e.g. "GST extra as applicable"). |
| `hidden` | Nothing about GST appears. |

### Mapping the reference UI

| Packers Bilty label | `gst_treatment` | `gst_print` |
|---|---|---|
| GST Charge Show In Quotation | `exclusive` | `full` |
| GST % Show & GST Charge Hide | `exclusive` | `rate_only` |
| Without GST Quotation | `none` | `hidden` |
| GST Exempted | `exempt` | `note_only` |
| GST Extra | `extra` | `note_only` |
| GST Included in Subtotal | `inclusive` | `full` |

All six reference behaviours are reproduced, with no special-casing, plus valid combinations the reference cannot express (e.g. inclusive + rate_only).

**UI note:** keep the single dropdown the user sees. Present the six familiar labels; store two fields. Users should not have to reason about two dimensions — the mapping table above is the presenter's job, not theirs.

---

## 3. Schema changes

All migrations to be reviewed and run by Arun. Nothing here is to be executed by an agent.

```sql
-- Quotations
alter table public.quotations
  add column gst_treatment    text not null default 'exclusive',
  add column gst_print        text not null default 'full',
  add column show_total_in_pdf boolean not null default true,
  add column gst_split        text,                    -- 'cgst_sgst' | 'igst'
  add column place_of_supply_state_code integer,
  add column taxable_value    numeric not null default 0,
  add column exempt_reason    text;

alter table public.quotations
  add constraint quotations_gst_treatment_chk
    check (gst_treatment in ('exclusive','inclusive','exempt','extra','none')),
  add constraint quotations_gst_print_chk
    check (gst_print in ('full','rate_only','note_only','hidden')),
  add constraint quotations_gst_split_chk
    check (gst_split is null or gst_split in ('cgst_sgst','igst')),
  add constraint quotations_exempt_reason_chk
    check (gst_treatment <> 'exempt' or exempt_reason is not null);
```

Mirror the same five columns onto `orders` with the `quote_` prefix so conversion carries the treatment through:

```sql
alter table public.orders
  add column quote_gst_treatment text default 'exclusive',
  add column quote_gst_print     text default 'full',
  add column quote_show_total_in_pdf boolean default true,
  add column quote_taxable_value numeric,
  add column quote_exempt_reason text,
  add column place_of_supply_state_code integer;
```

`orders.quote_gst_mode` stays as-is (intra/inter). Consider renaming to `quote_gst_split` in the same migration for consistency, updating the single live row.

### Backfill for the 8 existing quotations

**CORRECTED 25 Aug 2026. The original rule below was wrong and would
have changed two live documents.**

<details><summary>Original rule, kept for history — do not run</summary>

```sql
-- WRONG: derives gst_print from gst_amount.
update public.quotations
   set gst_treatment = case when coalesce(gst_amount,0) > 0
                            then 'exclusive' else 'none' end,
       gst_print     = case when coalesce(gst_amount,0) > 0
                            then 'full' else 'hidden' end,
       taxable_value = coalesce(subtotal,0) - coalesce(discount_amount,0)
 where gst_treatment is null or taxable_value = 0;
```

`Test 1` (gst_amount 1440) and `Abi` (gst_amount 1540) both carry
`_gstShowInPdf: "false"`. This rule sets them to `full`, which starts
printing GST on two quotations where it was deliberately hidden — the
exact defect §3's own closing sentence and test case 13 exist to
prevent.
</details>

**`gst_print` derives from `charges->>'_gstShowInPdf'`.** `gst_amount > 0`
is a fallback used *only* where the legacy keys are absent, which is the
four pre-builder rows:

```sql
update public.quotations q
   set gst_treatment = case
         -- Legacy rows never expressed inclusive/exempt/extra, so the
         -- only distinction recoverable is "was tax charged".
         when coalesce(q.gst_amount, 0) > 0 then 'exclusive'
         else 'none'
       end,
       gst_print = case
         -- Authoritative when present, including the real-tax-but-hidden
         -- combination the old rule could not represent.
         when q.charges->>'_gstShowInPdf' = 'true'  then 'full'
         when q.charges->>'_gstShowInPdf' = 'false' then 'rate_only'
         -- Fallback ONLY where the key is absent (pre-builder rows).
         when coalesce(q.gst_amount, 0) > 0 then 'full'
         else 'hidden'
       end,
       gst_split = case q.charges->>'_gstType'
         when 'intra' then 'cgst_sgst'
         when 'inter' then 'igst'
         else null            -- 'auto' and absent both mean "not decided"
       end,
       taxable_value = coalesce(q.subtotal, 0) - coalesce(q.discount_amount, 0);
```

**`false` maps to `rate_only`, not `hidden`.** The tax was genuinely
charged and is in the total; hiding it entirely would misrepresent an
`exclusive` quote as a `none` one, and `total` would no longer reconcile
against `taxable_value`. `rate_only` is the mode that means "tax exists,
figures suppressed", which is what the flag actually expressed.

`_gstType: 'auto'` maps to NULL rather than guessing a split — §6's rule
that a NULL state code must never silently become `cgst_sgst` applies
identically here.

Verify by re-rendering one existing quotation PDF before and after and confirming the totals are byte-identical. A backfill that changes a historical document's printed total is a defect, not a migration.

---

## 4. Calculation

**Order of operations matters and is non-negotiable:** discount applies to the taxable value *before* GST. The reference UI confirms this — its discount field is labelled "Applicable on Sub-Total Amount".

```
gross = sum(charge lines)
taxable_value = gross − discount_amount

if treatment = 'exclusive':
    tax_total = round(taxable_value × gst_pct / 100, 2)
    total     = taxable_value + tax_total

if treatment = 'inclusive':
    taxable_value = round(gross_after_discount / (1 + gst_pct/100), 2)
    tax_total     = gross_after_discount − taxable_value
    total         = gross_after_discount

if treatment in ('exempt','extra','none'):
    tax_total = 0
    total     = taxable_value
```

### The split — compute once, then halve

```
if gst_split = 'cgst_sgst':
    cgst = round(tax_total / 2, 2)
    sgst = tax_total − cgst        -- absorbs the odd paisa
    igst = 0
else:
    igst = tax_total
    cgst = sgst = 0
```

**Do not** compute CGST and SGST independently as `taxable × rate/2` each and add them. On odd amounts that produces a one-paisa discrepancy against `tax_total`, which is exactly the kind of mismatch a GST reconciliation flags.

### Rounding

Section 170 of the CGST Act requires the final tax amount to be rounded to the nearest rupee. Store `round_off` as its own field so the printed invoice reconciles:

```
round_off   = round(total) − total
final_total = round(total)
```

Never round intermediate values. Round once, at the end, and record the adjustment.

### Guard

`gst_pct` must be one of `0, 5, 12, 18, 28`. Enforce with a CHECK constraint, not only in the UI — the current default of `5` on `quotations` differs from the reference UI's `18`, and both are legitimate for P&M (5% applies to GTA supply without ITC, 18% to full-service shifting under SAC 996719). **Decide which is correct as the Nagarva default and set it deliberately**, rather than inheriting `5` by accident.

---

## 5. Document-type permission matrix

**This is the most important section. Do not copy the reference UI here.**

A tax invoice under Rule 46 of the CGST Rules must state the taxable value, the rate of tax, and the amount of tax charged. Several of the reference modes make that impossible. A quotation is a commercial document with no such constraint.

| Combination | Quotation | Tax Invoice |
|---|---|---|
| `exclusive` + `full` | ✅ | ✅ |
| `inclusive` + `full` | ✅ | ✅ |
| `exclusive` + `rate_only` | ✅ | ❌ tax amount is mandatory |
| `exempt` + `note_only` | ✅ | ⚠️ issue a **Bill of Supply**, not a tax invoice |
| `extra` + `note_only` | ✅ | ❌ tax must be stated, not deferred |
| `none` + `hidden` | ✅ | ❌ |
| `show_total_in_pdf = false` | ✅ | ❌ |

### Required behaviour

1. The quotation screen offers all six labels.
2. The invoice screen offers **only** `exclusive + full`, `inclusive + full`, and `exempt`.
3. On quote → invoice conversion, if the quotation's treatment is not invoice-legal, **block and prompt** rather than silently rewriting. The user chose "GST Extra" for a reason and must consciously convert it.
4. `exempt` on an invoice switches the document type to **Bill of Supply** and suppresses tax columns. This is a document-type change, not a print flag.
5. An invoice always prints the total. `show_total_in_pdf` is a quotation-only field.

Shipping the reference UI's control set unchanged on the invoice would let a tenant issue a non-compliant tax invoice. They would not discover it until a GST audit, and it would be Nagarva's defect, not theirs.

---

## 6. CGST/SGST vs IGST — derive, do not ask

The reference UI makes GST TYPE a manual dropdown. Do not copy this. Interstate moves are the highest-value jobs in this business and a manually-selected wrong tax type is a real filing error.

```
place_of_supply_state_code = destination state (services: place of supply
                             is the delivery location for goods transport)

gst_split = 'cgst_sgst'  when org.state_code = place_of_supply_state_code
          = 'igst'       otherwise
```

Show it **read-only** on the form with the derivation visible ("Karnataka → Tamil Nadu: IGST"). Allow a manual override only behind an explicit toggle that records who overrode it and why, into the audit log.

### Prerequisite — currently blocking

`organizations.state_code` is NULL for both live orgs. Until populated:

- Add `state_code` to org setup as a required field
- Backfill APC and Ponci (both Karnataka, code 29)
- Capture destination state on the quotation
- Until all three are done, `gst_split` falls back to manual with a visible "Verify tax type" warning on the form

**Do not derive silently from NULL.** A NULL state code defaulting to `cgst_sgst` would apply the wrong tax to every interstate move without any signal.

---

## 7. PDF rendering rules

| `gst_print` | Charge table | Total block |
|---|---|---|
| `full` | Taxable value, rate, CGST/SGST or IGST as separate lines | Full breakdown + round-off |
| `rate_only` | "GST @ 18%" with no amount column | Total only |
| `note_only` | Nothing in the table | Declaration line beneath the total |
| `hidden` | Nothing | Nothing |

Declaration text, by treatment:

- `exempt` → "Exempt supply under [reason]. Not liable to GST."
- `extra` → "GST extra as applicable."
- `inclusive` → "Total is inclusive of GST @ 18%."

Invoices additionally always print: HSN/SAC (`996719`), supplier GSTIN, recipient GSTIN if registered, place of supply when `igst`, and taxable value.

---

## 8. Out of scope — flag, do not build now

The reference screen shows a **separate GST % on the insurance charge line** (3% insurance, its own GST dropdown). That is per-line tax rates, not a document-level rate.

That is a materially larger change: `gst_pct` moves from the document to each charge line, the calculator aggregates per rate slab, and the PDF prints a rate-wise summary. It is also the correct model for GST — an invoice with mixed-rate lines legally requires a rate-wise breakup.

**Recommendation:** build the document-level model in this spec first. Design the schema so per-line rates are an extension (charge lines gain a nullable `gst_pct` that falls back to the document rate) rather than a rewrite. Do not build it now.

---

## 9. Test cases

Every case asserts against a stored quotation re-read from Postgres, not against in-memory state. Per the standing principle: verify by running.

| # | Input | Expect |
|---|---|---|
| 1 | ₹10,000, exclusive, 18%, intra | taxable 10,000 · CGST 900 · SGST 900 · total 11,800 |
| 2 | ₹10,000, exclusive, 18%, inter | taxable 10,000 · IGST 1,800 · total 11,800 |
| 3 | ₹11,800, inclusive, 18% | taxable 10,000 · tax 1,800 · total 11,800 |
| 4 | ₹10,000 less ₹1,000 discount, exclusive 18% | taxable 9,000 · tax 1,620 · total 10,620 |
| 5 | ₹10,000, exempt | tax 0 · total 10,000 · declaration printed · reason required |
| 6 | ₹10,000, extra | tax 0 · total 10,000 · "GST extra" printed |
| 7 | ₹10,000, none + hidden | total 10,000 · no GST text anywhere in PDF |
| 8 | ₹3,333, exclusive, 18%, intra | tax 599.94 → CGST 299.97 · SGST 299.97 · **sum equals tax exactly** |
| 9 | ₹10,001, exclusive, 5% | round_off recorded; printed total reconciles to the penny |
| 10 | Quotation with `extra` → convert to invoice | **blocked with prompt**, not silently rewritten |
| 11 | Quotation with `exempt` → convert | produces Bill of Supply, not tax invoice |
| 12 | Org `state_code` NULL | manual split + visible warning; never silent `cgst_sgst` |
| 13 | Existing pre-migration quotation | PDF total identical before and after backfill |

Case 8 catches the split-rounding bug. Case 13 catches a destructive backfill. Both are the ones most likely to be skipped and most expensive to find later.

---

## 10. Build order

1. Populate `organizations.state_code` (APC and Ponci = 29, Karnataka) and add it to org setup as required
2. Migration: new columns + CHECK constraints + backfill of the 8 existing quotations
3. Calculator with the five treatments, split-once-then-halve, and single final rounding
4. Unit tests — cases 1 through 9 — **before** any UI work
5. Quotation form: single dropdown, six labels, two stored fields
6. Quotation PDF: four print modes
7. Place-of-supply capture + `gst_split` derivation with the NULL warning
8. Invoice: restricted permission set + conversion guard (cases 10, 11)
9. Bill of Supply as a document type
10. Device verification: cases 12 and 13 on a real APK

Steps 1 and 2 return to Arun to run. No tier starts until the previous is device-verified.

---

*Grounded in live introspection of `hqqcapifefsaqvotqvlt` on 25 August 2026. Statutory references are to the CGST Act and CGST Rules as a general matter and should be confirmed with your CA before the invoice module ships — this overlaps register item 31, which is already awaiting that review.*
