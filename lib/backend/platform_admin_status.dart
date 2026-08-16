import '/app_session.dart';
import '/backend/supabase/supabase.dart';

/// Populates `AppSession.instance.isPlatformAdmin` — the same
/// `platform_admins` lookup `super_admin_page_widget.dart`'s own
/// `_checkAdminAndLoad()` already makes (and the same table
/// `is_platform_admin()` checks at the DB level), mirrored here so
/// `nav_items.dart` can gate the Platform Admin nav entry with a plain
/// synchronous read instead of an async call at build time.
///
/// Call this once, right after every `AppSession.setVendorSession(...)`
/// call site, before navigating to Home — same "load once at login,
/// read synchronously thereafter" contract `StaffPermissions.loadForStaff`
/// already uses for a manager's permission matrix. Not relevant to staff/
/// supervisor/field-staff sessions (never called from those login paths):
/// a platform admin is always a real vendor-type Supabase Auth account —
/// Nagarva's own operator — never a per-org staff shadow user.
Future<void> refreshPlatformAdminStatus() async {
  final userId = AppSession.instance.authUserId;
  if (userId == null) {
    AppSession.instance.isPlatformAdmin = false;
    return;
  }
  try {
    final rows = await PlatformAdminsTable().queryRows(
      queryFn: (q) => q.eq('user_id', userId).limit(1),
    );
    AppSession.instance.isPlatformAdmin = rows.isNotEmpty;
  } catch (_) {
    // Table missing / RLS denies entirely — treat as not-admin, matching
    // SuperAdminPageWidget's own equivalent catch.
    AppSession.instance.isPlatformAdmin = false;
  }
}
