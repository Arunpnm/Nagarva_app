repo: Arunpnm/Nagarva_app
branch: main
path: lib

## Last sync
date: 2026-10-28T12:00:00Z

### Updated in this project
- Customer app + website (new, no repo source yet): booking flow, Review & pay ticket, live tracking, claims, reschedule/cancel
- Customer app + website in 6 languages (English, Hindi, Tamil, Telugu, Kannada, Malayalam)
- Creative pass: blue hero Home and Track, package cards, add-ons itemised on Review
- Marketplace: vendor Nagarva jobs (availability, extra cities, return trips); admin Marketplace incl. Return trips

## Sync history
- 2026-10-19T03:10:00Z: Marketplace vendor + admin, 4 plans, order documents, order journey, permissions, biometric login, business details
- 2026-10-19T01:10:00Z: Import & export on 14 modules
- 2026-10-19T00:50:00Z: Admin Plans & Vendor detail rebuilt from lib/super_admin_page
- 2026-10-18T16:05:00Z: Batch 4 (Assets & Partners)
- 2026-10-18T15:45:00Z: Batch 3 (Money): Expenses, P&L report, Reports
- 2026-10-18T15:40:00Z: Batch 2 (Operations) and back buttons on every non-tab screen
- 2026-10-18T15:15:03Z: Batch 1 (Sales) finished in 6 languages; customer detail; Help & support
- 2026-10-18T13:45:07Z: No rebuilds; verified nav, surveys removal, lead pipeline strip
- 2026-10-17T09:39:50Z: Crew & Accounts wireframes; quote design settings and Generate quote preview
- 2026-10-16T17:54:56Z: Batch 1 redesign (Login, Dashboard, Leads, Orders), supervisor/field homes, nav

## Screen map
| Project screen | Repo files |
|---|---|
| Login (email + PIN) | lib/login_page/login_page_widget.dart, lib/login_page/pin_login_page_widget.dart |
| Dashboard | lib/home_page/home_page_widget.dart, lib/components/dashboard_kpi_grid.dart |
| Leads | lib/leads_page/leads_page_widget.dart, lib/backend/lead_status.dart, lib/components/lead_status_strip.dart, lib/backend/lead_stage_evidence.dart, docs/COMPETITOR_UX_SPEC.md |
| Orders | lib/orders_page/orders_page_widget.dart, lib/backend/order_stages.dart |
| Bottom nav / More sheet | lib/components/mobile_bottom_nav.dart, lib/components/app_nav_drawer.dart, lib/nav_items.dart |
| Supervisor / field homes | lib/nav_items.dart, lib/supervisor_jobs_page/supervisor_jobs_page_widget.dart |
| Theme | lib/flutter_flow/flutter_flow_theme.dart |
| Crew & Accounts wireframes | docs/nagarva_staff_pay_and_expense_brief.md, docs/NG-BRIEF-supervisor-field-operations.md, lib/backend/staff_pay_types.dart, lib/backend/material_usage.dart, lib/permissions.dart |
| Customers (+ detail) | lib/customers_page/customers_page_widget.dart, lib/customers_page/customer_detail_page_widget.dart |
| Inbox | lib/wa_inbox_page/wa_inbox_page_widget.dart |
| Reviews | lib/reviews_page/reviews_page_widget.dart |
| Survey & Quote | lib/survey_quote_hub_page/survey_quote_hub_page_widget.dart |
| Calendar | lib/calendar_page/calendar_page_widget.dart |
| Trips (+ detail) | lib/trips_page/trips_page_widget.dart, lib/trips_page/trip_detail_page_widget.dart |
| Tasks & activities | lib/tasks_page/tasks_page_widget.dart |
| LR Register | lib/lr_register_page/lr_register_page_widget.dart |
| Ops log | lib/operations_standalone_page/operations_standalone_page_widget.dart |
| Expenses | lib/expense_page/expense_page_widget.dart, lib/quick_expense_page/quick_expense_page_widget.dart |
| P&L report | lib/p_l_report_page/p_l_report_page_widget.dart |
| Reports | lib/reports_page/reports_page_widget.dart |
| Fleet | lib/fleet_page/fleet_page_widget.dart, lib/fleet_page/vehicle_detail_sheet.dart |
| Materials | lib/materials_page/materials_page_widget.dart, lib/materials_page/material_detail_sheet.dart |
| Warehouses | lib/warehouses_page/warehouses_page_widget.dart |
| Vendors (+ bills, payments) | lib/vendors_page/vendors_page_widget.dart, lib/vendors_page/vendor_detail_page_widget.dart |
| Insurance & claims | lib/insurance_claims_page/insurance_claims_page_widget.dart |
| Admin · Vendors + detail | lib/super_admin_page/super_admin_page_widget.dart, lib/super_admin_page/tenant_detail_page.dart, supabase/functions/admin-update-org, admin-reset-owner-password, admin-delete-org |
| Admin · Plans & pricing | lib/super_admin_page/plans_tab.dart, lib/super_admin_page/plan_edit_sheet.dart |
| Vendor · Nagarva jobs (jobs, wallet, tier) | Design only (no repo source) |
| Admin · Marketplace (live, alerts, disputes, vendors, money, city rules, return trips) | Design only (no repo source) |
| Customer app (Nagarva Customer.dc.html) | Design only (no repo source) |
| Customer website (Nagarva Website.dc.html) | Design only (no repo source) |
