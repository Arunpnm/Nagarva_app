# Nagarva — public customer links: handoff brief

Session date: 29 Jul 2026. Written for Cowork/Claude Code to resume.

---

## What was wrong

The app generated customer links (`/survey`, `/quote`, `/sign`) pointing at
`nagarva.in`, which is a static marketing page dropped on Netlify with no
such routes. Every link 404'd. Nothing was wrong with token generation —
tokens were being persisted correctly to `surveys.token` all along.

## What is now DONE and verified live

**Two migrations run against `hqqcapifefsaqvotqvlt`:**

1. `nagarva_public_token_rpcs.sql`
   - Added `surveys.expires_at`, `surveys.used_at`,
     `document_signatures.expires_at` (14-day default), plus token indexes.
   - Created 4 SECURITY DEFINER RPCs granted to `anon`:
     `public_get_survey`, `public_submit_survey`,
     `public_get_signature_request`, `public_submit_signature`.
     All validate token, status, and expiry server-side. RLS stays ON;
     anon never touches tables directly.

2. `nagarva_public_survey_catalogue.sql`
   - Created `public.app_defaults` (key/value jsonb, RLS on, no policies)
     seeded with `survey_cats` mirroring `kDefaultSurveyCats` from
     `lib/backend/pricing_defaults.dart`.
   - Created `resolve_survey_cats(uuid)` — reads
     `pricing_config.config->'survey_cats'` for the org, falls back to
     `app_defaults`. NOT granted to anon; called only internally.
   - `public_get_survey` now returns the resolved catalogue so each tenant's
     customers see that tenant's own item list.

**Static site deployed:** Netlify project `nagarva-link`, custom domain
`link.nagarva.in`. Plain HTML/CSS/JS, no build step, deployed by drag-drop.
Contains `/survey` and `/sign` pages plus shared `nagarva.css` and
`config.js` (holds Supabase URL + anon key).

**App updated:** `lib/config/app_config.dart` → `kPublicBaseUrl` default
changed from `https://nagarva.in` to `https://link.nagarva.in`.

**Verified end-to-end:** survey link opened, catalogue rendered, 4 line
items submitted totalling 135 cft, row flipped to `status='submitted'` with
`submitted_at` set and `rooms` populated. Token correctly rejected on reuse.

### Shape of `surveys.rooms`

Flat array, one entry per selection:

```json
[{"cat":"Bedrooms","item":"Bed","sub":"Queen Size","cft":55,"qty":2}]
```

Total CFT = `sum(cft * qty)`. This shape was chosen freely because nothing
in the app read the column. Do not change it without updating the deployed
survey page at the same time.

---

## Remaining work

### 1. Survey review screen in the app — HIGHEST PRIORITY

Currently a vendor sees only "Survey response received" in
`lead_detail_page_widget.dart`. The customer's submitted items are
invisible in the UI. The feature does not deliver value until this exists.

Required:
- When `surveys.status == 'submitted'`, render the items grouped by `cat`,
  showing `item`, `sub`, `qty` and line CFT, with the total.
- Show `special_instructions` if present.
- Add a visible indicator on the Leads/CRM list so a vendor can spot
  responses without opening each lead.
- Prefill the detailed quote builder (`SurveyQuotePageWidget`) from the
  submitted selections rather than making the vendor re-enter them.

Note `lib/backend/pricing_defaults.dart` already has `packageNameForCft`
and `packageInfoForCft` — use them to display suggested package and vehicle
from the total CFT.

### 2. `/quote` public page + RPC — still 404s

`lead_detail_page_widget.dart` line ~639 and ~849 call
`_shareLink('/quote', quotation.token)`. Those links are still broken,
exactly as `/survey` was. Needed:

- A `public_get_quotation(p_token)` RPC following the same pattern as
  `public_get_survey` — validate token/status/expiry, return only what the
  customer must see, no org_id.
- Add `expires_at` to `quotations` and an index on `token`.
- A `/quote` page in the `nagarva-link` site, matching the existing visual
  system in `nagarva.css`.
- Decide whether accepting a quote from that page should write back
  (e.g. status → accepted) or whether acceptance goes through `/sign`.

The `quotations` schema was not available this session — introspect it
before writing anything.

Known pre-existing bug worth fixing while in there: `quotations.token`'s DB
default `encode(gen_random_bytes(24),'hex')` does not come back populated on
insert, so the token is generated client-side as a workaround
(see `_generateHexToken` and its comment). `surveys.token` works fine, so
this is isolated to `quotations`. Not root-caused.

### 3. Verify the unmerged diff before anything else

At time of writing there is an unmerged `+1,372 −180` change on
`Nagarva_app main` covering GST mode resolution (`inter`/`intra` resolved at
write time under a CHECK constraint), quote snapshot columns, and a merge of
two duplicate GST state-code tables into `lib/backend/gst_state_codes.dart`.
It is explicitly marked untested against a device or live database, and its
accompanying SQL was written from the generated Dart mirror rather than live
introspection.

Do not build on top of it unverified. Introspect the live schema, confirm no
`quote_*` column already exists under a different type (the `if not exists`
guards silently skip those and the app then writes the wrong shape), then
test on device before merging.

### 4. Housekeeping

- `customer_surveys` table is unused by the current flow — `surveys` is the
  live one. Decide whether to retire it.
- `lib/flutter_flow/nav/nav.dart` may still register `/survey` and `/quote`
  routes from when links were meant to open in the Flutter web build. Those
  are dead now that links point at the static site.
- `surveys` has no `photos` column but `customer_surveys` does. Customer
  photos would materially improve quoting accuracy — consider adding
  `photos jsonb` plus a storage bucket with an upload policy scoped to the
  token.
- Signature `signer_ip` is null: Postgres cannot see the caller IP through
  an RPC. If signatures need to hold up in a dispute, route
  `public_submit_signature` through an Edge Function that captures it.

---

## Rules that still apply

- Arunkumar executes all SQL manually — hand him migrations, do not assume
  DB access.
- Prefer complete file replacements over patches.
- `orders.id` is TEXT (NGV-XXXX), needs `::text` casts in joins.
- Changing a function's return type requires explicit `DROP` before
  `CREATE OR REPLACE`.
- RLS policies use `in (select current_org_ids())`, not `= any(...)`.
- No pricing of any kind on public customer pages — vendors set their own
  rates and those must not be exposed.
