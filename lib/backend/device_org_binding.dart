import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '/backend/supabase/supabase.dart';

const _kBoundOrgIdKey = '__bound_org_id__';
const _kBoundOrgNameKey = '__bound_org_name__';
const _kBoundOrgSlugKey = '__bound_org_slug__';

// Auth plan REVISED (30 Jul 2026) — person binding, not just org binding.
const _kBoundStaffIdKey = '__bound_staff_id__';
const _kBoundStaffNameKey = '__bound_staff_name__';
const _kBoundStaffRoleKey = '__bound_staff_role__';
const _kDeviceIdKey = '__device_id__';

/// Device binding.
///
/// Originally (parity brief Part 7) a device was bound to an ORG, and the
/// PIN screen searched that whole org for a matching PIN. That is what
/// allowed a staff member whose 4-digit PIN equalled the owner's to be
/// handed an owner session — the device only knew "which company", so the
/// PIN alone had to carry the whole identity.
///
/// The revised model binds a device to a PERSON. Every staff member has
/// their own phone, so the device knows exactly which `staff_id` it
/// belongs to and calls `staff-login` with `{staff_id, pin}`. It never
/// searches an org-wide pool and cannot reach the owner's credentials at
/// all — the escalation path is removed structurally rather than guarded
/// against.
///
/// Two kinds of bound device:
///   * STAFF — bound via an invite code, has [boundStaffId]. Uses
///     `staff-login`.
///   * OWNER — bound by org slug only, no staff id. Uses `pin-login`,
///     which is now effectively owner-only.
class DeviceOrgBinding {
  static SharedPreferences? _prefs;

  static Future<void> initialize() async =>
      _prefs = await SharedPreferences.getInstance();

  static String? get boundOrgId => _prefs?.getString(_kBoundOrgIdKey);
  static String? get boundOrgName => _prefs?.getString(_kBoundOrgNameKey);
  static String? get boundOrgSlug => _prefs?.getString(_kBoundOrgSlugKey);

  static String? get boundStaffId => _prefs?.getString(_kBoundStaffIdKey);
  static String? get boundStaffName => _prefs?.getString(_kBoundStaffNameKey);
  static String? get boundStaffRole => _prefs?.getString(_kBoundStaffRoleKey);

  static bool get isBound => boundOrgId != null;

  /// True when this device belongs to a specific staff member, so PIN
  /// login must go through `staff-login` rather than the org-wide pool.
  static bool get isStaffDevice => boundStaffId != null;

  /// Stable per-install identifier, used to rate-limit invite redemption
  /// per device. Generated locally — it is not a secret and not an
  /// identity, just something to count failures against.
  static String get deviceId {
    final existing = _prefs?.getString(_kDeviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final r = Random.secure();
    final id = List<int>.generate(16, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    _prefs?.setString(_kDeviceIdKey, id);
    return id;
  }

  /// Binds to an org only — the OWNER path, where the person is
  /// established by the PIN against `org_members`.
  static Future<void> bind({
    required String orgId,
    required String orgName,
    required String orgSlug,
  }) async {
    await _prefs?.setString(_kBoundOrgIdKey, orgId);
    await _prefs?.setString(_kBoundOrgNameKey, orgName);
    await _prefs?.setString(_kBoundOrgSlugKey, orgSlug);
    // Clear any stale person binding, so re-binding an ex-staff phone to
    // an owner doesn't leave the old staff_id behind and silently keep
    // routing to staff-login.
    await _prefs?.remove(_kBoundStaffIdKey);
    await _prefs?.remove(_kBoundStaffNameKey);
    await _prefs?.remove(_kBoundStaffRoleKey);
  }

  /// Binds to a specific PERSON — the STAFF path, after redeeming an
  /// invite. This is what closes the escalation hole.
  static Future<void> bindStaff({
    required String orgId,
    required String orgName,
    required String orgSlug,
    required String staffId,
    required String staffName,
    String? staffRole,
  }) async {
    await _prefs?.setString(_kBoundOrgIdKey, orgId);
    await _prefs?.setString(_kBoundOrgNameKey, orgName);
    await _prefs?.setString(_kBoundOrgSlugKey, orgSlug);
    await _prefs?.setString(_kBoundStaffIdKey, staffId);
    await _prefs?.setString(_kBoundStaffNameKey, staffName);
    if (staffRole != null) {
      await _prefs?.setString(_kBoundStaffRoleKey, staffRole);
    } else {
      await _prefs?.remove(_kBoundStaffRoleKey);
    }
  }

  /// Re-bind entry point for a device that changes hands. Clears the
  /// person binding too — a phone handed to a new supervisor must not
  /// keep pointing at the previous one's staff_id.
  static Future<void> unbind() async {
    await _prefs?.remove(_kBoundOrgIdKey);
    await _prefs?.remove(_kBoundOrgNameKey);
    await _prefs?.remove(_kBoundOrgSlugKey);
    await _prefs?.remove(_kBoundStaffIdKey);
    await _prefs?.remove(_kBoundStaffNameKey);
    await _prefs?.remove(_kBoundStaffRoleKey);
    // _kDeviceIdKey deliberately survives: it exists to rate-limit invite
    // guessing, so clearing it on unbind would hand an attacker a free
    // counter reset.
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

  /// Redeems a staff invite code and binds this device to that person.
  ///
  /// Returns null on success, or a human-readable error to show. Does NOT
  /// create a session — the staff member still enters their PIN
  /// afterwards. Redeeming proves "this device belongs to this person";
  /// the PIN proves "this is that person". Collapsing the two would make
  /// a leaked code sufficient on its own.
  static Future<String?> redeemInvite(String code) async {
    try {
      final res = await SupaFlow.client.functions.invoke(
        'staff-invite-redeem',
        body: {'code': code.trim().toUpperCase(), 'device_id': deviceId},
      );
      final data = res.data;
      if (data is! Map || data['ok'] != true) {
        return (data is Map ? data['error'] as String? : null) ??
            'That code could not be used.';
      }
      await bindStaff(
        orgId: data['org_id'] as String,
        orgName: (data['org_name'] as String?) ?? 'Your company',
        orgSlug: (data['org_slug'] as String?) ?? '',
        staffId: data['staff_id'] as String,
        staffName: (data['staff_name'] as String?) ?? 'Staff',
        staffRole: data['staff_role'] as String?,
      );
      return null;
    } catch (_) {
      return 'Could not reach the server. Check your connection.';
    }
  }
}
