import 'package:flutter/foundation.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';

/// Unreviewed customer_surveys count for the Surveys nav badge (Session 4,
/// Part B1) — same ValueNotifier-singleton pattern as ApprovalQueue
/// (backend/approval_queue.dart), for the same reason: the count is read
/// from two nav render sites that don't share a widget subtree (the
/// sidebar rail and the mobile bottom nav, both in main.dart) and
/// invalidated from a third (the surveys list itself, on review/convert/
/// discard).
class SurveyQueue {
  SurveyQueue._();

  static final SurveyQueue instance = SurveyQueue._();

  /// customer_surveys rows with status = 'submitted' — filled in by the
  /// customer, not yet reviewed by staff. 0 until the first [refresh].
  final ValueNotifier<int> unreviewedCount = ValueNotifier<int>(0);

  Future<void> refresh() async {
    if (OrgScope.currentOrgId == null) {
      unreviewedCount.value = 0;
      return;
    }
    try {
      final rows = await CustomerSurveysTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('status', 'submitted'),
      );
      unreviewedCount.value = rows.length;
    } catch (_) {}
  }
}
