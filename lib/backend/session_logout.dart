import 'package:flutter/material.dart';

import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/nav/nav.dart';
import '/permissions.dart';
import '/staff_auth.dart';

/// The one real logout sequence, shared by every place a session can end —
/// the owner/manager sidebar footer (`main.dart`'s `_NavBarPageState`) and
/// the supervisor overflow menu (`SupervisorMenuButton`). Extracted here
/// specifically so a second, slightly-different logout can't drift back in
/// the way `home_page_widget.dart`'s old drawer once did (see its own
/// comment: a Logout tile that never called `signOut()`/`AppSession.clear()`
/// and just navigated to LoginPage with the session fully intact).
Future<void> performLogout(BuildContext context) async {
  try {
    await SupaFlow.client.auth.signOut();
  } catch (_) {
    // Staff (PIN) sessions have no Supabase Auth session of their own.
  }
  await StaffAuth.clearStoredVendorToken();
  StaffPermissions.clearActive();
  AppSession.instance.clear();
  if (context.mounted) context.go('/login');
}
