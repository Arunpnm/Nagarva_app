import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '/backend/pending_auth_message.dart';
import '/backend/pending_password_reset.dart';
import '/backend/supabase/supabase.dart';
import '/backend/vendor_org_resolver.dart';
import '/index.dart';

/// Handles the Supabase auth deep link (17 Aug 2026):
///
///   nagarva://auth-callback#access_token=...&refresh_token=...&type=...
///
/// forwarded here by the link.nagarva.in landing page for every auth
/// email type it branches on: signup, recovery, invite, magiclink,
/// email_change — that static site has no Supabase client of its own
/// (see the 16 Aug 2026 redirect-issue report); its only job is to bounce
/// this scheme/host at whatever device opened the original email,
/// matching the `nagarva`/`auth-callback` intent-filter in
/// AndroidManifest.xml.
///
/// `type=recovery` is the one value handled differently — a password
/// reset must not silently log the user in with their OLD password still
/// live. Every other value (signup, invite, magiclink) and any
/// unknown/missing type with a valid token are signup-equivalent:
/// establish the session and go straight to the dashboard, same as
/// today. See [_AuthLinkResult] and [_process].
///
/// Registers both entry points the `app_links` package exposes:
///   - `getInitialLink()`: the app was launched BY this link (cold start).
///     Call [handleInitialLink] once, in main(), before runApp() — see
///     that method's own doc comment for why no explicit navigation
///     happens there (recovery routes via PendingPasswordReset instead).
///   - `uriLinkStream`: the app was already running and Android delivered
///     the intent to the existing instance (warm resume — this is what
///     the manifest's `launchMode="singleTop"` is for, so this doesn't
///     spawn a second instance). Call [startListening] once, after
///     runApp(), with the live `GoRouter`.
class AuthDeepLinkHandler {
  AuthDeepLinkHandler._();

  static final _appLinks = AppLinks();
  static StreamSubscription<Uri>? _sub;

  static const _kGenericFailureMessage =
      'Could not complete sign-in. Please log in with your email and password.';

  /// Cold start. On [_AuthLinkResult.dashboard] this populates AppSession
  /// the same way a normal login does — no explicit navigation here,
  /// deliberately: GoRouter's `/` route (`_initialize` in nav.dart) is
  /// public regardless of auth state, so it always renders
  /// LoginPageWidget for an unbound device (the expected case for a
  /// brand-new signup) BEFORE any redirect logic runs. LoginPageWidget's
  /// own `initState` already self-redirects to Home the moment it sees
  /// `AppSession.currentOrgId` non-null (the same mechanism that makes a
  /// plain browser-reload session restore work) — this reuses that,
  /// rather than teaching GoRouter a second way to decide its initial
  /// location. On [_AuthLinkResult.setNewPassword], `_process` itself
  /// already set `PendingPasswordReset.active` as a side effect —
  /// `_initialize`'s own builder checks that flag ahead of the
  /// bound/unbound branch, so nothing further is needed here either.
  ///
  /// On [_AuthLinkResult.failure], stashes a [PendingAuthMessage] and
  /// does nothing further. AppSession stays unauthenticated, so that same
  /// default landing page picks the message up and shows it in its own
  /// error banner. Never throws — any failure here must not block
  /// `runApp()` or leave the user stuck on the splash screen.
  static Future<void> handleInitialLink() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri == null) return;
      await _process(uri);
    } catch (e) {
      debugPrint('Auth deep link (cold start) failed: $e');
      PendingAuthMessage.set(_kGenericFailureMessage);
    }
  }

  /// Warm resume. Unlike cold start there is no natural "app boot" to
  /// lean on for routing, so this navigates explicitly via the passed
  /// [router] based on the outcome: the dashboard, the set-new-password
  /// screen, or `/login` (with the error banner pre-filled via
  /// [PendingAuthMessage]) on failure or any throw. Safe to call more
  /// than once — only the first call attaches the listener.
  static void startListening(GoRouter router) {
    _sub ??= _appLinks.uriLinkStream.listen((uri) async {
      try {
        final result = await _process(uri);
        switch (result) {
          case _AuthLinkResult.dashboard:
            router.go(HomePageWidget.routePath);
          case _AuthLinkResult.setNewPassword:
            router.go(SetNewPasswordPageWidget.routePath);
          case _AuthLinkResult.failure:
            router.go(LoginPageWidget.routePath);
        }
      } catch (e) {
        debugPrint('Auth deep link (warm resume) failed: $e');
        PendingAuthMessage.set(_kGenericFailureMessage);
        router.go(LoginPageWidget.routePath);
      }
    }, onError: (Object e) {
      debugPrint('Auth deep link stream error: $e');
    });
  }

  /// Parses the fragment and does the actual work. Every non-dashboard
  /// outcome has already set whatever state its caller needs
  /// (PendingAuthMessage for failure, PendingPasswordReset for
  /// setNewPassword) — callers just route, never compose their own state.
  static Future<_AuthLinkResult> _process(Uri uri) async {
    if (uri.scheme != 'nagarva' || uri.host != 'auth-callback') {
      // Not ours — some other deep link. Ignore silently.
      return _AuthLinkResult.failure;
    }

    // access_token/refresh_token/type arrive in the URI FRAGMENT
    // (implicit flow, matches supabase.dart's authFlowType.implicit), not
    // the query string — Uri.splitQueryString on uri.fragment parses the
    // same key=value&key=value shape and already percent/plus-decodes,
    // same as it would for a real query string.
    final params = Uri.splitQueryString(uri.fragment);

    final error = params['error_description'] ?? params['error'];
    if (error != null && error.isNotEmpty) {
      PendingAuthMessage.set(error);
      return _AuthLinkResult.failure;
    }

    final refreshToken = params['refresh_token'];
    if (refreshToken == null || refreshToken.isEmpty) {
      // No token, no error — malformed/unexpected link. Fail quietly
      // rather than guess at a message that might be wrong.
      PendingAuthMessage.set(
          'This confirmation link is missing required information. '
          'Please log in with your email and password.');
      return _AuthLinkResult.failure;
    }

    // Only `recovery` is special-cased — invite/magiclink/signup, and any
    // unknown or missing type alongside a valid token, are all
    // signup-equivalent (establish the session, go to the dashboard).
    final isRecovery = params['type'] == 'recovery';

    try {
      final res = await SupaFlow.client.auth.setSession(refreshToken);
      final user = res.user;
      if (user == null) {
        throw Exception('Could not restore your session.');
      }
      // NG-BRIEF-vendor-auth-flow.md §2a's create-org recovery, shared
      // with login_page_widget.dart's _handleVendorLogin — this is the
      // step that actually finishes signup: confirming alone never ran
      // create-org (that only happens in the SAME browser/app instance
      // that originally called signUp(), which "Confirm email" being on
      // means this one never was). A recovery link is an EXISTING user
      // resetting their password, not a fresh signup, but the org lookup
      // here is a plain read for them (org_members already has their
      // row) — same call, same result either way. A fresh signup has
      // exactly one org by construction — no multi-org picker needed here
      // the way the interactive login flow has one for a consultant/
      // owner account.
      final availableOrgs = await resolveVendorOrgs(user);
      final orgId = availableOrgs.first.orgId;
      await establishVendorSession(user, orgId, availableOrgs);

      if (isRecovery) {
        // The one thing that must NOT happen for a password reset: the
        // session above is already fully live and usable, so without
        // this gate the user would land straight on the dashboard with
        // their OLD password still the only one that works — this flag
        // is what routes them to SetNewPasswordPageWidget instead.
        PendingPasswordReset.active = true;
        return _AuthLinkResult.setNewPassword;
      }
      return _AuthLinkResult.dashboard;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      PendingAuthMessage.set(
        msg.contains('expired') || msg.contains('invalid')
            ? (isRecovery
                ? 'This password reset link has expired or was already '
                    'used. Please request a new one from the login screen.'
                : 'This confirmation link has expired or was already used. '
                    'Please log in — you can request a new confirmation '
                    'email from the sign-up screen if you still need one.')
            : _kGenericFailureMessage,
      );
      return _AuthLinkResult.failure;
    }
  }
}

enum _AuthLinkResult { dashboard, setNewPassword, failure }
