import '/flutter_flow/flutter_flow_util.dart';
import 'quotation_page_widget.dart' show QuotationPageWidget;
import 'package:flutter/material.dart';

class QuotationPageModel extends FlutterFlowModel<QuotationPageWidget> {
  ///  State fields for stateful widgets in this page.

  // State field(s) for CustomerName widget.
  FocusNode? customerNameFocusNode;
  TextEditingController? customerNameTextController;
  String? Function(BuildContext, String?)? customerNameTextControllerValidator;
  // State field(s) for CustomerPhone widget.
  FocusNode? customerPhoneFocusNode;
  TextEditingController? customerPhoneTextController;
  String? Function(BuildContext, String?)? customerPhoneTextControllerValidator;
  // State field(s) for FromAddress widget.
  FocusNode? fromAddressFocusNode;
  TextEditingController? fromAddressTextController;
  String? Function(BuildContext, String?)? fromAddressTextControllerValidator;
  // State field(s) for ToAddress widget.
  FocusNode? toAddressFocusNode;
  TextEditingController? toAddressTextController;
  String? Function(BuildContext, String?)? toAddressTextControllerValidator;
  // State field(s) for MoveDate widget.
  FocusNode? moveDateFocusNode;
  TextEditingController? moveDateTextController;
  String? Function(BuildContext, String?)? moveDateTextControllerValidator;
  // State field(s) for FloorDetails widget.
  FocusNode? floorDetailsFocusNode;
  TextEditingController? floorDetailsTextController;
  String? Function(BuildContext, String?)? floorDetailsTextControllerValidator;
  // State field(s) for EstimateAmount widget.
  FocusNode? estimateAmountFocusNode;
  TextEditingController? estimateAmountTextController;
  String? Function(BuildContext, String?)?
      estimateAmountTextControllerValidator;
  // State field(s) for Notes widget.
  FocusNode? notesFocusNode;
  TextEditingController? notesTextController;
  String? Function(BuildContext, String?)? notesTextControllerValidator;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    customerNameFocusNode?.dispose();
    customerNameTextController?.dispose();

    customerPhoneFocusNode?.dispose();
    customerPhoneTextController?.dispose();

    fromAddressFocusNode?.dispose();
    fromAddressTextController?.dispose();

    toAddressFocusNode?.dispose();
    toAddressTextController?.dispose();

    moveDateFocusNode?.dispose();
    moveDateTextController?.dispose();

    floorDetailsFocusNode?.dispose();
    floorDetailsTextController?.dispose();

    estimateAmountFocusNode?.dispose();
    estimateAmountTextController?.dispose();

    notesFocusNode?.dispose();
    notesTextController?.dispose();
  }
}
