import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/form_field_controller.dart';
import '/index.dart';
import 'new_order_page_widget.dart' show NewOrderPageWidget;
import 'package:flutter/material.dart';

class NewOrderPageModel extends FlutterFlowModel<NewOrderPageWidget> {
  ///  Local state fields for this page.

  String? ordService = 'House Shifting';

  String? ordBranch = 'Bengaluru';

  String? ordType = 'Direct';

  DateTime? ordMoveDate;

  String? ordPorterComm = '16';

  bool? ordSaveSuccess = false;

  bool? ordMoveDatePicked = false;

  ///  State fields for stateful widgets in this page.

  // State field(s) for OrdCustomerField widget.
  FocusNode? ordCustomerFieldFocusNode;
  TextEditingController? ordCustomerFieldTextController;
  String? Function(BuildContext, String?)?
      ordCustomerFieldTextControllerValidator;
  // State field(s) for OrdPhoneField widget.
  FocusNode? ordPhoneFieldFocusNode;
  TextEditingController? ordPhoneFieldTextController;
  String? Function(BuildContext, String?)? ordPhoneFieldTextControllerValidator;
  // State field(s) for OrdFromCityField widget.
  FocusNode? ordFromCityFieldFocusNode;
  TextEditingController? ordFromCityFieldTextController;
  String? Function(BuildContext, String?)?
      ordFromCityFieldTextControllerValidator;
  // State field(s) for OrdToCityField widget.
  FocusNode? ordToCityFieldFocusNode;
  TextEditingController? ordToCityFieldTextController;
  String? Function(BuildContext, String?)?
      ordToCityFieldTextControllerValidator;
  // State field(s) for OrdFromAddressField widget.
  FocusNode? ordFromAddressFieldFocusNode;
  TextEditingController? ordFromAddressFieldTextController;
  String? Function(BuildContext, String?)?
      ordFromAddressFieldTextControllerValidator;
  // State field(s) for OrdToAddressField widget.
  FocusNode? ordToAddressFieldFocusNode;
  TextEditingController? ordToAddressFieldTextController;
  String? Function(BuildContext, String?)?
      ordToAddressFieldTextControllerValidator;
  // State field(s) for OrdFromFloorField widget.
  FocusNode? ordFromFloorFieldFocusNode;
  TextEditingController? ordFromFloorFieldTextController;
  String? Function(BuildContext, String?)?
      ordFromFloorFieldTextControllerValidator;
  // State field(s) for OrdToFloorField widget.
  FocusNode? ordToFloorFieldFocusNode;
  TextEditingController? ordToFloorFieldTextController;
  String? Function(BuildContext, String?)?
      ordToFloorFieldTextControllerValidator;
  DateTime? datePicked;
  // State field(s) for OrdAmountField widget.
  FocusNode? ordAmountFieldFocusNode;
  TextEditingController? ordAmountFieldTextController;
  String? Function(BuildContext, String?)?
      ordAmountFieldTextControllerValidator;
  // State field(s) for OrdServiceDropdown widget.
  String? ordServiceDropdownValue;
  FormFieldController<String>? ordServiceDropdownValueController;
  // State field(s) for OrdBranchDropdown widget.
  String? ordBranchDropdownValue;
  FormFieldController<String>? ordBranchDropdownValueController;
  // State field(s) for OrdTypeDropdown widget.
  String? ordTypeDropdownValue;
  FormFieldController<String>? ordTypeDropdownValueController;
  // State field(s) for OrdPorterCommDropdown widget.
  String? ordPorterCommDropdownValue;
  FormFieldController<String>? ordPorterCommDropdownValueController;
  // State field(s) for OrdNotesField widget.
  FocusNode? ordNotesFieldFocusNode;
  TextEditingController? ordNotesFieldTextController;
  String? Function(BuildContext, String?)? ordNotesFieldTextControllerValidator;
  // State field(s) for OrdGstinField widget (RLS/GST audit, 12 Aug 2026) —
  // customer's GSTIN, needed on a B2B tax invoice for their input credit.
  // Pre-filled from customers.gstin when an existing customer is matched
  // by phone at save time; editable so it can be corrected per order.
  FocusNode? ordGstinFieldFocusNode;
  TextEditingController? ordGstinFieldTextController;
  String? Function(BuildContext, String?)? ordGstinFieldTextControllerValidator;
  // Porter settlement fields — only relevant when ordType == 'Porter'.
  // Ported from apc_webapp App.jsx's order-form settlement preview
  // (lines ~3656-3736): cash the porter/driver collects from the customer
  // on delivery; the difference between the order amount and that cash is
  // what the porter already paid APC up front (the "advance").
  FocusNode? ordPorterCashCollectFieldFocusNode;
  TextEditingController? ordPorterCashCollectFieldTextController;
  String? Function(BuildContext, String?)?
      ordPorterCashCollectFieldTextControllerValidator;
  // Stores action output result for [Backend Call - Insert Row] action in SaveOrderBtn widget.
  OrdersRow? createdOrder;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    ordPorterCashCollectFieldFocusNode?.dispose();
    ordPorterCashCollectFieldTextController?.dispose();

    ordCustomerFieldFocusNode?.dispose();
    ordCustomerFieldTextController?.dispose();

    ordPhoneFieldFocusNode?.dispose();
    ordPhoneFieldTextController?.dispose();

    ordFromCityFieldFocusNode?.dispose();
    ordFromCityFieldTextController?.dispose();

    ordToCityFieldFocusNode?.dispose();
    ordToCityFieldTextController?.dispose();

    ordFromAddressFieldFocusNode?.dispose();
    ordFromAddressFieldTextController?.dispose();

    ordToAddressFieldFocusNode?.dispose();
    ordToAddressFieldTextController?.dispose();

    ordFromFloorFieldFocusNode?.dispose();
    ordFromFloorFieldTextController?.dispose();

    ordToFloorFieldFocusNode?.dispose();
    ordToFloorFieldTextController?.dispose();

    ordAmountFieldFocusNode?.dispose();
    ordAmountFieldTextController?.dispose();

    ordNotesFieldFocusNode?.dispose();
    ordNotesFieldTextController?.dispose();

    ordGstinFieldFocusNode?.dispose();
    ordGstinFieldTextController?.dispose();
  }
}
