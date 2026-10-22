import 'package:flutter/material.dart';
import '/components/ng_widgets.dart';

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

  /// Redeems a staff invite and binds this device to that PERSON.
  ///
  /// Deliberately does not log anyone in — it establishes whose phone
  /// this is. The PIN screen that follows establishes that it is really
  /// them. A leaked code alone must not be enough.
  Future<void> _redeemInvite() async {
    final ctrl = TextEditingController();
    final ng = NgPalette.of(context);
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
              style: TextStyle(fontSize: 13, color: ng.mute),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 22, letterSpacing: 4, fontWeight: FontWeight.w600),
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
    final ng = NgPalette.of(context);
    return Scaffold(
      backgroundColor: ng.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: NgIconTile(
                      icon: Icons.phonelink_setup_rounded,
                      status: NgStatus.accent,
                      size: 60,
                      iconSize: 30),
                ),
                const SizedBox(height: 22),
                Text('Set up this device',
                    style: NgFonts.geist(
                        fontSize: 30,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.6,
                        color: ng.text)),
                const SizedBox(height: 8),
                Text(
                  'Enter your organization code (ask your admin, or use the '
                  'link they shared — e.g. nagarva.in/apc).',
                  style: NgFonts.geist(fontSize: 15, height: 1.4, color: ng.mute),
                ),
                const SizedBox(height: 28),
                const NgFieldLabel('Organization code'),
                TextField(
                  controller: _slugController,
                  cursorColor: ng.acc,
                  style: NgFonts.mono(fontSize: 17, color: ng.text),
                  decoration: InputDecoration(
                    hintText: 'apc',
                    hintStyle: NgFonts.mono(fontSize: 17, color: ng.faint),
                    prefixIcon:
                        Icon(Icons.business_rounded, size: 20, color: ng.faint),
                    filled: true,
                    fillColor: ng.s1,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: ng.w08),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: ng.acc, width: 1.5),
                    ),
                  ),
                  onSubmitted: (_) => _bind(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: NgFonts.geist(fontSize: 13, color: ng.red)),
                ],
                const SizedBox(height: 20),
                NgPrimaryButton(
                  icon: Icons.arrow_forward_rounded,
                  label: _loading ? 'Checking…' : 'Continue',
                  height: 54,
                  onPressed: _loading ? null : _bind,
                ),
                const SizedBox(height: 10),
                // Auth plan REVISED item 3. Staff never type an org code:
                // that only binds "which company", which is what forced
                // PIN login to search an org-wide pool. An invite binds
                // this phone to ONE staff_id, so login can go straight to
                // staff-login and never touch the owner's credentials.
                NgSecondaryButton(
                  icon: Icons.vpn_key_outlined,
                  iconColor: ng.acc,
                  label: 'I have an invite code',
                  height: 50,
                  onPressed: _loading ? null : _redeemInvite,
                ),
                const SizedBox(height: 18),
                Center(
                  child: NgLinkButton('First time? Log in with email instead',
                      onTap: () =>
                          context.pushNamed(LoginPageWidget.routeName)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
