import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '/backend/device_org_binding.dart';

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

  static Future<void> turnOff() async {
    final k = _key();
    if (!_platformOk || k == null) return;
    try {
      await _store.delete(key: k);
    } catch (_) {}
  }
}
