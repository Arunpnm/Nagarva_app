// Tax-type detection is decided by a STRING MATCH, which CLAUDE.md's own
// convention says must be tested with the format that actually occurs in
// the wild, not the format that is easiest to match.
//
// The bug these pin (found live, 2 Sep 2026): gstStateCode is an exact map
// lookup, and the quote builder passes full postal addresses. Neither end
// matched, both fell to the default 33, and a Chennai -> Bengaluru move was
// billed CGST + SGST instead of IGST. Both cities were in the table the
// whole time — the lookup was simply never given a city.
import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/backend/gst_state_codes.dart';

void main() {
  group('gstStateCode — exact city lookup (unchanged behaviour)', () {
    test('known cities resolve', () {
      expect(gstStateCode('Chennai'), 33);
      expect(gstStateCode('Bengaluru'), 29);
      expect(gstStateCode('bangalore'), 29);
    });

    test('unknown falls back to the documented default', () {
      expect(gstStateCode('Nowhere'), kGstDefaultStateCode);
      expect(gstStateCode(null), kGstDefaultStateCode);
      expect(gstStateCode(''), kGstDefaultStateCode);
    });
  });

  group('gstStateCodeFromLocation — full addresses', () {
    test('the exact addresses from the live failure now resolve', () {
      expect(
        gstStateCodeFromLocation(
            '12/4 Anna Nagar West, 2nd Floor, Chennai 600040'),
        33,
      );
      expect(
        gstStateCodeFromLocation(
            'No 7 HSR Layout Sector 2, Ground Floor, Bengaluru 560102'),
        29,
      );
    });

    test('a bare city still works', () {
      expect(gstStateCodeFromLocation('Chennai'), 33);
      expect(gstStateCodeFromLocation('  bengaluru  '), 29);
    });

    test('case and surrounding punctuation do not matter', () {
      expect(gstStateCodeFromLocation('FLAT 3B, CHENNAI - 600 001'), 33);
    });

    test('when two cities appear, the LAST one wins', () {
      // Indian addresses put the city near the end, so an earlier match is
      // usually a street or locality name rather than the destination.
      expect(gstStateCodeFromLocation('Mysore Road, Bengaluru 560026'), 29);
    });

    test('nothing recognisable still falls back, never guesses harder', () {
      expect(gstStateCodeFromLocation('Plot 12, Industrial Estate'),
          kGstDefaultStateCode);
      expect(gstStateCodeFromLocation(null), kGstDefaultStateCode);
      expect(gstStateCodeFromLocation(''), kGstDefaultStateCode);
    });
  });

  group('isInterState — the regression that mis-taxed a real quote', () {
    test('Chennai -> Bengaluru is INTERSTATE when given full addresses', () {
      expect(
        isInterState(
          '12/4 Anna Nagar West, 2nd Floor, Chennai 600040',
          'No 7 HSR Layout Sector 2, Ground Floor, Bengaluru 560102',
        ),
        isTrue,
        reason: 'this pair returned false and produced CGST+SGST on a '
            'genuinely inter-state consignment',
      );
    });

    test('Chennai -> Bengaluru is INTERSTATE when given bare cities', () {
      expect(isInterState('Chennai', 'Bengaluru'), isTrue);
    });

    test('a move within one state is INTRA-state', () {
      expect(isInterState('Chennai', 'Coimbatore'), isFalse);
      expect(
        isInterState('12/4 Anna Nagar, Chennai 600040',
            '5 Race Course Road, Coimbatore 641018'),
        isFalse,
      );
    });

    test('two unknown locations read as intra-state, as before', () {
      // Both fall to the same default. Stated explicitly because it is the
      // assumption the whole bug rested on, and it is still live for any
      // city missing from the table.
      expect(isInterState('Somewhere', 'Elsewhere'), isFalse);
    });
  });
}
