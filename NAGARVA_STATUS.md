# NAGARVA — Project Status & Roadmap

> Last updated: 25 Jul 2026 · Owner: Arunkumar (Arponia Ventures)
> Update this file at the end of every working session.
> Legend: ✅ done · 🔨 in progress · ⬜ pending · 🅿️ parked

---

## ✅ COMPLETED

### Foundation & Auth
- ✅ Multi-tenant Supabase schema; RLS on 18 org-scoped tables
      (`current_org_ids()` / `is_platform_admin()`)
- ✅ Vendor login, signup + auto trial plan, forgot password, session restore
- ✅ Staff PIN login — SERVER-SIDE (Edge Function `staff-login`, bcrypt in
      Postgres, real auth.uid(), shadow users, org_members auto-link)
- ✅ Vendor↔staff session swap; silent vendor restore on Lock;
      staff-aware app reload (no privilege escalation on refresh)
- ✅ GitHub repo + green CI (analyze + sanity tests)
- ✅ Brand system: navy/gold/teal, Manrope + IBM Plex Mono, 3 themes

### Staff & RBAC
- ✅ Staff CRUD (roles, PIN, PF/ESIC toggles, active/inactive, plan gating)
- ✅ Permission matrix (Bilty-style): per-module View/Add/Edit/Del,
      role presets, permission-driven sidebar + URL guard

### Money
- ✅ Payment entries: part-payments, balance due, WhatsApp Remind,
      Outstanding/Received tiles
- ✅ Staff salary ledger: pay salary, advances, settle, per-job earnings
- ✅ P&L report with Porter commission gating
- ✅ Accounts page (daily register) in sidebar
- ✅ Invoice numbering APC/2627/XXX (harness-verified 19/19;
      live end-to-end test still pending — see below)

### Operations & CRM
- ✅ Orders (NGV-XXXX IDs), Operations page, Leads Kanban pipeline
- ✅ Lead & Order edit forms — date pickers fixed (theme + null-crash)
- ✅ Live dashboard KPIs, notifications (triggers + Realtime),
      per-tenant branding, Quick Entry modal

### Platform
- ✅ Responsive sidebar / bottom nav; nagarva.in landing (Netlify DNS)
- ✅ Android build: Kotlin reserved-keyword fix (`in`.nagarva.app)

---

## 🔨 THIS WEEK (26 Jul – 1 Aug) — stabilise & unblock invoicing

| # | Item | Est. effort | Target |
|---|------|-------------|--------|
| 1 | ✅ Full test pass A/B/C/C2/D (sessions, matrix, calendars, Accounts) | 1–2 hrs | 26 Jul |
| 2 | ✅ `phase1_rename_settings_keys.sql` + live invoice test (→ APC/2627/001) — BLOCKS first real invoice | 1 hr | 26 Jul |
| 3 | ✅ Picker sweep (remaining transparent calendars) | 1–2 hrs | 27 Jul |
| 4 | ✅ Dashboard period filter (month arrows + This/Last/3M/FY/All chips) | 2–3 hrs | 28 Jul |
| 5 | Calendar page blank-render crash | 1–2 hrs | 29 Jul |
| 6 | Cleanup: plan_id signup verify · Test 3 org_members delete · staff.pin null-out · PIN rate limiting | 1–2 hrs | 30 Jul |
| 7 | Android on-device install (MIUI "Install via USB") + phone smoke test | 30 min | any day |

**Week ETA: ~8–12 working hours → done by 1 Aug 2026**

**Item 1 test-pass notes (25 Jul 2026, Claude Code session, live-tested
against nagarva-demo with the owner logging in when a password was
needed):** 5 real bugs found and fixed, each verified live in Chrome and
committed/pushed separately:
- Session restore silently failed on every reload/cold-start even with a
  valid Supabase token in local storage — two compounding bugs: (1)
  `main.dart` read `.currentUser` before `Supabase.initialize()`'s
  background `recoverSession()` had resolved (a known supabase_flutter
  web race), and (2) even once `AppSession` was correctly populated,
  nothing ever redirected off `LoginPage` — the router builds it
  unconditionally at `/`. Fixed both; reload now goes straight to the
  dashboard as the restored session (vendor or staff).
- Calendar page had ~470 lines of hardcoded FlutterFlow mockup reminder
  cards ("Follow-up: Ravi Menon" etc.) rendering above the real "Active
  Reminders (Live)" list, presented as if genuine. Removed.
- HomePage's own hamburger drawer duplicated navigation with none of the
  staff permission-matrix filtering the bottom nav/sidebar already has —
  a staff member without Payments/Expenses/Salary/Settings access could
  still see and tap those tiles (harmless due to a generic URL guard
  elsewhere, but confusing). Its Logout tile also never called
  `signOut()`/`AppSession.clear()` at all — just navigated to `/login`,
  which the new redirect fix would've made look like Logout does nothing.
  Both fixed: drawer now filters by `StaffPermissions.activeStaffPages`,
  Logout does a real sign-out (verified: auth token gone from
  localStorage, reload stays on login page).
- Dashboard's "Upcoming Orders" had no `move_date >= today` filter, so it
  showed the oldest confirmed orders ever created instead of ones
  actually coming up. Fixed.
- Permission matrix (view/edit/save/persist), date pickers on New
  Order/New Lead (select + cancel), and Accounts (daily register +
  day-detail expand) all tested clean, no fixes needed.

**Item 3 note (25 Jul 2026):** grepped the whole app for
`showDatePicker`/`showTimePicker`/`showDateRangePicker`/`DateTimePicker(`
— only two call sites exist anywhere (New Order, New Lead), both already
wrapped in `wrapInMaterialDatePickerTheme` and both live-tested clean in
item 1. No other page has its own picker to sweep. Nothing to fix.

**Item 4 note (25 Jul 2026):** added This/Last/3M/FY/All chips + month
arrows above the dashboard's financial KPI row (Revenue/Labour/Expenses/
Net Profit) and the orders-in-period count, computed client-side from
raw `orders`/`expenses`/`order_staff` (same approach as PLReportPage)
rather than the fixed `dashboard_kpis_view` which only ever computed
"this calendar month". One deliberate behaviour change: the period is
now based on `orders.move_date` (matches Accounts/P&L pages) instead of
the view's `orders.created_at` — a booked-in-July order that moves in
June now correctly shows under June, not July. Active Leads/Outstanding/
Reminders stay current-state, unaffected by the period picker (matches
how those numbers are actually used). Live-tested: all 5 chips, both
arrows, and the chip-highlight-follows-arrow-position behavior all
verified correct with real seeded data (This/Last/3M/FY/All revenue
figures cross-check against each other correctly).

---

## ⬜ CORE V1 — required before IPAMTOA beta onboarding

| # | Module | Scope | Est. effort | ETA (sequential) |
|---|--------|-------|-------------|------------------|
| 8 | Survey → Quotation → Order flow | Survey form, quote builder, customer-facing token links (`get_quotation_by_token()`, `submit_survey()` RPCs), e-sign/accept, convert to order | 12–18 hrs (~4–6 sessions) | ~10 Aug |
| 9 | Org switcher (dual-membership accounts) | Switch UI + session org context | 2–3 hrs | ~12 Aug |
| 10 | Vendor onboarding polish | First-run wizard: logo, GST, invoice prefix, staff seed | 3–4 hrs | ~14 Aug |
| 11 | Subscription billing | Razorpay checkout, plan up/downgrade, trial-expiry lock, webhooks | 10–14 hrs (~4 sessions) | ~22 Aug |
| 12 | Super-admin platform view | All-tenant list, plan override, usage stats | 4–6 hrs | ~25 Aug |
| 13 | Beta hardening | Write-path isolation test, service-role audit, error reporting, backups | 4–6 hrs | ~28 Aug |

**🎯 IPAMTOA beta launch ready: ~end of August 2026**
(assumes current pace: 1–2 sessions/day, 2–3 productive hrs/session;
Survey→Quote→Order and Billing are the two long poles)

---

## 🅿️ V2 / PARKED (post-beta)

- 🅿️ Phase 1 ERP: double-entry accounting, chart of accounts,
      `post_journal()`, one-click Tally export (SQL already drafted)
- 🅿️ Payroll compliance depth (PF/ESIC filings)
- 🅿️ Fleet module depth: vehicle documents, expiry alerts
- 🅿️ WhatsApp voice-note load matching (Whisper + AI extraction + Baileys)
      — scoped, parked until Nagarva v1 complete
- 🅿️ PWA / Play Store release pipeline

---

## KNOWN RISKS / NOTES

- ~~`phase1_rename_settings_keys.sql` MUST run before the first real
  invoice or the counter duplicates at 001.~~ **Confirmed done 25 Jul
  2026** (Claude Code session, read-only check via authenticated REST
  query, no data touched): `settings` already holds the renamed
  `inv_seq_2627` key (value `2`), and two real invoices already exist
  sequenced correctly — `APC/2627/001` (order NGV-1010) and
  `APC/2627/002` (order NGV-1001). Both the migration and the live
  invoice test are satisfied; nothing left to do here.
- staff.pin plaintext column still populated — null it only after
  confirming Staff form + login fully use pin_hash path (item 6).
- Staff-login endpoint has gateway JWT verification OFF by design
  (auth happens inside the function); add rate limiting in item 6.
- Flutter pinned at 3.35.5 — NEVER `flutter upgrade` / `pub upgrade`.
- New dev PC: Gradle cache junctioned C:→D:\gradle_cache; Android SDK
  still on C: (move later if space tightens).
