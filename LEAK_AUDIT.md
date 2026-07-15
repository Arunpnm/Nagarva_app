# Tenant-Leak Audit — Static Analysis

## Stage 1 fix status — 14 Jul 2026

**All 10 numbered leaks and every write-gap row below are fixed in app
code**, via `lib/backend/supabase/org_scope.dart` (the `OrgScope` helper —
see CLAUDE.md's "Org scoping convention"). Full detail in CLAUDE.md's 14 Jul
2026 Stage 1 changelog entry; short version per item:

| # | Status | Fix |
|---|---|---|
| 1 (payments_page) | **Fixed** | Kept the page (it's a live bottom-nav tab, not dead code — checked `main.dart` before deciding) and added the org_id filter. |
| 2 (salary_page views) | **Fixed** | Both view queries now use `OrgScope.read(q)`. |
| 3 (new_order_page edit load) | **Fixed** | Read + its edit-mode save (write gap) both scoped. |
| 4 (new_lead_page edit load) | **Fixed** | Same as #3. |
| 5 (order_detail_page invoice check) | **Fixed** | Read + the invoice_no update (write gap) both scoped. |
| 6 (order_detail_page invoice counter) | **Fixed** | Read/insert/update all scoped; key renamed `inv_seq_<SLUG>_<FY>` → `inv_seq_<FY>` (migration: `supabase/phase1_rename_settings_keys.sql`, not yet run). |
| 7 (supervisor_job_page job load) | **Fixed** | Scoped, plus all 5 `OrdersTable().update()` write gaps in that file. |
| 8 (supervisor_job_page OTP re-fetch) | **Fixed** | Scoped. |
| 9 (staff login) | **Deliberately not touched** | Owner is replacing this path with a Supabase Edge Function next; explicitly out of scope for this pass. |
| 10 (accounts_page settings) | **Fixed** | Read/insert/update all scoped; key renamed `accounts_opening_balance:<orgId>` → `accounts_opening_balance` (same migration file). |

All other write-gap rows named in the original audit (record_payment_page
save, operations_page approve/reopen, lead_detail_page convert-to-order) are
also fixed — every `matchingRows` in the app now chains `OrgScope.write(q)`
before the row filter, and every insert spreads `...OrgScope.stamp()`.

**Fixed 14 Jul 2026 (follow-up)**: `record_payment_page_widget.dart`'s save
button used to match with `.eqOrNull('id', _model.selectedPayOrderId)` —
`selectedPayOrderId` could reach null (the visibility guard above it only
checked `== ''`, not null), and `eqOrNull` silently drops the filter on
null, so a null id would have updated every order in the org. Now guards
for null/empty before the call (shows an error, returns early) and uses a
plain `.eq('id', orderId)`. Also grepped the whole app for every
`matchingRows:` call site — this was the only write using `eqOrNull` as its
row filter; every other update/delete already used a plain `.eq(...)`. Rule
added to CLAUDE.md's "Org scoping convention": never use `eqOrNull` for the
row-identifying filter in a write.

**Still open, unchanged by this pass**: no RLS policies exist yet. Everything
above is a client-side guard rail (`OrgScope` throws if org isn't resolved,
and is used everywhere), not a database-enforced one — the anon key can
still bypass all of it via a raw request. That remains the real fix per
CLAUDE.md's Roadmap.

---

Generated 14 Jul 2026. Static read-through of every Supabase query in `lib/`
(no `flutter run`/`flutter analyze` — per request, this is a map, not a fix).
Method: grepped all `*Table().queryRows/insert/update/delete` call sites
across all 28 pages, then read each call site's `queryFn`/`data`/`matchingRows`
to check for `org_id`/`AppSession.instance.currentOrgId`.

## Summary: flagged leaks

| # | Severity | File : line | Table | Issue |
|---|---|---|---|---|
| 1 | **High** | `payments_page/payments_page_widget.dart:36` | `orders` | Read filters only on `payment_status='pending'` — **no `org_id` filter at all**. Every org's pending-payment orders are returned. This page is routed (`nav.dart`, `index.dart`) and linked from `home_page_widget.dart`, but is **not mentioned in CLAUDE.md's page inventory** — looks like a leftover/duplicate of RecordPaymentPage that never got the Phase 1 org_id pass. |
| 2 | **High** | `salary_page/salary_page_widget.dart:44,50` | `attendance_view`, `advances_view` | Both queried with `queryFn: (q) => q` — no filter of any kind. Returns every org's attendance and advance rows. Only the `staff` query on the same page was scoped; the two views were missed. |
| 3 | **Medium** | `new_order_page/new_order_page_widget.dart:90-91` | `orders` | Edit-mode load (`_loadExistingOrder`) matches only `id = widget.orderId`, no `org_id` check. If `orderId` from another org ever reaches this page (bad deep link, tampered query param), the form silently loads and displays that order's data. |
| 4 | **Medium** | `new_lead_page/new_lead_page_widget.dart:75-76` | `leads` | Same pattern as #3 (`_loadExistingLead`), matches only `id`. |
| 5 | **Medium** | `order_detail_page/order_detail_page_widget.dart:163-164` | `orders` | `_generateInvoice` re-checks for an existing `invoice_no` via `q.eq('id', widget.orderId!)` only — no `org_id`. |
| 6 | **Medium** | `order_detail_page/order_detail_page_widget.dart:130-132` | `settings` | Invoice sequence counter is read via `q.eq('key', key)` only. The key itself embeds the org slug (`inv_seq_<SLUG>_<FY>`), so it's namespaced by *string content*, not by an `org_id` column filter — two orgs with colliding slug prefixes would share a counter. |
| 7 | **Medium** | `supervisor_job_page/supervisor_job_page_widget.dart:89` | `orders` | Job load matches only `id = widget.orderId`, no `org_id`. |
| 8 | **Medium** | `supervisor_job_page/supervisor_job_page_widget.dart:248-249` | `orders` | OTP re-verification re-fetch also matches only `id`, no `org_id`. |
| 9 | **Low (by design, still worth flagging)** | `login_page/login_page_widget.dart:144,148` | `staff` | Staff-login path matches phone/name across **all orgs** (org isn't known pre-auth) — this is the documented "insecure by design" flow (CLAUDE.md "Current login flow"), but it is a genuine cross-tenant query: a phone/PIN collision between two orgs' staff could authenticate into the wrong org. Flagging per the audit ask even though CLAUDE.md already tracks the underlying fix (Edge Function + RLS). |
| 10 | **Low** | `accounts_page/accounts_page_widget.dart:81-82,246` | `settings` | Opening-balance key/value queried and updated via `q.eq('key', _openingBalanceKey)` only. The key embeds `currentOrgId` as a string (`accounts_opening_balance:<orgId>`), so it's effectively isolated in practice, but — like #6 — it's string-namespacing, not an `org_id` column filter. |

**Pattern seen across ~11 write sites** (not counted as separate leaks above, but worth naming as a class): updates that mutate an already-org-scoped row use `matchingRows: (q) => q.eq('id', ...)` / `.eqOrNull('id', ...)` with **no accompanying `org_id` check** — e.g. `RecordPaymentPage` save, `OperationsPage` `_approveEntry`/`_reopenEntry`, `SupervisorJobPage`'s five `OrdersTable().update(...)` calls, `LeadDetailPage`'s convert-to-order status flip, `NewOrderPage`/`NewLeadPage` edit-mode saves, `OrgSetupPage`'s settings counter update. In most of these the `id` originates from a row the user already fetched through an org-scoped read, so the practical exposure is lower than #1-#2, but none of them would stop a crafted request from mutating another org's row if the id were known/guessed. Listed per-row in the full table below (column "Write scoped?").

## Full per-page query map

### HomePage (`home_page/home_page_widget.dart`)
| Table/View | Op | Read org-scoped? | Insert stamps org_id? |
|---|---|---|---|
| dashboard_kpis_view | select | Yes (`eqOrNull org_id`) | – |
| orders (status=confirmed) | select | Yes | – |
| leads (status=new) | select | Yes | – |
| branch_kpis_view | select | Yes | – |

### OrdersPage (`orders_page/orders_page_widget.dart`)
| Table | Op | Read org-scoped? |
|---|---|---|
| orders — all/pending/confirmed/transit/delivered/cancelled (6 tabs) | select | Yes, all 6 |

### LeadsPage (`leads_page/leads_page_widget.dart`)
| Table | Op | Read org-scoped? |
|---|---|---|
| leads — all/new/contacted/qualified/won/lost (6 tabs) | select | Yes, all 6 |

### NewOrderPage (`new_order_page/new_order_page_widget.dart`)
| Table | Op | Scoped? | Notes |
|---|---|---|---|
| orders | select (`_loadExistingOrder`, edit-mode) | **No — leak #3** | matches `id` only |
| orders | insert | N/A read | **stamps org_id** |
| orders | update (edit-mode save) | **No — write gap** | matches `id` only |

### NewLeadPage (`new_lead_page/new_lead_page_widget.dart`)
| Table | Op | Scoped? | Notes |
|---|---|---|---|
| leads | select (`_loadExistingLead`, edit-mode) | **No — leak #4** | matches `id` only |
| leads | insert | N/A read | **stamps org_id** |
| leads | update (edit-mode save) | **No — write gap** | matches `id` only |

### OrderDetailPage (`order_detail_page/order_detail_page_widget.dart`)
| Table | Op | Scoped? | Notes |
|---|---|---|---|
| settings (invoice seq counter) | select | **No — leak #6** | matches `key` only, org namespaced via string content |
| settings | insert (counter init) | N/A read | **stamps org_id** |
| settings | update (counter incr) | **No — write gap** | matches `key` only |
| orders (existing invoice_no check) | select | **No — leak #5** | matches `id` only |
| orders | update (stamp invoice_no) | **No — write gap** | matches `id` only |

### LeadDetailPage (`lead_detail_page/lead_detail_page_widget.dart`)
| Table | Op | Scoped? | Notes |
|---|---|---|---|
| orders (convert-to-order) | insert | N/A read | **stamps org_id** |
| leads (flip status→confirmed) | update | **No — write gap** | matches `id` only |

### RecordPaymentPage (`record_payment_page/record_payment_page_widget.dart`)
| Table | Op | Scoped? |
|---|---|---|
| orders (pending payments) | select | Yes (`eqOrNull org_id`) |
| orders (save payment) | update | **No — write gap**, matches `id` only |

### PaymentsPage (`payments_page/payments_page_widget.dart`) — *not in CLAUDE.md's page list, but routed/reachable*
| Table | Op | Scoped? |
|---|---|---|
| orders (pending payments) | select | **No — leak #1, no org_id filter whatsoever** |

### QuickExpensePage (`quick_expense_page/quick_expense_page_widget.dart`)
| Table | Op | Scoped? |
|---|---|---|
| expenses | insert | **stamps org_id** |

### ExpensePage (`expense_page/expense_page_widget.dart`)
| Table | Op | Scoped? |
|---|---|---|
| expenses | select | Yes |

### SalaryPage (`salary_page/salary_page_widget.dart`)
| Table | Op | Scoped? |
|---|---|---|
| staff | select | Yes |
| attendance_view | select | **No — leak #2** |
| advances_view | select | **No — leak #2** |

### FleetPage (`fleet_page/fleet_page_widget.dart`)
| Table | Op | Scoped? |
|---|---|---|
| vehicles | select | Yes |

### OperationsPage (`operations_page/operations_page_widget.dart`)
| Table | Op | Scoped? |
|---|---|---|
| trips_view | select | Yes |
| orders (pending approvals) | select | Yes |
| orders (`_approveEntry`) | update | **No — write gap**, matches `id` only |
| order_tracking (`_approveEntry`) | insert | **stamps org_id** |
| orders (`_reopenEntry`) | update | **No — write gap**, matches `id` only |
| order_tracking (`_reopenEntry`) | insert | **stamps org_id** |

### CalendarPage (`calendar_page/calendar_page_widget.dart`)
| Table | Op | Scoped? |
|---|---|---|
| reminders_view | select | Yes |

### UsersPage (`users_page/users_page_widget.dart`)
| Table | Op | Scoped? |
|---|---|---|
| staff | select | Yes |

### MaterialsPage (`materials_page/materials_page_widget.dart`)
| Table | Op | Scoped? |
|---|---|---|
| materials | select | Yes |

### QuotationPage (`quotation_page/quotation_page_widget.dart`)
| Table | Op | Scoped? |
|---|---|---|
| quotations | insert | **stamps org_id** (no read query on this page) |

### AccountsPage (`accounts_page/accounts_page_widget.dart`)
| Table | Op | Scoped? |
|---|---|---|
| orders | select | Yes |
| expenses | select | Yes |
| order_staff | select | Yes |
| settings (opening balance) | select | **No — leak #10 (soft)**, matches `key` only (org id embedded in key string) |
| settings (opening balance) | insert | **stamps org_id** |
| settings (opening balance) | update | **No — write gap**, matches `key` only |

### PLReportPage (`p_l_report_page/p_l_report_page_widget.dart`)
| Table | Op | Scoped? |
|---|---|---|
| orders, expenses, order_staff, leads | select (4 queries) | Yes, all 4 |

### ReportsPage (`reports_page/reports_page_widget.dart`)
| Table | Op | Scoped? |
|---|---|---|
| orders, expenses, order_staff | select (3 queries) | Yes, all 3 |

### SupervisorJobPage (`supervisor_job_page/supervisor_job_page_widget.dart`)
| Table | Op | Scoped? | Notes |
|---|---|---|---|
| orders (load job) | select | **No — leak #7** | matches `id` only |
| staff | select | Yes | |
| expenses (job expenses) | select | Yes | |
| orders (`_changeStatus`) | update | **No — write gap** | matches `id` only |
| order_tracking (`_changeStatus`) | insert | **stamps org_id** | |
| orders (`_startJob`) | update | **No — write gap** | matches `id` only |
| orders (`_startShifting`) | update | **No — write gap** | matches `id` only |
| expenses (`_addExpense`) | insert | **stamps org_id** | |
| orders (`_generateOtp`) | update | **No — write gap** | matches `id` only |
| orders (`_verifyAndComplete` re-fetch OTP) | select | **No — leak #8** | matches `id` only |
| orders (`_verifyAndComplete` finalize) | update | **No — write gap** | matches `id` only |

### SettingsPage (`settings_page/settings_page_widget.dart`)
| Table | Op | Scoped? |
|---|---|---|
| organizations (own org profile) | select | Yes — matched to `AppSession.currentOrgId`, correct usage |

### LoginPage (`login_page/login_page_widget.dart`)
| Table | Op | Scoped? | Notes |
|---|---|---|---|
| org_members (resolve org from auth user) | select | N/A | pre-org-resolution step, correct by construction |
| organizations (vendor path) | select | N/A | matched to resolved `orgId` |
| subscription_plans (vendor path) | select | N/A | global table, plan lookup by id/default flag |
| staff (phone match) | select | **No — leak #9 (by design, tracked in CLAUDE.md)** | queries across all orgs |
| staff (name match, fallback) | select | **No — leak #9** | same |
| organizations (staff path) | select | N/A | matched to resolved `orgId` from staff row |
| subscription_plans (staff path) | select | N/A | matched to resolved plan id |

### SignupPage (`signup_page/signup_page_widget.dart`)
| Table | Op | Scoped? | Notes |
|---|---|---|---|
| subscription_plans | select | N/A | global table |
| organizations | insert | N/A | creates the new org itself — no org_id to stamp |
| org_members | insert | **stamps org_id** | of the newly created org |

### OrgSetupPage (`org_setup_page/org_setup_page_widget.dart`)
| Table | Op | Scoped? |
|---|---|---|
| organizations (own org) | update | Yes — matched to `orgId` from AppSession |
| settings (business details, multiple rows) | insert | **stamps org_id** |

### PlanPage, QuickEntryPage
No direct Supabase queries — PlanPage reads only from `AppSession`; QuickEntryPage is a static 4-button launcher. Nothing to audit.

## Notes on method / limitations
- Static only — no `flutter run`/`flutter analyze`, per request. Line numbers reflect the files as read during this pass; re-verify if the files have changed since.
- "Write gap" rows are not necessarily exploitable through the app's own UI (the `id` usually comes from a row the user already fetched via an org-scoped read), but none of them would block a crafted request that supplies a foreign `id` — worth deciding whether to harden with an explicit `org_id` match once RLS (CLAUDE.md's tracked next step) isn't yet in place to catch this at the DB layer.
- Nothing was fixed in this pass — this is the map only, as requested.
