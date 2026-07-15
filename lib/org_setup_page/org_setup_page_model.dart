import '/flutter_flow/flutter_flow_model.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'org_setup_page_widget.dart' show OrgSetupPageWidget;

class OrgSetupPageModel extends FlutterFlowModel<OrgSetupPageWidget> {
  FocusNode? gstinFocusNode;
  TextEditingController? gstinController;

  FocusNode? prefixFocusNode;
  TextEditingController? prefixController;

  FocusNode? addressFocusNode;
  TextEditingController? addressController;

  FocusNode? cityFocusNode;
  TextEditingController? cityController;

  FocusNode? stateFocusNode;
  TextEditingController? stateController;

  bool isLoading = false;
  String? errorMessage;

  @override
  void initState(BuildContext context) {
    gstinController ??= TextEditingController();
    gstinFocusNode ??= FocusNode();
    prefixController ??= TextEditingController();
    prefixFocusNode ??= FocusNode();
    addressController ??= TextEditingController();
    addressFocusNode ??= FocusNode();
    cityController ??= TextEditingController();
    cityFocusNode ??= FocusNode();
    stateController ??= TextEditingController();
    stateFocusNode ??= FocusNode();
  }

  @override
  void dispose() {
    gstinFocusNode?.dispose();
    gstinController?.dispose();
    prefixFocusNode?.dispose();
    prefixController?.dispose();
    addressFocusNode?.dispose();
    addressController?.dispose();
    cityFocusNode?.dispose();
    cityController?.dispose();
    stateFocusNode?.dispose();
    stateController?.dispose();
  }
}
