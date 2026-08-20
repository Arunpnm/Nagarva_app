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
/// **Verifying this file is not the same as verifying crash reporting.**
/// Every test here calls `Sentry.captureException` directly, which never
/// touches the handler chain a real crash travels down. On 20 Aug 2026
/// that chain was severed — `main.dart`'s `_installErrorHandlers()` runs
/// inside `initCrashReporting`'s appRunner and overwrote both
/// `FlutterError.onError` and `PlatformDispatcher.onError` — so Sentry
/// received nothing from real crashes while all 18 tests passed. The
/// acceptance test is an UNHANDLED error in a release build on a device,
/// arriving in the dashboard. See CLAUDE.md's conventions.
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
/// key so a rename of the value format cannot slip past. Longest
/// alternatives first, so `access_token` is never matched as a bare
/// `token`.
///
/// The boundary is a NON-WORD LOOKBEHIND, `(?<![A-Za-z0-9_])`, not
/// `[?&]`. These appear in three shapes and all three are real:
///   * inside a URL            — `...?token=abc`
///   * as a bare query string  — `token=abc` with no leading `?`, which
///     is exactly how Sentry's `SentryRequest.queryString` stores it
///   * loose in free text      — `Exception: rejected token=abc`
///
/// The pattern was widened twice on 20 Aug 2026 for the second and third
/// of those, each time because a test caught a live credential going
/// out, never because anyone spotted it by reading. That is the whole
/// argument for the tests in crash_redaction_test.dart.
final _tokenParam = RegExp(
  r'((?<![A-Za-z0-9_])(?:access_token|refresh_token|api_key|apikey|signature|token|jwt|sig|key)=)[^&\s]*',
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
  // 1. Request: rebuild it from scratch carrying ONLY url/method/query.
  //
  // This CANNOT use copyWith(data: null, ...). copyWith treats a null
  // argument as "leave unchanged", so that form silently kept the body,
  // the cookies and the Authorization header while reading exactly like
  // it dropped them. Caught 20 Aug 2026 by the scrubEvent tests below —
  // the string-level tests passed the whole time, because the defect was
  // never in the regexes.
  //
  // Constructing a fresh SentryRequest makes omission the default: any
  // field not named here cannot be transmitted, including fields Sentry
  // adds in a future version. A deny-list would have to be updated for
  // each one; this does not.
  final req = event.request;
  if (req != null) {
    event.request = SentryRequest(
      url: _redactNullable(req.url),
      queryString: _redactNullable(req.queryString),
      method: req.method,
    );
  }

  // 2. Exception values and messages.
  if (event.message != null) {
    event.message = SentryMessage(
      redactSensitive(event.message!.formatted),
      template: _redactNullable(event.message!.template),
    );
  }

  // 3. EXCEPTIONS — the payload of an actual crash.
  //
  // This is the one that matters most and was missing until 20 Aug 2026.
  // A crash report is an exception, not a message: `event.message` is
  // null for virtually every real crash, and the text a developer needs
  // lives in exceptions[].value. Scrubbing message/request/breadcrumbs
  // while leaving exceptions untouched meant the most common case —
  // "Exception: no customer found for +919845011001" — went out intact.
  //
  // Found by the live test firing a real exception through the shipped
  // configuration. Every string-level test passed throughout; the
  // regexes were never the problem, the coverage was. The doc comment at
  // the top of this file claimed exception values were scrubbed for days
  // before the code actually did it.
  final exceptions = event.exceptions;
  if (exceptions != null && exceptions.isNotEmpty) {
    event.exceptions = exceptions
        .map((e) => e.copyWith(value: _redactNullable(e.value)))
        .toList();
  }

  // 4. Anything a caller attached by hand.
  final extra = event.extra;
  if (extra != null && extra.isNotEmpty) {
    event.extra = extra.map(
      (k, v) => MapEntry(k, v is String ? redactSensitive(v) : v),
    );
  }

  // 5. Breadcrumbs — where URLs and navigation paths actually live, and
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
    (options) => configureSentryOptions(options, dsn: kSentryDsn),
    appRunner: appRunner,
  );
}

/// The one place Sentry's safety posture is defined.
///
/// Extracted so a test can initialise Sentry with EXACTLY this
/// configuration and fire a real event through it. A test that re-declares
/// the options would only prove that a copy of the config redacts —
/// which is worth nothing, because the copy is not what ships.
void configureSentryOptions(SentryFlutterOptions options,
    {required String dsn, String? environment}) {
  {
      options.dsn = dsn;
      options.environment = environment ?? kSentryEnvironment;
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
  }
}

/// Kept separate so the version string has one source. Mirrors
/// kAppVersion's define; imported lazily to avoid a config dependency
/// cycle in this low-level file.
const String _releaseTag = String.fromEnvironment(
  'NAGARVA_APP_VERSION',
  defaultValue: '1.0.0+1',
);
