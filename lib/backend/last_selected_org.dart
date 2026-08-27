import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which org a multi-org vendor last switched to, so a page
/// reload / cold start can restore that org instead of always falling
/// back to the first `org_members` row.
///
/// This closes main.dart's old `TODO(W2)`: it was written when there was
/// no org switcher yet ("when the org switcher is built..."); the switcher
/// (`components/org_switcher_sheet.dart`) has existed since — this is that
/// follow-up.
///
/// Deliberately a plain UX nicety, not a security boundary: if the stored
/// org isn't in the caller's current `org_members` list (revoked access,
/// signed into a different account, or nothing saved yet), callers fall
/// back to the first membership row exactly as before this existed.
class LastSelectedOrg {
  static const _kKey = '__last_selected_org_id__';

  static Future<String?> get() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kKey);
  }

  static Future<void> set(String orgId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, orgId);
  }
}
