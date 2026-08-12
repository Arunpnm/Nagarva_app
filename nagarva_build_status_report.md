# Nagarva — Build Status Report

**As of:** 01 Aug 2026
**Repo:** `Arunpnm/Nagarva_app` · branch `main`
**Confidence key:** ✅ verified this session · 📋 from spec (nothing built) · ⚠️ from memory, verify against `NAGARVA_STATUS.md`

---

## PART A — PENDING

### A0. Immediate (before any new build)

| # | Item | Notes |
|---|---|---|
| 1 | **Part 8 APK test** ✅ | Built and pushed, never run on device. Five tests, order matters — see A0.1 |
| 2 | `20260801_pricing_config_charge_basis.sql` ✅ | Written, deliberately **not run**. App works without it via the Dart fallback |
| 3 | **Basis settings UI** ✅ | Once this exists it writes `charge_basis` on save and the backfill above becomes unnecessary |

**A0.1 — the five Part 8 tests, hardest-to-catch first:**

1. Reprint the ₹39,900 July order — only real legacy-shape jsonb regression test
2. Quote-sign → convert → invoice — confirm provenance line, then confirm an invoice-specific signature displaces the inherited one
3. Generate as APC, switch to TEST 1, generate again — tenant bleed check
4. Detailed PDF with a charge that is `included` **and** `per_cft` — orthogonality check
5. Survey PDF before any quote exists — quote button disabled, survey still generates

### A1. Operational flow — Part 7 build order 📋

Entire `nagarva_operational_flow.md` is specification. Nothing built.

| # | Item | Section | State |
|---|---|---|---|
| 1 | **Quote versioning** | 1.2 | Brief written (`nagarva_part9_quote_versioning.md`), not built |
| 2 | Supervisor access window fix | 2.2 | Not started — current single-date rule breaks every interstate job |
| 3 | Materials issue → consume → return | Part 3 | Not started — stock accuracy degrades daily until this exists |
| 4 | Fuel entries (litres + odometer) + daily closing km | 4.1 | Not started |
| 5 | Unlock / edit-request path | 1.5 | Not started — needed before the completion lock is enforced in anger |
| 6 | Cash imprest + expense approval | 2.5, 6.4 | Not started |
| 7 | Job costing (actual vs quoted) | 6.1 | Not started — assembly of 2–4, highest-value output |
| 8 | RBAC matrix, server-side | Part 5 | Not started |
| 9 | Cancellation, reschedule, feedback, escalations | 6.2, 6.3, 6.5, 6.6 | Not started |

**Capture-from-day-one warning (§Part 7 closing note):** diesel **litres** and material **returns** are impossible to reconstruct retrospectively. Every day without them is a day of data that can never be analysed. That argues for pulling items 3 and 4 forward if the ordered list slips.

### A2. Operational flow — gaps outside the ordered list 📋

Not in the Part 7 sequence, so easily lost:

- **Documents from a confirmed order** (§1.4): LR / Consignment Note, Packing List, Loading Slip, Money Receipt, POD. Invoice exists; the rest do not.
- **Document numbering integrity** (§6.11): per-org, per-FY, gapless, concurrency-safe. Must use a DB sequence or `select … for update`, never client-side max+1. Applies to LR, PL, money receipt, invoice — **not** to quotes.
- **Lost-lead remarketing pool** (§1.3), including `postponed` with expected future date and auto-reminder, and `marketing_opt_out` (DPDP).
- **Duplicate lead detection** (§6.10) — same phone from multiple sources.
- **Multi-day jobs**: separate `load_date` / `delivery_date` (§2.2).
- **Supervisor reassignment mid-job** (§2.2).
- **Attendance double-count rule** — per-day wage vs per-job rate, per org (§2.3).
- **Partial / shared loads** (§6.7), **storage state** (§6.8), **advance & balance payment gates** (§6.9).
- **Attached / hired vehicles** with `ownership` flag (§4.7).
- **Vehicle compliance alerts** — FC, insurance, permit, PUC, road tax at 30/15/7 days (§4.6).

### A3. Parity brief (Parts 1–7) ⚠️

**This section needs verification.** Several look complete from evidence seen this session, but I have not read `NAGARVA_STATUS.md`.

| Item | Evidence seen this session |
|---|---|
| Systemic refresh-after-write | Mechanism confirmed live: `nagarvaRouteObserver` + `RefreshOnPopMixin/onPageRefresh()` — likely done |
| Login screen port (Part 7 addendum) | Screenshots show device setup, org code, PIN, email login, org switcher all working — likely done |
| Survey / quote flow port | Working end-to-end in screenshots — likely done |
| GST auto-detect | `isInterState()` confirmed in `lib/backend/gst_state_codes.dart` — done |
| Charge billing modes | `_billingMode` per-key map confirmed live — done |
| Settings wiring, fleet CRUD | Not observed |
| Expense filters | Not observed |
| Navigation touch targets | Not observed |
| Materials inventory | Not observed — overlaps A1 item 3 |
| WhatsApp templates | Not observed |

### A4. Outside the app ⚠️

- **Privacy policy page** on nagarva.in — blocks Meta/WhatsApp API approval, Play Store submission, and DPDP compliance. Flagged previously, believed still open.
- **Landing page mobile responsive fix.**
- **SEO** — site surfaces only for brand-name searches, not industry keywords. Organic is a months-long play; **direct IPAMTOA outreach remains the faster path to early adopters.**

---

## PART B — SHIPPED

### B1. Part 8 (tonight) ✅

| Commit | Contents |
|---|---|
| `7b16fee` | Notification bell on Dashboard AppBar — reused existing `NotificationBell`, 48×48 target, `99+` cap, Realtime-driven badge |
| `0195e8f` | Shared `PdfBranding` builder + separate `SurveyPdf` / `QuotePdf`; invoice signature inheritance via `orders.quotation_id` with provenance line and `Awaiting customer signature` fallback |
| `6253524` | `PricingConfig.chargeBasis`, per-line basis picker, jsonb dual-shape reader/writer, Summary/Detailed PDF toggle with Inclusions/Exclusions |

`flutter analyze` clean on all touched files. One SQL file parked unrun by design.

### B2. Earlier ⚠️

- **Core V1 items 1–13** — reported complete.
- **Super-admin console** — tenant list, plan override, suspend/reactivate; built and live-tested.
- **Platform foundations** — multi-tenant RLS with `current_org_ids()`, staff PIN bcrypt auth via Edge Function minting real Supabase sessions, survey→quote→order (live-tested on a real ₹39,900 order), staff salary ledger, P&L, payment entries, WhatsApp templates, notifications, fleet, dashboard KPIs.
- **Build/release** — first universal APK (63.6 MB); Android SDK and Gradle cache on D:; Kotlin reserved-keyword fix for `in.nagarva.app`.

---

## PART C — HOW TO CLOSE THE VERIFICATION GAP

Sections A3, A4 and B2 are reconstructed from memory. To make this report authoritative, have Claude Code do one pass:

> Read `NAGARVA_STATUS.md` and `nagarva_parity_brief.md`. For every item in both, report its actual state in the codebase — not what the tracker claims, but what the code shows. Flag any item marked done in the tracker that you cannot find evidence for, and any item marked pending that appears already built. Do not fix anything; report only.

That reconciliation is worth doing before picking the next build item, because A3 items may already be done, and A1 item 3 (materials) overlaps a parity item.

---

## PART D — RECOMMENDED SEQUENCE

1. Test Part 8 on device (A0.1).
2. Run the reconciliation pass (Part C).
3. Decide the parked SQL — hold it until the basis settings UI exists.
4. Then Part 9 (quote versioning) — smallest, protects every negotiation from that day forward, and the brief is already written.
5. Then reassess: if items 3 and 4 (materials, fuel litres) keep slipping, pull them forward on the day-one-capture argument.

**Not in parallel.** Each of A1's items is schema-touching, and your SQL rule is human-in-the-loop. Two agents generating migrations against the same database at once is how you get a conflicting pair neither of them knows about.
