import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/backend/doc_prefix.dart';

void main() {
  group('validateDocPrefix — format', () {
    test('accepts a financial-year prefix at the 12-char ceiling', () {
      // BLR/2026-27/0001 is 16 characters, Rule 46(b)'s cap exactly.
      expect('BLR/2026-27/'.length, kDocPrefixMaxLength);
      expect(validateDocPrefix('BLR/2026-27/'), isNull);
      expect(validateDocPrefix('CBE/2026-27/'), isNull);
      expect(validateDocPrefix('AP/2026-27/'), isNull);
    });

    test('rejects 13 characters — one past the statutory budget', () {
      // The regression this guards: the CHECK allowed 10 until 2 Sep 2026,
      // so an FY prefix was rejected by the DB after the client accepted
      // it. Client and constraint must agree on the same number.
      const tooLong = 'ABCD/2026-27/';
      expect(tooLong.length, kDocPrefixMaxLength + 1);
      expect(validateDocPrefix(tooLong), contains('12 characters or fewer'));
    });

    test('blank is not an error — it means "keep the seeded default"', () {
      // Seeding derives a unique per-org prefix from the slug, so a vendor
      // with no opinion is already on a valid, non-colliding one. Treating
      // blank as invalid would block onboarding for no reason.
      expect(validateDocPrefix(''), isNull);
      expect(validateDocPrefix('   '), isNull);
    });

    test('rejects characters the DB CHECK rejects', () {
      for (final bad in ['APC 26/', 'APC#26/', 'APC_26/', 'APC.26/']) {
        expect(validateDocPrefix(bad), isNotNull, reason: bad);
      }
    });

    test('accepts letters, digits, slash and hyphen', () {
      for (final ok in ['APC', 'apc-26', 'AP/26', '2026-27/', 'A1-B2/C3']) {
        expect(validateDocPrefix(ok), isNull, reason: ok);
      }
    });

    test('trims before measuring, so trailing space is not an overflow', () {
      expect(validateDocPrefix('  BLR/2026-27/  '), isNull);
    });
  });

  group('docPrefixRejection — server uniqueness verdict', () {
    test('null means available', () {
      expect(docPrefixRejection(null), isNull);
    });

    test('a message means taken, and is surfaced verbatim', () {
      // The RPC names the holder on purpose: for a multi-org owner
      // "already used by APC Bengaluru" is actionable, "in use" is not.
      const msg = 'Prefix "BLR/2026-27/" is already used by APC Bengaluru.';
      expect(docPrefixRejection(msg), msg);
    });

    test('a reservation is reported as a rejection', () {
      const msg = 'Prefix "AP/2026-27/" is reserved for APC Andhra Pradesh '
          '(org not yet created).';
      expect(docPrefixRejection(msg), msg);
    });

    test('an empty string is treated as available, not as a blank error', () {
      expect(docPrefixRejection(''), isNull);
      expect(docPrefixRejection('   '), isNull);
    });

    test('an unexpected shape FAILS CLOSED', () {
      // The important one. This gate decides whether a vendor may take a
      // document identity; answering "free" on a response we do not
      // understand hands out a duplicate silently, which is the exact
      // failure the mechanism exists to stop. Anything non-null and
      // non-String must reject.
      for (final weird in <Object>[
        true,
        0,
        <String, dynamic>{'unexpected': 'shape'},
        <String>['BLR/2026-27/'],
      ]) {
        expect(docPrefixRejection(weird), isNotNull,
            reason: '${weird.runtimeType} must not read as available');
      }
    });
  });
}
