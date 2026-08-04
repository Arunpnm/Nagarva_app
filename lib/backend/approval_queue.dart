import 'package:flutter/foundation.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';

/// Count of jobs a supervisor has finished that the owner hasn't closed yet.
///
/// Exists purely for DISCOVERY. The approval action itself is already built
/// and is not duplicated here: `🔒 Close Order` on Order Details
/// (`order_crew_section._markComplete`) is the approval — owner-only,
/// stamps `closed_at`, and now also writes `supervisor_status = 'approved'`.
/// The gap this closes is that the owner had no way to *learn* a job was
/// waiting: the supervisor's OTP flow sets `completed_pending`, My Jobs
/// shows "⏳ Awaiting", and nothing on the owner's side ever surfaced it.
///
/// A [ValueNotifier] rather than per-page state because the count is read
/// in three places that don't share a widget subtree — the sidebar rail and
/// the mobile bottom nav (both in `main.dart`'s NavBarPage) and
/// OperationsPage's own section header — and is invalidated from a fourth
/// (Close Order, on a pushed route). Prop-drilling that would mean
/// threading a count through NavBarPage into two nav components and back
/// out again.
class ApprovalQueue {
  ApprovalQueue._();

  static final ApprovalQueue instance = ApprovalQueue._();

  /// Orders with `supervisor_status = 'completed_pending'` that are not
  /// already closed/cancelled. 0 until the first [refresh].
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  /// Same filter the OperationsPage section uses, kept here so the badge
  /// and the list can never disagree about what "awaiting" means.
  static PostgrestTransformBuilder awaitingFilter(PostgrestFilterBuilder q) =>
      OrgScope.read(q)
          .eq('supervisor_status', 'completed_pending')
          .neq('status', 'closed')
          .neq('status', 'cancelled');

  /// Best-effort — a failed count must never break nav rendering, so this
  /// leaves the previous value in place rather than throwing or zeroing.
  ///
  /// No explicit logout hook is needed to stop one session's badge leaking
  /// into the next: logging out clears `currentOrgId`, which zeroes the
  /// count here on the next call, and NavBarPage re-seeds on mount anyway
  /// (the nav is unmounted between logout and the next login, so there is
  /// no window in which a stale badge is on screen). Deliberately not
  /// called from `AppSession.clear()` — that would make app_session depend
  /// on this, which depends on OrgScope, which depends back on
  /// app_session.
  Future<void> refresh() async {
    if (OrgScope.currentOrgId == null) {
      pendingCount.value = 0;
      return;
    }
    try {
      final rows = await OrdersTable().queryRows(queryFn: awaitingFilter);
      pendingCount.value = rows.length;
    } catch (_) {}
  }
}
