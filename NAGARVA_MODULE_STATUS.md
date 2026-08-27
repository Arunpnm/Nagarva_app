# Nagarva — Verified Module Status

**Created:** 27 Aug 2026
**Purpose:** `nagarva_module_register.md` lists what was *planned*. This
file records what is **actually true**, verified against live Postgres
(`hqqcapifefsaqvotqvlt`) and against `lib/` — never against the docs.

**Why this file exists.** The register and `CLAUDE.md` have gone stale in
both directions, repeatedly and in ways that cost real sessions: things
marked done that were never built, and things marked open that shipped
weeks ago. `CLAUDE.md`'s own changelog documents at least four prior
reconciliation passes. The failure is structural — status lived in
prose next to design rationale, so nobody could tell which sentences
were claims and which were decisions.

**Rule for maintaining this file: a status line changes only when
something was introspected.** `count(*)`, `information_schema`,
`pg_proc`, `pg_policies`, or a grep of `lib/`. Never from memory of an
earlier read, and never from a commit message — see the `branches` entry
below for why commit messages specifically are not evidence.

---

## 1. Corrections found this pass

Five places where the documented state was wrong. Listed first because
they are the point of the document.

| # | Claim | Reality | Evidence |
|---|---|---|---|
| 1 | `quick_payment_section.dart` swallows allocator errors in a bare `catch (_)` — "the worse half", per CLAUDE.md's FY-rollover section | **Fixed, but UNCOMMITTED — and not by this session.** The bare catch is gone; it now extracts the DB message via `extractDbErrorMessage`, shows a "No receipt number" dialog naming the cause, and lets the vendor choose — not a hard block, per Item 32b. **See the provenance warning below: this file changed on disk mid-session and the change is not in any commit.** | Read `quick_payment_section.dart:193-237`; `git diff` shows it as a pending change against `HEAD` |
| 2 | `20260825_branches_table.sql` — commit `4d12856` says "(unrun)" | **Live.** Table exists, 11 columns, **3 rows**. The commit message was accurate when written and is now stale. | `information_schema.columns`, `select count(*) from branches` |
| 3 | Warehouse reads as built — tables exist and are in `kSoftDeleteTables` discussions | **Greenfield.** `warehouses` 0 rows, `storage_jobs` 0 rows, and **no file in `lib/` queries either table.** Schema only. | Row counts + `grep` of `lib/` |
| 4 | NG-030 transit insurance + claim tracking — listed as Phase 3 outstanding | **Substantially built.** `insurance_policies`, `claims`, `claim_items` all exist, and `insurance_claims_page_widget.dart` does real CRUD against all three (7 query/insert/update sites). Register is wrong. | `information_schema.tables` + grep |
| 5 | `getText('porcashcol1')` / `('porcashcol2')` on New Order's porter section | **Live UI bug, now fixed.** Neither key has ever existed in `kTranslationsMap`, so `getText` returned `''` — the "Cash Collected by Porter (₹)" **label and hint rendered blank** on every porter order since the field was added. Found by the ARB migration; recovered into `app_en.arb`. | `grep porcashcol lib/flutter_flow/internationalization.dart` → no match |

> **Lesson worth keeping.** #5 was invisible to every prior sweep because
> the sweeps looked for *hardcoded* strings. This was the opposite
> failure — a string that was correctly externalised to a key that was
> never created. A localisation call that silently resolves to `''` looks
> identical in code to one that works. Only enumerating keys against the
> map finds it.

---

## 2. Unrun migrations — verified live, 27 Aug 2026

Supabase has no reliable migration ledger for this project (SQL is run
by hand in the editor; `list_migrations` shows only 2 entries from
16 Aug). So each was verified by checking for the objects it creates.

| File | State | How verified | Notes |
|---|---|---|---|
| `20260825_gst_treatment_and_display.sql` | **UNRUN** | `gst_treatment` absent from `quotations` and `orders` | GST spec step 2. Blocks correct CGST/SGST vs IGST split. **Step 1 is no longer blocked** — the GSTIN-33/Karnataka contradiction is resolved by the org-per-state model (section 10.1). |
| `20260820_phase_a_device_register.sql` | **UNRUN** | `device_bindings` does not exist | Reviewed in full this pass — see §3. |
| `20260808_tierB_org_billing_rls.sql` | **UNRUN** | `org_insert` policy still present on `organizations`; Tier B drops it | Held pending Arun's signup + Super Admin device tests. |
| `20260819_pod_relationship_cleanup.sql` | **Not applied, by decision** | — | Render-side guard already makes the document correct. Arun's call. |

**Confirmed RUN** (so nobody re-runs them): Tier A
(`staff`/`staff_invites` carry per-command policies), `20260816_invite_codes.sql`
(`invite_codes` + `platform_settings` exist), `20260825_branches_table.sql`,
`20260818_item32_plan_enforcement.sql` (`org_effective_plan` exists),
`20260817_item12c_package_columns.sql`, and
`20260812_next_doc_number_fail_loud.sql` — the last confirmed by reading
`pg_get_functiondef('next_doc_number')`, which raises `P0001` with a
descriptive message when no series row matches and **does not**
auto-insert a bare-prefix row. That is the Ponci `0001` bug, closed at
the database.

---

## 3. Device register migration — review, ready to run

`supabase/20260820_phase_a_device_register.sql`. Reviewed line by line
against the current live schema. **Verdict: correct, safe, and inert.**

**Every preflight dependency verified present:** tables `organizations`,
`staff`, `org_members`, `staff_invites`; functions `current_org_ids()`,
`is_org_owner(uuid)`, `is_org_manager(uuid)`, `gen_random_uuid()`;
column `staff.active` (boolean). `orders.supervisor_id` exists (uuid),
which §4 of the migration reads.

**Safety properties:** wrapped in `begin`/`commit`; preflight aborts on a
missing dependency; postflight aborts and rolls back if any object it
was meant to create is absent; fully idempotent
(`create table if not exists`, `create or replace function`,
`drop policy if exists`). No object it creates already exists, so there
is no collision.

**Confirmed non-issues:**
- `leads.assigned_staff_id` genuinely does not exist. The
  `exception when undefined_column` handler around that count is
  load-bearing and correct — without it the whole offboard would fail on
  a column that was never added.
- `is_org_manager()` resolves through `current_staff_id()`, so a
  **manager on a PIN session** can read the register and revoke a
  device. The RLS read policy and `revoke_device` both work for shadow
  staff auth users, not just email sessions.

**Findings to decide on, none blocking:**
1. **It enforces nothing, and delivers nothing, until three follow-ups
   land.** `record_device_login`, `revoke_device`, `offboard_staff` and
   `device_bindings` are referenced by **zero** files in `lib/` and zero
   Edge Functions (grepped `*.dart` and `*.ts` — no matches). Running
   the SQL is therefore risk-free and effect-free. The value arrives
   only after: (a) `pin-login`/`staff-login` redeployed to call
   `record_device_login`, (b) a device-management UI calling
   `revoke_device`, (c) `staff-deactivate` updated to call
   `offboard_staff`. (a) and (c) are Edge Function deploys.
2. **Permission asymmetry, probably intentional, worth confirming.**
   `revoke_device` allows owner **or manager**; `offboard_staff` is
   **owner only** (`is_org_owner` checks `org_members` alone). So a
   manager can revoke a device — the weaker, install-scoped control —
   but cannot deactivate the person, which is the control that actually
   works. Defensible, but it should be a decision rather than an
   accident.
   **FLAGGED FOR DECISION, 27 Aug 2026 — resolve BEFORE `pin-login` /
   `staff-login` are redeployed to call `record_device_login`.** Once
   those deploys land the register starts filling with real devices and
   the asymmetry becomes live behaviour: a manager offboarding a leaver
   can revoke every device they hold and still leave the person's PIN
   working, because `staff.active` is the only control that actually
   closes re-entry (an ex-employee re-binds a new device freely — the
   org code is the vendor's public slug). Revoking without deactivating
   therefore *looks* like offboarding and is not. Either grant
   `offboard_staff` to managers too, or restrict `revoke_device` to
   owners so the two controls cannot diverge.
3. `device_bindings.revoked_by` has no FK to `auth.users`. Minor;
   consistent with the rest of this schema.

**Recommendation:** safe to run whenever. Because it is inert, running it
early costs nothing and removes it from the critical path. **Not run —
Supabase access is read-only this session and Arun has not confirmed.**

---

## 4. ⏳ Dated deadline — FY numbering rollover

**Target ship: December 2026. Hard deadline: 1 April 2027.**
December leaves a full quarter of margin to test a real rollover against
a live org before the boundary.

**Verified state, 27 Aug 2026:**
- `roll_over_number_series()` **does not exist** in the database.
- `number_series` holds 33 rows. **Every active row is `fy = '2026-27'`.**
  Zero rows exist for `2027-28`, for either org.
- The other FY present is the legacy `2627` format — 5 rows, all
  `active = false`, all with **empty prefixes**. These are inert:
  `next_doc_number` filters on `active`. They are the residue of the
  bare-`0001` bug and should not be reactivated.

**The 5 orphan rows are a historical-document question, not cleanup —
UNRESOLVED.** Re-verified directly, 27 Aug 2026 (an earlier count of
"six rows / 5 receipts, 2 invoices" in session notes was wrong; these
are the queried figures):

| doc_type | branch | last_number | active |
|---|---|---|---|
| invoice | Bengaluru | 1 | false |
| invoice | Chennai | 1 | false |
| proforma | Chennai | 1 | false |
| receipt | Bengaluru | 1 | false |
| receipt | Chennai | 5 | false |

`last_number` is the last number ISSUED, so **6 money receipts, 2 tax
invoices and 1 proforma already went to customers carrying bare,
prefix-less numbers** (`0001` rather than `2026/0001`). Deleting the
rows changes nothing about those documents; it only discards the
evidence of which numbers were used. Reissuing or renumbering them is a
decision about documents a customer already holds — and for the tax
invoices, about documents that may have been filed. **Left untouched
deliberately. Not a tidy-up to be done in passing.**

**What happens at 00:00 IST on 1 April 2027** if nothing ships: five doc
types hard-fail (invoice, proforma, voucher, money receipt, LR) because
`next_doc_number` raises `P0001` with no matching row. The sixth path —
Quick Payment — now surfaces a dialog rather than failing silently
(see §1 #1), so the silent-unnumbered-payment half of this is already
closed.

Design is settled in `CLAUDE.md`: RPC + owner-confirmed Settings card +
a shared catch that turns `P0001` into a "start 2027-28 numbering"
prompt at the six allocator call sites. **No cron.**

---

## 5. Uncommitted / unanchored work

> **RESOLVED 27 Aug 2026 — everything below is now committed.** Three
> commits on `main` (unpushed at time of writing, pending review):
> `fix(payments): surface receipt-number failures…`,
> `feat(l10n): NG-055 ARB substrate, 171 migrated sites, and org session
> restore`, and this document's own commit. Both stashes are preserved
> AND anchored to branches — `stash-12aug-lastselectedorg` and
> `stash-11aug-materials` — so they survive a `git stash drop`.
>
> **The provenance question below is answered:**
> `quick_payment_section.dart` was modified by the **Claude Code session
> running concurrently on this machine**, which was told at ~00:30 that
> it was the only writer. Both sessions were live against one working
> tree for roughly half an hour. Nothing was lost, but the concern this
> section raises was correct and the near-miss was real.
>
> **The mechanism that nearly repeated the 12 Aug loss:** a stale
> `.git/index.lock` (0 bytes, created 00:14, still present at 07:43)
> blocked every `git add`. That is exactly how the 12 Aug fix ended up
> uncommitted and then lost. Removed after confirming no `git` process
> was running and that `.git/index` was intact. **If a commit ever fails
> with `index.lock` exists, check for a live git process, then clear it
> and commit — do not leave the work on disk.**
>
> The section is kept as written for the record.

**`LastSelectedOrg` — real, correct, never committed.**

- `lib/backend/last_selected_org.dart` is **untracked**. Verified with
  `git log --all -- <path>` → **no output**. The file has never existed
  in any commit on any branch.
- That settles the question `NAGARVA_DEV_LOG.md` left open on 26 Aug:
  the 12 Aug attempt was **never committed and never reverted**. It was
  written to disk, lost to a later session, and correctly re-derived on
  26 Aug. Not a revert to investigate.
- Working-tree changes (+30/−4 across three files, via
  `git diff --ignore-cr-at-eol`): `main.dart` (prefers the saved org when
  it is still a real membership, else falls back to `members.first`
  exactly as before), `login_page_widget.dart` and
  `settings_page_widget.dart` (persist on login / on org switch).
- **Unverified by a compiler.** No `flutter analyze` has ever run against
  it, across three attempts on three separate days.
- **Two stashes must be preserved:** `stash@{0}` (WIP on
  `e60f38a`), `stash@{1}` ("MID laptop backup before sync").

**`quick_payment_section.dart` — uncommitted, and provenance unclear.**

At the start of this session (27 Aug, ~00:30) `git diff --ignore-cr-at-eol`
reported exactly **three** modified files — `main.dart`,
`login_page_widget.dart`, `settings_page_widget.dart`, +30/−4. That
listing did **not** include `quick_payment_section.dart`.

Its mtime is **00:56 on 27 Aug**, i.e. during this session but before
this session's first edit (01:01), and this session never wrote to that
file. So it was modified by something else — most likely concurrent work
by Arun, another session, or a scheduled task — while this session was
reading it.

**Implications, stated plainly:**
- The receipt-number fix is real and correct, but it is **working-tree
  only**. It is not in any commit. Same failure mode as `LastSelectedOrg`
  above: correct work sitting unanchored on disk, one careless
  `git checkout` from being lost.
- It should be committed **separately** from the localisation work — it
  is a financial-correctness fix and belongs in its own reviewable
  commit, per `CLAUDE.md`'s "security migrations get their own commit"
  convention, which applies to this class of change for the same reason.
- If another session is running concurrently against this working tree,
  **that is worth knowing before anyone commits**, because two agents
  staging overlapping changes is how the CRLF mess and the lost 12 Aug
  fix happened in the first place.

**Repo hygiene:** ~300 files show as modified; all CRLF-only. Always
inspect with `git diff --ignore-cr-at-eol`. A `.gitattributes`
normalisation pass is still outstanding and still needs a working
analyzer.

---

## 6. Tenants — live state

| Org | Slug | Plan status | Trial ends | Members | Staff | Orders |
|---|---|---|---|---|---|---|
| Arun Packers and Couriers | `apc` | **active** | — | 5 | 9 | 25 |
| Ponci Packers And Movers | `ponci-packers-and-movers` | **trial** | **2026-08-23** (elapsed) | 1 | 0 | 0 |

**Ponci's trial has already expired** — 23 Aug 2026, four days ago, not
"around 30 Aug". With `grace_days = 7` from `subscription_plans`, grace
runs out **30 Aug 2026**, which is the date in Arun's head and is
correct for *read-only*, but the trial itself lapsed earlier.

**Consequence that affects planning:** Ponci is the only non-APC tenant
and therefore the only fresh-tenant test vehicle. From 30 Aug, Item 32b's
`enforce_org_writable()` trigger blocks INSERT on orders, leads,
quotations, customers, vendors, materials, trips, tasks, vendor_bills and
expenses for that org. Reads, exports, `payment_entries` and `receipts`
stay open by design. So **any fresh-tenant testing that needs to create
records must happen before 30 Aug, or Ponci's plan/trial dates must be
extended** via Super Admin. This directly touches the branch-management
screen, which is the thing currently blocking fresh-tenant testing.

---

## 7. Module status — verified

Legend: **live** = built and exercised · **partial** = built, gaps named
· **greenfield** = schema and/or nothing in `lib/` · **blocked** = waiting
on a named thing.

### Live
Auth/PIN login and device binding · org scoping (`OrgScope`) and RLS on
18 tables · view `security_invoker` on 12 views · branch scoping
(field-verified) · dashboard Phase 1 (10 tiles, RBAC-gated) · orders,
leads, customers, quotations, survey/CFT catalogue and slabs (Item 12,
field-verified) · document generation (invoice, LR, quotation, money
receipt) · numbering via `next_doc_number` (fail-loud confirmed) ·
supervisor OTP + POD · soft delete + recycle bin · plan enforcement
(Item 32/32b) · Sentry (wiring caveat below) · Help & About ·
**insurance policies and claims** (see §1 #4).

### Partial
- **Materials (NG-016)** — CRUD live, 5 rows, `stock_movements` 5 rows.
  The **issue → consume → return → damage cycle is missing**; that is the
  whole module. `low_stock_view` exists.
- **Accounts** — Daily Accounts Register live and org-scoped. Depth items
  in `NG-BRIEF-accounts-depth.md` outstanding.
- **Sentry** — integration correct; `main.dart`'s handlers **overwrite**
  Sentry's own. Acceptance test is an unhandled error in a release build
  reaching the dashboard, which has never been done. Provider-side geo
  scrubbing ("Prevent Storing of IP Addresses") still needs turning on.
- **Reports / P&L** — built, but the two views **disagree on net profit**
  (`dashboard_kpis_view` subtracts labour and expenses; `branch_kpis_view`
  subtracts only porter commission). Branch margin is suppressed rather
  than shown wrong. Scheduled with NG-046.
- **Localisation (NG-055)** — see §8.

### Greenfield
- **Warehouse / storage billing (NG-044)** — `warehouses` 0 rows,
  `storage_jobs` 0 rows, **nothing in `lib/` touches either**.
- **Fuel (NG-017) and mileage (NG-019)** — no `fuel_entries` table
  exists at all. `vehicle_trips` has 1 row. Capture-first risk: litres
  cannot be reconstructed later.
- **Salary ledger (NG-014)** — `staff_advances` 0 rows.
- **Vendors (NG-038)** — `vendors` and `vendor_bills` both 0 rows.
- **Tasks, trips, reviews, WA inbox** — pages exist, tables at 0 rows.
- **Journal entries** — table exists, 0 rows, double-entry unbuilt.
- **Contracts, purchase orders, documents** — tables exist, 0 rows,
  nothing in `lib/` queries them.
- **E-way bill (NG-026/027)**, **condition photos (NG-028)**,
  **offline mode (NG-052)** — not started.

### Blocked
- **Item 31 subscription billing (NG-051)** — Arun's CA, on which entity
  bills for subscriptions.
- **Item 13 public enquiry link (NG-032)** — four blockers, incl. no
  SMS/WhatsApp send path and no rule for which branch owns a NULL-branch
  public lead (fail-closed RLS makes such a lead owner-visible only).
- **WhatsApp (NG-039)** — AiSensy unbuilt; gates NG-035, NG-036.
- **link.nagarva.in** — every path still serves the `/auth` relay page.
  `/quote` and `/track` share buttons hidden. Nothing deploys until the
  survey/sign recovery is confirmed.
- **Privacy policy + terms (NG-005)** — blocks Play Store and Meta
  review. Small, unblocks three things.

### Standing gaps
- **FK coverage: 12 of 116 org-scoped tables** have an FK on `org_id`.
  Deleting an org strands the rest silently. Cascade decision unmade.
- **`SoftDeleteService.isOwner`** gates order deletion with **nothing
  behind it in the DB** — `can_delete_order()` checks no role at all.
  UI-only. The fix loosens access, so it is a decision.
- Two overlapping RPC families (survey, signature). Consolidation
  unscheduled.

---

## 8. Localisation (NG-055) — state after this pass

**Substrate decided: ARB + `gen_l10n`** (Option A), on the grounds that
the app writes GST invoices and LR/consignment notes for Tamil Nadu and
Karnataka. That makes locale-correct number formatting (Indian 2,2,3
digit grouping), ICU plurals, and typed interpolation **hard
requirements**, and a `Map<String,String>` cannot format or interpolate
anything. Rationale is recorded in `l10n.yaml`'s own header.

**Done this pass:**
- **English fallback in `getText`** — it previously ended `?? ''`. All
  715 keys carry empty `ta`/`hi`/`kn` values, so switching locale
  rendered a **blank app**, not a partly-translated one. This had to land
  before the picker, not after.
- **Locale list trimmed** to Tier 1 `en/ta/hi/kn` in both
  `FFLocalizations.languages()` and `main.dart`'s `supportedLocales`,
  which must stay in step. Dropped seven FlutterFlow export defaults,
  two of which (`ar`, `ur`) are RTL — never laid out or tested for.
  `getVariableText`'s positional array was reordered in the same edit;
  its order is load-bearing against `languageIndex`.
- **Settings language picker** — `setLocale` had no caller outside
  `main.dart`, so the feature was unreachable. Names render in their own
  script. Not owner-gated: a driver or packer is who needs it.
- **ARB scaffolding** — `l10n.yaml`, `generate: true` in `pubspec.yaml`
  (no new dependency: `flutter_localizations` and `intl 0.20.2` were
  already pinned), `lib/l10n/app_en.arb` with **490 messages**, and
  `app_ta`/`app_hi`/`app_kn` stubs so those locales *resolve* rather than
  silently falling back to `supportedLocales.first`.
- **All 171 `getText()` call sites migrated** across 15 files to
  `AppLocalizations.of(context).<key>`. Keys were derived mechanically
  from the English text and deduplicated 690 → 488, so identical strings
  share one message. **16 of the 171 were line-wrapped by `dart format`**
  and would have been missed by a single-line regex — the exact trap
  `CLAUDE.md`'s grep convention warns about; the migration used a
  multiline matcher.
- `AppLocalizations.delegate` registered ahead of `FFLocalizationsDelegate`,
  which **stays** — it still owns locale persistence, not just lookup.

**Not done, deliberately:** the ~1,700 raw Dart strings in everything
built since July (875 `Text('…')`, 459 label/hint, ~367 SnackBars).
Heaviest: `order_detail_page` 102, `components` 77, `vendors_page` 53,
`trips_page` 52, `settings_page` 51, `insurance_claims_page` 51.
**This waits for the branch-management screen** — that screen still
blocks fresh-tenant testing, and a 1,700-string sweep colliding with it
would make both unreviewable.

**Verification status — RUN AND PASSED, 27 Aug 2026.** The acceptance
test described here (the paragraph this replaces predicted it would fail
loudly, and it did) has now been executed:
- `flutter pub get` — **failed first**, then clean. See the reserved-word
  rule below.
- `flutter analyze lib/` — **177 issues, 0 errors**, identical to the
  pre-migration baseline: same 10 warnings, same files. The 171 migrated
  sites cost **zero** net analyzer issues.
The prediction was right on the mechanism: the one defect was a compile
error, not silent wrong output.

**RULE — an ARB key that is a Dart reserved word breaks the ENTIRE l10n
build, not just its own string.** `gen_l10n` maps ARB keys straight to
Dart getters, so `"new"` generated `String get new` and **all five**
output files failed to parse — `app_localizations.dart` plus every
locale. `flutter pub get` could not complete at all. Renamed to
`statusNew` (one call site, `leads_page_widget.dart:444`). `app_en.arb`
was swept against the full Dart reserved-word list — `new` was the only
hit, so this was a one-off, not the first of many. **Check this on any
future key addition**; the `@statusNew` description records why the key
is not the obvious name.

**`lib/l10n/gen/` is GITIGNORED** (decision made 27 Aug 2026 — the
"open decision" this paragraph used to record). `flutter pub get`
regenerates it from `lib/l10n/*.arb`. **Consequence: a fresh clone will
not compile until `flutter pub get` has been run.** The reviewability
rationale that originally argued for committing it was removed from
`l10n.yaml` at the same time, so it cannot outlive the decision it
justified.

**When translating: document strings are out of scope.** GST invoice and
LR/consignment-note wording has a legally expected form. Nothing in the
PDF paths should be translated without a specific decision.

---

## 9. Document numbering — prefix model (audited 27 Aug 2026)

**Record only. Nothing in this section has been fixed.** Read-only audit
of the live schema, `next_doc_number`'s body, and every Dart reference.

**The model.** `number_series` is keyed per-org, per-doc-type,
per-branch, per-FY:

```sql
CREATE UNIQUE INDEX number_series_uniq ON public.number_series
  USING btree (org_id, doc_type, COALESCE(branch,''), COALESCE(fy,''));
```

`prefix` is **not** part of the key — it is an attribute of the slot, so
one `(org, doc_type, branch, fy)` has exactly one prefix. `prefix` and
`suffix` default `''`, `padding` defaults 4, `last_number` defaults 0.
`org_id`, `branch`, `fy` and `prefix` are all NULLABLE. A composite FK
`(org_id, branch) → branches(org_id, name)` carries `ON UPDATE CASCADE`,
so a branch rename correctly carries its series.

### 9.1 The vendor's entered prefix is silently discarded

`OrgSetupPage` has a prefix field on the onboarding form. It writes
`settings.invoice_prefix` — and **nothing reads that key.** The only
occurrence in the entire repo is the write itself
(`org_setup_page_widget.dart:87`). `next_doc_number` reads
`number_series.prefix` and never consults `settings`.

So a vendor types their invoice prefix during onboarding, the app
accepts it, and their invoices carry the seeded `2026/` instead.
**User-visible on the first invoice a new tenant issues** — and it is
the vendor's own document identity, so it will not read as a small bug
to them. Live: zero `settings` rows match `%prefix%` for either org.

### 9.2 No prefix validation at any layer

`next_doc_number` performs none. It selects `for update`, raises P0001
if not found, increments, and returns:

```sql
coalesce(rec.prefix,'') || lpad(n::text, coalesce(rec.padding,4), '0')
  || coalesce(rec.suffix,'')
```

`coalesce(prefix,'')` means NULL and empty are **silently valid** —
which is exactly how the bare-`0001` invoices in §4 were produced. The
table carries no CHECK constraints at all beyond the PK and branch FK,
so a 400-character or punctuation-laden prefix would be accepted and
printed onto a GST invoice.

**Needed:** a CHECK — non-empty, max ~10 chars, whitelist alphanumerics
plus `/` and `-`. **Rule 46(b) caps the whole invoice number at 16
characters**, so the prefix budget is genuinely small once padding and
any suffix are counted.

### 9.3 A prefix edit silently continues the old counter

`prefix` and `last_number` are independent columns with no trigger, no
CHECK and no history. Changing `2026/` → `APC/` while `last_number = 12`
makes the next document `APC/0013`: the series continues its count under
a new identity, and `0001`–`0012` under the old prefix are unreachable
and unrecorded. `last_number` is only ever incremented by
`next_doc_number`, so **no audit trail exists** to reconstruct which
numbers went out under which prefix.

For tax invoices this breaks **Rule 46(b) consecutiveness** — two
visually distinct series sharing one counter, with nothing recording
that the change happened or when.

**Proposed rule — CONFIRM WITH CA before building:**
- Freely editable: quotations, proformas, leads, LRs.
- **Locked once `last_number > 0`: invoices and receipts.** Changeable
  only at FY rollover, which is where NG-010's
  `roll_over_number_series()` (§4) already creates a clean boundary.

### 9.4 Recurring class — and one case that only LOOKED like it

**CORRECTED 27 Aug 2026. The prefix case is NOT an instance of this
class. The original wording here was wrong; it is kept below the
correction because the mistake is instructive.**

Ponci's prefixes are byte-identical to APC's — `2026/`, `CLM-`, `CTR-`,
`GRN-`, `LR`, `PO-`, `PS-`, `STG-`. That was read as "new-tenant seeding
copies APC's configuration." **It does not.** `seed_org_number_series()`
builds every prefix from a **hardcoded `values` list inside the function
body**, and the calendar-prefixed types derive the year from
`current_fy_ist()`. Both orgs show `2026/` because both were seeded by
the same function in the same financial year — nothing was ever read
from APC.

**Why this matters beyond one wrong sentence: the test returns the same
symptom for both causes.** Asking "what does a non-APC tenant get on day
one?" yields "the same thing APC has" whether the cause is
tenant-copying or a shared hardcoded default. The symptom cannot
distinguish them. **Confirming an instance therefore requires reading
the seeding path**, not comparing two tenants' rows:

| Cause | Evidence | Fix |
|---|---|---|
| Tenant-copying | seed reads another org's rows | Derive per tenant |
| Shared default | seed has literals in its own body | Make configurable |
| Derived | seed computes from FY/date/org input | **Nothing — correct** |

**Genuine instances of the class:** the CFT catalogue (Item 12) and the
branch dropdown that blocked Ponci from creating any order at all.
**Not an instance:** number-series prefixes (shared default, and the
year portion is correctly derived — see 9.6).

<details><summary>Original wording, wrong, kept for the record</summary>

"Ponci's prefixes are byte-identical to APC's … This is the same class
as the CFT catalogue (Item 12) and the branch dropdown … new-tenant
seeding copies APC's configuration rather than establishing the
tenant's own."
</details>

### 9.5 The seeded year prefix is DERIVED, not a literal — do not "fix" it

Checked because a hardcoded `2026/` would break at the FY boundary
alongside the `roll_over_number_series()` gap (§4). **It is not
hardcoded.** `seed_org_number_series()` does:

```sql
v_fy   := public.current_fy_ist();
v_year := split_part(v_fy, '-', 1);
...
case when d.calendar_prefix then v_year || '/' else d.prefix end
```

and `current_fy_ist()` switches on `month >= 4` in `Asia/Kolkata`. An org
created on 1 April 2027 is seeded `2027/` with no intervention.

**This is NOT part of the FY-rollover gap.** That gap is about EXISTING
orgs having no rows for the next FY; seeding only ever runs at org
creation. Two different problems that both mention prefixes and years —
do not merge them, and do not replace this derivation with a literal.

### 9.6 Orphan rows — verified figures

6 money receipts, 2 tax invoices and 1 proforma were issued on bare,
prefix-less numbers. The 5 rows recording this are all `active = false`
and therefore inert (`next_doc_number` filters on `active`). Full
per-row table in §4.

**A CA question, not cleanup** — it concerns documents customers already
hold and invoices that may have been filed. It should go to the CA
**alongside the pending GSTIN state question** (APC's GSTIN begins `33`
= Tamil Nadu while the org record says Karnataka), since both are
invoice-compliance questions for the same adviser and the GSTIN answer
also unblocks the GST step-1 migration.

---

## 10. Tenancy model — an ORG per state, not a branch per state

**Structural correction from Arun, 27 Aug 2026. This resolves several
open items at once and cancels one piece of planned work.**

**The model is ORG-PER-LOCATION. There are no branches in it.**

Every location is its own org: Tamil Nadu, Karnataka and Andhra — and
**Bengaluru and Mysuru too**. Separate staff, vehicles, accounts and
orders, and a **separate licence purchase each**. Only the owner is
shared. Any new location is a new org, never a new branch.

> **Corrected twice on 27 Aug 2026, and the second correction matters.**
> An earlier version of this section said "branches mean multiple
> locations WITHIN one org, sharing staff and accounts." That was still
> wrong: it left branches as a real, if narrower, hierarchy. They are
> not one. Two locations never share staff or accounts, whatever their
> distance apart.

### 10.0 `branches` is VESTIGIAL — an FK target, not a hierarchy

**Anyone reading `branches` as a user-facing hierarchy is reading it
wrong.** It survives for one reason: it is a live FK target. 22 tables
carry a `branch` value under a composite FK
`(org_id, branch) -> branches(org_id, name)`, and `orders.branch` /
`staff.branch` hold that literal string.

The steady state is **exactly one row per org** — the `Head Office` seed
from `20260827_branches_management.sql`. That migration is still
correct and still needed: without a branch row the FKs cannot be
satisfied and no order, lead or staff member can be created.

Consequences, all deliberate:
- **No "Branches" entry in Settings.** Removed 27 Aug 2026 — a card
  there would teach the wrong model to every vendor who opened it.
- `BranchesPage` **still exists and is still routed**, reachable from
  New Order's zero-branch empty state and by direct URL. Kept as a
  recovery path, not navigation. Renaming is cosmetic at one row per
  org; a SQL `update` covers the rare real need.
- **`branches.gstin` and `branches.state_code` are DEAD COLUMNS.**
  Never populate them. GSTIN is **org-level** — under org-per-location
  each registration belongs to its own org, so a branch-level GSTIN has
  no meaning. They were added by `20260825_branches_table.sql` before
  this model was settled. **Deliberately NOT dropped:** a tracker line
  prevents the misreading, while a migration is irreversible for no
  gain.
- Item 30's `branch_isolation` policies still function, but have
  nothing to isolate at one branch per org. Do not extend them.

### 10.1 What this resolves

- **The GSTIN 33 / Karnataka contradiction is RESOLVED — not a data
  error.** `33` is Tamil Nadu, and that GSTIN belongs to the **Tamil Nadu
  org**. The Karnataka org simply has no GSTIN yet. Nothing to reconcile
  and nothing to ask the CA about on this specific point.
  **This unblocks GST step 1** (`20260825_gst_treatment_and_display.sql`
  is still unrun, but the question that was holding it is answered).
  Note the orphan-row question in section 9.6 is a **separate** CA item
  and is still open.
- **GSTIN stays ORG-LEVEL.** Do not move it to `branches`.
  `branches.gstin` and `branches.state_code` (added by
  `20260825_branches_table.sql`) have **no role in this model** and are
  written by nothing. Candidates for removal; left in place because
  dropping columns is a decision, not a cleanup.
- **State-to-state isolation comes from `org_isolation`, which works
  today.** It was never branch RLS's job.

### 10.2 What this CANCELS — do not build it

**Per-GSTIN branch serials under Rule 46(b) are MOOT.** CLAUDE.md's
NG-010 note says that if branches acquire their own GSTINs, invoice
serials must become per-GSTIN by passing `p_branch` through the
allocator at six call sites. Under an org-per-state model
`number_series` is **already** org-scoped, so separate registrations get
separate serials for free. **Do not implement branch-aware allocation.**
The NG-010 rule that `number_series` must never get a `branch_isolation`
policy still stands, and is now doubly true.

### 10.3 Branch RLS Tier 2 — CANCELLED

Superseded by the second correction above. Item 30's
`branch_isolation` policies are field-verified and still function, but
with **one branch per org they have nothing to isolate** — every row in
an org shares its single branch value. Isolation between locations is
`org_isolation`, which works today.

**Do not build Tier 2.** (An earlier version of this section said Tier 2
was merely "re-scoped" to within-org branches. There are no within-org
branches.)

### 10.4 Multi-org: switching WORKS, creating DOES NOT

The owner needs to move between three orgs without logging out.

**Switching is built and complete.** `showOrgSwitcherSheet`
(`lib/components/org_switcher_sheet.dart`) surfaces in Settings gated on
`availableOrgs.length > 1`, and at login when a user belongs to more
than one. `main.dart`'s restore builds `memberOrgIds` as a Set and
validates `LastSelectedOrg` against it, so cold-start restore across
several orgs is correct. No logout required.

**Creating a second org is BLOCKED, and this is now on the critical
path.** `create_org_with_owner()` begins:

```sql
select om.org_id, om.role into v_existing
  from public.org_members om where om.user_id = p_user_id
  order by om.created_at asc limit 1;
if found then
  return query select false, ...   -- returns the EXISTING org
  return;
end if;
```

A user who already belongs to **any** org gets that org handed back with
`is_new = false`, and nothing is created. So the owner **cannot create
org #2 or #3 through signup.**

That early return is **not a bug** — it is the "confirmed but no org
yet" recovery path `vendor_org_resolver.dart` depends on, and removing
it would strand signups. The fix is to separate *recover my existing
org* from *deliberately create another*, which needs an explicit flag
and its own task. **Not attempted inside branch management.**

**Nothing here has ever run against real data:** all 6 users currently
hold exactly one membership each (verified `org_members`), so every
multi-org path — picker, switcher, restore — is **untested in the
field**. Expect to find defects when the owner's second org exists.

### 10.5 GSTIN entry rules — RECORD ONLY, not built

Same free-then-locked shape as the prefix rule in section 9.3:

- **Optional at registration.** A new org may have no GSTIN yet — the
  Karnataka org is exactly that case, and forcing one would make a
  vendor invent a value.
- **Validated on entry:** 15 characters, and the **first two digits must
  match the org's state code**. That is the check that would have caught
  the `33`-vs-Karnataka pairing at the point of entry rather than months
  later.
- **Locked once the org has issued its first GST invoice.** Changing a
  GSTIN after invoices carry it re-attributes filed documents to a
  different registration. Editable before that, frozen after — with the
  same "changeable at FY rollover" escape hatch the prefix rule uses if
  a genuine re-registration happens.

---

## 11. Recommended next

1. **Run the device-register migration** (§3) — inert, zero-risk, off the
   critical path once done.
2. **Decide Ponci's trial extension before 30 Aug** (§6) — three days.
   Otherwise the only fresh-tenant test org goes read-only.
3. ~~**`flutter pub get` + `flutter analyze`**~~ — **DONE 27 Aug 2026.**
   0 errors, 177 issues (the untouched baseline). Cleared the
   localisation work *and* the LastSelectedOrg change, compiler-unverified
   across three sessions until now. Found and fixed one defect: the
   reserved-word ARB key (§8).
4. **Branch-management screen** — named as the blocker for fresh-tenant
   testing. **Next task.**
5. **NG-005 privacy policy + terms** — small, unblocks Play Store and
   Meta review.
6. **`roll_over_number_series()`** — December 2026 (§4).
