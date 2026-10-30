import 'package:flutter/material.dart';

import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/components/ng_widgets.dart';
import '/components/theme_quick_button.dart';
import '/config/app_config.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';
import 'super_admin_page_widget.dart';

/// Nagarva Admin sign-in (Claude Design handoff, `Nagarva Admin.dc.html`
/// LOGIN section; screens/admin/00-login.png): work email and password
/// through Supabase Auth, for the Nagarva team only.
///
/// After the password is accepted the DATABASE decides who is an admin:
/// `is_platform_admin()` (platform_admins, the same table RLS and the
/// Super Admin page check). Anyone else is signed straight back out, so
/// a vendor's own email login cannot be used to get in here.
///
/// Left out of the design on purpose: the "Demo · sign in as" chips (a
/// prototype shortcut; asked to remove), and the footer promising a
/// 2-step code on new devices, because no second factor exists yet.
class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  static const routeName = 'AdminLoginPage';
  static const routePath = '/admin-login';

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@') || password.isEmpty) {
      setState(() => _error = 'Enter your work email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = SupaFlow.client.auth;
    try {
      final res =
          await auth.signInWithPassword(email: email, password: password);
      final user = res.user;
      final isAdmin = user != null &&
          (await SupaFlow.client.rpc('is_platform_admin')) == true;
      if (!isAdmin) {
        await auth.signOut();
        AppSession.instance.isPlatformAdmin = false;
        setState(() => _error =
            'This account is not on the Nagarva team. Use the vendor login instead.');
        return;
      }
      AppSession.instance
        ..authUserId = user.id
        ..isPlatformAdmin = true;
      if (mounted) context.go(SuperAdminPageWidget.routePath);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not sign in. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter your work email first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupaFlow.client.auth
          .resetPasswordForEmail(email, redirectTo: kAuthRedirectUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Password reset link sent to $email.')));
      }
    } catch (_) {
      setState(() => _error = 'Could not send the reset link.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.accBtn,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('N',
                            style: NgFonts.geist(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: NgPalette.onAcc)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Nagarva Admin',
                                style: NgFonts.geist(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: c.text)),
                            Text('For the Nagarva team only',
                                style: NgFonts.geist(
                                    fontSize: 12.5, color: c.mute)),
                          ],
                        ),
                      ),
                      ThemeQuickButton(iconColor: c.soft),
                    ]),
                    const SizedBox(height: 20),
                    NgInput(
                      controller: _email,
                      hint: 'Work email',
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 10),
                    NgInput(
                      controller: _password,
                      hint: 'Password',
                      obscure: true,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _forgot,
                        child: Text('Forgot password?',
                            style: NgFonts.geist(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: c.acc)),
                      ),
                    ),
                    if (_error != null) ...[
                      Text(_error!,
                          style: NgFonts.geist(fontSize: 13, color: c.red)),
                      const SizedBox(height: 10),
                    ],
                    NgPrimaryButton(
                      label: _busy ? 'Signing in…' : 'Sign in',
                      onPressed: _busy ? null : _signIn,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
