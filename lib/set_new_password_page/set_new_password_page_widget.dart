import 'package:flutter/material.dart';
import '/components/auth_shell.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';

import '/backend/pending_password_reset.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
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

  Widget _eye(bool visible, VoidCallback onTap) => IconButton(
        icon: Icon(visible ? Icons.visibility_off : Icons.visibility,
            color: NgPalette.of(context).faint, size: 20),
        onPressed: onTap,
      );

  // Login redesign (13 Nov 2026): same blue header + white card as the
  // other sign-in screens.
  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: NgAuthShell(
        title: 'Set a new password',
        subtitle: 'Choose a new password to finish resetting your account.',
        icon: Icons.lock_reset,
        card: NgAuthCard(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const NgAuthLabel('New password'),
                TextFormField(
                  controller: _passwordController,
                  focusNode: _passwordFocusNode,
                  obscureText: !_passwordVisible,
                  autofillHints: const [AutofillHints.newPassword],
                  style: NgFonts.geist(color: c.text, fontSize: 15),
                  // Same rule as SignupPageWidget's own password field.
                  validator: (v) => (v == null || v.length < 8)
                      ? 'Password must be at least 8 characters'
                      : null,
                  decoration: authInputDecoration(context,
                      hint: 'At least 8 characters',
                      suffix: _eye(_passwordVisible,
                          () => safeSetState(() => _passwordVisible = !_passwordVisible))),
                ),
                const SizedBox(height: 16),
                const NgAuthLabel('Type it again'),
                TextFormField(
                  controller: _confirmController,
                  focusNode: _confirmFocusNode,
                  obscureText: !_confirmVisible,
                  autofillHints: const [AutofillHints.newPassword],
                  style: NgFonts.geist(color: c.text, fontSize: 15),
                  validator: (v) => (v != _passwordController.text)
                      ? 'Passwords do not match'
                      : null,
                  decoration: authInputDecoration(context,
                      hint: 'Re-enter the new password',
                      suffix: _eye(_confirmVisible,
                          () => safeSetState(() => _confirmVisible = !_confirmVisible))),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.redBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(_errorMessage!,
                        style: NgFonts.geist(color: c.red, fontSize: 13)),
                  ),
                ],
                const SizedBox(height: 20),
                NgPrimaryButton(
                  label: _isLoading ? 'Please wait…' : 'Save & log in',
                  height: 50,
                  onPressed: _isLoading ? null : _handleSubmit,
                ),
              ],
            ),
          ),
        ),
        below: [
          const SizedBox(height: 16),
          Text('Other phones logged in with the old password are logged out.',
              textAlign: TextAlign.center,
              style: NgFonts.geist(fontSize: 13, color: c.mute)),
        ],
      ),
    );
  }
}
