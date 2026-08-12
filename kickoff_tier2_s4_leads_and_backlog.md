# Claude Code Kickoff — Tier 2, Session 4: Lead Details Parity + Remaining Backlog

**Repo:** `Arunpnm/Nagarva_app` · **DB:** `hqqcapifefsaqvotqvlt` (001–010 applied)
**Scope:** Session 4 is Part A only. Parts B and C are the ordered backlog — work through them in sequence without waiting for a new brief between each.

---

# PART A — Lead Details parity  (this session)

The last confirmed APC parity gap. Small compared to Sessions 1–3.

## A1. Detail field table

Label left, value right, divider between each, `—` for null. **Render every row even when empty** — the dash tells the user the field exists.

Route · From · To · Floor (`{from}F → {to}F`) · Date · Service · Package · Packing · Source · Branch

## A2. Auto-creation note

When the lead has a note, render it as a left-bordered blockquote under the field table:

> Auto-created from WhatsApp reply. First message: "[unsupported]"

Nothing when null — no empty container, no placeholder.

## A3. Status chips — freely tappable

Unlike orders, lead status moves in **any** direction with one tap.

| Key | Label | Colour |
|---|---|---|
| `new` | New Lead | `#95A5A6` |
| `followup` | Follow Up | `#3498DB` |
| `survey` | Survey Done | `#9B59B6` |
| `quoted` | Quoted | `#E67E22` |
| `confirmed` | Confirmed | `#2ECC71` |
| `lost` | Lost | `#E74C3C` |

- Immediate write, no dialog — **except `Lost`**, which confirms and captures an optional reason into `quote_outcomes` (`outcome: 'lost'`, `reason_code`, `reason_note`, `competitor_name`, `competitor_price` — table exists from migration 004).
- Backward movement allowed.
- Current chip filled and non-tappable.
- Remove any separate "Mark as lost" link.
- Pipeline stepper becomes a visual mirror of chip state.
- Gate on `canActive('leads', 'edit')`.

## A4. Quick contact row — missing entirely

| Button | Style | Action |
|---|---|---|
| WhatsApp | Green filled | Opens WhatsApp to `lead.phone` with the tenant's lead-opening template |
| Call | Blue outlined | `tel:` intent |

Both disabled when phone is null or malformed. The phone number in the lead header is also tappable.

## A5. Confirm Order (Skip Survey) — highest-risk item

Must succeed **from any status, with no survey and no quote present.**

- Do not block on null `quote_id`.
- Do not block on no survey.
- Opens the minimal order sheet pre-filled from lead fields.
- On success: create the order, set lead status `confirmed`, link `lead.order_id`, navigate to the order.
- **Call `findOrCreateCustomer` so `orders.customer_id` is set at creation** — same helper Quick Payment uses. Do not leave it null.

Verify explicitly on a brand-new lead with zero survey and zero quote data.

## A6. Retain

`Create Quote`, `Build Detailed Quote` and `Send for Signature` move **into** the Survey & Quote card as secondary actions rather than top-level buttons. DOC/PDF export icons stay.

## A7. Acceptance

- [ ] All detail rows render, `—` for nulls
- [ ] Auto-creation note conditional
- [ ] Six chips tappable in both directions
- [ ] `Lost` captures reason into `quote_outcomes`
- [ ] Pipeline mirrors chip state without manual refresh
- [ ] Leads list reflects new status on back-navigation
- [ ] **Confirm Order succeeds with null quote and no survey**
- [ ] New order has `customer_id` populated
- [ ] WhatsApp and Call work; disabled on null phone
- [ ] Quote actions reachable from the Survey & Quote card

---

# PART B — Stub modules  (next, in this order)

Four routes currently render `ComingSoonPage`. Each is self-contained.

## B1. Customer Surveys (`surveys`)

`customer_surveys` table exists (29 columns, token-based). Gives `Send Customer Survey Link` a destination.

- List: customer, submitted date, linked lead, status
- Detail: room-by-room inventory, CFT totals, photos, special instructions
- Actions: `Open in Survey & Quote`, `Attach to Lead`, `Convert to Order`, `Discard`
- Unreviewed badge count on the nav item

## B2. Reviews (`reviews`)

`reviews` table exists (migration 001).

- Request sender — WhatsApp template with `organizations.google_review_url`, triggered from an order at `delivered`/`closed`
- Collected list with rating, comment, order reference
- Filter by rating and branch
- Auto-trigger N hours after `delivered`

## B3. WA Inbox (`inbox`)

`wa_contacts` and `wa_messages` exist (migration 001). Source of auto-created leads.

- Conversation list: contact, last message, unread badge, linked lead/order chip
- Thread view, inbound and outbound
- Free-text and template send
- Auto-create lead on first inbound; unparseable media records `[unsupported]`
- Per-conversation mute, mirroring the order-level `wa_muted`

## B4. Survey & Quote standalone (`survey`)

Currently reachable only from a lead.

- Start with no lead (walk-in)
- CFT catalogue management — item master, per-item CFT, categories
- Cross-lead quote list with status filters
- Accepts a `navLead` param for deep-linking from the lead screen

---

# PART C — New modules from migrations 003–009

Ordered by dependency. Schema is complete for all of these; none need new SQL.

| # | Module | Tables | Note |
|---|---|---|---|
| 1 | **Materials** | `materials`, `stock_movements`, `purchase_orders`, `grn`, `low_stock_view` | Consumption feeds order P&L. Trigger keeps `materials.quantity` in step. |
| 2 | **Rate cards** | `rate_cards`, `rate_card_rules/charges/floor_charges/multipliers` | Turns survey CFT into an auto-quote. Default card seeded with 16 charge heads. |
| 3 | **LR register** | `lr_register`, `lr_series`, `lr_copies`, `pod_records` | Searchable register behind the LR document. |
| 4 | **Operations standalone** | `order_tracking`, `complaints` | Two tabs. Tracking entries update order status via a label map. |
| 5 | **Accounts depth** | `chart_of_accounts`, `journal_entries/lines`, `bank_accounts`, `ledger_entries`, `trial_balance_view` | 36 accounts seeded. Journal enforces balance via deferred trigger. |
| 6 | **Vendors** | `vendors`, `order_vendors`, `vendor_bills`, `vendor_payments` | Subcontractor cost — already feeds the P&L card. |
| 7 | **Customers** | `customers`, `customer_addresses/contacts`, `customer_360_view` | 29 rows back-filled. LTV, repeat rate, outstanding. |
| 8 | **Insurance & claims** | `insurance_policies`, `claims`, `claim_items` | Full workflow: intimated → survey → assessed → settled. |
| 9 | **Trips** | `trips`, `trip_orders`, `trip_expenses`, `trip_pnl_view` | Part-load consolidation with per-order cost allocation. |
| 10 | **Calendar** | orders + leads by date | Drag to reschedule. |
| 11 | **Reports** | all the `_view` objects | XLSX and PDF export. |
| 12 | **Tasks & activities** | `tasks`, `activities` | Polymorphic across every entity. |
| 13 | **E-Way Bill** | `eway_bills`, `eway_vehicle_updates`, `eway_consolidated` | **Needs NIC API credentials** — schema mirrors the payload. Legal requirement above ₹50,000. |
| 14 | **GST returns** | `gst_returns`, `gstr1_b2b_view`, `gstr1_b2c_view`, `itc_register_view` | Export JSON/CSV for the portal. |
| 15 | **Payroll** | `payroll_runs`, `payslips`, staff PF/ESI columns | Attendance → earnings → deductions → payslip. |
| 16 | **Storage** | `warehouses`, `storage_jobs`, `storage_items`, `storage_billing_cycles` | Recurring billing revenue stream. |
| 17 | **Contracts** | `contracts`, `sla_events` | Corporate accounts with SLA tracking. |
| 18 | **Tenant billing** | `org_subscriptions`, `platform_invoices`, `org_usage`, `billing_events` | Vendor self-service view, upgrade, pay. Blocks SaaS launch. |

---

## Standing rules

- Complete file replacements
- `orders.id` is TEXT — `::text` casts on joins
- Everything through `current_org_ids()`
- Every write logs to `audit_log` with before/after
- Gate every screen and destructive action via `canActive(module, action)`
- Read tenant values from `organizations` / `app_settings` — never hardcode
- **No SQL execution.** Hand over a migration file if schema is genuinely missing.
- `flutter analyze` clean before each commit — but remember it cannot catch string-keyed route or tab lookups. After any rename touching `_tabs`, a route name or a nav key, grep the string across `lib/`.
- Commit and **push** after each coherent unit. Do not let a backlog build.

## Report format per module

1. Files replaced
2. Schema that turned out insufficient — flag, don't patch
3. Anything already present that the brief assumed missing
4. Anything with no data source — flag rather than invent
