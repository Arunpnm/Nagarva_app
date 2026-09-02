import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/backend/staff_pay_types.dart';
import 'package:arun_p_k_r_s/backend/supabase/supabase.dart';

/// Staff-pay brief §2 / §11 — who appears on a crew sheet.
///
/// This is a three-string enum, so the risk is not arithmetic, it is
/// SILENCE: [StaffPayType.of]'s default decides what happens to every
/// staff row written before `pay_type` existed. Default it the wrong way
/// and the entire existing crew disappears from every crew sheet in the
/// product, with no error anywhere — the vendor just sees an empty list
/// and goes back to the diary. That failure is invisible in review and
/// invisible at runtime, which is exactly why it is pinned here.
///
/// Deliberately not covered: the crew sheet widget itself (present/absent
/// toggling, the driver tag, the A/C tick) — that is widget state over a
/// live Supabase session, not pure logic. The DB half of the driver rule
/// is enforced by the partial unique index
/// `order_staff_one_driver_per_order`, not by Dart.
StaffRow staffWith(String? payType) => StaffRow({
      'id': 'staff-1',
      'name': 'Test Hand',
      if (payType != null) 'pay_type': payType,
    });

void main() {
  group('StaffPayType.of', () {
    test('reads each of the three live CHECK values back unchanged', () {
      expect(StaffPayType.of(staffWith('monthly_fixed')),
          StaffPayType.monthlyFixed);
      expect(StaffPayType.of(staffWith('dynamic')), StaffPayType.dynamicPay);
      expect(StaffPayType.of(staffWith('temporary')), StaffPayType.temporary);
    });

    test('a row with no pay_type is DYNAMIC, not monthly-fixed', () {
      // The load-bearing case. Postgres defaults the column to 'dynamic',
      // and a row that predates the migration is loading crew until
      // somebody says otherwise. Defaulting to monthly_fixed instead
      // would empty every crew sheet silently.
      expect(StaffPayType.of(staffWith(null)), StaffPayType.dynamicPay);
      expect(StaffPayType.isOnCrewSheet(staffWith(null)), isTrue);
    });

    test('an unrecognised value falls back rather than leaking through', () {
      expect(StaffPayType.of(staffWith('contractor')), StaffPayType.dynamicPay);
      expect(StaffPayType.of(staffWith('')), StaffPayType.dynamicPay);
      // Case matters: the CHECK constraint stores lowercase, so anything
      // else is an unrecognised value, not a near miss to be normalised.
      expect(StaffPayType.of(staffWith('DYNAMIC')), StaffPayType.dynamicPay);
      expect(StaffPayType.of(staffWith('Monthly_Fixed')),
          StaffPayType.dynamicPay);
    });
  });

  group('crew sheet eligibility (validation rule §11)', () {
    test('monthly-fixed staff never appear on a crew sheet', () {
      expect(StaffPayType.isOnCrewSheet(staffWith('monthly_fixed')), isFalse);
    });

    test('dynamic and temporary staff do', () {
      expect(StaffPayType.isOnCrewSheet(staffWith('dynamic')), isTrue);
      expect(StaffPayType.isOnCrewSheet(staffWith('temporary')), isTrue);
    });

    test('eligibility is an allow-list, so a new pay type is opt-in', () {
      // If a fourth pay type is added later it must be added to
      // crewSheetEligible deliberately — it must not appear on every crew
      // sheet in the product just by existing.
      expect(StaffPayType.crewSheetEligible,
          isNot(contains(StaffPayType.monthlyFixed)));
      expect(StaffPayType.crewSheetEligible.length, 2);
      for (final t in StaffPayType.crewSheetEligible) {
        expect(StaffPayType.all, contains(t));
      }
    });
  });

  test('labels cover every value, including an unknown one', () {
    expect(StaffPayType.label(StaffPayType.monthlyFixed), 'Monthly fixed');
    expect(StaffPayType.label(StaffPayType.dynamicPay), 'Dynamic');
    expect(StaffPayType.label(StaffPayType.temporary), 'Temporary');
    expect(StaffPayType.label('contractor'), 'Dynamic');
  });
}
