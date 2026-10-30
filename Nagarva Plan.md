# Nagarva — Product plan (Crew, Salary & Accounts)

Draft for review. Items marked **❓** need your answer before we build.

---

## 1. What we are building

A mobile app for a packers & movers vendor that runs the whole job:
lead → quote → order → job day → daily closing → owner approval → accounts & salary.

The part we are working on now is **what happens after the job day**: recording who worked, what was spent, and turning that into staff pay and order profit.

## 2. Who uses it

| Person | What they do |
|---|---|
| **Owner** | Sets up services, lead sources, staff and salary methods. Approves daily summaries. Pays salary. Sees accounts and profit. |
| **Supervisor** | Runs jobs on site. Closes each day: crew, pay for daily/temporary staff, food, costs, advances, vehicle. Submits to owner. |
| **Staff** (driver, packer, helper) | Sees own jobs, attendance, earnings, advances, salary slips. |

✅ **Decided:** access is not fixed by role. When the owner creates a staff member, he ticks what that person can **View / Add / Edit / Delete** per module (see 3.4). Role only pre-fills a default set.

## 3. Setup (done once, edited anytime)

**3.1 Services** — vendor's own list (House shifting, Office shifting, Bike shifting, Pet relocation…). Used in New lead, New order, reports.

**3.2 Lead sources** — vendor's own list (Meta, Google, Justdial, Referral…). Used in New lead, New order, reports.

**3.3 Staff** — one record per person:
- Photo, name, phone, address
- Aadhaar number + Aadhaar photo
- Role (Driver, Supervisor, Packer, Helper)
- Referred by (name + phone)
- **Salary method** (see 4)

**3.4 Permissions** (set while creating/editing staff)

| Module | View | Add | Edit | Delete |
|---|---|---|---|---|
| Leads | ☐ | ☐ | ☐ | ☐ |
| Quotes | ☐ | ☐ | ☐ | ☐ |
| Orders | ☐ | ☐ | ☐ | ☐ |
| Daily summary | ☐ | ☐ | ☐ | — |
| Approve daily summary | ☐ | — | — | — |
| Staff | ☐ | ☐ | ☐ | ☐ |
| Salary & advances | ☐ | ☐ | ☐ | — |
| Accounts & profit | ☐ | — | — | — |
| Stock / materials | ☐ | ☐ | ☐ | ☐ |
| Settings (services, lead sources, quote design) | ☐ | ☐ | ☐ | ☐ |

Role defaults (owner can change any tick):
- **Supervisor** — Leads, Orders, Daily summary (view/add/edit), Staff (view), Stock (view/add).
- **Driver / Packer / Helper** — own jobs and own salary only.
- **Owner** — everything; cannot be removed.

Extra rules:
- **Own data only** toggle — e.g. supervisor sees only orders assigned to him.
- **Hide amounts** toggle — can see orders but not prices/profit.
- Nobody can give someone more access than they have.

Same model is reused in **Nagarva Admin** (section 10) for Sales / Support / Marketing.

✅ **Extra staff details:** emergency contact (name, relation, phone) and joining date. Added to Add staff and the staff profile.

## 4. Salary methods

| Method | Who | How pay is decided |
|---|---|---|
| **Fixed monthly** | Permanent staff | Fixed amount per month. Optional trip allowance and overtime on top. |
| **Daily** | Regular staff, not on salary | No fixed rate. Supervisor enters the day's pay in Daily summary, based on the order value. |
| **Temporary** | Called only when needed | Same as daily — pay entered per job/day. |

Rules:
- Daily/temporary pay **must** be entered before the day can be submitted.
- Owner can change any amount during approval; the old amount is shown.
- Monthly staff are paid from Salary, not cash on the day.

✅ **When pay is given:** daily and temporary labour are paid after each order ends; their pay has no link to monthly staff. Monthly staff are paid by the **10th of the next month**.
✅ **Monthly staff leave:** 26 paid working days + 4 weekly offs (paid). Absent on a day with no order = paid. Absent because he **refused an order** = unpaid day, cut = monthly ÷ 26. Supervisor marks this in Daily summary → crew → Leave → "Refused an order"; owner sees it in approval and it is logged.

## 5. The job day → Daily summary

Supervisor closes each day in 6 steps:

1. **Crew** — who worked, on which orders, what kind of work (full / half / loading / unloading). Leave marked here.
   - Daily/temporary: enter today's pay, split across orders (equal by default, editable).
   - Monthly: share shown automatically (salary ÷ 26), split across orders.
2. **Food & room** — food/tea per order, room stays shared by people.
3. **Costs** — diesel, toll, material, parking, add-on services (cost + amount billed to customer).
4. **Advances** — cash advance given to staff or vendor today.
5. **Vehicle** — hired vehicle: vendor, freight, advance paid, collected from customer, who owes whom.
6. **Review** — totals, warnings, submit.

## 6. Owner approval

- Status: Draft → Submitted → **Approved** or **Sent back** (with reason) → resubmitted.
- Nothing hits accounts or salary until **Approved**.
- On approval the app posts:
  - Daily/temporary pay → each person's earnings for the month
  - Advances → deducted from that person's salary
  - Costs, food, vehicle, labour share → each order's cost
  - Cash movements → day book

✅ **Locked days:** approved days are locked. Only the vendor owner can reopen; reopening is recorded in the Activity log and the supervisor must resubmit.

## 7. Salary (monthly)

Per staff, for the month:
- **Earned** = monthly salary (+ trips + overtime) **or** sum of approved daily pay
- **− Advances**
- **− Already paid**
- **= Balance to pay**

Owner pays (UPI/cash), staff gets WhatsApp message + slip.

## 8. Accounts & order profit

Per order:
**Order value − (labour share + food + costs + vehicle) = profit**

- Labour share for monthly staff is an estimate (salary ÷ 26 split over that day's orders). It tells you roughly what labour cost each order — not exact.
- Day view: all orders and costs for one day.
- Month view: total income, costs, profit by service and by lead source.

✅ **Monthly costs:** office rent, phone, WiFi, electricity and similar costs are entered in Accounts → Overview → Office & monthly costs, and are deducted in month profit.

## 9. Status today

| Area | Status |
|---|---|
| Services & lead sources settings | Built |
| New lead uses those lists | Built |
| New order uses those lists | Built (Service + Lead source chips, prefilled from lead) |
| Staff form + salary methods | Built (photo upload is placeholder) |
| Daily summary + approval | Built (demo data) |
| Monthly share in order cost | Built |
| Salary page | Built |
| Accounts screens | Built. Approved days now post in (older days are demo data) |
| Posting on approval | Built: daily/temp wages + days → Salary, advances → staff advance list, refused days → salary cut, orders & costs → Accounts day. Reopen reverses it. |
| Staff list page | Built (Menu → People → Staff: search, salary-method and role filters, call, open profile) |
| Tamil / Hindi for new screens | **Not yet** |

## 10. Nagarva Admin (platform side)

A separate login for **Nagarva the company**, not for vendors. Works on desktop web and mobile.

### 10.1 Who logs in

| Role | Sees | Can do |
|---|---|---|
| **Super admin** (Nagarva owner) | Everything | Everything, incl. managing admin users and plan prices |
| **Sales** | Trials, new sign-ups, leads assigned to them | Follow up, extend trial, apply discount (up to a limit), convert to paid |
| **Support** | Vendor profile, plan, usage, tickets, vendor's error log | Answer tickets, reset vendor password, see the vendor's last actions and errors (no login as vendor) |
| **Marketing** | Sign-up sources, campaign numbers, plan mix | Create coupon codes, send broadcast (WhatsApp/in-app) |
| ~~Accounts~~ | — | Not a person. Handled by the system (see 10.4). Super admin approves refunds. |

Rule: same permission grid as vendor staff (3.4) — role pre-fills, super admin adjusts per person. Each person sees only the menus they are allowed. Sales sees only vendors assigned to them unless super admin allows all.

### 10.2 Screens

1. **Dashboard** — active vendors, trials, expiring this week, MRR, new sign-ups, open tickets. Each role sees only its tiles.
2. **Vendors** — list with search/filter (city, plan, status, sign-up source, assigned sales person).
3. **Vendor detail** — business info, owner contact, GSTIN, plan & expiry, users count, orders this month, payment history, tickets, notes/activity log.
   - Actions: **Activate / Deactivate / Suspend**, extend expiry, change plan, add free days, reset password, assign sales person.
4. **Plans & pricing** — Starter / Growth / Pro: price monthly & yearly, user limit, order limit, features on/off. **Trial & discount settings:** trial days (30), grace days (7), max discount % for sales (10). Price change applies to new sign-ups; existing vendors keep price until renewal (❓ confirm).
5. **Coupons** — code, % or ₹ off, valid till, max uses.
6. **Payments** — all subscription payments, failed, refunds, invoices.
7. **Support tickets** — from vendor app; status, priority, assigned agent.
8. **Leads / trials (Sales)** — sign-ups not yet paid, follow-up date, notes.
9. **Broadcasts (Marketing)** — message to all / by plan / by city.
10. **Admin team** — add staff, give role, deactivate. Super admin only.
11. **Audit log** — who changed what (plan, status, price). Super admin only.

### 10.3 Vendor status rules

| Status | Vendor app |
|---|---|
| Trial | Full access till trial end |
| Active | Full access |
| Grace (expired ≤ 7 days) | Works, shows renew banner every day with days left |
| Expired | Read-only, can renew |
| Suspended / Deactivated | Cannot log in, sees contact-support screen |

✅ **Trial:** 30 days, full access. **Grace:** 7 more days after trial or plan ends. Day 38 → Expired (read-only).
✅ **Managed from Nagarva Admin → Plans & pricing:** super admin sets default trial days, grace days and discount cap. New sign-ups get the new values; existing trials keep theirs. Per vendor, super admin or sales can extend a trial from Vendor detail (sales up to 7 days, more needs super admin). Every change is logged in the audit log.
✅ **Payment gateway:** Razorpay. Keys stored on the server only, never in the app.
✅ **Discount:** 10% for now. It is a setting in Nagarva Admin → Plans & pricing, so super admin can change it later without an app update. Sales can apply up to this cap; above it needs super admin approval.
✅ **Support:** no login as vendor (vendors don't want it). See 10.5.
✅ **Accounts:** no Accounts person. The system does it (see 10.4).
✅ **Renewal:** both. AutoPay (UPI/card mandate) is the default at checkout; vendor can switch to "Pay manually each time". Can change anytime in vendor app → Plan & billing.
✅ **Admin platform:** desktop web and mobile. Same login and permissions; mobile shows a compact layout (dashboard tiles, vendor list, vendor detail actions, tickets). Heavy screens (audit log, reports, plan editor) work on mobile but are best on desktop.

### 10.4 Payments handled by the system

1. Vendor taps **Renew** → Razorpay checkout (UPI, card, netbanking). Or AutoPay mandate if chosen.
2. Razorpay sends a **webhook** to our server → payment marked Paid → plan end date moves forward → vendor status back to Active. No one marks it by hand.
3. **GST invoice** is made automatically (invoice number series, vendor GSTIN if given) and sent on WhatsApp + email; also downloadable in the vendor app.
4. **Failed payment / AutoPay failed:** system retries on day 1 and 3, sends WhatsApp reminder; vendor moves to Grace as normal.
5. **Reminders:** 7, 3 and 1 day before trial or plan end; daily during Grace.
6. **Daily check:** system matches every Razorpay payment with our records each night. Anything not matching shows on the Admin dashboard as a red tile for super admin.
7. **Refunds:** super admin only, from Payments screen; goes through Razorpay refund API, credit note made automatically.
8. **Monthly report:** collections, GST collected, refunds, MRR — one-tap Excel export for the CA.

### 10.5 Support without logging in as vendor

- **Vendor snapshot** in Vendor detail: plan, status, users, last login per user, app version, phone model, orders this month. No order prices, no customer data.
- **Activity & error log:** last 50 actions and any app errors (e.g. "photo upload failed", "daily summary submit failed") with time. Support sees what went wrong without seeing the vendor's data.
- **Help from inside the app:** vendor taps Help → writes issue → app attaches screen name, app version and the last error automatically. Optional screenshot, sent only if vendor taps "attach".
- **Call-back / WhatsApp:** ticket shows a WhatsApp button so support can message the vendor directly.
- **Fix tools for support:** reset PIN/password, resend invoice, extend trial by up to 7 days (logged), clear stuck sync.
- **Screen share only if vendor agrees:** support sends a one-time request; vendor taps Allow; ends when either side closes. Logged in audit log.

## 11. Proposed build order

1. ~~Answer the ❓ above.~~ Done.
2. ~~New order: Service + Lead source from Settings.~~ Done.
3. ~~Staff list page~~ Done.
4. ~~Posting on approval~~ Done.
5. ~~Accounts month view by service and lead source~~ Done (Accounts → Profit by).
6. Translations.
7. **Nagarva Admin**: login + role picker → Dashboard → Vendors list → Vendor detail with activate/deactivate → Plans & pricing → Admin team & permissions → Tickets, Payments, Coupons, Broadcasts.
   - ✅ Batch 1 built (Nagarva Admin.dc.html): login with role (demo), role-based Dashboard, Vendors list (search, status & city filters, sales see only assigned), Vendor detail (snapshot, plan, payments, admin log; actions: extend trial / free days, change plan, discount, reset owner PIN, assign sales, suspend / deactivate / activate with reason, caps for sales/support), Plans & pricing (prices, limits, trial 30, grace 7, discount cap 10%, extension cap 7), Admin team (add, deactivate, View/Add/Edit/Delete grid, "sees all vendors" for sales), Audit log. Works on desktop (sidebar) and mobile (drawer, bottom-sheet dialogs).
   - ✅ Batch 2: Approvals queue (sales/support requests above limits → super admin approves/rejects with reason; applied + logged) and Payments (Oct tiles, paid/failed/retrying/refunded, retry now, refund with credit note, resend invoice, nightly Razorpay check with link-to-vendor fix, October Excel report for CA).
   - ✅ Batch 3: Support tickets (priority, assign to me, WhatsApp reply, screen/app version/error attached, fix tools, resolve/reopen), Coupons (% or ₹ off, plans, valid till, max uses, pause; >30% needs super admin), Broadcasts (WhatsApp / in-app / both; all, by plan, by city, trial, expiring; Meta cost estimate).
   - ✅ Vendor app billing: Razorpay checkout sheet (coupon, GST 18%, AutoPay on by default, UPI/Card/Netbanking, success + WhatsApp invoice), grace banner (7 days, app works), expired lock screen (renew / read-only / WhatsApp support), demo switch on Plan & billing.
   - Next: vendor app Help button → Admin tickets; billing strings into translations.


## 12. Activity log / audit trail

✅ **Built in the vendor app:** Menu → Setup → Activity log. Timeline inside every Lead and Order detail (newest 6, "All N" opens the full log filtered to that ID).

**What is recorded:** create, edit, delete, approve, send back, assign, status/stage change, calls and call outcomes, notes, quotes sent, payments, receipts, invoices, expenses, salary paid, advances, staff added, permission changes, settings lists, login/logout, log exports. Each entry: who, role, when, device, module, action, Lead ID, Order ID, before → after values, reason.

**Lead → order:** one chain per customer. Order timeline also shows its lead's history, so you see who called, followed up, quoted and converted.

**Deletes:** reason required. Record is removed from lists, a full copy is kept in the log entry. Delete needs the Delete tick for that module.

**Screen filters:** date, module, action, done by, search Lead / Order ID / name. Admin adds vendor filter. CSV and Excel export (respects the viewer's masking).

### 12.1 Who sees what

| Viewer | Sees |
|---|---|
| Vendor owner | All activity of own company |
| Manager | Activity log tick on by default; modules he can view |
| Other staff | No log screen by default (owner can tick it). Timelines show only modules they can view. "Own data only" → only their own actions and their jobs. "Hide amounts" → ₹ masked, Accounts/Payments hidden; own salary/advance still shown |
| Nagarva Super admin | All vendors, everything, can export |
| Nagarva Support | All vendors, amounts and customer phones masked, no export |
| Nagarva Sales | Assigned vendors only; Leads, Quotes, Orders only; amounts masked |

Vendor owners also see actions Nagarva staff took on their account (e.g. "PIN reset by Nagarva Support").

### 12.2 Security (server build)

- Written by the server inside the same database transaction as the change. The app never writes logs directly.
- Append-only table: no update/delete API; database role for the app has INSERT + SELECT only.
- Each entry stores a hash of itself + the previous entry (hash chain). Nightly job verifies the chain; a break alerts super admin.
- Server time (IST) only; device time is ignored.
- Never logged: PIN, password, OTP, tokens, Razorpay keys, full Aadhaar (last 4 only).
- Retention: 7 years for money entries (GST), 3 years for the rest. ✅ confirmed.


## 13. Languages (pan-India)

Language picker is a dropdown sheet (login screen + app header): English, हिन्दी, தமிழ், తెలుగు, ಕನ್ನಡ, മലയാളം, मराठी, বাংলা, ગુજરાતી, ਪੰਜਾਬੀ, ଓଡ଼ିଆ, অসমীয়া, اردو. Searchable by native or English name.

- ✅ Phase 1 done: English, Hindi, Tamil, Telugu, Kannada, Malayalam for all app text in the translation table (604 strings, incl. order stages, lead status, menu groups, WhatsApp templates). Machine-quality, needs native review.
- ✅ Newer screens (Activity log, Staff list, Profit by, leave reasons, monthly costs, language picker, delete lead) now translated in all 6 languages.
- Still English by design: Activity log entry text (it is a record, kept as written), module/action filter names, Nagarva Admin texts.
- Plan: move all text to translation files per language; add Telugu, Kannada, Malayalam, Marathi, Bengali, Gujarati next; Urdu needs right-to-left layout.
- Customer-facing items (WhatsApp templates, quote PDF, survey link) follow the customer's language, set on the lead.
**Rollout (north + south first):**
1. **Phase 1:** English, Hindi, Tamil, Telugu, Kannada, Malayalam. Covers the Hindi belt (Delhi NCR, UP, Bihar, MP, Rajasthan, Haryana, Uttarakhand, Jharkhand, Chhattisgarh) and all of the south (Chennai, Bengaluru, Hyderabad, Kochi). Hindi also works as a second language for most crews in Mumbai, Pune, Ahmedabad and Punjab.
2. **Phase 2:** Marathi, Bengali, Gujarati, Punjabi (Mumbai, Pune, Kolkata, Ahmedabad, Surat, Punjab).
3. **Phase 3:** Odia, Assamese, Urdu (Urdu needs right-to-left layout).
- Field-staff screens (attendance, earnings, jobs) are translated first in each language; owner screens next.
❓ Who checks translations (your team or a translation vendor)?
