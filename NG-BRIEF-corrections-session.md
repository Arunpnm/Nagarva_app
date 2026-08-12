# Corrections session brief

**For:** Claude Code
**Scope:** Accumulated small divergences and known-wrong code. No new modules.
**Why now:** these are all things Accounts depth will sit on top of. Clearing them first is
cheaper than working around them later.

> **Verify before editing.** File paths, line numbers and column names below come from earlier
> session reports, not from reading the current tree. Introspect the live schema and the actual
> files first. Where this brief and the code disagree, follow the code and say so.

**Commit separately per item.** If one turns out to be wrong or contested, the others still ship.

---

## A. Schema corrections — one migration, Arun reviews and runs

### A1. `customer_surveys.converted_to_order_id` type mismatch

The column is `uuid`; `orders.id` is `text`. The join is impossible as written.

Before writing anything: report how many rows have a non-null value, and whether any of those
values correspond to a real `orders.id`. If existing values are orphaned uuids that never
matched an order, say so — they should be nulled rather than cast into garbage text.

Expected shape (verify the constraint name against `pg_constraint` first):

```sql
alter table customer_surveys
  drop constraint if exists customer_surveys_converted_to_order_id_fkey;

alter table customer_surveys
  alter column converted_to_order_id type text
  using converted_to_order_id::text;

alter table customer_surveys
  add constraint customer_surveys_converted_to_order_id_fkey
  foreign key (converted_to_order_id) references orders(id) on delete set null;
```

Check whether an FK existed at all before assuming it did.

### A2. Soft-delete column uniformity on `trips` and `tasks`

`vendors`, `vendor_bills`, `vendor_payments`, `customers` carry the full
`deleted_at` / `deleted_by` / `delete_reason` triple. `trips` and `tasks` carry only
`deleted_at`, so `SoftDeleteService.softDelete` would throw against them — which is why they
were left out of `kSoftDeleteTables` with a doc comment instead.

Add the two missing columns to both tables so the schema is uniform and the service has one
contract rather than two.

**Separate the schema fix from the product decision.** Adding the columns does not commit
anyone to using soft-delete as the user-facing retire action for trips and tasks — the status
flip to `cancelled` may well remain the right UX. Add the columns; do **not** add these tables
to `kSoftDeleteTables` in this session. Flag the UX question to Arun and leave it for him.

---

## B. Dart corrections

### B1. Entity picker — stop writing blank `entity_id`

Tasks & Activities currently offers a real picker only for `entity_type: 'order'`. Lead,
customer and vendor are selectable but leave `entity_id` null, producing rows that can never
be joined or filtered.

Generalise `OrderPickerDialog` into an `EntityPickerDialog` that takes a table name, a display
column, an optional subtitle column and a search column, then wire all four entity types
through it. One dialog, four configurations.

If that turns out to be more than a couple of hours, do the interim guard instead — constrain
the entity-type dropdown to `order` only — and say why. Unjoinable rows accumulating is worse
than a temporarily reduced dropdown.

### B2. Notifications recipient filtering — investigate before changing

`NotificationBell` fetches the last 30 `notifications` rows for the org, then filters
client-side to the current session (`recipient_staff_id == currentStaffId`, or `== null` for
owner/vendor).

**First, answer this question and report it before touching anything:** do staff PIN sessions
each have their own Supabase auth user, or do all staff in an org share a single auth identity
with the staff layer handled in-app?

- **Separate auth users** → the client-side filter is a real data-exposure issue: staff can
  read colleagues' notification rows off the wire. Move the recipient predicate into the query
  *and* into the RLS policy.
- **Shared auth identity** → RLS cannot distinguish staff members at all, the client-side
  filter is the only mechanism available, and this is not a leak. In that case document it in
  the file's doc comment and change nothing.

Do not guess which it is. This determines whether B2 is a security fix or a non-issue.

### B3. Fake stat cards — two pages

Both are hardcoded FlutterFlow placeholder strings that never read their model.

- `fleet_page_widget.dart:177-401` — "4 Active / 2 Idle / 1 Service" should be computed from
  `_model.vehiclesList` by status.
- `leads_page_widget.dart` — the funnel cards (New / Contacted / Qualified / Won) should be
  computed from `_model.leadsList` by status.

Match each page's existing status vocabulary rather than inventing labels.

### B4. `WaMessagesRow.contactId` nullable force-unwrap

Force-unwraps a column that is genuinely nullable in the database. Harmless today only because
nothing reads `.contactId` — the first feature that touches it crashes. Make it nullable-safe.

### B5. Survey CFT stepper touch targets

`survey_quote_page_widget.dart:1030` and `:1046` — increase to 48×48 minimum. Outstanding
since before the last APK build.

---

## C. Gate

`flutter analyze` clean against the existing 164-issue baseline, zero new errors, before each
commit. As established: clean analyze is necessary and not sufficient — string-keyed lookups
and layout violations both pass it.

Device verification is Arun's. List explicitly what needs tapping.

---

## D. Not in this session — Arun's queue

Listed here so nothing is lost, not for Claude Code to act on.

1. **Migrations 011 and 012** — written but never reviewed or run.
2. **`create-org` hardening step 4** — dropping direct INSERT policies for `authenticated`,
   pending device signup confirmation.
3. **Fleet and Staff hang** — after the Materials `Flexible`/`InkWell` fix, confirm on device
   whether these two still hang. If they do, capture `flutter run > D:\run.log 2>&1` for each
   and read the error-causing widget line; it is likely the same class of violation in a
   different place.
4. **Test data wipe** — should happen before Accounts depth lands, so the GL has no backfill
   problem. Delete transactional rows in dependency order; leave org, staff, rate cards and
   auth users alone. Have the truncate script written and reviewed like any migration.
