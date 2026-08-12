# Claude Code Kickoff — Tier 2, Session 1: Order Details Parity

**Repo:** `Arunpnm/Nagarva_app` · **DB:** `hqqcapifefsaqvotqvlt` (migrations 001–006 applied)
**Reference:** `nagarva_master_parity_brief.md` §6
**Scope:** five confirmed-missing elements on Order Detail. No other screens.

Your own Step 4 sweep confirmed all five are absent from `lib/` — this is building them, not finding them.

---

## Read first

Migrations 001–006 added roughly 75 tables. Three matter here and did not exist when the master brief was written:

| Table | Why it matters |
|---|---|
| `addons` | Post-quote upsell. Rolls into Revenue (Final). |
| `order_vendors` + `vendor_bills` | Subcontractor cost. **Was invisible in APC's P&L.** |
| `stock_movements` | Materials consumed per order, at cost. |

This means **Nagarva's P&L can be more accurate than APC's**, which had no vendor or materials cost at all. Build for the real figure, not APC's approximation.

Also available: `next_doc_number(org, doc_type, branch, fy)` — atomic, row-locked. Use it for every document number. Do not roll your own counter.

---

## 1. Order P&L card

Placement: after the detail field table, before the Labour/Crew section.

### Rows

| Row | Source | Style |
|---|---|---|
| Quote Amount | `orders.quote_total` | plain |
| Add-ons (`n`) | `sum(addons.amount)` where status ≠ cancelled | plain, omit row if zero |
| **Revenue (Final)** | quote + add-ons | green, bold |
| Staff Salary (`n` staff) | order's crew salary total | red negative, `—` if zero |
| Order Expenses (`n` items) | `expenses` for this order + `orders.field_expenses` jsonb | red negative, `—` if zero |
| Vendor Cost (`n`) | `sum(vendor_bills.total_amount)` for this order | red negative, omit if zero |
| Materials (`n`) | `sum(abs(value))` from `stock_movements` where `order_id` and type = `consumption` | red negative, omit if zero |
| Porter Commission | see below | red negative, only when `order_source = 'porter'` |
| **Net Profit** | Revenue − all costs | bold, large, health dot |

### Porter commission — computed, never stored

```
local:      revenue × 0.16
outstation: revenue × 0.19
```
Keyed off `orders.order_type`. Missing this silently overstates profit on every Porter job.

### Health dot

🟢 margin ≥ 25% · 🟡 10–25% · 🔴 < 10% or negative. Compute against Revenue (Final).

### Gating

Whole card behind `canActive('reports', 'view')`. **Absent, not disabled** — a supervisor sees no card.

### Refresh

Recompute after any write to: addons, expenses, field expenses, crew salary, vendor bills, stock movements, payments. Single fan-out invalidation.

---

## 2. Quick Payment Update

Placement: after the P&L card.

Renders only when `orders.payment_status <> 'paid'` **and** `canActive('orders', 'edit')`.

- Header `QUICK PAYMENT UPDATE`
- `Balance due: ₹{revenue_final − orders.paid_total}` — use `paid_total`, not `advance_paid`
- Numeric field, placeholder `New payment ₹`
- `Save & Receipt` **disabled until a valid amount > 0 is entered**

On save, in one transaction:
1. Insert `payment_entries` (amount, mode, `account_id` — default cash account from `bank_accounts` where `is_default`)
2. Update `orders.paid_total`; set `payment_status` to `partial` or `paid`
3. Generate the money receipt using `next_doc_number(org, 'receipt', branch, fy)`
4. Insert `ledger_entries` — party_type `customer`, party_id `orders.customer_id`, entry_type `payment`, credit = amount
5. Invalidate order detail, orders list, payments list, P&L

**Over-collection:** if amount > balance, warn and require explicit confirmation. Do not silently accept.

---

## 3. Duplicate Order

Placement: utility row in the documents section. Purple outline, label `⧉ Copy`. Gated `canActive('orders', 'create')`.

**Clone:** customer, customer_id, phone, from/to, addresses, floors, amount, order_type, distance, service, branch, order_source, rate_card_id, contract_id.

**Reset:** date → null, status → `pending`, `advance_paid` → 0, `paid_total` → 0, `payment_status` → `pending`, vehicle_no/driver blank, supervisor_id null, invoice_no null, lr_no null, eway fields null, `job_otp` null, `supervisor_status` null.

**Set:** notes → `Copy of {source_id}`, new id via your existing NGV-XXXX generator.

**Improvement over APC:** APC creates the copy then tells you to go set the date. Ask for the move date in the same dialog. Toast: `Order {newId} created`.

---

## 4. Documents grid

Placement: bottom, above Delete. Wrapping grid.

| Document | `doc_type` for numbering | Signature companion |
|---|---|---|
| 📄 Tax Invoice | `invoice` | ✍️ |
| 🧾 Money Receipt | `receipt` | ✍️ |
| 📋 Proforma | `proforma` | — |
| 🚛 LR / Bilty | (uses `lr_series`) | ✍️ |
| 📦 Packing List | — | — (item modal first) |
| 🔢 Loading Slip | — | — (item modal first) |
| 🚗 Vehicle Condition | — | — |
| 💳 Payment Voucher | `voucher` | ✍️ |

### Signature companion

Opens a standalone signature pad. Captured signature is held and applied to the **next** document generated. While held, show `✅ Customer signature captured — will appear on next document`.

**Improvement over APC:** APC discards the signature after one document. Persist it to `document_signatures` against the order so every document for that order can carry it. Clear only on explicit user action.

### Packing List / Loading Slip

Open an item-entry modal first (`Add all items being packed`), then generate. One shared modal, type switched.

### LR / Bilty

Writes a row to `lr_register` (migration 003), numbered from `lr_series`. Populate consignor/consignee from the customer record, and link `eway_bill_id` if one exists.

### Tax Invoice

Number via `next_doc_number(org, 'invoice', branch, fy)`. Write `invoice_no`, `invoice_issued_at`. SAC 996719. IGST vs CGST+SGST auto-detect from state codes. This feeds `gstr1_b2b_view` — if `customer.gstin` is set it lands in B2B, otherwise B2C.

### Utility row

| Button | Action |
|---|---|
| 📋 Copy UPI | Copy `organizations.upi_id`, toast |
| 💸 Send Pay Link | WhatsApp with UPI, balance, order ref |
| 🔗 Copy Track Link | Copy `{origin}?track={orderId}` |
| ⧉ Copy | Duplicate Order (§3) |

Copy UPI and Send Pay Link hidden when `payment_status = 'paid'`.

**Fix APC's defect:** the FAB covers the last utility button and Delete. Add bottom padding = FAB height + 16dp.

---

## 5. Mark Order Complete

Placement: in the Crew section, below the labour list. Full-width green.

Distinct from the operations stepper — this closes the order **financially**.

On tap:
1. If `revenue_final − paid_total <> 0` → **hard warning** naming the outstanding amount. Require explicit confirm.
2. If no invoice issued → warn.
3. On confirm: status → `closed`, stamp `closed_at`, lock the P&L.
4. Invalidate order detail, orders list, dashboard KPIs.

Gated `canActive('orders', 'edit')`.

---

## Constraints

- Complete file replacements, not patches
- `orders.id` is TEXT — `::text` casts on every join
- All queries through `current_org_ids()`
- Every write logs to `audit_log` with `old_value` / `new_value` / `changed_fields` (columns added in migration 005)
- No new SQL — the schema is complete for this session. If you think something is missing, report it rather than writing a migration.
- `flutter analyze` clean before each commit

---

## Acceptance criteria

- [ ] P&L card renders with all applicable rows; zero-value optional rows omitted
- [ ] Vendor cost and materials consumption included — not just labour and expenses
- [ ] Porter commission at 16% local / 19% outstation, only when `order_source = 'porter'`
- [ ] Health dot matches the margin thresholds
- [ ] P&L absent (not greyed) without `reports.view`
- [ ] P&L recomputes after every cost-affecting write
- [ ] Quick Payment hidden when paid or without `orders.edit`
- [ ] Balance uses `paid_total`
- [ ] Save disabled until valid amount
- [ ] Payment writes entry, updates order, generates numbered receipt, posts to ledger
- [ ] Over-collection requires explicit confirmation
- [ ] Duplicate clones and resets exactly per §3, asks for the date inline
- [ ] All 8 documents generate; 4 signature companions work
- [ ] Signature persists to `document_signatures` for the order
- [ ] Packing List and Loading Slip open the item modal first
- [ ] LR writes to `lr_register` with a series-allocated number
- [ ] Invoice uses `next_doc_number`, sets SAC 996719, correct GST mode
- [ ] All 4 utility buttons work; pay buttons hidden when paid
- [ ] Nothing obscured by the FAB
- [ ] Mark Order Complete hard-warns on non-zero balance
- [ ] Audit entries written with before/after values

---

## Report back

1. Files replaced
2. Anything in the schema that turned out insufficient
3. Anything already present that this spec assumed missing
4. Whether the P&L cost sources all had usable data, or some are structurally empty until other modules ship
