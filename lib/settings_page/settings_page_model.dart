import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'settings_page_widget.dart' show SettingsPageWidget;
import 'package:flutter/material.dart';

class SettingsPageModel extends FlutterFlowModel<SettingsPageWidget> {
  // Loaded from the `organizations` table for AppSession.currentOrgId.
  // Was previously hardcoded (CLAUDE.md known bug #4).
  OrganizationsRow? org;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
