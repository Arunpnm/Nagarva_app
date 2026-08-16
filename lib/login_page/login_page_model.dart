import '/flutter_flow/flutter_flow_model.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'login_page_widget.dart' show LoginPageWidget;

/// Vendor login only (Supabase Auth, email + password). Staff login is
/// PinLoginPageWidget's own model now — this page's old in-tab Staff Login
/// form (phone/name + PIN) was removed 16 Aug 2026; see login_page_widget.dart's
/// class doc comment for why.
class LoginPageModel extends FlutterFlowModel<LoginPageWidget> {
  bool isLoading = false;
  String? errorMessage;

  // --- Vendor login (Supabase Auth) ---
  FocusNode? vendorEmailFocusNode;
  TextEditingController? vendorEmailController;

  FocusNode? vendorPasswordFocusNode;
  TextEditingController? vendorPasswordController;
  bool vendorPasswordVisible = false;

  @override
  void initState(BuildContext context) {
    vendorEmailController ??= TextEditingController();
    vendorEmailFocusNode ??= FocusNode();
    vendorPasswordController ??= TextEditingController();
    vendorPasswordFocusNode ??= FocusNode();
  }

  @override
  void dispose() {
    vendorEmailFocusNode?.dispose();
    vendorEmailController?.dispose();
    vendorPasswordFocusNode?.dispose();
    vendorPasswordController?.dispose();
  }
}
