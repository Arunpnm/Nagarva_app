import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '/backend/pending_auth_message.dart';
import '/backend/supabase/supabase.dart';
import '/backend/vendor_org_resolver.dart';
import '/index.dart';

/// Handles the email-confirmation deep link (17 Aug 2026):
///
///   nagarva://auth-callback#access_token=...&refresh_token=...&type=signup
///
/// forwarded here by the link.nagarva.in confirmation landing page — that
/// static site has no Supabase client of its own (see the 16 Aug 2026
/// redirect-issue report); its only job is to bounce this scheme/host at
/// whatever device opened the original confirmation email, matching the
/// `nagarva`/`auth-callback` intent-filter added to AndroidManifest.xml.
///
/// Registers both entry points the `app_links` package exposes:
///   - `getInitialLink()`: the app was launched BY this link (cold start).
///     Call [handleInitialLink] once, in main(), before runApp() — see
///     that method's own doc comment for why no explicit navigation
///     happens there.
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

  /// Cold start. On success this populates AppSession the same way a
  /// normal login does — no explicit navigation here, deliberately:
  /// GoRouter's `/` route (`_initialize` in nav.dart) is public
  /// regardless of auth state, so it always renders LoginPageWidget for
  /// an unbound device (the expected case for a brand-new signup) BEFORE
  /// any redirect logic runs. LoginPageWidget's own `initState` already
  /// self-redirects to Home the moment it sees `AppSession.currentOrgId`
  /// non-null (the same mechanism that makes a plain browser-reload
  /// session restore work) — this reuses that, rather than teaching
  /// GoRouter a second way to decide its initial location.
  ///
  /// On failure, stashes a [PendingAuthMessage] and does nothing further.
  /// AppSession stays unauthenticated, so that same default landing page
  /// picks the message up and shows it in its own error banner. Never
  /// throws — any failure here must not block `runApp()` or leave the
  /// user stuck on the splash screen.
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
  /// [router]: the dashboard on success, `/login` (with the error banner
  /// pre-filled via [PendingAuthMessage]) on failure or any throw. Safe
  /// to call more than once — only the first call attaches the listener.
  static void startListening(GoRouter router) {
    _sub ??= _appLinks.uriLinkStream.listen((uri) async {
      try {
        final success = await _process(uri);
        router
            .go(success ? HomePageWidget.routePath : LoginPageWidget.routePath);
      } catch (e) {
        debugPrint('Auth deep link (warm resume) failed: $e');
        PendingAuthMessage.set(_kGenericFailureMessage);
        router.go(LoginPageWidget.routePath);
      }
    }, onError: (Object e) {
      debugPrint('Auth deep link stream error: $e');
    });
  }

  /// Parses the fragment and does the actual work. Returns true only on
  /// a fully-established vendor session — every false path has already
  /// set a [PendingAuthMessage], so callers never need to compose their
  /// own message, just route to /login.
  static Future<bool> _process(Uri uri) async {
    if (uri.scheme != 'nagarva' || uri.host != 'auth-callback') {
      return false; // Not ours — some other deep link. Ignore silently.
    }

    // access_token/refresh_token/type=signup arrive in the URI FRAGMENT
    // (implicit flow, matches supabase.dart's authFlowType.implicit), not
    // the query string — Uri.splitQueryString on uri.fragment parses the
    // same key=value&key=value shape and already percent/plus-decodes,
    // same as it would for a real query string.
    final params = Uri.splitQueryString(uri.fragment);

    final error = params['error_description'] ?? params['error'];
    if (error != null && error.isNotEmpty) {
      PendingAuthMessage.set(error);
      return false;
    }

    final refreshToken = params['refresh_token'];
    if (refreshToken == null || refreshToken.isEmpty) {
      // No token, no error — malformed/unexpected link. Fail quietly
      // rather than guess at a message that might be wrong.
      PendingAuthMessage.set(
          'This confirmation link is missing required information. '
          'Please log in with your email and password.');
      return false;
    }

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
      // means this one never was). A fresh signup has exactly one org by
      // construction — no multi-org picker needed here the way the
      // interactive login flow has one for a consultant/owner account.
      final availableOrgs = await resolveVendorOrgs(user);
      final orgId = availableOrgs.first.orgId;
      await establishVendorSession(user, orgId, availableOrgs);
      return true;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      PendingAuthMessage.set(
        msg.contains('expired') || msg.contains('invalid')
            ? 'This confirmation link has expired or was already used. '
                'Please log in — you can request a new confirmation email '
                'from the sign-up screen if you still need one.'
            : _kGenericFailureMessage,
      );
      return false;
    }
  }
}
