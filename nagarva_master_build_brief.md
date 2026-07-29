# Nagarva — Live APK Test Fix Brief #2 (28 Jul 2026)

Source: live phone testing of Lead Details screen (lead "abi", Chennai → Bengaluru, House Shifting). Reference UX for status flow: APC React app lead screen. Five items below, ordered by severity.

---

# Nagarva — Master Build Brief (28–29 Jul 2026)

Nagarva is a **pan-India multi-tenant ERP for packers and movers**, not a lead tracker. This document is the single source of truth for outstanding scope. Items 1–11 came from the live APK phone test; 12–21 from the follow-on review; 22–30 are ERP/compliance scope required for pan-India operation.

## Master index

| # | Item | Status |
|---|---|---|
| 1 | Survey link crash (`Uri.base` on APK) | **Built** |
| 2 | Detailed quote → order merge | Not started |
| 3 | Customer signature on quote/invoice | Partial — public page built, in-app actions + PDF block pending |
| 4 | Lead Details alignment | Not started |
| 5 | Lead/order status flow | Not started |
| 6 | Customer order tracking link | Partial — public page built, in-app actions + `status_history` writes pending |
| 7 | Multi-language (tiered Indian languages) | Not started |
| 8 | Dashboard blank slot when icon hidden | Not started |
| 9 | Theme not applied to drawer + search | Not started |
| 10 | Follow-ups, reminders & call log | **Built** — device testing pending |
| 11 | Delete / archive app-wide | **Built** — device testing pending; payment-entry delete outstanding |
| 12 | Per-tenant CFT catalogue + vehicle/crew slabs | Not started |
| 13 | Public per-vendor enquiry link | Not started |
| 14 | Condition photos at loading | Not started |
| 15 | Proof of delivery | Not started |
| 16 | Self-signup and trial onboarding | Not started |
| 17 | Data export | Not started |
| 18 | Offline mode for surveys | Not started |
| 19 | Payment collection link (UPI) | Not started |
| 20 | Error monitoring (Sentry) | Not started |
| 21 | Privacy policy + terms | Not started — **blocks Play Store + WhatsApp API** |
| 22 | LR / consignment note (bilty) | Not started — **legally required** |
| 23 | E-way bill support | Not started — **legally required >₹50k** |
| 24 | Corporate / B2B client accounts | Not started |
| 25 | Vehicle compliance & maintenance | Not started |
| 26 | Transit insurance | Not started |
| 27 | Warehousing / storage billing | Not started |
| 28 | Branch transfers & inter-branch settlement | Not started |
| 29 | Reports pack | Not started |
| 30 | Roles & permissions matrix | Not started |

**Also carried over from `nagarva_parity_brief.md`** (verify each is closed before calling parity done): systemic refresh-after-write bug, settings wiring, fleet CRUD, expense filters, navigation touch targets, materials inventory, WhatsApp templates, Part 7 login screen port.

---

## Item 1 — Survey link generation crashes (BLOCKER)

**Observed error (toast):**
```
Could not create survey link: Bad state: Origin is only applicable schemes http and https: file:///
```

**Root cause:** The link builder is using `Uri.base.origin` (or equivalent) to construct the public survey URL. On Flutter **web** `Uri.base` is the page URL, so `.origin` works. On a **mobile APK** `Uri.base` is `file:///`, and calling `.origin` on a non-http(s) scheme throws exactly this `Bad state` error. This code path was almost certainly written/tested on web and never on device.

**Fix:**
1. Grep the codebase for `Uri.base` — every usage is suspect on mobile.
2. Introduce a single source of truth for the public web base URL, e.g. in `lib/config/app_config.dart`:
   ```dart
   /// Public web origin used for customer-facing links (survey, quote sign, invoice).
   /// Never derive this from Uri.base — it is file:/// inside the APK.
   const String kPublicBaseUrl = 'https://nagarva.in';
   ```
   If customer links are served from a different host (e.g. an app subdomain), use that instead — confirm with Boss before hardcoding.
3. Build survey links as `'$kPublicBaseUrl/s/<survey_token>'` (keep the existing route/token scheme, just swap the origin source).
4. Optional hardening: if per-tenant custom domains are ever planned, read base URL from org settings with `kPublicBaseUrl` as fallback.

**Acceptance:** On a physical device APK, tapping "Send survey link" generates a valid `https://` link, opens the WhatsApp share flow, and the link opens the customer survey page in a mobile browser.

---

## Item 2 — "Build Detailed Quote" data not carried into "Convert to Order"

**Observed:** After filling the detailed quote (CFT item lines, charges, GST etc.), tapping **Convert to Order** creates an order that does not contain the quote data — items, amounts, and charge lines are lost or blank.

**Fix:**
1. Trace the Convert to Order handler. It must:
   - Look up the **latest quote** for the lead (detailed quote takes precedence over simple quote if both exist).
   - Copy across: quote total → order `quote_amount` / value; item lines (name, qty, CFT, rate); charge lines with billing modes; GST mode (IGST vs CGST+SGST) and GST amount; packing type; from/to/floors; approx date → order date (editable).
   - Link the order back to the quote (`orders.quote_id` or equivalent) so the invoice can later be generated from the same line items.
2. If the schema lacks columns/tables for order item lines, propose the migration SQL for Boss to run in Supabase (remember: `orders.id` is TEXT NGV-XXXX — any FK/join needs `::text` casts; RLS policies use `in (select current_org_ids())`).
3. Refresh-after-write: after conversion, the order detail screen must show the merged data immediately without app restart (this is the known systemic refresh bug — apply the standard invalidate/refetch pattern here too).

**Acceptance:** Build a detailed quote with ≥3 item lines + 2 charges + GST, convert to order, open the order → all lines, totals, and GST are present and match the quote exactly.

---

## Item 3 — Customer signature on quote and invoice (public sign link)

**Requirement:** Customer must be able to **sign** the quote and the invoice remotely. Generate a shareable link (WhatsApp-first) that opens a public page where the customer views the document and signs.

**Design:**
1. **Schema (propose SQL for Boss):**
   - `document_signatures` table: `id uuid pk`, `org_id`, `document_type` ('quote' | 'invoice'), `document_id text`, `sign_token text unique`, `customer_name`, `signature_data text` (base64 PNG from signature pad), `signed_at timestamptz`, `signer_ip`, `status` ('pending' | 'signed'), `created_at`.
   - Public read/write must go through an **Edge Function** (like the staff PIN auth pattern) keyed by `sign_token` — do NOT open RLS to anon on the main tables.
2. **Public sign page** (Flutter web route, e.g. `/sign/<token>`):
   - Shows the rendered quote/invoice (read-only), a signature pad (`signature` pub package or HTML canvas), name confirmation field, and a "Sign & Accept" button.
   - On submit: Edge Function validates token, stores signature, sets status = signed, timestamps it.
3. **In-app:**
   - Quote and invoice screens get a "Send for Signature" action → creates token, builds link with `kPublicBaseUrl` (Item 1's constant), opens WhatsApp share with a template message.
   - Lead/order detail shows signature status chip: *Awaiting signature* → *Signed on <date>*.
   - Signed signature image embeds into the quote/invoice PDF ("Accepted by <name>, <date>" + signature image above the line).

**Acceptance:** Send sign link via WhatsApp from the APK, sign on another phone's browser, status flips to Signed in-app (with refresh working), and the regenerated invoice PDF shows the signature block.

---

## Item 4 — Alignment of items on Lead Details

**Observed:** Field rows on Lead Details are not consistently aligned (label left / value right spacing is uneven, long values wrap awkwardly, Survey & Quote status pills and buttons have inconsistent widths/padding).

**Fix:**
1. Extract a shared `DetailRow` widget: label (fixed style, left) + value (right-aligned, `Flexible` with ellipsis/wrap rules) with consistent vertical padding — use it across Contact, Move Details, Notes cards.
2. Normalize the Survey & Quote section: status pills full-width or consistent intrinsic width, equal spacing between "Create Quote" / "Build Detailed Quote" buttons, consistent touch targets (min 48dp — same rule as the parity brief's navigation item).
3. Empty states: "Notes / Notes" double label looks like a bug — show "No notes yet" placeholder when empty; hide empty Email row or show "—".
4. Do a one-pass sweep of the same row pattern on Order Details and Quote screens so alignment is uniform app-wide.

**Acceptance:** Screenshot comparison — labels and values on one vertical grid, no orphan/duplicate labels, buttons evenly sized.

---

## Item 5 — Lead/order status flow (match APC pattern)

**Reference:** APC app lead screen has a tappable status pipeline: **New Lead → Follow Up → Survey Done → Quoted → Confirmed → Lost**, plus a top progress strip (New / Follow Up / Survey / Quoted / Order) showing where the lead sits.

**Current Nagarva:** only a static "new" badge; status doesn't advance visibly as survey/quote actions happen.

**Fix:**
1. Define the canonical lead status enum in one place: `new → follow_up → survey_done → quoted → confirmed` (+ terminal `lost`). Confirm against existing `leads.status` values in Supabase; migrate/backfill if names differ.
2. **Auto-transitions:** sending survey → at least `follow_up`; survey submitted → `survey_done`; quote created/sent → `quoted`; Convert to Order → `confirmed`. Never auto-downgrade.
3. **Manual override:** tappable status chips on Lead Details (like APC) for manual stage set, with `lost` requiring a confirm dialog + optional reason.
4. **Progress strip** at top of Lead Details showing the pipeline with the current stage highlighted (visual parity with APC's New/Follow Up/Survey/Quoted/Order strip).
5. Leads list: filter/group by status; status chip colored per stage.
6. Status changes write immediately and reflect without restart (refresh-after-write pattern again).

**Acceptance:** Walk a lead end-to-end on device: create → send survey → customer submits → quote → convert to order; the status strip advances at each step automatically, and manual chip taps also work.

---

## Item 6 — Customer order tracking (public link)

**Requirement:** Customer can track their move status via a shareable link — same public-link pattern as the survey (Item 1) and signature (Item 3) links.

**Design:**
1. **Token:** add `tracking_token text unique` to `orders` (or a small `order_tracking_tokens` table) — propose SQL for Boss.
2. **Public tracking page** at `/track/<token>` (Flutter web):
   - Order ref (NGV-XXXX), from → to, move date.
   - Status timeline: **Confirmed → Packing → In Transit → Arrived → Delivered → Completed** with current stage highlighted, timestamps per stage.
   - Assigned vehicle + driver name/phone (only if org enables it in settings).
   - No customer login required; token is the auth. Reads go through an Edge Function keyed by token — no anon RLS on `orders`.
3. **In-app:**
   - Order status updates (staff-side) drive the timeline — reuse/extend the order status enum; each status change writes a `status_history` row (`order_id text`, `status`, `changed_at`, `changed_by`).
   - "Share Tracking Link" action on Order Details → WhatsApp template with the link (built from `kPublicBaseUrl`).
4. Later hook: this same status history feeds WhatsApp auto-notifications per stage (template already exists in WhatsApp templates module — wire when ready).

**Acceptance:** Share tracking link from APK, open on another phone → live status timeline; staff updates order status → customer page reflects it on refresh.

---

## Item 7 — Multi-language support (Indian languages, tiered)

**Requirement:** App UI and customer-facing public pages (survey, sign, tracking) available in multiple Indian languages.

**Language set:**
- **Tier 1 (launch):** English (en), Tamil (ta), Hindi (hi), Kannada (kn) — covers Chennai, Bengaluru, and North-India customers.
- **Tier 2 (fast follow):** Telugu (te), Malayalam (ml), Marathi (mr) — completes South + West coverage for pan-India moves.
- **Tier 3 (on demand):** Gujarati (gu), Bengali (bn) — add when a tenant/market needs them; the ARB structure makes each new language a translation-only task, no code changes.

**Implementation:**
1. Standard Flutter localization: `flutter_localizations` + `intl` with one `.arb` file per language (`app_en.arb`, `app_ta.arb`, `app_hi.arb`, `app_kn.arb`, …); enable `flutter gen-l10n`. Structure all Tier 1–3 locales up front even if Tier 2/3 files start as English copies — adding a language later is then purely filling in translations.
2. **Scope for v1:** all visible UI strings on the main flows — login, dashboard, leads, survey/quote, orders, payments, expenses, settings. Extract hardcoded strings to ARB keys as encountered; don't block on 100% coverage — untranslated keys fall back to English.
3. **Language picker:** in Settings (per-user preference, stored locally + optionally in profile); also honor device locale on first launch.
4. **Customer pages:** language selector (or `?lang=ta` param baked into the shared link based on org/lead preference).
5. **Translation source:** generate first-pass machine translations for all Tier 1 languages, then give Boss a review sheet (key, EN, TA, HI, KN columns) as an xlsx — Boss reviews Tamil directly; Hindi/Kannada can be spot-checked by branch staff or IPAMTOA friends before Tier 2 effort is spent. Industry terms (bilty, CFT, packing, LR) stay in English across all languages.
6. Watch for layout breakage: Tamil strings run long — the `DetailRow`/button widgets from Item 4 must handle overflow gracefully.

**Acceptance:** Switch language in Settings → whole app flips instantly without restart; survey link opened with `?lang=ta` renders Tamil.

---

## Item 8 — Dashboard blank space when icon hidden (layout not reflowing)

**Observed:** When a dashboard icon/tile is hidden (permission-gated or toggled off), its slot stays blank — the grid keeps the empty cell instead of reflowing, and the content area doesn't extend into that space.

**Root cause (likely):** The dashboard grid renders a fixed list of children where hidden items are replaced with an empty `SizedBox`/`Container` or `Visibility(visible:false, maintainState/maintainSize: true)` instead of being removed from the children list.

**Fix:**
1. Build the tile list by **filtering first, then rendering**: `items.where((i) => i.visible).toList()` fed into `GridView`/`Wrap` — never render placeholder widgets for hidden tiles.
2. If `Visibility` is used, drop `maintainSize`/`maintainState` or replace with a plain conditional.
3. Verify the grid itself sizes to content (`shrinkWrap` / proper `Expanded` in the column) so remaining tiles reflow and fill the row.
4. Regression check: hide/show tiles via settings and via role permissions — no gaps in either path, on both small and large screens.

**Acceptance:** Hide any dashboard icon → remaining icons reflow with no blank slot; layout fills the full width.

---

## Item 9 — Theme not applied: left sidebar (drawer) + search button

**Observed:**
- Left sidebar/drawer keeps its own colors and ignores the active theme (dark/light or brand theme switch).
- Search button/bar color also doesn't change with theme.

**Root cause (likely):** Hardcoded `Color(...)`/`Colors.*` values inside the drawer and search widgets instead of reading from `Theme.of(context)` — so the theme switch updates the rest of the app but not these.

**Fix:**
1. Audit `Drawer`, drawer header, list tiles, and the search field/button for hardcoded colors; replace with `ColorScheme` tokens (`surface`, `onSurface`, `primary`, `surfaceContainerHighest` etc.).
2. Define drawer + search styling **once** in the app `ThemeData` (`drawerTheme`, `searchBarTheme` / `inputDecorationTheme`, `iconTheme`) so both modes derive automatically.
3. Sweep for the same pattern elsewhere — anywhere `Colors.` or raw hex appears outside the theme file is a candidate. Brand navy/gold/teal palette should live only in the `ThemeData` definitions.
4. Verify state propagation: theme change must rebuild the drawer even if it's kept alive (if the drawer is built outside the `MaterialApp` theme scope, fix the widget tree).

**Acceptance:** Toggle theme → drawer background, text, icons, and the search button/bar all switch correctly with no stale colors, including while the drawer is open.

---

## Item 10 — Follow-ups, reminders & call log on leads and quotes (BUSINESS-CRITICAL)

**Gap:** Nagarva's Lead Details has no reminder or follow-up capability at all. This is mandatory for the business — leads are won or lost on repeated follow-up, and a quote sitting without chase is dead revenue. APC already has the right pattern and Nagarva must reach parity or better.

**Reference (APC lead screen):** a REMINDERS section with `+ Add`, each reminder showing title ("Quote follow-up: <customer>"), due date, a note line ("Followup by 3pm today"), and per-reminder `+ Log Call` and `Done` actions, plus a collapsible "Show all N calls" history.

**Requirements:**

1. **Multiple follow-ups per lead AND per quote.** Not one "next follow-up date" field — a full list. A lead can have several open reminders (call back, site visit, price negotiation) simultaneously.

2. **Schema (propose SQL for Boss):**
   - `reminders`: `id uuid pk`, `org_id`, `entity_type` ('lead' | 'quote' | 'order'), `entity_id text` (TEXT to accommodate `orders.id` NGV-XXXX — cast with `::text` on joins), `title`, `note`, `due_at timestamptz`, `status` ('open' | 'done' | 'cancelled'), `completed_at`, `assigned_to` (staff id, nullable — defaults to creator), `created_by`, `created_at`.
   - `follow_up_logs`: `id uuid pk`, `org_id`, `entity_type`, `entity_id text`, `reminder_id uuid null` (set when logged against a specific reminder), `channel` ('call' | 'whatsapp' | 'sms' | 'email' | 'visit' | 'other'), `outcome` ('connected' | 'no_answer' | 'busy' | 'callback_requested' | 'not_interested' | 'converted'), `notes text`, `next_action_at timestamptz null`, `logged_by`, `logged_at`.
   - RLS on both: `org_id in (select current_org_ids())`.
   - Indexes on `(org_id, entity_type, entity_id)` and `(org_id, status, due_at)` — the second drives the due-today list.

3. **Lead Details UI (new section, above Survey & Quote):**
   - REMINDERS header with `+ Add` button → dialog: title, due date+time picker, note, assign to staff.
   - Each open reminder row: title, due date (red if overdue, amber if today), note line, with `Log Call` and `Done` actions.
   - `Log Call` opens a quick sheet: channel, outcome, notes, and an optional "set next follow-up" date — if set, it **auto-creates the next reminder** in the same action. This is the key loop: never leave a lead without a next step.
   - Collapsible "Show all N follow-ups" → chronological log history with who/when/outcome.
   - Completed reminders collapse out of the main view but stay in history.

4. **Quotation screen:** same reminders + log widget, scoped to the quote. When a quote is sent, **auto-create a follow-up reminder** (default +2 days, configurable in Settings) titled "Quote follow-up: <customer name>" — matching APC's behaviour. Same for survey sent (default +1 day).

5. **Surfacing (this is where the value is — reminders nobody sees are useless):**
   - Dashboard tile/section: **Today's Follow-ups** and **Overdue** counts, tapping through to a filtered list.
   - Leads list: badge/icon on rows with overdue follow-ups; sort/filter by "needs follow-up".
   - Optional local notification at due time (device-level, no server push needed for v1).

6. **WhatsApp tie-in:** `Log Call` sheet includes a WhatsApp quick-action that opens the existing template flow and auto-logs a `whatsapp` channel entry on return.

7. Refresh-after-write applies — adding/completing a reminder must reflect immediately (systemic bug).

**Acceptance:** On device — add two reminders to a lead, log a call against one with outcome "callback_requested" and a next date, confirm the next reminder auto-creates; send a quote and confirm the follow-up reminder auto-appears; dashboard shows correct today/overdue counts; history shows all logged calls with timestamps and staff names.

---

## Item 11 — Delete / archive is missing app-wide (leads, quotes, orders, staff, everything)

**Gap:** There is no delete function anywhere in Nagarva. Test rows, duplicate leads, wrong entries, and departed staff all accumulate with no way to remove them. APC has `Delete Lead` on the lead screen; Nagarva has nothing.

**Core principle — soft delete, not hard delete.** Every entity gets `deleted_at timestamptz`, `deleted_by uuid`, `delete_reason text`. Deleted rows disappear from all lists and lookups but stay in the database. Reasons: (a) accidental deletes are recoverable, (b) financial and GST records must be retained by law, (c) a hard delete would cascade and silently destroy linked payments, salary ledger entries, and P&L history. Hard delete is reserved for the super-admin console only.

**Rules per entity:**

| Entity | Delete allowed? | Behaviour |
|---|---|---|
| Lead | Yes | Soft delete. Blocked if already converted to an order — offer "mark as Lost" instead. |
| Quote | Yes | Soft delete. Blocked if the quote is signed (Item 3) or already converted — supersede with a new version instead. |
| Order | **Restricted** | Soft delete (owner-only) **only if** no payments recorded and no GST invoice issued. If either exists → block, and offer **Cancel Order** (status change, keeps the audit trail). Never delete an invoiced order — GST records must be retained. |
| Payment entry | Owner-only | Soft delete with mandatory reason; must reverse the linked ledger/P&L effect, not just hide the row. |
| Staff | Yes | **Deactivate, don't delete** (`active = false`) — salary ledger, attendance, and job history all reference the staff row. Hard delete only if the staff member has zero linked records. Deactivating must also invalidate their PIN login. |
| Expense / Material / Fleet | Yes | Soft delete, owner or manager. |

**Implementation:**

1. **Schema (propose SQL for Boss):** add `deleted_at`, `deleted_by`, `delete_reason` to `leads`, `quotes`, `orders`, `payments`, `expenses`, `materials`, `fleet`. Add partial indexes `where deleted_at is null` on the hot list queries.
2. **RLS / read filtering:** update every RLS policy and every list query to append `and deleted_at is null`. This is the highest-risk part — a missed spot means deleted rows reappear somewhere. Grep systematically for each table's read paths.
3. **Guard functions:** a DB-side check (or Edge Function) that validates the rules table above before allowing the update — don't rely on the UI alone. E.g. `can_delete_order(order_id)` returns false when payments or an invoice exist.
4. **UI:**
   - `Delete` action in the overflow/bottom of each detail screen — destructive styling (red), never adjacent to a primary action.
   - Confirmation dialog stating what will happen ("This lead will be removed from your list. It can be restored by the owner.") with a **mandatory reason** field for orders and payments.
   - Blocked cases explain *why* and offer the alternative (Lost / Cancel Order / Deactivate).
   - Undo snackbar for ~10 seconds after a lead or quote delete — cheapest way to prevent most support requests.
5. **Permissions:** leads/quotes deletable by owner + manager; orders, payments, staff by **owner only**. Wire into the existing role gating (`AppSession.currentStaffId == null` for owner, per Part 7 login).
6. **Recycle bin (Settings → Deleted Items):** owner-only list of soft-deleted records from the last 90 days with a Restore action. Small screen, big payoff — turns every accidental delete into a non-event.
7. **Audit:** every delete writes to an `audit_log` (entity, id, action, actor, reason, timestamp) if one exists; if not, propose the table.
8. Refresh-after-write applies — the row must vanish from the list immediately.

**Acceptance:** Delete a lead → gone from list, restorable from recycle bin. Try to delete an order with a payment → blocked with Cancel Order offered. Try to delete an invoiced order → blocked. Deactivate a staff member → their PIN no longer logs in, salary history intact. No deleted record appears in any list, KPI, dashboard count, or P&L figure.

---

## Item 12 — Per-tenant CFT catalogue + vehicle/crew slab configuration

**Gap:** Both the CFT item catalogue (Single Bed 30, Double 45, …) and the CFT→package/vehicle/crew slabs live in `_config` and are effectively hardcoded. Nagarva is multi-tenant: every packer has a different fleet, different crew norms, and different names for the same items. A Bengaluru vendor with 14ft trucks and a Coimbatore vendor running tempos cannot share one table. As it stands the product only fits businesses shaped exactly like APC.

**First, for Claude Code to answer before building:** where do the CFT catalogue and the slab thresholds currently live, are they per-org or global, and is there any existing UI touching them? Build on what's there rather than adding a parallel config.

### 12A — Editable CFT item catalogue (per tenant)

**Schema:** `survey_catalogue_items` — `id uuid`, `org_id`, `category text` (Kitchen, Bedrooms, …), `name text` (e.g. "Double Bed"), `cft numeric`, `sort_order int`, `active boolean`, plus soft-delete columns per Item 11.

- **Settings → Survey & Pricing → Item Catalogue:** grouped by category, inline edit of name and CFT, reorder, add/remove items, add/rename categories.
- **Seed on tenant creation** from the current `_config` defaults, so a new signup gets a working catalogue immediately rather than an empty screen.
- **Critical interaction with the Item-A CFT fix:** quote lines store their CFT at add-time, so editing a catalogue value must **never** retroactively change an existing quote. Confirm this holds after the change — it is the whole reason for that fix.
- Deactivating an item hides it from new surveys but leaves old quotes intact.

### 12B — Editable vehicle/crew slabs (per tenant)

**Schema:** `cft_slabs` — `id uuid`, `org_id`, `cft_from numeric`, `cft_to numeric`, `package_name text`, `vehicle_label text`, `crew_count int`, `sort_order int`, soft-delete columns.

Default seed (edit freely per tenant):

| From CFT | To CFT | Package | Vehicle | Crew |
|---|---|---|---|---|
| 0 | 100 | Micro Shifting | 7 Ft | 2 |
| 101 | 250 | Mini | 10 Ft | 3 |
| 251 | 450 | Standard | 14 Ft | 4 |

- **Settings → Survey & Pricing → Vehicle & Crew Slabs:** editable table, add/remove rows.
- **Validation on save:** ranges must not overlap and must not leave gaps. An unmatched CFT silently producing no suggestion is the same class of bug as the 0-CFT one — fail loudly at config time, not quietly at quote time.
- Vendors define their own vehicle labels (some run 17ft/20ft, some use tonnage) — free text, not an enum.

### 12C — Suggestion, not a hard rule

The slab result stays a **suggestion the surveyor can override per quote**. The survey screen shows "Suggested: Standard · 4 crew · 14 Ft" with an edit affordance; the chosen package, vehicle, and crew count are stored **on the quote/order**, not re-derived at render. Two reasons: real jobs have narrow staircases, long carries, and fragile loads that no CFT table predicts; and re-deriving would let a later slab edit silently rewrite a dispatched job.

Where the surveyor overrides, keep the suggested value alongside the chosen one — over time that difference tells the vendor their slabs need adjusting.

**Acceptance:** Edit a catalogue item's CFT → new surveys use the new value, existing quotes unchanged. Add a slab row overlapping an existing one → blocked with a clear message. Override the suggested crew on a quote → the override persists to the order and survives a later slab edit.

---

## Item 13 — Public per-vendor survey link (lead capture channel)

**What this is, and how it differs from Item 1.** Item 1's survey link is a **per-lead token**: the office creates a lead, generates a link, sends it to that one customer, and the link already knows who they are. Item 13 is a **permanent per-vendor link** — `nagarva.in/s/arunpackers` — that anyone can open. The customer fills in their own details and items, and a new lead is created in the vendor's account.

This turns Nagarva's survey tool into a lead-capture channel. Vendors can put the link on WhatsApp status, their website, Google Business profile, or a visiting card. Commercially this may be the strongest early-adoption pitch to IPAMTOA members — it brings them *new* leads rather than only organising leads they already have.

### 13A — The link and the public form

- Route `/s/<org_slug>` (distinct from the per-lead `/s/<token>` path — namespace them clearly, e.g. `/enquiry/<slug>` vs `/survey/<token>`, so they can't collide).
- `resolve_org_by_slug()` already exists from the Part 7 login work — reuse it rather than adding a second lookup.
- Page shows vendor branding (org name, logo, phone) then the survey form: name, phone, from/to city and address, floors, approximate date, service type, and the CFT item picker from the existing survey flow (using that org's catalogue once Item 12A lands).
- On submit, the customer sees their own summary — item count, total CFT, and optionally the suggested package — plus a "we'll call you shortly" confirmation.

### 13B — Anti-spam, which is the whole design problem

A public form with no gate will collect junk, and junk in the leads list destroys trust in the product faster than a missing feature does.

1. **Phone OTP before submit.** OTP infrastructure already exists for supervisor job completion — reuse it. An unverified phone never creates a row.
2. **Rate limit per IP and per phone** (e.g. 3 submissions/hour/IP), tracked the same way `org_pin_attempts` handles login lockout.
3. **Land in a holding state, not the leads list.** Submissions arrive as `source = 'web_enquiry'` with `status = 'new_enquiry'`, shown in a separate **Web Enquiries** inbox. A staff member accepts (→ becomes a real lead) or rejects (→ dismissed, no clutter). Never let an anonymous form write straight into the working leads pipeline.
4. **Duplicate handling:** same phone within a configurable window (default 30 days) attaches to the existing lead as a new follow-up log entry rather than creating a second lead.
5. Honeypot field + minimum time-on-form to defeat naive bots.

### 13C — Vendor controls (Settings → Public Enquiry Link)

- Enable/disable the public link entirely.
- Show the link with copy button and a QR code (printable for visiting cards and shop signage).
- Regenerate the slug if it gets abused or scraped.
- Choose which fields are required vs optional.
- Toggle whether the customer sees the suggested package/vehicle, or just a confirmation — some vendors will not want pricing hints exposed publicly.
- Optional auto-reply: WhatsApp template fires to the customer on submit ("Thanks, we've received your enquiry").

### 13D — Notifications

New enquiry triggers the existing notification path to the owner and any staff with lead permissions. A public link nobody checks is worse than no link — the whole value is speed of first response.

**Schema notes:** reuse `leads` with `source`/`status` values rather than a separate enquiries table, so accepting an enquiry is a status change rather than a row copy. Add `enquiry_slug`, `enquiry_enabled`, `enquiry_settings jsonb` to the org/settings table. All new columns respect Item 11's soft-delete pattern.

**Acceptance:** Open the vendor link on a phone with no app session, complete OTP, submit a survey with items → enquiry appears in the vendor's Web Enquiries inbox with correct CFT total, owner gets notified, accepting it creates a normal lead that flows through survey → quote → order. Submitting twice from the same number attaches rather than duplicating. Disabling the link in Settings makes the URL show a clean "not accepting enquiries" page.

---

## Item 14 — Condition photos at loading (damage protection)

**Why this matters most.** Every packers-and-movers dispute is some version of "that scratch was already there." Photographic evidence at pickup is the single feature most likely to save a vendor real money, and no competitor app in the Indian SMB segment does it well.

- **Capture:** on the order/job screen, a "Loading Photos" step — camera capture per room or per item line, with the item name attached where relevant. Multiple photos per entry, plus an optional note ("existing dent, left panel").
- **Timestamps and integrity:** store `captured_at` server-side, not from the device clock. Photos are immutable once uploaded — no replace, only add.
- **Storage:** Supabase Storage bucket per org, path `<org_id>/orders/<order_id>/loading/…`, with RLS so one tenant can never read another's. **Compress client-side before upload** (target ~200–400 KB) — surveyors are on mobile data and a 12MP original per item will destroy their quota and your storage bill.
- **Unloading counterpart:** same capture at delivery, so before/after sit side by side.
- **Customer visibility:** optionally surfaced on the tracking page (Item 6) — vendor toggle in Settings, since some will want it and some won't.
- **Offline:** queue locally and upload on reconnect (see Item 18) — loading bays frequently have no signal.

**Acceptance:** Capture 10 photos across 3 rooms on a job, go offline mid-capture, reconnect → all 10 upload with correct timestamps and attach to the right order.

---

## Item 15 — Proof of delivery (POD)

Item 3 covers signing quotes and invoices. Delivery is a separate moment and needs its own artifact.

- **At delivery completion:** customer signature (reuse the Item 3 signature pad), "received in good condition" confirmation with an option to note exceptions, unloading photos (Item 14), and delivery timestamp + location.
- **Damage claim path:** if the customer marks an exception, capture what and photograph it — this becomes the record if a claim follows.
- **POD document:** generates a PDF with order details, signature, timestamp, and photo thumbnails. Shareable to the customer by WhatsApp, and permanently attached to the order.
- **Ties to Item 5:** POD completion is what moves an order to Delivered/Completed, rather than a staff member setting it manually.
- Works with the existing supervisor OTP flow rather than replacing it — OTP proves the staff member was there, POD proves what the customer received.

**Acceptance:** Complete a delivery on device with signature and 3 photos, one exception noted → PDF generates with all elements, order status advances, customer receives it on WhatsApp.

---

## Item 16 — Self-signup and trial onboarding

**Gap:** tenants are currently created manually. Fine at 3 vendors, blocking at 30 — and manual provisioning means every IPAMTOA signup waits on Boss being at a laptop.

- **Public signup flow:** business name, owner name, phone, email, city → OTP verify → org created, slug auto-generated (editable), owner `org_members` row created with role `owner`, PIN set (per the Part 7 login model).
- **Wire up `assign_default_trial_plan`** — it exists but needs a signup path reaching it. Confirm trial length and what happens at expiry (read-only? grace period? Decide before launch, not after the first trial ends).
- **Seed the new tenant** with default CFT catalogue and slabs (Item 12), default WhatsApp templates, and a sample lead so the app isn't an empty shell on first open.
- **Guided first-run:** short checklist — add your branches, add staff, set your GST details, set your slabs. Vendors who see an empty dashboard churn immediately.
- **Super-admin console** (already built) gets visibility of new signups for approval or monitoring.

**Acceptance:** Sign up from a clean phone with no prior session → working tenant with seeded config, trial plan assigned, first-run checklist visible, and the org appears in the super-admin console.

---

## Item 17 — Data export

Vendors will ask "can I get my data out," and under India's DPDP Act you're obliged to answer yes. It's also the best answer to the "what if Nagarva shuts down" objection during a sales conversation.

- **Settings → Export Data:** owner-only. Exports leads, quotes, orders, payments, expenses, staff, and attendance as CSV (one file per entity) or a single XLSX workbook with a sheet each.
- Date-range filter; default to current financial year.
- **GST-relevant export** as a separate preset: invoices with SAC codes, GST split, and invoice numbers — formatted for handoff to a CA. This one gets used every quarter and is worth getting right.
- Generated server-side (Edge Function) for anything large, delivered as a download link rather than blocking the app.
- Excludes soft-deleted rows by default, with an option to include them for audit purposes.

**Acceptance:** Export a full financial year → workbook opens in Excel with correct sheets, figures reconcile against the in-app P&L, GST preset matches issued invoices.

---

## Item 18 — Offline mode for surveys

Surveyors work in basements, lifts, stairwells, and buildings with no signal. If the survey screen needs connectivity to save, entries get lost — and a lost survey is a lost quote.

- **Local-first for the survey/quote flow:** write to local storage (Drift/sqflite or Hive) first, sync to Supabase when connectivity returns. The surveyor should never see a spinner or an error mid-survey.
- **Sync queue** with visible status: a small indicator showing "3 items pending sync," and a manual retry.
- **Conflict rule:** last-write-wins is acceptable here — two people rarely survey the same flat simultaneously — but log conflicts rather than silently discarding.
- **Scope deliberately:** survey/quote capture and Item 14 photo capture only. Do **not** attempt offline for payments, invoicing, or anything financial — the reconciliation complexity is not worth it.
- Photos queue as files and upload on reconnect, compressed.

**Acceptance:** Enable airplane mode, complete a full survey with items and 5 photos, close the app, reopen, restore connectivity → everything syncs and appears server-side intact.

---

## Item 19 — Payment collection link (UPI / gateway)

Completes the set of customer-facing links alongside survey, signature, and tracking.

- **"Request Payment" action** on order/invoice → generates a link, sent by WhatsApp with the amount and order reference.
- **Start with UPI intent links** (`upi://pay?pa=…&am=…&tn=…`) — zero integration cost, no gateway fees, works with every Indian payment app, and vendors already have a UPI ID. This alone covers most of the need.
- **Optional gateway** (Razorpay/Cashfree) as a Phase 2 for card/netbanking and automatic reconciliation. Per-tenant credentials in Settings — each vendor uses their own account; Nagarva never holds funds.
- **Reconciliation:** UPI links can't auto-confirm, so the flow is: customer pays → staff confirms receipt in-app → payment entry created. With a gateway, the webhook creates the entry automatically.
- Partial payments supported (advance, balance), linked to the existing five-column money split.
- **Never auto-mark an order paid from a UPI link alone** — always require staff confirmation, or you'll get false "paid" states.

**Acceptance:** Send a payment request for a balance amount, pay via UPI on another phone, staff confirms → payment entry created, `paid_total` and `payment_status` update correctly.

---

## Item 20 — Error monitoring and crash reporting

**Gap:** bugs are currently found by testing on one phone. With 30 tenants, you need crashes reported to you rather than discovered through a WhatsApp complaint three days later.

- **Sentry** (Flutter SDK, free tier is sufficient at this scale) capturing crashes, unhandled exceptions, and failed Supabase calls.
- **Tag every event with `org_id`, screen name, and app version** — without tenant context a crash report is nearly useless for support.
- **Scrub PII before send:** no customer names, phone numbers, or addresses in event payloads. DPDP applies to error logs too.
- **Breadcrumbs** for the last few navigation and network events — turns "app crashed" into "app crashed after Convert to Order with a null quote."
- **Structured build versioning** (the APC app already does `v2026.07.05-D`) so a report names the exact build.
- **Optional:** in-app "Report a problem" that attaches recent logs — most vendors won't file a bug report, but the ones who do become your best testers.

**Acceptance:** Force a crash in a debug build → appears in Sentry within a minute with org_id, screen, version, and breadcrumbs, and no customer PII in the payload.

---

## Item 21 — Privacy policy page (compliance blocker, carried over)

Still outstanding from earlier sessions and **blocking three things**: Meta/WhatsApp Business API approval, Play Store submission, and DPDP Act compliance.

- Public page at `nagarva.in/privacy`, linked from the app footer and login screen.
- Must cover: what data is collected (vendor and end-customer), why, where it's stored (Supabase region), retention periods, third parties (Meta/WhatsApp, payment gateway, Sentry), user rights under DPDP, and a grievance contact.
- Add a terms-of-service page at the same time — Play Store asks for both.
- Note the soft-delete retention policy (Item 11) and the export right (Item 17) explicitly, since both are DPDP-relevant.

This is a text-and-a-page task, not an engineering one, but nothing ships to Play Store without it.

---

## Item 22 — LR / Consignment Note (Bilty) — LEGALLY REQUIRED

**Why:** Under the Carriage by Road Act 2007 and Rules 2011, a goods transport operator must issue a consignment note. It is also what a customer, an insurer, and a checkpoint officer all ask for. Nagarva cannot claim to serve pan-India movers without it. (Note the deliberate separation from the IPAMTOA Bilty app — this is Nagarva's own tenant-scoped LR.)

- **Schema:** `consignment_notes` — `lr_number text` (per-org sequential, configurable prefix/format like `APC/LR/2627/0001`), `order_id text`, consignor and consignee name/address/phone/GSTIN, from/to, goods description, package count, declared value, freight amount, freight payment mode (**Paid / To-Pay / Billed**), vehicle number, driver name and phone, `issued_at`, `e_way_bill_no`, soft-delete columns.
- **Numbering:** same "last issued" counter convention as your GST invoice series, per org, per financial year. Never reuse a number; never leave a gap.
- **Print/PDF:** multi-copy format (Consignor / Consignee / Transporter / Driver copy) with org letterhead and terms on the reverse.
- **Generated from the order** — no re-keying. Consignor defaults to the customer, consignee to the destination contact.
- Attach to the order and share by WhatsApp; visible on the tracking page (Item 6).

**Acceptance:** Generate an LR from an order → correct sequential number, all four copies render, PDF shares by WhatsApp, number is never duplicated across concurrent generation.

---

## Item 23 — E-way bill support — LEGALLY REQUIRED

**Why:** Movement of goods worth over ₹50,000 between states (and often within) requires an e-way bill. Interstate household moves routinely cross that threshold. Without support, vendors keep a parallel manual process and Nagarva stays a partial system.

- **Phase 1 (do first — low effort, high value):** capture and store the e-way bill number, validity date, and PDF against the order/LR. Alert when validity is close to expiry on an in-transit order. This alone covers most vendor need.
- **Phase 2:** direct **NIC e-way bill API** integration — generate from order data (GSTINs, HSN/SAC, distance, vehicle number), update vehicle number on transhipment, cancel/extend. Per-tenant NIC credentials in Settings; Nagarva never holds a shared credential.
- **Validation:** flag orders over the threshold that have no e-way bill recorded before dispatch — a blocking warning, dismissible with a reason (e.g. exempt goods).
- Store the transporter ID (GSTIN-linked) in org settings.

**Acceptance:** Record an e-way bill on an interstate order → appears on LR and tracking; an over-threshold order without one shows a dispatch warning.

---

## Item 24 — Corporate / B2B client accounts (credit customers)

**Why:** Corporate relocations, employee transfers, and repeat institutional clients are the profitable end of this business. They don't pay per-job in cash — they need credit terms and consolidated monthly billing. Nagarva currently assumes a one-off retail customer.

- **`customers` master table** (distinct from `leads`): name, type (`individual` | `corporate`), GSTIN, billing address, contact persons (multiple), credit limit, payment terms (Net 15/30/45), assigned rate card.
- **Link orders to a customer** rather than storing loose name/phone — this is also the foundation for repeat-customer history and CRM.
- **Consolidated invoicing:** select multiple completed orders for one corporate client in a period → single GST invoice with a line per job.
- **Statement of account:** all invoices, payments, and outstanding for a client, with ageing buckets (0–30 / 31–60 / 61–90 / 90+). This is the screen an owner uses to chase money.
- **Credit control:** warn when a new order would exceed the client's credit limit or when invoices are overdue.
- **Rate cards per corporate client:** negotiated per-CFT or per-route pricing that overrides the default slabs (Item 12).

**Acceptance:** Create a corporate client with Net 30 terms, run three orders, generate one consolidated invoice, view the ageing statement, and see a credit warning on a fourth order past the limit.

---

## Item 25 — Vehicle compliance and maintenance

**Why:** An expired FC or permit stops a truck at a checkpoint mid-move. Fleet-owning vendors need expiry tracking, and it's a feature they will immediately understand the value of.

- **Extend `vehicles`:** registration number, type, capacity (CFT and tonnage), ownership (`owned` | `attached` | `hired`), plus expiry dates for **insurance, fitness certificate (FC), permit, PUC, road tax, and national permit**.
- **Expiry alerts** at 30/15/7 days, surfaced on the dashboard and via notification. This is the whole point of the feature.
- **Document storage:** upload the RC, insurance, permit and FC PDFs against the vehicle.
- **Maintenance log:** service date, odometer, work done, cost, next-service-due — feeds into expenses and P&L.
- **Driver records:** licence number and expiry, licence class, contact, linked vehicle, plus police verification status (customers increasingly ask).
- **Attached/hired vehicle handling:** owner name, contact, and commission or hire rate, since most Indian movers run a mix of owned and market vehicles.

**Acceptance:** Add a vehicle with all expiry dates → alerts appear at 30/15/7 days on dashboard; maintenance entries post to expenses.

---

## Item 26 — Transit insurance

**Why:** Customers ask "is my goods insured" on nearly every interstate quote. Vendors either declare it manually or lose the job. It's also a margin line.

- **Per-order insurance:** declared goods value, premium rate (% configurable per org), computed premium, policy number, insurer name, coverage type (all-risk / basic transit).
- **Quote integration:** insurance appears as an optional charge line in the detailed quote (Item 2), so the customer sees and accepts it explicitly.
- **Claim tracking:** if damage is reported (linked to Items 14/15 photos), record claim number, amount claimed, status, and settlement — the photos become the evidence pack.
- **Document storage:** policy PDF attached to the order and shareable to the customer.

**Acceptance:** Add insurance to a quote at a configured rate → flows to order and invoice; a damage exception at POD can open a claim linked to the loading photos.

---

## Item 27 — Warehousing / storage billing

**Why:** Storage between move-out and move-in is common in Indian relocations and is billed differently from transport — per day or per month, per CFT or per unit area. Vendors currently handle it on paper.

- **Storage records:** order link, warehouse/branch location, goods description and CFT, check-in date, expected and actual check-out, rate basis (`per_day` | `per_month`), rate, computed charges.
- **Auto-accrual:** charges accumulate daily so an owner can see live storage revenue and what each customer owes without manual calculation.
- **Space tracking:** total capacity vs occupied per warehouse, so a vendor knows what they can accept.
- **Billing:** storage charges roll into the customer's invoice or statement (Item 24) as a separate line.
- Condition photos (Item 14) at check-in and check-out — same dispute-protection logic.

**Acceptance:** Check goods into storage, let time pass, see accrued charges match the rate basis, check out and bill correctly.

---

## Item 28 — Branch transfers and inter-branch settlement

**Why:** APC alone runs Chennai, Bengaluru, and Coimbatore. Pan-India vendors are multi-branch by definition, and a Chennai→Bengaluru job involves both branches. Without settlement logic, branch P&L is meaningless.

- **Job ownership vs execution:** an order records both the **originating branch** (who won the lead) and the **executing branch** (who did the work).
- **Revenue split rule** per org — configurable percentage or fixed origination commission — so both branches' P&L reflects reality.
- **Inter-branch ledger:** what Chennai owes Bengaluru and vice versa, with periodic settlement entries.
- **Branch-level P&L and dashboards** (`branch_kpis_view` already exists — extend it for the split rather than replacing it).
- **Materials/inventory transfers** between branches with in-transit state, tying into the existing materials module.

**Acceptance:** Create an order originated in Chennai and executed in Bengaluru → both branch P&Ls reflect the configured split, inter-branch ledger shows the balance.

---

## Item 29 — Reports pack

**Why:** An ERP is judged on what an owner can see without exporting to Excel. Nagarva has dashboard KPIs but no report layer.

Minimum set, all with date-range and branch filters, all exportable (Item 17):

- **Sales register** — orders by period, branch, service type, source.
- **Lead conversion funnel** — leads → surveys → quotes → orders, with conversion % and average time per stage, sliced by source and by staff. This is the report that tells a vendor which marketing actually works.
- **Outstanding / receivables ageing** — 0–30 / 31–60 / 61–90 / 90+, by customer.
- **GST summary** — output tax by month, IGST vs CGST+SGST split, ready for GSTR-1 reconciliation.
- **Staff performance** — jobs completed, revenue attributed, attendance, salary vs output.
- **Vehicle utilisation** — trips, km, fuel, revenue per vehicle, idle days.
- **Expense analysis** — by category, branch, and period, against revenue.
- **P&L** — monthly and financial-year, already partly built; formalise it as a report.

**Acceptance:** Each report renders with correct figures reconciling against source records, filters work, export produces matching data.

---

## Item 30 — Roles and permissions matrix

**Why:** Permissions are currently ad-hoc (owner vs staff, some per-screen gating). An ERP used by a 30-person business needs a defined matrix, and it's a common enterprise sales question.

- **Defined roles:** Owner, Branch Manager, Sales/Telecaller, Surveyor, Supervisor, Accounts, Driver. Per-tenant custom roles later if needed.
- **Permission matrix** per module (leads, quotes, orders, payments, expenses, staff, salary, reports, settings) × action (view, create, edit, delete, approve). Stored per org so vendors can adjust.
- **Data scoping:** branch-level restriction (a Chennai manager sees only Chennai) and own-records-only (a telecaller sees only their leads).
- **Sensitive gating:** salary figures, P&L, and customer contact export restricted by default — the most common vendor concern is staff walking off with the customer list.
- **Enforce server-side in RLS**, not only in the UI. Client-side gating alone is not a permission system.
- Ties into Item 11's delete rules and the Part 7 PIN login model.

**Acceptance:** Create a Branch Manager limited to one branch → cannot see other branches' orders or any salary data, via both UI and direct API call.

---

## Session command block — finish Items 3 + 6, plus custom-item CFT fix

Paste into Claude Code as one instruction. Boss runs the two `supabase functions deploy` commands himself.

### A. Custom-item CFT fix (do first — data correctness)

Currently `_totalCft` and `_save` resolve CFT by walking `_config.surveyCats`, so any custom item not in the catalogue silently counts as **0 CFT**, under-sizing the suggested package and vehicle. Fix structurally, not with a special case:

1. Store `cft` **on the item line itself** at add-time — catalogue items copy their CFT value in when added; custom items carry the CFT entered in the name+CFT dialog.
2. Change `_totalCft` and `_save` to **sum the stored per-line `cft`**, with no lookup against `_config.surveyCats` at total time.
3. Persist `cft` per line in the quote items table/JSON so historic quotes keep the numbers they were actually quoted at (catalogue CFT revisions must never retroactively change an old quote — matters for customer disputes).
4. Guard: block save if any line has `cft == 0` unless the user explicitly confirms, so a zero can never pass unnoticed.
5. Backfill note for Boss: existing quotes with custom items may hold 0 CFT — flag them rather than silently rewriting.

### B. Finish Item 3 (signatures) — in-app side

- "Send for Signature" action on the quote screen and invoice screen → creates `sign_token`, builds link from `kPublicBaseUrl`, opens WhatsApp share with template.
- Signature status chip on lead/order/quote detail: *Awaiting signature* → *Signed on <date>*.
- PDF signature block: embed the stored signature image + "Accepted by <name>, <date>" above the line on both quote and invoice PDFs.
- Apply refresh-after-write so status flips without restart.

### C. Finish Item 6 (tracking) — in-app side

- "Share Tracking Link" action on Order Details → token + WhatsApp share.
- `status_history` writes on **every** order status change (`order_id text`, `status`, `changed_at`, `changed_by`) — this is what drives the public timeline; without it `/track` shows a static page.
- Status chips on Order Details reflecting current stage.
- Keep the timeline as a **display-layer mapping** over the existing `booked/transit/delivered/...` vocabulary. Do **not** write finer-grained stage names into `orders.status` — that would make in-progress orders vanish from OrdersPage tabs (same trap SupervisorJobPage documents).

### D. Boss runs these before testing

```
supabase functions deploy sign-document
supabase functions deploy track-order
```

Then hot restart. Both public pages fail to load until these are deployed.

### E. Then Item 10 (follow-ups) + Item 11 (delete) — full specs in the sections above

These are the two largest gaps and both need SQL from Boss before the Flutter side lands. Sequence:

1. **Propose the migrations first, in one file**, for Boss to review and run:
   - `reminders` + `follow_up_logs` tables (Item 10), RLS `org_id in (select current_org_ids())`, indexes on `(org_id, entity_type, entity_id)` and `(org_id, status, due_at)`.
   - `deleted_at` / `deleted_by` / `delete_reason` columns across `leads`, `quotes`, `orders`, `payments`, `expenses`, `materials`, `fleet` (Item 11), plus partial indexes `where deleted_at is null`, and the `can_delete_order()` guard function.
   - `entity_id` must be **text** in both new tables — `orders.id` is TEXT (NGV-XXXX), so joins need `::text` casts.
   - Enable RLS explicitly in the migration file itself (`alter table ... enable row level security`) rather than relying on the Supabase UI prompt.
2. **Item 11's RLS/read sweep is the risky part** — add `and deleted_at is null` to every read path in the same pass: RLS policies, list queries, dashboard KPIs, P&L totals. Go table-by-table, not screen-by-screen. A deleted lead that vanishes from the list but still counts in dashboard numbers is worse than no delete at all.
3. Then build the Flutter side for both: REMINDERS section on Lead Details + quote screen with `+ Add` / `Log Call` / `Done` and the auto-chain (logging a call with a next date auto-creates the next reminder); delete actions with destructive styling, mandatory reason for orders/payments, blocked cases offering Lost / Cancel Order / Deactivate, undo snackbar, and the owner-only recycle bin in Settings.
4. Auto-create "Quote follow-up: <customer>" (+2 days) on quote sent, and a survey follow-up (+1 day) on survey sent.
5. Staff deletion is **deactivation** (`active = false`) — this already invalidates PIN login, since `verify_org_pin()` filters on `coalesce(s.active, true)`.

Items 5 (status flow) and 10 both restructure Lead Details — do them in one sitting so the screen is only rebuilt once.

### F. Acceptance for this session

- Add a custom item with a typed CFT → total and vehicle suggestion include it; save and reopen → CFT persists.
- Send a signature link from the APK, sign on another phone, status flips in-app, regenerated PDF shows the signature block.
- Share a tracking link, change order status staff-side, customer page timeline advances; order still appears in the correct OrdersPage tab throughout.

1. Item 1 (blocker, small fix) → 2. Item 10 (business-critical gap — follow-ups) → 3. Item 11 (delete/archive — do the schema + RLS sweep in one focused pass) → 4. Item 2 (data integrity) → 5. Item 5 (status flow — pairs naturally with Item 10, both touch Lead Details) → 6. Item 8 + 9 (quick layout/theme fixes, good batch) → 7. Item 3 (signatures, needs SQL) → 8. Item 6 (tracking, builds on same public-link pattern) → 9. Item 7 (multi-language, biggest surface area — do last so new screens from Items 3/6/10/11 get localized too) → 10. Item 4 (polish, fold into Item 7's overflow work).

**Note on Items 5 + 10:** both add sections to Lead Details and both need the same refresh-after-write fix — worth doing in one sitting so the screen is only restructured once.

**Note on Item 11:** the `deleted_at is null` filter must be added to every read path in the same pass as the schema change. Half-done soft delete is worse than none — rows that reappear in one screen but not another erode trust in the data.

All SQL migrations: output as ready-to-run statements for Boss to execute in Supabase (project `hqqcapifefsaqvotqvlt`); remember explicit `DROP FUNCTION` before changing return types, per `CLAUDE.md`.
