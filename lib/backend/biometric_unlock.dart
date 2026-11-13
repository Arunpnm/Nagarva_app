import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '/app_session.dart';
import '/backend/device_org_binding.dart';
import '/backend/edge_function_errors.dart';
import '/backend/supabase/supabase.dart';

/// Fingerprint / face unlock on the PIN screen (Arun, 12 Nov 2026).
///
/// HOW IT WORKS. PIN login is checked on the server (pin-login /
/// staff-login), so the phone's fingerprint cannot replace the PIN by
/// itself. After a successful PIN login the person is offered "Use
/// fingerprint next time"; if they agree, this phone keeps their PIN in
/// Android's encrypted storage (Keystore-backed, readable only by this
/// app on this phone). Next time, a fingerprint or face match releases
/// that PIN and the normal PIN login runs with it. Same server checks,
/// same lockouts; nothing changes on the server.
///
/// One saved PIN per company + person on this phone. It is removed when:
///   * the person turns it off (Settings),
///   * the saved PIN stops working (PIN changed), or
///   * the device's company binding changes.
///
/// ANDROID ONLY. Web has no fingerprint API we can use; the button never
/// shows there.
class BiometricUnlock {
  BiometricUnlock._();

  static final _auth = LocalAuthentication();
  static const _store = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static bool get _platformOk =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Key for the person this device's PIN screen logs in: the bound staff
  /// member, or the company's owner pool.
  static String? _key() {
    final org = DeviceOrgBinding.boundOrgId;
    if (org == null) return null;
    return 'bio_unlock_v1:$org:${DeviceOrgBinding.boundStaffId ?? 'owner'}';
  }

  /// True when the phone has a fingerprint or face enrolled.
  static Future<bool> available() async {
    if (!_platformOk) return false;
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Name shown on the button ("Unlock as Ravi"), or null when this phone
  /// has no saved fingerprint unlock for the current binding.
  static Future<String?> savedName() async {
    final k = _key();
    if (!_platformOk || k == null) return null;
    try {
      final raw = await _store.read(key: k);
      if (raw == null) return null;
      return (jsonDecode(raw) as Map)['name'] as String? ?? '';
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isOn() async => (await savedName()) != null;

  /// Asks for a fingerprint / face. True only on a real match.
  static Future<bool> confirm(String reason) async {
    if (!_platformOk) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Saves the PIN that just logged in successfully.
  static Future<bool> save({required String pin, required String name}) async {
    final k = _key();
    if (!_platformOk || k == null) return false;
    try {
      await _store.write(
          key: k, value: jsonEncode({'pin': pin, 'name': name}));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The saved PIN, released only after a fingerprint / face match.
  static Future<String?> unlockPin(String reason) async {
    final k = _key();
    if (!_platformOk || k == null) return null;
    if (!await confirm(reason)) return null;
    try {
      final raw = await _store.read(key: k);
      if (raw == null) return null;
      final pin = (jsonDecode(raw) as Map)['pin'] as String?;
      return (pin != null && RegExp(r'^\d{4}$').hasMatch(pin)) ? pin : null;
    } catch (_) {
      return null;
    }
  }

  /// Turn on from Settings, for someone who logged in another way
  /// (mobile OTP, email): checks [pin] with the server exactly as the PIN
  /// screen would, ties this phone's PIN screen to the logged-in person,
  /// then asks for a fingerprint and saves. Returns null on success, or
  /// one plain line saying what went wrong (Arun, 12 Nov 2026: "if I
  /// login through phone OTP I can't enable biometric").
  static Future<String?> enableWithPin(String pin,
      {required String reason, required String noPinMessage}) async {
    if (!_platformOk) return null;
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) return noPinMessage;
    final s = AppSession.instance;
    final orgId = s.currentOrgId;
    if (orgId == null) return 'Please log in again.';
    final staffId = s.currentStaffId;
    try {
      // Only checks the PIN: the answer's login tokens are not used, so
      // the current login stays as it is.
      final res = staffId != null
          ? await SupaFlow.client.functions.invoke('staff-login',
              body: {'staff_id': staffId, 'pin': pin})
          : await SupaFlow.client.functions.invoke('pin-login',
              body: {'org_id': orgId, 'pin': pin});
      final data = res.data;
      if (data is! Map || data['access_token'] == null) {
        return 'Wrong PIN. Try again.';
      }
      // pin-login also accepts a staff PIN from the shared pool; this must
      // be the owner's own PIN when the owner is turning it on.
      if (staffId == null && data['kind'] == 'staff') {
        return 'Wrong PIN. Try again.';
      }
    } catch (e) {
      return extractFunctionErrorMessage(e, fallback: friendlyError(e));
    }
    // From now on this phone opens on the PIN screen for this person,
    // which is where the fingerprint prompt lives.
    final slug = s.currentOrgSlug ?? '';
    final name = s.currentOrgName ?? '';
    if (staffId != null) {
      await DeviceOrgBinding.bindStaff(
        orgId: orgId,
        orgName: name,
        orgSlug: slug,
        staffId: staffId,
        staffName: s.currentStaffName ?? '',
        staffRole: s.currentStaffRole,
      );
    } else if (DeviceOrgBinding.boundOrgId != orgId ||
        DeviceOrgBinding.boundStaffId != null) {
      await DeviceOrgBinding.bind(orgId: orgId, orgName: name, orgSlug: slug);
    }
    if (!await confirm(reason)) return '';
    final ok = await save(pin: pin, name: s.currentStaffName ?? name);
    return ok ? null : 'Could not save. Please try again.';
  }

  static Future<void> turnOff() async {
    final k = _key();
    if (!_platformOk || k == null) return;
    try {
      await _store.delete(key: k);
    } catch (_) {}
  }
}
