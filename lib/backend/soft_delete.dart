import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';

/// Soft delete, app-wide (live-test fix brief #2, item 11).
///
/// Nothing is ever hard-deleted from here. Every entity carries
/// `deleted_at` / `deleted_by` / `delete_reason`; deleted rows vanish from
/// lists but stay in the database, because (a) accidental deletes must be
/// recoverable, (b) GST and financial records must be retained by law, and
/// (c) a hard delete would cascade into payments, salary ledger and P&L
/// history.
///
/// **The read side is the risky half.** Every list/KPI/report query must
/// also filter `deleted_at is null` — see [OrgScope.read], which now
/// applies that filter for the tables that have the column, so a new query
/// is safe by default rather than by remembering.

/// Tables that carry the soft-delete columns (per the 28 Jul migration).
/// [OrgScope.read] consults this to decide whether to append the filter.
const Set<String> kSoftDeleteTables = {
  'leads',
  'quotations',
  'orders',
  'payment_entries',
  'expenses',
  'materials',
  'vehicles',
};

/// Outcome of a delete guard — mirrors `can_delete_order()`'s return shape.
/// Not a bool, so the UI can explain *why* and offer the right alternative
/// rather than just greying out a button.
class DeleteCheck {
  const DeleteCheck({
    required this.allowed,
    this.reason,
    this.alternative,
  });

  final bool allowed;
  final String? reason;

  /// 'mark_lost' | 'cancel_order' | 'deactivate' | 'supersede'
  final String? alternative;

  static const allow = DeleteCheck(allowed: true);
}

class SoftDeleteService {
  /// Owner-only actions (orders, payments, staff). Staff PIN sessions have
  /// a currentStaffId; the owner does not — same convention as the rest of
  /// the app's role gating.
  static bool get isOwner => AppSession.instance.currentStaffId == null;

  // ---- Guards ------------------------------------------------------------

  /// Order deletion is checked SERVER-side via `can_delete_order()`, not
  /// here, so the UI can't be the only thing enforcing it (item 11.3).
  static Future<DeleteCheck> canDeleteOrder(String orderId) async {
    if (!isOwner) {
      return const DeleteCheck(
        allowed: false,
        reason: 'Only the owner can delete an order.',
      );
    }
    try {
      final res = await SupaFlow.client
          .rpc('can_delete_order', params: {'p_order_id': orderId});
      final row = (res is List && res.isNotEmpty)
          ? Map<String, dynamic>.from(res.first as Map)
          : (res is Map ? Map<String, dynamic>.from(res) : null);
      if (row == null) {
        return const DeleteCheck(
            allowed: false, reason: 'Could not verify this order.');
      }
      return DeleteCheck(
        allowed: row['allowed'] == true,
        reason: row['reason'] as String?,
        alternative: row['alternative'] as String?,
      );
    } catch (e) {
      // Fail CLOSED. A guard that can't be evaluated must not be treated
      // as permission — this one protects GST records.
      return DeleteCheck(
        allowed: false,
        reason: 'Could not verify whether this order can be deleted: $e',
      );
    }
  }

  /// A lead already converted to an order can't be deleted — "Lost" is the
  /// honest state, and the order still references it.
  static Future<DeleteCheck> canDeleteLead(String leadId) async {
    try {
      final orders = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('lead_id', leadId),
      );
      if (orders.isNotEmpty) {
        return const DeleteCheck(
          allowed: false,
          reason: 'This lead has already been converted to an order.',
          alternative: 'mark_lost',
        );
      }
      return DeleteCheck.allow;
    } catch (e) {
      return DeleteCheck(
          allowed: false, reason: 'Could not verify this lead: $e');
    }
  }

  /// A signed quote is a record of what the customer agreed to; a
  /// converted one is referenced by an order. Neither may be deleted.
  static Future<DeleteCheck> canDeleteQuote(String quoteId) async {
    try {
      final sigs = await SupaFlow.client
          .from('document_signatures')
          .select('status')
          .eq('document_type', 'quote')
          .eq('document_id', quoteId)
          .eq('status', 'signed')
          .limit(1);
      if (sigs.isNotEmpty) {
        return const DeleteCheck(
          allowed: false,
          reason: 'This quote has been signed by the customer.',
          alternative: 'supersede',
        );
      }
      final orders = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('quotation_id', quoteId),
      );
      if (orders.isNotEmpty) {
        return const DeleteCheck(
          allowed: false,
          reason: 'This quote has already been converted to an order.',
          alternative: 'supersede',
        );
      }
      return DeleteCheck.allow;
    } catch (e) {
      return DeleteCheck(
          allowed: false, reason: 'Could not verify this quote: $e');
    }
  }

  // ---- Mutations ---------------------------------------------------------

  /// Marks a row deleted and writes an audit entry.
  ///
  /// [reason] is mandatory for orders and payment entries per the brief;
  /// that is enforced at the call site (the dialog won't submit without
  /// one) rather than here, so this stays reusable.
  static Future<void> softDelete({
    required String table,
    required String id,
    String? reason,
  }) async {
    assert(kSoftDeleteTables.contains(table),
        '$table has no soft-delete columns — see the 28 Jul migration.');
    await SupaFlow.client
        .from(table)
        .update({
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
          'deleted_by': SupaFlow.client.auth.currentUser?.id,
          'delete_reason': reason,
        })
        .eq('id', id)
        .eq('org_id', AppSession.instance.currentOrgId!);
    await _audit(
      entityType: table,
      entityId: id,
      action: 'delete',
      reason: reason,
    );
  }

  /// Undo, and the recycle bin's Restore.
  static Future<void> restore({
    required String table,
    required String id,
  }) async {
    await SupaFlow.client
        .from(table)
        .update({
          'deleted_at': null,
          'deleted_by': null,
          'delete_reason': null,
        })
        .eq('id', id)
        .eq('org_id', AppSession.instance.currentOrgId!);
    await _audit(entityType: table, entityId: id, action: 'restore');
  }

  /// Soft-deleted rows from the last [days] days, newest first — backs the
  /// owner-only recycle bin.
  static Future<List<Map<String, dynamic>>> recycleBin({
    required String table,
    int days = 90,
  }) async {
    final since = DateTime.now().toUtc().subtract(Duration(days: days));
    final rows = await SupaFlow.client
        .from(table)
        .select()
        .eq('org_id', AppSession.instance.currentOrgId!)
        .not('deleted_at', 'is', null)
        .gte('deleted_at', since.toIso8601String())
        .order('deleted_at', ascending: false);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  static Future<void> _audit({
    required String entityType,
    required String entityId,
    required String action,
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
        // wouldn't identify who acted.
        'actor_name': AppSession.instance.currentStaffName ?? 'Owner',
        'reason': reason,
      });
    } catch (_) {
      // Never fail the delete because the audit row didn't write — the
      // delete is recoverable either way, and blocking it would be worse.
    }
  }
}
