import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/app_session.dart';
import '/backend/device_org_binding.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_session_loader.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/staff_auth.dart';

/// Unified PIN login (parity brief Part 7). Ported from reference/APC Web
/// App JSX/App.jsx's LoginScreen (~line 1341): four single-digit boxes,
/// auto-advance, backspace-back, auto-submit on the 4th digit, an
/// on-screen numpad, and a shake-on-wrong-PIN animation. No email, no
/// password, no phone entry — owner and staff share this one screen, each
/// typing their own PIN. The org comes from the device (see
/// DeviceOrgBinding), never typed here.
///
/// The old two-tab email/password + phone/PIN LoginPageWidget is kept,
/// unreachable from normal navigation but not deleted — this flow could
/// not be live-tested this session (network outage), and it's also the
/// only path that can set an owner's PIN for the very first time (see
/// "Use email login instead" below).
class PinLoginPageWidget extends StatefulWidget {
  const PinLoginPageWidget({super.key});

  static String routeName = 'PinLoginPage';
  static String routePath = '/pin-login';

  @override
  State<PinLoginPageWidget> createState() => _PinLoginPageWidgetState();
}

class _PinLoginPageWidgetState extends State<PinLoginPageWidget>
    with SingleTickerProviderStateMixin {
  final _digits = <String>['', '', '', ''];
  int _focusedBox = 0;
  bool _busy = false;
  String? _error;
  late final AnimationController _shakeCtrl;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _tapDigit(String d) {
    if (_busy) return;
    final i = _digits.indexOf('');
    if (i == -1) return;
    setState(() {
      _digits[i] = d;
      _focusedBox = i == 3 ? 3 : i + 1;
    });
    if (i == 3) _submit();
  }

  void _tapBackspace() {
    if (_busy) return;
    var i = _digits.lastIndexWhere((d) => d.isNotEmpty);
    if (i == -1) return;
    setState(() {
      _digits[i] = '';
      _focusedBox = i;
    });
  }

  Future<void> _submit() async {
    final pin = _digits.join();
    if (pin.length != 4) return;
    final orgId = DeviceOrgBinding.boundOrgId;
    if (orgId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await SupaFlow.client.functions.invoke(
        'pin-login',
        body: {'org_id': orgId, 'pin': pin},
      );
      final data = res.data;
      if (data is! Map || data['access_token'] == null) {
        throw Exception('Wrong PIN. Try again.');
      }
      final kind = data['kind'] as String?;
      final refreshToken = data['refresh_token'] as String;

      final swap = await SupaFlow.client.auth.setSession(refreshToken);
      if (swap.session == null) throw Exception('Could not start session.');

      if (kind == 'staff') {
        final staff = Map<String, dynamic>.from(data['staff'] as Map);
        final staffOrgId = staff['org_id'] as String;
        // Part 7 drops the old requirement of an existing vendor session
        // on this device (see login_page_widget.dart's "device not set up
        // for staff login yet" guard) — a fresh device now needs its own
        // org display info, hence loading it here via setOrgOnly rather
        // than relying on a vendor session that was set up earlier.
        final sessionData = await loadOrgSessionData(staffOrgId);
        AppSession.instance.setOrgOnly(
          orgId: sessionData.orgId,
          orgName: sessionData.orgName,
          orgSlug: sessionData.orgSlug,
          logoUrl: sessionData.logoUrl,
          limits: sessionData.limits,
          features: sessionData.features,
          planName: sessionData.planName,
          planStatus: sessionData.planStatus,
          trialEndsAt: sessionData.trialEndsAt,
          orgActive: sessionData.orgActive,
        );
        AppSession.instance.setStaff(
          staffId: staff['id'] as String,
          staffName: (staff['name'] as String?) ?? 'Staff',
          role: staff['role'] as String?,
        );
      } else {
        // Owner: resolve org/plan exactly like the vendor email/password
        // path already does (login_page_widget.dart's _handleVendorLogin).
        final user = SupaFlow.client.auth.currentUser!;
        final members = await OrgMembersTable().queryRows(
          queryFn: (q) => q.eq('user_id', user.id),
        );
        final orgIds =
            members.map((m) => m.orgId).whereType<String>().toList();
        if (orgIds.isEmpty) {
          throw Exception('This account is not linked to any organization.');
        }
        final sessionData = await loadOrgSessionData(orgIds.first);
        AppSession.instance.setVendorSession(
          authUserId: user.id,
          orgId: sessionData.orgId,
          orgName: sessionData.orgName,
          orgSlug: sessionData.orgSlug,
          logoUrl: sessionData.logoUrl,
          limits: sessionData.limits,
          features: sessionData.features,
          planName: sessionData.planName,
          planStatus: sessionData.planStatus,
          trialEndsAt: sessionData.trialEndsAt,
          orgActive: sessionData.orgActive,
        );
        await StaffAuth.saveVendorRefreshToken();
      }

      if (!mounted) return;
      context.go(HomePageWidget.routePath);
    } catch (e) {
      _shakeCtrl.forward(from: 0);
      setState(() {
        _digits.setAll(0, ['', '', '', '']);
        _focusedBox = 0;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _digitBox(int i) {
    final theme = FlutterFlowTheme.of(context);
    final filled = _digits[i].isNotEmpty;
    final active = _focusedBox == i;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 58,
      height: 66,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: filled || active ? theme.primary : theme.secondaryText,
          width: 2,
        ),
      ),
      child: Text(
        filled ? '•' : '',
        style: GoogleFonts.jetBrainsMono(
            fontSize: 26, fontWeight: FontWeight.w700, color: theme.primaryText),
      ),
    );
  }

  Widget _numKey(String label, {VoidCallback? onTap, Widget? icon}) {
    final theme = FlutterFlowTheme.of(context);
    return SizedBox(
      width: 72,
      height: 56,
      child: Material(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Center(
            child: icon ??
                Text(label,
                    style: GoogleFonts.interTight(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: theme.primaryText)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final orgName = DeviceOrgBinding.boundOrgName ?? 'Nagarva';
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_shipping, size: 48, color: theme.primary),
                const SizedBox(height: 12),
                Text(orgName,
                    style: GoogleFonts.interTight(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: theme.primaryText)),
                const SizedBox(height: 4),
                Text('Enter your 4-digit PIN',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: theme.secondaryText)),
                const SizedBox(height: 28),
                AnimatedBuilder(
                  animation: _shakeCtrl,
                  builder: (context, child) {
                    final t = _shakeCtrl.value;
                    final dx = (t == 0 || t == 1)
                        ? 0.0
                        : 10 * (t < 0.5 ? 1 : -1) * (1 - (t - 0.5).abs() * 2);
                    return Transform.translate(
                        offset: Offset(dx, 0), child: child);
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 4; i++) ...[
                        _digitBox(i),
                        if (i < 3) const SizedBox(width: 12),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 20,
                  child: _busy
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : (_error != null
                          ? Text(_error!,
                              style: TextStyle(
                                  color: theme.error,
                                  fontWeight: FontWeight.w600))
                          : null),
                ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
                      _numKey(d, onTap: () => _tapDigit(d)),
                    const SizedBox(width: 72, height: 56),
                    _numKey('0', onTap: () => _tapDigit('0')),
                    _numKey('',
                        icon: const Icon(Icons.backspace_outlined, size: 20),
                        onTap: _tapBackspace),
                  ],
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () =>
                      context.pushNamed(LoginPageWidget.routeName),
                  child: const Text('Use email login instead'),
                ),
                TextButton(
                  onPressed: () async {
                    await DeviceOrgBinding.unbind();
                    if (mounted) {
                      context.pushNamed(OrgBindingPageWidget.routeName);
                    }
                  },
                  child: const Text('Not your organization? Switch device'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
