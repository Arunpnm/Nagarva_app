import '/flutter_flow/flutter_flow_theme.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/app_session.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'signup_page_model.dart';
export 'signup_page_model.dart';

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

    final company = _model.companyController!.text.trim();
    final email = _model.emailController!.text.trim();
    final password = _model.passwordController!.text;
    final phone = _model.phoneController!.text.trim();

    safeSetState(() {
      _model.isLoading = true;
      _model.errorMessage = null;
    });

    try {
      // 1. Create (or, on a retried signup, re-authenticate as) the
      // Supabase Auth user. Org creation itself no longer happens here —
      // it moved server-side into create-org / create_org_with_owner(),
      // which is atomic, idempotent, and is the only thing allowed to
      // write organizations/org_members now.
      final authResponse = await SupaFlow.client.auth.signUp(
        email: email,
        password: password,
      );

      final user = authResponse.user;
      if (user == null) {
        safeSetState(() {
          _model.errorMessage =
              'Account created — please confirm your email, then log in.';
          _model.isLoading = false;
        });
        return;
      }

      // "Confirm email" is currently OFF, so signUp() returns a session
      // directly and SupaFlow.client's auth state now holds it — that's
      // what functions.invoke() below authenticates with. If confirm-email
      // is ever turned on (a separate, not-yet-done step), session will be
      // null here until the user clicks the emailed link; create-org can't
      // be called without a JWT, so stop and tell them to confirm instead
      // of throwing on a 401.
      if (authResponse.session == null) {
        safeSetState(() {
          _model.errorMessage =
              'Account created — please confirm your email, then log in.';
          _model.isLoading = false;
        });
        return;
      }

      // 2. Bootstrap the org via the create-org Edge Function
      // (create_org_with_owner() under the hood) instead of inserting into
      // organizations/org_members directly — that RPC is atomic, retry-safe,
      // and is the only thing with a service-role grant to write those
      // tables now.
      final res = await SupaFlow.client.functions.invoke(
        'create-org',
        body: {
          'org_name': company,
          if (phone.isNotEmpty) 'phone': phone,
        },
      );

      final data = res.data;
      if (data is! Map || data['ok'] != true) {
        final serverError =
            (data is Map && data['error'] is String) ? data['error'] as String : null;
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

      // 5. Go to org setup
      if (mounted) {
        context.go(OrgSetupPageWidget.routePath);
      }
    } catch (e) {
      safeSetState(() {
        _model.errorMessage = e.toString().replaceFirst('Exception: ', '');
        _model.isLoading = false;
      });
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
                              validator: (v) =>
                                  (v == null || !v.contains('@'))
                                      ? 'Enter a valid email'
                                      : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _model.passwordController!,
                              focusNode: _model.passwordFocusNode!,
                              obscureText: !_model.passwordVisible,
                              style: GoogleFonts.inter(color: Colors.white),
                              validator: (v) => (v == null || v.length < 6)
                                  ? 'Password must be at least 6 characters'
                                  : null,
                              decoration: _inputDecoration(
                                label: 'Password',
                                hint: 'Min. 6 characters',
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
                            _buildField(
                              controller: _model.phoneController!,
                              focusNode: _model.phoneFocusNode!,
                              label: 'Phone (optional)',
                              hint: '+91 98765 43210',
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
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
                              onPressed: _model.isLoading ? null : _handleSignup,
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
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      style: GoogleFonts.inter(color: Colors.white),
      keyboardType: keyboardType,
      validator: validator,
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
