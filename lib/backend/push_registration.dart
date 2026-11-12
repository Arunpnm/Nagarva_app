import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/config/app_config.dart';

/// Phone push notifications (12 Nov 2026, Arun: alerts with sound even
/// when the app is closed).
///
/// The phone's push address (FCM token) is registered against whoever is
/// logged in, through `register_push_token()`
/// (supabase/20261112_push_notifications.sql). The server side is the
/// `push-send` Edge Function, fired for every new bell notification.
///
/// ANDROID ONLY. The web build never touches Firebase: there is no web
/// config, and the bell's own sound already covers an open browser tab.
///
/// Everything here is best-effort. A phone that refuses permission, has
/// no Google Play services, or is offline simply gets no push; nothing in
/// the app waits on it or shows an error for it.
class PushRegistration {
  static bool _ready = false;
  static String? _token;
  static String? _registeredFor; // "<org>|<user>"

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Called once from main(). Cheap and safe to call when unsupported.
  static Future<void> init() async {
    if (!_supported || _ready) return;
    try {
      await Firebase.initializeApp();
      _ready = true;
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        _token = t;
        _registeredFor = null;
        sync();
      });
      AppSession.instance.addListener(sync);
    } catch (e) {
      debugPrint('Push: Firebase not available ($e)');
    }
  }

  /// Registers this phone for the current login, once per org+person.
  static Future<void> sync() async {
    if (!_ready) return;
    final orgId = AppSession.instance.currentOrgId;
    final uid = SupaFlow.client.auth.currentUser?.id;
    if (orgId == null || uid == null) return;
    final key = '$orgId|$uid';
    if (_registeredFor == key) return;
    _registeredFor = key; // claim first: the listener fires often
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      _token ??= await FirebaseMessaging.instance.getToken();
      final token = _token;
      if (token == null) {
        _registeredFor = null;
        return;
      }
      await SupaFlow.client.rpc('register_push_token', params: {
        'p_org_id': orgId,
        'p_token': token,
        'p_platform': 'android',
        'p_app_version': kAppVersion,
      });
    } catch (e) {
      _registeredFor = null; // try again on the next session change
      debugPrint('Push: register failed ($e)');
    }
  }

  /// Logout: this phone stops receiving this person's alerts. Must run
  /// BEFORE sign-out, while the login still exists.
  static Future<void> unregister() async {
    if (!_ready) return;
    final token = _token;
    _registeredFor = null;
    if (token == null) return;
    try {
      await SupaFlow.client
          .rpc('unregister_push_token', params: {'p_token': token});
    } catch (_) {}
  }
}
