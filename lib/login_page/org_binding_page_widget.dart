import 'package:flutter/material.dart';
import '/components/ng_widgets.dart';
import '/components/auth_shell.dart';
import '/l10n/gen/app_localizations.dart';

import '/backend/device_org_binding.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';

/// One-time device -> org binding (parity brief Part 7). Shown once per
/// device before the PIN screen ever appears — "the org comes from the
/// device, not from the user's input" (nagarva_part7_login.md). Also
/// reachable again via PinLoginPageWidget's "Switch device" link for a
/// device that changes hands.
class OrgBindingPageWidget extends StatefulWidget {
  const OrgBindingPageWidget({super.key});

  static String routeName = 'OrgBindingPage';
  static String routePath = '/bind-org';

  @override
  State<OrgBindingPageWidget> createState() => _OrgBindingPageWidgetState();
}

class _OrgBindingPageWidgetState extends State<OrgBindingPageWidget> {
  final _slugController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _slugController.dispose();
    super.dispose();
  }

  /// One box for both codes (login redesign, 12 Nov 2026).
  ///
  /// A personal invite code (8 letters/digits, works once) ties this phone
  /// to ONE staff member, so their PIN goes straight to staff-login. A
  /// company code only says which company; the PIN then finds the person.
  /// Neither logs anyone in: the PIN screen that follows does that, so a
  /// leaked code alone is not enough.
  Future<void> _join() async {
    final l = AppLocalizations.of(context);
    final raw = _slugController.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = l.auCodeBad);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final looksLikeInvite =
          RegExp(r'^[A-Za-z0-9]{8}$').hasMatch(raw.replaceAll(' ', ''));
      String? inviteError;
      if (looksLikeInvite) {
        inviteError = await DeviceOrgBinding.redeemInvite(
            raw.replaceAll(' ', '').toUpperCase());
        if (inviteError == null) {
          if (mounted) context.go(PinLoginPageWidget.routePath);
          return;
        }
      }
      final org = await DeviceOrgBinding.findBySlug(raw.toLowerCase());
      if (org == null) {
        setState(() => _error = inviteError ?? l.auCodeBad);
        return;
      }
      await DeviceOrgBinding.bind(
          orgId: org.id, orgName: org.name, orgSlug: org.slug);
      if (mounted) context.go(PinLoginPageWidget.routePath);
    } catch (_) {
      setState(() => _error = l.auCodeBad);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final link = authLinkColor(context);
    return NgAuthShell(
      title: l.auJoinT,
      subtitle: l.auJoinS,
      icon: Icons.person_add_alt_1_outlined,
      onBack: () => context.go('/'),
      card: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NgAuthLabel(l.auCode),
          TextField(
            controller: _slugController,
            autocorrect: false,
            enableSuggestions: false,
            cursorColor: c.acc,
            style: NgFonts.mono(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: c.text),
            decoration: authInputDecoration(context),
            onSubmitted: (_) => _join(),
          ),
          const SizedBox(height: 6),
          Text(l.auCodeHint,
              style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
          if (_error != null) ...[
            const SizedBox(height: 12),
            NgAuthNote(_error!, error: true),
          ],
          const SizedBox(height: 16),
          NgPrimaryButton(
            label: _loading ? '…' : l.suContinue,
            height: 52,
            onPressed: _loading ? null : _join,
          ),
        ],
      ),
      below: [
        const SizedBox(height: 14),
        NgAuthNote(l.auNoCode),
        const SizedBox(height: 14),
        Center(
          child: GestureDetector(
            onTap: () => context.go(LoginPageWidget.routePath),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${l.auOwnerQ} '),
                TextSpan(
                    text: l.lpLogIn,
                    style: NgFonts.geist(
                        color: link, fontWeight: FontWeight.w600)),
              ]),
              style: NgFonts.geist(fontSize: 14, color: c.soft),
            ),
          ),
        ),
      ],
    );
  }
}
