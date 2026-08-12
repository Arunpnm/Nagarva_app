# Nagarva Part 8 — Revision B

**Supersedes** `nagarva_part8_pdf_and_notifications.md` for Items 2, 3 and 4.
Item 1 is done and unaffected.

**Corrections carried over from code review:** `document_signatures.signature_data` is in-row base64 text, not Storage. `quote_charges` is a jsonb column on `orders`, not a table. The refresh mechanism is `nagarvaRouteObserver` + `RefreshOnPopMixin/onPageRefresh()`. Where Rev A conflicts with the repo, the repo wins.

---

## Item 1 — commit and push now

Self-contained, `flutter analyze` clean, reuses the existing widget rather than adding a parallel path. No reason to hold it behind Items 2–4. Three deviations from Rev A were correct calls:

- Reusing the Realtime-driven count instead of adding `count_unread_notifications()` — Rev A's SQL was written against a schema that doesn't exist (`read_at`/`user_id` vs the actual `read boolean` + `recipient_staff_id uuid`).
- Not wiring the bell into `RefreshOnPopMixin` — a persistent AppBar action isn't a page, and Realtime is strictly better than return-to-screen refresh for a live badge.
- No new `NotificationsScreen` route — the existing popup already satisfies the acceptance criteria.

---

## Q1 / Item 3 — the sequence tested was quote-sign → invoice-generate

The missing signature was on the **invoice** PDF. It cannot have been the quote PDF, because the quote PDF doesn't exist yet — building it is Item 2. So the invoice signature lookup found nothing, which is the code behaving as designed.

This is a UX gap, not a bug. The four hypotheses in Rev A are all dead — don't spend time on them.

**Decision: the invoice must inherit the quote's signature when the order was converted from that quote, and must show its provenance.**

Rationale: from the customer's side they signed once, for this job. Asking them to sign again at invoice stage to authorise work they already accepted reads as distrust and will cost conversions. But the two signatures do mean different things legally — quote acceptance is not delivery confirmation — so inheritance must be visible, not silent.

Implementation:

- On invoice PDF generation, if no `documentType: 'invoice'` signature exists for this `orderId`, fall back to the `documentType: 'quote'` signature for the `quotationId` the order was converted from.
- Render it with the provenance line: `Quote accepted by <name> on <dd MMM yyyy> — signature carried forward from quotation <ref>`. Never present an inherited signature as if it were signed on the invoice.
- Keep the existing `OrderDetailPage` invoice signature-request button. If an invoice-specific signature is later captured it takes precedence and replaces the inherited one.
- If neither exists, print `Awaiting customer signature` rather than blank space.

Precondition to check before building: does the order row retain a link back to the source `quotationId`? If the conversion doesn't persist it, that link is needed first, and it's a genuinely useful field independently.

---

## Q2 / Item 2 — separate documents, shared builder

**Decision: two documents, not one combined.**

They ship at different moments in the pipeline. The survey PDF goes to the customer at survey stage, before pricing exists. The quote PDF goes out after. A combined document forces a quote to exist before anything can be sent, which breaks the flow visible on the Lead Details pipeline (Survey completes and sits there while Quoted is still pending).

There's also a commercial reason to keep them apart: customers routinely want the itemised CFT list on its own for insurance declaration and for shopping the job around, and a survey list is a fine thing to hand over. The priced quote is not.

Build one shared header/footer/branding builder, two document generators on top of it. If a single handover pack is wanted later it's a third generator that composes both — cheap once the parts exist.

Export UI: two buttons in the Survey & Quote card, with the quote button disabled until a quote exists.

---

## Q3 / Item 4 — per-org configurable basis, snapshotted at quote time

**Decision: basis becomes per-org configurable in `pricing_config`, with the current `kDefaultChargeFields` values seeding the defaults. Do not hardcode basis per charge key.**

Rationale: this is the multi-tenant call. Packers price the same service differently — some charge packing per CFT, some lumpsum by house type, some per room. Hardcoding "packing is always per-CFT" bakes APC's pricing model into every tenant's quotes and will be the first thing a new vendor complains about. The global `_billingMode` toggle stays as the org-wide default; per-line basis overrides it.

**No SQL migration required.** `quote_charges` is jsonb, so this is a value-shape upgrade:

```
legacy:  { "packing": 5000 }
new:     { "packing": { "amount": 5000, "basis": "per_cft", "qty": 135, "rate": 37.04 } }
```

Reader rule: if the value is a number, treat it as legacy lumpsum with basis `null` and render it as a plain line with no basis column. If it's an object, render the full breakdown. That keeps every existing order's PDF reprinting correctly with no backfill.

**Critical: resolve basis at quote time and write it into the jsonb snapshot.** Do not look basis up from `pricing_config` at PDF-render time. The snapshot pattern in `20260729_order_quote_snapshot.sql` exists precisely so a reprinted document matches what the customer agreed to; reading live config would silently rewrite historical quotes when an org changes its pricing model.

`pricing_config` gains a per-charge-key basis map. Send the SQL for that before executing — human-in-the-loop rule stands.

Charge keys needing a basis option, from `kDefaultChargeFields`: packing, loading, transport, unloading, unpacking, rearrangement, materials, toll/parking, insurance. Allowed bases: `lumpsum`, `per_cft`, `per_floor`, `per_trip`, `per_km`, `percent_of_declared_value`, `at_actuals`.

Rendering rule unchanged from Rev A: a zero or null line prints `Included` or is omitted, never `₹0`.

---

## Build order (revised)

1. Item 1 — commit and push now.
2. Item 3 precondition — confirm the order retains `quotationId`.
3. Item 2 — shared builder + survey PDF + quote PDF.
4. Item 3 — invoice signature inheritance with provenance line.
5. Item 4 — basis config + jsonb shape upgrade + detailed variant.
