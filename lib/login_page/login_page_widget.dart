import '/l10n/gen/app_localizations.dart';
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
import '/components/language_quick_button.dart';
import '/components/theme_quick_button.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/flutter_flow_theme.dart' show kBrandAccent;
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
    _model.dispose();
    super.dispose();
  }

  Future<void> _handleVendorLogin() async {
    final email = _model.vendorEmailController!.text.trim();
    final password = _model.vendorPasswordController!.text;

    if (email.isEmpty || password.isEmpty) {
      safeSetState(() => _model.errorMessage = 'Enter email and password.');
      return;
    }

    safeSetState(() {
      _model.isLoading = true;
      _model.errorMessage = null;
    });

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
    ctrl.dispose();
    return result;
  }

  /// Turns raw Supabase/auth exceptions into human messages. The raw
  /// AuthApiException toString (statusCode 400, code invalid_credentials…)
  /// was being shown to users verbatim.
  String _friendlyAuthError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('invalid_credentials') ||
        msg.contains('invalid login credentials')) {
      return 'Email or password is incorrect. Please try again.';
    }
    if (msg.contains('email_not_confirmed') ||
        msg.contains('email not confirmed')) {
      return 'Please verify your email first — check your inbox for the confirmation link.';
    }
    if (msg.contains('user_already_exists') ||
        msg.contains('already registered')) {
      return 'An account with this email already exists. Try logging in instead.';
    }
    if (msg.contains('rate limit') || msg.contains('too many')) {
      return 'Too many attempts. Please wait a minute and try again.';
    }
    if (msg.contains('network') ||
        msg.contains('socket') ||
        msg.contains('failed host lookup')) {
      return 'Could not reach the server. Check your internet connection.';
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _handleForgotPassword() async {
    final email = _model.vendorEmailController!.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      safeSetState(() => _model.errorMessage =
          'Enter your account email above first, then tap Forgot password.');
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Password reset link sent to $email. Check your inbox '
              '(and spam folder).',
              style: NgFonts.geist(),
            ),
            backgroundColor: const Color(0xFF5CCB89),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      safeSetState(() => _model.errorMessage = _friendlyAuthError(e));
    } finally {
      safeSetState(() => _model.isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: c.bg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              NgHeaderButton(
                                  child: ThemeQuickButton(iconColor: c.soft)),
                              const SizedBox(width: 8),
                              NgHeaderButton(
                                  child:
                                      LanguageQuickButton(iconColor: c.soft)),
                            ],
                          ),
                          const SizedBox(height: 36),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              // Nagarva platform logo; the truck icon is the
                              // fallback so the screen never breaks.
                              child: Image.asset(
                                'assets/images/nagarva_logo.png',
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 60,
                                  height: 60,
                                  color: c.status(NgStatus.accent).bg,
                                  child: const Icon(Icons.local_shipping,
                                      color: kBrandAccent, size: 32),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          // Shared multi-tenant gateway: no org is known yet,
                          // so this shows the platform, never a tenant brand
                          // (CLAUDE.md known bug #5).
                          Text('Welcome back',
                              style: NgFonts.geist(
                                  fontSize: 30,
                                  height: 1.15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.6,
                                  color: c.text)),
                          const SizedBox(height: 8),
                          Text('Sign in to Nagarva — industry ERP for packers '
                              '& movers',
                              style: NgFonts.geist(fontSize: 15, color: c.mute)),
                          const SizedBox(height: 28),
                          _buildVendorForm(),
                          const Spacer(),
                          const SizedBox(height: 22),
                          // Bound vs. unbound device get different footer
                          // links, never both. A BOUND device only reaches
                          // this page via PinLoginPage's "Use email login
                          // instead"; for that visitor "Joining a team?"
                          // would unbind an already-correct device. An
                          // UNBOUND device lands here by default, and the
                          // org/invite-code path is the one a staff member
                          // who installed the app manually needs.
                          DeviceOrgBinding.isBound
                              ? _bottomLink(
                                  prefix: '',
                                  action: 'Back to PIN login',
                                  onTap: () =>
                                      context.go(PinLoginPageWidget.routePath),
                                )
                              : _bottomLink(
                                  prefix: 'Joining a team? ',
                                  action: 'Use an org or invite code',
                                  onTap: () async {
                                    await DeviceOrgBinding.unbind();
                                    if (mounted) {
                                      context.pushNamed(
                                          OrgBindingPageWidget.routeName);
                                    }
                                  },
                                ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_rounded, color: c.faint, size: 14),
                              const SizedBox(width: 5),
                              Text('Secured & encrypted',
                                  style: NgFonts.geist(
                                      color: c.faint, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Shared shape for the page's single footer link — two mutually
  /// exclusive variants render depending on `DeviceOrgBinding.isBound`.
  Widget _bottomLink({
    required String prefix,
    required String action,
    required VoidCallback onTap,
  }) {
    final c = NgPalette.of(context);
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: RichText(
          text: TextSpan(
            style: NgFonts.geist(color: c.mute, fontSize: 13.5),
            children: [
              if (prefix.isNotEmpty) TextSpan(text: prefix),
              TextSpan(
                text: action,
                style: NgFonts.geist(
                    color: c.acc, fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVendorForm() {
    final c = NgPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Email',
            style: NgFonts.geist(
                fontSize: 13, fontWeight: FontWeight.w500, color: c.mute)),
        const SizedBox(height: 6),
        _textField(
          controller: _model.vendorEmailController!,
          focusNode: _model.vendorEmailFocusNode!,
          hint: 'owner@company.com',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text('Password',
                  style: NgFonts.geist(
                      fontSize: 13, fontWeight: FontWeight.w500, color: c.mute)),
            ),
            GestureDetector(
              onTap: _model.isLoading ? null : _handleForgotPassword,
              child: Text('Forgot?',
                  style: NgFonts.geist(
                      color: c.acc, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _textField(
          controller: _model.vendorPasswordController!,
          focusNode: _model.vendorPasswordFocusNode!,
          hint: 'Your password',
          icon: Icons.lock_outline_rounded,
          obscureText: !_model.vendorPasswordVisible,
          suffixIcon: IconButton(
            icon: Icon(
              _model.vendorPasswordVisible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: c.faint,
              size: 20,
            ),
            onPressed: () => safeSetState(
              () =>
                  _model.vendorPasswordVisible = !_model.vendorPasswordVisible,
            ),
          ),
        ),
        if (_model.errorMessage != null) ...[
          const SizedBox(height: 14),
          _errorBox(_model.errorMessage!),
        ],
        const SizedBox(height: 20),
        Material(
          color: c.accBtn,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _model.isLoading ? null : _handleVendorLogin,
            child: SizedBox(
              height: 54,
              child: Center(
                child: _model.isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: NgPalette.onAcc))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Log in',
                              style: NgFonts.geist(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: NgPalette.onAcc)),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded,
                              size: 20, color: NgPalette.onAcc),
                        ],
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Owners who signed up by mobile number have no password — the
        // signup screen doubles as their OTP login (vendor signup, 21 Oct
        // 2026).
        Center(
          child: NgLinkButton(
            AppLocalizations.of(context).suMobileLogin,
            icon: Icons.sms_outlined,
            onTap: _model.isLoading
                ? null
                : () => context.go(VendorSignupPageWidget.routePath),
          ),
        ),
        if (_signupStatus != null) ...[
          const SizedBox(height: 12),
          _signupBanner(_signupStatus!),
        ],
        const SizedBox(height: 14),
        // Approval-first signup by mobile number replaced the email
        // SignupPage as the way in (21 Oct 2026).
        _bottomLink(
          prefix: 'New here? ',
          action: 'Create an account',
          onTap: () => context.go(VendorSignupPageWidget.routePath),
        ),
      ],
    );
  }

  /// A mobile-signup application still on this device's session: show
  /// where it stands, the handoff's "Login A shows status banner".
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
  }) {
    final c = NgPalette.of(context);
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
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
