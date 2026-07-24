import 'package:shared_preferences/shared_preferences.dart';

import '/backend/supabase/supabase.dart';

/// Vendor <-> staff session swap helpers (Option A of the Lock design).
///
/// Staff PIN login now mints a REAL Supabase session for the staff member
/// via the `staff-login` Edge Function, which REPLACES the vendor's
/// session on this device. To make the sidebar Lock button return to the
/// vendor silently (no re-typing email/password), we save the vendor's
/// refresh token here right before the swap and restore it on Lock.
///
/// Supabase rotates refresh tokens on use, so after every successful
/// restore we overwrite the stored token with the newly issued one.
class StaffAuth {
  static const _kVendorRefreshKey = 'nagarva_vendor_refresh_token';

  /// Save the CURRENT session's refresh token as the vendor token.
  /// Call this (a) right after a successful vendor login, and
  /// (b) immediately before swapping to a staff session.
  static Future<void> saveVendorRefreshToken() async {
    final token = SupaFlow.client.auth.currentSession?.refreshToken;
    if (token == null || token.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kVendorRefreshKey, token);
  }

  /// Whether this device has a saved vendor session to Lock back to.
  static Future<bool> hasVendorToken() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_kVendorRefreshKey);
    return t != null && t.isNotEmpty;
  }

  /// Lock: swap the active (staff) session back to the saved vendor
  /// session. Returns true on success. The caller (sidebar Lock button)
  /// is responsible for clearing staff state in AppSession and routing.
  static Future<bool> lockToVendor() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kVendorRefreshKey);
    if (token == null || token.isEmpty) return false;
    try {
      final res = await SupaFlow.client.auth.setSession(token);
      if (res.session == null) return false;
      // Refresh tokens rotate — keep the new one for the next Lock.
      final newToken = res.session!.refreshToken;
      if (newToken != null && newToken.isNotEmpty) {
        await prefs.setString(_kVendorRefreshKey, newToken);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Full logout cleanup — forget the stored vendor token too.
  static Future<void> clearStoredVendorToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kVendorRefreshKey);
  }
}
