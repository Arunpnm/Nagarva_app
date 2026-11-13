import 'package:flutter/material.dart';

import '/l10n/gen/app_localizations.dart';

import 'package:flutter/services.dart';
import '/components/auth_shell.dart';
import '/components/vendor_logo.dart';
import '/app_session.dart';
import '/backend/biometric_unlock.dart';
import '/backend/device_org_binding.dart';
import '/backend/edge_function_errors.dart';
import '/backend/org_resolution.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_session_loader.dart';
import '/backend/vendor_org_resolver.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/components/language_quick_button.dart';
import '/index.dart';
import '/permissions.dart';

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

  /// Fingerprint / face unlock (12 Nov 2026, lib/backend/biometric_unlock.dart).
  bool _bioAvailable = false;
  String? _bioName; // non-null = saved on this phone
  bool _usedBio = false;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    WidgetsBinding.instance.addPostFrameCallback((_) => _initBio());
  }

  Future<void> _initBio() async {
    final ok = await BiometricUnlock.available();
    final name = ok ? await BiometricUnlock.savedName() : null;
    if (!mounted) return;
    setState(() {
      _bioAvailable = ok;
      _bioName = name;
    });
    // Saved: ask straight away, like a banking app. Cancel falls back to
    // the keypad, and the fingerprint key stays there to try again.
    if (name != null) _bioLogin();
  }

  Future<void> _bioLogin() async {
    if (_busy) return;
    final pin = await BiometricUnlock.unlockPin(
        AppLocalizations.of(context).bioReason);
    if (pin == null || !mounted) return;
    setState(() {
      _digits.setAll(0, pin.split(''));
      _focusedBox = 3;
      _usedBio = true;
    });
    await _submit();
  }

  /// After a PIN login that did not use the fingerprint: offer to save it.
  Future<void> _offerBio(String pin) async {
    if (!_bioAvailable || _bioName != null || !mounted) return;
    final l = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.fingerprint_rounded, size: 36),
        title: Text(l.bioAsk),
        content: Text(l.bioAskSub),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.bioNo)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.bioYes)),
        ],
      ),
    );
    if (yes != true) return;
    // A real match before saving, so the PIN is only ever stored behind a
    // finger or face that this phone has just recognised.
    if (!await BiometricUnlock.confirm(l.bioReason)) return;
    final s = AppSession.instance;
    await BiometricUnlock.save(
      pin: pin,
      name: s.currentStaffName ?? s.currentOrgName ?? '',
    );
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
      // Auth plan REVISED item 4. A device bound to a specific PERSON
      // goes to `staff-login` with {staff_id, pin} — it never searches the
      // org-wide pool and so cannot reach the owner's credentials at all.
      // That is the structural fix for the privilege escalation; the
      // collision guard in verify_org_pin is the stopgap for devices still
      // on the old org-only binding.
      //
      // `pin-login` is now effectively owner-only: reached only by a
      // device bound by org slug with no staff_id.
      final staffId = DeviceOrgBinding.boundStaffId;
      final res = staffId != null
          ? await SupaFlow.client.functions.invoke(
              'staff-login',
              body: {'staff_id': staffId, 'pin': pin},
            )
          : await SupaFlow.client.functions.invoke(
              'pin-login',
              body: {'org_id': orgId, 'pin': pin},
            );
      final data = res.data;
      if (data is! Map || data['access_token'] == null) {
        throw Exception('Wrong PIN. Try again.');
      }
      // staff-login returns no `kind` — it only ever authenticates staff,
      // which is the point. Treat its response as the staff branch.
      final kind = staffId != null ? 'staff' : data['kind'] as String?;
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
          graceDays: sessionData.graceDays,
          orgActive: sessionData.orgActive,
          trialFallsBackToFree: sessionData.trialFallsBackToFree,
          trialEndedToFree: sessionData.trialEndedToFree,
        );
        AppSession.instance.setStaff(
          staffId: staff['id'] as String,
          staffName: (staff['name'] as String?) ?? 'Staff',
          role: staff['role'] as String?,
        );
        // Was missing — the only one of the three setStaff() call sites
        // that didn't also load the permission matrix (main.dart's
        // session-restore and the legacy login_page_widget.dart both
        // already do this). Without it, StaffPermissions.activeStaffPages
        // stays null for the rest of the session, and main.dart's nav
        // filter used to silently substitute a hardcoded 3-item guess
        // instead of the real permission-driven set.
        await StaffPermissions.loadForStaff(staff['id'] as String);
      } else {
        // Owner: resolve org/plan through the same create-org recovery
        // path login_page_widget.dart's _handleVendorLogin and the
        // email-confirmation deep-link handler both use — this branch
        // used to just throw "not linked to any organization" on an
        // empty org_members, the same dead end §2a's recovery exists to
        // close everywhere else. No promptForOrgName here: a PIN-login
        // device implies the org already exists (that's what the PIN was
        // verified against), so org_name metadata being missing on this
        // path would mean something is genuinely wrong, not a legitimate
        // "ask the user" case.
        final user = SupaFlow.client.auth.currentUser!;
        final availableOrgs = await resolveVendorOrgs(user);
        // CORRECTNESS FIX, 27 Aug 2026. This used to be
        // `availableOrgs.first.orgId` — so the PIN was verified against
        // `orgId` (DeviceOrgBinding.boundOrgId, above) and the session
        // was then established for an UNRELATED row. With several orgs
        // live, an owner could authenticate against one legal entity and
        // land in another's books; it had not bitten only because row
        // order happened to favour the right one, and that order is not
        // even deterministic.
        //
        // The bound org is now the SOLE input on this path — not
        // consulted-then-preferred, which would leave it readable as a
        // preference. resolveActiveOrg throws if it is not a real
        // membership rather than falling through to another org.
        final resolved = await resolveActiveOrg(
          availableOrgs: availableOrgs,
          boundOrgId: orgId,
        );
        if (resolved == null) {
          throw Exception('Your account is not linked to any organization.');
        }
        await establishVendorSession(user, resolved.orgId, availableOrgs);
      }

      if (!mounted) return;
      if (!_usedBio) await _offerBio(pin);
      if (!mounted) return;
      context.go(HomePageWidget.routePath);
    } catch (e) {
      // The saved PIN was refused: it was changed since. Forget it and
      // ask for the PIN once; the offer comes back after that login.
      if (_usedBio && e is FunctionException && e.status == 401) {
        await BiometricUnlock.turnOff();
        _bioName = null;
      }
      final wasBio = _usedBio;
      _usedBio = false;
      // `invoke` throws FunctionException on any non-2xx response (17 Aug
      // 2026 finding — see edge_function_errors.dart) — a wrong PIN (401)
      // or a rate-limit lockout (429) both land here, not in the
      // `data['access_token'] == null` check above, which is why this
      // screen used to show a raw "FunctionException(status: ...)" string
      // instead of "Wrong PIN. Try again." / the lockout message.
      _shakeCtrl.forward(from: 0);
      setState(() {
        _digits.setAll(0, ['', '', '', '']);
        _focusedBox = 0;
        _error = wasBio && _bioName == null
            ? AppLocalizations.of(context).bioPinChanged
            : extractFunctionErrorMessage(e, fallback: friendlyError(e));
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Redesign ("LOGIN B: PIN-first, device bound"): a 16px dot per digit
  /// instead of a box — filled accent once entered, the next position
  /// ringed in accent, the rest a w25 ring.
  Widget _pinDot(int i) {
    final c = NgPalette.of(context);
    final filled = _digits[i].isNotEmpty;
    final next = !filled && _focusedBox == i;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? c.accBtn : Colors.transparent,
        border: Border.all(
          color: filled
              ? c.accBtn
              : next
                  ? authLinkColor(context)
                  : c.hairline(0.25),
          width: 2,
        ),
      ),
    );
  }

  Widget _numKey(String label,
      {VoidCallback? onTap, Widget? icon, double width = 72, Color? color}) {
    final c = NgPalette.of(context);
    return SizedBox(
      width: width,
      height: 64,
      child: Material(
        color: color ?? c.s1,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Center(
            child: icon ??
                Text(label,
                    style: NgFonts.geist(
                        fontSize: 26,
                        fontWeight: FontWeight.w500,
                        color: c.text)),
          ),
        ),
      ),
    );
  }

  // Login redesign (12 Nov 2026): blue header with the VENDOR's name and
  // initials (never the platform's logo: this phone belongs to their
  // company now), the PIN dots on a card over it, then the keypad.
  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final link = authLinkColor(context);
    final pad = MediaQuery.paddingOf(context);
    final orgName = (DeviceOrgBinding.boundOrgName ?? '').trim();
    final staffName = (DeviceOrgBinding.boundStaffName ?? '').trim();
    final isStaffPhone = DeviceOrgBinding.isStaffDevice;
    final initials = VendorLogo.initials(orgName);

    Widget framed(Widget child, {double h = 24}) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: h),
              child: child,
            ),
          ),
        );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                color: kAuthBlue,
                padding: EdgeInsets.only(top: pad.top + 8, bottom: 58),
                child: framed(
                  Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.verified_user_rounded,
                              size: 16, color: kAuthOnBlueSoft),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(l.ngLinkedDevice,
                                style: NgFonts.geist(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: kAuthOnBlueSoft)),
                          ),
                          const LanguageQuickButton(iconColor: Colors.white),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: 64,
                        height: 64,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: initials.isEmpty
                            ? const Icon(Icons.local_shipping_rounded,
                                size: 30, color: kAuthBlue)
                            : Text(initials,
                                style: NgFonts.geist(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: kAuthBlue)),
                      ),
                      const SizedBox(height: 12),
                      if (isStaffPhone && staffName.isNotEmpty) ...[
                        Text(orgName,
                            textAlign: TextAlign.center,
                            style: NgFonts.geist(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: kAuthOnBlueSoft)),
                        const SizedBox(height: 6),
                        Text(l.auWelcomeBack(staffName),
                            textAlign: TextAlign.center,
                            style: NgFonts.geist(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.48,
                                color: Colors.white)),
                      ] else
                        Text(orgName,
                            textAlign: TextAlign.center,
                            style: NgFonts.geist(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.48,
                                color: Colors.white)),
                      const SizedBox(height: 6),
                      Text(_bioName != null ? l.auUnlockHint : l.ngEnterPin,
                          textAlign: TextAlign.center,
                          style: NgFonts.geist(
                              fontSize: 14, color: kAuthOnBlueSoft)),
                    ],
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -30),
                child: framed(
                  Column(
                    children: [
                      AnimatedBuilder(
                        animation: _shakeCtrl,
                        builder: (context, child) {
                          final t = _shakeCtrl.value;
                          final dx = (t == 0 || t == 1)
                              ? 0.0
                              : 10 *
                                  (t < 0.5 ? 1 : -1) *
                                  (1 - (t - 0.5).abs() * 2);
                          return Transform.translate(
                              offset: Offset(dx, 0), child: child);
                        },
                        child: Semantics(
                          label: l.ngEnterPin,
                          child: NgAuthCard(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 30, vertical: 20),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < 4; i++) ...[
                                  _pinDot(i),
                                  if (i < 3) const SizedBox(width: 20),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 22,
                        child: _busy
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5, color: c.acc),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(l.ngVerifying,
                                      style: NgFonts.geist(
                                          color: c.mute,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500)),
                                ],
                              )
                            : (_error != null
                                ? Text(_error!,
                                    textAlign: TextAlign.center,
                                    style: NgFonts.geist(
                                        fontSize: 13.5,
                                        color: c.red,
                                        fontWeight: FontWeight.w600))
                                : null),
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          const gap = 12.0;
                          final keyWidth =
                              ((constraints.maxWidth - 2 * gap) / 3)
                                  .clamp(48.0, 120.0);
                          return Column(
                            children: [
                              for (final row in [
                                ['1', '2', '3'],
                                ['4', '5', '6'],
                                ['7', '8', '9'],
                              ]) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (final d in row) ...[
                                      _numKey(d,
                                          width: keyWidth,
                                          onTap: () => _tapDigit(d)),
                                      if (d != row.last)
                                        const SizedBox(width: gap),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: gap),
                              ],
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Bottom-left: fingerprint / face when
                                  // saved on this phone, else empty.
                                  _bioName != null
                                      ? Semantics(
                                          button: true,
                                          label: l.bioSetting,
                                          child: _numKey('',
                                              width: keyWidth,
                                              color: kAuthBlue,
                                              icon: const Icon(
                                                  Icons.fingerprint_rounded,
                                                  size: 30,
                                                  color: Colors.white),
                                              onTap: _bioLogin),
                                        )
                                      : SizedBox(width: keyWidth, height: 64),
                                  const SizedBox(width: gap),
                                  _numKey('0',
                                      width: keyWidth,
                                      onTap: () => _tapDigit('0')),
                                  const SizedBox(width: gap),
                                  _numKey('',
                                      width: keyWidth,
                                      color: Colors.transparent,
                                      icon: Icon(Icons.backspace_outlined,
                                          size: 24, color: c.text),
                                      onTap: _tapBackspace),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 18),
                      // Forgot the PIN: log in the long way (OTP or email)
                      // and set a new one in Settings.
                      TextButton(
                        onPressed: () =>
                            context.go(LoginPageWidget.routePath),
                        child: Text(l.auForgotPin,
                            textAlign: TextAlign.center,
                            style: NgFonts.geist(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: link)),
                      ),
                      TextButton(
                        onPressed: () async {
                          await DeviceOrgBinding.unbind();
                          if (!context.mounted) return;
                          context.go('/');
                        },
                        child: Text(l.auOtherAccount,
                            textAlign: TextAlign.center,
                            style: NgFonts.geist(
                                fontSize: 13.5, color: c.mute)),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_rounded, size: 14, color: c.mute),
                          const SizedBox(width: 5),
                          Text(l.ngSecuredBy,
                              style: NgFonts.geist(
                                  fontSize: 12, color: c.mute)),
                        ],
                      ),
                      SizedBox(height: pad.bottom),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
