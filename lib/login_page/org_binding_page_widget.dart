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
