import '/flutter_flow/flutter_flow_model.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'signup_page_widget.dart' show SignupPageWidget;

class SignupPageModel extends FlutterFlowModel<SignupPageWidget> {
  FocusNode? companyFocusNode;
  TextEditingController? companyController;

  FocusNode? emailFocusNode;
  TextEditingController? emailController;

  FocusNode? passwordFocusNode;
  TextEditingController? passwordController;
  bool passwordVisible = false;

  FocusNode? phoneFocusNode;
  TextEditingController? phoneController;

  bool isLoading = false;
  String? errorMessage;

  @override
  void initState(BuildContext context) {
    companyController ??= TextEditingController();
    companyFocusNode ??= FocusNode();
    emailController ??= TextEditingController();
    emailFocusNode ??= FocusNode();
    passwordController ??= TextEditingController();
    passwordFocusNode ??= FocusNode();
    phoneController ??= TextEditingController();
    phoneFocusNode ??= FocusNode();
  }

  @override
  void dispose() {
    companyFocusNode?.dispose();
    companyController?.dispose();
    emailFocusNode?.dispose();
    emailController?.dispose();
    passwordFocusNode?.dispose();
    passwordController?.dispose();
    phoneFocusNode?.dispose();
    phoneController?.dispose();
  }
}
