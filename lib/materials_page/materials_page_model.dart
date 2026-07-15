import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'materials_page_widget.dart' show MaterialsPageWidget;
import 'package:flutter/material.dart';

class MaterialsPageModel extends FlutterFlowModel<MaterialsPageWidget> {
  ///  Local state fields for this page.

  // Was an empty shell with 8 hardcoded fake SKUs (CLAUDE.md "Empty shells").
  // Now backed by the `materials` table, org-scoped.
  List<MaterialsRow>? materialsOut;
  List<MaterialsRow> materialsList = [];

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
