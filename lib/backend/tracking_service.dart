import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';

/// Order tracking helpers (live-test fix brief #2, item 6).
///
/// The public tracking page reads through the `track-order` Edge Function;
/// everything here is the staff side, running under a real session, so it
/// goes direct to the org-scoped tables.
class TrackingService {
  /// The order's `tracking_token`, or null if the order has none (i.e.
  /// the 28 Jul migration hasn't run).
  static Future<String?> tokenForOrder(String orderId) async {
    final rows = await OrdersTable().queryRows(
      queryFn: (q) => OrgScope.read(q).eq('id', orderId),
    );
    if (rows.isEmpty) return null;
    final token = rows.first.trackingToken;
    return (token == null || token.isEmpty) ? null : token;
  }

  /// Records a status change on the customer-visible timeline.
  ///
  /// Call this from EVERY place that changes an order's status or
  /// tracking_status. It deliberately does not itself write to `orders` —
  /// the caller owns that update — so this can be dropped in next to an
  /// existing update without changing its semantics.
  ///
  /// Best-effort by design: a history-write failure must never abort the
  /// status change the user actually asked for. The timeline degrades to
  /// missing a timestamp; the order stays correct.
  static Future<void> logStatus({
    required String orderId,
    required String status,
    String? note,
  }) async {
    try {
      await SupaFlow.client.from('order_status_history').insert({
        ...OrgScope.stamp(),
        'order_id': orderId,
        'status': status,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        // Staff PIN sessions have no auth user of their own; null is fine
        // and the column is nullable.
        'changed_by': SupaFlow.client.auth.currentUser?.id,
      });
    } catch (_) {
      // Swallowed on purpose — see doc comment.
    }
  }

  /// Convenience: update the order's status AND log it in one call, so a
  /// caller can't accidentally do one without the other.
  static Future<void> setStatus({
    required String orderId,
    String? status,
    String? trackingStatus,
    String? note,
  }) async {
    final data = <String, dynamic>{
      if (status != null) 'status': status,
      if (trackingStatus != null) 'tracking_status': trackingStatus,
    };
    if (data.isNotEmpty) {
      await OrdersTable().update(
        data: data,
        matchingRows: (q) => OrgScope.write(q).eq('id', orderId),
      );
    }
    await logStatus(
      orderId: orderId,
      // Prefer the customer-facing value on the timeline when both moved.
      status: trackingStatus ?? status ?? 'updated',
      note: note,
    );
  }

  /// Whether the current session may see crew details on the public page
  /// — mirrored here only for the in-app settings toggle; the RPC is the
  /// real gate.
  static bool get isOwnerSession => AppSession.instance.currentStaffId == null;
}
