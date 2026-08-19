import '/flutter_flow/flutter_flow_model.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'signup_page_widget.dart' show SignupPageWidget;

class SignupPageModel extends FlutterFlowModel<SignupPageWidget> {
  // NG-BRIEF-vendor-auth-flow.md §3 — owner name, new: not captured
  // anywhere today, but it's the dashboard greeting and appears on
  // documents. Field order below matches the brief's: owner name,
  // business name, email, password, confirm password, then the
  // pre-existing optional phone field, then the terms checkbox.
  FocusNode? ownerNameFocusNode;
  TextEditingController? ownerNameController;

  FocusNode? companyFocusNode;
  TextEditingController? companyController;

  FocusNode? emailFocusNode;
  TextEditingController? emailController;

  FocusNode? passwordFocusNode;
  TextEditingController? passwordController;
  bool passwordVisible = false;

  FocusNode? confirmPasswordFocusNode;
  TextEditingController? confirmPasswordController;
  bool confirmPasswordVisible = false;

  FocusNode? phoneFocusNode;
  TextEditingController? phoneController;

  // Closed-beta invite-code gate (16 Aug 2026) — deliberately NOT marked
  // required client-side. The server (create-org) is the sole source of
  // truth for whether a code is needed at all, so this screen never
  // needs a redeploy when the gate is later turned off (Item 12) — an
  // empty value just gets sent through and the server decides.
  FocusNode? inviteCodeFocusNode;
  TextEditingController? inviteCodeController;

  bool agreedToTerms = false;

  bool isLoading = false;
  String? errorMessage;

  @override
  void initState(BuildContext context) {
    ownerNameController ??= TextEditingController();
    ownerNameFocusNode ??= FocusNode();
    companyController ??= TextEditingController();
    companyFocusNode ??= FocusNode();
    emailController ??= TextEditingController();
    emailFocusNode ??= FocusNode();
    passwordController ??= TextEditingController();
    passwordFocusNode ??= FocusNode();
    confirmPasswordController ??= TextEditingController();
    confirmPasswordFocusNode ??= FocusNode();
    phoneController ??= TextEditingController();
    phoneFocusNode ??= FocusNode();
    inviteCodeController ??= TextEditingController();
    inviteCodeFocusNode ??= FocusNode();
  }

  @override
  void dispose() {
    ownerNameFocusNode?.dispose();
    ownerNameController?.dispose();
    companyFocusNode?.dispose();
    companyController?.dispose();
    emailFocusNode?.dispose();
    emailController?.dispose();
    passwordFocusNode?.dispose();
    passwordController?.dispose();
    confirmPasswordFocusNode?.dispose();
    confirmPasswordController?.dispose();
    phoneFocusNode?.dispose();
    phoneController?.dispose();
    inviteCodeFocusNode?.dispose();
    inviteCodeController?.dispose();
  }
}
