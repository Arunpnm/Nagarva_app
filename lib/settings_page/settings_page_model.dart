import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import 'settings_page_widget.dart' show SettingsPageWidget;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class SettingsPageModel extends FlutterFlowModel<SettingsPageWidget> {
  // Loaded from the `organizations` table for AppSession.currentOrgId.
  // Was previously hardcoded (CLAUDE.md known bug #4).
  OrganizationsRow? org;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
