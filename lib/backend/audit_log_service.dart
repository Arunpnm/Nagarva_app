import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';

/// Shared `audit_log` writer for Order Details Session 1's writes — Quick
/// Payment, Duplicate Order, LR/Bilty, Mark Order Complete. The kickoff
/// brief is explicit: "Every write logs to audit_log with old_value /
/// new_value / changed_fields (columns added in migration 005)".
///
/// `SoftDeleteService` already has its own private `_audit()` writing the
/// pre-005 columns (entity_type/action/actor/actor_name/reason) for
/// delete/restore specifically — this is the general-purpose sibling for
/// everything else, using the fuller migration-005 shape.
class AuditLogService {
  AuditLogService._();

  /// Never throws — an audit row failing to write must not block the
  /// write it's describing (same rationale as SoftDeleteService's
  /// `_audit`), since the real data change already committed by the time
  /// this is called.
  static Future<void> log({
    required String entityType,
    required String entityId,
    required String action,
    Map<String, dynamic>? oldValue,
    Map<String, dynamic>? newValue,
    List<String>? changedFields,
    String? reason,
  }) async {
    try {
      await AuditLogTable().insert({
        ...OrgScope.stamp(),
        'entity_type': entityType,
        'entity_id': entityId,
        'action': action,
        'actor': SupaFlow.client.auth.currentUser?.id,
        // Staff PIN sessions share the org's auth user, so the uid alone
        // wouldn't identify who acted — same rationale as
        // SoftDeleteService's _audit.
        'actor_name': AppSession.instance.currentStaffName ?? 'Owner',
        'actor_role': AppSession.instance.currentStaffRole ??
            (AppSession.instance.currentStaffId == null ? 'owner' : null),
        if (oldValue != null) 'old_value': oldValue,
        if (newValue != null) 'new_value': newValue,
        if (changedFields != null) 'changed_fields': changedFields,
        'reason': reason,
      });
    } catch (_) {}
  }
}
