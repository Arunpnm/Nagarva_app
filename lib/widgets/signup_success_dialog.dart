import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/flutter_flow/flutter_flow_theme.dart' show kBrandGold;

// Not centrally named beyond kBrandGold (flutter_flow_theme.dart) —
// these match signup_page_widget.dart's own dark navy palette exactly
// (its Scaffold background / card Container decorations), which is its
// own bespoke dark theme rather than the app's general FlutterFlowTheme.
// _kSuccessGreen matches login_page_widget.dart's own success SnackBar
// color (_handleForgotPassword).
const Color _kCardDark = Color(0xFF1E2035);
const Color _kSuccessGreen = Color(0xFF2E7D32);

/// Shown after a successful `signUp()` while "Confirm email" is on — a
/// success state, not the page's error path. Replaces the old inline
/// "Account created — please confirm your email" banner (16 Aug 2026
/// finding: it rendered in the page's error-red styling despite being a
/// success). signup_page_widget.dart's inline banner stays for actual
/// signup FAILURES only; this dialog is the one and only success path.
Future<void> showSignupSuccess(
  BuildContext context, {
  required String email,
  required String orgName,
  required VoidCallback onLogin,
  required Future<void> Function() onResend,
  VoidCallback? onOpenEmail,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _SignupSuccessDialog(
      email: email,
      orgName: orgName,
      onLogin: onLogin,
      onResend: onResend,
      onOpenEmail: onOpenEmail,
    ),
  );
}

class _SignupSuccessDialog extends StatefulWidget {
  const _SignupSuccessDialog({
    required this.email,
    required this.orgName,
    required this.onLogin,
    required this.onResend,
    this.onOpenEmail,
  });

  final String email;
  final String orgName;
  final VoidCallback onLogin;
  final Future<void> Function() onResend;

  /// Null hides the "Open Email App" button entirely rather than showing
  /// a control that would do nothing — see signup_page_widget.dart's own
  /// construction of this callback (android_intent_plus, resolved before
  /// this dialog is shown, not at tap-time).
  final VoidCallback? onOpenEmail;

  @override
  State<_SignupSuccessDialog> createState() => _SignupSuccessDialogState();
}

class _SignupSuccessDialogState extends State<_SignupSuccessDialog> {
  bool _resending = false;
  String? _resendMessage;

  Future<void> _handleResend() async {
    setState(() {
      _resending = true;
      _resendMessage = null;
    });
    try {
      await widget.onResend();
      if (mounted) {
        setState(() => _resendMessage = 'Sent — check your inbox.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _resendMessage = 'Could not resend. Try again shortly.');
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kCardDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _kSuccessGreen.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mark_email_read_outlined,
                    color: _kSuccessGreen, size: 32),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Account created!',
              textAlign: TextAlign.center,
              style: GoogleFonts.interTight(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                style: GoogleFonts.inter(
                    color: Colors.white70, fontSize: 14, height: 1.4),
                children: [
                  const TextSpan(text: "We've sent a confirmation link to "),
                  TextSpan(
                    text: widget.email,
                    style: const TextStyle(
                        color: kBrandGold, fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                      text:
                          '. Open it to activate ${widget.orgName} on Nagarva.'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            if (widget.onOpenEmail != null) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: widget.onOpenEmail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBrandGold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.mail_outline, size: 18),
                  label: Text('Open Email App',
                      style:
                          GoogleFonts.interTight(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onLogin();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Go to Login',
                    style: GoogleFonts.interTight(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: _resending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kBrandGold),
                    )
                  : GestureDetector(
                      onTap: _handleResend,
                      child: Text(
                        "Didn't get it? Resend email",
                        style: GoogleFonts.inter(
                          color: kBrandGold,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
            if (_resendMessage != null) ...[
              const SizedBox(height: 6),
              Center(
                child: Text(
                  _resendMessage!,
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
