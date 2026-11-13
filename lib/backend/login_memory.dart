import 'package:shared_preferences/shared_preferences.dart';

import '/app_session.dart';
import '/backend/device_org_binding.dart';
import '/backend/owner_pin.dart';
import '/backend/supabase/supabase.dart';

/// "Keep me logged in on this phone" (login redesign, 12 Nov 2026).
///
/// TICKED (the default): after an owner logs in, this phone is tied to
/// their company, so the next time the app opens it goes straight to the
/// quick unlock (PIN or fingerprint) and never asks for a company code.
///
/// NOT TICKED: the login lasts until the app is closed. The next cold
/// start finds [shouldForgetNow] true and signs out before showing
/// anything.
class LoginMemory {
  LoginMemory._();

  static const _kSessionOnly = 'nagarva_session_only';

  /// True once a login happened in THIS run of the app, so the session
  /// being used right now is never mistaken for a left-over one.
  static bool _loggedInThisRun = false;

  /// Mobile number typed on the Log in screen, handed to the OTP screen.
  /// Kept in memory (never in a URL, which a browser would show and log).
  static String? _pendingPhone;

  static void setPendingPhone(String digits) => _pendingPhone = digits;

  static String? takePendingPhone() {
    final p = _pendingPhone;
    _pendingPhone = null;
    return p;
  }

  /// Call just before a login is attempted.
  static Future<void> set({required bool remember}) async {
    _loggedInThisRun = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSessionOnly, !remember);
    } catch (_) {}
  }

  static Future<bool> get _sessionOnly async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kSessionOnly) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// At app start: is there a left-over login the person asked us not to
  /// keep?
  static Future<bool> shouldForgetNow() async =>
      !_loggedInThisRun && await _sessionOnly;

  /// After a successful OWNER login: tie this phone to the company so the
  /// next open is the quick unlock. Does nothing when
  ///   * "keep me logged in" was not ticked,
  ///   * this is a staff member's phone (it stays theirs),
  ///   * the owner has no PIN yet (the PIN screen could never succeed;
  ///     SetOwnerPinPage calls this again once one is saved).
  static Future<void> rememberOwnerDevice() async {
    try {
      if (await _sessionOnly) return;
      final s = AppSession.instance;
      final orgId = s.currentOrgId;
      final uid = SupaFlow.client.auth.currentUser?.id;
      if (orgId == null || uid == null || s.currentStaffId != null) return;
      if (DeviceOrgBinding.isStaffDevice) return;
      if (DeviceOrgBinding.boundOrgId == orgId) return;
      if (await ownerNeedsPin(orgId: orgId, userId: uid)) return;
      await DeviceOrgBinding.bind(
        orgId: orgId,
        orgName: s.currentOrgName ?? '',
        orgSlug: s.currentOrgSlug ?? '',
      );
    } catch (_) {
      // Best effort: without it the app simply opens on the login screen.
    }
  }
}
