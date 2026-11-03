import 'package:shared_preferences/shared_preferences.dart';

/// "This device is locked" — persisted across reloads (BUG-012, 3 Nov 2026).
///
/// Lock keeps the owner's Supabase session on the device (Slack model, see
/// main.dart `_lockDevice`) so staff PINs keep working. Before this flag
/// existed, every login screen treated that surviving session as proof of
/// identity: after Lock (or a reload of a PIN-bound device) the PIN screen
/// could be skipped with "Use email login instead" or "Log in with mobile
/// number", landing straight in the owner's dashboard.
///
/// Rule:
///   * set by Lock, and at cold start on a PIN-bound device (the root route
///     shows the PIN pad there — that promise now holds);
///   * while set, main.dart does NOT restore AppSession from the stored
///     Supabase session, so no screen can auto-enter;
///   * cleared only when a login actually completes (PIN, OTP or password)
///     — AppSession.setVendorSession / setStaff call [unlock].
class DeviceLock {
  DeviceLock._();

  static const _kLockedKey = 'nagarva_device_locked';
  static bool _locked = false;

  static bool get isLocked => _locked;

  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _locked = prefs.getBool(_kLockedKey) ?? false;
    } catch (_) {
      _locked = false;
    }
  }

  static Future<void> lock() async {
    _locked = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kLockedKey, true);
    } catch (_) {}
  }

  static Future<void> unlock() async {
    if (!_locked) return;
    _locked = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kLockedKey);
    } catch (_) {}
  }
}
