import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '/app_session.dart';
import '/backend/owner_pin.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/index.dart';

/// First-run owner PIN bootstrap (28 Aug 2026).
///
/// **The gap this closes.** `create_org_with_owner()` takes no PIN and
/// creates no staff, so every brand-new org lands with
/// `org_members.pin_hash` NULL and zero `staff` rows. A device bound to
/// that org shows PinLoginPage by default — and `verify_org_pin()`
/// iterates the owner pool and the staff pool, both of which are empty,
/// so **no PIN can ever succeed**. Every attempt is a failure that
/// increments `pin_ip_attempts`, and 10 of them lock the IP for 15
/// minutes. The vendor's first experience of the product is a keypad
/// that cannot work and then locks them out.
///
/// Confirmed live on a fresh sandbox org, 28 Aug 2026: `pin_hash` NULL,
/// 0 staff.
///
/// **Why a screen and not a `p_pin` argument on the function.** A PIN
/// passed to a SQL function is a credential in `pg_stat_statements` and
/// in query logs. Routing it through the app means it travels the same
/// path as every other PIN in the product — client -> `org_members.pin`
/// -> `org_members_hash_pin_trigger` -> bcrypt -> `pin_hash`, plaintext
/// nulled in the same statement. One hashing path to audit, not two.
///
/// **Skippable, deliberately.** Forcing it blocks a vendor who just
/// wants to look around on their first login; never offering it is the
/// dead end above. Skip lands on the dashboard, and Settings' "App PIN"
/// card stays available — that card is gated on
/// `currentStaffId == null` (an email-session test, not a PIN gate), so
/// an owner with no PIN can always reach it. Verified before this screen
/// was written; without that, skip would dead-end.
class SetOwnerPinPageWidget extends StatefulWidget {
  const SetOwnerPinPageWidget({super.key});

  static const String routeName = 'SetOwnerPinPage';
  static const String routePath = '/set-owner-pin';

  @override
  State<SetOwnerPinPageWidget> createState() => _SetOwnerPinPageWidgetState();
}

class _SetOwnerPinPageWidgetState extends State<SetOwnerPinPageWidget> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _continue() => context.go(HomePageWidget.routePath);

  Future<void> _save() async {
    final pin = _pinController.text.trim();
    final confirm = _confirmController.text.trim();

    // Checked here rather than in saveOwnerPin: confirmation is this
    // screen's concern, not the shared write's. Settings has a single
    // field and re-entry there is a change, not a first set.
    if (pin != confirm) {
      setState(() => _error = 'The two PINs do not match.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final result = await saveOwnerPin(context, pin);

    if (!mounted) return;
    setState(() => _saving = false);

    if (result.saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN set. You can now sign in with it.')),
      );
      _continue();
      return;
    }
    // A cancelled disambiguation carries no message — say nothing rather
    // than inventing an error for a deliberate choice.
    if (result.message != null) {
      setState(() => _error = result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final orgName = AppSession.instance.currentOrgName ?? 'your organization';

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.lock_outline, size: 48, color: theme.primary),
                  const SizedBox(height: 20),
                  Text(
                    'Set your PIN',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.interTight(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: theme.primaryText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'A 4-digit PIN lets you sign in to $orgName without '
                    'typing your email and password every time.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                        fontSize: 14, color: theme.secondaryText),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'New PIN',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _confirmController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => _saving ? null : _save(),
                    decoration: const InputDecoration(
                      labelText: 'Confirm PIN',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: GoogleFonts.inter(
                          fontSize: 13, color: theme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Set PIN'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _saving ? null : _continue,
                    child: const Text('Skip for now'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'You can set it later from Settings → App PIN.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                        fontSize: 12, color: theme.secondaryText),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
