import 'package:flutter_test/flutter_test.dart';
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
}
