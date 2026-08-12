import 'package:flutter/material.dart';

import '/app_session.dart';
import '/backend/device_org_binding.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/nav/nav.dart';
import '/index.dart';
import '/permissions.dart';
import '/staff_auth.dart';

/// The one real logout sequence, shared by every place a session can end —
/// the owner/manager sidebar footer (`main.dart`'s `_NavBarPageState`), the
/// supervisor overflow menu (`SupervisorMenuButton`), SettingsPage's own
/// Logout button, and HomePage's drawer. Extracted here specifically so a
/// second, slightly-different logout can't drift back in the way
/// `home_page_widget.dart`'s old drawer once did (see its own comment: a
/// Logout tile that never called `signOut()`/`AppSession.clear()` and just
/// navigated to LoginPage with the session fully intact) — and, per the
/// bug fixed below, so a routing fix here doesn't need making four times.
Future<void> performLogout(BuildContext context) async {
  try {
    await SupaFlow.client.auth.signOut();
  } catch (_) {
    // Staff (PIN) sessions have no Supabase Auth session of their own.
  }
  await StaffAuth.clearStoredVendorToken();
  StaffPermissions.clearActive();
  AppSession.instance.clear();
  if (!context.mounted) return;
  // Bug fix (8 Aug 2026): this used to always context.go('/login') — the
  // old two-tab email/password + phone/PIN screen — regardless of device
  // binding. Staff have a PIN, not an email and password, so a driver
  // tapping Logout landed on a screen he had no credentials for; only
  // force-closing and reopening the app recovered, because THAT path goes
  // through nav.dart's `_initialize` route (`/`), which already makes this
  // exact decision (`DeviceOrgBinding.isBound ? PinLoginPageWidget :
  // OrgBindingPageWidget`). Logout never consulted it. Reused here rather
  // than reimplemented: a device stays bound after a normal logout (no
  // code here clears it, deliberately — only "Switch device" calls
  // DeviceOrgBinding.unbind()), so the common case is now correctly
  // routed straight back to the PIN screen. LoginPageWidget stays the
  // fallback for the one real "no binding" case: a session that reached
  // this app via the email/password tab directly, without ever binding
  // this device to an org.
  context.go(DeviceOrgBinding.isBound
      ? PinLoginPageWidget.routePath
      : LoginPageWidget.routePath);
}
