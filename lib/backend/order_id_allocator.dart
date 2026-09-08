import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/config/app_config.dart';

/// The one place an order id is allocated.
///
/// Replaces four byte-identical `_nextOrderId()` methods — new_order_page,
/// lead_detail_page, order_detail_page (Duplicate Order) and
/// supervisor_entry_page — each of which did:
///
///     READ  settings where key='order_id_seq'   -- round trip 1
///     next = current + 1                        -- in Dart, on the device
///     UPSERT value = next                       -- round trip 2
///
/// with no lock between the two. Two people creating an order at the same
/// moment both read 1001, both write 1002, and both get `NGV-1002`. The
/// window is a full network round trip on a phone, not microseconds. The
/// second `orders` INSERT then fails on the primary key, so nothing is
/// corrupted — someone simply loses the order they just entered, and the
/// number is burned either way.
///
/// **There is deliberately no client-side fallback.** Falling back to the
/// old read-modify-write when the RPC fails would reintroduce the exact
/// race, at precisely the moment things are already going wrong — which
/// is when concurrent retries are most likely. A failure here surfaces to
/// the caller and the order is not created. That is the correct outcome:
/// an order with a colliding id is worse than an order that was not
/// created, because the second is visible and the first is not.
class OrderIdAllocator {
  OrderIdAllocator._();

  /// Allocates the next order id for the current org, e.g. `APC-1003`.
  ///
  /// Throws if the caller has no org, if the allocator has not been
  /// deployed yet, or if Postgres refuses — never returns a guessed id.
  static Future<String> next() async {
    if (!kServerSideOrderIds) {
      // Guarded rather than silently falling back, so a build shipped
      // before the migration fails loudly in testing instead of quietly
      // racing in production.
      throw StateError(
          'Server-side order ids are not enabled. Run '
          'supabase/20260908_next_order_id_allocator.sql and set '
          'kServerSideOrderIds = true.');
    }

    final orgId = OrgScope.currentOrgId;
    if (orgId == null || orgId.isEmpty) {
      throw StateError('No current org — cannot allocate an order id.');
    }

    final result =
        await SupaFlow.client.rpc('next_order_id', params: {'p_org': orgId});

    final id = (result ?? '').toString().trim();
    if (id.isEmpty) {
      // An empty return would otherwise become an empty primary key and
      // a 23502 at insert time, blaming the wrong thing.
      throw StateError('next_order_id returned nothing for org $orgId.');
    }
    return id;
  }
}
