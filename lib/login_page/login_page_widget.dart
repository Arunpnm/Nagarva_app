import '/flutter_flow/flutter_flow_theme.dart';
import '/backend/device_org_binding.dart';
import '/backend/org_resolution.dart';
import '/backend/pending_auth_message.dart';
import '/backend/supabase/supabase.dart';
import '/backend/vendor_org_resolver.dart';
import '/config/app_config.dart';
import '/components/org_switcher_sheet.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/app_session.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
              style: GoogleFonts.inter(),
            ),
            backgroundColor: const Color(0xFF2E7D32),
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
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: const Color(0xFF0F1117),
        body: SafeArea(
          top: true,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F1117), Color(0xFF1A1A2E)],
                stops: [0.0, 1.0],
                begin: AlignmentDirectional(1.0, 1.0),
                end: AlignmentDirectional(-1.0, -1.0),
              ),
            ),
            alignment: const AlignmentDirectional(0.0, 0.0),
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Column(
                        children: [
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A1200),
                              borderRadius: BorderRadius.circular(45),
                            ),
                            clipBehavior: Clip.antiAlias,
                            // Nagarva platform logo. Drop the file at
                            // assets/images/nagarva_logo.png (assets/images/
                            // is already declared in pubspec). Until the
                            // file exists, errorBuilder falls back to the
                            // old truck icon so the screen never breaks.
                            child: Image.asset(
                              'assets/images/nagarva_logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.local_shipping,
                                color: kBrandGold,
                                size: 48,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            // Was hardcoded 'Arun Packers And Couriers'
                            // (CLAUDE.md known bug #5). This screen is now
                            // the shared multi-tenant login gateway (any
                            // vendor's staff/owner can land here before an
                            // org is known), so it shows the platform name
                            // rather than one tenant's brand. Per-org
                            // branding still applies post-login (see
                            // SettingsPage / AppSession.currentOrgName).
                            'Nagarva',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.interTight(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Industry ERP for packers & movers',
                            style: GoogleFonts.inter(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2035),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.all(20),
                        child: _buildVendorForm(),
                      ),

                      const SizedBox(height: 16),
                      // Bound vs. unbound device get different footer links,
                      // never both. A BOUND device only ever reaches this
                      // page via PinLoginPageWidget's "Use email login
                      // instead" (owner setting up a PIN for the first
                      // time, or an existing staff member without one) — for
                      // that visitor, "Joining a team?" would unbind an
                      // already-correct device just to get back to the PIN
                      // screen, which is destructive, not a way back. An
                      // UNBOUND device is this page's own default landing
                      // spot (nav.dart's _initialize, NG-BRIEF-vendor-auth-
                      // flow.md §4) — for a staff member who installed the
                      // app manually instead of arriving via an invite link,
                      // the org/invite-code path is the one they need.
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

                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock,
                              color: Color(0xFF888899), size: 14),
                          const SizedBox(width: 6),
                          Text(
                            'Secured & Encrypted',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF888899),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Shared shape for the page's single footer link — extracted since two
  /// mutually-exclusive variants render here depending on
  /// `DeviceOrgBinding.isBound` (see the call site).
  Widget _bottomLink({
    required String prefix,
    required String action,
    required VoidCallback onTap,
  }) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: RichText(
          text: TextSpan(
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
            children: [
              if (prefix.isNotEmpty) TextSpan(text: prefix),
              TextSpan(
                text: action,
                style: GoogleFonts.inter(
                  color: kBrandGold,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVendorForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _textField(
          controller: _model.vendorEmailController!,
          focusNode: _model.vendorEmailFocusNode!,
          label: 'Email',
          hint: 'owner@company.com',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _textField(
          controller: _model.vendorPasswordController!,
          focusNode: _model.vendorPasswordFocusNode!,
          label: 'Password',
          hint: 'Your password',
          icon: Icons.lock_outline,
          obscureText: !_model.vendorPasswordVisible,
          suffixIcon: IconButton(
            icon: Icon(
              _model.vendorPasswordVisible
                  ? Icons.visibility_off
                  : Icons.visibility,
              color: Colors.white38,
              size: 20,
            ),
            onPressed: () => safeSetState(
              () =>
                  _model.vendorPasswordVisible = !_model.vendorPasswordVisible,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: _model.isLoading ? null : _handleForgotPassword,
            child: Text(
              'Forgot password?',
              style: GoogleFonts.inter(
                color: kBrandGold,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (_model.errorMessage != null) ...[
          const SizedBox(height: 14),
          _errorBox(_model.errorMessage!),
        ],
        const SizedBox(height: 18),
        FFButtonWidget(
          text: 'Log In',
          onPressed: _model.isLoading ? null : _handleVendorLogin,
          options: FFButtonOptions(
            width: double.infinity,
            height: 52,
            color: kBrandGold,
            textStyle: GoogleFonts.interTight(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            borderRadius: BorderRadius.circular(12),
            elevation: 0,
          ),
          showLoadingIndicator: _model.isLoading,
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "New here? ",
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
            ),
            GestureDetector(
              onTap: () => context.go(SignupPageWidget.routePath),
              child: Text(
                'Create an account',
                style: GoogleFonts.inter(
                  color: kBrandGold,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _errorBox(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 13),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: GoogleFonts.inter(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.inter(color: Colors.white54),
        hintStyle: GoogleFonts.inter(color: Colors.white24),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFF2A2D45),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF3A3D55)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBrandGold, width: 1.5),
        ),
      ),
    );
  }
}
