import '/flutter_flow/flutter_flow_model.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'login_page_widget.dart' show LoginPageWidget;

/// Two-path login: 0 = vendor (Supabase Auth), 1 = staff (phone + PIN).
class LoginPageModel extends FlutterFlowModel<LoginPageWidget> {
  int activeTab = 0;

  bool isLoading = false;
  String? errorMessage;

  // --- Vendor login (Supabase Auth) ---
  FocusNode? vendorEmailFocusNode;
  TextEditingController? vendorEmailController;

  FocusNode? vendorPasswordFocusNode;
  TextEditingController? vendorPasswordController;
  bool vendorPasswordVisible = false;

  // --- Staff login (phone/name + PIN) ---
  FocusNode? namePhoneFieldFocusNode;
  TextEditingController? namePhoneFieldTextController;
  String? Function(BuildContext, String?)?
      namePhoneFieldTextControllerValidator;

  FocusNode? pinFieldFocusNode;
  TextEditingController? pinFieldTextController;
  bool pinFieldVisibility = false;
  String? Function(BuildContext, String?)? pinFieldTextControllerValidator;

  @override
  void initState(BuildContext context) {
    vendorEmailController ??= TextEditingController();
    vendorEmailFocusNode ??= FocusNode();
    vendorPasswordController ??= TextEditingController();
    vendorPasswordFocusNode ??= FocusNode();

    namePhoneFieldTextController ??= TextEditingController();
    namePhoneFieldFocusNode ??= FocusNode();
    pinFieldTextController ??= TextEditingController();
    pinFieldFocusNode ??= FocusNode();
  }

  @override
  void dispose() {
    vendorEmailFocusNode?.dispose();
    vendorEmailController?.dispose();
    vendorPasswordFocusNode?.dispose();
    vendorPasswordController?.dispose();

    namePhoneFieldFocusNode?.dispose();
    namePhoneFieldTextController?.dispose();
    pinFieldFocusNode?.dispose();
    pinFieldTextController?.dispose();
  }
}
