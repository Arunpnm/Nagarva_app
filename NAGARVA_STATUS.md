# NAGARVA — Project Status & Roadmap

> Last updated: 28 Jul 2026 · Owner: Arunkumar (Arponia Ventures)
> Update this file at the end of every working session.
> Legend: ✅ done · 🔨 in progress · ⬜ pending · 🅿️ parked

---

## 🔨 27-28 Jul 2026 — Parity brief (nagarva_parity_brief.md), worked in priority order 1,5,2,4,3,6

- **✅ Part 1 — refresh-after-write bug — FIXED, live-verified in Chrome.**
  Root cause: `NavBarPage` (main.dart) swaps a single `body` slot between tab
  widgets, so each tab's State is created once and reused for as long as
  that tab stays selected — every list/dashboard page fetched its data once
  in `initState` with no mechanism to know a route pushed on top of it
  (RecordPaymentPage, NewOrderPage, a staff sheet, ...) had written new
  data. Switching tabs "fixed" it only because that path *does*
  dispose/recreate the State — which is why it looked like a per-screen
  quirk instead of one systemic gap.
  Fix: `lib/flutter_flow/nav/nav.dart` now has a single app-wide
  `nagarvaRouteObserver` (`RouteObserver<ModalRoute<dynamic>>` — typed on
  `ModalRoute`, not `PageRoute`, because several write surfaces are
  `showModalBottomSheet`/`showDialog` routes, which are `PopupRoute`s;
  `RouteObserver.didPop` only fires when both the popped route and the
  route below it match the observer's generic type) registered via
  `observers:` on the `GoRouter`. A new `RefreshOnPopMixin` wraps the
  subscribe/unsubscribe boilerplate — a page just implements
  `onPageRefresh()` calling its existing load method. Applied to: HomePage,
  OrdersPage, LeadsPage, PaymentsPage, ExpensePage, SalaryPage,
  OperationsPage, FleetPage, UsersPage, MaterialsPage, CalendarPage,
  AccountsPage, PLReportPage, ReportsPage, LeadDetailPage (its
  `_loadLinked()` survey/quotation refresh). `flutter analyze` held at the
  152 baseline throughout (a batch of `unnecessary_import` lints appeared
  and were cleaned up — most pages already get `nav.dart` transitively via
  `flutter_flow_util.dart`).
  **Real crash found and fixed while live-testing this**: fully paying off
  an order via RecordPaymentPage (`payment_status` → `'paid'`) crashed with
  `FlutterError: "There should be exactly one item with [DropdownButton]'s
  value"` — the order drops out of `_model.unpaidOrders` on reload but
  `_model.selected` (the dropdown's `value`) was never cleared, and only
  ever got reassigned when reached via `?orderId=` in the first place (the
  generic Quick-Entry entry point never reassigned it at all). Fixed in
  `record_payment_page_widget.dart`'s `_load()`: re-resolves the current
  selection by id against the fresh list every time (whether it came from
  `widget.orderId` or a prior manual dropdown pick), falling back to no
  selection when the order paid off completely instead of crashing.
  **Live-verified in Chrome** (`flutter run -d chrome`, logged in as APC
  owner): recorded a partial payment on Rohit Malhotra's order from
  PaymentsPage → list totals updated with no navigation; recorded a full
  payoff on two different orders via HomePage's Quick Entry → Record
  Payment (previously the exact crash repro) → no crash, dropdown correctly
  reset to "Select order", and HomePage's Outstanding tile updated
  (₹1.1L → ₹95.5K) immediately on returning to the dashboard, no tab
  switch needed.
  **Known residual gap, not fixed this pass (scoped out, see brief Part 1
  vs. detail pages):** OrderDetailPage and LeadDetailPage display their own
  order/lead fields purely from nav-query params (`widget.orderCustomer`
  etc.), never re-querying the row itself — a pre-existing limitation, not
  introduced by this pass. Editing an order/lead and popping back to its
  own detail page still shows the stale nav-param snapshot (though the
  *list* pages you'd navigate from now correctly refresh). Fixing this
  needs converting ~19-32 `widget.xxx` reads per page to a fresh fetch by
  id, which is a contained but real follow-up, not attempted blind in the
  same pass as the systemic fix.

- **✅ Part 5 — nav touch targets + responsive layout — BUILT, live-verified
  at mobile only before a network outage blocked further testing (see
  below).**
  - New `lib/components/mobile_bottom_nav.dart`: replaces the stock
    `BottomNavigationBar` (which squeezed up to 12 destinations into a
    fixed bar with no labels and well under the 48dp tap-target minimum —
    the exact phone-test complaint). Every destination is now ≥64dp
    wide/tall (evenly distributed if the full set fits, horizontally
    scrollable otherwise for the full 12-item owner nav on a narrow
    phone), labels always visible, active state = filled gold pill behind
    a 27px icon + bold gold label (not a colour shift).
  - Scroll-aware hide/reveal: `main.dart`'s mobile branch wraps `body` in
    `NotificationListener<UserScrollNotification>`, toggling `_navVisible`
    only on `ScrollDirection.forward`/`reverse` — no idle timer anywhere,
    so the nav can't vanish while the user is stationary.
  - Breakpoint lowered from 768dp to 600dp: 600-1024dp (tablet) and
    >1024dp (desktop) now both get the existing collapsible left rail
    (previously devices in the 600-768dp gap wrongly got the cramped
    mobile bar). The rail's expanded/collapsed choice is now persisted via
    SharedPreferences (`_setRailExpanded`), loaded on `NavBarPage.initState`
    — it wasn't before.
  - Tap-target audit (5e): grepped for explicit small `BoxConstraints`/
    zero-padding icon buttons app-wide. Found and fixed one real
    violation — HomePage's period-navigation prev/next-month arrows were
    constrained to 32x32dp; now 48x48dp. Survey CFT counters (the brief's
    other named concern) don't exist yet — will be built to the 48dp spec
    from the start in Part 3, not retrofitted.
  - **Live-verified**: mobile viewport (390px) in Chrome, logged in as APC
    owner — new bottom nav renders with labels, gold active pill, correct
    icons for the full 12-item owner set.
  - **Not yet live-verified (built + `flutter analyze` clean only)**:
    tablet (820px) and desktop (1440px) breakpoints, scroll-hide/reveal
    behaviour, and rail-persistence across a reload — the preview
    browser's external network access dropped entirely mid-session
    (`fetch('https://example.com')` itself timed out, not just Supabase),
    blocking login before these could be checked. Will verify once network
    access is confirmed back.

- **✅ Part 2 — dead settings + fleet gaps — BUILT, partially live-verified
  (payments/dashboard flows only, before the same network outage).**
  - **2a settings toggles**: Notifications is now a real `Switch`
    (`lib/components/notification_bell.dart`'s new `NotificationPrefs`,
    SharedPreferences-backed, default on) gating only the disruptive
    in-app popup — the bell's badge/list still show everything regardless
    of this setting. Dark Mode row replaced with a working Light/Dark/
    Midnight selector (see 2b). Language/Export Data/Backup rows removed
    entirely from `settings_page_widget.dart` per the brief's table.
  - **2b theme**: brand rebrand to navy `#0F2A47` / gold `#E3B23C` / teal
    `#1FA98C` applied to `flutter_flow_theme.dart`'s Light and Dark themes
    (primary/secondary/tertiary + Dark's backgrounds), the 3 hardcoded
    orange FABs (Home/Leads/Orders), and the previously-independent
    hardcoded orange (`0xFFFF6B35`) on LoginPage/SignupPage. Added a real
    third **Midnight** theme (`MidnightModeTheme extends DarkModeTheme`,
    near-black backgrounds, same accent triad) — didn't exist before at
    all, despite NAGARVA_STATUS.md previously claiming "3 themes" as done.
    `FlutterFlowTheme.effectiveVariant(context)`/`MyApp.setThemeVariant`
    are the new shared selection logic; the desktop sidebar's existing
    Light/Dark chips extended to 3-way, and the exact same control is now
    also on mobile via SettingsPage (it never was before — this was the
    "yesterday's build didn't have it" gap the owner flagged live this
    session).
  - **2c Fleet**: `lib/fleet_page/vehicle_detail_sheet.dart` (new) — tap a
    vehicle card to view full detail (type, driver, status, insurance/
    permit expiry with overdue highlighting, last service, notes) with an
    Edit action, plus a new "Add Vehicle" FAB; both were entirely missing
    before (not even a tap handler existed). Expiry alert notifications
    deliberately NOT built (parked per the brief).
    **Found and removed while in this file**: FleetPage had 4 fully
    hardcoded fake vehicle cards (TN-01-AB-1234 through TN-04-GH-3456,
    leftover FlutterFlow mockup data) rendering below the real list,
    un-tappable and misleading — removed (732 lines). Did not fix the
    page's still-hardcoded top stat tiles ('4'/'Active', '2'/...) —
    flagged here as a follow-up, out of the explicit 2c ask.
  - **Live-verified**: none of Part 2 specifically (network outage hit
    before reaching Settings/Fleet in this session's browser pass) — code
    reviewed and `flutter analyze` clean, but mark as **built-not-verified**
    per the brief's own instruction until a live pass confirms the
    Notifications switch, theme selector, and vehicle detail/edit sheet
    actually work end-to-end in the browser.
  - **Network outage note**: mid-session the preview browser lost all
    external connectivity (`fetch('https://example.com')` itself timed
    out) — this is why Part 2 and the rest of Part 5 couldn't be
    live-tested this pass. Not a code issue; re-verify once connectivity
    is confirmed.

- **✅ Part 4 — smaller gaps — BUILT, not live-verified (same network
  outage; code-reviewed + `flutter analyze` clean).**
  - **4a Expense filters**: This Week/This Month/All period chips (by
    `expense_date` falling back to `created_at`) plus an "Order-linked
    only" toggle (`order_id != null`), computed client-side over the
    already-loaded `expensesList` — this page had zero filters before.
  - **4b Leads — Generate Survey Link on the card**: LeadDetailPage
    already had a working "Request Survey" (built earlier this project) —
    the gap was specifically the list card having no shortcut. Added a
    48x48dp icon button per card (`_quickSurveyLink` in
    `leads_page_widget.dart`) that inserts a `surveys` row (client-generated
    `id`/`token`, same scheme as the detail page's `_generateHexToken` —
    `surveys.lead_id` confirmed uuid, matches `LeadsRow.id`) and shows a
    copyable link dialog without leaving the list.
  - **4c quotation_page_widget.dart fix**: its ad-hoc quote's
    `QuotationsTable().insert()` had the same `id`/`token`-has-no-DB-default
    gap already fixed in `lead_detail_page_widget.dart` (CONSTRAINTS
    section) — was never live-tested. Now generates both client-side
    before insert, matching the established pattern exactly.
  - **Not live-verified**: same network outage as Parts 2/5 — flagged
    built-not-verified pending a live pass (record an expense and check
    the filters, tap the new lead-card button and confirm the link opens
    `/survey?token=...` correctly, submit the ad-hoc quote form and
    confirm the insert succeeds without a duplicate-key/null-id error).

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
| 5 | ✅ Calendar page blank-render crash | 1–2 hrs | 29 Jul |
| 6 | ✅ Cleanup: plan_id signup verify · Test 3 org_members delete · staff.pin null-out · PIN rate limiting — **the 25 Jul ✅ was premature (6c/6d were only "ready to run"); actually executed + verified 27 Jul, see note below** | 1–2 hrs | 30 Jul |
| 7 | 🔨 Android on-device install (MIUI "Install via USB") + phone smoke test | 30 min | any day |

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
| 8 | ✅ Survey → Quotation → Order flow | Survey form, quote builder, customer-facing token links (`get_quotation_by_token()`, `submit_survey()` RPCs), e-sign/accept, convert to order — **live-verified end-to-end 27 Jul 2026** | 12–18 hrs (~4–6 sessions) | done |
| 9 | ✅ (partial) Org switcher (dual-membership accounts) | Switch UI + session org context — **unblocked 27 Jul (owner added to TEST 1 as a 2nd org_members row); live multi-org test still pending** | 2–3 hrs | ~12 Aug |
| 10 | ✅ Vendor onboarding polish | First-run wizard: logo, GST, invoice prefix, staff seed | 3–4 hrs | ~14 Aug |
| 11 | 🔨 Subscription billing | Razorpay checkout, plan up/downgrade, trial-expiry lock, webhooks — trial lock ✅, checkout **BLOCKED on real Razorpay keys** | 10–14 hrs (~4 sessions) | ~22 Aug |
| 12 | ✅ Super-admin platform console | All-tenant list + tenant detail + plan management + suspend/reactivate — **built out into a full console and live-verified 27 Jul 2026; see notes below for the one remaining migration** | 4–6 hrs | done |
| 13 | 🔨 Beta hardening | Write-path isolation test, service-role audit, error reporting, backups | 4–6 hrs | ~28 Aug |

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

**Item 5 note (25 Jul 2026):** root cause was `OrdersRow.moveDate`
(`getField<DateTime>('move_date')!`) throwing for any order with a null
`move_date` — Calendar page reads every org order unfiltered via
`_orderDays()`/`_ordersOn()`, so one bad row blanked the whole page.
Item 1's live test didn't reproduce it only because this org's seeded
demo orders all happen to have a move_date. Fixed by reading the raw
nullable field (`o.getField<DateTime>('move_date')`) instead of the
throwing getter, skipping orders with no move_date. Also fixed the same
pattern in home_page_widget.dart's new period-filter code (item 4,
introduced this session) since it has the identical unfiltered-read
shape. **Not yet fixed, flagged for item 13 (Beta hardening) instead of
scope-creeping item 5** — the same `.moveDate` non-null assert is used
unguarded in `p_l_report_page_widget.dart`, `reports_page_widget.dart`,
`accounts_page_widget.dart`, and `orders_page_widget.dart`. None of
these crashed in this session's testing (same reason: no null-move_date
row exists in current seed data), but any of them would blank on a real
org that has one. Consider a DB `NOT NULL` constraint on `orders.
move_date` too, once existing rows are confirmed clean — would remove
the whole bug class at the source instead of patching each read site.

**Item 6 note (25 Jul 2026), four sub-parts:**
- **(a) plan_id signup verify — confirmed already correct.**
  `signup_page_widget.dart` fetches the default trial plan before the
  `organizations` insert and stamps `plan_id`/`plan_status`/
  `trial_ends_at` on creation (matches CLAUDE.md's prior fix). Live
  read-only REST check against the org this session is authenticated as
  confirms `plan_id` is non-null (`plan_status: 'active'`). Nothing to
  fix.
- **(b) "Test 3" org_members delete — could NOT locate, flagged for
  Arun.** RLS correctly scopes this session's authenticated queries to
  only the current org's `org_members` row — I have no way to see
  other orgs' test data (and shouldn't, without service-role access,
  which I don't have and won't use). Whatever "Test 3" refers to needs
  to be found and removed by Arun directly in the Supabase dashboard.
- **(c) staff.pin null-out — app fix shipped, DB step ready-to-run.**
  Root cause: `staff_form_sheet.dart` pre-filled the "Login PIN" field
  with the existing plaintext PIN on every edit open (confirmed live in
  item 1's testing — editing Vignesh showed "2222" in cleartext). The
  `pin` column is a write-only conduit for a DB trigger
  (`staff_hash_pin`, see `supabase/20260723_staff_auth_link_v2.sql`)
  that bcrypt-hashes it into `pin_hash`, which is all the staff-login
  Edge Function actually reads for auth — `pin` itself was never read
  anywhere except this one display bug. Fixed: the field now always
  starts blank ("Leave blank to keep current PIN"); the existing
  blank-means-no-change save logic and validator were already correct.
  **`supabase/20260725_staff_pin_rate_limit.sql`'s cleanup block
  (`update public.staff set pin = null`) is ready to run** now that the
  app no longer reads this column — needs Arun to execute in the
  Supabase SQL editor.
- **(d) PIN rate limiting — added, ready-to-run.** The `staff-login`
  Edge Function had no lockout at all — unlimited attempts against a
  4-digit PIN. `supabase/20260725_staff_pin_rate_limit.sql` (**not yet
  executed — needs Arun to run in the Supabase SQL editor**) adds
  `failed_pin_attempts`/`pin_locked_until` columns and rewrites
  `verify_staff_pin` (same name/signature) to track and enforce a
  5-attempts/15-minute lockout atomically in Postgres. The Edge Function
  now returns 429 with a "try again after HH:MM" message on lockout,
  and `login_page_widget.dart`'s staff-login handler was fixed to
  actually surface that message — it previously caught every error
  (401 wrong-PIN and this new 429 alike) the same way and silently fell
  through to a generic "Invalid name/phone or PIN," which would have
  swallowed the new lockout message entirely.
  **Not live-testable from this session** (would require deploying the
  Edge Function and either 5 real failed attempts against seeded staff,
  or waiting out a real lockout window) — verified by code review and
  `flutter analyze` only.

**Item 6 update (27 Jul 2026) — (b), (c), (d) all resolved; the 25 Jul ✅
above was premature for two of the four sub-parts.**
- **(b) "Test 3" org_members delete — resolved, was a red herring.**
  There was never an `org_members` row to delete — "Test 3" was an
  orphan `organizations` row (`25bf0c00-fc4e-42ba-878e-9a9852e01c8b`)
  with zero members, which is exactly why the 25 Jul session's
  RLS-scoped, authenticated-only query couldn't see it (correctly — an
  org with no members is invisible to every normal session by design,
  not a bug). Arun found and deleted it directly along with its 4
  `settings` rows via the Supabase dashboard.
- **(c) staff.pin null-out — DB step executed 27 Jul.**
  `supabase/20260725_staff_pin_rate_limit.sql`'s cleanup block
  (`update public.staff set pin = null`) has now been run. Verified: 0
  plaintext PINs remain, 0 staff rows are missing `pin_hash` (i.e.
  nothing was nulled that hadn't already been hashed first).
- **(d) PIN rate limiting — DB step executed 27 Jul, needed one more
  correction first.** `supabase/20260725_staff_pin_rate_limit.sql`
  originally failed with `42P13` ("cannot change return type of
  existing function") — `verify_staff_pin()` already existed (created by
  `20260723_staff_auth_link_v2.sql`) returning 5 columns, and this
  migration's version returns 7 (adds `locked`/`locked_until`);
  `CREATE OR REPLACE FUNCTION` cannot change a return type in place, only
  a plain `CREATE FUNCTION` can, so an explicit `DROP FUNCTION IF EXISTS`
  was added before the `CREATE OR REPLACE`. Same lesson as
  `views_dashboard_and_ops.sql`'s pre-existing `DROP VIEW IF EXISTS`
  requirement for view column-type changes — see the new CLAUDE.md note
  on this. Re-run succeeded; verified live: 2 rate-limit columns
  (`failed_pin_attempts`, `pin_locked_until`) present on `staff`. Not yet
  live-tested end-to-end (would need 5 real failed PIN attempts against a
  seeded staff member, or waiting out a lockout window) — still
  code-review-verified only for the actual lockout *behaviour*, though
  the schema/function deployment itself is now confirmed live.

**Item 7 note (25 Jul 2026) — BLOCKED, needs Arun.**
`flutter build apk --release` failed:
`java.io.IOException: There is not enough space on the disk` — Gradle
couldn't download the Android runtime jars it needs.
`Get-PSDrive` shows **C: has 0 GB free** (215 GB used); D: has 415 GB
free. Per this doc's own "New dev PC" note, only the Gradle *cache* was
junctioned C:→D:\gradle_cache — the Android SDK itself is still on C:,
which combined with everything else on that drive appears to have
filled it. **Did not attempt to free space myself** (not a call to make
unilaterally without knowing what's safe to remove on C:).

**What's needed:** free up C:, or move more of the Android SDK setup to
D: the same way the Gradle cache already was. Once there's headroom,
re-run `flutter build apk --release` from `D:\nagarva_app` using the
pinned SDK (`D:\software\flutter_windows_3.35.5-stable\flutter\bin\
flutter.bat`) to confirm the build itself is healthy before sideloading.

**Deferred as a result:** moving `MainActivity.kt` from the stale
`android/app/src/main/kotlin/com/example/my_project/` path to
`android/app/src/main/kotlin/in/nagarva/app/` (package is already
`in.nagarva.app`) — this was flagged as safe tidy-up *if the build still
passes after*, and I can't verify that without a working APK build. Not
done this session.

**MIUI sideload instructions (once you have a built APK):**
1. Settings → About phone → tap "MIUI version" 7 times to unlock
   Developer Options.
2. Settings → Additional settings → Developer options → enable
   **USB debugging** AND **Install via USB** (MIUI blocks sideloading
   without both — this is the actual gate, not just USB debugging).
3. Connect the phone, accept the "Allow USB debugging?" prompt.
4. `flutter install` from `D:\nagarva_app` (or copy the APK from
   `build/app/outputs/flutter-apk/app-release.apk` and open it on-device
   via a file manager) to sideload.

**Smoke-test checklist once installed:**
- App opens without crashing, shows the Nagarva login screen.
- Vendor login works (email/password).
- Dashboard loads with real KPI numbers, period filter chips work.
- Orders list loads and scrolls.
- Staff PIN login works (device-unlock banner, then PIN).
- Logout actually returns to the login screen and stays there (this
  session fixed a real bug here — worth double-checking on a fresh
  device where the bug's original symptom would have been most visible).

**Item 8 note (25 Jul 2026) — code complete, ready for review + SQL run,
verification blocked by the disk-space issue below.** No product spec was
available for this pass, so a scope assumption was made and documented at
the top of `supabase/20260725_survey_quote_flow.sql` rather than stalling:
vendor requests a survey for a lead (shareable link, no customer login) →
customer fills a structured move-details form via `submit_survey()` →
vendor builds a quote (single total + GST%, not a full line-item builder —
that already exists separately in `quotation_page_widget.dart` for ad-hoc
quotes) → shares a second link → customer views it via
`get_quotation_by_token()` and accepts by typing their name (e-sign =
typed name + timestamp, no signature-pad dependency) → vendor converts the
accepted quote to a real order, seeded with the quote's actual total
instead of the ₹0 the plain lead-convert path uses.

What shipped:
- `supabase/20260725_survey_quote_flow.sql` (**NOT YET RUN** — ready for
  Arun to execute): new `surveys` table (RLS org-isolated) + `token`/
  `accepted_at`/`accepted_by_name`/`survey_id` columns on the existing
  `quotations` table (which already had `items`/`charges`/`subtotal`/
  `gst_pct`/`total` — built on top of it rather than duplicating), plus
  4 `security definer` RPCs granted to `anon`: `get_survey_by_token`,
  `submit_survey`, `get_quotation_by_token`, `accept_quotation`. Each RPC
  only ever touches the one row matching the exact token given (same
  trust model as any share-link feature) — tokens are 24 random bytes,
  not guessable/enumerable.
- Two new public, unauthenticated pages: `lib/survey_page/` (`/survey?
  token=...`) and `lib/quote_page/` (`/quote?token=...`), registered in
  `nav.dart`/`index.dart`. Neither touches `AppSession` — they talk to
  Supabase only through the anon RPCs above.
- `lib/lead_detail_page/lead_detail_page_widget.dart`: new "Survey &
  Quote" section — Request Survey / Create Quote / Convert Quote to
  Order buttons, each showing the resulting share link in a copyable
  dialog. Convert-to-order reuses the existing `_nextOrderId()` counter
  and the same order-insert shape the plain lead-convert button already
  used, just seeded from the quotation's real total.

**Verification status:** `flutter analyze` is clean (140 issues, same
baseline, 0 new). **Could not run `flutter test` or a live browser
check** — see the disk-space note below, which broke the Dart test
compiler mid-session. Manual verification of the actual survey-submit ->
quote-accept -> convert-to-order loop, end to end in a browser, is still
needed once disk space is freed.

**Disk-space note (25 Jul 2026) — escalated from item 7's blocker.** C:
has been at 0 GB free all session (see item 7). It's now also breaking
`flutter test` directly — a run during item 8's work crashed the Dart
compiler ("Error: The Dart compiler exited unexpectedly" / null-check on
a null value) and hung for the full 12-minute timeout. `flutter analyze`
still works and was used for all verification from this point forward.
This is no longer just an Android-build problem — freeing C: drive space
is now blocking the core dev/test loop too.

**26 Jul 2026 — disk space fixed, items 1–6 retested live, item 8
live-verified as blocked, items 9/10/12/13 built + live-verified, item 11
partially built** (Claude Code session, continuation of 25 Jul — Android
SDK reinstalled on D:\Android\Sdk, `flutter doctor` fully green, C: has
headroom again, `flutter test`'s Dart-compiler crash from the disk-space
note above is gone). Full toolchain working for the first time this
project — everything below except the two flagged blockers is
`flutter analyze` clean AND live-browser-verified in Chrome, not just
code-reviewed.

- **Items 1–6 retest: no regressions.** Session restore, dashboard period
  chips (This/Last recompute correctly), Calendar (no blank-crash, real
  reminders), Accounts daily register, Settings real org data, invoice
  generation (now produces a real downloadable PDF — better than this
  doc's earlier "text dialog" note, which is now stale), and Logout (real
  sign-out, confirmed via root path showing the login screen after) all
  retested clean. **New (pre-existing, not a regression) finding, now
  fixed as part of item 13 below:** no route-level auth guard existed —
  navigating directly to e.g. `/calendar` after Logout rendered the page
  with empty data instead of redirecting to login.
- **Item 8 live-tested — confirmed blocked exactly as flagged, not a new
  problem.** "Request Survey" fails with the live error
  `Could not find the table 'public.surveys' in the schema cache` —
  proves `supabase/20260725_survey_quote_flow.sql` has not been run.
  "Create Quote" also fails to persist (confirmed by reloading the page
  under the vendor's own authenticated session, not just an anon-key
  check — RLS discovery below explains why the anon check alone isn't
  trustworthy). One red herring chased and closed: the error's hint
  pointed at a pre-existing `customer_surveys` table; grepped the whole
  app and confirmed it has zero references anywhere in `lib/` — it's
  unused schema from the RLS migration below, not a real conflict with
  the new `surveys` table. **Needs Arun to run the SQL file before this
  can be completed.**
- **Discovered this doc's "Multi-tenancy status" section (in the stale
  CLAUDE.md, not this file) is significantly out of date**: a full RLS
  rollout (`supabase/migrations/20260715_rls_v1.sql`, committed by Arun
  directly on 15 Jul, before this session) already enables RLS on all 18
  core tables via `current_org_ids()`/`is_platform_admin()`, and a
  `platform_admins` table already exists — none of this was reflected in
  CLAUDE.md. This doc (NAGARVA_STATUS.md) already had it right ("RLS on
  18 org-scoped tables" under Foundation & Auth) — CLAUDE.md needs a
  reconciliation pass against actual git history, flagged for next
  session rather than done blind here.
- **Item 9 (org switcher) — built and live-verified for the common
  single-org case; the multi-org picker itself is genuinely blocked on
  test data.** `AppSession` now tracks `availableOrgs` (every
  `org_members` row for the signed-in user, not just `members.first` —
  the old `.limit(1)` silently dropped every membership past the first).
  New shared `loadOrgSessionData()` helper
  (`lib/backend/supabase/org_session_loader.dart`) so the org+plan lookup
  isn't duplicated between login and switching. New
  `showOrgSwitcherSheet()` bottom sheet
  (`lib/components/org_switcher_sheet.dart`). LoginPage now queries every
  `org_members` row and shows the picker when there's more than one;
  Settings gets a "Switch Organization" button, shown only when
  `availableOrgs.length > 1`. **Live-verified:** logged in as the single
  real vendor account — Settings correctly shows only Logout (no
  switcher clutter) and login proceeds straight through, confirming the
  refactored `_handleVendorLogin` has no regression for the 99% case.
  **Could not test the actual multi-org picker** — creating a second
  `org_members` row for the same auth user needs either a raw DB insert
  (blocked twice by the sandbox's own safety classifier, even using the
  vendor's own JWT — correctly refused, not routed around) or an in-app
  "invite existing user to another org" flow that doesn't exist yet.
  **Needs Arun**: either seed one test `org_members` row via the Supabase
  dashboard (exact SQL was given in-session), or accept this stays
  code-reviewed-only for the multi-org path until a real second-org
  vendor exists.
- **Item 10 (vendor onboarding polish) — built and fully live-verified.**
  `OrgSetupPageWidget` (the first-run wizard) gained a "Branding" section
  (new `lib/components/logo_upload_card.dart`, same upload mechanism as
  Settings' logo card but kept as a separate small widget rather than
  refactoring that already-working code) and a "Your Team" section that
  reuses the existing `StaffFormSheet` from Users (no new form built —
  same permission-matrix dialog). **Live-verified:** logo card correctly
  showed the already-uploaded org logo; team section listed all 8 real
  seeded staff; "Add Team Member" opened the full Add Staff sheet
  correctly (closed without submitting, to avoid writing test rows into
  live data).
- **Item 12 (super-admin platform view) — built and live-verified for the
  access-denied path; the positive (actual tenant list) path is blocked
  on the owner seeding one row.** New `platform_admins.dart` table class
  (schema wasn't previously wired into the Dart layer even though the
  table's existed since 15 Jul) and `lib/super_admin_page/` at
  `/super-admin` — not linked from any nav, direct-URL only. Gates on a
  `platform_admins` row for the signed-in user (that migration's own
  "KNOWN GAPS" note already flagged seeding as not done, so by design no
  account passes this gate yet); shown all-tenant list has plan-override
  (dropdown → `organizations.plan_id` update) and per-org usage counts
  (orders/leads/staff). **Live-verified:** navigating to `/super-admin`
  as the real vendor account correctly shows "This account is not a
  platform administrator" — the `platform_admins` self-check query itself
  ran without error (confirming the table really is live), it just
  correctly found no row. **Needs Arun** to
  `insert into platform_admins (user_id) values ('<auth-uid>')` for
  whichever account should reach this page, then the all-tenant list can
  be verified live.
- **Items 9 and 12 update (27 Jul 2026) — both unblocked, live tests
  still pending.** Arun seeded `platform_admins` for the owner account
  (unblocks item 12's all-tenant-list positive path) and added the owner
  as a second `org_members` row on TEST 1 (unblocks item 9's multi-org
  picker) directly via the Supabase dashboard — the two blockers flagged
  in the notes above. Neither has been live-tested yet in this session;
  that's the next thing to verify, not assumed working just because the
  test data now exists.
- **Item 12 update (27 Jul 2026, super-admin console pass) — built out
  into a real platform console and live-tested end-to-end against
  nagarva-demo. STEP 0 verify first**: confirmed the pre-existing
  tenant list, plan-override dropdown, and usage counts already worked
  exactly as described — nothing in that path was rebuilt, only added to.
  - **Plans tab** (`lib/super_admin_page/plans_tab.dart` +
    `plan_edit_sheet.dart`): lists every `subscription_plans` row (name,
    price, billing period, limits, features) with a create/edit sheet.
    The limit/feature keys shown are the real ones the app gates on,
    grepped live rather than guessed (`max_users`/`max_orders`/
    `max_leads`; `whatsapp`/`reports`/`gst_invoice`/`multi_branch` — the
    first draft assumed `invoice`/`fleet`/`salary`, which don't exist in
    the live data, corrected before ever saving). Saving merges onto the
    plan's original jsonb rather than replacing it wholesale, so editing
    price doesn't silently drop an unrelated feature key. Guards against
    unsetting the last `is_default_trial` plan. **Live-verified**: list/
    edit-sheet/pre-fill and the New Plan form all render correctly with
    real data (Pro/Starter/Trial). **Found a real bug, not yet fixed in
    SQL**: editing a plan's price closed the sheet with no error and even
    showed the new value in the list — but reloading showed the old value
    again. Root cause: `subscription_plans` has had a SELECT-only RLS
    policy since `20260715_rls_v1.sql` ("read-only, managed via
    dashboard"), no INSERT/UPDATE — RLS silently filters the write to zero
    rows with no client-visible error. Migration written:
    `supabase/20260727_subscription_plans_admin_write.sql` (**not run —
    Arun runs all SQL**). Re-tested the Create Plan flow after diagnosing
    this: it now surfaces a clean `PostgrestException ... 42501` in the
    UI instead of a silent no-op, confirming both the diagnosis and that
    the app's error handling is correct either way.
  - **Tenant detail page** (`lib/super_admin_page/tenant_detail_page.dart`):
    tapping a tenant card opens name/slug/GSTIN/created/plan/plan_status/
    trial_ends_at/owner email + orders/leads/staff/invoices counts.
    Owner email needs a new RPC (`get_org_owner_email`, joining
    `org_members` → `auth.users`, security-definer + `is_platform_admin()`
    gated) written to `supabase/20260727_super_admin_owner_email.sql`
    (**not run**) — the page calls it defensively and shows
    "— (needs 20260727_super_admin_owner_email.sql)" instead of erroring
    when it's missing, confirmed live for both APC and TEST 1.
  - **Tenant suspension** (Step 3): checked first whether
    `organizations.active` already existed and was read anywhere — it
    existed (since the original schema) but nothing consumed it, so this
    wires up an existing column rather than adding one. `AppSession`
    gained `orgActive`/`isSuspended`, threaded through
    `org_session_loader.dart` into login, org-switch, and session-restore.
    `NavBarPage`'s trial-expiry lock screen (item 11) was refactored into
    a shared `_buildLockScreen(suspended:)` per this task's own
    instruction to reuse it rather than build a second one — suspended
    copy has no "View Plans" upsell. **Live-verified, full round trip**:
    suspended TEST 1 from its tenant detail page, switched a real session
    into it, confirmed the "Account suspended" lock screen rendered (not
    the trial-expiry copy), confirmed the suspension survived a fresh
    page reload, then reactivated it from the same page and confirmed
    *that* also survived a reload. TEST 1 was left active/clean afterward.
  - **Found and fixed one unrelated regression while testing the above**:
    switching into TEST 1 to see the lock screen required the "Switch
    Organization" button, which turned out to be missing after a page
    reload for any multi-org account. Root cause: `main.dart`'s
    session-restore path only ever queried the first `org_members` row
    (`.limit(1).maybeSingle()`) and never populated
    `AppSession.availableOrgs` — unlike `login_page_widget.dart`'s
    explicit-login flow, which was correctly fixed when item 9 was built.
    There was a pre-existing `TODO(W2)` comment flagging exactly this gap
    that had been missed. Fixed in its own commit (not bundled with the
    suspension work, since it's a pre-existing bug unrelated to this
    session's task).
  - **Two migrations still need Arun to run** before this console is
    fully live: `supabase/20260727_subscription_plans_admin_write.sql`
    (blocks Plans tab writes) and
    `supabase/20260727_super_admin_owner_email.sql` (blocks the owner
    email field — degrades gracefully without it, not a hard blocker).
  - **Out of scope, per the task**: Razorpay/billing checkout, billing
    history, per-tenant invoicing — none of this pass touched them.
- **Item 11 (subscription billing) — trial-expiry lock built and
  live-verified (no false-positive regression); Razorpay checkout itself
  is genuinely blocked, same as already flagged.** `AppSession` gained
  `planStatus` (threaded through login, org-switch, and session-restore —
  three call sites) and `isTrialExpired` (`planStatus == 'trial' &&
  trialEndsAt` has passed). `NavBarPage` now shows a dedicated lock screen
  instead of the tab shell when true, with "View Plans" and "Logout" —
  nothing org-scoped renders while unpaid. **Live-verified:** the real
  vendor account's Dashboard rendered normally after this change (not
  locked out), confirming no false positive. Actual Razorpay checkout
  (package, checkout UI, webhook signature verification) needs a real
  Razorpay account/API key — cannot be built without it, same class of
  gap as a payment feature, not attempted.
- **Item 13 (beta hardening) — several concrete fixes shipped and
  live-verified; some sub-scope items need the owner, not code.**
  - **Same bug class as item 5's Calendar crash, found in 6 more files**:
    `OrdersRow.moveDate` (`getField<DateTime>('move_date')!`) throws for
    any order with a null `move_date`; item 5 only fixed Calendar and
    flagged 4 more files as residual risk (`p_l_report_page_widget.dart`,
    `reports_page_widget.dart`, `accounts_page_widget.dart`,
    `orders_page_widget.dart`). Grepped for every `.moveDate` call site
    this pass, found 2 more with the identical unguarded pattern
    (`operations_page_widget.dart` — silently swallowed by an empty
    `catch (_) {}`, meaning Operations could go blank with zero error
    shown; `salary_page/staff_ledger_sheet.dart`). Added
    `OrdersRow.moveDateOrNull` (null-safe read of the same column) and
    fixed all 6 files to skip/guard null-move_date rows instead of
    crashing or silently failing. **Live-verified**: Accounts, Reports
    (Month + All period), P&L, Orders (list + detail), Operations, and
    Salary (July + June, confirming the null-safe `_inMonth` fix computes
    real per-staff earnings correctly) all re-tested with real data —
    identical numbers to before the fix, zero regressions.
  - **Route-level auth guard added** (`lib/flutter_flow/nav/nav.dart`) —
    closes the gap found retesting item 1 above. A `redirect:` callback on
    the top-level `GoRouter` bounces any non-public route to `/login` when
    `AppSession.isAuthenticated` is false; `/`, `/login`, `/signup`,
    `/survey*`, `/quote*` stay public. Safe against the session-restore
    race item 1 already fixed: `main()` fully `await`s Supabase's session
    recovery before `runApp()`, so by the time the router's `redirect`
    ever runs, `AppSession` is already correctly populated one way or the
    other — confirmed by re-reading `main.dart`'s restore sequence before
    writing this, not just assumed.
  - **Global error-handling safety net added** (`lib/main.dart`) —
    `FlutterError.onError`, `PlatformDispatcher.instance.onError`, and a
    custom `ErrorWidget.builder` replace Flutter's default red screen /
    blank-page-on-release with a friendly "Something went wrong" fallback
    and console logging. Real crash-reporting (Sentry or similar) needs a
    real account/DSN — flagged, not fabricated, same class of gap as
    Razorpay.
  - **Quick audits, both clean**: grepped the whole app for
    `service_role`/`SERVICE_ROLE` — zero matches, no service-role key has
    ever been checked in. Grepped for hand-written `.eq('org_id', ...)`
    filters outside `org_scope.dart` — the only matches are the new
    `super_admin_page_widget.dart` (the one deliberate, documented,
    RLS-backed exception), confirming the org-scoping convention has no
    accidental regressions anywhere else.
  - **Not done this pass, still open**: "backups" (a Supabase project
    dashboard setting, not app code — needs Arun to configure point-in-
    time recovery/backup schedule directly); a from-scratch write-path
    isolation *test suite* (the audits above are a manual grep pass, not
    an automated regression test — worth a real test file later).

**Disk-space status: resolved.** Android SDK reinstalled on D:\Android\Sdk,
`flutter doctor` fully green (Android toolchain + licenses pass), C: and D:
both have headroom. Item 7 (Android on-device install) can resume once a
physical device is available to sideload to — not attempted this pass
(session was web-only).

**27 Jul 2026 — item 8 live-verified end-to-end, two real bugs found and
fixed** (Claude Code session, continuation of 26 Jul — Arun ran
`supabase/20260725_survey_quote_flow.sql` successfully against nagarva-demo,
confirmed live: surveys table = 1 row, quotations new columns = 4, RPCs
registered = 4; the file on disk was corrected to match what actually
executed — see its own header for the two corrections, both already
applied, do not revert). Full loop tested in Chrome against the real
database, not code review: vendor Request Survey → customer fills
`/survey?token=...` with no auth session → re-visit shows "already
submitted" (the `and status = 'pending'` guard surfaces correctly in the
UI) → vendor Create Quote → customer views `/quote?token=...` with real
totals → accepts by typing a name → re-visit shows "Accepted by
[name]" persists (re-accept correctly can't re-trigger since the accept
form is hidden once accepted) → vendor Convert Quote to Order → real
order created with the quotation's actual total (₹39,900, confirmed via
the Orders list, not ₹0) and the lead flips to `confirmed`.

Two real, previously-unverified bugs found and fixed along the way —
both only surface against a live database, which is exactly why this
verification pass mattered:
- **`quotations.id` has no DB-generated default** (unlike `surveys.id`,
  which does) — every `_createQuote()` insert failed with Postgres 23502
  "null value in column id" until fixed. Root-caused via the Dart VM's
  own console log (Flutter DevTools' Logging tab turned out to be
  gesture-arena noise, not app output — `read_console_messages` on the
  page's own tab is what actually surfaces `print()`/uncaught-exception
  output for a `flutter run -d chrome` debug build). Fixed by generating
  the id client-side (`const Uuid().v4()`, added `uuid` as a direct
  pubspec dependency — it was only ever a transitive
  `dependency_override`). **`quotation_page_widget.dart`'s separate
  ad-hoc quote form has the exact same gap and was never live-tested
  either** — flagged here, not fixed, since it's a different feature
  outside this pass's scope.
- **`quotations.token`'s DB default also doesn't come back populated on
  new inserts**, even though it uses the identical expression as
  `surveys.token` (which does work) — not fully root-caused (would need
  DB introspection access this session doesn't have), but confirmed via
  a pre-existing quotation row (created before the migration ran, then
  backfilled by the migration's own `UPDATE ... WHERE token IS NULL`
  step) which had a real token and worked fine once loaded. Fixed the
  same way as `id`: generate a 24-random-byte hex token client-side
  (`_generateHexToken()`) rather than trust the column default.
- **Separately, `quote_page_widget.dart` crashed** (caught cleanly by
  this session's own item-13 `ErrorWidget.builder` — first real proof
  that safety net works) on that same pre-existing quotation row:
  `items`/`charges` are `jsonb`, and this row had them stored as a JSON
  object instead of an array (likely from a different, older insert path
  that never sets these fields at all). `(q['items'] as List?)` threw a
  `TypeError` instead of returning null. Fixed with an `is List` check
  instead of an unsafe cast — defensive against any legacy row shape,
  not just this one.

Also checked per this session's own request: neither `survey_page_widget.dart`
nor `quote_page_widget.dart` touch the `surveys`/`quotations` tables
directly anywhere — both go through the four RPCs exclusively, so the new
`to authenticated` restriction on the `surveys` RLS policy (added in the
same migration-run correction pass) doesn't affect them. `surveys.dart`
already existed as a generated table class (built in the original item 8
pass, not missing as the task briefing wondered).

`flutter analyze` clean (149 issues, same baseline, 0 new), `flutter test`
passes. Every fix in this entry is live-verified in Chrome against
nagarva-demo, not just code-reviewed — this whole pass existed specifically
because the previous "code complete, analyze-clean" state had never been
run against a real database.

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
