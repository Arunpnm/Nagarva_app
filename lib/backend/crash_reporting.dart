/// Crash reporting — Sentry, added 19 Aug 2026 before the first outside
/// tester build.
///
/// **Everything here exists to stop customer data leaving the device.**
/// This app holds a vendor's customers: names, phone numbers, addresses,
/// GSTINs, and — the sharpest one — signed-URL tokens. A signature token
/// in a third-party service is not PII, it is a LIVE CREDENTIAL: anyone
/// holding it can open the signing page and sign as that customer. So
/// scrubbing here is not hygiene, it is access control, and it must fail
/// closed.
///
/// Three layers, deliberately overlapping:
///   1. `sendDefaultPii: false` — no IPs, no usernames, no device
///      identifiers attached automatically.
///   2. Request bodies stripped entirely. Nothing we send to Postgres or
///      an Edge Function should ever be reconstructable from a crash
///      report, and an allow-list of "safe" fields would rot the moment
///      somebody adds a column.
///   3. Regex redaction over every string that still goes out —
///      messages, exception values, breadcrumb text, and URLs. This is
///      the backstop for the two above missing something.
library;

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// DSN. Empty by default: a build without the define reports nothing at
/// all rather than failing, so a forgotten flag is silence, not a crash.
const String kSentryDsn = String.fromEnvironment('NAGARVA_SENTRY_DSN');

/// `tester` for the shared build, `dev` for Arun's own, set per build via
/// --dart-define so one APK's crashes never mix with another's.
const String kSentryEnvironment = String.fromEnvironment(
  'NAGARVA_SENTRY_ENV',
  defaultValue: 'dev',
);

bool get crashReportingEnabled => kSentryDsn.isNotEmpty;

// ---------------------------------------------------------------------------
// Redaction
// ---------------------------------------------------------------------------

/// Query parameters whose VALUE is a credential, not data. Matched on the
/// key so a rename of the value format cannot slip past.
final _tokenParam = RegExp(
  r'([?&](?:token|access_token|refresh_token|apikey|api_key|key|signature|sig|jwt)=)[^&\s]*',
  caseSensitive: false,
);

/// Bare token-shaped strings that appear outside a URL — a token pasted
/// into an error message, or a JWT in an exception value.
final _bareJwt = RegExp(r'\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}[.A-Za-z0-9_-]*');

/// Indian mobile numbers, with or without a +91 prefix and common
/// separators. Deliberately broad: a false positive costs a redacted
/// number in a stack trace, a false negative costs a customer's phone
/// number sitting in a third-party service.
///
/// Digit-run boundaries use lookaround, NOT \b. `\b` cannot match between
/// two digits, so `+919845011001` — the single most common way a number
/// gets pasted — sailed straight through the first version of this
/// pattern. Caught by crash_redaction_test.dart, which is why that test
/// exists. `(?<!\d)` / `(?!\d)` anchor to the ends of the digit run
/// instead, so the prefixed form matches while a longer id like
/// 1234567890123 still does not.
final _phone = RegExp(r'(?<!\d)(?:\+?91[\s-]?)?[6-9]\d{9}(?!\d)');

/// GSTIN: 2-digit state code, 5-letter PAN prefix, 4 digits, letter,
/// alphanumeric, Z, checksum.
final _gstin = RegExp(
  r'\b\d{2}[A-Z]{5}\d{4}[A-Z][A-Z0-9]Z[A-Z0-9]\b',
  caseSensitive: false,
);

/// Applies every redaction rule to one string.
///
/// Order matters: token parameters are stripped before the generic
/// patterns, so a token that happens to contain a digit run is never
/// half-redacted into something still usable.
String redactSensitive(String input) {
  if (input.isEmpty) return input;
  return input
      .replaceAllMapped(_tokenParam, (m) => '${m[1]}[redacted]')
      .replaceAll(_bareJwt, '[redacted-jwt]')
      .replaceAll(_gstin, '[redacted-gstin]')
      .replaceAll(_phone, '[redacted-phone]');
}

String? _redactNullable(String? s) => s == null ? null : redactSensitive(s);

/// Scrubs an event immediately before it leaves the device.
///
/// Returns the event, never null — dropping events wholesale would hide
/// real crashes. The goal is a report that is still diagnostic with the
/// customer data taken out of it, not no report.
SentryEvent? scrubEvent(SentryEvent event) {
  // 1. Request: drop the body and cookies outright, redact the URL.
  final req = event.request;
  if (req != null) {
    event.request = req.copyWith(
      data: null,
      cookies: null,
      headers: const {},
      url: _redactNullable(req.url),
      queryString: _redactNullable(req.queryString),
    );
  }

  // 2. Exception values and messages.
  if (event.message != null) {
    event.message = SentryMessage(
      redactSensitive(event.message!.formatted),
      template: _redactNullable(event.message!.template),
    );
  }

  // 3. Breadcrumbs — where URLs and navigation paths actually live, and
  //    therefore where a /sign?token=... would otherwise be captured.
  final crumbs = event.breadcrumbs;
  if (crumbs != null) {
    event.breadcrumbs = crumbs
        .map((c) => c.copyWith(
              message: _redactNullable(c.message),
              data: c.data == null
                  ? null
                  : c.data!.map((k, v) => MapEntry(
                        k,
                        v is String ? redactSensitive(v) : v,
                      )),
            ))
        .toList();
  }

  return event;
}

/// Initialises Sentry and runs [appRunner] inside it.
///
/// When no DSN is configured this just runs the app — the tester build
/// and a local debug build take the same code path, so nothing about
/// crash reporting can change app behaviour.
Future<void> initCrashReporting(Future<void> Function() appRunner) async {
  if (!crashReportingEnabled) {
    await appRunner();
    return;
  }
  await SentryFlutter.init(
    (options) {
      options.dsn = kSentryDsn;
      options.environment = kSentryEnvironment;
      options.release = 'nagarva@$_releaseTag';

      // No automatic PII: no IP address, no device identifiers, no
      // usernames attached to events.
      options.sendDefaultPii = false;

      // Sampling: full crash capture, no performance tracing. Tracing
      // would attach request URLs on a much wider surface than errors do,
      // which is more redaction surface for no benefit at this stage.
      options.tracesSampleRate = 0.0;

      // Screenshots and view hierarchy would photograph customer data on
      // screen at the moment of a crash. Never enable these.
      options.attachScreenshot = false;
      options.attachViewHierarchy = false;

      options.beforeSend = (event, hint) => scrubEvent(event);

      options.beforeBreadcrumb = (crumb, hint) {
        if (crumb == null) return null;
        return crumb.copyWith(
          message: _redactNullable(crumb.message),
          data: crumb.data?.map(
            (k, v) => MapEntry(k, v is String ? redactSensitive(v) : v),
          ),
        );
      };
    },
    appRunner: appRunner,
  );
}

/// Kept separate so the version string has one source. Mirrors
/// kAppVersion's define; imported lazily to avoid a config dependency
/// cycle in this low-level file.
const String _releaseTag = String.fromEnvironment(
  'NAGARVA_APP_VERSION',
  defaultValue: '1.0.0+1',
);
