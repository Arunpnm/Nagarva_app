# Nagarva Document Field Specification

**Source:** Four live APC documents supplied as reference — LR/Consignment Note, Quotation, Tax Invoice, Money Receipt.
**Purpose:** These are what an established packers-and-movers operation actually issues. Nagarva's document generator must produce equivalents. This is the field-level target.

**Status:** Reference spec, not a build brief. Sections marked **[SCHEMA GAP]** need columns that do not exist yet.

---

## 0. Shared header block — every document

| Field | Source | Present in Nagarva? |
|---|---|---|
| Company logo | `organizations.logo_url` | ✅ |
| Company name | `organizations.name` | ✅ |
| Tagline | `organizations.tagline` | ✅ (migration 006) |
| Full address | `organizations.address/city/state/pincode` | ✅ (006) |
| GSTIN | `organizations.gstin` | ✅ |
| PAN | `organizations.pan` | ✅ (006) |
| Multiple phone numbers | — | **[SCHEMA GAP]** — APC prints 4 |
| Landline | — | **[SCHEMA GAP]** |
| Website | `organizations.website` | ✅ (006) |
| Email | `organizations.support_email` | ✅ (006) |
| **UDYAM / MSME number** | — | **[SCHEMA GAP]** |
| **"Affiliated By: Govt Of Karnataka"** | — | **[SCHEMA GAP]** |
| **Branch list line** | — | **[SCHEMA GAP]** — "Branch: Chennai, Bengaluru, Coimbatore & Hyderabad" |
| Authorised signatory image | `organizations` branding | ⚠️ verify org-scoped |
| Footer: "computer-generated document" + query phone | static + org phone | — |

**Add to `organizations`:** `phone_secondary`, `phone_tertiary`, `landline`, `udyam_no`, `affiliation_text`, `branch_list_text`, `signatory_image_url`.

---

## 1. LR / Consignment Note

The most field-heavy document, and the one Nagarva's current version is furthest from.

### 1.1 Four separate copies

APC issues **Driver · Consignor · Consignee · Transporter** copies. Identical body, different label in a prominent box. Nagarva generates one.

**Required:** copy-type selector on generation, label rendered top-right.

### 1.2 Header fields

| Field | Notes |
|---|---|
| LR No | `lr_register.lr_no` — APC format `2026/0013` (FY/serial), not `LR-0001`. Match the format. |
| LR Date | `lr_register.lr_date` |
| Move From / Move To | place names, not full addresses |
| Vehicle No | `lr_register.vehicle_no` |

### 1.3 NOTICE block

Fixed legal paragraph about delivery only to the named consignee with written authorisation. **[SCHEMA GAP]** — needs to be tenant-editable boilerplate, not hardcoded. Store in `app_settings` under category `documents`, key `lr_notice_text`.

### 1.4 Risk & insurance panel — titled "AT OWNER'S RISK" or "AT CARRIER'S RISK"

| Field | Status |
|---|---|
| **Risk type** (Owner's Risk / Carrier's Risk) | **[SCHEMA GAP]** — add `lr_register.risk_type` |
| Material Insured (yes/no) | `insurance_policies` exists |
| Insurance Company | `insurance_policies.insurer_name` ✅ |
| Policy Number | `insurance_policies.policy_no` ✅ |
| Insurance Date | `insurance_policies.coverage_start` ✅ |
| Insured Amount | `insurance_policies.declared_value` ✅ |
| Distance (km) | `orders.distance_km` ✅ |
| Driver name + mobile | `lr_register.driver_name/driver_phone` ✅ |

### 1.5 Consignor / Consignee blocks

Name · Mobile · **GST No (prints "N/A" when absent)** · full address with city, state **with state code in brackets** — `Tamil Nadu (33)` — and pincode.

State code already exists as `organizations.state_code`; consignor/consignee state codes need adding to `lr_register`. **[SCHEMA GAP]**

### 1.6 Freight panel — three columns

`Paid` · `To Pay` · `To Be Billed`. Only one carries a value.

`lr_register.freight_mode` exists (`paid | to_pay | tbb`) — render as a three-column grid with the amount under the active mode.

### 1.7 Packages & goods

| Field | Status |
|---|---|
| Goods description | ✅ default "Old and Used Household Goods For Personal Usage Only, Not For Sale" |
| No. of packages | `lr_register.package_count` ✅ |
| **Actual weight** | `lr_register.actual_weight_kg` ✅ |
| **Charged weight** | `lr_register.charged_weight_kg` ✅ |
| Remark | `lr_register.remarks` ✅ |

### 1.8 Demurrage schedule

"Demurrage charge after more than 5 days @ ₹500 per day + handling & local transportation charges."

**[SCHEMA GAP]** — `demurrage_free_days` and `demurrage_rate_per_day` in `app_settings`, printed as a sentence.

### 1.9 Freight details breakdown

Basic Freight · Loading Charge · Unloading Charge · S.T. Charge · Other Charge · **LR/CN Charge** · Subtotal · GST @18% · Total

`LR/CN Charge` is a new charge head — add to the 15 in `rate_card_charges`. **[SCHEMA GAP]**

### 1.10 Right panel

Goods Value · Inv No. + Date (links LR to invoice) · **GST Paid By: Consignor/Consignee** **[SCHEMA GAP]** — add `lr_register.gst_payable_by` (exists) and render it.

### 1.11 Signatures

Authorised signatory image + "Consignor's Signature" space. Declaration paragraph above.

---

## 2. Quotation

### 2.1 Header

| Field | Status |
|---|---|
| Quotation No | format `2026/0042` |
| Quotation Date | ✅ |
| **Packing Date** | **[SCHEMA GAP]** |
| **Delivery Date** | **[SCHEMA GAP]** |
| **Moving Date** | `orders.move_date` ✅ |
| Customer name, phone, **email** | ✅ |
| **Moving Type** (House Hold Goods) | ✅ service |
| **Load Type** (Full Load / Part Load) | **[SCHEMA GAP]** |
| **Vehicle Type** (Dedicated / Shared) | **[SCHEMA GAP]** |
| **Transport mode** (By Road / Rail / Air) | **[SCHEMA GAP]** |

Three distinct dates matter operationally — packing, moving and delivery are different days on an outstation job.

### 2.2 Move From / Move To panels

Address · City · State · Pincode · Country · **Floor (2nd/1st)** · **Is Lift Available: Yes/No**

Floor exists. `has_lift` exists on `customer_addresses` but not on the order. **[SCHEMA GAP]** — add `from_has_lift` / `to_has_lift` to `orders`.

### 2.3 Charge table

Freight · Packing Charge · Un Packing Charge · Loading Charge · Un Loading Charge · Packing Material Charge → **Sub Total** → SGST (9%) · CGST (9%) → **FOV/Insurance Charge @3% on declared value** → **Total Amount** → **Total in words**

**FOV is a percentage-of-declared-value line** — the rate card supports `percent` as a unit, so this is configuration, not schema. Declared value must print in the label: `@3% On Declaration Value Of Goods (150000/-)`.

**Amount in words** is required on quote, invoice and receipt. Needs an Indian-numbering converter (lakh/crore, not million). **[SCHEMA GAP]** — utility function.

### 2.4 Survey questions

"Is there easy access for loading & unloading?" · "Are there any restrictions?" — Yes/No each. **[SCHEMA GAP]** — belongs in the survey payload.

### 2.5 Bank details block

Beneficiary Name · Bank Name · A/C No · IFSC · UPI ID · PhonePe/GPay number.

`organizations.upi_id` exists (006). **[SCHEMA GAP]** — `bank_name`, `bank_account_no`, `bank_ifsc`, `beneficiary_name` on `organizations`.

### 2.6 Moving items list — page 2

Sr No · Goods Description · Quantity · Value INR · Remark, with a **Total quantity** row (APC: 34 items).

This is the survey inventory rendered onto the quote. `surveys.rooms` holds it. **The item list must flow through to the quotation PDF** — currently it doesn't.

### 2.7 Terms & Conditions — page 3

Twelve clauses covering scope exclusions, liability, insurance advice, **80% advance on booking**, storage availability, notice period, wooden packing, gold/cash exclusion, **24% interest after 15 days**, payment favour.

**[SCHEMA GAP]** — tenant-editable, stored in `app_settings` under `documents/quotation_terms`. Must not be hardcoded; every vendor's terms differ.

---

## 3. Tax Invoice

Largely what Nagarva builds, plus:

| Field | Status |
|---|---|
| Bill No | format `2026/0027` |
| Billing Date | ✅ |
| **LR No cross-reference** | ✅ via `orders.lr_id` — must print |
| Delivery Date | **[SCHEMA GAP]** |
| Vehicle No | ✅ |
| Bill To block (separate from Move From) | **[SCHEMA GAP]** — billing party can differ from consignor |
| Package count | ✅ |
| Total Weight/Volume | ✅ |
| **HSN/SAC Code** | prints `-` in APC; Nagarva should print **996719** |
| Payment Remark | **[SCHEMA GAP]** |
| Remark | ✅ |
| **Reverse Charge: YES/NO** | **[SCHEMA GAP]** — GST requirement |
| GST Paid By | **[SCHEMA GAP]** |
| **PAID watermark when settled** | **[SCHEMA GAP]** — diagonal green stamp |
| **Customer signature + name + phone + date/time** | ✅ `document_signatures` (widened in 007) — must print the captured signature with a timestamp |
| Amount in words | **[SCHEMA GAP]** |
| Bank details block | **[SCHEMA GAP]** |

---

## 4. Money Receipt

Simplest, and closest to complete.

| Field | Status |
|---|---|
| Receipt No | format `2026/0024` |
| Date | ✅ |
| "Received with thanks from M/s." + name | ✅ |
| Phone | ✅ |
| **"Towards Final Payment of Bill No." + bill no + bill date** | **[SCHEMA GAP]** — link receipt to invoice |
| From / To | ✅ |
| **Payment mode** (UPI/Cash/Bank) | ✅ `payment_entries.mode` |
| **Transaction reference numbers** | ✅ `payment_entries.reference` (added 001) — APC prints three comma-separated |
| Amount in words | **[SCHEMA GAP]** |
| Amount in figures, large | ✅ |
| Branch list line | **[SCHEMA GAP]** |

**Note:** APC's receipt shows three UPI transaction IDs on one receipt — a receipt can cover multiple payment entries. Nagarva's model is one receipt per payment. Decide whether to support consolidated receipts.

---

## 5. Consolidated schema gaps

### `organizations`
`phone_secondary` · `phone_tertiary` · `landline` · `udyam_no` · `affiliation_text` · `branch_list_text` · `signatory_image_url` · `bank_name` · `bank_account_no` · `bank_ifsc` · `beneficiary_name`

### `orders`
`packing_date` · `delivery_date` · `load_type` · `vehicle_type` · `transport_mode` · `from_has_lift` · `to_has_lift` · `billing_party_name` · `billing_party_address` · `payment_remark` · `reverse_charge`

### `lr_register`
`risk_type` · `consignor_state_code` · `consignee_state_code` · `lr_cn_charge` · `goods_value` · `copy_type` (generation-time, not stored)

### `app_settings` (category `documents`)
`lr_notice_text` · `demurrage_free_days` · `demurrage_rate_per_day` · `quotation_terms` · `receipt_footer_text`

### `rate_card_charges`
Add `lrCnCharge` as a 16th head.

### Utility
Indian-numbering amount-to-words converter (lakh/crore).

---

## 6. Numbering format correction

APC uses **`FY/serial`** — `2026/0013`, `2026/0042`, `2026/0027`, `2026/0024`.

Nagarva's `next_doc_number` currently produces `INV-0001`. The `number_series` table already has `prefix`, `suffix` and `padding`, so this is configuration: set `prefix = '2026/'` and `padding = 4`.

**Decision needed:** match APC's format, or keep the prefixed form. APC's is what Indian transporters and GST filings expect to see. Recommend matching.

---

## 7. Priority

**Tier A — blocks a legally correct invoice**
HSN/SAC 996719 · Reverse Charge flag · amount in words · Bill To block · bank details

**Tier B — blocks a usable LR**
Four copy types · risk type · freight three-column panel · demurrage schedule · NOTICE text · GST Paid By

**Tier C — quote completeness**
Three dates · load/vehicle type · lift availability · item list on the PDF · T&C page · FOV line

**Tier D — polish**
PAID watermark · UDYAM/affiliation · branch list · consolidated receipts
