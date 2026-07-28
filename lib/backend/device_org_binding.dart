import 'package:shared_preferences/shared_preferences.dart';

import '/backend/supabase/supabase.dart';

const _kBoundOrgIdKey = '__bound_org_id__';
const _kBoundOrgNameKey = '__bound_org_name__';
const _kBoundOrgSlugKey = '__bound_org_slug__';

/// Device <-> org binding (parity brief Part 7).
///
/// The PIN login screen never asks which org a user belongs to — that's
/// resolved once per device (first launch, or a deliberate re-bind) and
/// cached locally. See nagarva_part7_login.md: "the org comes from the
/// device, not from the user's input."
class DeviceOrgBinding {
  static SharedPreferences? _prefs;

  static Future<void> initialize() async =>
      _prefs = await SharedPreferences.getInstance();

  static String? get boundOrgId => _prefs?.getString(_kBoundOrgIdKey);
  static String? get boundOrgName => _prefs?.getString(_kBoundOrgNameKey);
  static String? get boundOrgSlug => _prefs?.getString(_kBoundOrgSlugKey);

  static bool get isBound => boundOrgId != null;

  static Future<void> bind({
    required String orgId,
    required String orgName,
    required String orgSlug,
  }) async {
    await _prefs?.setString(_kBoundOrgIdKey, orgId);
    await _prefs?.setString(_kBoundOrgNameKey, orgName);
    await _prefs?.setString(_kBoundOrgSlugKey, orgSlug);
  }

  /// Re-bind entry point (spec: "long-press the logo, or a link under the
  /// numpad") for a device that changes hands.
  static Future<void> unbind() async {
    await _prefs?.remove(_kBoundOrgIdKey);
    await _prefs?.remove(_kBoundOrgNameKey);
    await _prefs?.remove(_kBoundOrgSlugKey);
  }

  /// Looks up an org by its slug via the pre-auth `resolve_org_by_slug`
  /// RPC (20260728_org_pin_login.sql) — no session exists yet at this
  /// point, so this can't go through a normal RLS-scoped table read.
  static Future<({String id, String name, String slug})?> findBySlug(
      String slug) async {
    final rows = await SupaFlow.client
        .rpc('resolve_org_by_slug', params: {'p_slug': slug.trim()});
    if (rows is List && rows.isNotEmpty) {
      final r = rows.first as Map;
      return (
        id: r['id'] as String,
        name: r['name'] as String,
        slug: r['slug'] as String,
      );
    }
    return null;
  }
}
