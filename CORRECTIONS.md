# Nagarva redesign — corrections before build

**For:** Cowork (Flutter build) · **From:** design review of `design_handoff_nagarva_redesign` (20 Oct 2026)
**Rule:** where this file and `README.md` disagree, **this file wins**. Line numbers refer to `design/Nagarva App.dc.html`.

Status key: **FIX** = decided, build it this way. All items are decided (B-rows confirmed 20 Oct 2026).

---

## A. Must fix — conflicts with decisions already made

### A1. One stage model, not three — FIX
The prototype shows three separate progress trackers for the same record:
- the 9-stage journey strip (`jrny`, line 2211) — Lead · Follow-up · Survey · Quote & advance · Supervisor · Move day · Invoice · Payment & issues · Closed
- a 5-step lead pipeline on Lead detail (line 665) — New · Follow up · Survey · Quoted · Order
- a 6-step order status list on Order detail (line 731) and My jobs (line 454), from `STAGES` (line 3889) — Confirmed · Packing · In transit · Arrived · Delivered · Completed

**Build:**
- One state resolver (`order_journey`) is the only source of stage. Every screen reads it; actions are derived from it, never from hardcoded button lists (this is the shared mechanism from the 15 Sep pending-UX decision).
- The 6 move statuses become **sub-steps of journey stage 6 (Move day)**, not a parallel tracker. The "Mark as In transit" button stays, but it advances the Move-day sub-step inside the same record.
- Remove the separate 5-step lead pipeline from Lead detail; the journey strip at the top replaces it.
- Lead list/detail shows **"Converted"** once the lead reaches stage 4 Confirmed, and hides Build quote / Convert / Edit lead / Delete lead.

### A2. Attendance = supervisor group photo — FIX
Prototype (line 494, `attendance`): each field staff taps a fingerprint **Check in**.
**Build:** the supervisor takes one **group photo** of the crew at the site (with GPS + time). The app lists the crew for that job; the supervisor ticks who is present. Add automatic face matching against staff photos **if feasible** (optional phase 2 — the tick list must work without it).
Field staff screen keeps "Today's job", "This week" and "Earned this month", and drops the self check-in button.

### A3. Advances: only the manager records them — FIX
Prototype: the supervisor's Daily summary has an **Advance** tab (`dsTab==='adv'`, line 6657) where advances are added.
**Build:**
- Remove the Advance tab from the supervisor's Daily summary (tabs become Crew · Food & room · Costs · Vehicle · Review).
- Advances are recorded only by the **manager** (and owner) in Salary/Staff.
- The supervisor can **view** salary, attendance and advances for **their own branch only** — read-only.
- Staff can view their own advance history and salary balance — read-only.
- Default permission grid for the Supervisor role: Advances = View only (no Add/Edit).
- Vehicle freight advances to a hired vehicle's driver (the "Fr. Veh" case) are **not** staff advances; keep them in the Vehicle tab against the order.

### A4. No pre-filled money (§52) — FIX
Pre-filled values found:
| Where | What | Line |
|---|---|---|
| Advance on confirm | `defAdv = Math.max(500, 25% rounded to ₹500)` | 5095 |
| Quotation document | advance row = 25%, min ₹500 | 5825 |
| Quotation document | payment schedule 55% / 25% / 12% | 5822 |
| Transit insurance | premium 2%, minimum ₹250 | 5020 |

**Build:**
- Advance field opens at **₹0**. Quick-pick % chips are shown only if the vendor has set them in Settings › Rate cards (advance %, optional).
- Quote payment schedule comes from the vendor's own terms; if none is set, no schedule is printed.
- Insurance premium % and minimum are **vendor settings** (empty by default). If they are not set, the insurance toggle asks the vendor to set them first.
- The survey estimate (CFT × rate) is fine **only** because the rate comes from the vendor's own rate card. If the rate card is empty, show "Set your CFT rate", not a number.

### A5. GST — per vendor and per branch, with IGST — FIX
Found in the prototype, three different hard-coded rates:
- P&L: "GST summary (5%)" — CGST 2.5 / SGST 2.5 (`pl_gst`, line 4459)
- GST & exports: `gross / 1.18` (18%) (line 5538)
- Invoice (README): CGST 9% / SGST 9%, never IGST

**Build:**
- Settings › Business details, **per branch**: GST registered yes/no, GSTIN, state, default GST rate (no default value — vendor picks).
- **Unregistered branch** (e.g. APC Karnataka, APC Andhra Pradesh): the order's final document is a **Bill of supply / Invoice without GST**; no tax lines and no GST in the P&L for that branch.
- **Registered branch:** place of supply = customer state. Same state as branch → CGST + SGST (rate ÷ 2 each). Different state → **IGST** at the full rate. A Chennai → Bengaluru move billed from Chennai is IGST.
- P&L, GST exports and invoice all read the **same** rate and split from the order; no screen computes its own.
- Show the rate on the invoice exactly as configured (do not print "9%" literally).

### A6. Revised quote confirmed by the customer via a link — FIX
Prototype: the customer's response (Negotiating / Confirmed / Rejected) is tapped by staff. There is no customer-side acceptance.
**Build (journey stage 4):**
- "Share quote" sends a `link.nagarva.in/quote` link for the **current version**.
- The customer opens it, sees the version and its items, and taps **Accept** (with optional signature) or **Ask for changes**.
- On Accept → the customer pays the advance on the same page (Razorpay/UPI) or the vendor records it → order confirms → order number + money receipt are created together.
- Every new version re-sends the link; older links show "This quote was replaced by v{n}".
- Staff can still record the response manually (customer replied by phone) — logged as "Confirmed by {staff} on call".

---

## B. Decisions (confirmed by Arun, 20 Oct 2026) — FIX

| # | Topic | Decision |
|---|---|---|
| B1 | **Move back a stage / Reopen** vs the stage-lock rule | Keep as an **owner-only override**. A reason is required, it is written to the Activity log, and it reverses posted side effects (stock, odometer, receipts). |
| B2 | **Trial length** | **30 days.** Change README and Admin › Plans (`trialDays`, currently 14) to 30. Grace stays 7 days. |
| B3 | **Plan names** | Free / Basic / Growth / Pro (no change requested). Update Plan.md, which still says Starter/Growth/Pro. |
| B4 | **Trial = Pro** | The 30-day trial is the **full Pro plan** (all modules, AI photo survey included). There is **no** per-trial plan choice and **no** AI-survey quota on lower plans: AI photo survey stays Pro-only. When the trial ends, the vendor picks Free/Basic/Growth/Pro, and gets 7 days' grace. Remove "Trial: 14 days" per plan from the README plans table; replace it with one row: "Trial: 30 days of Pro for every new vendor". |
| B5 | **Branches** | Growth = 2 branches, Pro = unlimited. |
| B6 | **Bottom nav** | Owner/manager: Home · Leads · Orders · Pay · More (Ops moves into More). Supervisor: My jobs · Orders · Ops · More. |
| B7 | **Default theme** | Light by default; midnight/dark in settings. |

---

## C. Cost allocation must be configurable per vendor — FIX
The Daily summary defaults ("split equal") follow APC's way. Nagarva is multi-vendor, so each rule is a vendor setting with APC's rule as one option:
- Daily/temporary wages → split across that day's orders for that person (equal by default, editable). ✔ already in prototype
- **Food/tea** → split only among staff who went on that order, and **collected from staff** (APC) — option: company expense to the order.
- **Room** → not linked to orders; split equally among the people staying in the room and collected from each (APC) — option: office overhead.
- Diesel, materials, add-on services → cost of the specific order.
- Hired-vehicle freight → per order, with "customer pays us" / "customer pays vehicle owner directly" settlement.

---

## D. Small UI fixes — FIX
1. **Journey stage 4:** the v1/v2 quote list is drawn twice (once in the stage card, once below the survey estimate). Keep only the lower list with struck-through older versions.
2. **Attendance screen:** the notification card title reads "Notification sound" (`nt_title`, line 4849). Rename it to "Notifications".
3. **Pull-to-refresh** on every scrollable page (the top-bar refresh button can stay as well). This is part of the one refresh mechanism from the 15 Sep decision.
4. **Plan & billing:** label the AutoPay amount "₹1,769 incl. 18% GST" so it matches "Renew · ₹1,499".
5. **Translations** (hi, ta, te, kn, ml) are machine-written. Ship them behind a "Beta" label in the language picker until native review is done; do not change keys.

---

## E. README edits
Update `README.md` so it no longer contradicts this file:
- Roles table: Field staff = "today's job, own earnings" (no self check-in); Supervisor = "group-photo attendance, view-only salary/attendance/advances for own branch".
- Journey stage 4: customer link acceptance; advance opens at ₹0; insurance % from settings.
- Journey stage 6: lists the move sub-steps (Packing → In transit → Arrived → Delivered).
- Order documents: invoice tax follows A5 (CGST+SGST or IGST, or no GST for unregistered branches).
- Plans table: apply section B — 30-day trial of Pro for every new vendor (not per plan), Growth gets 2 branches, AI photo survey Pro-only.
- Common screen chrome: bottom nav per B6; default theme light per B7.
