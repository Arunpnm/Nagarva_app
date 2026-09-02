import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';

/// Reconciles `order_staff` against `orders.job_team` — Session 2 Part A.
///
/// `job_team` (jsonb array of `staff.id` strings, written by the
/// supervisor's field job screen when picking a crew) never propagated to
/// `order_staff` — the real crew table the crew sheet, `order_crew_section
/// .dart` and the P&L card's Staff Salary line all read from. Consequence:
/// attendance and salary needed manual re-entry, and every job crewed only
/// through `job_team` under-reported its labour cost. This is the fix,
/// called every time `orders.job_team` is written.
///
/// **This service adds PEOPLE to a job. It never decides what they earn.**
/// Rows land at `salary_amount: 0` and stay there until a human types a
/// figure on the crew sheet — see [kUnpricedSalary] for why that zero is
/// load-bearing rather than a placeholder.
class CrewSyncService {
  CrewSyncService._();

  /// The wage every synced crew member starts at, and the value that means
  /// "no human has priced this assignment yet".
  ///
  /// This used to be `staff.salary / 26` — a derived day rate. It was
  /// removed 1 Sept 2026 (Arun): **Nagarva is a SaaS product, so no price,
  /// rate or wage field is ever pre-filled or suggested anywhere in the
  /// app.** Rates move by vendor, by city, by job type and by role; the
  /// staff-pay brief §3 is explicit that the pattern "is not reliable
  /// enough to automate", and "an auto-suggested rate the vendor has to
  /// correct on every job is slower than typing the right number once".
  ///
  /// The derivation was worse than merely slow. A wage this service
  /// invented was indistinguishable, in the row and on every screen
  /// reading it, from one the vendor actually decided — so it flowed
  /// straight into the job's labour cost, the P&L card and the settlement
  /// table as though someone had agreed it. A zero is visibly unfinished;
  /// a plausible wrong number is not.
  static const double kUnpricedSalary = 0;

  /// Call this immediately after any write to `orders.job_team`.
  ///
  /// Adds an `order_staff` row (team_type 'labour', is_half_day false,
  /// salary_amount [kUnpricedSalary]) for every staff id in [teamIds] that
  /// doesn't already have one for this order.
  ///
  /// Removes an existing `order_staff` row for a staff id no longer in
  /// [teamIds] — but ONLY when nobody has priced that row yet. A row
  /// carrying a typed wage is left in place rather than silently
  /// discarded: an entered salary is a human decision this sync must not
  /// overwrite just because the crew list changed.
  ///
  /// Note this test got STRICTER when the day rate went away. It used to
  /// compare against the derived rate, so a wage a vendor had genuinely
  /// typed was deleted whenever it happened to equal `salary / 26` — the
  /// one figure most likely to be typed if the old dialog had ever
  /// suggested it. Now only an untouched zero is removable.
  static Future<void> syncFromJobTeam({
    required String orderId,
    required List<String> teamIds,
  }) async {
    final orgId = OrgScope.currentOrgId;
    if (orgId == null) return;

    final existingRows = await OrderStaffTable().queryRows(
      queryFn: (q) => OrgScope.read(q, orgId: orgId).eq('order_id', orderId),
    );
    final existingByStaffId = {
      for (final r in existingRows)
        if (r.staffId != null) r.staffId!: r
    };

    final toAdd =
        teamIds.where((id) => !existingByStaffId.containsKey(id)).toSet();
    final toConsiderForRemoval = existingByStaffId.entries
        .where((e) => !teamIds.contains(e.key))
        .toList();

    if (toAdd.isEmpty && toConsiderForRemoval.isEmpty) return;

    for (final id in toAdd) {
      await OrderStaffTable().insert({
        ...OrgScope.stamp(orgId: orgId),
        'order_id': orderId,
        'staff_id': id,
        'salary_amount': kUnpricedSalary,
        'is_half_day': false,
        'team_type': 'labour',
      });
    }

    for (final entry in toConsiderForRemoval) {
      final row = entry.value;
      final unpriced = (row.salaryAmount ?? 0) == kUnpricedSalary;
      if (unpriced && row.id != null) {
        await OrderStaffTable().delete(
          matchingRows: (q) =>
              OrgScope.write(q, orgId: orgId).eq('id', row.id!),
        );
      }
      // else: a priced row survives being dropped from job_team — the
      // owner reconciles it on the crew sheet, same as any other
      // order_staff row not sourced from job_team at all.
    }
  }
}
