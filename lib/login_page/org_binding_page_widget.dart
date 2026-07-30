import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/device_org_binding.dart';
import '/flutter_flow/flutter_flow_theme.dart';
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

  /// Redeems a staff invite and binds this device to that PERSON.
  ///
  /// Deliberately does not log anyone in — it establishes whose phone
  /// this is. The PIN screen that follows establishes that it is really
  /// them. A leaked code alone must not be enough.
  Future<void> _redeemInvite() async {
    final ctrl = TextEditingController();
    final theme = FlutterFlowTheme.of(context);
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter your invite code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your owner sends this to you. It works once.',
              style: TextStyle(fontSize: 13, color: theme.secondaryText),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 22, letterSpacing: 4, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(hintText: 'ABCD2345'),
              onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(ctrl.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    final entered = code?.trim() ?? '';
    ctrl.dispose();
    if (entered.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await DeviceOrgBinding.redeemInvite(entered);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _loading = false;
        _error = err;
      });
      return;
    }
    // Bound to a person now — straight to the PIN screen, which will
    // route to staff-login because boundStaffId is set.
    context.goNamed(PinLoginPageWidget.routeName);
  }

  Future<void> _bind() async {
    final slug = _slugController.text.trim();
    if (slug.isEmpty) {
      setState(() => _error = 'Enter your organization code.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final org = await DeviceOrgBinding.findBySlug(slug);
      if (org == null) {
        setState(() => _error = 'No organization found for "$slug".');
        return;
      }
      await DeviceOrgBinding.bind(
          orgId: org.id, orgName: org.name, orgSlug: org.slug);
      if (mounted) context.go(PinLoginPageWidget.routePath);
    } catch (e) {
      setState(() => _error = 'Could not verify that code. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_shipping, size: 48, color: theme.primary),
                const SizedBox(height: 16),
                Text('Set up this device',
                    style: GoogleFonts.interTight(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: theme.primaryText)),
                const SizedBox(height: 8),
                Text(
                  'Enter your organization code (ask your admin, or use the '
                  'link they shared — e.g. nagarva.in/apc).',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: 13, color: theme.secondaryText),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _slugController,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                      labelText: 'Organization code', hintText: 'apc'),
                  onSubmitted: (_) => _bind(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: TextStyle(color: theme.error)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _bind,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primary,
                        foregroundColor: Colors.white),
                    child: Text(_loading ? 'Checking...' : 'Continue'),
                  ),
                ),
                const SizedBox(height: 12),
                // Auth plan REVISED item 3. Staff never type an org code:
                // that only binds "which company", which is what forced
                // PIN login to search an org-wide pool. An invite binds
                // this phone to ONE staff_id, so login can go straight to
                // staff-login and never touch the owner's credentials.
                OutlinedButton.icon(
                  onPressed: _loading ? null : _redeemInvite,
                  icon: const Icon(Icons.vpn_key, size: 18),
                  label: const Text('I have an invite code'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    foregroundColor: theme.primary,
                    side: BorderSide(color: theme.primary),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () =>
                      context.pushNamed(LoginPageWidget.routeName),
                  child: const Text('First time? Log in with email instead'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
