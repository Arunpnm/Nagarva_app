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
| Business accounts | Missing | |
| Customer portal & GPS | Missing | `/track` page exists but is not hosted; no GPS |
| Coupons & referrals | Missing | |
| Lead rules & lost report | Missing | lost reasons are recorded (`quote_outcomes`), no report screen |

## Operations
| Design module | App | Notes |
|---|---|---|
| Orders | Built | |
| Operations | Built | |
| Daily summary | Missing | |
| Calendar | Built | |
| Trips | Built | |
| Tasks | Built | |
| LR Register | Built | |
| Ops Log | Built | OperationsStandalonePage |
| Part-load & routes | Missing | |
| Damage claims | Partial | InsuranceClaimsPage |

## Money
| Design module | App | Notes |
|---|---|---|
| Approvals | Partial | Awaiting-approval queue lives on Operations |
| Payments | Built | |
| Rate Cards | Built | |
| Expenses | Built | |
| Accounts | Built | |
| P & L | Built | |
| Reports | Built | |
| GST, TDS & exports | Missing | |
| Credit notes & refunds | Missing | |
| Bank & UPI match | Missing | |
| Cash book | Missing | |

## People
| Design module | App | Notes |
|---|---|---|
| Staff | Built | UsersPage |
| Salary | Built | |
| Leave | Missing | |
| Payslips, PF & ESI | Missing | |
| Overtime & incentives | Missing | |
| Staff documents | Missing | |
| Labour contractors | Missing | |

## Assets
| Design module | App | Notes |
|---|---|---|
| Fleet | Built | |
| Materials | Built | |
| Warehouses | Built | |
| Storage billing | Partial | storage card inside Order Details |

## Transport
| Design module | App | Notes |
|---|---|---|
| Driver app | Missing | |
| Fuel & FASTag | Missing | `fuel_fills` table exists, no screen |
| Diesel advance | Missing | |
| Docs, tyres & battery | Missing | |
| E-way bills | Missing | |
| Hired trucks | Missing | |

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
| WhatsApp | Missing | no send path exists yet (Phase 4) |
| Quote design | Missing | |
| Services & sources | Missing | `lead_sources` table exists, no editor |
| Business details | Built | inside Settings |
| Login & security | Partial | App PIN card in Settings |
| Permissions & alerts | Missing | |

## Setup
| Design module | App | Notes |
|---|---|---|
| Branches | Built | |
| Auto WhatsApp | Missing | no send path exists yet |
| Approvals (rules) | Missing | |
| Backup & offline | Missing | |
| Dashboard widgets | Missing | |
| Activity log | Missing | `audit_log` is written, no viewer |
| Help & support | Built | HelpAboutPage |

## Totals
Built 33 · Partial 5 · Missing 35 (of 73).

## How visual parity will be checked
Design screens are rendered from the handoff in Chromium (fonts and icons
served locally). App screens are rendered from the Flutter web build with
Supabase calls answered by fixture data shaped like the design's sample data,
so each pair can be compared side by side.
