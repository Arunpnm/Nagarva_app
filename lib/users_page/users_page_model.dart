import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'users_page_widget.dart' show UsersPageWidget;
import 'package:flutter/material.dart';

class UsersPageModel extends FlutterFlowModel<UsersPageWidget> {
  ///  Local state fields for this page.

  // Was an empty shell (CLAUDE.md "Empty shells" / Phase 2) — the six staff
  // cards on this page were hardcoded FlutterFlow placeholder data
  // (Arun Kumar / Suresh M. / Murugan P. / Kala R. / Balu S. / Senthil R.),
  // not real records. Now backed by the `staff` table, org-scoped.
  List<StaffRow>? staffOut;
  List<StaffRow> staffList = [];

  // Role filter chip: null = All, else 'admin' | 'driver' | 'staff'.
  String? roleFilter;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
