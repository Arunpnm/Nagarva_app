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
/// also filter `deleted_at is null` — see `SupabaseTable._select()`
/// (table.dart), which now applies that filter for every table in
/// [kSoftDeleteTables], at the one funnel `queryRows`/`querySingleRow`
/// already pass through — not [OrgScope.read] itself (corrected 16 Aug
/// 2026; this comment previously credited OrgScope, which never touched
/// `deleted_at` at all). A new query is safe by default because of table.dart,
/// not because of anything OrgScope does.
///
/// **This is app-layer, not RLS, and that's deliberate, not a gap.** RLS
/// policies do not — and must not — filter `deleted_at`: the recycle bin
/// (`recycle_bin_page.dart`) reads deleted rows directly via
/// [recycleBin], and a policy-level filter would block that read too,
/// same as it blocks everyone else. `_select()` is the correct place for
/// this filter precisely because it's a *read default*, not a hard
/// boundary — the recycle bin is the one caller that needs to opt out,
/// and does, by going around it.

/// Tables that carry the soft-delete columns (per the 28 Jul migration).
/// `SupabaseTable._select()` (table.dart) consults this to decide whether
/// to append the filter.
///
/// Other tables with a live `deleted_at` column that are DELIBERATELY not
/// listed here (checked directly against Postgres 16 Aug 2026 — see
/// CLAUDE.md's Item 11 changelog entry for the full table-by-table audit):
///
/// - `lr_register`, `journal_entries` — MUST NEVER be added. An issued LR
///   is a legal document under the Carriage by Road Act; it gets
///   cancelled with a reason and stays in the register, never deleted.
///   Double-entry corrects by a reversing entry, never by deleting a
///   journal row. If either of these ever needs a "remove this" action,
///   that's a cancel/reversal flow, not `SoftDeleteService.softDelete()`.
/// - `warehouses`, `storage_jobs`, `contracts`, `purchase_orders` — belong
///   to modules not built yet (no page anywhere in `lib/` queries them).
///   Wire soft-delete in when each module actually lands, not before.
/// - `documents` — column exists, but no page anywhere in `lib/` queries
///   this table at all; nothing to wire delete into yet either way.
///
/// `rate_cards`, `tasks`, `trips` were in the same "has live UI, no
/// delete yet" bucket as `documents` until 17 Aug 2026 — now wired in
/// below, per Arun's decision: rate_cards (old cards are referenced by
/// historical quotes, so hard delete would orphan them — same shape as
/// every other table here), tasks (no special handling needed), trips
/// (guarded — see [canDeleteTrip] — a deleted trip must not silently
/// change P&L for a completed order).
const Set<String> kSoftDeleteTables = {
  'leads',
  'quotations',
  'orders',
  'payment_entries',
  'expenses',
  'rate_cards',
  'tasks',
  'trips',
  'materials',
  'vehicles',
  'vendors',
  'vendor_bills',
  'vendor_payments',
  'customers',
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

  /// A payment already folded into an issued Money Receipt, or belonging
  /// to a closed order, may not be deleted — added 16 Aug 2026 alongside
  /// the first delete UI for `payment_entries`.
  static Future<DeleteCheck> canDeletePaymentEntry(
      PaymentEntriesRow entry) async {
    if (entry.receiptId != null) {
      return const DeleteCheck(
        allowed: false,
        reason: 'This payment has already been receipted. Deleting it '
            'would leave that receipt referring to a payment that no '
            'longer exists.',
      );
    }
    try {
      final orders = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', entry.orderId),
      );
      final order = orders.isEmpty ? null : orders.first;
      if ((order?.status ?? '').toLowerCase() == 'closed') {
        return const DeleteCheck(
          allowed: false,
          reason: 'This order is closed and its payment history is locked.',
        );
      }
      return DeleteCheck.allow;
    } catch (e) {
      return DeleteCheck(
          allowed: false, reason: 'Could not verify this payment: $e');
    }
  }

  /// A material still carrying stock is kept out of the recycle bin by
  /// mistake far more easily than a real "delete this SKU" — block it
  /// rather than silently orphan `stock_movements` rows against a vanished
  /// material.
  static Future<DeleteCheck> canDeleteMaterial(MaterialsRow m) async {
    if ((m.quantity ?? 0) != 0) {
      return const DeleteCheck(
        allowed: false,
        reason: 'This material still has stock on hand. Stock it out to '
            'zero first, then delete.',
      );
    }
    return DeleteCheck.allow;
  }

  /// A trip linked to a completed order, or one that already has fuel/
  /// expense entries or a captured vehicle log (odometer/fuel) against
  /// it, may not be deleted — a deleted trip must not silently change
  /// P&L for a job that's already been costed. Added 17 Aug 2026
  /// alongside the first delete UI for `trips`.
  static Future<DeleteCheck> canDeleteTrip(TripsRow trip) async {
    if (trip.id == null) return DeleteCheck.allow;
    try {
      final tripOrders = await TripOrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('trip_id', trip.id!),
      );
      final orderIds =
          tripOrders.map((o) => o.orderId).whereType<String>().toList();
      if (orderIds.isNotEmpty) {
        final orders = await OrdersTable().queryRows(
          queryFn: (q) => OrgScope.read(q).inFilter('id', orderIds),
        );
        final completed = orders.any((o) => const {'delivered', 'closed'}
            .contains((o.status ?? '').toLowerCase()));
        if (completed) {
          return const DeleteCheck(
            allowed: false,
            reason: 'This trip is linked to a completed order. Deleting it '
                "would silently change that order's P&L.",
          );
        }
      }

      final expenses = await TripExpensesTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('trip_id', trip.id!).limit(1),
      );
      if (expenses.isNotEmpty) {
        return const DeleteCheck(
          allowed: false,
          reason: 'This trip has fuel or other expenses logged against it. '
              'Deleting it would silently change P&L.',
        );
      }

      final hasVehicleLog = trip.kmStart != null ||
          trip.kmEnd != null ||
          (trip.fuelLitres ?? 0) > 0;
      if (hasVehicleLog) {
        return const DeleteCheck(
          allowed: false,
          reason: 'This trip has a vehicle log (odometer/fuel) recorded. '
              'Cancel it instead of deleting.',
        );
      }
      return DeleteCheck.allow;
    } catch (e) {
      return DeleteCheck(allowed: false, reason: 'Could not verify this trip: $e');
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
