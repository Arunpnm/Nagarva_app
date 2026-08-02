import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';

/// Reconciles `order_staff` against `orders.job_team` — Session 2 Part A.
///
/// `job_team` (jsonb array of `staff.id` strings, written by the
/// supervisor's field job screen when picking a crew) never propagated to
/// `order_staff` — the real crew table `order_crew_section.dart` and the
/// P&L card's Staff Salary line both read from. Consequence: attendance
/// and salary needed manual re-entry, and every job crewed only through
/// `job_team` under-reported its labour cost. This is the fix, called
/// every time `orders.job_team` is written.
class CrewSyncService {
  CrewSyncService._();

  /// Day-rate default for a job-team addition — staff.salary / 26,
  /// rounded. Matches order_crew_section.dart's own "Add Labour" dialog
  /// exactly, so a crew member picked via the field job screen gets the
  /// same suggested per-job rate as one added by the owner directly.
  static double _dayRate(double? monthlySalary) =>
      monthlySalary == null ? 0 : (monthlySalary / 26).roundToDouble();

  /// Call this immediately after any write to `orders.job_team`.
  ///
  /// Adds an `order_staff` row (team_type 'labour', is_half_day false,
  /// salary_amount defaulted to [_dayRate]) for every staff id in
  /// [teamIds] that doesn't already have one for this order.
  ///
  /// Removes an existing `order_staff` row for a staff id no longer in
  /// [teamIds] — but ONLY when its `salary_amount` still exactly matches
  /// that staff member's current day-rate default. A row whose salary was
  /// hand-edited (by the owner in Order Details, or by a supervisor
  /// override) is left in place rather than silently discarded — per
  /// Part A's explicit instruction, an edited salary is a human decision
  /// this sync must not overwrite just because the crew list changed.
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

    final relevantStaffIds = {...toAdd, ...toConsiderForRemoval.map((e) => e.key)};
    final staffRows = await StaffTable().queryRows(
      queryFn: (q) =>
          OrgScope.read(q, orgId: orgId).inFilter('id', relevantStaffIds.toList()),
    );
    final staffById = {
      for (final s in staffRows)
        if (s.id != null) s.id!: s
    };

    for (final id in toAdd) {
      await OrderStaffTable().insert({
        ...OrgScope.stamp(orgId: orgId),
        'order_id': orderId,
        'staff_id': id,
        'salary_amount': _dayRate(staffById[id]?.salary),
        'is_half_day': false,
        'team_type': 'labour',
      });
    }

    for (final entry in toConsiderForRemoval) {
      final row = entry.value;
      final defaultRate = _dayRate(staffById[entry.key]?.salary);
      final untouched = (row.salaryAmount ?? 0) == defaultRate;
      if (untouched && row.id != null) {
        await OrderStaffTable().delete(
          matchingRows: (q) =>
              OrgScope.write(q, orgId: orgId).eq('id', row.id!),
        );
      }
      // else: a hand-edited salary survives being dropped from job_team —
      // the owner reconciles it manually via Team & Salary, same as any
      // other order_staff row not sourced from job_team at all.
    }
  }
}
