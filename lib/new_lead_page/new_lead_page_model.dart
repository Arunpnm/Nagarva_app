import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_drop_down.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/form_field_controller.dart';
import 'dart:ui';
import '/index.dart';
import 'new_lead_page_widget.dart' show NewLeadPageWidget;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class NewLeadPageModel extends FlutterFlowModel<NewLeadPageWidget> {
  ///  Local state fields for this page.

  String? ldService = '';

  String? ldStatus = 'new';

  String? ldSource = '';

  String? ldBranch = 'Bengaluru';

  bool? ldSaveSuccess = false;

  DateTime? ldApproxDate;

  bool? ldApproxDatePicked = false;

  ///  State fields for stateful widgets in this page.

  // State field(s) for LdCustomerField widget.
  FocusNode? ldCustomerFieldFocusNode;
  TextEditingController? ldCustomerFieldTextController;
  String? Function(BuildContext, String?)?
      ldCustomerFieldTextControllerValidator;
  // State field(s) for LdPhoneField widget.
  FocusNode? ldPhoneFieldFocusNode;
  TextEditingController? ldPhoneFieldTextController;
  String? Function(BuildContext, String?)? ldPhoneFieldTextControllerValidator;
  // State field(s) for LdEmailField widget.
  FocusNode? ldEmailFieldFocusNode;
  TextEditingController? ldEmailFieldTextController;
  String? Function(BuildContext, String?)? ldEmailFieldTextControllerValidator;
  // State field(s) for LdFromCityField widget.
  FocusNode? ldFromCityFieldFocusNode;
  TextEditingController? ldFromCityFieldTextController;
  String? Function(BuildContext, String?)?
      ldFromCityFieldTextControllerValidator;
  // State field(s) for LdToCityField widget.
  FocusNode? ldToCityFieldFocusNode;
  TextEditingController? ldToCityFieldTextController;
  String? Function(BuildContext, String?)? ldToCityFieldTextControllerValidator;
  DateTime? datePicked;
  // State field(s) for LdServiceDropdown widget.
  String? ldServiceDropdownValue;
  FormFieldController<String>? ldServiceDropdownValueController;
  // State field(s) for LdStatusDropdown widget.
  String? ldStatusDropdownValue;
  FormFieldController<String>? ldStatusDropdownValueController;
  // State field(s) for LdSourceDropdown widget.
  String? ldSourceDropdownValue;
  FormFieldController<String>? ldSourceDropdownValueController;
  // State field(s) for LdBranchDropdown widget.
  String? ldBranchDropdownValue;
  FormFieldController<String>? ldBranchDropdownValueController;
  // State field(s) for LdNotesField widget.
  FocusNode? ldNotesFieldFocusNode;
  TextEditingController? ldNotesFieldTextController;
  String? Function(BuildContext, String?)? ldNotesFieldTextControllerValidator;
  // Stores action output result for [Backend Call - Insert Row] action in SaveLeadBtn widget.
  LeadsRow? createdLead;

  // Edit-mode support: when NewLeadPageWidget.leadId is set, the page loads
  // the existing lead here instead of starting from the field defaults
  // above, and the save button updates that row instead of inserting a
  // new one. Fixes LeadDetailPage's "Edit Lead" button, which previously
  // navigated here with no way to load the lead it was meant to edit —
  // see CLAUDE.md.
  bool isLoadingExisting = false;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    ldCustomerFieldFocusNode?.dispose();
    ldCustomerFieldTextController?.dispose();

    ldPhoneFieldFocusNode?.dispose();
    ldPhoneFieldTextController?.dispose();

    ldEmailFieldFocusNode?.dispose();
    ldEmailFieldTextController?.dispose();

    ldFromCityFieldFocusNode?.dispose();
    ldFromCityFieldTextController?.dispose();

    ldToCityFieldFocusNode?.dispose();
    ldToCityFieldTextController?.dispose();

    ldNotesFieldFocusNode?.dispose();
    ldNotesFieldTextController?.dispose();
  }
}
