// `settings.value` is jsonb and has held three different shapes.
//
// `BusinessSettingsSection._saveProfile` passed `jsonEncode(profile)` — a
// Dart String — into a jsonb column, so the client stored a jsonb SCALAR
// STRING rather than an object. APC Coimbatore's live row holds
// `"{\"invoice_terms\":\"\"}"`, and `value->>'invoice_terms'` against it
// returns null.
//
// The write side now passes the Map. This pins that the reader handles
// BOTH shapes, because rows written before the fix are still in the table
// and a vendor must not open Settings to find their saved terms blank.
import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/backend/supabase/database/tables/settings.dart';

SettingsRow row(dynamic value) => SettingsRow({'key': 'business_profile', 'value': value});

void main() {
  test('a real jsonb OBJECT — what is written from now on', () {
    expect(row({'invoice_terms': 'Pay in 7 days', 'upi_id': 'a@b'}).valueJson,
        {'invoice_terms': 'Pay in 7 days', 'upi_id': 'a@b'});
  });

  test('the live malformed row — a jsonb string holding JSON', () {
    // Byte-for-byte what APC Coimbatore holds today.
    expect(row(r'{"invoice_terms":""}').valueJson, {'invoice_terms': ''});
  });

  test('doubly-encoded, if the bug is ever reintroduced upstream', () {
    expect(row(r'"{\"invoice_terms\":\"x\"}"').valueJson,
        {'invoice_terms': 'x'});
  });

  group('malformed input returns null instead of throwing', () {
    // A broken branding blob must cost a footer, never a document.
    final bad = {
      'null': null,
      'empty string': '',
      'whitespace': '   ',
      'not json': 'this is not json',
      'a json array': '[1,2,3]',
      'a bare number': 42,
      'a json number as text': '42',
      'truncated json': '{"invoice_terms":',
    };
    bad.forEach((name, v) {
      test(name, () => expect(row(v).valueJson, isNull));
    });
  });

  test('the hand-rolled read this replaces would THROW on a real object',
      () {
    // Why every call site had to move: `value` returns Dart's
    // Map.toString() for an object — `{invoice_terms: x}` — which is not
    // JSON. Fixing the write without the readers would have broken every
    // document footer in the product.
    final r = row({'invoice_terms': 'x'});
    expect(r.value, isNot(startsWith('{"')));
    expect(r.valueJson, {'invoice_terms': 'x'});
  });
}
