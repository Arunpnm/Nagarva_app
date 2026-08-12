# Nagarva Parity Brief — Part 8 Addendum
## PDF Export + Dashboard Notifications

**Source:** Live APK test, 31 Jul 2026 (build verified: device setup → org code → PIN/email login → dashboard all working).
**Scope:** 4 items. Items 1 and 3 are bugs. Items 2 and 4 are new build.

---

## Item 1 — Notification bell missing on Dashboard AppBar (BUG)

**Current state:** Dashboard AppBar renders hamburger (left) → "Dashboard" title → search icon (right). No notification entry point anywhere on the screen. The `REMINDERS` KPI card shows a count but is not the notification inbox.

**Required:**

- Add a bell `IconButton` to the Dashboard AppBar `actions`, positioned **before** the search icon.
- Unread badge: red dot with count when `unread > 0`, no badge at zero. Cap display at `99+`.
- Tap → push `NotificationsScreen` (already built in Core V1 — reuse, do not rebuild).
- Touch target minimum 48×48 logical px, consistent with the navigation touch-target fixes in Part 4.
- Icon colour must match the existing AppBar icon treatment (white on `#0F2A47` navy).

**Unread count source:**

```sql
select count(*) from notifications
where org_id in (select current_org_ids())
  and read_at is null
  and (user_id = auth.uid() or user_id is null);
```

- Wrap in a `count_unread_notifications()` RPC so RLS stays server-side.
- Refresh on: screen focus, pull-to-refresh, and after any write that creates a notification. This must use the same `refreshAfterWrite` pattern from the Part 1 systemic fix — do **not** introduce a separate one-off refresh path.
- If Supabase realtime is already subscribed on `notifications`, bind the badge to that stream instead of polling.

**Acceptance:** Bell visible on Dashboard. Badge count matches the Notifications screen list. Marking one read decrements the badge without an app restart.

---

## Item 2 — Download Survey & Quote as PDF (NEW)

**Where:** Lead Details → `Survey & Quote` card. Currently the card has `Build quote from this survey`, the `Quote sent` status chip and `Awaiting signature — resend link`, but no export.

**Add:** a `Download PDF` action in the card header row (icon + label), plus a share affordance so it can go straight to WhatsApp.

**Packages:** `pdf` (document build) + `printing` (`Printing.sharePdf` / `Printing.layoutPdf`). Do not add a new PDF dependency — check `pubspec.yaml` first, Flutter is pinned at 3.35.5 so version-resolve carefully.

**Document structure — Survey section:**

- Org header block: logo, business name, address, GSTIN, phone, email — pulled from the org profile/`settings` table, never hardcoded to APC.
- Lead reference, customer name, phone, move date, origin → destination.
- Items grouped by room exactly as the app displays them:

  ```
  Kitchen                              35 CFT
    Refrigerator — Single Door         15 CFT
    Refrigerator — Double Door         20 CFT
  Bedrooms                            100 CFT
    Bed — Double                       45 CFT
    Bed — Queen Size                   55 CFT
  ```

- Footer totals: total CFT, item count, and the suggested line (`1 RK / Studio · 2 crew · 7 Ft`).

**Document structure — Quote section:**

- Charge lines with the billing mode shown per line (lumpsum / per CFT / per floor / per trip) — reuse the charge billing modes from Part 3.
- Subtotal → GST block. GST must use the existing IGST vs CGST+SGST auto-detect logic; do not re-implement the state comparison.
- Grand total in words and figures.
- Quote validity date, payment terms, T&C.
- Signature block (see Item 3).

**Filename:** `Nagarva_Quote_<lead_ref>_<yyyyMMdd>.pdf`. Same convention for survey-only.

**Acceptance:** PDF opens on a real device, shares to WhatsApp, org branding correct for the logged-in tenant (test on both APC and TEST 1 to confirm no tenant bleed).

---

## Item 3 — Customer signature not visible in PDF (BUG)

The signature is captured on the customer-facing quote acceptance page but does not render in the generated PDF.

**Investigate in this order — most likely first:**

1. **Base64 data-URL prefix not stripped.** If the web signature pad saves via `toDataURL()`, the stored string starts with `data:image/png;base64,`. Passing that whole string to `base64Decode` throws or yields garbage. Strip everything up to and including the comma before decoding.
2. **Private Storage bucket.** If the signature is a Storage object, a plain public URL returns 403. Use `storage.from(bucket).download(path)` to get bytes, or generate a signed URL. The PDF builder needs the raw bytes either way — `pw.Image` cannot fetch a network URL by itself.
3. **Column not selected.** Check that the query feeding the PDF builder actually selects the signature column. A `select('id, name, total')` style projection will silently drop it.
4. **Async race.** Image bytes must be fetched and awaited **before** `pw.Document().addPage(...)` runs. This is the same class of bug as the APC proforma race condition — resolve the future first, then build.

**Correct render:**

```dart
final Uint8List sigBytes = await _fetchSignatureBytes(quoteId);
final sigImage = pw.MemoryImage(sigBytes);
// inside page build:
pw.Image(sigImage, height: 60, fit: pw.BoxFit.contain)
```

**Signature block content:** signature image, signer name, `Signed on <dd MMM yyyy, hh:mm a>`, and the acceptance reference/token if one is stored.

**Fallback rule:** if bytes fail to load, print the text line `Digitally accepted on <date> — reference <token>` rather than leaving blank space. A silently empty signature area on a document sent to a customer is worse than a missing image.

**Acceptance:** Generate a PDF for a quote with a captured signature and confirm the image renders. Then generate one for an unsigned quote and confirm it shows `Awaiting customer signature` instead of a blank box.

---

## Item 4 — Detailed PDF with service breakdown (NEW)

Customers need to see what is actually included, not just a single lumpsum figure.

**Add a toggle** at the point of export: `Summary` (current, single total) vs `Detailed` (itemised services).

**Detailed variant — service lines:**

| Service | Basis | Notes |
|---|---|---|
| Packing | per CFT / lumpsum | material grade if mapped |
| Loading | per floor / lumpsum | floor count + lift available Y/N |
| Transportation | per trip / per km | vehicle type, truck ft |
| Unloading | per floor / lumpsum | destination floor count |
| Unpacking | per CFT / lumpsum | |
| Rearrangement | lumpsum | often optional — mark clearly |
| Packing materials | itemised | source from materials inventory (Part 5) |
| Toll / Parking / Octroi | at actuals | |
| Insurance | % of declared value | show declared value |

- Each line must show: service name, basis, quantity, rate, amount. A line with a zero or null amount is either omitted or printed as `Included` — never as `₹0`, which reads as a pricing error to a customer.
- Add an explicit **Inclusions / Exclusions** block below the table. Exclusions are where disputes come from, so give them equal visual weight.
- Storey/floor and lift availability should carry through from the survey, not be re-entered.

**Schema note:** if `quote_charges` has no `service_type` column, this needs a migration to classify each charge line. Flag it and send the SQL rather than executing — the human-in-the-loop rule applies.

**Acceptance:** Detailed PDF for a real quote shows every charge line traceable back to what was entered in the quote builder, and the sum of lines equals the grand total on the summary PDF for the same quote.

---

## Build order

1. Item 1 (smallest, unblocks dashboard completeness)
2. Item 3 (fix the signature path first — Items 2 and 4 both depend on it)
3. Item 2 (summary PDF)
4. Item 4 (detailed variant, built on Item 2's document skeleton)

## Open questions for Arun

1. Where is the customer signature currently stored — a column on `quotes`, or a file in Supabase Storage? This determines the Item 3 fix.
2. Should the Survey PDF and Quote PDF be two separate documents or one combined document with two sections?
3. Does `quote_charges` already have a service/category column, or is a migration needed for Item 4?
