import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/pending_password_reset.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart' show kBrandGold;
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/index.dart';

/// Landing page for a `type=recovery` deep link (17 Aug 2026 —
/// auth_deep_link.dart's recovery branch). A recovery link authenticates
/// the device the same way a signup confirmation does (setSession(), full
/// vendor session established) — the one thing that must NOT happen
/// automatically is landing straight on the dashboard with the OLD
/// password still active. This page is the required gate in between:
/// new password + confirm, same rules as SignupPageWidget's own fields,
/// then `auth.updateUser()`.
///
/// Reached two ways: PendingPasswordReset.active (checked by nav.dart's
/// `_initialize` route, for a cold start where a deep link launched the
/// app and there's no router yet at the point the link is processed) or
/// a direct `router.go(routePath)` (warm resume, auth_deep_link.dart's
/// startListening() already has a live router). Either way, AppSession is
/// already fully populated by the time this page shows — success just
/// clears the flag and goes to the dashboard, no further session setup
/// needed.
class SetNewPasswordPageWidget extends StatefulWidget {
  const SetNewPasswordPageWidget({super.key});

  static String routeName = 'SetNewPasswordPage';
  static String routePath = '/set-new-password';

  @override
  State<SetNewPasswordPageWidget> createState() =>
      _SetNewPasswordPageWidgetState();
}

class _SetNewPasswordPageWidgetState extends State<SetNewPasswordPageWidget> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  final _confirmFocusNode = FocusNode();
  bool _passwordVisible = false;
  bool _confirmVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _passwordFocusNode.dispose();
    _confirmFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    safeSetState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await SupaFlow.client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );
      // The gate is cleared on success only — a failed attempt must not
      // let a later app restart skip straight past this screen with the
      // old password still live.
      PendingPasswordReset.active = false;
      if (mounted) context.go(HomePageWidget.routePath);
    } on AuthApiException catch (e) {
      safeSetState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (_) {
      safeSetState(() {
        _errorMessage = 'Could not update your password. Please try again.';
        _isLoading = false;
      });
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: GoogleFonts.inter(color: Colors.white54),
      hintStyle: GoogleFonts.inter(color: Colors.white24),
      prefixIcon: Icon(icon, color: Colors.white38, size: 20),
      filled: true,
      fillColor: const Color(0xFF2A2D45),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF3A3D55)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBrandGold, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      errorStyle: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1117),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Column(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A1200),
                              borderRadius: BorderRadius.circular(40),
                            ),
                            child: const Icon(Icons.lock_reset,
                                color: kBrandGold, size: 36),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Set a new password',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.interTight(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Choose a new password to finish resetting your account.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _passwordController,
                        focusNode: _passwordFocusNode,
                        obscureText: !_passwordVisible,
                        style: GoogleFonts.inter(color: Colors.white),
                        // Same rule as SignupPageWidget's own password field.
                        validator: (v) => (v == null || v.length < 8)
                            ? 'Password must be at least 8 characters'
                            : null,
                        decoration: _inputDecoration(
                          label: 'New Password',
                          hint: 'Min. 8 characters',
                          icon: Icons.lock_outline,
                        ).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _passwordVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.white38,
                              size: 20,
                            ),
                            onPressed: () => safeSetState(
                                () => _passwordVisible = !_passwordVisible),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmController,
                        focusNode: _confirmFocusNode,
                        obscureText: !_confirmVisible,
                        style: GoogleFonts.inter(color: Colors.white),
                        // Same rule as SignupPageWidget's confirm-password
                        // field — validated client-side, no round trip.
                        validator: (v) => (v != _passwordController.text)
                            ? 'Passwords do not match'
                            : null,
                        decoration: _inputDecoration(
                          label: 'Confirm New Password',
                          hint: 'Re-enter your new password',
                          icon: Icons.lock_outline,
                        ).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _confirmVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.white38,
                              size: 20,
                            ),
                            onPressed: () => safeSetState(
                                () => _confirmVisible = !_confirmVisible),
                          ),
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: GoogleFonts.inter(
                                color: Colors.redAccent, fontSize: 13),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      FFButtonWidget(
                        text: 'Update Password',
                        onPressed: _isLoading ? null : _handleSubmit,
                        options: FFButtonOptions(
                          height: 52,
                          color: kBrandGold,
                          textStyle: GoogleFonts.interTight(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          elevation: 0,
                        ),
                        showLoadingIndicator: _isLoading,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
