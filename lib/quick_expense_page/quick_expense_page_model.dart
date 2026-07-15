import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_drop_down.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/form_field_controller.dart';
import 'dart:ui';
import 'quick_expense_page_widget.dart' show QuickExpensePageWidget;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class QuickExpensePageModel extends FlutterFlowModel<QuickExpensePageWidget> {
  ///  Local state fields for this page.

  String? expCategory = 'Fuel';

  ///  State fields for stateful widgets in this page.

  // State field(s) for ExpAmountField widget.
  FocusNode? expAmountFieldFocusNode;
  TextEditingController? expAmountFieldTextController;
  String? Function(BuildContext, String?)?
      expAmountFieldTextControllerValidator;
  // State field(s) for ExpCategoryDropdown widget.
  String? expCategoryDropdownValue;
  FormFieldController<String>? expCategoryDropdownValueController;
  // State field(s) for ExpDateField widget.
  FocusNode? expDateFieldFocusNode;
  TextEditingController? expDateFieldTextController;
  String? Function(BuildContext, String?)? expDateFieldTextControllerValidator;
  // State field(s) for ExpOrderIdField widget.
  FocusNode? expOrderIdFieldFocusNode;
  TextEditingController? expOrderIdFieldTextController;
  String? Function(BuildContext, String?)?
      expOrderIdFieldTextControllerValidator;
  // State field(s) for ExpDescField widget.
  FocusNode? expDescFieldFocusNode;
  TextEditingController? expDescFieldTextController;
  String? Function(BuildContext, String?)? expDescFieldTextControllerValidator;
  // Stores action output result for [Backend Call - Insert Row] action in SaveExpenseBtn widget.
  ExpensesRow? savedExpense;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    expAmountFieldFocusNode?.dispose();
    expAmountFieldTextController?.dispose();

    expDateFieldFocusNode?.dispose();
    expDateFieldTextController?.dispose();

    expOrderIdFieldFocusNode?.dispose();
    expOrderIdFieldTextController?.dispose();

    expDescFieldFocusNode?.dispose();
    expDescFieldTextController?.dispose();
  }
}
