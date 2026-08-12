# Claude Code Kickoff — Tier 2, Session 3: Document Generation

**Repo:** `Arunpnm/Nagarva_app` · **DB:** `hqqcapifefsaqvotqvlt` (001–009 applied)
**Reference:** `nagarva_document_field_spec.md` — full field-level target
**Scope:** bring the four core documents up to what an established operator actually issues.

---

## Why this before remaining parity work

Documents are what the customer receives. A vendor can work around a rough lead screen; they cannot hand their accountant an invoice that fails GST scrutiny. Three items here are statutory, not cosmetic.

The spec was derived from four **live APC documents** supplied as reference — a real LR, quotation, tax invoice and money receipt from a working packers-and-movers business. That is the bar.

---

## What migration 009 gave you

All of this exists in the database now. Verified against the live schema.

**`organizations`** — `phone_secondary/tertiary/quaternary`, `landline`, `udyam_no`, `affiliation_text`, `branch_list_text`, `signatory_image_url`, `signatory_name`, `beneficiary_name`, `bank_name`, `bank_account_no`, `bank_ifsc`, `upi_display_number`

**`orders`** — `packing_date`, `delivery_date`, `load_type`, `vehicle_type`, `transport_mode`, `from_has_lift`, `to_has_lift`, `billing_party_*` (4), `hsn_sac_code` (defaults `996719`), `reverse_charge`, `payment_remark`

**`lr_register`** — `risk_type`, consignor/consignee `state`/`state_code`/`pincode`, `basic_freight`, `loading_charge`, `unloading_charge`, `st_charge`, `lr_cn_charge`, `gst_pct`, `gst_amount`, `goods_value`, `invoice_no`, `invoice_date`, `material_insured`, `insurer_name`, `policy_no`, `insurance_date`, `insured_amount`, `distance_km`

**`quotations`** — three dates, `load_type`, `vehicle_type`, `transport_mode`, floors, lift flags, `declared_value`, `fov_pct`, `fov_amount`, `easy_access`, `access_restrictions`, `access_notes`

**`surveys`** — the same access/floor/lift/declared-value fields, since that is where they are captured

**New tables** — `lr_copies` (one row per generated copy type), `receipts` (groups several `payment_entries` under one receipt number)

**New function** — `amount_in_words(numeric)` returns Indian numbering. Verified: `44620` → `Forty Four Thousand Six Hundred and Twenty Rupees Only`. Use it; do not write a Dart equivalent.

**`app_settings`** category `documents` — 8 seeded keys per org: `lr_notice_text`, `demurrage_free_days`, `demurrage_rate_per_day`, `demurrage_text`, `goods_description_default`, `invoice_note`, `doc_footer_text`, `quotation_terms`

**Numbering** — `number_series` prefixes now `2026/` with padding 4 for invoice, proforma, receipt, quotation, credit_note, debit_note, voucher. `lr_series` likewise. Allocate via `next_doc_number()` / `next_lr_number()` — never read-then-write.

---

## 1. Shared header — build once, use everywhere

Every document carries the same block. Build a single widget/builder, not four copies.

Top strip: `affiliation_text` left, `udyam_no` right.
Then: logo · company name · tagline · full address · GSTIN · PAN · all phone numbers comma-separated · landline · website · email.
Money receipt additionally prints `branch_list_text`.

Footer on every document: `doc_footer_text` from settings, then "For Any Query contact us: {phones}".

**All of it reads from `organizations`.** Nothing hardcoded, nothing falling back to APC values — this is a multi-tenant product and branding leaks have caused incidents before.

---

## 2. LR / Consignment Note

The furthest from target. Currently one plain copy.

### 2.1 Four copies

Generate **Driver · Consignor · Consignee · Transporter**. Identical body; the copy name prints in a bordered box, large, right side under the LR panel.

Offer "generate all four" as one action producing four PDFs. Record each in `lr_copies` with `copy_type` and `pdf_url`.

### 2.2 Layout

Three-column band under the header:

| Left | Centre | Right |
|---|---|---|
| **NOTICE** — `lr_notice_text` from settings | **AT OWNER'S RISK** / **AT CARRIER'S RISK** per `risk_type` | **LR / CONSIGNMENT NOTE** |

Centre panel rows: Material Insured · Insurance Company · Policy Number · Insurance Date · Insured Amount · Distance · Driver name + mobile.

Right panel: Lr No · Lr Date · Move From · Move To · Vehicle No, then the copy-type box.

### 2.3 Consignor / Consignee

Name · Mobile · **GST No — print `N/A` when empty, never blank** · address, then `{city}, {state} ({state_code}) - {pincode}`.

The bracketed state code is a GST convention. Do not omit it.

### 2.4 Freight — three columns

`Paid` · `To Pay` · `To Be Billed`. The amount sits under whichever `freight_mode` is set; the other two show `--`.

### 2.5 Packages, remark, demurrage

Goods description (default from `goods_description_default`) · No. of Packages · Actual vs Charged weight side by side · Remark.

Demurrage sentence built from `demurrage_text` with `{days}` and `{rate}` substituted.

### 2.6 Freight details

Basic Freight · Loading · Unloading · S.T. Charge · Other Charge · LR/CN Charge · Subtotal · GST @{gst_pct}% · **Total**. Empty lines print `--`, not `0`.

Right of it: Goods Value · Inv No. + Date · **GST Paid By: {gst_payable_by}**.

### 2.7 Foot

Declaration paragraph, authorised signatory image + company name, and a "Consignor's Signature" space.

---

## 3. Quotation — three pages

### Page 1
Header · QUOTATION title · Quotation No. in a boxed accent chip · customer name, phone, email · Moving Type, Load Type, Vehicle Type, transport mode · four dates right-aligned (Quotation, Packing, Delivery, Moving) · greeting paragraph naming from and to.

Move From / Move To panels: address, city, state, pincode, country, **Floor**, **Is Lift Available: Yes/No**.

Charge table: numbered rows, only non-zero heads · **Sub Total** · SGST/CGST or IGST · **FOV/Insurance Charge @{fov_pct}% On Declaration Value Of Goods ({declared_value}/-)** · **Total Amount** · **Total Amount In Words** via `amount_in_words()`.

### Page 2
The two access questions with Yes/No · bank details block · UPI line · the `invoice_note` warning · authorised signatory and a receiver's-signature box · **Moving Items table**: Sr No, Goods Description, Quantity, Value INR, Remark, with a **Total quantity** row.

That item table comes from the survey inventory. `surveys.rooms` holds it. **This is the piece most likely to be missing** — the survey data must flow onto the quotation PDF.

### Page 3
`quotation_terms` from settings, rendered as bullets. Tenant-editable — never hardcode.

---

## 4. Tax Invoice

Closest to done. Add:

- **BILL (TAX INVOICE)** title bar
- Bill No · Billing Date · **Lr No cross-reference** · Delivery Date · Vehicle No
- **Bill To** block, distinct from Move From — falls back to the customer when `billing_party_name` is null
- Move From / Move To side by side
- Package count · Total Weight/Volume · **HSN/SAC Code — print `996719`**
- Payment Remark · Remark · insurance charge sentence
- Particulars column right side with the same heads as the quote
- **GST Paid By** and **Reverse Charge: YES/NO**
- **Total Freight In Words**
- Customer signature from `document_signatures` with name, phone, and **date & time**
- Bank details block
- **PAID watermark** — diagonal, green, semi-transparent, only when `payment_status = 'paid'`

---

## 5. Money Receipt

- Title **MONEY RECEIPT**, centred
- Receipt No. left, Date right
- "Received with thanks from M/s." + name, Phone No.
- **"Towards Final Payment of Bill No." {invoice_no} "Dated" {invoice_date}** — use "Part Payment" when `is_final = false`
- From / To
- "as per details by" {mode} · "No." {reference_nos}
- Amount in words, full width
- **Amount in figures, large** — `Rs. 44620.00/-`
- Authorised signatory

Support the consolidated case: a receipt can cover several `payment_entries`. Use the `receipts` table; join `payment_entries.receipt_id`.

---

## Constraints

- Read every tenant value from `organizations` / `app_settings`. **No hardcoded company details.**
- Use `amount_in_words()` from the database, not a Dart reimplementation
- Allocate numbers via `next_doc_number()` / `next_lr_number()` only
- All queries through `current_org_ids()`
- `orders.id` is TEXT — `::text` casts on joins
- Every generation writes `audit_log`
- Complete file replacements
- `flutter analyze` clean before each commit

---

## Acceptance criteria

- [ ] Shared header renders from `organizations` with zero hardcoded values
- [ ] All four LR copies generate and record in `lr_copies`
- [ ] LR panel title switches on `risk_type`
- [ ] GST No prints `N/A` when absent; state code in brackets
- [ ] Freight three-column panel reflects `freight_mode`
- [ ] Demurrage sentence built from settings
- [ ] LR freight breakdown includes LR/CN Charge; blanks show `--`
- [ ] Quotation renders all three pages
- [ ] Survey item inventory appears on quotation page 2 with a quantity total
- [ ] FOV line shows percentage and declared value in the label
- [ ] Terms render from `app_settings`, not code
- [ ] Invoice prints HSN/SAC 996719, Reverse Charge, GST Paid By
- [ ] Bill To falls back to customer when no billing party set
- [ ] PAID watermark only when paid
- [ ] Captured signature prints with name, phone, date and time
- [ ] Amount in words on quotation, invoice and receipt via the SQL function
- [ ] Receipt links to invoice number and date
- [ ] Consolidated receipts supported
- [ ] Document numbers come from the series allocators
- [ ] Two tenants produce two different-looking documents — verify with a second org

---

## Report back

1. Files replaced
2. Whether `surveys.rooms` had a usable shape for the quotation item table, or needs a transform
3. Any field in the spec with no data source — flag rather than invent
4. Whether PDF page-break handling holds when the item list runs long
