import '/backend/supabase/supabase.dart';

/// Find-or-create a `customers` row by phone — shared by every place that
/// creates an order/lead/payment and needs `customer_id` populated.
///
/// Order Details Session 1's Quick Payment Update needs `orders.customer_id`
/// to post a `ledger_entries` row (`party_id uuid not null`). Checking the
/// live migration, orders were NOT actually left unlinked in general — Arun
/// confirmed the migration's own backfill matched every pre-migration order
/// to a customer by phone (see nagarva_migration_001_foundations, the
/// `orders_unlinked`-style backfill around line 597). The real bug is that
/// `new_order_page_widget.dart`'s insert never started populating
/// `customer_id` for orders created after that migration ran — so nulls
/// have been accumulating at the one call site that skips this, not because
/// most orders were never linked in the first place.
///
/// Matches `norm_phone()` (migration 001) digit-for-digit — strip
/// non-digits, keep the last 10 — so a client-side lookup always agrees
/// with `customers.phone_normalized` (a generated column) and the unique
/// index `customers_org_phone_uniq (org_id, phone_normalized)`. That index
/// is what makes the insert-after-lookup race in [findOrCreate] safe: on a
/// concurrent-insert conflict (Postgres error 23505) we re-select instead
/// of failing, since the index guarantees exactly one row exists per
/// (org, phone) once either insert commits.
class CustomerLookup {
  CustomerLookup._();

  /// Null if [phone] has fewer than 10 usable digits — this app treats a
  /// too-short/missing phone as "no usable phone", not as a match key.
  /// `norm_phone()` itself doesn't null out short numbers (`right(str, 10)`
  /// just returns the whole string when it's shorter), so this extra
  /// length check exists specifically to avoid the DB function's looser
  /// behaviour turning a junk 3-digit "phone" into a real match key.
  static String? normalizePhone(String? phone) {
    if (phone == null) return null;
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return null;
    return digits.substring(digits.length - 10);
  }

  /// Returns the matching/created `customers.id`, or null if [phone] has no
  /// usable digits (per [normalizePhone]) — callers must treat null as "skip
  /// whatever needed a customer id", never as a reason to block the caller's
  /// own write (e.g. a payment must still record without a linked customer).
  static Future<String?> findOrCreate({
    required String orgId,
    required String name,
    String? phone,
  }) async {
    final normalized = normalizePhone(phone);
    if (normalized == null) return null;

    Future<String?> lookup() async {
      final row = await SupaFlow.client
          .from('customers')
          .select('id')
          .eq('org_id', orgId)
          .eq('phone_normalized', normalized)
          .isFilter('deleted_at', null)
          .maybeSingle();
      return row?['id'] as String?;
    }

    final existing = await lookup();
    if (existing != null) return existing;

    try {
      final inserted = await SupaFlow.client
          .from('customers')
          .insert({
            'org_id': orgId,
            'name': name.trim().isEmpty ? 'Unknown' : name.trim(),
            'phone': phone,
          })
          .select('id')
          .single();
      return inserted['id'] as String?;
    } on PostgrestException catch (e) {
      // customers_org_phone_uniq fired — another insert for the same
      // (org, phone) won the race between our lookup and our insert.
      // Re-select rather than treating this as a failure.
      if (e.code == '23505') return lookup();
      rethrow;
    }
  }

  /// The customer's GSTIN, if any — RLS/GST audit, 12 Aug 2026. Used to
  /// copy an existing customer's GSTIN forward onto a new order's
  /// `billing_party_gstin` at the same point [findOrCreate] resolves
  /// `customer_id`, so a B2B tax invoice has what the customer needs to
  /// claim input credit without making them re-supply it every order.
  /// Returns null for a brand-new customer (nothing to copy) as much as
  /// for a lookup failure — callers already treat a null GSTIN as "leave
  /// whatever the order form has," so the two cases don't need telling
  /// apart here.
  static Future<String?> gstinFor(String? customerId) async {
    if (customerId == null) return null;
    try {
      final row = await SupaFlow.client
          .from('customers')
          .select('gstin')
          .eq('id', customerId)
          .maybeSingle();
      final gstin = row?['gstin'] as String?;
      return (gstin == null || gstin.trim().isEmpty) ? null : gstin.trim();
    } catch (_) {
      return null;
    }
  }
}
