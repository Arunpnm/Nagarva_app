# Claude Code Kickoff — Tier 2, Session 2: Supervisor OTP Completion Flow

**Repo:** `Arunpnm/Nagarva_app` · **DB:** `hqqcapifefsaqvotqvlt` (001–007 applied)
**Reference:** `nagarva_master_parity_brief.md` §6.4 — **with the corrections below, which override it**
**Scope:** the supervisor's job-completion path and the `job_team` → `order_staff` propagation bug.

---

## Schema corrections to the master brief

Verified against `supabase/schema_snapshot_2026-08-01.csv`. The brief was written from APC's source and is wrong in two places.

| Brief says | Reality |
|---|---|
| `orders.start_km` gates the completion button | **No such column.** Odometer lives in `vehicle_trips.km_start` / `km_end`, keyed by `order_id`. |
| OTP writes only to `orders` | `pod_records` exists with `otp_verified`, `signature_data`, `photo_urls`, `packages_delivered`, `packages_short`, `damage_noted`, lat/lng. **The OTP flow should create a POD record.** Neither brief caught this. |

### What actually exists on `orders`

`supervisor_id` · `supervisor_status` · `supervisor_notes` · `job_otp` · `job_team` · `job_start_time` · `job_end_time` · `vehicle_no` · `vehicle_id` · `driver_name` · `driver_phone` · `third_party_vehicle` · `distance_km` · plus the full stage timestamp set including `delivered_at` and `closed_at`.

### Related tables

- **`order_staff`** — `order_id`, `staff_id`, `salary_amount`, `is_half_day`, `team_type`. The real crew table.
- **`vehicle_trips`** — `order_id`, `km_start`, `km_end`, `fuel_amount`, `toll_amount`, `driver_bata`, `trip_date`.
- **`pod_records`** — proof of delivery, links to `lr_id` and `order_id`.
- **`order_status_history`** — `order_id`, `status`, `note`, `changed_at`, `changed_by`.
- **`attendance`** — `staff_id`, `attendance_date`, `status`, `marked_by`.

---

## Part A — Fix the `job_team` → `order_staff` bug first

**This is a known open item and it blocks everything else in this session.**

`orders.job_team` is written when a supervisor assembles a crew. It never propagates to `order_staff`. Consequence: attendance and salary both require manual re-entry of the same names, and the P&L's Staff Salary line reads from `order_staff`, so it under-reports on every job where the crew was set through `job_team`.

**Required:**

1. Inspect `job_team`'s actual shape before writing anything — likely a jsonb array of staff ids or names. Report what you find.
2. On write of `job_team`, upsert matching `order_staff` rows: `order_id`, `staff_id`, `team_type`, `salary_amount` defaulting to the staff member's `staff.salary`, `is_half_day` false.
3. Removing someone from `job_team` deletes their `order_staff` row **only if `salary_amount` is still the untouched default** — never silently discard an edited salary.
4. Back-fill existing orders where `job_team` is populated and `order_staff` is empty. Hand me a migration for this; do not run it yourself.

Until this works, the OTP flow has no reliable crew list to stamp attendance against.

---

## Part B — Supervisor job screen

A distinct screen, not a button. Entered from the supervisor's `sup-jobs` nav item.

### B1. My Jobs list

Query: `orders` where `supervisor_id = <current staff id>` and `status not in ('closed','cancelled')`.

Card per job: order id, customer, route, date, current stage, and a status badge —
- `⏳ Awaiting` (gold) when `supervisor_status = 'completed_pending'`
- otherwise the current stage label

Tapping a job opens the detail below.

### B2. Job detail — before completion

Shows route, addresses, date, crew from `order_staff`, vehicle and driver.

Two actions available before completion:
- **Field expenses** — append to `orders.field_expenses`. Shape is pinned by migration 007: `[{"type": text, "amount": numeric, "note": text, "at": date}]`. Twelve types per master brief §6.3.
- **Start job** — stamps `orders.job_start_time` if not already set.

### B3. Closing odometer

Reads and writes `vehicle_trips` for this `order_id`, **not** `orders`.

- If no `vehicle_trips` row exists, create one on first save with `km_start`.
- Closing reading writes `km_end`.
- **`🏁 Shifting Completed — Get OTP` is disabled while `km_start` is set and `km_end` is empty.** This is the brief's gate, corrected to the right table.
- If `km_start` was never captured, do not block — the vehicle may be third-party.

### B4. OTP generation

1. Tap generates a **4-digit** code, writes `orders.job_otp`, toasts `OTP: {code} — Ask customer to confirm`.
2. Render at 48px, letter-spacing 8, monospace, accent colour.
3. Customer reads it aloud; supervisor types it into a 4-digit field.
4. Border: red on mismatch, green at 4 characters, neutral otherwise.
5. Mismatch → `❌ Wrong OTP. Try again.` **No write of any kind.**

The OTP is proof of delivery. It must not be skippable by the supervisor.

### B5. On correct OTP — one transaction

1. `orders.supervisor_status = 'completed_pending'`
2. `orders.supervisor_notes` from the notes field
3. `orders.job_end_time = now()`
4. If status not already `delivered`/`closed` → advance to `delivered`, stamp `delivered_at`
5. Insert `order_status_history`: status `delivered`, note `Completed by supervisor, OTP verified`, `changed_by` = supervisor
6. **Insert `pod_records`** — `order_id`, `otp_verified: true`, `delivered_at`, `captured_by`, `received_by_name` + `received_by_phone` if captured, `packages_delivered`, `packages_short`, `damage_noted` + `damage_description`, `photo_urls`, lat/lng if permission granted, and `lr_id` where the order has one
7. Mark `attendance` present for each `order_staff` member for that date, `marked_by` = supervisor, if not already marked
8. `audit_log` entry with before/after
9. Toast `🎉 Job complete! Awaiting owner approval.`

Steps 6 and 7 are additions to the master brief. POD capture is why `pod_records` exists, and attendance is the thing supervisors currently re-key by hand.

### B6. After completion

Job card shows `⏳ Awaiting`. Supervisor can no longer edit the odometer or regenerate the OTP. Field expenses stay editable until the owner closes the order.

Owner then closes it via `🔒 Close Order` on Order Detail — already built in Session 1, stamps `closed_at`.

---

## Part C — Supervisor's other screens

Thin, but they complete the nav set built in Tier 1. Currently `ComingSoonPage` stubs.

| Route | Content |
|---|---|
| `sup-entry` (Job Entry) | Create an order from the field — minimal form: customer, phone, route, date, service. Calls the same `findOrCreateCustomer` helper as Quick Payment. |
| `sup-team` (My Team) | `staff` where branch matches, with today's attendance state and a mark-present action. |
| `sup-sal` (My Earnings) | This supervisor's `order_staff` rows with salary, grouped by month; plus `staff_advances` balance. |
| `sup-att` (My Attendance) | This supervisor's own `attendance` rows, month calendar view. |

If any of these is larger than it looks, build `sup-jobs` properly and report the rest rather than rushing them.

---

## Permissions

- Supervisor reaching Order Detail must still see **no P&L card and no salary figures** — Tier 1 gating already handles this; confirm it holds on the new screens.
- `sup-*` routes are supervisor-only. The Tier 1 route guard should already bounce others; verify.
- A supervisor must not be able to set their own salary, delete orders, or view reports.

---

## Constraints

- Complete file replacements
- `orders.id` is TEXT — `::text` casts on joins
- All queries through `current_org_ids()`
- Every write to `audit_log` with `old_value` / `new_value` / `changed_fields`
- **No SQL execution.** If schema changes are needed, hand me a migration file — including the Part A back-fill.
- `flutter analyze` clean before each commit

---

## Acceptance criteria

- [ ] `job_team` shape reported before any code written
- [ ] `job_team` writes propagate to `order_staff`
- [ ] Removal does not discard an edited `salary_amount`
- [ ] Back-fill migration handed over, not run
- [ ] My Jobs lists only this supervisor's open orders
- [ ] `⏳ Awaiting` badge shows on `completed_pending`
- [ ] Odometer reads/writes `vehicle_trips`, not `orders`
- [ ] Completion button disabled when `km_start` set and `km_end` empty
- [ ] Not blocked when `km_start` was never captured
- [ ] 4-digit OTP generated, written to `job_otp`, rendered at 48px
- [ ] Wrong OTP writes nothing
- [ ] Correct OTP performs all nine steps in one transaction
- [ ] `pod_records` row created with `otp_verified = true`
- [ ] Attendance marked for every crew member
- [ ] `order_status_history` entry written
- [ ] Odometer and OTP locked after completion; field expenses stay open
- [ ] Owner's Close Order stamps `closed_at`
- [ ] Supervisor sees no P&L or salary anywhere
- [ ] `sup-*` routes bounce non-supervisors

---

## Report back

1. `job_team`'s actual shape, and how many existing orders need back-filling
2. Files replaced
3. Whether `vehicle_trips` or the newer `trips` table is the right home for odometer readings long-term — `vehicle_trips` is 1:1 with an order, `trips` is many-orders-per-vehicle. Recommend which, don't migrate.
4. Anything in Part C that turned out larger than a thin screen
