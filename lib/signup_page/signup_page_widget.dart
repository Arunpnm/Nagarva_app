import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
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

  String _slugify(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
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
      // 1. Create Supabase Auth user
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

      final userId = user.id;
      final baseSlug = _slugify(company);
      // Append 4 chars of userId to avoid collisions
      final slug = '$baseSlug-${userId.replaceAll('-', '').substring(0, 4)}';

      // 2. Load the default trial plan (fetched before the org insert so
      // plan_id/plan_status/trial_ends_at can be stamped on creation —
      // previously this was fetched after and never written back, leaving
      // organizations.plan_id NULL on every signup).
      final plans = await SubscriptionPlansTable().queryRows(
        queryFn: (q) => q.eq('is_default_trial', true).limit(1),
      );
      final plan = plans.isNotEmpty ? plans.first : null;
      final trialEndsAt = DateTime.now().toUtc().add(const Duration(days: 14));

      // 3. Create organization
      // NOTE: 'email' and 'owner_id' are deliberately NOT sent here — the
      // owner-confirmed live schema for organizations is (id, name, slug,
      // gstin, phone, plan_id, plan_status, trial_ends_at, active,
      // created_at), which has neither column. Ownership is recorded via
      // org_members.role = 'owner' below instead.
      final org = await OrganizationsTable().insert({
        'name': company,
        'slug': slug,
        'phone': phone.isEmpty ? null : phone,
        'plan_id': plan?.id,
        'plan_status': 'trial',
        'trial_ends_at': trialEndsAt.toIso8601String(),
        'active': true,
      });

      final orgId = org.id!;

      // 4. Create org membership
      await OrgMembersTable().insert({
        'org_id': orgId,
        'user_id': userId,
        'role': 'owner',
      });

      // 5. Set app session
      AppSession.instance.setVendorSession(
        authUserId: userId,
        orgId: orgId,
        orgName: company,
        orgSlug: slug,
        limits: (plan?.limits is Map)
            ? Map<String, dynamic>.from(plan!.limits as Map)
            : {},
        features: (plan?.features is Map)
            ? Map<String, dynamic>.from(plan!.features as Map)
            : {},
        planName: plan?.name ?? 'Free Trial',
        trialEndsAt: org.trialEndsAt,
      );

      // 6. Go to org setup
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
                            child: const Icon(
                              Icons.local_shipping,
                              color: Color(0xFFFF6B35),
                              size: 44,
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
                                color: const Color(0xFFFF6B35),
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
                                color: const Color(0xFFFF6B35),
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
        borderSide: const BorderSide(color: Color(0xFFFF6B35), width: 1.5),
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
