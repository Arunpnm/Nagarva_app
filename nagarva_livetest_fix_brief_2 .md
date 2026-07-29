# Nagarva — Live APK Test Fix Brief #2 (28 Jul 2026)

Source: live phone testing of Lead Details screen (lead "abi", Chennai → Bengaluru, House Shifting). Reference UX for status flow: APC React app lead screen. Five items below, ordered by severity.

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
