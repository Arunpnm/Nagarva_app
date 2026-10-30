# Handoff: Nagarva app and admin redesign

## Overview
Nagarva is business software for Indian packers & movers and transport operators. This package covers:

- **Nagarva App**: the mobile app used by owners, managers, supervisors, field staff and drivers. It runs the business from first enquiry to a closed, paid order, plus fleet, money, people and setup.
- **Nagarva Admin**: the Nagarva-side super admin panel. It covers vendors, plans and pricing, approvals, tickets, payments, coupons, broadcasts and the marketplace.
- **Nagarva Customer** (mobile app) and **Nagarva Website**: where the public books a move directly with Nagarva. Nagarva sets the price and broadcasts the job to vendors (the marketplace).

Target codebase: **Arunpnm/Nagarva_app** (Flutter / FlutterFlow, Supabase), branch `main`, folder `lib/`. `github.md` maps redesigned screens to the existing repo files they were built from.

## About the design files
The files in `design/` are **design references built in HTML**. They are working prototypes that show the intended look, copy and behaviour. They are not production code. Rebuild them in the existing Flutter app using its patterns (FlutterFlow theme, widgets, Supabase backend). Do not ship the HTML.

To view them, open `design/Nagarva App.dc.html`, `Nagarva Admin.dc.html`, `Nagarva Customer.dc.html` or `Nagarva Website.dc.html` in Chrome. Keep every file in `design/` in the same folder, because `support.js` and the `i18n-*.js` files are loaded relatively.

All data in the prototypes is demo data held in memory. Every list, number and ID is a stand-in for a Supabase table.

## Fidelity
**High fidelity.** The colours, type, spacing, radii, copy and interactions are final. Match them using Flutter widgets. All styles are inline in the HTML, so you can read exact values from the element you are looking at.

---

## Design tokens

### Themes (App)
Three themes. The key names are the ones used in the code.

| token | midnight (default) | dark | light |
|---|---|---|---|
| bg | #0A0C10 | #0C1A2B | #F4F3F0 |
| s1 (card) | #12151B | #12243A | #FFFFFF |
| s2 (raised button) | #1A1E26 | #1A2E47 | #F2F1ED |
| s3 (icon tile, chip) | #1F232B | #1F3550 | #ECEAE5 |
| sheet | #14171D | #13263D | #FFFFFF |
| inset (field / inner panel) | #0F1217 | #0E1E31 | #F4F3F0 |
| nav | #0D1015 | #0E1F33 | #FFFFFF |
| text | #ECEEF2 | #EEF2F7 | #16181D |
| soft | #C3C8D1 | #C5CFDC | #3D424B |
| mute | #8A93A3 | #93A1B6 | #5E6572 |
| faint | #5B6372 | #66768F | #7D838E |

- **Hairlines** `w04…w25` are `rgba(rgb, alpha × k)`, where k = 1 (midnight), 1.2 (dark) or 1.4 (light), capped at 0.5. Most borders use `w06`, fields use `w1`, and toggle-off uses `w15`.
- **Accent (orange):**
  - dark themes: `oklch(0.74 0.16 55)`, used for both text and buttons
  - light theme: text `oklch(0.56 0.17 48)`, button `oklch(0.70 0.17 50)`
  - text on an accent button is always `#0A0C10`
- **Status colours** use the formula `col(h)`:
  - dark: `oklch(0.76 0.14 h)` (amber `oklch(0.82 0.13 85)`)
  - light: `oklch(0.53 0.15 h)` (amber `oklch(0.56 0.12 75)`)
  - hues: green 155, amber 85, blue 255, red 25
- **Tint backgrounds** `tint(h)`:
  - dark: `oklch(0.76 0.14 h / 0.14)`
  - light: `oklch(0.62 0.14 h / 0.13)`
- **Selected chip:** background `text`, label `#0A0C10` on dark themes or `#FFFFFF` on light.
- **Document paper** (doc viewer): white `#FFFFFF`, ink `#16181D`, secondary text `#5B6170`, rules `#E3E5EA`, doc-type label `#C2410C`.

### Typography
- **UI font:** `Geist` 400/500/600/700, with fallbacks Noto Sans Tamil, Devanagari, Telugu, Kannada and Malayalam so Indian scripts render.
- **Numbers, IDs, amounts and odometer readings:** `Geist Mono` 500/600.
- **Icons:** Material Symbols Rounded (outline, weight 400).

Type scale used:

| Size | Weight | Use |
|---|---|---|
| 21px | 600 | screen title (letter-spacing −0.02em) |
| 20px | 600 | sheet title |
| 17–18px | 600 | big numbers |
| 14.5–15px | 600 | card title |
| 14px | 600 | button |
| 13–13.5px | 400/600 | body |
| 12–12.5px | — | secondary |
| 11–11.5px | — | pills and captions |
| 12px | 600 | menu group label (UPPERCASE, letter-spacing 0.08em) |

### Shape and spacing
- **Radii:** cards 18 · tiles 14–16 · fields 12 · small buttons 9–11 · icon tiles 11–12 · pills 999 · sheets 28 (top corners) · phone frame 44.
- **Heights:** primary button 46–52 · secondary 42–44 · field 44 · chip 32–36 · toggle 44×26 (20px knob).
- **Spacing:** screen padding 14–16 · gaps 6 / 8 / 10 / 12 / 14.
- **Elevation:** no shadows. Depth comes from surface colour steps and 1px hairlines.

---

## Roles
| Role | Default view |
|---|---|
| Owner | Everything |
| Manager | Everything except billing/plan, restore, approvals decisions |
| Supervisor | My Jobs, job journey (move day), team, attendance approval for field staff |
| Field staff | Attendance check-in, today's job |
| Driver | Driver app (trip start/end, fuel, toll) |

- Per-staff permissions are View / Add / Edit / Delete for each module (screen `staffPerm`).
- Staff attendance is approved by the supervisor. Supervisor attendance is approved by the manager or the owner.
- Owner-only actions: move an order back a stage, reopen an order, approve or reject approval requests, restore a backup, change modules or plan, and choose who may assign a supervisor.

## Business type, modules and plans

### Business type
Asked once after the first-run phone setup and saved on the device:
- Packers & Movers
- Transport / Logistics
- Both

### Modules (Settings › Modules)
Modules sit in three groups:
- **Packers & Movers:** sq, reviews, portal, claims, stor, whs, mats, cftcat, qtheme
- **Transport:** trips, lr, loads, drv, fuel, dadv, vdocs, eway, hire
- **Advanced:** b2b, promo, lrules, gst, cnote, bank, cash, pnl, hr:pay/inc/doc/lab, ins, tasks, olog, plat:br/bk/dw

How they behave:
- The business type picks the default set. The owner can override any module.
- A module that is off is hidden from the menu, and its data is kept.
- Advanced items are collected into one collapsed "Advanced" menu group.

### Plans
| | Free | Basic | Growth | Pro |
|---|---|---|---|---|
| Price / month | ₹0 | ₹499 | ₹1,499 | ₹2,999 |
| Price / year | — | ₹4,990 | ₹14,990 | ₹29,990 |
| Users | 3 | 5 | 10 | Unlimited |
| Orders / month | 20 | 60 | 250 | Unlimited |
| Trial | — | 14 days | 14 days | 14 days |
| Grace period | — | 7 days | 7 days | 7 days |

What each plan adds:
- **Free:** the core flow (Lead → Survey → Quote → Advance & confirm → Order → Payments). Documents: quotation, money receipt, invoice.
- **Basic:** survey report, packing list, LR, loading slip; Operations, Calendar, Attendance, Salary, Fleet, Materials, Driver app, Inbox, Reviews.
- **Growth:** transit insurance and claims, trips, fuel, e-way bills, hired trucks, warehouse and storage, auto WhatsApp, approvals, reports, P&L, coupons, lead rules.
- **Pro:** branches, AI photo survey, customer portal and live GPS, GST/TDS/Tally export, bank and UPI match, cash book, payslips with PF & ESI, backup, B2B accounts.

How plan gating works:
- The minimum plan for each screen is in `PMIN` in `Nagarva App.dc.html`. Screens below the vendor's plan are hidden from the menu.
- Settings › Modules shows a lock pill with the plan name for each locked module, and it opens Plan & billing.
- Plan definitions (prices, limits, trial and grace days, feature flags) are edited in Admin › Plans & pricing.

---

## The order journey (core flow)
Screen `jrny`. It opens from the strip on Lead detail or Order detail, and from My Jobs › Open job journey. It is one record per lead or order, with a 9-segment progress bar.

| # | Stage | What happens | Gate to move on |
|---|---|---|---|
| 1 | Lead | Name, phone, service, route, move date, source, created by and when | — |
| 2 | Follow-up | Log a call outcome (Not reachable / Call back / Interested / Not interested) with notes. The next-follow-up picker has quick picks, a 21-day date strip, a full calendar, Morning/Afternoon/Evening slots and ±15 min. The full history shows who called and when. | Then choose: Survey / Skip survey & quote / Confirm order |
| 3 | Survey | Mode is Visit (date + open the survey screen with camera), Share link (WhatsApp, optional **AI photo survey, Pro only**), or On call (items + CFT). | Survey has a result (link filled / visit date / items) |
| 4 | Quote & advance | Survey estimate (CFT × rate) creates v1. Every version is kept (older ones struck through). Share on WhatsApp. Customer response: Negotiating (send a revised amount), Rejected (reason → lead lost), Confirmed. Optional **transit insurance** (declared value, premium 2%, min ₹250, added to the order value). On Confirmed, **take an advance** (25% suggested; Cash / UPI / Bank / Cheque + reference). This creates the order number and the money receipt together. "Confirm without advance" is also allowed. | Confirmed |
| 5 | Supervisor | Assign a supervisor. Who may assign is set by the owner: Owner only / Owner + manager / Owner + person following up. Sends a "Job assigned" notification. | Supervisor set |
| 6 | Move day | Crew chips, materials issued (limited to stock on hand), vehicle, start and end odometer. Extras: extra work, extra materials, boxes kept by the customer. Each extra is added to the order value. "Start move" needs vehicle + start odometer. "Finish move" needs end > start. | Finish move |
| 7 | Invoice | Quote + extras + insurance = final value. Customer signature (draw or upload). Share invoice. | Signature taken |
| 8 | Payment & issues | Total / Paid / Balance, record a payment (receipt number from prefix), raise or resolve tickets. | **Close is blocked while:** a ticket is open, a balance is due, the signature is missing, or the end odometer is missing. The reason is shown. |
| 9 | Closed | — | Owner can reopen |

Side effects when the move is finished:
- materials are taken out of stock, with the order reference in each item's history
- the vehicle's odometer is updated
- a trip record is added (km, revenue)
- a vehicle service warning shows within 1,000 km of the next service, and turns red when it is overdue (every 10,000 km)

Other journey rules:
- **Direct orders** (created without a lead) start at stage 5, with Follow-up and Survey marked "Skipped · direct order".
- Every action is written to the Activity log (who, role, when, what).
- **Auto WhatsApp** is sent at: new enquiry, survey booked, quote shared, order confirmed, move started, delivered, payment reminder. Each one can be switched on or off in Setup › Auto WhatsApp.

## Order documents
Shown in the Documents panel on the journey screen. Each card shows **Ready · tap to view**, **After {stage}**, **Not opted**, or a **plan lock**.

| Document | Prefix | Ready after | Plan |
|---|---|---|---|
| Survey report | SVY | Survey done (n/a if skipped) | Basic |
| Quotation | QT | First quote version | Free |
| Money receipt | RCT | Each payment (switch between receipts) | Free |
| Packing list | PK | Supervisor assigned | Basic |
| Loading slip | LS | Move started | Basic |
| Lorry receipt (LR) | LR | Move started | Basic |
| Insurance cover | INS | Order confirmed with insurance opted | Growth |
| Tax invoice | INV | Invoice shared | Free |

Document viewer layout (overlay):
- business name, address, GSTIN and phone at the top
- document type in orange, number and date at the top right
- a party grid with two columns
- an item table with 3 columns
- right-aligned totals
- notes and terms
- two signature lines (the customer's drawn signature appears on the invoice)
- footer buttons: Download PDF and Share on WhatsApp

On the invoice, GST is split CGST 9% / SGST 9% from the total.

Numbering:
- Format is set in Settings › Business details › Document numbers: `PREFIX-YYMM-0001` (default), `PREFIX/YY-YY/0001`, or `PREFIX-0001`.
- Each prefix can be edited by the vendor.

---

## Screens (App)
These are the 83 screen keys in the `scr` map in `Nagarva App.dc.html`. Each key is a `<!-- COMMENT -->` section in the template.

- **Auth & first run:**
  - Login (email + PIN or mobile OTP with SMS auto-read consent; biometric unlock)
  - First-run phone permissions sheet (notifications, location, camera, SMS; shown once per install)
  - Business-type sheet
- **Sales:**
  - Dashboard (widgets can be reordered and hidden)
  - Leads list and Lead detail
  - New lead
  - Inbox (WhatsApp)
  - Survey & Quote hub
  - Customers and Customer detail
  - Reviews
  - Business accounts (credit limit, monthly billing)
  - Customer portal & GPS
  - Coupons & referrals
  - Lead rules & lost report
- **Operations:**
  - Orders list and Order detail
  - New order
  - Order journey
  - Operations
  - Daily summary
  - Calendar
  - Trips and Trip detail
  - Tasks
  - LR register
  - Ops log
  - Part-load & routes
  - Damage claims
  - Packing list & box labels (QR)
  - Vehicle (car/bike) checklist with scratch photos
- **Money:**
  - Approvals
  - Payments (custom amount, mode, reference)
  - Rate cards
  - Expenses
  - Accounts
  - P&L
  - Reports
  - GST, TDS & exports (GSTR-1, GSTR-3B, Tally, Zoho)
  - Credit notes & refunds
  - Bank & UPI match
  - Cash book
- **People:**
  - Staff list
  - New staff
  - Staff permissions
  - Salary and salary edit
  - HR tabs: Leave, Payslips/PF/ESI, Overtime & incentives, Staff documents, Labour contractors
  - Attendance (field check-in; supervisor and manager approval)
  - Team and earnings (supervisor)
- **Assets & transport:**
  - Fleet
  - Materials
  - Warehouses
  - Storage billing
  - Driver app
  - Fuel & FASTag
  - Diesel advance
  - Vehicle docs, tyres & battery
  - E-way bills
  - Hired trucks
- **Partners:**
  - Vendors
  - Insurance
- **Account & setup:**
  - Modules
  - Plan & billing (checkout, coupons, AutoPay)
  - CFT & packages
  - WhatsApp templates
  - Quote design
  - Services & sources
  - Business details (logo, tagline, GSTIN, address, phones, bank details, e-signature, default T&C plus vendor T&C, document prefixes)
  - Login & security (change or reset password and PIN for every role, biometric, sessions)
  - Permissions & alerts (tones, vibrate, quiet hours, per-alert toggles)
  - Branches
  - Auto WhatsApp
  - Approvals rules
  - Backup & offline
  - Dashboard widgets
  - Activity log
  - Help & support (raises a ticket in Admin)

Common screen chrome:
- top bar with the business logo and tagline, search (searches leads, surveys, quotes, orders and staff by name or phone), notifications and help
- bottom nav: Home / Leads / Orders / Pay / More
- the More sheet shows menu groups in a 4-column icon grid
- every non-tab screen has a back button

Import and export: 14 core modules have **Import (Excel/CSV)** and **Export**. The app shows the column template and a row-validation preview.

## Screens (Admin)
`Nagarva Admin.dc.html` is a responsive web layout with a sidebar.
- **Dashboard:** MRR, vendors by status.
- **Vendors:** list, filters, and a detail page with Overview / Payments / Logs and actions (extend trial, discount, suspend, reset owner password, delete org).
- **Approvals:** discount and extension requests above each role's limit.
- **Plans & pricing:** the 4 plans, editable price, limits, trial/grace days and feature flags.
- **Payments**, **Tickets**, **Coupons**, **Broadcasts**, and **Team & roles** (super, sales, support, marketing).
- The panel has a light / dark theme switch.

---

## State and data
Each in-memory seed in the prototype maps to a table or entity:

| Seed | Table / entity |
|---|---|
| `LEADS` | leads |
| `ORDERS` | orders |
| journey `J0`/`J1` | order_journey: follows[], survey{}, quotes[], supervisor, crew[], materials{}, vehicle, odo_start/end, extras[], insurance{}, signature, invoice, payments[], tickets[] |
| `STAFF0` | staff (pay type, rates, advances) |
| `VEH0` | vehicles (with service due km) |
| `MAT0` | materials (stock and movements) |
| `TRIPS0` | trips |
| `PLANS` | plans |
| `BIZ0` | business_profile (prefixes, numbering format, T&C) |

- Every write calls `this.log(module, action, text)`, which becomes the `activity_log` table (actor, role, ts).
- Settings persisted on the device: `ng_onb_done` and `ng_biz_type` in localStorage.
- Approval-gated actions (`needAppr`) queue the change for the owner instead of applying it. They cover deletes, revised quotes, payment edits, rate card changes and salary changes. Approving runs the queued change.

## Vendor signup, staff join, check-in, company switch (App)
- **Vendor signup** (screen `signup`): phone → OTP → business → documents → review → status. Admin › Approvals › New vendor signups can approve it (this creates a Free-plan vendor) or send it back with reason chips. Once approved, the vendor picks **Start 30-day Pro trial** or **Stay on Free**. A banner appears when 3 or fewer trial days are left. When the trial ends, the vendor falls back to Free. Rate cards start empty (0) and a banner asks the vendor to fill them.
- **Staff join:** the owner sends an invite code (`AP-xxxx`) from the Staff list. Staff enter code → OTP → set PIN. The phone number must match the staff record. The account sheet offers Help, Log out and Remove this phone.
- **Check-in:** field staff cannot check themselves in. They scan a rotating QR code (refreshes every 30 s) on the supervisor's Team screen. The supervisor checks in by GPS (within 200 m) plus a selfie. The supervisor can "Mark present" crew who have no phone, with a reason. The owner sees "Check-ins to review" in Approvals and can Flag one.
- **Company switch:** tap the business name in the header. The list shows only companies saved on this phone. "Add a company" works by login or invite code. The sign-out icon removes a company that is not the current one.
- **Global search:** an empty query shows only a hint. Results come from data across modules (leads, orders, customers, staff).

## Marketplace (Nagarva sells moves direct)
**Pricing (set by Nagarva only):**
- CFT from the item inventory × package rate (Economy / Standard / Premium; local base + per-km)
- plus floor/stair charge, plus add-ons, plus 18% GST
- Customers see the full total only on **Review and pay**. Package cards show no price. Add-on prices show on the Add-ons screen and are itemised again on Review.

**Money flow:**
- Customer pays an advance to Nagarva: 10%, minimum ₹999.
- The balance is paid to the vendor after the delivery OTP.
- On completion, the vendor wallet is credited with the advance minus 12% commission (commission is on the ex-GST amount).

**Broadcast:**
- Gold vendors see a job first, then Silver, then Bronze.
- Admin sets the delay windows per city. The first vendor to accept gets the job.
- If the wallet is below the minimum (default ₹2,000), the vendor cannot see broadcasts.
- Premium-package jobs go to Gold only.

**Tier score:** 7 weighted factors (rating, on-time arrival, damage claims, acceptance rate, photo compliance, vendor cancellations, jobs completed). The weights must total 100. Tiers: Gold 80+, Silver 60+, Bronze below 60.

**Vendor app › Nagarva jobs** (screen `mkt`, menu Sales):
- **Jobs tab:**
  - new broadcasts with a Gold timer, a masked customer, and Accept / Pass
  - accepted jobs move through the stepper Accepted → On the way → Arrived → Loading (3 photos) → In transit → Delivered (customer OTP)
  - completed jobs with their rating
- **Wallet tab:**
  - balance and minimum
  - top up by UPI
  - withdraw above the minimum
  - transaction list
- **Tier tab:** the factor breakdown and score.
- **Also:**
  - an Available switch
  - extra pickup cities
  - return-trip mode, which offers jobs heading back to the home city

**Admin › Marketplace:**
- **Live:** 4 columns plus a job drawer with the timeline. Actions: push to the next tier, assign, re-assign.
- **Alerts:** no vendor, late, missing photos, stuck.
- **Disputes:** refund / split / reject.
- **Vendors:** tier, score, wallet, suspend.
- **Money:** GMV, advances, commission. Withdrawals can be marked paid.
- **City rules** (steppers): Gold/Silver windows, wallet minimum, commission %, advance % and minimum, late minutes, stuck hours, return-trip window.
- **Weights:** the tier factor weights.
- **Return trips:** return-trip jobs and vendors.

## Customer app and website
`Nagarva Customer.dc.html` is the phone app. `Nagarva Website.dc.html` is the **same flow and look** in a web shell: a blue site bar and a centred 560px column. Keep the two in sync.

**Flow:**
1. Login: mobile → OTP (demo 1234), coupon FIRST500
2. Move type: Full house / Office / Up to 5 items / Bike only; Within city or Intercity
3. Home: pickup / drop card, then "Get my moving cost"
4. Items: room by room, size variants, install / uninstall options
5. Move date and pickup time slot
6. Package: Economy / Standard / Premium (Economy only for shared intercity)
7. Add-ons: damage cover, unpacking & arranging, storage with a months picker
8. Review and pay: itemised bill, coupon, a blue "ticket" total (Pay now to Nagarva / Pay mover later), cancellation policy
9. Payment: UPI / card / net banking
10. Booking confirmed

**After booking:**
- **Track:** blue header with a truck moving along the route line by stage; timeline Booked → Mover assigned → Packing → On the way → Delivered → Balance paid; crew card (calls are masked through Nagarva); crew photos; delivery OTP shown as 4 digit boxes; pay balance; rating with good/bad chips.
- **Reschedule:** free if more than 72 h before the move, ₹500 within 72 h.
- **Cancel:** full refund more than 72 h before the move, 50% of the advance at 72–24 h, no refund within 24 h.
- **Report damage:** pick items, add photos, Nagarva reviews within 48 h.
- **Bookings** and **Account** (saved addresses, language, payments, help).

**Customer tokens** (light only):
- Nagarva blue `#0B2F73` (hero, selected card, ticket), deeper blue text `#0B3A8C`
- orange `#F37A0E` (CTA, highlight word, truck), text on orange `#0A0C10`
- page `#F4F3F0`, card `#FFFFFF`, ink `#16181D`, secondary `#5E6572`, hairline `rgba(22,24,29,0.08)`
- the hero has a bottom radius of 30, the floating card a radius of 22 with shadow `0 18px 40px -18px rgba(11,47,115,0.45)`
- primary CTA 54px tall, radius 16
- decorative orange ring: 34px border, `rgba(243,122,14,0.16)`
- Home headline 34px/700, letter-spacing −0.045em
- the truck animation loops every 9 s, linear

## Translations
- English plus Hindi, Tamil, Telugu, Kannada and Malayalam. Each string is a key such as `jr_title`.
- English source strings live in the `S`, `S2`, `HP`, `B1…B20` objects in the app file.
- Other languages live in `design/i18n-*.js` as `window.NG_TX[lang][key]`. Menu labels are in `NG_TX[lang]._mnu`.
- Native-speaker review is complete (28 Oct 2026).
- **Customer app / website** use a different scheme:
  - dictionaries keyed by the English text itself: `i18n-c-{hi,ta,te,kn,ml}.js`, with `*2.js` holding the second half of each language
  - each dictionary also has `_p` regex patterns for dynamic strings ("3 items", "2nd floor")
  - `i18n-cust.js` swaps the text in the DOM; this is a prototype shortcut only
  - in the real app, move these strings to proper ARB/l10n keys
  - addresses, names and booking codes stay in English
  - the selected language is saved as `ng_cust_lang`

## Assets
- `design/assets/icon/nagarva_icon.png`: app icon.
- `design/assets/images/nagarva_logo.png`: wordmark. Each vendor's uploaded logo replaces it in the top bar and on documents.
- Icons are Material Symbols Rounded; use Flutter's `material_symbols_icons` package.

## Files
- `design/Nagarva App.dc.html`: the full app prototype.
- `design/Nagarva Admin.dc.html`: the admin panel.
- `design/Nagarva Customer.dc.html`: the customer mobile app.
- `design/Nagarva Website.dc.html`: the customer website (same flow as the app).
- `design/support.js`: the prototype runtime, needed to open the files. Not for porting.
- `design/i18n-*.js`, `design/i18n-s2-en.json`: translation tables (vendor/admin). `design/i18n-c-*.js` + `i18n-cust.js`: customer app/website.
- `design/Quote Themes.dc.html`: quote PDF layout options.
- `design/Crew & Accounts Wireframes.dc.html`: crew pay and expense wireframes.
- `github.md`: the repo screen map.
- `Nagarva Plan.md`: the product plan.
- `WORKING_NOTES.md`: build notes from the design sessions.
- `screens/`: reference screenshots. Open the HTML to see every other state.
  - `screens/app/`: vendor app, every module, full-length PNGs (390 wide @2x, light theme, owner on Pro plan, business type "both"). File names follow the More-menu groups:
    - `00-more-menu`, `auth-01..03` (owner login, staff login, vendor signup), `role-01..03` (supervisor jobs, supervisor Team QR, field attendance), `sheet-01..04` (staff join, switch company, add company, staff invite).
    - `sales-01..11`: dashboard, leads, Nagarva jobs (+ wallet, tier), inbox, survey & quote, customers, reviews, business accounts, customer portal & GPS, coupons & referrals, lead rules & lost report.
    - `ops-01..11`: orders, operations, daily summary, calendar, trips, tasks, LR register, ops log, part-load & routes, damage claims, order journey.
    - `money-01..11`: approvals (+ check-ins), payments, rate cards, expenses, accounts, P & L, reports, GST/TDS/exports, credit notes, bank & UPI match, cash book.
    - `people-01..07`: staff, salary, leave, payslips/PF/ESI, overtime & incentives, staff documents, labour contractors.
    - `assets-01..04`: fleet, materials, warehouses, storage billing.
    - `transport-01..06`: driver app, fuel & FASTag, diesel advance, docs/tyres/battery, e-way bills, hired trucks.
    - `partners-01..02`: vendors, insurance.
    - `account-01..09`: modules, plan & billing (+ trial), CFT & packages, WhatsApp, quote design, services & sources, business details, login & security, permissions & alerts.
    - `setup-01..07`: branches, auto WhatsApp, approval rules, backup & offline, dashboard widgets, activity log, help & support.
  - `screens/admin/`: every admin page, full length: `00-login`, `01-dashboard`, `02-marketplace` + `02a..02h` tabs (live, job drawer, alerts, disputes, vendors, money, return trips, city rules), `03-vendors`, `04-vendor-detail`, `05-approvals`, `06-plans-pricing`, `07-payments`, `08-support-tickets`, `09-coupons`, `10-broadcasts`, `11-admin-team`, `12-audit-log`.
  - Screenshots are DOM renders; a few labels wrap slightly differently than in the browser. The HTML is the source of truth for spacing and wrapping.
  - `screens/customer/`: all 21 customer app screens and sheets in flow order (01 login → 21 account), plus Home in Tamil and Review in Hindi.
  - `screens/website/`: website shell versions of login, home, items, package, review & pay, track, bookings, account.
- Dev note: each prototype exposes `window.__ngC` (the component) so states can be set from the console, e.g. `__ngC.setState({scr:'track',stage:3})`. Prototype only.
