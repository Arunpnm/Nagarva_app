# Nagarva Mobile App — Project Brief for Claude Code

## What this app is
Flutter mobile app for the packers-and-movers industry. It began as the internal app
for **Arun Packers and Couriers (APC)** and is being evolved into the mobile client of
**Nagarva** — a multi-tenant vertical SaaS/ERP for packers-and-movers companies
(APC becomes tenant #1). Positioning: "industry ERP with one-click Tally export".

The refined feature spec lives in the owner's separate React/Supabase web app
(App.jsx, deployed at arunpkrs.netlify.app). When in doubt about business logic,
that web app's behaviour is the source of truth.

## Origin & structure (important)
This codebase is a **FlutterFlow code export** (project `arun-p-k-r-s-ny5c4z`),
exported 12 Jul 2026 and now developed as plain Flutter. FlutterFlow is no longer
used; edit Dart files directly.

**Read `CLAUDE_ADDENDUM_vendor_flow.md` too.** It documents the vendor
registration/plan requirement (added 12 Jul 2026) and, as of 13 Jul 2026, its
core pieces are already implemented: two-path LoginPage (vendor via Supabase
Auth + staff via phone/PIN), SignupPage, OrgSetupPage, PlanPage, and
`lib/app_session.dart` (AppSession — org/plan/staff session state). This file
was out of date about that until this pass; check actual `lib/` contents
before assuming something described below as "not built" is really missing.

- `lib/<page_name>/..._widget.dart` + `..._model.dart` — one folder per page (FlutterFlow style)
- `lib/flutter_flow/` — FlutterFlow helper library (theme, widgets, `custom_functions.dart`)
- `lib/backend/supabase/` — Supabase client + generated table classes
- `lib/backend/supabase/supabase.dart` — **the** connection config (URL + anon key)

## Environment rules (do not break these)
1. **Flutter SDK is pinned at 3.35.5** (detached HEAD in `C:\src\flutter`).
   **Never run `flutter upgrade`.** Newer Flutter marks `IconData` as `final`,
   which breaks the pinned `font_awesome_flutter 10.x` and `page_transition 2.x`.
   A deliberate modernization (Flutter latest + font_awesome_flutter 11 + patching
   `lib/flutter_flow/flutter_flow_widgets.dart` and `flutter_flow_icon_button.dart`)
   is planned but is its own task — do not do it casually.
2. pubspec pins exact versions (FlutterFlow style). Avoid `flutter pub upgrade`
   unless intentionally doing the modernization task.
3. `lib/flutter_flow/custom_functions.dart` was hand-fixed for null safety
   (null numbers → 0, null dates → ''). Keep function signatures unchanged —
   generated pages call them.
4. If code is ever re-exported from FlutterFlow (should not be needed),
   `lib/backend/supabase/supabase.dart` resets to placeholders and must be re-fixed.

## Supabase backend
- Project: **Nagarva Supabase** — `hqqcapifefsaqvotqvlt`
  URL `https://hqqcapifefsaqvotqvlt.supabase.co` (anon key already in supabase.dart)
- Old single-tenant APC project `yyznvvycxlihtjqlkmlm` — legacy, not used by this app.
- A third project id `xwnvhrecgubikloxkiis` appears in old SQL file headers —
  the dashboard views were originally written for it and were NEVER created in the
  Nagarva project (confirmed by runtime 404s).

Tables used by the app (generated classes in lib/backend/supabase/database/tables/):
orders, leads, staff, expenses, vehicles, attendance, staff_advances, vehicle_trips,
reminders, quotations, materials, settings, complaints, order_staff, order_tracking,
pricing_config, transactions, **organizations, org_members, subscription_plans**
(the last three are the multi-tenant/vendor-flow tables from
CLAUDE_ADDENDUM_vendor_flow.md — already have generated Dart classes; not yet
confirmed to exist as real tables in the live `hqqcapifefsaqvotqvlt` project —
run the `information_schema.tables` query from that addendum to check).
Note: bank_accounts/bank_transactions are mentioned in older notes but have no
generated table class as of 13 Jul 2026 — don't assume they exist.

Views expected: attendance_view, advances_view, trips_view, reminders_view,
dashboard_kpis_view, branch_kpis_view — SQL to create all 6 (reverse-engineered
from the generated table classes, not from the live schema) lives at
`supabase/views_dashboard_and_ops.sql`. Read the assumptions/notes at the top
before running; verify against live column names first.

### `settings` table — current live schema (updated 14 Jul 2026)
- Composite primary key `(org_id, key)`, FK `org_id` → `organizations`. **RLS
  is enabled with two policies.** (This used to say "the first table in the
  app to have real RLS, see below for the other 16" — that was true on 14
  Jul but stale since 15 Jul, when RLS was rolled out to every other core
  table too. See "Multi-tenancy status" below, corrected 1 Aug 2026.)
- `value` is **jsonb**, migrated from `text` on 14 Jul 2026 via a `try_jsonb`
  helper (valid JSON passed through as-is, plain text wrapped as a JSON
  string). Practical effect: legacy numeric-looking values (the invoice
  sequence counter, the opening balance) were valid JSON on their own, so
  they came through as JSON *numbers*, not JSON strings.
  `lib/backend/supabase/database/tables/settings.dart`'s `value` getter was
  updated to coerce any JSON scalar to a String instead of doing a strict
  cast — the old `getField<String>('value')` would have thrown on read for
  every row holding a JSON number. All writes now go through
  `SettingsTable().upsert(data, onConflict: 'org_id,key')` (new method on
  `SupabaseTable`, see `lib/backend/supabase/database/table.dart`) instead
  of the old "insert, catch the conflict, fall back to a key-only update"
  workaround — real upsert semantics now that the composite PK exists.
- Keys already renamed to the app's convention and **the rename migration
  is EXECUTED — do not run `supabase/phase1_rename_settings_keys.sql`
  again**: `inv_seq_<SLUG>_<FY>` → `inv_seq_<FY>` (e.g. `inv_seq_2627`)
  and `accounts_opening_balance:<orgId>` → `accounts_opening_balance`
  (seeded per org, value 0).
- **Invoice counter convention: the stored value is the LAST ISSUED
  number, not the next one.** `_nextInvoiceNo()` in
  `lib/pages/order_detail_page/order_detail_page_widget.dart` does
  read `current` → `next = current + 1` → upserts `next` → returns
  `next` as the invoice number. A fresh FY therefore starts at value
  **0** (first invoice = 001). Verified live 14 Jul 2026: `inv_seq_2627`
  set to 0 after a brief mis-seed at 1 (which would have made the first
  invoice 002). Do not "fix" the counter to 1 for a fresh year.

## Current login flow (REWRITTEN 1 Aug 2026 — was two-path/insecure-by-design,
now PIN-first; verified against `lib/flutter_flow/nav/nav.dart` directly, not
carried over from memory)
The root route `/` (`createRouter`'s `_initialize`) is PIN-first, per Part 7
(`nagarva_part7_login.md`):
- `DeviceOrgBinding.isBound` false → **OrgBindingPageWidget** (`/bind-org`,
  one-time org-code entry via the pre-auth `resolve_org_by_slug` RPC).
- Bound → **PinLoginPageWidget** (`/pin-login`) — the shared 4-digit PIN
  screen for both owner and staff (see the file's own doc comment; also see
  this session's keypad-layout fix, `lib/login_page/pin_login_page_widget.dart`).
  Submits to the `pin-login` or `staff-login` Edge Function depending on
  whether the device is bound to a specific `staff_id`
  (`DeviceOrgBinding.boundStaffId`) or just an org — a person-bound device
  never searches the owner PIN pool at all, which is the structural fix for
  the privilege-escalation bug `verify_org_pin`'s collision guard also
  defends against. Both paths mint a real Supabase Auth session (bcrypt
  verified in Postgres; staff get a shadow `staff-<uuid>@staff.nagarva.in`
  auth user) — there is no client-side/insecure PIN check left anywhere.
- **LoginPageWidget** (`/login`, the old two-tab email/password + phone/PIN
  screen) still exists and is still reachable — both new screens link to it
  ("Use email login instead" / "First time? Log in with email instead") —
  but is no longer the default landing page. It's also still the only path
  that can set an owner's PIN for the first time (Settings' "App PIN" card
  needs a normal logged-in session to reach) and the vendor self-registration
  entry point (→ SignupPage → the `create-org` Edge Function).
- `GoRouter`'s top-level `redirect:` bounces any non-public route to `/login`
  (not `/pin-login`) when `AppSession.isAuthenticated` is false — `/`,
  `/login`, `/signup`, `/survey*`, `/quote*`, `/sign*`, `/track*`,
  `/pin-login`, `/bind-org` are the public prefixes (`_kPublicRoutePrefixes`
  in `nav.dart`); everything else requires a session.
All paths converge on `AppSession.instance` (`lib/app_session.dart`) holding
`currentOrgId`, `currentStaffId`, plan limits/features, `availableOrgs`, etc.

## Page inventory (REWRITTEN 1 Aug 2026 — was a 13 Jul, 28-page snapshot;
the per-page build history below it stops the same day and had gone stale
for weeks. Verified via `nav.dart`'s registered routes directly — 35 named
routes as of today, grouped by area; exhaustive per-page narrative history
was not reconstructed, see the Changelog for that)
- **Onboarding/auth**: OrgBindingPage, PinLoginPage, LoginPage (fallback),
  SignupPage, OrgSetupPage, PlanPage.
- **Core CRM/ops**: HomePage, OrdersPage, OrderDetailPage, LeadsPage,
  LeadDetailPage, NewOrderPage, NewLeadPage, OperationsPage, CalendarPage,
  QuickEntryPage (a 4-button shortcut launcher with no data of its own —
  not a shell, working as designed).
- **Finance**: PaymentsPage, RecordPaymentPage, QuickExpensePage,
  ExpensePage, SalaryPage, AccountsPage, PLReportPage, ReportsPage.
- **Quotation/survey (staff-side)**: QuotationPage (ad-hoc single-total
  quote), SurveyQuotePage (the itemized CFT/charges/GST builder,
  `/survey-quote`), SupervisorJobPage (field-side of the supervisor OTP job
  workflow).
- **People/assets**: UsersPage, FleetPage, MaterialsPage, SettingsPage
  (includes the owner-only Recycle Bin, reached via a button rather than
  its own route).
- **Public, no auth, token-keyed** (customer-facing, built since the 13 Jul
  snapshot this section replaces): SurveyPage (`/survey`), QuotePage
  (`/quote`), SignPage (`/sign`, signature capture via
  `lib/components/signature_pad.dart`), TrackPage (`/track`).
- **Platform**: SuperAdminPage (`/super-admin`, direct-URL only, not linked
  from any nav, gated on a `platform_admins` row).
No empty shells remain anywhere in this list as of today.

## Known bugs / immediate issues
1. **~~dashboard_kpis_view (and likely all 6 views) missing in Nagarva project~~
   — MIGRATIONS REPORTED RUN 13 Jul 2026 ("Phase 0b", a separate session with
   live Supabase access — not this Cowork session; not independently
   verified from here).** HomePage used to throw PGRST205 "Could not find
   the table 'public.dashboard_kpis_view'". SQL to create all 6 views lives
   at `supabase/views_dashboard_and_ops.sql` (written 13 Jul 2026 by reading
   the generated table classes — the original `views_phase1.sql`/
   `views_phase2.sql` files referenced here previously live in
   `C:\Users\Arun\ArunPKRS2\supabase\` on the owner's machine and were not
   reachable from this session; if you can read them, prefer them and diff
   against the new file). The views also select/group by `org_id` (see bug
   #7) and were run AFTER `supabase/phase1_add_org_id.sql`. **Owner-reported
   verify: 3 `subscription_plans` seeded, 1 `organizations` row (APC, fixed
   id, tenant #1), 18 `orders` + 8 `staff` backfilled to APC — this was
   pre-existing test data from web-app usage, now owned by APC.** Still
   needs the boot check confirmed: `flutter run -d chrome` → login →
   Dashboard, to see the views render clean and real KPI numbers (not zeros).
2. **~~SalaryPage renders blank~~ — FIXED 13 Jul 2026.** Root cause was not a
   layout bug (the ListViews already had correct shrinkWrap/primary:false) —
   `initState` simply never queried `StaffTable`, so `_model.staffList` stayed
   empty. Query added.
3. **~~google_fonts fetches fonts at runtime~~ — partially fixed 13 Jul 2026.**
   `GoogleFonts.config.allowRuntimeFetching = false` is now set in main.dart,
   so no more network calls at startup. Still TODO: bundle actual font files
   in assets/fonts/ and declare them in pubspec.yaml, or text will silently
   fall back to the platform default font instead of the intended Google Font.
4. **SettingsPage shows hardcoded placeholders — FIXED 13 Jul 2026** for the
   profile card (business name, phone, GST, email now load from
   `organizations` via `AppSession.currentOrgId`). **Logout — FIXED 13 Jul
   2026 (later pass):** was just `context.pop()`; now calls
   `SupaFlow.client.auth.signOut()`, `AppSession.instance.clear()`, and
   navigates to LoginPage. Still TODO on this page: notifications toggle,
   dark mode persistence, export/backup.
5. **~~Branding hardcoded "Arun Packers & Couriers" on HomePage/LoginPage~~
   — FIXED 13 Jul 2026 (later pass).** LoginPage now shows "Nagarva" /
   "Industry ERP for packers & movers" (it's the shared multi-tenant login
   gateway — no org is known yet at that screen, so platform branding is
   correct here, not per-org). HomePage never actually had hardcoded
   branding text in its UI (only a stale doc comment, now corrected) — what
   it *did* lack was org scoping on its dashboard queries, which is bug #7.
   Per-org branding (business name etc.) already works via SettingsPage/
   `AppSession.currentOrgName`.
6. **Android package id — FIXED 13 Jul 2026.** Was `com.mycompany.arunpkrs`
   (this doc previously said `com.example.my_project`, which was stale — that
   path only survives as the *folder name* for MainActivity.kt, not the
   package). Now `in.nagarva.app`, app label "Nagarva", in build.gradle,
   all 3 AndroidManifest.xml files, strings.xml, and MainActivity.kt's package
   declaration. Proper launcher icons are still the default Flutter icon —
   not done.
7. **Phase 1 multi-tenancy groundwork laid 13 Jul 2026; DB migration
   ~~NOT been run yet~~ REPORTED RUN 13 Jul 2026 ("Phase 0b" sync, not
   independently verified from this session).** `org_id` getters were added
   to all 16 remaining table classes (orders, leads, expenses, vehicles,
   attendance, staff_advances, vehicle_trips, reminders, quotations,
   materials, settings, complaints, order_staff, order_tracking,
   pricing_config, transactions) plus the 4 join views and the 2 KPI views,
   matching the pattern already on `staff`/`org_members`. `.eqOrNull('org_id',
   ...)` filters (reads) and `'org_id': AppSession.instance.currentOrgId`
   stamps (inserts) were wired into HomePage, OrdersPage, LeadsPage,
   NewOrderPage, NewLeadPage, ExpensePage, QuickExpensePage, FleetPage,
   OperationsPage, CalendarPage, QuotationPage (SalaryPage already had it).
   `supabase/phase1_add_org_id.sql` (adds the `org_id` column to all 16
   tables, backfills existing rows to APC, indexes it) and the updated
   `supabase/views_dashboard_and_ops.sql` were reportedly run in order — the
   owner's verify showed 18 orders + 8 staff now carrying APC's org_id.
   Boot check still pending to confirm no page throws "column org_id does
   not exist" in practice.
   **UPDATED 13 Jul 2026 (later pass):** RecordPaymentPage and AccountsPage
   are now org-scoped (AccountsPage was a full rebuild, not just a filter —
   see changelog). Remaining pages NOT yet given org_id filters: PLReportPage,
   ReportsPage (still empty shells, no queries to scope yet), and the
   vendor-flow pages' internal lookups beyond login. OrderDetailPage,
   LeadDetailPage, QuickEntryPage don't need "scoping" yet either — they
   have zero Supabase calls to scope (see Page Inventory correction above);
   they need full data-wiring first.

## Multi-tenancy status (the core architectural gap)
- **UPDATED 13 Jul 2026 ("Phase 0b" sync):** `org_id` getters exist on every
  generated table/view class (see bug #7). The DB migration
  (`supabase/phase1_add_org_id.sql`) and the updated views SQL are
  **reported run** against the live `hqqcapifefsaqvotqvlt` project — owner's
  verify: 3 `subscription_plans`, 1 `organizations` row (APC, tenant #1),
  18 orders + 8 staff backfilled with APC's org_id. Not independently
  confirmed from this session (no live DB/Flutter access here) — pending the
  owner's boot check.
- ~12 pages now filter reads/stamp inserts by `currentOrgId` — see bug #7 for
  the exact list of what's done vs still open. PLReportPage/ReportsPage are
  still empty shells (nothing to scope yet); OrderDetailPage/LeadDetailPage/
  QuickEntryPage need full data-wiring before scoping is even applicable.
- **CORRECTED 1 Aug 2026 (reconciliation pass) — the paragraph below was
  stale since 15 Jul 2026 and had gone uncorrected for over two weeks.**
  `supabase/migrations/20260715_rls_v1.sql` — committed by Arun directly
  the day after the paragraph below was written, not from a Claude Code
  session, which is why it was missed here — enables RLS on all 18
  org-scoped tables (`orders`, `leads`, `staff`, `expenses`, `vehicles`,
  `attendance`, `staff_advances`, `vehicle_trips`, `reminders`,
  `quotations`, `materials`, `complaints`, `order_staff`, `order_tracking`,
  `pricing_config`, `transactions`, `customer_surveys`, `settings`) via an
  `org_isolation` policy (`org_id in (select current_org_ids())`), plus
  `organizations`/`org_members`/`subscription_plans`/`platform_admins`
  individually. `NAGARVA_STATUS.md`'s 26 Jul 2026 entry already caught
  this same staleness and flagged it for a follow-up pass that never
  happened until now. The blocker described below (staff PIN path having
  no real `auth.uid()`) is *also* stale on its own terms — Part 7's
  `pin-login`/`staff-login` Edge Functions (see `nagarva_part7_login.md`
  and `NAGARVA_STATUS.md`) mint a real Supabase Auth session (shadow user,
  bcrypt-verified) for staff PIN logins now, so that precondition is met
  too. The "Current login flow" section above and "Page inventory" section
  below still describe the OLD client-side-PIN/two-tab-LoginPage
  architecture Part 7 replaced — flagged here as a second, related
  staleness this pass did not fix (out of scope for a targeted RLS
  correction; worth its own pass).
  <details><summary>Original 14 Jul 2026 paragraph, kept for history</summary>

  RLS status updated 14 Jul 2026: `settings` now has RLS enabled (two
  policies) — the first of the 17 core tables to get it. The other 16
  (orders, leads, staff, expenses, vehicles, attendance, staff_advances,
  vehicle_trips, reminders, quotations, materials, complaints, order_staff,
  order_tracking, pricing_config, transactions) still have no RLS — anon
  key can still read everything on those, including staff PINs. Per the
  owner: rolling out RLS on the rest is blocked on the staff-login Edge
  Function (see "Current login flow" above) — RLS policies need a real
  auth.uid() to check against, and the staff PIN path doesn't produce one
  yet (it's a client-side Postgres read, no Supabase Auth session). Vendor
  login already uses Supabase Auth, so RLS wouldn't block that path today —
  but policies keyed on org membership need to work for both login paths at
  once, hence waiting for the Edge Function before writing them.
  </details>
- Old/legacy SQL files (`nagarva_schema.sql`, `views_phase1.sql`,
  `views_phase2.sql`) on the owner's machine are considered **superseded**
  by `supabase/phase1_add_org_id.sql` + `supabase/views_dashboard_and_ops.sql`
  per the Phase 0b sync — owner to delete them; not present in this repo so
  nothing to remove here.
- **Stage 1 tenant-safety pass done 14 Jul 2026** (see LEAK_AUDIT.md and the
  "Org scoping convention" section below): a static audit found 10 reads
  with no org_id filter and ~14 writes matching by primary key alone with no
  org_id check. All closed in app code (no SQL run — see
  `supabase/phase1_rename_settings_keys.sql`, EXECUTED live 14 Jul 2026).
  RLS is still the real backstop this doesn't replace — see below.

## Org scoping convention (required for all new queries)
Use `lib/backend/supabase/org_scope.dart`'s `OrgScope` helper instead of
hand-writing `.eq('org_id', ...)`/`.eqOrNull('org_id', ...)` anywhere:
- Reads: `queryFn: (q) => OrgScope.read(q).eqOrNull('status', 'pending')`
- Writes (update/delete) — chain the row filter AFTER `OrgScope.write(q)`,
  never instead of it: `matchingRows: (q) => OrgScope.write(q).eq('id', id)`
- Inserts: spread `...OrgScope.stamp()` into the payload map.
- **Upserts** (any table with a real unique/composite-key constraint —
  currently just `settings`, PK `(org_id, key)` since 14 Jul 2026): use
  `SomeTable().upsert({...OrgScope.stamp(), ...}, onConflict: 'org_id,key')`
  instead of the old "insert, catch the conflict, fall back to an update"
  workaround. Don't reach for that workaround again for a new table unless
  you've confirmed it has no such constraint yet.
- **Never use `eqOrNull` for the row-identifying filter in a `matchingRows`
  (update/delete).** `eqOrNull(col, value)` silently drops the filter
  entirely when `value` is null — fine for an optional read filter, but on a
  write it means a null id doesn't fail, it matches (and updates/deletes)
  every row the org-scope filter allows instead of zero. This is exactly
  what happened in `record_payment_page_widget.dart`'s Save Payment button
  (found after the Stage 1 pass, fixed 14 Jul 2026 — see changelog): the id
  came from a variable that could be null, `eqOrNull` let a null id through
  as "no filter" instead of erroring. The fix pattern: guard for null/empty
  before the call and return early with a user-facing error, then use a
  plain `.eq('id', theNowNonNullId)` so a bug that lets a null through again
  throws instead of silently mutating every row.

All three throw if `AppSession.instance.currentOrgId` is null instead of
silently building an unscoped (all-orgs) query — this is the guard rail from
LEAK_AUDIT.md Stage 1. Every one of the 10 leaks and ~14 write-gaps found in
that audit came from a call site that either forgot the org_id filter or
matched a row by id/key alone; this helper is now used at every query site
in the app (see `git grep "eqOrNull('org_id'"` — should return nothing) so a
new hand-written filter is the thing to flag in review, not the norm.
Two classes of query are deliberately NOT run through this helper because
they run before an org is known by construction: LoginPage's org-resolution
reads and SignupPage's org-creation insert — see LEAK_AUDIT.md's "N/A" rows.
**This is still not RLS.** The helper is a client-side guard rail, not a
database-enforced one — the anon key can still read/write anything if a
request bypasses the app's own queries. RLS policies per org remain the real
backstop (see "Multi-tenancy status" above) and are not superseded by this.

## Roadmap (agreed with owner)
- **Phase 0 — Database foundation:** ~~create the 6 views~~ / ~~add org_id to
  all tables~~ / ~~seed APC data~~ reported done 13 Jul 2026 ("Phase 0b").
  ~~RLS on `settings`~~ done 14 Jul 2026, ~~RLS on the other 16 tables~~ done
  15 Jul 2026 (`supabase/migrations/20260715_rls_v1.sql` — see "Multi-tenancy
  status", corrected 1 Aug 2026 after standing stale here for two weeks).
  ~~Login via Edge Function~~ also done — Part 7's `pin-login`/`staff-login`
  Edge Functions (see `nagarva_part7_login.md`) replaced the old client-side
  staff PIN check with a real bcrypt-verified Supabase Auth session; the
  "Current login flow" section above still describes the pre-Part-7
  architecture and needs its own update pass (not done here, out of scope
  for this correction).
- **Phase 1 — Tenant-safe app:** org_id in every table class, filter on every query,
  stamp on every insert; org-based branding from settings.
- **Phase 2 — Complete the shell pages:** Quotation, Materials, Users
  wired to real data 13 Jul 2026 (see changelog). **Accounts done 13 Jul
  2026 later pass** — turned out to need no schema decision at all (the
  "five-column split / bank_accounts" idea didn't exist in the reference
  app; ported as a Daily Accounts Register instead, see changelog). P&L
  Report and Reports done same session (formulas ported from the React
  web app, see changelog). OrderDetailPage/LeadDetailPage turned out to
  already show real data via nav params — they just needed real actions,
  which they now have (Generate Invoice, Open Field Job, Convert to
  Order, working Edit buttons via edit-mode on NewOrderPage/NewLeadPage).
  QuickEntryPage needed nothing — never a mockup, just a working shortcut
  launcher (see its correction entry). Phase 2 is effectively complete.
- **Phase 3 — Finance layer:** GST invoice (SAC 996719, IGST vs CGST/SGST
  auto-detect, sequential numbering APC/2526/001), porter commission settlement
  (16% local / 19% outstation, minus advance), booking advance freeze,
  double-entry Phase 1 posting.
- **Phase 4 — Field & comms:** supervisor OTP job workflow, attendance,
  AiSensy WhatsApp triggers via Supabase Edge Functions (never call AiSensy
  from the app — keeps API key out of the APK).
- **Phase 5 — Release:** package rename, signed APK/AAB, Play Store; privacy
  policy page live on nagarva.in (also needed for Meta/WhatsApp API).

## Dev workflow
```
cd "C:\Android project\nagarva_app"
flutter run            # choose 1 = Chrome for quick testing
# r = hot reload, R = hot restart, q = quit
flutter build apk --release   # Android build (licenses accepted, cmdline-tools OK)
```
Backup of the previous working build: `C:\Android project\nagarva_app_old`
(May snapshot; delete once confident). Old FlutterFlow DSL workspace (reference
docs only, do not edit): `C:\Users\Arun\ArunPKRS2` — its context/pages.md and
dsl/edit.dart are useful specs of intended behaviour.

## Conventions for Claude Code sessions
- **Changing a function's return type or a view's column type needs an
  explicit `DROP` first — `CREATE OR REPLACE` will not do it.** Postgres
  rejects an in-place type change on both `CREATE OR REPLACE FUNCTION`
  and `CREATE OR REPLACE VIEW`. This has now caused two live failures:
  `42P16` on `reminders_view.due_date` (a view column's type changed) and
  `42P13` on `verify_staff_pin` (`supabase/20260725_staff_pin_rate_limit.sql`
  changed its return table from 5 columns to 7). Fix is `DROP VIEW IF
  EXISTS ...` / `DROP FUNCTION IF EXISTS ...` immediately before the
  `CREATE OR REPLACE`, inside the same transaction so there's no window
  where the object doesn't exist. When writing new SQL that alters an
  existing function/view's shape, add the `DROP IF EXISTS` up front
  rather than finding out from a live 42P13/42P16.
- **Every org-scoped query goes through `OrgScope` (`lib/backend/supabase/org_scope.dart`)** —
  see "Org scoping convention" above. Do not hand-write `.eq('org_id', ...)`.
- Work in small verifiable steps: one page or one migration per commit-sized change.
- After DB changes, paste SQL for the owner to run in the Supabase SQL editor
  (he runs it manually) unless told otherwise.
- Never commit or print service-role keys. Anon key in supabase.dart is fine.
- The owner tests on Chrome via `flutter run`; keep the app bootable at all times.
- **Keep this file current.** It went stale for at least a day (missed the
  entire vendor-flow build-out in CLAUDE_ADDENDUM_vendor_flow.md and had a
  wrong package id) before this pass caught up. Update the relevant section
  whenever you land a fix or discover the doc is wrong, not just at the end
  of a big session.

## Changelog
- **2 Aug 2026 (latest), five more device-test findings — P&L data
  bugs, missing owner notification, decision change on lock timing.**
  1. **Owner got no notification on job completion.** The Awaiting
     Approval badge/queue (added earlier the same day) is pull, not
     push — it only helps if the owner is already looking at Operations.
     `_verifyAndComplete` now writes to two tables on success:
     `notification_log` (migration 006's multi-channel dispatch ledger —
     `event_type: 'otp_completed'` is one of the values its own column
     comment already lists) and `notifications` (what `NotificationBell`
     actually subscribes to via Realtime and renders today). Both,
     deliberately — the ledger alone wouldn't reach the owner until a
     future push pipeline reads it; the bell table alone would lose the
     audit trail the ledger exists for. Both writes are best-effort, so a
     notification failure can't fail the completion transaction itself.
  2. **P&L "Order Expenses" count bug**: `_sumFieldExpenses` returned only
     a running total, never a count, so an order whose costs came
     entirely from `field_expenses` (not the `expenses` table) showed
     "(0 items)" next to a correct non-zero ₹ total. Now returns
     `(total, count)`.
  3. **P&L cost rows at exactly ₹0 read as a red "₹0"**, indistinguishable
     from a real zero cost. `_row` now shows "—" (matching the existing
     null case) for any `negative: true` row whose amount is exactly
     zero. Caught and removed two stale conditions on the way: Staff
     Salary's `_staffCount == 0 ? null : ...` only handled zero
     *headcount*, not zero *salary* (the actual bug — 3 staff, ₹0 total);
     Order Expenses compared `_salaryTotal == _expensesTotal`, two
     unrelated totals, almost certainly a copy-paste leftover.
  4. **Owner had no way to set labour salary at all.** `order_staff
     .salary_amount` existed and the P&L read it, but nothing wrote it
     after the initial "Add Labour" entry — which is the actual reason
     Staff Salary was always ₹0. The amount in `OrderCrewSection`'s
     labour row is now tappable (pencil icon, disabled once the order is
     closed) and opens an edit dialog writing `salary_amount` directly.
  5. **Decision change: lock supervisor edits at OTP success, not at
     Close Order.** Previously field expenses stayed editable until the
     owner closed the order (crew was already effectively locked — the
     step machine simply never re-renders the team picker after
     `done`). `_fieldExpensesCard` now takes an `editable` flag;
     `_doneCard` always renders it read-only (with a lock icon),
     regardless of whether the owner has closed the order yet.
  6. **Confirmed, not changed**: no salary/wage figure is visible
     anywhere in the 5 supervisor screens or the field job page —
     grepped for `salary`/`₹` across all of them. The one screen that
     does show ₹ figures to a supervisor is My Earnings, and only their
     own `order_staff` rows (`staff_id = currentStaffId`), which is the
     point of that screen, not a leak.
- **2 Aug 2026 (later still), supervisor UX follow-up from device
  testing.** Full OTP flow confirmed working end to end (OTP, POD
  capture, lock-after-completion, Awaiting badge) — these are polish/gap
  items found alongside that confirmation, not correctness bugs in the
  flow itself.
  1. **No logout reachable on a supervisor session — real blocker.**
     Supervisors have no drawer and the bottom nav has no account item,
     so there was no way to sign out at all. New `performLogout()`
     (`lib/backend/session_logout.dart`) is now the one shared logout
     sequence — `main.dart`'s `_NavBarPageState._logout` (owner path)
     calls it too, so the two can't drift apart the way the old
     HomePage-drawer Logout tile once did (13 Jul 2026 entry). New
     `SupervisorMenuButton` (`lib/components/supervisor_menu_button.dart`)
     — an AppBar overflow menu with the same Light/Dark/Midnight controls
     as the owner sidebar (`MyApp.of(context).setThemeVariant`) plus
     Logout — added to all 4 supervisor nav screens and the per-order
     Field Job screen.
  2. **Trimmed the supervisor nav from 6 items to 4** (`nav_items.dart`):
     dropped 'Job Entry' (supervisors work assigned jobs, they don't book
     new ones — the screen and its route are parked, not deleted) and
     'Team Attendance' (a ComingSoon stub that turned out fully redundant
     with 'My Team', which already does branch staff + today's
     attendance + mark-present in full — building a second screen for
     the same job made no sense). Also fixes the 6-item bottom nav's
     horizontal-scroll cutoff that was clipping Team Attendance.
  3. **Found and fixed the same class of bug as #1 below, while
     touching this code**: `homeNavNameForCurrentSession()` still returned
     `'SupJobsComingSoon'`, the pre-rename name from before Session 2
     renamed the route to `'SupervisorJobsListPage'`. Since `_tabs`
     doesn't recognise the old name, a supervisor's first login would
     have landed on a blank body until they tapped a bottom-nav item
     themselves. Same root cause as bug #1 (a string-keyed reference that
     drifted after a rename, invisible to `flutter analyze`), caught by
     re-checking rather than assuming the rename was complete everywhere.
  4. **My Jobs now groups by state** (Active / Awaiting Approval /
     collapsed Recently Delivered) instead of one flat list, so delivered
     jobs don't bury active ones as volume grows — device-test
     suggestion, not a defect (the un-grouped list was correct per spec,
     just heading toward a UX problem).
  5. **Field Job's "Customer (hidden after completion)" now shows the
     order id too** (`{orderId} · Customer (hidden)`) — the privacy hold
     itself is deliberate (post-job contact / lead-poaching prevention,
     same rule as OrdersPage/OperationsPage) and stays; a supervisor with
     several completed jobs just had no way to tell which one they'd
     tapped into once the name disappeared.
- **2 Aug 2026 (device test), two bugs found on a real supervisor
  session.** Both were invisible to `flutter analyze` — worth noting,
  since this session repeatedly used "analyze clean" as the proxy for
  correctness and it did not catch either.
  1. **All six supervisor screens rendered ComingSoonPage — Session 2 was
     entirely unreachable.** `main.dart`'s `_tabs` getter had a blanket
     `for (item in _navItems) item.name: ComingSoonPage(...)` for any
     non-owner/manager session. **`_tabs` is the real router for
     bottom-nav tabs**: `NavBarPage` renders `tabs[_currentPageName]`
     directly and `_selectTab` only sets that string — it never goes
     through GoRouter, so the `FFRoute`s Session 2 registered in
     `nav.dart` only ever covered direct URLs and `context.pushNamed`.
     Session 2 updated `nav_items.dart`, `nav.dart` and `index.dart` but
     not this map, so every screen it built still rendered a stub, taking
     the OTP flow and the approval queue that depends on it with it.
     Analyze can't catch this: it's a runtime string-keyed map lookup,
     not a compile-time reference. Fixed by listing the five real
     supervisor screens explicitly (looping is what hid it);
     `StaffTeamAttendance` and the two field-staff destinations stay
     stubs, and are now visibly stubs.
  2. **P&L card read ₹0 on every directly-booked order.** `quote_total`
     is only populated for orders created from a quote; an order booked
     directly carries its value in `amount`. Revenue (Final), Net Profit
     and the margin all read ₹0 with a red 0% dot while Quick Payment on
     the same screen showed a real balance. Revenue base is now
     `quote_total` when non-zero else `amount`. The Quote Amount row
     still reads `quote_total` (honest ₹0 when there was no quote) with
     an "Order Amount" row shown only on the fallback path, so the column
     visibly adds up instead of a total appearing under a ₹0 line.
     **The same assumption was in two more places and was fixed with
     it** — `order_crew_section._markComplete` (Close Order's balance
     warning, which therefore would NOT have warned about a real
     outstanding balance on a directly-booked order — the one thing that
     dialog exists to do) and OperationsPage's Awaiting Approval balance,
     which mirrors it. All three now share the same fallback; if the
     `quote_total`/`amount` split is ever reconciled properly, those are
     the three sites.
- **2 Aug 2026 (last), Awaiting Approval queue — closes the supervisor
  OTP workflow's dead-end.** Found while answering a status-vocabulary
  question (see the entry below): the supervisor OTP flow set
  `supervisor_status = 'completed_pending'`, but `'approved'` was read in
  3 places and **written in 0**, and the owner had no screen listing
  finished-but-unclosed jobs. Arun's call on shape: a **discovery list,
  not a new workflow** — `🔒 Close Order` on Order Details (Session 1,
  owner-only, stamps `closed_at`) already IS the approval action, so no
  second approve button was built.
  - **New 4th section on OperationsPage, above Active Shifting**:
    "Awaiting Approval", `supervisor_status = 'completed_pending'` and
    status not closed/cancelled. Card carries order id, customer, route,
    supervisor name, `job_end_time` and **balance due**. Hidden entirely
    when empty. Tapping opens Order Details, where the owner reviews the
    P&L and closes. Placed on Operations rather than HomePage per Arun:
    it's a work queue sitting next to the other order-state lists, and
    the page is already owner/manager-gated; HomePage is for at-a-glance
    numbers.
  - **Balance due deliberately uses Close Order's own formula**
    (`quote_total` + non-cancelled addons − `paid_total`), NOT
    QuickPaymentSection's `amount`/`advance_paid` one. The point of
    showing it in the queue is that it matches the number Close Order
    hard-warns about, so the owner can chase payment first instead of
    being surprised at the dialog. If those two formulas are ever
    reconciled, reconcile this with `_markComplete`.
  - **Close Order now also writes `supervisor_status = 'approved'`** in
    the same update as `status`/`closed_at`. This is what actually closes
    the loop — it gives `'approved'` its only writer in the app, so the
    three existing read sites can finally be true. Also refreshes the
    badge so the job drops out of the queue immediately.
  - **Badge on the Operations nav item** (`lib/backend/approval_queue.dart`,
    a `ValueNotifier<int>`; `lib/components/nav_badge.dart`, a generic
    icon+count widget). Wired into both nav render sites — the sidebar
    rail and `MobileBottomNav` — and seeded in `NavBarPage.initState` for
    owner/manager sessions, so a waiting job is visible without opening
    Operations. The "which nav item gets which count" decision lives at
    the render sites; `NavBadgeIcon` stays generic. No logout hook needed
    (see `refresh`'s doc comment for why, and for the circular-import
    reason it isn't called from `AppSession.clear()`).
- **2 Aug 2026 (last), OperationsPage status-vocabulary bug.** Arun asked
  for a `grep` of `'in_transit'` across `lib/` after spotting three live
  orders carrying `'transit'`. Found a real bug:
  `operations_page_widget.dart`'s `_activeStatuses` set matched
  `{team_assigned, accepted, shifting_started, in_transit}` — of those,
  **only `team_assigned` is ever actually written by this app**; the other
  three are reference-app names nothing here writes. The value that really
  means "crew is shifting right now" is `'transit'`
  (`supervisor_job_page._startShifting`), and it was in neither
  `_activeStatuses` nor `_upcomingStatuses` — so an in-progress job was
  invisible on the Operations board in **both** sections, not merely
  mis-sorted. Added `'transit'` to the set and to `_statusColor`; left the
  three dead names in place (harmless, would match legacy rows) but
  commented as not-relied-upon, with the real writer list recorded inline
  so the next editor doesn't re-add aspirational values.
  - **Second half of that request could not be confirmed as asked**: the
    "master brief §6.2 legacy status normalisation map"
    (`accepted`→`assigned`, `pending_review`→`delivered`,
    `completed`→`closed`, `unloading`→`in_transit`) **does not exist in
    this repo or this codebase**. `nagarva_master_parity_brief.md` is not
    in the repo at all, and neither `nagarva_parity_brief.md` nor
    `nagarva_master_build_brief.md` contains such a map. The only status
    normaliser in `lib/` is `canonicalOrderStage()`
    (`lib/backend/order_stages.dart`), which is used by exactly ONE caller
    (`track_page_widget.dart`, the public customer timeline), targets a
    different 6-value presentation vocabulary, and disagrees with the
    quoted map on 4 of its 5 pairs (`unloading`→`arrived` not
    `in_transit`; `accepted` and `pending_review` unhandled→null;
    `completed`→`completed` not `closed`). Applying that map app-wide is a
    real architectural change, not a confirmation — flagged for Arun to
    decide rather than invented from a document not in hand.
- **2 Aug 2026 (still later), Order Details Tier 2 Session 2 — Supervisor
  OTP Completion Flow** (Claude Code session; migrations 001-007 live).
  Built against `kickoff_tier2_s2_supervisor_otp.md`'s corrections
  to the master parity brief (odometer lives in `vehicle_trips`, not
  `orders.start_km`, which doesn't exist; OTP completion should also
  create a `pod_records` row). New pages: `supervisor_jobs_page` (My
  Jobs list, the real `sup-jobs` nav destination — distinct from the
  existing per-order `SupervisorJobPage`), `supervisor_entry_page`
  (`sup-entry`), `supervisor_team_page` (`sup-team`),
  `supervisor_earnings_page` (`sup-sal`), `supervisor_attendance_page`
  (`sup-att`) — all 5 ComingSoon stubs in `kSupervisorNavItems` are now
  real screens, registered under new route names in `nav.dart` (updated
  in lockstep in `nav_items.dart`). New `lib/backend/crew_sync_service.dart`.
  - **Part A — the `job_team` → `order_staff` propagation bug, fixed.**
    `job_team`'s actual shape (found by reading the existing
    `supervisor_job_page_widget.dart` before writing anything, per the
    brief's own requirement): a jsonb array of plain `staff.id` strings,
    e.g. `["uuid1","uuid2"]` — no nested shape. `CrewSyncService
    .syncFromJobTeam` now runs on every `job_team` write (both in
    `_startShifting` and the completion transaction): adds an
    `order_staff` row per new id (salary defaulted to `staff.salary / 26`
    rounded — matching `order_crew_section.dart`'s own existing "Add
    Labour" day-rate convention, NOT the raw monthly salary), and removes
    a row for an id dropped from `job_team` only when that row's
    `salary_amount` still exactly equals that default — an edited salary
    is never silently discarded. Back-fill migration handed over, not
    run: `supabase/nagarva_migration_008_job_team_backfill.sql` — only
    touches orders with zero existing `order_staff` rows, so it can't
    clobber crew the owner already entered manually.
  - **Part B, the field job screen rebuilt.** `supervisor_job_page_widget.dart`
    (+ its model) rewritten: crew now displayed from `order_staff` (the
    table Part A keeps in sync), field expenses moved from the old
    `expenses` table to `orders.field_expenses` (migration 007's pinned
    jsonb shape) per the brief's correction, a new odometer section reads/
    writes `vehicle_trips.km_start`/`km_end` (not `orders`) and gates
    "🏁 Shifting Completed — Get OTP" per the brief's corrected rule (never
    blocks when no opening reading was ever captured — third-party
    vehicle), OTP renders at 48px monospace with red/green/neutral entry-
    field borders, and the verified-completion transaction now performs
    all 9 of the brief's steps in one place — including the two the
    original master brief never had: a `pod_records` insert (photo/GPS
    capture skipped and flagged below — see gaps) and marking `attendance`
    present for every crew member. `order_status_history` needed no new
    code — `TrackingService.logStatus` already wrote it.
  - **Part C, 4 thin screens.** Job Entry (minimal order creation via
    `CustomerLookup.findOrCreate`), My Team (branch staff + mark-present),
    My Earnings (this supervisor's own `order_staff` rows by month +
    `staff_advances` balance), My Attendance (this month's own attendance,
    simple date list not a calendar grid). All stayed thin as scoped.
  - **Gaps flagged, not silently worked around**: POD `photo_urls` and
    lat/lng are left empty/null — no confirmed Supabase Storage bucket
    for POD photos, and no location package in `pubspec.yaml` (this app's
    pinned-SDK environment rules warn against casually adding one).
    Confirmed by Arun as deliberate, pairs with planned offline-queue
    work — both need retry paths for supervisors working in basements
    with no signal.
  - **`vehicle_trips` vs `trips` for odometer — confirmed by Arun**:
    `vehicle_trips` (1:1 with an order) is correct and stays; `trips`
    stays for its own separate many-orders-per-vehicle part-load case.
    Two tables, two purposes, no migration needed.
  - **Follow-up same day: migration 008 caught in review before Arun ran
    it.** The first draft applied TODAY's `staff.salary` to every
    matching order regardless of age — for an order already
    `delivered`/`closed`, that fabricates a crew cost that was never
    actually recorded at the time, flowing straight into Session 1's P&L
    card and silently changing a historical profit figure. Fixed: the
    back-fill now excludes `delivered`/`closed`/`cancelled` orders
    entirely — their crew stays unrecorded in `order_staff`, exactly as
    before this migration. Only orders still open/in-progress get
    back-filled.
  - **Follow-up same day: field expense categories expanded 6 → 16.**
    Arun's master brief §6.3 (unavailable when this page was rebuilt)
    turned out to only overlap 2 of the original 6 (Food, Packing
    Material) — instructed to keep all 6 and append the other 10
    (Extra vehicle, AC/TV/Geyser install-uninstall, Carpenter, Crane/
    hydra, Parking, Vehicle repair, Cleaning, Other), not consolidate
    down to a clean 12.
- **2 Aug 2026 (later), migration 007 corrections applied — 3 of 4 Session
  1 gaps closed** (`supabase/nagarva_migration_007_corrections.sql`,
  applied live, file added to `supabase/`). Fixes the entry directly
  below, which is now stale in three places:
  1. **`orders.closed_at` was never actually missing.** It pre-dates
     migrations 001-006 (that's why grepping those files found nothing) —
     confirmed live with the full stage-timestamp set (`assigned_at`,
     `accepted_at`, `loading_started_at`, `delivered_at`, `closed_at`,
     `lr_issued_at`, `invoice_issued_at`). Mark Order Complete
     (`order_crew_section.dart`) now stamps it. Lesson: this was reading
     the migration files as the schema source of truth instead of
     `supabase/schema_snapshot_2026-08-01.csv`, which would have shown it.
  2. **`document_signatures.document_type` CHECK widened** to
     `quote, invoice, proforma, receipt, lr, voucher, packing_list,
     loading_slip, vehicle_condition, pod, contract, order`, plus new
     `order_id`/`is_persistent` columns. `order_documents_section.dart`'s
     signature companion now persists to all 4 companion types (invoice/
     receipt/lr/voucher) at capture time and reloads on page load —
     previously only Invoice could durably persist.
  3. **`next_lr_number(org, branch, fy)`** — atomic, row-locked, same
     contract as `next_doc_number`. LR generation now calls it instead of
     the read-then-write `lr_series` update used before.
  Also backfilled `porter_commission_pct` for existing porter orders
  (16/19 seeded from `order_type`, but `is_porter`+`porter_commission_pct`
  remain the source of truth going forward — the porter-commission
  correction from the entry below stands), and pinned `field_expenses`'
  jsonb shape (`[{"type","amount","note","at"}]`, default `'[]'`, existing
  rows normalised) — `order_pnl_section.dart`'s parsing already assumed
  this shape correctly, now confirmed rather than guessed. **Not fixed,
  out of scope for 007**: Packing List/Loading Slip items still have no
  backing table, still ephemeral per generation.
- **2 Aug 2026, Order Details Session 1 — Tier 2 kickoff, all 5 items**
  (Claude Code session; migrations 001-006 confirmed live via the owner's
  own `information_schema` query, files added to `supabase/`). Built
  against the actual kickoff brief (`kickoff_tier2_s1_order_details.md`,
  found in the repo root partway through — earlier items were built from
  a conversation summary before that file was located, then reconciled
  against it). New files: `lib/order_detail_page/order_pnl_section.dart`,
  `quick_payment_section.dart`, `order_documents_section.dart`,
  `lib/components/simple_document_pdf.dart`,
  `lib/backend/customer_lookup.dart`, `lib/backend/audit_log_service.dart`.
  - **Item 1, P&L card**: Quote + non-cancelled add-ons → Revenue (Final);
    costs from staff salary, order expenses + `field_expenses` jsonb,
    `vendor_bills`, `stock_movements` consumption; health dot at the
    brief's thresholds. **Deliberate correction to the brief itself**: its
    porter-commission formula assumes `orders.order_type` encodes
    local/outstation (×16%/×19%) — this app has no such field; `order_type`
    has only ever meant Direct/Porter here. Used the app's real,
    already-established fields instead: `orders.is_porter` (gate) +
    `orders.porter_commission_pct` (office-picked rate stored per order).
    Gated `canActive('reports','view')`, absent not disabled.
  - **Item 2, Quick Payment Update**: inserts `payment_entries`
    (`orders.paid_total`/`payment_status` update via the existing DB
    trigger, not written directly), mints a receipt number via
    `next_doc_number(org,'receipt',branch,fy)` for the confirmation
    toast/ledger narration, posts `ledger_entries` (party_type customer).
    Over-collection requires explicit confirm. `ledger_entries.party_id`
    is NOT NULL, so this needed `orders.customer_id` populated — added
    `CustomerLookup.findOrCreate` (match-by-`norm_phone`, same algorithm
    as migration 001's own backfill) and wired it into `new_order_page`'s
    create path (the actual source of new unlinked orders — the
    migration's own backfill had already linked every pre-existing order)
    and, defensively, into Quick Payment itself.
  - **Item 3, Duplicate Order**: clones shipment/pricing fields per the
    brief's §3 list (plus `is_porter`/`porter_commission_pct`, not in the
    brief's literal list but required for P&L consistency on a cloned
    Porter order), resets to `status: 'pending'`, notes → `Copy of
    {source_id}`, asks for move date inline. Lives in the Documents
    section's utility row ("⧉ Copy") per the brief's placement, not as a
    standalone button.
  - **Item 4, Documents grid**: Tax Invoice reuses the existing
    `InvoicePdf` (now numbered via `next_doc_number` instead of the old
    `settings`-based counter — this starts a new series, does not
    continue `inv_seq_<fy>`). The other 7 documents are generated through
    one shared `SimpleDocumentPdf` builder on `PdfBranding`'s primitives.
    Signature companion: in-app capture (`SignaturePad`, already existed)
    held in section state, applied to every document generated until
    explicitly cleared. **Schema gap, not worked around**:
    `document_signatures.document_type` has a CHECK constraint limited to
    `('quote','invoice')`; the brief wants the companion signed-persisted
    for Invoice/Receipt/LR/Voucher. Only Invoice durably persists — the
    other three carry the signature into that generation's PDF but can't
    reload it after leaving the page. LR/Bilty numbering used a
    read-then-write against `lr_series` (no atomic RPC exists for it —
    `next_doc_number` doesn't list `lr` as a doc_type), same accepted
    non-atomic pattern the old invoice counter used. Packing List/Loading
    Slip items aren't persisted (no backing table). "Copy Track Link"
    reuses the existing token-based `/track` link rather than the brief's
    literal `?track={orderId}` shape — that would have exposed tracking
    by guessable order id with no token check.
  - **Item 5, Mark Order Complete**: in the Crew section below the labour
    list, full-width green, gated `canActive('orders','edit')`. Hard
    warning + explicit confirm on non-zero balance, warns if unbilled,
    writes `status: 'closed'`. **Schema gap, not worked around**: the
    brief calls for stamping `closed_at`, but no such column exists in
    any of the 6 migrations, and the brief's own constraints say no new
    SQL this session — status is written, the timestamp is not. "Lock the
    P&L" implemented as a UI lock (Quick Payment hides, Add/Remove
    Labour/reassign-supervisor disable) rather than a DB flag, same
    reason. **Found and fixed a real bug while wiring this in**:
    `OrdersPage`'s "Completed" tab filter didn't include `'closed'` at
    all — a closed order would have silently landed in "Pending" instead
    (the filter's own comment already anticipated `'closed'` in the
    customer-privacy check two lines above, just not in the tab logic).
  - **Audit logging added retroactively for items 2-3 too**: the brief's
    constraints require every write to log to `audit_log` with
    old_value/new_value/changed_fields (migration 005 columns) — missed
    on the first pass through items 1-3 (built from a summary before the
    brief file was found), added once caught. New `AuditLogService`
    (parallel to `SoftDeleteService`'s existing private `_audit`, which
    still only writes the pre-005 columns for delete/restore).
  - **Stale generated Dart classes fixed along the way** (flagged by
    Arun as "32 files for 131 database objects" — not regenerated
    wholesale, fixed field-by-field as each was actually needed):
    `orders.dart` (+`customerId`, `rateCardId`, `contractId`),
    `payment_entries.dart` (+`accountId`, `reference`, `reconciled`,
    `reconciledAt` — all real migration-001 columns), `organizations.dart`
    (+`upiId`, `address`), `audit_log.dart` (+`oldValue`, `newValue`,
    `changedFields`, `actorRole`).
  - **Not done / flagged for the owner rather than guessed**: whether
    `document_signatures`'s CHECK constraint should be widened (needs a
    migration Arun runs); whether `lr_series` should get a real atomic
    RPC like `next_doc_number` has; whether `orders` should get
    `closed_at`/a `pnl_locked` flag. All three are additive, low-risk
    migrations, not written per the brief's explicit "no new SQL, report
    instead" instruction.
- **1 Aug 2026, "Current login flow" + "Page inventory" rewritten
  (NG-002 remainder, consolidated module register).** Both sections were
  flagged as stale in the same-day RLS-correction entry below but
  deliberately left untouched then — this closes that out. "Current login
  flow" described the pre-Part-7 two-tab LoginPage with an insecure
  client-side staff PIN check; rewritten against `nav.dart` directly to
  describe the actual PIN-first `_initialize` route, the
  owner/staff-pool split via `DeviceOrgBinding.boundStaffId`, and the
  `redirect:`/`_kPublicRoutePrefixes` auth guard. "Page inventory" was a
  13 Jul 2026 snapshot (28 pages) with a long since-superseded per-page
  correction history; rewritten as a grouped list of all 35 routes
  currently registered in `nav.dart` (verified by grep, not reconstructed
  from memory) rather than re-narrating each page's build history — the
  four public token-keyed customer pages (Survey/Quote/Sign/Track) and
  SuperAdminPage didn't exist at all in the section being replaced.
- **1 Aug 2026, RLS section corrected (reconciliation pass).** This doc's
  "Multi-tenancy status" section and its two cross-references (the
  `settings` schema note, the Roadmap's Phase 0 entry) had claimed since
  14 Jul 2026 that only `settings` had RLS and the other 16 tables were
  blocked on the staff-login Edge Function. Both halves of that claim went
  stale the very next day: `supabase/migrations/20260715_rls_v1.sql`
  (committed by Arun directly, not from a Claude Code session) enabled RLS
  on all 18 org-scoped tables, and Part 7's `pin-login`/`staff-login` Edge
  Functions later gave the staff PIN path a real Supabase Auth session.
  `NAGARVA_STATUS.md`'s own 26 Jul 2026 entry had already caught this same
  staleness and deferred the fix to "next session" — that session didn't
  happen until today. All three spots corrected in place (old text kept
  in a collapsed `<details>` block on the main one, for history). The
  "Current login flow" and "Page inventory" sections are flagged as a
  second, related staleness (still describe the pre-Part-7 architecture)
  but were **not** rewritten this pass — out of scope for a targeted RLS
  correction, worth its own pass.
- **14 Jul 2026 (later), migrations verified live + counter convention fix**
  (claude.ai session, owner ran SQL in the Supabase editor with screenshots):
  - Confirmed `settings.value` is jsonb on the live DB
    (`SELECT jsonb_typeof(value), count(*)` returned string×3, number×2 —
    no errors).
  - Key rename executed live: `inv_seq_APC_2627` → `inv_seq_2627`;
    `accounts_opening_balance` seeded per org (2 rows, value 0 — table
    spans two org_ids). Live `settings` now: `accounts_opening_balance`
    ×2, `address`, `city`, `inv_seq_2627`, `monthly_target`, `state`.
  - **Caught and fixed a counter mis-seed**: `inv_seq_2627` was briefly
    set to 1 on the assumption the value is the *next* number. Code review
    of `_nextInvoiceNo()` showed the convention is *last issued* (read →
    +1 → store → use), so 1 would have made the first invoice APC/2627/002
    and skipped 001. Reset to 0. Schema section above updated with the
    convention so this isn't re-broken.
  - Corrected this doc's own earlier wording ("value = next invoice
    number") in the `settings` schema section — it was wrong.
- **14 Jul 2026, settings jsonb/composite-PK/RLS sync** (Cowork session —
  owner reported live DB changes made outside this session: `settings` now
  has a composite PK `(org_id, key)` with RLS enabled (two policies),
  `value` migrated from `text` to `jsonb`, and the key-rename migration
  (`supabase/phase1_rename_settings_keys.sql`, written in the Stage 1 pass
  above) has been executed. Still no working Flutter/bash toolchain in this
  session — nothing below is `flutter analyze`/`flutter run`-verified).
  - **Fixed a real crash risk from the jsonb migration**:
    `settings.dart`'s `value` getter did `getField<String>('value')`, a
    strict cast. Legacy numeric-looking values (the invoice counter, the
    opening balance) were valid JSON on their own, so the migration's
    try_jsonb helper stored them as JSON *numbers*, not strings — every
    read of those rows would have thrown a cast exception. Fixed to coerce
    any JSON scalar to its String form, with a whole-number-double special
    case (`1.0` → `"1"`) so `int.tryParse` in the invoice
    counter/opening-balance code doesn't silently fail and reset the
    counter to 0.
  - **Added `SupabaseTable.upsert()`** (`lib/backend/supabase/database/table.dart`)
    now that a real composite PK exists to upsert against. Replaced the
    "insert, catch the conflict, fall back to a key-only update" workaround
    in `accounts_page_widget.dart` (opening balance) and
    `order_detail_page_widget.dart` (invoice counter) with
    `SettingsTable().upsert(data, onConflict: 'org_id,key')`.
  - **`org_setup_page_widget.dart`'s onboarding settings insert** was a
    plain `.insert(rows)` — with the composite PK now live, saving that
    page twice for the same org (e.g. the owner edits business details
    after finishing onboarding) would throw a duplicate-key error. Switched
    to `.upsert(rows, onConflict: 'org_id,key')` and, while touching it,
    switched the manual `'org_id': orgId` stamps to `...OrgScope.stamp()`
    for consistency with the rest of the app.
  - **Reconciled the "plan_id NULL on signup" item** the owner's DB note
    listed as still pending: checked `signup_page_widget.dart` and the
    13 Jul 2026 "signup plan_id fix" changelog entry below — the code fix
    (fetch the default trial plan before the `organizations` insert, stamp
    `plan_id`/`plan_status`/`trial_ends_at` on creation) is still in place
    and wasn't touched or reverted by anything since. Not re-fixed, since
    there's nothing wrong with the code; if new orgs are still landing with
    a null `plan_id`, the bug is elsewhere (a live-DB check of
    `is_default_trial` on `subscription_plans`, or a signup path that
    bypasses this page, would be the next things to check) — flagged here
    rather than silently doing nothing or duplicating a fix that already
    exists.
  - **RLS is on `settings` now** (see schema note above) — the first of 17
    core tables to get it. Updated "Multi-tenancy status" and the Roadmap's
    Phase 0 entry accordingly. The other 16 tables are still unprotected,
    blocked on the staff-login Edge Function per the owner's plan.

- **14 Jul 2026, Stage 1 follow-up — eqOrNull-in-write fix** (Cowork
  session, same conversation, addressing the one residual gap flagged at
  the end of the Stage 1 pass below). Fixed
  `record_payment_page_widget.dart`'s Save Payment button: it matched with
  `OrgScope.write(rows).eqOrNull('id', _model.selectedPayOrderId)`, and
  `selectedPayOrderId` could reach null (set from `OrdersRow.id`, which is
  nullable, and the section's visibility guard only checked `== ''`, not
  null) — `eqOrNull` would have silently dropped the id filter and updated
  every order in the org. Fixed by guarding for null/empty before the call
  (shows a SnackBar and returns early) and switching to a plain
  `.eq('id', orderId)` so this can't regress silently. Then grepped the
  entire app for every `matchingRows:` call site (`git grep "matchingRows:"`)
  and every remaining `eqOrNull` — confirmed this was the only write using
  `eqOrNull` as its row filter; every other `update`/`delete` in the app
  already used a plain `.eq(...)` (either from the Stage 1 pass or
  pre-existing). Added the rule to "Org scoping convention" above so this
  class of bug is called out for anyone writing a new update/delete.

- **14 Jul 2026, Stage 1 — tenant-leak fixes** (Cowork session, following up
  on a static LEAK_AUDIT.md audit from a prior session in the same
  conversation; still no working Flutter/bash toolchain, `flutter analyze`
  attempted at the end — see result noted there — nothing here is
  `flutter run`-verified). Work order was LEAK_AUDIT.md's 10 flagged leaks
  + ~14 write-gap rows. No SQL was run.
  - **New helper: `lib/backend/supabase/org_scope.dart`** (`OrgScope` class)
    — see "Org scoping convention" section above. Swept the entire codebase
    to use it instead of hand-written `.eq('org_id', ...)`/`.eqOrNull(...)`
    (`git grep "eqOrNull('org_id'"` now returns nothing).
  - **Leak #1 (payments_page)** — decided to fix in place, not delete:
    checked `main.dart`'s `NavBarPage` tabs map first and found PaymentsPage
    is a live bottom-nav tab (Home/Orders/Leads/Operations/**Payments**/
    Expense/Salary/Fleet/Settings), not dead/orphaned code as the audit
    guessed from it being missing off CLAUDE.md's page inventory. Added the
    missing org_id filter instead of removing the page/route.
  - **Leak #2** (salary_page `attendance_view`/`advances_view` queried with
    no filter at all) — fixed.
  - **Leaks #3/#4** (new_order_page/new_lead_page edit-mode loads matching
    only on `id`) — fixed, plus their edit-mode save updates (write gaps).
  - **Leaks #5/#6** (order_detail_page invoice_no check + invoice-sequence
    counter) — fixed. Also renamed the settings key from
    `inv_seq_<SLUG>_<FY>` to `inv_seq_<FY>` now that org_id scopes it (the
    display-facing invoice number, e.g. "APC/2526/001", is unaffected — only
    the internal DB lookup key changed). Migration for existing rows:
    `supabase/phase1_rename_settings_keys.sql` (EXECUTED live 14 Jul 2026).
  - **Leaks #7/#8** (supervisor_job_page job load + OTP re-fetch) — fixed,
    plus all 5 `OrdersTable().update(...)` write gaps in that file.
  - **Leak #10** (accounts_page opening-balance settings row) — fixed.
    Renamed key from `accounts_opening_balance:<orgId>` to
    `accounts_opening_balance` (same migration file as above).
  - **Leak #9 (staff login) deliberately left untouched** per instruction —
    owner is replacing that path with a Supabase Edge Function next.
  - **All other write gaps closed**: record_payment_page's save, both of
    operations_page's approve/reopen updates, lead_detail_page's
    convert-to-order status flip. Every `update`/`delete` `matchingRows` in
    the app now chains `OrgScope.write(q)` before the row-identifying filter.
  - **Known residual gap, not in scope for this pass, flagged for next
    session**: `record_payment_page_widget.dart`'s save button calls
    `OrgScope.write(rows).eqOrNull('id', _model.selectedPayOrderId)` — the
    `eqOrNull` means if `selectedPayOrderId` is ever null when Save is
    pressed, the update would match every order in the current org instead
    of none. Pre-existing behavior (previously it would have matched every
    order in every org), not one of LEAK_AUDIT.md's listed items, but worth
    a follow-up: either guard the button so it can't fire without a
    selected order, or switch to a plain `.eq` so a null id fails loudly.
  - **RLS is still not in place.** This pass is a client-side guard rail
    (see "Org scoping convention"), not a substitute for RLS policies — the
    anon key can still bypass all of this via a raw request. Still the next
    real gap per the Roadmap.

- **13 Jul 2026, full-parity pass — edit-mode for NewOrderPage/NewLeadPage**
  (same session — owner said "complete this fully, next we will have
  flutter run," so this closes out the last open item from the task list
  before the owner's first real build/boot check. Still no working
  Flutter/bash toolchain here — nothing below is build-verified, this is
  the first thing worth running `flutter analyze` against.):
  - **NewOrderPageWidget and NewLeadPageWidget now accept an optional
    `orderId`/`leadId`.** When set, `initState` loads the existing row
    (`OrdersTable`/`LeadsTable`, queried by `id`) and populates every text
    controller plus each dropdown's value **and** its underlying
    `FormFieldController` — setting only the plain model field (e.g.
    `ordService`) is not enough once the dropdown has already built once,
    since `FlutterFlowDropDown` is driven by a lazily-created
    `FormFieldController` (`ordServiceDropdownValueController ??=
    FormFieldController(...)`) that doesn't re-read the model field after
    creation. Both is required: `_model.ordService = order.service;
    _model.ordServiceDropdownValueController?.value = order.service;`.
  - **Save button branches on `widget.orderId`/`widget.leadId`**: edit
    mode calls `.update(data:, matchingRows: (q) => q.eq('id', ...))`
    instead of `.insert(...)`, button text changes to "Update
    Order"/"Update Lead", and on success it just pops back to
    OrderDetailPage/LeadDetailPage instead of also pushing
    OrdersPage/LeadsPage. Edit mode's update payload only touches the
    fields actually on the form (customer/addresses/amount/service/
    branch/order_type/porter fields/notes) — it deliberately does **not**
    touch `status`, `payment_status`, `tracking_status`, or
    `advance_paid`, so editing shipment details can't silently reset
    payment progress or job status that RecordPaymentPage/
    SupervisorJobPage set separately.
  - **Wired the two entry points**: OrderDetailPage's "Edit Order" and
    LeadDetailPage's "Edit Lead" buttons now pass `orderId`/`leadId` as a
    query param instead of navigating to a blank form; `nav.dart`'s
    `NewOrderPageWidget`/`NewLeadPageWidget` routes now read that param
    and pass it through.
  - This was the last item on the task list from this session's
    full-parity pass — see the punch list two entries up. Everything
    queued there (Accounts, PLReport, Reports, GST invoice, porter
    settlement, supervisor OTP workflow, edit-mode) is now done, pending
    the owner's `flutter run`/`flutter analyze` boot check.

- **13 Jul 2026, full-parity pass — QuickEntryPage correction** (same
  session, wrapping up): went to rebuild QuickEntryPage per the task list
  and found there was nothing to fix — it's a 4-button shortcut launcher
  (New Inquiry / Confirm Booking / Record Payment / Quick Expense) with no
  data of its own, each button already correctly navigates to a real page.
  It had been wrongly queued alongside OrderDetailPage/LeadDetailPage
  earlier this session on the assumption all three needed the same
  treatment. Corrected the Page Inventory section above. Net effect: the
  only genuinely open items from this session's task list are edit-mode
  for NewOrderPage/NewLeadPage (so OrderDetailPage's "Edit Order" and
  LeadDetailPage's "Edit Lead" buttons actually work) — everything else
  queued at the last checkpoint (Accounts, PLReport, Reports, GST invoice,
  porter settlement, supervisor OTP workflow) is done.

- **13 Jul 2026, full-parity pass — supervisor OTP workflow** (same
  session, same "continue"; checked in with the owner first — chose
  "keep going, same order." Still no working Flutter/bash toolchain,
  nothing below is build-verified):
  - **New page: SupervisorJobPage** (`lib/supervisor_job_page/`,
    registered in `lib/index.dart` and `lib/flutter_flow/nav/nav.dart`,
    route `/supervisor-job?orderId=...`) — the field-side of the
    supervisor OTP job workflow from apc_webapp App.jsx's
    SupervisorJobPage (lines ~10369-10597). Adapted to this app's real
    schema rather than copied verbatim — two deliberate deviations, both
    documented in the file's doc comments:
    1. This app's `orders.status` vocabulary is booked/pending/confirmed/
       transit/delivered/cancelled (see OrdersPage's 5 tabs), not the
       reference app's finer-grained pending/confirmed/assigned/accepted/
       loading/in_transit/delivered/closed. Rather than introduce new
       status values nothing else in the app understands (which would
       make jobs vanish from every OrdersPage tab while in progress), the
       step machine here tracks progress mainly via `supervisor_status`
       (null → in_progress → completed_pending → approved, same as the
       reference app) and only touches `status` twice: → 'transit' when
       shifting starts, → 'delivered' on verified completion.
    2. This app's orders table has `job_start_time`/`job_end_time`
       (timestamps) where the reference app has `start_km`/`end_km`
       (odometer) — there's no odometer column here at all, so the flow
       auto-captures timestamps instead of asking the supervisor to type
       odometer readings.
    Flow: Accept Job → pick labour team (from active `staff`, org-scoped)
    → Start Shifting (stamps `job_team` + `job_start_time`, order →
    'transit') → log job expenses (writes real `expenses` rows) + notes
    → Generate Completion Code (4-digit OTP, `Random().nextInt`, written
    to `orders.job_otp` + `job_end_time`) → Verify & Complete.
    **Security fix vs. the reference app** (flagged as a gap two
    changelog entries ago, now fixed): OTP verification here re-fetches
    `orders.job_otp` from the DB and checks the entered code against
    that, not just the in-memory value the reference app trusts — a
    previous pass's read of App.jsx flagged the reference app's
    in-memory-only check as a real security gap not worth copying.
    On verified match: `supervisor_status` → 'completed_pending', order
    → 'delivered' (if not already delivered/closed), an `order_tracking`
    row is logged.
  - **~~Owner-side approval added to OperationsPage~~ — NO LONGER TRUE,
    corrected 2 Aug 2026.** This entry claimed a "Pending Approvals"
    section listing `supervisor_status == 'completed_pending'` orders
    with Approve/Reopen buttons. **It is not in the code today**:
    `operations_page_widget.dart` renders exactly three sections (Active
    Shifting / Upcoming / Vehicle Trip Log) and contains no reference to
    `completed_pending` at all. The only trace left is
    `OperationsPageModel.pendingApprovals` — a declared field the widget
    never populates or reads, i.e. dead state from the rewrite that
    dropped the section. Almost certainly lost in the later OperationsPage
    rewrite (the one that replaced the FlutterFlow decoration with real
    `orders`/`vehicle_trips` queries), not deliberately removed.
    **Consequence — a live workflow dead-end:** the supervisor OTP flow
    writes `supervisor_status = 'completed_pending'` and My Jobs shows
    "⏳ Awaiting", but nothing anywhere in `lib/` ever wrote `'approved'`
    (grep at the time: read in 3 places, written in 0). So a supervisor's
    completed job waited forever for an approval the owner had no UI to
    give. **Closed the same day — see the entry above.**
  - **OrderDetailPage**: added an "Open Field Job" button (next to
    "Generate Invoice") that navigates to SupervisorJobPage for that
    order.
  - **Not done yet, next up**: QuickEntryPage (still 100% static, no
    real params even) and edit-mode for NewOrderPage/NewLeadPage (both
    still create-only — OrderDetailPage's "Edit Order" and
    LeadDetailPage's "Edit Lead" buttons remain broken, noted two
    changelog entries ago).

- **13 Jul 2026, full-parity pass continued further** (same session, same
  "continue" — still no working Flutter/bash toolchain, nothing below is
  build-verified):
  - **GST invoicing added to OrderDetailPage** (task from Phase 3):
    SAC 996719, interstate-vs-intrastate detection via the same city→state
    lookup table as apc_webapp App.jsx (defaulting unknown cities to Tamil
    Nadu), IGST @5% or CGST+SGST @2.5%+2.5% split (flat 5% assumed — no
    per-order `gst_pct` column exists yet, same simplification as
    PLReportPage's GST summary), and sequential invoice numbering
    (`<ORGSLUG>/<FY>/NNN`, FY = Apr-Mar, counter stored in `settings`,
    cached onto `orders.invoice_no` so re-generating reuses the same
    number). Shown as a copyable text invoice in a dialog rather than a
    PDF/print — this app has no PDF/printing package in pubspec.yaml and
    adding one wasn't done blind in a session with no compiler to verify
    the build against; flagged as a gap, not silently dropped.
  - **Found OrderDetailPage/LeadDetailPage are not actually "100% hardcoded
    mockups" the way this doc said a few entries up** — correction to that
    correction: they DO receive and display real data (passed as
    navigation query params from OrdersPage/LeadsPage, e.g.
    `widget.orderCustomer`), they just have zero further actions wired up
    (no status changes, no edit, no tracking). QuickEntryPage is still
    genuinely 100% static with no real params either.
  - **Fixed LeadDetailPage's "Convert to Order" button** — it only
    navigated to a blank NewOrderPage before, discarding the lead entirely
    and never marking it converted (so it could never count toward
    PLReportPage's lead-source conversion rate, which reads
    `leads.status == 'confirmed'`). Now inserts a real `orders` row from
    the lead's fields (amount defaults to 0 — a lead has no quoted amount)
    and flips the lead to `status: 'confirmed'`.
    - **Still broken, not touched this pass**: OrderDetailPage's "Edit
      Order" and LeadDetailPage's "Edit Lead" buttons both just navigate to
      a blank NewOrderPage/NewLeadPage with no edit mode (would create a
      *second* order/lead, not edit the existing one). Fixing this needs
      edit-mode support added to those two create-only forms — a
      contained but real follow-up task, not attempted blind in the same
      pass as everything else above.
  - **Not done yet, next up**: supervisor OTP job workflow (still fully
    open — formulas/flow already extracted from apc_webapp App.jsx in an
    earlier entry, ready to port); QuickEntryPage rebuild; NewOrderPage/
    NewLeadPage edit-mode; order status-change + tracking timeline UI on
    OrderDetailPage.

- **13 Jul 2026, full-parity pass continued** (same Cowork session, resumed
  after a status checkpoint — owner said "continue"). Still no working
  Flutter/bash toolchain; nothing below is build-verified.
  - **PLReportPage and ReportsPage rebuilt** (were 100% hardcoded, see Page
    Inventory correction above — now moved to "wired"). PLReportPage: period
    selector (month/quarter/year/all), revenue/expenses/net-profit/margin
    cards, branch P&L bars, lead-source conversion (reads `leads.source`/
    `status`), a GST summary block (5% bracket only, same limitation the
    reference app has — no per-order `gst_pct` column exists yet so a flat
    5% is assumed). ReportsPage: period selector + customer/city search,
    branch-wise revenue cards, last-6-months volume chart (not period-
    filtered, matches reference app), all-time top 10 customers by revenue
    (also not period-filtered, matches reference app), service mix bars.
    Formulas match the extraction from apc_webapp App.jsx lines 6350-7445
    with one faithfully-preserved reference-app quirk: PLReportPage's
    "other expenses" total is NOT period-filtered there (`expenses.filter(
    e=>!e.order_id)`, no date check) — kept as-is rather than "fixing" it,
    since it's the source-of-truth app's actual behavior.
  - **Found and fixed a real bug while wiring the porter commission
    formula into the two report pages above**: `orders.order_type` in
    *this* app has never meant "local"/"outstation" the way it does in the
    reference web app — there's no local/outstation field anywhere in
    NewOrderPage. This app's own (already-designed, already in the
    generated table class) mechanism is `orders.is_porter` +
    `orders.porter_commission_pct`, where the office picks 16% or 19%
    directly on a dropdown instead of deriving it from distance. First
    draft of AccountsPage/PLReportPage wrongly assumed the reference app's
    `order_type == 'outstation'` check — corrected to use `is_porter` +
    `porter_commission_pct` (defaulting to 16% if unset) in both files.
  - **NewOrderPage: fixed a pre-existing bug where the Porter Commission %
    dropdown was captured in the model (`ordPorterComm`) but never actually
    saved** — the insert payload only wrote `order_type` (Direct/Porter)
    and silently dropped the commission choice. Now also stamps `is_porter`,
    `order_source` ('porter' when applicable), and `porter_commission_pct`.
    Added the missing porter cash-flow fields from apc_webapp App.jsx's
    order form (lines ~3656-3736): a "Cash Collected by Porter" input
    (shown only when Order Type = Porter) and a live settlement preview
    (Advance the porter already paid / Commission / Net to APC), with
    `advance_paid` and `payment_status` now computed from that instead of
    always being hardcoded to `0.0`/`'pending'` for porter orders.
  - **Not done yet, next up**: GST invoicing UI, supervisor OTP workflow,
    and the OrderDetailPage/LeadDetailPage/QuickEntryPage rebuilds (task
    list unchanged from the checkpoint above).

- **13 Jul 2026, full-parity pass** (Cowork session — owner asked to bring
  the app to complete feature parity with the two reference web apps, now
  available at `reference/APC Web App JSX/App.jsx` (production logic
  source of truth per this doc's own convention) and
  `reference/Nagarva Web App JSX/Nagarva-App (1).jsx` (platform spec). No
  working Flutter/bash toolchain in this session — nothing below is
  build-verified with `flutter analyze`/`flutter run`; treat as "should
  compile" until the owner confirms. This is a large, multi-part pass;
  more of it remains open than closed — see the punch list at the end.
  - **Extracted exact business logic from the ~10,000-line reference
    App.jsx** for the five subsystems this doc's roadmap deferred to
    "port from the React web app": the Daily Accounts Register, porter/
    labour commission settlement, GST invoicing, the supervisor OTP job
    workflow, and P&L/Reports. Full formulas, field names, and code
    snippets captured; summarized in the sections below and still held in
    this session's context for the follow-up pages.
  - **HEADLINE CORRECTION:** the "AccountsPage blocked on a
    `bank_accounts`/`bank_transactions` five-column-split schema decision"
    claim (in this doc since the vendor-flow build-out) was wrong — grepped
    the entire reference app, zero matches for `bank_accounts` or a
    "five column" concept. `CO.bank`/`bankAcc`/`bankIfsc`/`upi` are just
    static company-profile fields printed on invoices. The real
    `AccountsPage` in the reference app (line 8522) is a **Daily Accounts
    Register**: a read-only, per-day cash-flow ledger computed entirely
    from `orders` + `expenses` (+ embedded `order_staff` for labour
    salary), with a running balance seeded from an editable opening
    balance. No new tables needed.
  - **AccountsPage rebuilt** (`lib/accounts_page/accounts_page_widget.dart`
    + `accounts_page_model.dart`) — was 100% hardcoded (fake "SBI Current
    A/C ₹2,84,500" cards, fake transactions). Now: queries `orders`,
    `expenses`, `order_staff` org-scoped, groups by `orders.move_date`,
    computes per-day revenue/collections/advance/pending/salary/order-
    expenses/other-expenses/porter-commission/profit-loss exactly per the
    reference formula (see DailyAccountRow doc comment in the model file),
    running balance chronological from an opening balance stored in
    `settings` (key `accounts_opening_balance:<orgId>`, editable via an
    AppBar action + dialog), summary chips (period revenue/expenses/net),
    and a tap-to-expand day-detail bottom sheet listing that day's orders
    with value/collected/pending plus the expense/salary/commission
    breakdown. Two known simplifications vs. the reference app, both
    flagged in code comments: (1) `orders.extra_charges` (jsonb) and
    `orders.booking_advance` aren't columns on this app's `orders` table
    yet, so "quote" and "advance" collapse to `amount`/`min(amount,
    advance_paid)` rather than the reference app's fuller formula — revisit
    once/if those columns get added; (2) no CSV export (reference app has
    one, mobile doesn't need it as urgently — flagged as a gap, not
    silently dropped).
  - **RecordPaymentPage org-scoped**: added the missing
    `.eqOrNull('org_id', AppSession.instance.currentOrgId)` filter to its
    pending-orders query (bug #7's list). Small, mechanical fix.
  - **Attempted the same for OrderDetailPage/LeadDetailPage/QuickEntryPage,
    found a bigger problem**: none of the three make any Supabase call at
    all — confirmed by grep for `Table()`/`queryRows`/`FutureBuilder`/
    `StreamBuilder`, all zero matches. This doc previously listed them as
    "wired and mostly working," which was inaccurate (see Page Inventory
    correction above). Did not attempt to wire these in this pass — each
    is a rebuild on the scale of AccountsPage/UsersPage, not a filter
    tweak, and doing three of those blind (no compiler) in the same pass
    as everything else risked a large unreviewable diff. Left as open work.
  - **Not done this pass** (all still open, formulas already extracted and
    ready to use next session): PLReportPage and ReportsPage (still empty
    shells — P&L/branch-P&L/lead-source/GST-summary and branch-revenue/
    monthly-volume/top-customers/service-mix formulas extracted from
    App.jsx lines 6350-7445, ready to port); GST invoicing (SAC 996719,
    interstate detection via a city→state lookup table defaulting unknown
    cities to Tamil Nadu, sequential `APC/2526/001`-style numbering stored
    in `settings` — note the reference app's counter is read-then-upsert,
    not atomic, worth using a proper sequence when porting); porter
    commission settlement UI (the 16%/19% formula is already used inline
    in the new AccountsPage, but the reference app also has a dedicated
    settlement preview on order entry that isn't ported yet); supervisor
    OTP job workflow (reference app generates a 4-digit OTP client-side,
    displays it to the supervisor to relay to the customer in person, and
    — a security gap worth NOT copying — verifies it only against in-memory
    React state rather than re-checking the DB; port the flow but fix that
    gap by verifying server-side against `orders.job_otp`); OrderDetailPage/
    LeadDetailPage/QuickEntryPage full rebuilds (see above).

- **13 Jul 2026, signup plan_id fix** (Cowork session — owner tested the
  live signup flow end-to-end and confirmed org + owner membership are
  created correctly; the one bug was `organizations.plan_id` left NULL).
  Root cause: `signup_page_widget.dart` fetched the default trial plan
  *after* inserting the org, and never wrote it back — the org row was
  created with no `plan_id`/`plan_status`/`trial_ends_at` at all. Fixed by
  reordering: the `subscription_plans` lookup (`is_default_trial = true`)
  now runs before the `organizations` insert, which is stamped with
  `plan_id` (from that plan), `plan_status: 'trial'`, and `trial_ends_at`
  (now + 14 days, UTC ISO string). Not build-verified (`flutter analyze`/
  `flutter run`) from this session. **Owner still needs to run the one-line
  SQL patch (given alongside this change) to fix the existing TEST 1 org
  created before this fix.**

- **13 Jul 2026** (Cowork session, no working Flutter/bash toolchain available
  — none of this was build-verified with `flutter analyze`/`flutter run`;
  treat as "should compile" until the owner confirms):
  - Wrote `supabase/views_dashboard_and_ops.sql` for known bug #1.
  - Fixed SalaryPage's missing staff query (known bug #2).
  - Set `GoogleFonts.config.allowRuntimeFetching = false` (known bug #3).
  - Wired SettingsPage's profile card to the `organizations` table (known bug #4).
  - Renamed Android package `com.mycompany.arunpkrs` → `in.nagarva.app`,
    label → "Nagarva" (known bug #6).
  - Discovered this doc didn't mention CLAUDE_ADDENDUM_vendor_flow.md's
    already-built SignupPage/OrgSetupPage/PlanPage/two-path login — updated
    the sections above accordingly.
  - **Not done yet, next up:** bundle real font files for #3; branding on
    Login/Home (#5); logout doesn't clear AppSession; org_id filtering on
    the rest of the ~52 queries (Phase 1); Phase 2-5 items untouched.

- **13 Jul 2026, later same-day pass** (Cowork session — resumed at user's
  request to "recheck the missing feature and complete this project"; again
  no working Flutter/bash toolchain, nothing here was build-verified with
  `flutter analyze`/`flutter run` — treat as "should compile" until the
  owner runs it):
  - **Logout fixed** (bug #4 follow-up): SettingsPage's Logout button now
    calls `SupaFlow.client.auth.signOut()`, `AppSession.instance.clear()`,
    and navigates to LoginPage, instead of just `context.pop()`.
  - **Branding fixed** (bug #5): LoginPage shows "Nagarva" instead of
    hardcoded "Arun Packers And Couriers" (correct here since no org is
    known pre-login). HomePage's stale doc comment corrected; it never had
    hardcoded branding text in its actual UI.
  - **Phase 1 multi-tenancy groundwork** (bug #7 — the big one this pass):
    - Added `org_id` getter/setter to all 16 remaining base table classes
      and to the 4 join views + 2 KPI views (previously only `staff`/
      `org_members` exposed it).
    - Wrote `supabase/phase1_add_org_id.sql`: adds the `org_id` column to
      all 16 tables, backfills to APC (`organizations.slug = 'apc'` —
      **verify this slug before running**), indexes it. **Owner needs to
      run this.**
    - Updated `supabase/views_dashboard_and_ops.sql`: all 6 views now pass
      `org_id` through; `dashboard_kpis_view` and `branch_kpis_view` are
      now grouped **per org** (one row per org_id) instead of one global
      row — re-run this after the migration above.
    - Wired `.eqOrNull('org_id', AppSession.instance.currentOrgId)` reads
      and `'org_id': AppSession.instance.currentOrgId` insert stamps into:
      HomePage (all 4 dashboard queries), OrdersPage (all 5 status tabs),
      LeadsPage (all 6 status tabs), NewOrderPage, NewLeadPage, ExpensePage,
      QuickExpensePage, FleetPage, OperationsPage, CalendarPage,
      QuotationPage.
    - **This is a breaking change until the SQL migration is run** — those
      pages will throw "column org_id does not exist" against the live DB
      until then. This mirrors how bug #1's views SQL already works (code
      shipped ahead of the owner running the migration) — same pattern,
      same caveat.
  - **Phase 2 shell pages — 3 of 6 built out with real data:**
    - **UsersPage**: was 100% hardcoded fake staff cards; now queries
      `StaffTable` (org-scoped), with working role filter chips and
      active/inactive sections. "Add New User" shows a clear "not built
      yet" message instead of silently doing nothing (a real add-staff form
      needs PIN/role/salary/PF fields — left as follow-up, not faked).
    - **MaterialsPage**: was 8 hardcoded fake SKUs; now queries
      `MaterialsTable` (org-scoped), computes low-stock count from real
      `quantity`/`min_stock`. Same honest "not built yet" message on
      Add/Restock rather than a fake action.
    - **QuotationPage**: the form itself was already fully built (all
      fields, controllers, validators) — only the save action was a stub
      (`print(...)`). Wired to a real `QuotationsTable().insert(...)` for
      the fields the form actually collects (customer/phone/addresses/
      amount/status). `items`/`charges`/GST fields are still null — that
      needs the GST invoice UI from Phase 3, not guessed at here.
    - **Not done**: AccountsPage (blocked — no `bank_accounts` table exists
      yet, this is a schema decision for the owner, see known bug list),
      PLReportPage, ReportsPage. Recommend tackling these with the React
      web app open side-by-side, since CLAUDE.md's own convention says that
      app is the source of truth for this business logic and it wasn't
      reachable from this session.
  - **Not done yet, next up:** run `phase1_add_org_id.sql` then the updated
    views SQL and confirm; add org_id filters to the remaining pages listed
    in bug #7; AccountsPage/PLReportPage/ReportsPage; bundle real fonts
    (#3); Phase 3-5 untouched.

- **13 Jul 2026, "Phase 0b" sync** (relayed into this Cowork session from a
  separate session that had live Supabase access — this session still has
  no working Flutter/bash toolchain, so nothing below was independently
  re-verified against the live DB; treating the report as accurate per the
  owner's coordination message):
  - Owner reports `phase1_add_org_id.sql` and the updated
    `views_dashboard_and_ops.sql` were both run successfully against
    `hqqcapifefsaqvotqvlt`. Verify: 3 `subscription_plans` rows seeded,
    1 `organizations` row (APC, fixed id, tenant #1), 18 `orders` + 8
    `staff` rows backfilled to APC's org_id — this was pre-existing data
    from the owner's own web-app testing, not synthetic seed data.
  - Updated known bugs #1 and #7 and the "Multi-tenancy status"/Roadmap
    Phase 0 sections above to reflect this.
  - **Outstanding per the owner's own follow-up list (not done by any
    agent yet):** (1) boot check — `flutter run -d chrome` → login →
    Dashboard, to confirm the views render clean and real KPI numbers show;
    (2) delete/retire the old superseded SQL files on the owner's machine
    (`nagarva_schema.sql`, `views_phase1.sql`, `views_phase2.sql` — not in
    this repo); (3) hand the vendor-signup build task to Claude Code:
    SignupPage → Supabase Auth signUp, insert `organizations` (slug from
    business name, `plan_id` = the `is_default_trial` plan) + `org_members`
    (role 'owner'), OrgSetupPage for business details, LoginPage's two paths
    (vendor via Auth / staff via phone+PIN unchanged), resolve
    `currentOrgId` from `org_members` after vendor login — verify
    `organizations.dart`/`org_members.dart` field names match the live
    schema first; any further schema change needs SQL handed back to the
    owner to run, not executed directly.
  - Next RLS work (Phase 0's last piece) should follow once the boot check
    and vendor-signup build are confirmed.

- **13 Jul 2026, vendor-flow schema reconciliation pass** (Cowork session —
  again no working Flutter/bash toolchain, nothing here build-verified with
  `flutter analyze`/`flutter run`; treat as "should compile" until the owner
  confirms). The owner handed back the actual field-by-field live schema for
  the three vendor-flow tables. **Finding: SignupPage, OrgSetupPage,
  PlanPage, and the two-path LoginPage were already fully built** (this
  matches what the addendum already said) — the real gap was that
  `subscription_plans.dart` had `name`/`display_name` backwards relative to
  the live schema (`code`/`name`), so every `plan.displayName` read silently
  returned null and the app's plan-name display always fell back to the
  hardcoded "Free Trial" string regardless of the org's actual plan. Fixed:
  - `subscription_plans.dart`: added `code`, `active`, `createdAt` getters;
    removed `displayName` (column doesn't exist) and `sortOrder` (not in
    schema, was unused). `name` now correctly means the human-readable label.
  - `signup_page_widget.dart` and `login_page_widget.dart`: both
    `plan.displayName` reads changed to `plan.name`.
  - `signup_page_widget.dart`: removed `'email'` and `'owner_id'` from the
    `organizations` insert payload — not in the owner-confirmed live schema
    (`organizations(id, name, slug, gstin, phone, plan_id, plan_status,
    trial_ends_at, active, created_at)`); ownership is already tracked via
    `org_members.role = 'owner'`, which was unaffected.
  - `organizations.dart`: added `planStatus` getter/setter. Left `email`,
    `logoUrl`, `ownerId` in place as read-only/best-effort getters (an absent
    column just returns null on read, and SettingsPage still reads
    `org.email` for its profile card) — but they must never appear in an
    insert/update payload again.
  - `org_members.dart`: added `createdAt` getter/setter to match schema.
    Left `invitedBy`/`joinedAt` in place, same read-only rationale.
  - Not touched: `plan_status` is exposed but nothing sets it yet (no
    confirmed value convention — 'trialing'/'active'/etc. — from the web
    app); RLS policies (still Phase 0's last piece); Razorpay upgrade path
    (Phase 3, deliberately stubbed on PlanPage already).
  - As always: no SQL was run or written this pass — this was pure Dart
    reconciliation against the schema the owner already confirmed live.

- **13 Jul 2026, compile-fix pass** (Cowork session — owner ran `flutter run`
  for the first time and it failed; this is the first real build signal on
  the vendor-flow pages). Root cause: `signup_page_widget.dart` and
  `org_setup_page_widget.dart` referenced `OrgSetupPageWidget.routePath`,
  `LoginPageWidget.routePath`, and `HomePageWidget.routePath` for
  navigation but never imported `/index.dart` (or the individual page
  files) — unlike `login_page_widget.dart` and `home_page_widget.dart`,
  which already followed the FlutterFlow convention of importing
  `/index.dart` for cross-page navigation. `lib/index.dart` itself and the
  `GoRoute`/`FFRoute` registrations in `lib/flutter_flow/nav/nav.dart` were
  already correct (Signup/OrgSetup/Plan all exported and routed) — this was
  purely a missing-import bug in the two newer widget files, not a routing
  or export gap.
  - Fixed: added `import '/index.dart';` to `signup_page_widget.dart` and
    `org_setup_page_widget.dart`.
  - Verified (statically, still no local Flutter toolchain): grepped every
    `*_widget.dart` file in `lib/` for `.routePath`/`.routeName` usage and
    cross-checked each against its own imports. All 12 files that reference
    another page's route now import `/index.dart` — no other files have
    this gap. `plan_page_widget.dart` doesn't navigate to another named page
    (its AppBar back button just pops), so it needs no such import.
  - Not touched: no existing page's route was changed, per owner's
    instruction.
