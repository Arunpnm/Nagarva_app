import '/flutter_flow/flutter_flow_theme.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_session_loader.dart';
import '/components/org_switcher_sheet.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/app_session.dart';
import '/index.dart';
import '/permissions.dart';
import '/staff_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'login_page_model.dart';
export 'login_page_model.dart';

/// Two-path login:
/// - Vendor tab: Supabase Auth (email + password) — the org owner/admin.
/// - Staff tab: device-unlock model (the "Slack model"). The device must
///   have been signed in with the vendor account at least once; the staff
///   row is looked up INSIDE that authenticated, RLS-scoped session (so
///   only this org's staff are visible). The PIN itself is then verified
///   SERVER-SIDE by the `staff-login` Edge Function (bcrypt in Postgres),
///   which mints a REAL Supabase session for the staff member. The app
///   swaps to that session, so staff carry their own auth.uid() and every
///   RLS policy applies to them exactly as it does to vendors. The
///   vendor's refresh token is saved first so the sidebar Lock button can
///   silently restore the vendor session (see /staff_auth.dart).
///   No plaintext PIN is ever read or compared on the client.
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

  /// Org this device is set up for (vendor session present), else null.
  /// Shown as a banner on the Staff tab so the device state is always
  /// visible instead of guessed.
  String? _deviceOrgName;
  bool _deviceChecked = false;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => LoginPageModel());
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
    _checkDeviceSetup();
  }

  Future<void> _checkDeviceSetup() async {
    final user = SupaFlow.client.auth.currentUser;
    if (user == null) {
      safeSetState(() => _deviceChecked = true);
      return;
    }
    try {
      final members = await OrgMembersTable().queryRows(
        queryFn: (q) => q.eq('user_id', user.id).limit(1),
      );
      String? orgName;
      if (members.isNotEmpty && members.first.orgId != null) {
        final orgs = await OrganizationsTable().queryRows(
          queryFn: (q) => q.eq('id', members.first.orgId!).limit(1),
        );
        orgName = orgs.isNotEmpty ? orgs.first.name : null;
      }
      safeSetState(() {
        _deviceOrgName = orgName ?? 'your organization';
        _deviceChecked = true;
      });
    } catch (_) {
      safeSetState(() {
        _deviceOrgName = 'your organization';
        _deviceChecked = true;
      });
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

      // Every org this user belongs to (not just the first) — a consultant
      // or owner can be linked to more than one, and used to silently pick
      // members.first, ignoring the rest. See app_session.dart's
      // OrgMembershipInfo / availableOrgs.
      var members = await OrgMembersTable().queryRows(
        queryFn: (q) => q.eq('user_id', user.id),
      );
      var orgIds = members.map((m) => m.orgId).whereType<String>().toList();

      if (orgIds.isEmpty) {
        // NG-BRIEF-vendor-auth-flow.md §2a — recovery, not an error.
        // "Confirm email" now being ON means create-org never ran at
        // signup (signup_page_widget.dart stops at session == null and
        // never reaches its create-org call). A confirmed, correctly-
        // authenticated user with zero org_members rows is exactly what
        // that leaves behind — this is that user's first chance to ever
        // get one, not a hostile account. create_org_with_owner() is
        // idempotent, so this is also the one-time repair for anyone
        // already stuck this way (krish8464@gmail.com and any other
        // pre-existing orphan) — no separate data-repair script needed.
        final meta = user.userMetadata ?? const <String, dynamic>{};
        var orgName = (meta['org_name'] as String?)?.trim();
        final metaPhone = (meta['phone'] as String?)?.trim();

        if (orgName == null || orgName.isEmpty) {
          // §2b: no stashed metadata means this account signed up before
          // this fix existed (or via some other path) — there's no
          // company name anywhere to fall back to, and the brief is
          // explicit: never silently default it to the email address.
          // Ask, once, right here.
          if (!mounted) return;
          orgName = await _promptForBusinessName(context);
          if (orgName == null || orgName.trim().isEmpty) {
            safeSetState(() {
              _model.errorMessage =
                  'A business name is required to finish setting up your account.';
              _model.isLoading = false;
            });
            return;
          }
          orgName = orgName.trim();
        }

        final res = await SupaFlow.client.functions.invoke(
          'create-org',
          body: {
            'org_name': orgName,
            if (metaPhone != null && metaPhone.isNotEmpty) 'phone': metaPhone,
          },
        );
        final data = res.data;
        if (data is! Map || data['ok'] != true) {
          final serverError = (data is Map && data['error'] is String)
              ? data['error'] as String
              : null;
          throw Exception(
              serverError ?? 'Could not set up your organization. Please try again.');
        }
        // caller_role is the one field allowed to gate a vendor session
        // out of this recovery path too — same rule signup_page_widget.dart
        // uses, never combined with any other flag.
        if (data['caller_role'] != 'owner') {
          throw Exception('This account is not linked to any organization.');
        }

        members = await OrgMembersTable().queryRows(
          queryFn: (q) => q.eq('user_id', user.id),
        );
        orgIds = members.map((m) => m.orgId).whereType<String>().toList();
        if (orgIds.isEmpty) {
          // create-org just reported ok:true — this would mean the
          // immediately-following read raced or failed independently.
          // Never trust a round-trip blindly; fail loudly instead of
          // silently re-entering the same dead end.
          throw Exception('Could not set up your organization. Please try again.');
        }
      }

      final orgRows = await OrganizationsTable().queryRows(
        queryFn: (q) => q.inFilter('id', orgIds),
      );
      final orgNameById = {for (final o in orgRows) o.id!: o.name};
      final roleByOrgId = {
        for (final m in members)
          if (m.orgId != null) m.orgId!: m.role,
      };
      final availableOrgs = orgIds
          .map((id) => OrgMembershipInfo(
                orgId: id,
                orgName: orgNameById[id] ?? '(unnamed org)',
                role: roleByOrgId[id],
              ))
          .toList();

      String orgId = orgIds.first;
      if (availableOrgs.length > 1) {
        if (!mounted) return;
        // Stash the list before the picker needs it (showOrgSwitcherSheet
        // reads AppSession.instance.availableOrgs / currentOrgId — neither
        // is set yet on first login, so pass currentOrgId irrelevant here,
        // the sheet just won't show a checkmark, which is correct pre-login).
        AppSession.instance.availableOrgs = availableOrgs;
        final chosen = await showOrgSwitcherSheet(context);
        if (chosen != null) orgId = chosen;
      }

      final sessionData = await loadOrgSessionData(orgId);
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
        availableOrgs: availableOrgs,
      );

      // Remember this vendor session so a later staff PIN unlock can be
      // Locked back to it without re-entering email/password (Option A).
      await StaffAuth.saveVendorRefreshToken();

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

  Future<void> _handleStaffLogin() async {
    final input = _model.namePhoneFieldTextController!.text.trim();
    final pin = _model.pinFieldTextController!.text.trim();

    if (input.isEmpty || pin.isEmpty) {
      safeSetState(
          () => _model.errorMessage = 'Enter your name/phone and PIN.');
      return;
    }

    // Device-unlock model: staff PIN login rides on top of the vendor's
    // Supabase Auth session. Without it, RLS (org_isolation on `staff`)
    // correctly returns zero rows — so fail with a clear setup message
    // instead of a misleading "invalid PIN".
    final authUser = SupaFlow.client.auth.currentUser;
    if (authUser == null) {
      safeSetState(() => _model.errorMessage =
          'This device is not set up for staff login yet. '
          'Ask the owner to log in once with the vendor account first.');
      return;
    }

    safeSetState(() {
      _model.isLoading = true;
      _model.errorMessage = null;
    });

    try {
      // Authenticated + RLS-scoped: only this org's staff are visible.
      // Phone matches exactly; name matches case-insensitively so
      // "rajesh kumar" finds "Rajesh Kumar".
      var rows = await StaffTable().queryRows(
        queryFn: (q) => q.eq('phone', input),
      );
      if (rows.isEmpty) {
        rows = await StaffTable().queryRows(
          queryFn: (q) => q.ilike('name', input),
        );
      }
      // NOTE: no PIN comparison here anymore — the PIN never touches the
      // client. We only narrow down WHICH staff row the person means; the
      // PIN is verified server-side (bcrypt) by the staff-login function.
      final candidates = rows.where((r) => (r.active ?? true)).toList();
      if (candidates.isEmpty) {
        throw Exception('Invalid name/phone or PIN.');
      }

      // Save the vendor's refresh token BEFORE swapping sessions, so the
      // sidebar Lock button can silently restore the vendor later.
      await StaffAuth.saveVendorRefreshToken();

      // Ask the Edge Function to verify the PIN and mint a real session.
      // If two staff share a name, try each candidate; the wrong ones
      // simply come back 401 and we move on.
      Map<String, dynamic>? result;
      for (final s in candidates) {
        if (s.id == null) continue;
        try {
          final res = await SupaFlow.client.functions.invoke(
            'staff-login',
            body: {'staff_id': s.id, 'pin': pin},
          );
          final data = res.data;
          if (data is Map && data['access_token'] != null) {
            result = Map<String, dynamic>.from(data);
            break;
          }
        } on FunctionException catch (e) {
          // Rate limiting (20260725_staff_pin_rate_limit.sql): the Edge
          // Function returns 429 with a specific "try again after HH:MM"
          // message when this staff member is locked out. That message
          // must reach the user directly — the old blanket catch here
          // treated every error (including this one) as "wrong PIN, try
          // the next same-name candidate," which silently discarded it
          // and fell through to the generic "Invalid name/phone or PIN."
          if (e.status == 429) {
            final msg = (e.details is Map ? e.details['error'] : null)
                    as String? ??
                'Too many failed attempts. Try again later.';
            throw Exception(msg);
          }
          // 401 Invalid PIN (or other transient error) for this
          // candidate — try the next one.
          continue;
        } catch (_) {
          continue;
        }
      }
      if (result == null) {
        throw Exception('Invalid name/phone or PIN.');
      }

      final staffInfo = Map<String, dynamic>.from(result['staff'] as Map);
      final staffRefreshToken = result['refresh_token'] as String?;
      if (staffRefreshToken == null || staffRefreshToken.isEmpty) {
        throw Exception('Could not start staff session. Try again.');
      }

      // Swap this device to the staff member's OWN session. From here on
      // every query runs with the staff's real auth.uid(), so RLS scopes
      // them to the org via their org_members row automatically.
      final swap =
          await SupaFlow.client.auth.setSession(staffRefreshToken);
      if (swap.session == null) {
        throw Exception('Could not start staff session. Try again.');
      }

      AppSession.instance.setStaff(
        staffId: staffInfo['id'] as String,
        staffName: (staffInfo['name'] as String?) ?? '',
        role: staffInfo['role'] as String?,
      );

      // Cache this staff member's permission matrix for the sidebar
      // (runs under the freshly-swapped staff session).
      await StaffPermissions.loadForStaff(staffInfo['id'] as String);

      // Org context normally comes from the vendor session restore in
      // main.dart; fill it from the function's response only if it is
      // still empty. (This lookup now runs under the STAFF session — it
      // works because the Edge Function inserted the staff member's
      // org_members row before returning.)
      final orgId = staffInfo['org_id'] as String?;
      if (AppSession.instance.currentOrgId == null && orgId != null) {
        try {
          final orgs = await OrganizationsTable().queryRows(
            queryFn: (q) => q.eq('id', orgId).limit(1),
          );
          final org = orgs.isNotEmpty ? orgs.first : null;

          Map<String, dynamic> limits = {};
          Map<String, dynamic> features = {};
          String? planName;
          try {
            final planId = org?.planId;
            final plans = planId != null
                ? await SubscriptionPlansTable()
                    .queryRows(queryFn: (q) => q.eq('id', planId).limit(1))
                : await SubscriptionPlansTable().queryRows(
                    queryFn: (q) => q.eq('is_default_trial', true).limit(1),
                  );
            if (plans.isNotEmpty) {
              final plan = plans.first;
              limits = (plan.limits is Map)
                  ? Map<String, dynamic>.from(plan.limits as Map)
                  : {};
              features = (plan.features is Map)
                  ? Map<String, dynamic>.from(plan.features as Map)
                  : {};
              planName = plan.name;
            }
          } catch (_) {
            // Plan lookup is best-effort — don't block login on it.
          }

          AppSession.instance.setOrgOnly(
            orgId: orgId,
            orgName: org?.name,
            orgSlug: org?.slug,
            logoUrl: org?.logoUrl,
            limits: limits,
            features: features,
            planName: planName,
            trialEndsAt: org?.trialEndsAt,
          );
        } catch (_) {
          AppSession.instance.setOrgOnly(orgId: orgId);
        }
      }

      if (mounted) context.go(HomePageWidget.routePath);
    } catch (e) {
      safeSetState(() {
        _model.errorMessage = _friendlyAuthError(e);
        _model.isLoading = false;
      });
    }
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
      await SupaFlow.client.auth.resetPasswordForEmail(email);
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

                      // Vendor / Staff tab switcher
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2035),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            _tabButton(label: 'Vendor Login', index: 0),
                            _tabButton(label: 'Staff Login', index: 1),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2035),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.all(20),
                        child: _model.activeTab == 0
                            ? _buildVendorForm()
                            : _buildStaffForm(),
                      ),

                      const SizedBox(height: 24),
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

  Widget _tabButton({required String label, required int index}) {
    final selected = _model.activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => safeSetState(() {
          _model.activeTab = index;
          _model.errorMessage = null;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? kBrandGold : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.interTight(
              color: selected ? Colors.white : Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
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
              () => _model.vendorPasswordVisible =
                  !_model.vendorPasswordVisible,
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

  Widget _buildStaffForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_deviceChecked) ...[
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: _deviceOrgName != null
                  ? const Color(0xFF15321B)
                  : const Color(0xFF33270F),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  _deviceOrgName != null
                      ? Icons.verified_user
                      : Icons.info_outline,
                  size: 16,
                  color: _deviceOrgName != null
                      ? const Color(0xFF66BB6A)
                      : const Color(0xFFFFB74D),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _deviceOrgName != null
                        ? 'Device ready — $_deviceOrgName. Enter your PIN.'
                        : 'Device not set up. Owner must log in once first.',
                    style: GoogleFonts.inter(
                      color: _deviceOrgName != null
                          ? const Color(0xFF9CDFA3)
                          : const Color(0xFFFFCC80),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        _textField(
          controller: _model.namePhoneFieldTextController!,
          focusNode: _model.namePhoneFieldFocusNode!,
          label: 'Name or Phone',
          hint: 'Enter your name or phone',
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 14),
        _textField(
          controller: _model.pinFieldTextController!,
          focusNode: _model.pinFieldFocusNode!,
          label: 'PIN',
          hint: '4-digit PIN',
          icon: Icons.pin_outlined,
          keyboardType: TextInputType.number,
          obscureText: !_model.pinFieldVisibility,
          suffixIcon: IconButton(
            icon: Icon(
              _model.pinFieldVisibility
                  ? Icons.visibility_off
                  : Icons.visibility,
              color: Colors.white38,
              size: 20,
            ),
            onPressed: () => safeSetState(
              () => _model.pinFieldVisibility = !_model.pinFieldVisibility,
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
          onPressed: _model.isLoading ? null : _handleStaffLogin,
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
