# Design parity — app vs the Claude Design handoff (21 Oct 2026)

Source of truth: `Nagarva App.dc.html` (Mobile app redesign project handoff).
The design's More menu lists 73 modules in 9 groups. This table maps each to
the Flutter app as of `main` @ 48c3d87.

Legend: **Built** = a screen exists (visual match still to be checked) ·
**Partial** = the job is done inside another screen · **Missing** = no screen.

## Sales
| Design module | App | Notes |
|---|---|---|
| Dashboard | Built | HomePage — user reports it looks different from the design |
| Leads / CRM | Built | LeadsPage |
| Inbox | Built | WaInboxPage |
| Survey & Quote | Built | SurveyQuoteHubPage |
| Customers | Built | CustomersPage |
| Reviews | Built | ReviewsPage |
| Business accounts | Built | BusinessAccountsPage — GSTIN / company customers + contracts |
| Customer portal & GPS | Missing | `/track` is live (`kTrackLinkHosted`); there is no GPS source |
| Coupons & referrals | Built | ReferralsPage — referrals (add) + discount rules (read-only) |
| Lead rules & lost report | Built | LostReportPage — `quote_outcomes` + `lead_source_performance_view` |

## Operations
| Design module | App | Notes |
|---|---|---|
| Orders | Built | |
| Operations | Built | |
| Daily summary | Built | DailySummaryPage — today's moves, money in/out, new leads |
| Calendar | Built | |
| Trips | Built | |
| Tasks | Built | |
| LR Register | Built | |
| Ops Log | Built | OperationsStandalonePage |
| Part-load & routes | Built | PartLoadPage — trips with more than one order (`trip_orders`) |
| Damage claims | Partial | InsuranceClaimsPage |

## Money
| Design module | App | Notes |
|---|---|---|
| Approvals | Built | ApprovalsPage — discount approvals + jobs to close (queue; decisions stay where they are) |
| Payments | Built | |
| Rate Cards | Built | |
| Expenses | Built | |
| Accounts | Built | |
| P & L | Built | |
| Reports | Built | |
| GST, TDS & exports | Built | GstPage — GSTR-1 B2B/B2C views + TDS; filing/export not built |
| Credit notes & refunds | Built | CreditNotesPage — numbered from the `credit_note` series |
| Bank & UPI match | Built (read-only) | BankMatchPage — statement import not built |
| Cash book | Built | CashBookPage — cash out live since 21 Oct (`kExpensePaymentModeLive`) |

## People
| Design module | App | Notes |
|---|---|---|
| Staff | Built | UsersPage |
| Salary | Built | |
| Leave | Built | LeavePage — migration live 21 Oct, `kStaffLeaveIncentivesLive` true |
| Payslips, PF & ESI | Built (read-only) | PayslipsPage — generating a payroll run is not built |
| Overtime & incentives | Built | IncentivesPage — same migration and flag as Leave |
| Staff documents | Built (read-only) | StaffDocumentsPage — `documents` where entity_type = staff |
| Labour contractors | Built | LabourContractorsPage — Vendors of type labour |

## Assets
| Design module | App | Notes |
|---|---|---|
| Fleet | Built | |
| Materials | Built | |
| Warehouses | Built | |
| Storage billing | Built | StorageBillingPage — all `storage_jobs`; billing stays on the order |

## Transport
| Design module | App | Notes |
|---|---|---|
| Driver app | Missing | |
| Fuel & FASTag | Built | FuelPage — fuel log with add; no FASTag/toll table exists |
| Diesel advance | Built | DieselAdvancePage — `job_expense_floats`; add is owner-only like its RLS |
| Docs, tyres & battery | Built | VehicleDocsPage — `fleet_compliance_view` + service log (add) |
| E-way bills | Built (read-only) | EwayBillsPage — generating needs the NIC API |
| Hired trucks | Built | HiredTrucksPage — hired trips + rented vehicles |

## Partners
| Design module | App | Notes |
|---|---|---|
| Vendors | Built | |
| Insurance | Built | |

## Account
| Design module | App | Notes |
|---|---|---|
| Modules | Missing | |
| Plan & billing | Built | PlanPage; payment is on hold (Item 31) |
| CFT & packages | Built | SurveyPricingPage |
| WhatsApp | Built, awaiting migration + deploy | WhatsAppPage — vendor's own Meta Cloud API number; `20261021_whatsapp_cloud_api.sql`, functions `whatsapp` + `whatsapp-webhook`, flag `kWhatsAppCloudLive` |
| Quote design | Missing | |
| Services & sources | Built | LeadSourcesPage — add sources and their commission |
| Business details | Built | inside Settings |
| Login & security | Partial | App PIN card in Settings |
| Permissions & alerts | Missing | |

## Setup
| Design module | App | Notes |
|---|---|---|
| Branches | Built | |
| Auto WhatsApp | Built, awaiting migration + deploy | AutoWhatsAppPage — five automatic messages, same flag |
| Approvals (rules) | Missing | |
| Backup & offline | Built (read-only) | BackupPage — starting a backup needs a server job |
| Dashboard widgets | Missing | |
| Activity log | Built | ActivityLogPage — `audit_log`, read-only |
| Help & support | Built | HelpAboutPage |

## Totals
21 Oct 2026 (later): 24 more modules built on the shared RecordModulePage
(`lib/components/record_module_page.dart`, modules in `lib/modules/`).
Two of them wait on a migration. Almost every backing table holds 0 rows,
so these screens are BUILT but not yet USED — none has met real data.

### Still not built, and why
| Module | Reason |
|---|---|
| Customer portal & GPS | `/track` is live; there is no GPS source |
| Driver app | needs its own role and session type |
| Modules, Dashboard widgets | a switch nothing reads would be a decoy; needs a policy reader first |
| Quote design | quote PDF theming is its own piece of work |
| Permissions & alerts | `notification_prefs` exists but nothing reads it |
| Approvals (rules) | `discount_policies` exists but nothing enforces it |
| Login & security | App PIN lives in Settings; nothing else to show yet |

## Earlier totals
Built 33 · Partial 5 · Missing 35 (of 73).

## How visual parity will be checked
Design screens are rendered from the handoff in Chromium (fonts and icons
served locally). App screens are rendered from the Flutter web build with
Supabase calls answered by fixture data shaped like the design's sample data,
so each pair can be compared side by side.

## 22 Oct 2026 — screens that were still on the old UI
Why they looked old: earlier redesign passes swapped the top bar and
recoloured, but left each screen's body (FlutterFlow text styles, cards with
shadows, FFButtonWidget, per-call button overrides) untouched.

Rebuilt to the handoff layout: all supervisor screens (My Jobs, field job,
My Team, Earnings, Attendance, Job Entry), Crew sheet, Survey quote builder,
every Order Details section, Customer/Vendor/Trip/Rate-card detail,
pre-login screens (login, org binding, set password, signup — now follow the
light theme by default), Quick entry. Every other screen and sheet had its
old text styles, colours, shadows and button overrides moved onto the design
palette (`NgPalette`, `NgFonts`, `ng_widgets.dart`). No `FFButtonWidget`
remains outside `lib/flutter_flow/`.

Not checked on a device; behaviour and queries were not changed.
