import '/app_session.dart';
import '/backend/supabase/supabase.dart';

/// Central helper for org-scoped Supabase queries — Stage 1 tenant-safety
/// pass (see LEAK_AUDIT.md and CLAUDE.md's "Org scoping convention").
///
/// Every leak and write-gap in LEAK_AUDIT.md came from hand-writing (or
/// forgetting to write) `.eq('org_id', AppSession.instance.currentOrgId)`
/// at each of ~40 call sites. Use these three helpers instead of writing
/// that filter by hand anywhere new:
///
/// Reads:
///   `queryFn: (q) => OrgScope.read(q).eqOrNull('status', 'pending')`
///
/// Writes (update/delete) — always chain the row-identifying filter AFTER
/// `OrgScope.write(q)`, never instead of it. Matching by `id` alone is
/// exactly the write-gap pattern this helper closes:
///   `matchingRows: (q) => OrgScope.write(q).eq('id', orderId)`
///
/// Inserts — spread into the payload map:
///   `await OrdersTable().insert({...OrgScope.stamp(), 'customer': ...})`
///
/// All three throw a [StateError] if no org is resolved
/// (`AppSession.instance.currentOrgId == null`) instead of silently
/// building a query that would match every org's rows. Every page that
/// reaches these helpers is already past login, where `currentOrgId` is
/// always set (see app_session.dart's `setVendorSession`/`setOrgOnly`) — if
/// this ever throws, that's a real bug (a query running before session
/// resolution), not a false alarm, and it should surface loudly rather than
/// leak data quietly.
///
/// Deliberately NOT used at the handful of call sites that run before an
/// org is known by construction — LoginPage's org-resolution reads
/// (`org_members` by `user_id`, `organizations`/`subscription_plans` by the
/// id just resolved), and SignupPage's org-creation insert. Those are
/// documented as N/A in LEAK_AUDIT.md, not leaks.
class OrgScope {
  OrgScope._();

  static String? get currentOrgId => AppSession.instance.currentOrgId;

  static String _require(String? orgId) {
    final id = orgId ?? currentOrgId;
    if (id == null) {
      throw StateError(
        'OrgScope: no org_id resolved (AppSession.instance.currentOrgId is '
        'null). Refusing to build a query that could otherwise match every '
        "org's rows — this is the Stage 1 guard rail from LEAK_AUDIT.md. "
        'The caller must ensure a signed-in org exists before querying an '
        'org-scoped table (this should never happen on an already-logged-in '
        'page — if it does, that\'s the real bug to fix, not this check).',
      );
    }
    return id;
  }

  /// First call inside a `queryRows`/`querySingleRow` `queryFn`. Chain
  /// further filters (`.eqOrNull(...)`, `.order(...)`, etc.) after it.
  static PostgrestFilterBuilder read(
    PostgrestFilterBuilder q, {
    String? orgId,
  }) =>
      q.eq('org_id', _require(orgId));

  /// First call inside an `update`/`delete` `matchingRows`. Chain the
  /// row-identifying filter (`.eq('id', ...)`) after it — never on its own.
  static PostgrestFilterBuilder write(
    PostgrestFilterBuilder q, {
    String? orgId,
  }) =>
      q.eq('org_id', _require(orgId));

  /// Spread into an insert payload map to stamp `org_id`.
  static Map<String, dynamic> stamp({String? orgId}) =>
      {'org_id': _require(orgId)};
}
