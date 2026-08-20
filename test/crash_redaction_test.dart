import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:arun_p_k_r_s/backend/crash_reporting.dart';

/// Tests for the Sentry scrubbing layer.
///
/// These are not style checks. A signature token reaching Sentry is a
/// live credential for signing as somebody's customer, so each case below
/// is a specific thing that must never leave the device.
void main() {
  group('token redaction — credentials, not PII', () {
    test('strips the token from a signature link', () {
      final out = redactSensitive(
          'GET https://link.nagarva.in/sign?token=abc123DEF456ghi failed');
      expect(out, contains('token=[redacted]'));
      expect(out, isNot(contains('abc123DEF456ghi')));
      // The rest of the URL survives — a redacted report still has to be
      // diagnostic.
      expect(out, contains('link.nagarva.in/sign'));
    });

    test('strips a token that is not the first query parameter', () {
      final out =
          redactSensitive('https://x.in/survey?org=apc&token=SECRETVALUE&v=2');
      expect(out, isNot(contains('SECRETVALUE')));
      expect(out, contains('org=apc'));
      // Redaction must stop at the parameter boundary, not eat the rest.
      expect(out, contains('v=2'));
    });

    test('strips access_token, apikey and signature parameters', () {
      for (final key in ['access_token', 'apikey', 'api_key', 'signature', 'sig']) {
        final out = redactSensitive('https://x.in/a?$key=LEAKME');
        expect(out, isNot(contains('LEAKME')), reason: 'leaked via $key');
      }
    });

    test('is case-insensitive on the parameter name', () {
      expect(redactSensitive('https://x.in/a?Token=LEAKME'),
          isNot(contains('LEAKME')));
    });


    test('redacts a bare key=value with no leading ? or &', () {
      // SentryRequest.queryString holds the query without its leading
      // '?', so the token sits at position 0. The original pattern
      // required [?&] in front and missed exactly this.
      final out = redactSensitive('token=LIVECREDENTIAL123');
      expect(out, isNot(contains('LIVECREDENTIAL123')));
      expect(out, contains('[redacted]'));
    });
    test('redacts a bare JWT outside any URL', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N';
      final out = redactSensitive('auth failed for $jwt');
      expect(out, isNot(contains(jwt)));
      expect(out, contains('[redacted-jwt]'));
    });
  });

  group('customer PII', () {
    test('redacts a bare Indian mobile number', () {
      final out = redactSensitive('customer 9845011001 not found');
      expect(out, isNot(contains('9845011001')));
      expect(out, contains('[redacted-phone]'));
    });

    test('redacts +91 and spaced forms', () {
      expect(redactSensitive('call +91 9900100012'),
          isNot(contains('9900100012')));
      expect(redactSensitive('call +919900100012'),
          isNot(contains('9900100012')));
    });

    test('redacts a GSTIN', () {
      final out = redactSensitive('GSTIN 33AABCU9603R1ZM rejected');
      expect(out, isNot(contains('33AABCU9603R1ZM')));
      expect(out, contains('[redacted-gstin]'));
    });

    test('leaves ordinary numbers alone so reports stay useful', () {
      // Order ids, amounts, counts, timestamps must survive — redacting
      // everything numeric would make crash reports unreadable.
      final out = redactSensitive('order NGV-1012 amount 12000 at 2026-08-19');
      expect(out, contains('NGV-1012'));
      expect(out, contains('12000'));
      expect(out, contains('2026-08-19'));
    });

    test('does not redact a 10-digit number starting below 6', () {
      // Indian mobiles start 6-9. A 10-digit id starting with 1 is not a
      // phone number and should stay readable.
      expect(redactSensitive('ref 1234567890'), contains('1234567890'));
    });
  });

  group('combined', () {
    test('handles several secrets in one string', () {
      final out = redactSensitive(
          'POST /sign?token=T0KEN for 9845011001 GSTIN 33AABCU9603R1ZM');
      expect(out, isNot(contains('T0KEN')));
      expect(out, isNot(contains('9845011001')));
      expect(out, isNot(contains('33AABCU9603R1ZM')));
    });

    test('empty and clean strings pass through unchanged', () {
      expect(redactSensitive(''), '');
      expect(redactSensitive('NullPointerException in build()'),
          'NullPointerException in build()');
    });
  });

  // -------------------------------------------------------------------------
  // Event-level: what actually leaves the device via beforeSend.
  //
  // The tests above prove the string helper. These prove the hook that
  // Sentry actually calls, on a real SentryEvent — message, request URL
  // and breadcrumbs, which are the three places customer data and live
  // tokens really travel.
  // -------------------------------------------------------------------------
  group('scrubEvent — the transmitted payload', () {
    test('scrubs message, request and breadcrumbs together', () {
      final event = SentryEvent(
        message: SentryMessage(
          'Failed for customer +919845011001 GSTIN 33AABCU9603R1ZM',
        ),
        request: SentryRequest(
          url: 'https://link.nagarva.in/sign?token=LIVECREDENTIAL123',
          queryString: 'token=LIVECREDENTIAL123',
          // A request body is the worst case: it can carry the whole row.
          data: {'pin': '4242', 'phone': '9845011001'},
          cookies: 'session=abc',
          headers: const {'Authorization': 'Bearer secret'},
        ),
        breadcrumbs: [
          Breadcrumb(
            message: 'navigate to /survey?token=ANOTHERCREDENTIAL',
            data: {'phone': '+919900100012'},
          ),
        ],
      );

      final out = scrubEvent(event)!;
      final blob = [
        out.message?.formatted,
        out.request?.url,
        out.request?.queryString,
        out.request?.data?.toString(),
        out.request?.cookies,
        out.request?.headers.toString(),
        out.breadcrumbs?.map((b) => '${b.message} ${b.data}').join(' '),
      ].whereType<String>().join(' | ');

      // Nothing sensitive survives anywhere in the payload.
      for (final secret in [
        'LIVECREDENTIAL123',
        'ANOTHERCREDENTIAL',
        '9845011001',
        '9900100012',
        '33AABCU9603R1ZM',
        'Bearer secret',
        'session=abc',
        '4242',
      ]) {
        expect(blob, isNot(contains(secret)), reason: 'leaked: $secret');
      }

      // And the report is still diagnostic.
      expect(out.request?.url, contains('link.nagarva.in/sign'));
      expect(out.message?.formatted, contains('Failed for customer'));
    });


    test('scrubs exception values — the payload of a real crash', () {
      // event.message is null for virtually every real crash; the text
      // lives in exceptions[].value. This was unscrubbed until 20 Aug
      // 2026 and is the single most likely way customer data would have
      // reached Sentry.
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: '_Exception',
            value: 'no customer found for +919845011001 '
                'GSTIN 33AABCU9603R1ZM token=LEAKME123',
          ),
        ],
      );
      final out = scrubEvent(event)!;
      final v = out.exceptions!.single.value!;
      expect(v, isNot(contains('9845011001')));
      expect(v, isNot(contains('33AABCU9603R1ZM')));
      expect(v, isNot(contains('LEAKME123')));
      expect(v, contains('no customer found for'));
      // The type must survive — it is how you find the crash.
      expect(out.exceptions!.single.type, '_Exception');
    });

    test('scrubs hand-attached extra data', () {
      final event = SentryEvent(
        extra: {'note': 'called +919900100012', 'count': 3},
      );
      final out = scrubEvent(event)!;
      expect(out.extra!['note'], isNot(contains('9900100012')));
      expect(out.extra!['count'], 3);
    });
    test('request body, cookies and headers are dropped entirely', () {
      final event = SentryEvent(
        request: SentryRequest(
          url: 'https://x.in/a',
          data: {'anything': 'at all'},
          cookies: 'k=v',
          headers: const {'X-Thing': 'value'},
        ),
      );
      final out = scrubEvent(event)!;
      expect(out.request?.data, isNull);
      expect(out.request?.cookies, isNull);
      expect(out.request?.headers, isEmpty);
    });

    test('an event with nothing sensitive is returned intact', () {
      final event = SentryEvent(
        message: SentryMessage('RangeError in OrdersPage.build'),
      );
      final out = scrubEvent(event)!;
      expect(out.message?.formatted, 'RangeError in OrdersPage.build');
    });
  });
}
