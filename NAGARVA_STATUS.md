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
| 5 | ✅ Calendar page blank-render crash | 1–2 hrs | 29 Jul |
| 6 | ✅ Cleanup: plan_id signup verify · Test 3 org_members delete · staff.pin null-out · PIN rate limiting | 1–2 hrs | 30 Jul |
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
| 8 | 🔨 Survey → Quotation → Order flow | Survey form, quote builder, customer-facing token links (`get_quotation_by_token()`, `submit_survey()` RPCs), e-sign/accept, convert to order — **BLOCKED, needs Arun to run the SQL** | 12–18 hrs (~4–6 sessions) | ~10 Aug |
| 9 | ✅ (partial) Org switcher (dual-membership accounts) | Switch UI + session org context | 2–3 hrs | ~12 Aug |
| 10 | ✅ Vendor onboarding polish | First-run wizard: logo, GST, invoice prefix, staff seed | 3–4 hrs | ~14 Aug |
| 11 | 🔨 Subscription billing | Razorpay checkout, plan up/downgrade, trial-expiry lock, webhooks — trial lock ✅, checkout **BLOCKED on real Razorpay keys** | 10–14 hrs (~4 sessions) | ~22 Aug |
| 12 | ✅ (gated) Super-admin platform view | All-tenant list, plan override, usage stats | 4–6 hrs | ~25 Aug |
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
