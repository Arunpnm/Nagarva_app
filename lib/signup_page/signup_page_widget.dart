import '/flutter_flow/flutter_flow_theme.dart';
import '/backend/edge_function_errors.dart';
import '/backend/platform_admin_status.dart';
import '/backend/supabase/supabase.dart';
import '/config/app_config.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/app_session.dart';
import '/index.dart';
import '/widgets/signup_success_dialog.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'signup_page_model.dart';
export 'signup_page_model.dart';

// NG-BRIEF-vendor-auth-flow.md §3. The URLs themselves moved to
// /config/app_config.dart on 18 Aug 2026, when Settings → Help & About
// started needing the same two links — one definition, two screens.
// These aliases stay so this file's own call sites read unchanged; see
// kTermsUrl/kPrivacyPolicyUrl for the live-verification note and why
// Play Store review depends on the privacy link.
const String kSignupTermsUrl = kTermsUrl;
const String kSignupPrivacyUrl = kPrivacyPolicyUrl;

class SignupPageWidget extends StatefulWidget {
  const SignupPageWidget({super.key});

  static String routeName = 'SignupPage';
  static String routePath = '/signup';

  @override
  State<SignupPageWidget> createState() => _SignupPageWidgetState();
}

class _SignupPageWidgetState extends State<SignupPageWidget> {
  late SignupPageModel _model;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => SignupPageModel());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_model.agreedToTerms) {
      safeSetState(() {
        _model.errorMessage =
            'Please agree to the Terms & Conditions to continue.';
      });
      return;
    }

    final ownerName = _model.ownerNameController!.text.trim();
    final company = _model.companyController!.text.trim();
    final email = _model.emailController!.text.trim();
    final password = _model.passwordController!.text;
    final phone = _model.phoneController!.text.trim();
    final inviteCode = _model.inviteCodeController!.text.trim();

    safeSetState(() {
      _model.isLoading = true;
      _model.errorMessage = null;
    });

    try {
      // 0. Validate the invite code BEFORE creating an auth account —
      // create-org (below) is still the real, atomic gate (this RPC can
      // race two people onto the last use of the same single-use code;
      // the loser gets create-org's own 403, same as before this check
      // existed), but checking here means the common case — a blank or
      // wrong code — never creates an orphaned "confirmed, no org"
      // account in the first place. is_invite_code_valid is
      // SECURITY DEFINER + anon-callable, returns a bare boolean only —
      // no code enumeration, no other invite_codes columns exposed.
      final codeValid = await SupaFlow.client.rpc(
        'is_invite_code_valid',
        params: {'p_code': inviteCode},
      ) as bool? ?? false;
      if (!codeValid) {
        safeSetState(() {
          _model.errorMessage =
              'That invite code is invalid or has already been used. '
              'Nagarva is currently in closed beta — contact us for access.';
          _model.isLoading = false;
        });
        return;
      }

      // 1. Create (or, on a retried signup, re-authenticate as) the
      // Supabase Auth user. Org creation itself no longer happens here —
      // it moved server-side into create-org / create_org_with_owner(),
      // which is atomic, idempotent, and is the only thing allowed to
      // write organizations/org_members now.
      //
      // NG-BRIEF-vendor-auth-flow.md §2b: org_name/phone go into `data`
      // (auth.users.raw_user_meta_data) so they survive the confirmation
      // gap — the user may confirm hours later, on another device, with
      // this screen long gone. login_page_widget.dart's recovery path
      // reads them back out of user.userMetadata.
      final authResponse = await SupaFlow.client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: kAuthRedirectUrl,
        data: {
          'org_name': company,
          'owner_name': ownerName,
          if (phone.isNotEmpty) 'phone': phone,
          // Closed-beta gate (16 Aug 2026): stashed in auth metadata for
          // the same reason org_name/phone are — a confirmation-gap retry
          // (vendor_org_resolver.dart) calls create-org again later, in a
          // session that never saw this form, and needs the code to still
          // be available then.
          if (inviteCode.isNotEmpty) 'invite_code': inviteCode,
        },
      );

      final user = authResponse.user;
      if (user == null) {
        await _presentSignupSuccess(email: email, orgName: company);
        return;
      }

      // §2c: Supabase's anti-enumeration behaviour for signUp() against an
      // ALREADY-registered email also returns 200 with session == null —
      // indistinguishable from a genuine brand-new signup by that alone,
      // which is why this used to tell a returning user to "confirm your
      // email" for a confirmation that will never arrive (they're already
      // confirmed). The one field that tells the two apart: a real new
      // signup gets a real new identity (non-empty `identities`); the
      // anti-enumeration response mirrors the existing user back with an
      // EMPTY identities list, since nothing was actually created.
      if ((user.identities ?? const []).isEmpty) {
        safeSetState(() {
          _model.errorMessage =
              'You already have an account with this email — log in instead.';
          _model.isLoading = false;
        });
        return;
      }

      // "Confirm email" is ON as of this pass (confirmed live, turned on
      // between 15 Jul and 1 Aug) — session is null here until the user
      // clicks the emailed link. Previously this was also the terminal
      // state: create-org was never called again for anyone. It's not
      // anymore — login_page_widget.dart's _handleVendorLogin now creates
      // the org itself on first post-confirmation login, reading org_name/
      // phone back from the metadata stashed above. This branch still
      // exists (and still shows the same message) for the OFF case never
      // fully going away, and so this screen behaves correctly either way
      // without needing to know which mode the project is in.
      if (authResponse.session == null) {
        await _presentSignupSuccess(email: email, orgName: company);
        return;
      }

      // 2. Bootstrap the org via the create-org Edge Function
      // (create_org_with_owner() under the hood) instead of inserting into
      // organizations/org_members directly — that RPC is atomic, retry-safe,
      // and is the only thing with a service-role grant to write those
      // tables now.
      // owner_name is sent but NOT yet read by create-org/index.ts or
      // create_org_with_owner() — neither has been updated to accept or
      // persist it (would need a migration for the RPC's signature, which
      // this pass deliberately doesn't ship — see the report). Sending it
      // now is forward-compatible and harmless either way: an unread JSON
      // field the server ignores today, ready the moment that migration
      // lands with no further client change needed.
      final res = await SupaFlow.client.functions.invoke(
        'create-org',
        body: {
          'org_name': company,
          'owner_name': ownerName,
          if (phone.isNotEmpty) 'phone': phone,
          if (inviteCode.isNotEmpty) 'invite_code': inviteCode,
        },
      );

      final data = res.data;
      if (data is! Map || data['ok'] != true) {
        final serverError = (data is Map && data['error'] is String)
            ? data['error'] as String
            : null;
        throw Exception(serverError ?? 'Could not create organisation.');
      }

      // 3. caller_role is the ONLY thing this gates on — standalone, never
      // combined with is_new. A staff/manager account at someone else's
      // org that lands here also gets is_new=false, identical to a genuine
      // signup retry on that field alone; only caller_role tells them
      // apart, and only 'owner' may ever get a vendor session out of this
      // screen.
      final callerRole = data['caller_role'];
      if (callerRole != 'owner') {
        safeSetState(() {
          _model.errorMessage =
              'This email already belongs to a team on Nagarva. Please log in instead.';
          _model.isLoading = false;
        });
        return;
      }

      // 4. Set app session from create-org's response — org_id/org_slug/
      // plan fields all come from the server now, not computed client-side.
      AppSession.instance.setVendorSession(
        authUserId: user.id,
        orgId: data['org_id'] as String,
        orgName: data['org_name'] as String? ?? company,
        orgSlug: data['org_slug'] as String,
        limits: (data['limits'] is Map)
            ? Map<String, dynamic>.from(data['limits'] as Map)
            : {},
        features: (data['features'] is Map)
            ? Map<String, dynamic>.from(data['features'] as Map)
            : {},
        planName: data['plan_name'] as String? ?? 'Free Trial',
        planStatus: data['plan_status'] as String?,
        trialEndsAt: data['trial_ends_at'] != null
            ? DateTime.tryParse(data['trial_ends_at'] as String)
            : null,
        orgActive: data['org_active'] as bool? ?? true,
      );
      // A fresh signup's auth user is brand new by construction — checking
      // anyway rather than assuming, same "confirm, don't guess" rule this
      // pass followed for platform_admins' own live schema (see
      // platform_admin_status.dart) — cheap, single-row lookup.
      await refreshPlatformAdminStatus();

      // 5. Go to org setup
      if (mounted) {
        context.go(OrgSetupPageWidget.routePath);
      }
    } catch (e) {
      safeSetState(() {
        _model.errorMessage = extractFunctionErrorMessage(e,
            fallback: e.toString().replaceFirst('Exception: ', ''));
        _model.isLoading = false;
      });
    }
  }

  /// Success path for "Confirm email" being on — replaces the old inline
  /// "Account created — please confirm your email" banner, which rendered
  /// in this page's error-red styling despite being a success (16 Aug
  /// 2026 finding). The inline banner (_model.errorMessage) stays for
  /// actual signup FAILURES only; this is the only success path now.
  Future<void> _presentSignupSuccess({
    required String email,
    required String orgName,
  }) async {
    final onOpenEmail = await _resolveOpenEmailAction();
    if (!mounted) return;
    await showSignupSuccess(
      context,
      email: email,
      orgName: orgName,
      onLogin: () {
        if (mounted) context.go(LoginPageWidget.routePath);
      },
      onResend: () => SupaFlow.client.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: kAuthRedirectUrl,
      ),
      onOpenEmail: onOpenEmail,
    );
    if (mounted) safeSetState(() => _model.isLoading = false);
  }

  /// android_intent_plus's canResolveActivity() needs the matching
  /// `<queries>` declaration in AndroidManifest.xml (Android 11+ package
  /// visibility filtering) — added alongside this. Resolved BEFORE the
  /// dialog is shown, not at tap-time: if this throws, isn't Android
  /// (canResolveActivity() itself returns false off-Android), or finds no
  /// matching app, the dialog's "Open Email App" button doesn't render at
  /// all rather than showing a control that would silently do nothing.
  Future<VoidCallback?> _resolveOpenEmailAction() async {
    try {
      const intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        category: 'android.intent.category.APP_EMAIL',
      );
      final canResolve = await intent.canResolveActivity();
      if (canResolve != true) return null;
      return () {
        // Already resolvability-checked above; a failure here would be a
        // rare race (app uninstalled between check and tap) — swallow
        // rather than surface, same as this dialog's own "silent no-op
        // instead of a dead control" rule.
        intent.launch().catchError((_) {});
      };
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1117),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo / header
                      Column(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A1200),
                              borderRadius: BorderRadius.circular(40),
                            ),
                            clipBehavior: Clip.antiAlias,
                            // Nagarva platform logo — same asset/fallback
                            // convention as LoginPage.
                            child: Image.asset(
                              'assets/images/nagarva_logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.local_shipping,
                                color: kBrandGold,
                                size: 44,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Create your account',
                            style: GoogleFonts.interTight(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Start your free trial today',
                            style: GoogleFonts.inter(
                              color: Colors.white54,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // Form card
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2035),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildField(
                              controller: _model.ownerNameController!,
                              focusNode: _model.ownerNameFocusNode!,
                              label: 'Owner Name',
                              hint: 'Your full name',
                              icon: Icons.person_outline,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Owner name is required'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            _buildField(
                              controller: _model.companyController!,
                              focusNode: _model.companyFocusNode!,
                              label: 'Company Name',
                              hint: 'e.g. Arun Packers and Couriers',
                              icon: Icons.business,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Company name is required'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            _buildField(
                              controller: _model.emailController!,
                              focusNode: _model.emailFocusNode!,
                              label: 'Email',
                              hint: 'owner@company.com',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) => (v == null || !v.contains('@'))
                                  ? 'Enter a valid email'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _model.passwordController!,
                              focusNode: _model.passwordFocusNode!,
                              obscureText: !_model.passwordVisible,
                              style: GoogleFonts.inter(color: Colors.white),
                              validator: (v) => (v == null || v.length < 8)
                                  ? 'Password must be at least 8 characters'
                                  : null,
                              decoration: _inputDecoration(
                                label: 'Password',
                                hint: 'Min. 8 characters',
                                icon: Icons.lock_outline,
                              ).copyWith(
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _model.passwordVisible
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: Colors.white38,
                                    size: 20,
                                  ),
                                  onPressed: () => safeSetState(() =>
                                      _model.passwordVisible =
                                          !_model.passwordVisible),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _model.confirmPasswordController!,
                              focusNode: _model.confirmPasswordFocusNode!,
                              obscureText: !_model.confirmPasswordVisible,
                              style: GoogleFonts.inter(color: Colors.white),
                              // §3: validated client-side before submit via
                              // the Form's own validate() — an inline error
                              // right at this field, never a network round
                              // trip just to discover the mismatch.
                              validator: (v) =>
                                  (v != _model.passwordController!.text)
                                      ? 'Passwords do not match'
                                      : null,
                              decoration: _inputDecoration(
                                label: 'Confirm Password',
                                hint: 'Re-enter your password',
                                icon: Icons.lock_outline,
                              ).copyWith(
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _model.confirmPasswordVisible
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: Colors.white38,
                                    size: 20,
                                  ),
                                  onPressed: () => safeSetState(() =>
                                      _model.confirmPasswordVisible =
                                          !_model.confirmPasswordVisible),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildField(
                              controller: _model.phoneController!,
                              focusNode: _model.phoneFocusNode!,
                              label: 'Phone (optional)',
                              hint: '+91 98765 43210',
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 16),
                            // Closed-beta gate — required client-side as of
                            // 17 Aug 2026 (was deliberately optional; Arun
                            // overrode that after finding a blank code sailed
                            // through this form and only failed later, at
                            // create-org, after an auth account already
                            // existed). is_invite_code_valid (called in
                            // _handleSignup, before signUp()) is the real
                            // check; this validator just stops an obviously
                            // blank submission before that round trip. NOTE
                            // for whoever turns the gate off at Item 12: this
                            // validator does NOT know the server-side flag,
                            // so it will keep demanding *some* text even
                            // once codes stop mattering — revisit then.
                            _buildField(
                              controller: _model.inviteCodeController!,
                              focusNode: _model.inviteCodeFocusNode!,
                              label: 'Invite Code',
                              hint: 'Required during closed beta',
                              icon: Icons.key_outlined,
                              textCapitalization: TextCapitalization.characters,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Invite code is required during closed beta'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            // §3: required, disables the submit button
                            // until ticked — not a validate-on-submit
                            // error, an actually-disabled button.
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Checkbox(
                                  value: _model.agreedToTerms,
                                  activeColor: kBrandGold,
                                  onChanged: (v) => safeSetState(
                                      () => _model.agreedToTerms = v ?? false),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: RichText(
                                      text: TextSpan(
                                        style: GoogleFonts.inter(
                                          color: Colors.white54,
                                          fontSize: 13,
                                        ),
                                        children: [
                                          const TextSpan(
                                              text: 'I agree to the '),
                                          TextSpan(
                                            text: 'Terms & Conditions',
                                            style: GoogleFonts.inter(
                                              color: kBrandGold,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            recognizer: TapGestureRecognizer()
                                              ..onTap = () => launchUrl(
                                                  Uri.parse(kSignupTermsUrl),
                                                  mode: LaunchMode
                                                      .externalApplication),
                                          ),
                                          const TextSpan(text: ' and '),
                                          TextSpan(
                                            text: 'Privacy Policy',
                                            style: GoogleFonts.inter(
                                              color: kBrandGold,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            recognizer: TapGestureRecognizer()
                                              ..onTap = () => launchUrl(
                                                  Uri.parse(kSignupPrivacyUrl),
                                                  mode: LaunchMode
                                                      .externalApplication),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_model.errorMessage != null) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _model.errorMessage!,
                                  style: GoogleFonts.inter(
                                    color: Colors.redAccent,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            FFButtonWidget(
                              text: 'Create Account',
                              onPressed:
                                  (_model.isLoading || !_model.agreedToTerms)
                                      ? null
                                      : _handleSignup,
                              options: FFButtonOptions(
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
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Login link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Already have an account? ',
                            style: GoogleFonts.inter(
                              color: Colors.white54,
                              fontSize: 14,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => context.go(LoginPageWidget.routePath),
                            child: Text(
                              'Log in',
                              style: GoogleFonts.inter(
                                color: kBrandGold,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
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

  Widget _buildField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      style: GoogleFonts.inter(color: Colors.white),
      keyboardType: keyboardType,
      validator: validator,
      textCapitalization: textCapitalization,
      decoration: _inputDecoration(label: label, hint: hint, icon: icon),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: GoogleFonts.inter(color: Colors.white54),
      hintStyle: GoogleFonts.inter(color: Colors.white24),
      prefixIcon: Icon(icon, color: Colors.white38, size: 20),
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      errorStyle: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12),
    );
  }
}
