import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arun_p_k_r_s/backend/fy_numbering.dart';

void main() {
  group('financial year', () {
    test('31 March is still the old year, 1 April the new', () {
      expect(currentFy(DateTime(2027, 3, 31, 23, 59)), '2026-27');
      expect(currentFy(DateTime(2027, 4, 1)), '2027-28');
      expect(currentFy(DateTime(2027, 1, 15)), '2026-27');
    });

    test('next year and the century wrap', () {
      expect(nextFy('2026-27'), '2027-28');
      expect(fyStarting(2099), '2099-00');
      expect(nextFy('2099-00'), '2100-01');
    });
  });

  group('isMissingSeriesError', () {
    PostgrestException p0001(String m) =>
        PostgrestException(message: m, code: 'P0001');

    test('matches both allocators\' "no series" refusals', () {
      expect(
          isMissingSeriesError(p0001(
              'No active number series configured for org=x, doc_type=invoice, '
              'branch=<none>, fy=2027-28. Configure one in number_series …')),
          isTrue);
      expect(
          isMissingSeriesError(p0001(
              'No active LR series configured for org=x, branch=<none>, '
              'fy=2027-28.')),
          isTrue);
    });

    // Offering to "start the year" for any other refusal would send the
    // user to fix the wrong thing.
    test('ignores every other P0001', () {
      expect(
          isMissingSeriesError(p0001(
              'next_doc_number cannot allocate order ids. Use next_order_id')),
          isFalse);
      expect(
          isMissingSeriesError(
              p0001('Your plan allows 50 orders a month.')),
          isFalse);
    });

    test('ignores other codes and non-Postgres errors', () {
      expect(
          isMissingSeriesError(PostgrestException(
              message: 'No active number series configured', code: '42501')),
          isFalse);
      expect(isMissingSeriesError(Exception('No active number series')),
          isFalse);
      expect(isMissingSeriesError('No active number series'), isFalse);
    });
  });
}
