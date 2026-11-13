import '/l10n/gen/app_localizations.dart';
import '/backend/edge_function_errors.dart';
import '/flutter_flow/ng_tokens.dart';
import '/backend/device_org_binding.dart';
import '/backend/org_resolution.dart';
import '/backend/owner_pin.dart';
import '/backend/pending_auth_message.dart';
import '/backend/supabase/supabase.dart';
import '/backend/vendor_org_resolver.dart';
import '/config/app_config.dart';
import '/components/org_switcher_sheet.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/app_session.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '/components/language_quick_button.dart';
import '/components/ng_widgets.dart';
import '/components/auth_shell.dart';
import '/backend/login_memory.dart';
import 'login_page_model.dart';
export 'login_page_model.dart';

/// Vendor login only: Supabase Auth (email + password) for the org
/// owner/admin. This is also the landing page for an unbound device
/// (nav.dart's _initialize), per NG-BRIEF-vendor-auth-flow.md §4.
///
/// Staff login (name/phone + PIN) lives entirely on PinLoginPageWidget now
/// — this page used to also carry its own in-tab Staff Login form, removed
/// 16 Aug 2026. That form duplicated PinLoginPageWidget's staff-login path
/// (same `staff-login` Edge Function, same session swap via
/// /staff_auth.dart) but was gated on an incidental precondition — a live
/// Supabase Auth session already cached on the device — rather than
/// `DeviceOrgBinding`, the concept the rest of the app actually uses for
/// device setup. Any real logout clears that session first
/// (session_logout.dart), so the tab always failed afterward with a
/// misleading "device not set up" message about a state this page doesn't
/// track.
class LoginPageWidget extends StatefulWidget {
  const LoginPageWidget({super.key});

  static String routeName = 'LoginPage';
  static String routePath = '/login';

  @override
  State<LoginPageWidget> createState() => _LoginPageWidgetState();
}

class _LoginPageWidgetState extends State<LoginPageWidget> {
  late LoginPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => LoginPageModel());
    // Email-confirmation deep link handler (main.dart) routes here on
    // failure with a message stashed for exactly this screen — see
    // PendingAuthMessage's own doc comment for why this bridge exists.
    _loadSignupStatus();
    final pendingError = PendingAuthMessage.takeAndClear();
    if (pendingError != null) {
      _model.errorMessage = pendingError;
    }
    // main.dart restores AppSession from a persisted Supabase session
    // before runApp() runs, but nothing ever acted on that — this page
    // rendered the login form unconditionally regardless, so a browser
    // reload (or staff device reopening the app) always bounced back to
    // login even with a valid, already-restored session sitting in
    // memory. If restore already succeeded, skip straight to Home instead
    // of asking the user to log in again.
    if (AppSession.instance.currentOrgId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(HomePageWidget.routePath);
      });
      return;
    }
  }

  @override
  void dispose() {
    _mobile.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _handleVendorLogin() async {
    final email = _model.vendorEmailController!.text.trim();
    final password = _model.vendorPasswordController!.text;

    if (email.isEmpty || password.isEmpty) {
      safeSetState(() =>
          _model.errorMessage = AppLocalizations.of(context).lpEnterBoth);
      return;
    }

    safeSetState(() {
      _model.isLoading = true;
      _model.errorMessage = null;
    });

    await LoginMemory.set(remember: _remember);
    try {
      final authResponse = await SupaFlow.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = authResponse.user;
      if (user == null) {
        throw Exception('Invalid email or password.');
      }

      // NG-BRIEF-vendor-auth-flow.md §2a/§2b recovery path (org_members
      // empty -> read org_name/phone/owner_name back out of auth metadata
      // -> create-org) now lives in vendor_org_resolver.dart, shared with
      // the email-confirmation deep-link auto-login path (main.dart) —
      // extracted 17 Aug 2026 rather than duplicated a second time.
      final availableOrgs = await resolveVendorOrgs(
        user,
        promptForOrgName: () => _promptForBusinessName(context),
      );

      // Which org this session lands in is decided in ONE place for all
      // four entry points — see org_resolution.dart. This used to prompt
      // whenever length > 1, which is wrong by design (Arun, 27 Aug
      // 2026): most users have exactly one org and a picker every login
      // is pure friction. The stored choice is now restored silently and
      // the picker appears only when there is no stored choice.
      if (!mounted) return;
      final resolved = await resolveActiveOrg(
        availableOrgs: availableOrgs,
        showPicker: () => showOrgSwitcherSheet(context),
      );
      if (resolved == null) {
        // Either no memberships at all, or the user belongs to several
        // and declined to choose. In the second case the app cannot
        // proceed — it does not know which company they mean, and
        // guessing is exactly what org_resolution.dart exists to
        // prevent. Sign back out so the session does not sit
        // half-established with no org.
        await SupaFlow.client.auth.signOut();
        throw Exception(availableOrgs.length > 1
            ? 'Choose an organization to continue, or sign in again.'
            : 'Your account is not linked to any organization.');
      }

      // resolveActiveOrg persists the choice itself — one writer, so the
      // call sites cannot drift apart on when it is stored.
      await establishVendorSession(user, resolved.orgId, availableOrgs);

      // "Remember me" (Arun, 12 Nov 2026): tell the phone's / browser's
      // password manager the sign-in worked, so it offers to save the
      // email and password. The app itself never stores a password.
      TextInput.finishAutofillContext();

      // First-run PIN bootstrap (28 Aug 2026). A brand-new org has
      // pin_hash NULL and zero staff, so its PIN screen cannot succeed
      // for anyone — every attempt just accrues an IP lockout. Offer to
      // set one at the only moment we know the vendor is authenticated
      // some other way.
      //
      // Email path only, deliberately: a PIN session already has a PIN
      // by definition, and PinLoginPage never reaches this code.
      // Skippable — see SetOwnerPinPageWidget for why.
      if (!mounted) return;
      if (await ownerNeedsPin(orgId: resolved.orgId, userId: user.id)) {
        if (mounted) context.go(SetOwnerPinPageWidget.routePath);
        return;
      }

      await LoginMemory.rememberOwnerDevice();
      if (mounted) context.go(HomePageWidget.routePath);
    } catch (e) {
      safeSetState(() {
        _model.errorMessage = _friendlyAuthError(e);
        _model.isLoading = false;
      });
    }
  }

  /// NG-BRIEF-vendor-auth-flow.md §2b's "re-prompt at first login if
  /// absent" option — used only when an org-less authenticated user has
  /// no org_name stashed in their auth metadata (an account that signed
  /// up before this recovery path existed). Returns null on cancel.
  Future<String?> _promptForBusinessName(BuildContext context) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('One more thing'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "We need your business name to finish setting up your account.",
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Business name',
                hintText: 'e.g. Arun Packers and Couriers',
              ),
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
    // After the close animation - see support_tickets_page.dart (BUG-020).
    Future.delayed(const Duration(milliseconds: 600), ctrl.dispose);
    return result;
  }

  /// Turns raw Supabase/auth exceptions into human messages. The raw
  /// AuthApiException toString (statusCode 400, code invalid_credentials…)
  /// was being shown to users verbatim.
  String _friendlyAuthError(Object e) {
    final msg = e.toString().toLowerCase();
    // BUG-001: these follow the chosen language.
    final l = AppLocalizations.of(context);
    if (msg.contains('invalid_credentials') ||
        msg.contains('invalid login credentials') ||
        msg.contains('invalid email or password')) {
      return l.lpWrongPassword;
    }
    if (msg.contains('email_not_confirmed') ||
        msg.contains('email not confirmed')) {
      return l.lpVerifyEmail;
    }
    if (msg.contains('user_already_exists') ||
        msg.contains('already registered')) {
      return l.lpEmailExists;
    }
    if (msg.contains('rate limit') || msg.contains('too many')) {
      return l.lpTooMany;
    }
    if (msg.contains('network') ||
        msg.contains('socket') ||
        msg.contains('failed host lookup')) {
      return l.lpNoInternet;
    }
    return friendlyError(e);
  }

  Future<void> _handleForgotPassword() async {
    final email = _model.vendorEmailController!.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      safeSetState(() => _model.errorMessage =
          AppLocalizations.of(context).lpForgotNeedsEmail);
      return;
    }
    safeSetState(() {
      _model.isLoading = true;
      _model.errorMessage = null;
    });
    try {
      // Explicit redirectTo, not the Auth dashboard's Site URL default —
      // same reasoning as signup_page_widget.dart's emailRedirectTo, and
      // this call had the identical gap: kAuthRedirectUrl's own doc
      // comment has the full story (16 Aug 2026 redirect-issue report).
      await SupaFlow.client.auth
          .resetPasswordForEmail(email, redirectTo: kAuthRedirectUrl);
      safeSetState(() => _resetSentTo = email);
    } catch (e) {
      safeSetState(() => _model.errorMessage = _friendlyAuthError(e));
    } finally {
      safeSetState(() => _model.isLoading = false);
    }
  }

  // ---- Login redesign (12 Nov 2026) ------------------------------------
  // One screen, two ways: Mobile number (OTP) or Email (password), with
  // "keep me logged in", and a Forgot-password view of the same screen.

  bool _mobileTab = true;
  bool _remember = true;
  bool _forgot = false;
  String? _resetSentTo;
  final _mobile = TextEditingController();

  Future<void> _sendLoginOtp() async {
    final l = AppLocalizations.of(context);
    final digits = _mobile.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) {
      safeSetState(() => _model.errorMessage = l.suPhBad);
      return;
    }
    await LoginMemory.set(remember: _remember);
    LoginMemory.setPendingPhone(digits);
    if (mounted) {
      context.go('${VendorSignupPageWidget.routePath}?mode=login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final link = authLinkColor(context);

    if (_forgot) {
      return NgAuthShell(
        title: l.auResetT,
        subtitle: l.auResetS,
        icon: Icons.lock_reset_rounded,
        onBack: () => safeSetState(() {
          _forgot = false;
          _resetSentTo = null;
          _model.errorMessage = null;
        }),
        card: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NgAuthLabel(l.lpEmail),
            TextField(
              controller: _model.vendorEmailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              cursorColor: c.acc,
              style: NgFonts.geist(color: c.text, fontSize: 15),
              decoration:
                  authInputDecoration(context, hint: 'owner@company.com'),
              onSubmitted: (_) => _handleForgotPassword(),
            ),
            if (_model.errorMessage != null) ...[
              const SizedBox(height: 12),
              NgAuthNote(_model.errorMessage!, error: true),
            ],
            const SizedBox(height: 16),
            NgPrimaryButton(
              label: l.auResetBtn,
              height: 52,
              onPressed: _model.isLoading ? null : _handleForgotPassword,
            ),
            if (_resetSentTo != null) ...[
              const SizedBox(height: 14),
              NgAuthNote(l.auResetSent(_resetSentTo!), success: true),
            ],
          ],
        ),
        below: [
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => safeSetState(() {
              _forgot = false;
              _mobileTab = true;
              _model.errorMessage = null;
            }),
            child: NgAuthNote(l.auNoPassword, icon: Icons.sms_outlined),
          ),
        ],
      );
    }

    Widget tab(String label, bool mobile) {
      final on = _mobileTab == mobile;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: Material(
            color: on ? kAuthBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => safeSetState(() {
                _mobileTab = mobile;
                _model.errorMessage = null;
              }),
              child: SizedBox(
                height: 40,
                child: Center(
                  child: Text(label,
                      style: NgFonts.geist(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: on ? Colors.white : c.mute)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final rememberRow = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => safeSetState(() => _remember = !_remember),
      child: SizedBox(
        height: 46,
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _remember,
                activeColor: kAuthBlue,
                checkColor: Colors.white,
                onChanged: (v) => safeSetState(() => _remember = v ?? true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(l.auKeep,
                  style: NgFonts.geist(fontSize: 14, color: c.text)),
            ),
          ],
        ),
      ),
    );

    final mobileForm = <Widget>[
      NgAuthLabel(l.suPh),
      TextField(
        controller: _mobile,
        keyboardType: TextInputType.phone,
        maxLength: 10,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        autofillHints: const [AutofillHints.telephoneNumberNational],
        cursorColor: c.acc,
        onSubmitted: (_) => _sendLoginOtp(),
        style: NgFonts.mono(
            fontSize: 16, fontWeight: FontWeight.w500, color: c.text),
        decoration: authInputDecoration(
          context,
          hint: '98400 11223',
          prefix: Padding(
            padding: const EdgeInsets.only(left: 14, right: 10),
            child: Text('+91',
                style: NgFonts.mono(
                    fontSize: 15, fontWeight: FontWeight.w500, color: c.soft)),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(l.auSmsHint, style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
    ];

    final emailForm = <Widget>[
      NgAuthLabel(l.lpEmail),
      TextFormField(
        controller: _model.vendorEmailController,
        focusNode: _model.vendorEmailFocusNode,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email, AutofillHints.username],
        cursorColor: c.acc,
        style: NgFonts.geist(color: c.text, fontSize: 15),
        decoration: authInputDecoration(context, hint: 'owner@company.com'),
      ),
      const SizedBox(height: 14),
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: NgAuthLabel(l.lpPassword)),
          GestureDetector(
            onTap: _model.isLoading
                ? null
                : () => safeSetState(() {
                      _forgot = true;
                      _model.errorMessage = null;
                    }),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(l.lpForgot,
                  style: NgFonts.geist(
                      color: link, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
      TextFormField(
        controller: _model.vendorPasswordController,
        focusNode: _model.vendorPasswordFocusNode,
        obscureText: !_model.vendorPasswordVisible,
        autofillHints: const [AutofillHints.password],
        cursorColor: c.acc,
        onFieldSubmitted: (_) => _handleVendorLogin(),
        style: NgFonts.geist(color: c.text, fontSize: 15),
        decoration: authInputDecoration(
          context,
          hint: l.lpPasswordHint,
          suffix: IconButton(
            tooltip: l.lpPassword,
            icon: Icon(
              _model.vendorPasswordVisible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: c.mute,
              size: 20,
            ),
            onPressed: () => safeSetState(() =>
                _model.vendorPasswordVisible = !_model.vendorPasswordVisible),
          ),
        ),
      ),
    ];

    Widget linkRow(String prefix, String action, VoidCallback onTap,
            {bool last = false}) =>
        InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            decoration: BoxDecoration(
              border: last ? null : Border(bottom: BorderSide(color: c.w06)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      if (prefix.isNotEmpty) TextSpan(text: '$prefix '),
                      TextSpan(
                          text: action,
                          style: NgFonts.geist(
                              color: link, fontWeight: FontWeight.w600)),
                    ]),
                    style: NgFonts.geist(fontSize: 14, color: c.text),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 20, color: c.mute),
              ],
            ),
          ),
        );

    return NgAuthShell(
      title: l.lpLogIn,
      subtitle: l.auChoose,
      showLogo: true,
      onBack: () => context.go('/'),
      trailing: LanguageQuickButton(iconColor: Colors.white),
      card: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                tab(l.suPh, true),
                const SizedBox(width: 4),
                tab(l.lpEmail, false),
              ]),
            ),
            const SizedBox(height: 18),
            ...(_mobileTab ? mobileForm : emailForm),
            const SizedBox(height: 8),
            rememberRow,
            if (_model.errorMessage != null) ...[
              const SizedBox(height: 6),
              NgAuthNote(_model.errorMessage!, error: true),
            ],
            const SizedBox(height: 10),
            NgPrimaryButton(
              label: _model.isLoading
                  ? '…'
                  : (_mobileTab ? l.suSend : l.lpLogIn),
              height: 52,
              onPressed: _model.isLoading
                  ? null
                  : (_mobileTab ? _sendLoginOtp : _handleVendorLogin),
            ),
          ],
        ),
      ),
      below: [
        if (_signupStatus != null) ...[
          const SizedBox(height: 12),
          _signupBanner(_signupStatus!),
        ],
        const SizedBox(height: 14),
        NgAuthCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              linkRow(l.auNew, l.lpCreateAccount,
                  () => context.go(VendorSignupPageWidget.routePath)),
              // A phone already tied to a company keeps its PIN screen one
              // tap away; any other phone offers the staff door.
              DeviceOrgBinding.isBound
                  ? linkRow('', l.lpBackToPin,
                      () => context.go(PinLoginPageWidget.routePath),
                      last: true)
                  : linkRow(l.auStaffQ, l.auStaffJoin, () async {
                      await DeviceOrgBinding.unbind();
                      if (!context.mounted) return;
                      context.go(OrgBindingPageWidget.routePath);
                    }, last: true),
            ],
          ),
        ),
      ],
    );
  }

  String? _signupStatus;

  Future<void> _loadSignupStatus() async {
    final user = SupaFlow.client.auth.currentUser;
    if (user == null || (user.phone ?? '').isEmpty) return;
    try {
      final row = await SupaFlow.client
          .from('vendor_signups')
          .select('status, plan_choice')
          .eq('auth_user_id', user.id)
          .maybeSingle();
      if (row == null || row['plan_choice'] != null) return;
      if (mounted) setState(() => _signupStatus = row['status'] as String?);
    } catch (_) {
      // No table yet (migration not run) or offline: no banner.
    }
  }

  Widget _signupBanner(String status) {
    final l = AppLocalizations.of(context);
    final c = NgPalette.of(context);
    final (tone, icon, text) = switch (status) {
      'approved' => (NgStatus.green, Icons.verified_rounded, l.suBnOk),
      'rejected' => (NgStatus.red, Icons.error_outline_rounded, l.suBnNo),
      _ => (NgStatus.amber, Icons.hourglass_top_rounded, l.suBnP),
    };
    final s = c.status(tone);
    return Material(
      color: s.bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.go(VendorSignupPageWidget.routePath),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: s.fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text,
                    style: NgFonts.geist(
                        color: c.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600)),
              ),
              Text(l.suView,
                  style: NgFonts.geist(
                      color: c.acc,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBox(String message) {
    final c = NgPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.redBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: c.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: NgFonts.geist(color: c.red, fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    Iterable<String>? autofillHints,
  }) {
    final c = NgPalette.of(context);
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      autofillHints: autofillHints,
      keyboardType: keyboardType,
      cursorColor: c.acc,
      style: NgFonts.geist(color: c.text, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: NgFonts.geist(color: c.faint, fontSize: 15),
        prefixIcon: Icon(icon, color: c.faint, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: c.s1,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.w08),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.acc, width: 1.5),
        ),
      ),
    );
  }
}
