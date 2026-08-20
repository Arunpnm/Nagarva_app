@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:arun_p_k_r_s/backend/crash_reporting.dart';

/// END-TO-END proof that what reaches Sentry is scrubbed.
///
/// The unit tests in crash_redaction_test.dart prove the helper and the
/// beforeSend hook in isolation. This one is different in the way that
/// matters: it initialises Sentry with **`configureSentryOptions` — the
/// exact function `initCrashReporting` uses in the shipped app** — and
/// fires a real exception carrying a phone number, a GSTIN and a live
/// signature token over the real network.
///
/// A test that re-declared the options would only prove that a copy of
/// the configuration redacts, which proves nothing about the build.
///
/// It also asserts on the payload the SDK is about to transmit, by
/// installing its own beforeSend AFTER the real one — so the assertion
/// sees precisely what leaves the process, not what we hoped would.
///
/// SKIPPED unless a DSN is supplied, so it never runs in ordinary CI:
///
///   flutter test test/sentry_live_redaction_test.dart \
///     --dart-define=NAGARVA_SENTRY_DSN=<dsn> \
///     --dart-define=NAGARVA_SENTRY_ENV=tester
void main() {
  const dsn = String.fromEnvironment('NAGARVA_SENTRY_DSN');
  const env = String.fromEnvironment('NAGARVA_SENTRY_ENV',
      defaultValue: 'test-harness');

  test('a real event transmitted to Sentry carries no customer data',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    SentryEvent? transmitted;

    await SentryFlutter.init((options) {
      // The shipped configuration, not a re-declaration of it.
      configureSentryOptions(options, dsn: dsn, environment: env);

      // Chain AFTER the real beforeSend so we observe the final payload.
      final realBeforeSend = options.beforeSend;
      options.beforeSend = (event, hint) async {
        final scrubbed = await realBeforeSend?.call(event, hint) ?? event;
        transmitted = scrubbed as SentryEvent?;
        return scrubbed;
      };
    });

    await Sentry.captureException(
      Exception(
        'REDACTION PROOF — customer +919845011001, GSTIN 33AABCU9603R1ZM, '
        'link https://link.nagarva.in/sign?token=LIVECREDENTIAL123',
      ),
    );
    await Sentry.close();

    expect(transmitted, isNotNull,
        reason: 'beforeSend never ran — the event was not transmitted');

    final payload = transmitted!.toJson().toString();
    for (final secret in [
      '9845011001',
      '33AABCU9603R1ZM',
      'LIVECREDENTIAL123',
    ]) {
      expect(payload, isNot(contains(secret)),
          reason: 'LEAKED to Sentry: $secret');
    }

    // Still diagnostic, and correctly tagged.
    expect(payload, contains('REDACTION PROOF'));
    expect(transmitted!.environment, env);
  }, skip: dsn.isEmpty ? 'no NAGARVA_SENTRY_DSN supplied' : false);
}
