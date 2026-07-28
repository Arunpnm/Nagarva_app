# NAGARVA PARITY BRIEF — 27 Jul 2026

## CONTEXT

A live phone test of the Nagarva APK surfaced bugs and gaps. The APC React web
app (arunpkrs.netlify.app) is the TARGET behaviour — I have placed its source at
`reference/apc_web_App.jsx` (14,770 lines). Read from it directly; do not guess
at values that are written there.

Key line references in that file, verified:
- `SURVEY_CATS` — line ~677. Six categories, ~50 items, CFT per variant.
- `getSubCft()` helper — immediately after SURVEY_CATS.
- `DEFAULT_CFT_RANGES` / `DEFAULT_PACKAGES` — line ~880.
- Charges + chargeTypes state shape — line ~2671.
- Charge billing-mode UI — line ~3175.
- Quotation line-item builder — line ~2789.
- `MaterialsPage` — line ~7709. `MatQuickUse` — line ~3996.
- WA templates — line ~7959 and ~9514.

Work through all parts in order without stopping for approval. Every judgement
call is pre-decided below. Commit each part separately, live-test in Chrome as
you go, hold `flutter analyze` at its 152 baseline, push at the end.

**Priority if time runs short: 1, 5, 2, 4, 3, 6.** Parts 3 and 6 are the largest
and may not finish today — that is expected and fine. Do not rush them to claim
completion; a truthful "built, not verified" is worth more than a false tick.

---

## PART 1 — refresh-after-write bug (highest priority)

After saving a record the change does not appear until the user navigates away
and back. Repro: record a cash collection → dashboard KPIs do not update.
Dashboard and list pages both affected.

Treat as systemic, not per-screen. Find the pattern — a write that doesn't
re-query, or doesn't `setState` — then audit EVERY write path: payments,
expenses, orders, leads, staff, salary, attendance, vehicles. Fix the pattern
once.

**Verify:** save a payment → payments list AND dashboard both update with no
navigation. Repeat for an expense and an order edit.

---

## PART 2 — dead settings + fleet gaps

**2a. Settings toggles do nothing.** Pre-decided, don't ask:

| Control | Action |
|---|---|
| dark mode | WIRE IT — theme system exists |
| notifications | WIRE IT — notifications table + Realtime already live |
| language | REMOVE from UI |
| export | REMOVE from UI |
| backup | REMOVE from UI (Supabase PITR is the real answer, not app code) |

A control that silently does nothing is worse than no control.

**2b. Theme switching** (Light/Dark/Midnight): verify and fix.
Brand: navy `#0F2A47`, gold `#E3B23C`, teal `#1FA98C`.

**2c. Fleet:** cannot open a truck from the list, cannot edit truck details,
cannot update insurance or permit expiry. Build the detail view and edit sheet.
Do NOT build expiry alert notifications — parked.

---

## PART 3 — port Survey & Quote from the React app

**3a. Survey item list with CFT.** Port `SURVEY_CATS` wholesale — all six
categories (Bedrooms, Living Room, Kitchen, Miscellaneous, Cartons & Packing,
and any others present), every item, every variant with its CFT. Each variant
gets a `+/-` counter. Running totals: item count and total CFT.

**3b. Package suggestion — INCLUDE IT after all.** `DEFAULT_CFT_RANGES` and
`DEFAULT_PACKAGES` are twenty lines and already written. Port them: total CFT →
suggested package, with crew count and vehicle size, shown as a summary card as
in the React app. (This reverses an earlier "out of scope" call — it is cheap
because the data already exists.)

**3c. Quotation charges** matching the React app exactly:
- Freight/Transport, Advance Paid
- Packing / Unpacking / Loading / Unloading / Packing Material — each with a
  billing-mode dropdown ("Incl. in Freight" vs a separate amount). See the
  `chargeTypes` state at line ~2671 for the exact semantics.
- Other Charges: Storage, Car Transport, Miscellaneous, S.T. Charge, Other
- Add-on Services: AC uninstall/install, TV uninstall/install, Wardrobe
  dismantle, Carpenter, Electrician, Bike transport
- Discount (present in the React charges object — don't drop it)

**3d. GST:** rate selector, auto-detect (IGST interstate / CGST+SGST intrastate),
show-in-PDF toggle, taxable value and split display. Mirror the React logic.
SAC 996719.

**3e. Orders page:** surface this same breakdown on order detail. Currently an
order shows a bare total with no itemisation. This is the single most-requested
gap from the phone test.

### MULTI-TENANCY — pre-decided, do not deviate

Do NOT hardcode CFT values, package rules, or charge defaults. Seed APC's values
as a default set, stored **per-org** so another vendor can override later. Check
whether the existing `pricing_config` table (has `org_id`) fits before creating
anything new; prefer extending it over adding a table.

The seed must be idempotent and must not overwrite a vendor's own edits on
re-run.

---

## PART 4 — smaller gaps

**4a. Expense page:** filters for month / week / order-wise.

**4b. Leads:** add "Generate Survey Link" on the lead card and detail page —
creates a `surveys` row for that lead and returns the shareable token link. The
backend RPCs already exist and are live-tested (`get_survey_by_token`,
`submit_survey`). This is only the missing entry point. Note `surveys.lead_id`
is **uuid**.

**4c.** `quotation_page_widget.dart`'s ad-hoc quote form has the same
`quotations.id` / `quotations.token` insert gap fixed elsewhere, and was never
live-tested. Fix and live-test.

---

## PART 5 — navigation touch targets and responsive layout

Reported from a real phone: bottom nav icons are too small to tap reliably.

**5a. Mobile bottom nav — fix sizing, do NOT move it to the side.** Bottom
placement is correct for thumb reach; the problem is target size.
- every destination min **48×48dp** tappable (Material minimum)
- icons 26–28px with padding, bar height ~64dp
- labels ALWAYS visible under icons, not only when selected
- active state visible at arm's length: filled icon + gold `#E3B23C` indicator,
  not a subtle colour shift alone
- respects the staff permission matrix exactly as now

**5b. Scroll-aware bottom nav:** hide on scroll down, reveal on scroll up.
**NO idle timer, NO auto-hide** — nav must never vanish while the user is
stationary.

**5c. Tablet (~600–1024dp):** collapsible left rail instead of bottom nav. 72dp
icons-only collapsed, ~240dp expanded with labels, deliberate tap to toggle,
choice persisted. Same 48dp minimums.

**5d. Desktop (>1024dp):** existing sidebar unchanged.

**5e. Audit tap targets app-wide,** not just nav: the survey CFT `+/-` counters
(there will be ~50 of them — this matters), quick-action rows on list cards,
icon-only buttons anywhere. Anything under 48dp gets padded out.

**Live-test at 390px, 820px and 1440px** in Chrome devtools; confirm nothing
overlaps or clips at the breakpoints.

---

## PART 6 — modules present in the React app, thin or absent in Nagarva

Only start this after 1–5 are done and committed. If time runs out, report as
not started.

**6a. Materials / packing inventory.** React app has a full page (line ~7709):
stock levels, min-stock low-stock warning, cost per unit, total inventory value,
and a quick-use widget inside the order expenses tab (line ~3996) that decrements
stock and books the cost against the order. Nagarva already has a `materials`
table with `org_id`. Port the page and the quick-use widget.

**6b. WhatsApp templates.** The React app stores these in localStorage with a
cloud-sync bolt-on (lines ~7959, ~9514). **Do not port that shape.** Nagarva
should use a per-org `wa_templates` table as specified in
`COMPETITOR_UX_SPEC.md` (id, org_id, code, category, body, enabled, updated_at),
with variable substitution. Provider selection (direct `wa.me` deep link vs
AiSensy API) is plan-gated — direct on all plans, API on Pro.

**6c. Report, don't build:** list anything else substantial in the React app
that Nagarva lacks, with a one-line note on effort. Do not start those.

---

## SQL — the one place you stop

Write any schema change to a migration file in `supabase/` and **CONTINUE
working**. Never execute DDL. At the end, list every migration I need to run, in
order, in one block.

If a feature cannot be live-tested until I run a migration: build it, say so
explicitly, and move on. Do not sit waiting, and do not mark it verified.

---

## CONSTRAINTS

- Flutter pinned **3.35.5**. Never `flutter upgrade` / `pub upgrade`. The "68
  packages have newer versions" notice is expected — ignore it.
- `quotations.id` and `quotations.token` have **NO db default**. Generate
  client-side on every insert. This bug has appeared twice already.
- `OrgScope` convention throughout. `super_admin_page_widget.dart` is the only
  documented cross-tenant exception.
- **DROP before CREATE OR REPLACE** when a function's return type or a view's
  column type changes (see CLAUDE.md). This has caused two failures.
- The React app is single-tenant APC. Everything ported must be org-scoped from
  birth — never copy a query that assumes one org.
- Update `NAGARVA_STATUS.md`. Mark verified ONLY if live-tested in a browser.
  Anything built but untested must say **built-not-verified**.

## NOT IN SCOPE

Razorpay/billing. Vehicle document expiry alerts. An "operations page issue" I
have not described yet. Anything in `COMPETITOR_UX_SPEC.md` beyond 6b.
