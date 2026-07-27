import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'settings_page_widget.dart' show SettingsPageWidget;
import 'package:flutter/material.dart';

class SettingsPageModel extends FlutterFlowModel<SettingsPageWidget> {
  // Loaded from the `organizations` table for AppSession.currentOrgId.
  // Was previously hardcoded (CLAUDE.md known bug #4).
  OrganizationsRow? org;

  // Vendor preference: show Porter commission on the dashboard
  // (settings key 'porter_enabled'). Porter is APC/Bengaluru-specific,
  // so pan-India vendors keep it off.
  bool porterEnabled = false;

  // Per-device toggle for the NotificationBell's in-app popup — see
  // NotificationPrefs (components/notification_bell.dart). Defaults true
  // to match popupsEnabled's default; SettingsPageWidget.initState
  // overwrites this from the actual stored preference.
  bool notificationsEnabled = true;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
