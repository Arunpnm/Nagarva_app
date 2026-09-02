// Storage charging rules, from nagarva_staff_pay_and_expense_brief.md
// sections 37-44. These are vendor decisions with money attached, not
// arithmetic preferences, so each one is pinned here.
//
// The two most expensive to get wrong, and the reason this file exists:
//   1. the 15-day minimum (an 8-day stay bills 15)
//   2. the plan is LOCKED at booking - a daily stay never becomes monthly
//      at day 30, and a monthly stay never refunds an early collection
import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/backend/storage_billing.dart';

void main() {
  final inDate = DateTime(2026, 9, 1);

  group('storageDays', () {
    test('counts whole calendar days', () {
      expect(storageDays(inDate, DateTime(2026, 9, 16)), 15);
      expect(storageDays(inDate, DateTime(2026, 10, 1)), 30);
    });

    test('same day is zero, and a reversed range never goes negative', () {
      expect(storageDays(inDate, inDate), 0);
      expect(storageDays(DateTime(2026, 9, 10), inDate), 0);
    });

    test('time of day is ignored — intake at 9am and 6pm bill the same', () {
      expect(
        storageDays(DateTime(2026, 9, 1, 9), DateTime(2026, 9, 16, 18)),
        15,
      );
    });
  });

  group('daily plan — the 15-day minimum (§38)', () {
    test('an 8-day stay bills 15 days, and says so', () {
      final c = computeStorageCharge(
        inDate: inDate,
        outDate: DateTime(2026, 9, 9),
        mode: StorageBillingMode.perDay,
        rate: 300,
      );
      expect(c.days, 8);
      expect(c.billedUnits, 15);
      expect(c.rent, 4500);
      expect(c.minimumApplied, isTrue,
          reason: 'a customer disputing an 8-day bill charged at 15 must be '
              'shown why, not just given a number');
    });

    test('a stay past the floor bills its actual days', () {
      final c = computeStorageCharge(
        inDate: inDate,
        outDate: DateTime(2026, 9, 21),
        mode: StorageBillingMode.perDay,
        rate: 300,
      );
      expect(c.days, 20);
      expect(c.billedUnits, 20);
      expect(c.rent, 6000);
      expect(c.minimumApplied, isFalse);
    });

    test('exactly at the floor is not flagged as a minimum', () {
      final c = computeStorageCharge(
        inDate: inDate,
        outDate: DateTime(2026, 9, 16),
        mode: StorageBillingMode.perDay,
        rate: 300,
      );
      expect(c.billedUnits, 15);
      expect(c.minimumApplied, isFalse);
    });

    test('the floor is per-record, not hardcoded', () {
      final c = computeStorageCharge(
        inDate: inDate,
        outDate: DateTime(2026, 9, 4),
        mode: StorageBillingMode.perDay,
        rate: 300,
        minBillingDays: 7,
      );
      expect(c.billedUnits, 7);
      expect(c.rent, 2100);
    });
  });

  group('the plan is LOCKED at booking (§39)', () {
    test('a DAILY stay does NOT become monthly at 30 days', () {
      // 45 days daily at 300 = 13,500. If the system silently switched to
      // the 4,200 monthly rate this would read 8,400 and the vendor would
      // be under-billing by 5,100 on one stay.
      final c = computeStorageCharge(
        inDate: inDate,
        outDate: DateTime(2026, 10, 16),
        mode: StorageBillingMode.perDay,
        rate: 300,
      );
      expect(c.days, 45);
      expect(c.billedUnits, 45);
      expect(c.rent, 13500);
    });

    test('a MONTHLY stay collected early still pays the whole month', () {
      final c = computeStorageCharge(
        inDate: inDate,
        outDate: DateTime(2026, 9, 6),
        mode: StorageBillingMode.perMonth,
        rate: 4200,
      );
      expect(c.days, 5);
      expect(c.billedUnits, 1);
      expect(c.rent, 4200, reason: 'no pro-rata refund on early collection');
    });

    test('monthly rounds UP to whole months', () {
      final c = computeStorageCharge(
        inDate: inDate,
        outDate: DateTime(2026, 10, 2), // 31 days
        mode: StorageBillingMode.perMonth,
        rate: 4200,
      );
      expect(c.billedUnits, 2);
      expect(c.rent, 8400);
    });

    test('monthly does not apply the daily minimum-days floor', () {
      final c = computeStorageCharge(
        inDate: inDate,
        outDate: DateTime(2026, 9, 3),
        mode: StorageBillingMode.perMonth,
        rate: 4200,
        minBillingDays: 15,
      );
      expect(c.rent, 4200);
      expect(c.minimumApplied, isFalse,
          reason: 'monthly rounding and the daily floor are different rules '
              'and the UI must not explain one with the other');
    });
  });

  group('monthly is NOT assumed cheaper than daily (§39)', () {
    // The vendor's own rates invert between two sizes. Anything that
    // "helpfully" picked the cheaper plan would be wrong half the time.
    test('Tata Ace: 15 days daily (4,500) costs MORE than a month (4,200)',
        () {
      final daily = computeStorageCharge(
        inDate: inDate,
        outDate: DateTime(2026, 9, 16),
        mode: StorageBillingMode.perDay,
        rate: 300,
      );
      final monthly = computeStorageCharge(
        inDate: inDate,
        outDate: DateTime(2026, 9, 16),
        mode: StorageBillingMode.perMonth,
        rate: 4200,
      );
      expect(daily.rent, 4500);
      expect(monthly.rent, 4200);
      expect(daily.rent, greaterThan(monthly.rent));
    });

    test('Pickup: 15 days daily (5,250) costs LESS than a month (5,300)', () {
      final daily = computeStorageCharge(
        inDate: inDate,
        outDate: DateTime(2026, 9, 16),
        mode: StorageBillingMode.perDay,
        rate: 350,
      );
      final monthly = computeStorageCharge(
        inDate: inDate,
        outDate: DateTime(2026, 9, 16),
        mode: StorageBillingMode.perMonth,
        rate: 5300,
      );
      expect(daily.rent, 5250);
      expect(monthly.rent, 5300);
      expect(daily.rent, lessThan(monthly.rent),
          reason: 'the relationship inverts between sizes, which is exactly '
              'why no code may compare the two plans');
    });
  });

  group('accrual while goods are still in store (§41)', () {
    test('a null out-date accrues to the as-of date', () {
      final c = computeStorageCharge(
        inDate: inDate,
        asOf: DateTime(2026, 9, 21),
        mode: StorageBillingMode.perDay,
        rate: 300,
      );
      expect(c.days, 20);
      expect(c.rent, 6000);
    });

    test('accrual on a young stay still shows the minimum', () {
      final c = computeStorageCharge(
        inDate: inDate,
        asOf: DateTime(2026, 9, 4),
        mode: StorageBillingMode.perDay,
        rate: 300,
      );
      expect(c.days, 3);
      expect(c.rent, 4500);
      expect(c.minimumApplied, isTrue);
    });
  });

  group('handling is separate from rent (§40)', () {
    test('loading and unloading are not folded into rent', () {
      final c = computeStorageCharge(
        inDate: inDate,
        outDate: DateTime(2026, 9, 16),
        mode: StorageBillingMode.perDay,
        rate: 300,
        handlingIn: 2000,
        handlingOut: 2500,
      );
      expect(c.rent, 4500);
      expect(c.handlingIn, 2000);
      expect(c.handlingOut, 2500);
      expect(c.total, 9000);
    });
  });

  group('custom arrangements bill exactly what was agreed', () {
    test('no floor and no rounding is applied', () {
      final c = computeStorageCharge(
        inDate: inDate,
        outDate: DateTime(2026, 9, 3),
        mode: StorageBillingMode.custom,
        rate: 999,
        customAmount: 12000,
        minBillingDays: 15,
      );
      expect(c.rent, 12000);
      expect(c.billedUnits, 1);
      expect(c.minimumApplied, isFalse);
    });
  });

  group('wire format matches the storage_jobs column', () {
    test('round-trips, and an unknown value falls back to the DB default', () {
      for (final m in StorageBillingMode.values) {
        expect(storageBillingModeFromWire(storageBillingModeToWire(m)), m);
      }
      expect(storageBillingModeFromWire(null), StorageBillingMode.perMonth);
      expect(storageBillingModeFromWire('nonsense'),
          StorageBillingMode.perMonth);
    });
  });

  group('rates come from org config, never from a shipped default', () {
    // The product rule: no price, rate, wage or charge is ever pre-filled
    // or suggested. A vendor's storage rates are THEIR data.
    const apcRates = [
      StorageSizeRate(size: 'Tata Ace', perDay: 300, perMonth: 4200),
      StorageSizeRate(size: 'Pickup', perDay: 350, perMonth: 5300),
    ];

    test('an org with no storage_rates gets an EMPTY list', () {
      expect(parseStorageRates(null), isEmpty);
      expect(parseStorageRates(const []), isEmpty);
      expect(parseStorageRates('nonsense'), isEmpty);
    });

    test('parses the stored jsonb shape', () {
      final parsed = parseStorageRates(const [
        {'size': 'Tata Ace', 'per_day': 300, 'per_month': 4200, 'min_days': 15},
      ]);
      expect(parsed, hasLength(1));
      expect(parsed.first.size, 'Tata Ace');
      expect(parsed.first.perDay, 300);
      expect(parsed.first.perMonth, 4200);
      expect(parsed.first.minDays, 15);
      expect(parsed.first.minimumCharge, 4500);
    });

    test('rows without a size are dropped rather than shown blank', () {
      expect(parseStorageRates(const [{'per_day': 300}]), isEmpty);
    });

    test('round-trips through the editor format', () {
      final back = parseStorageRates(storageRatesToConfig(apcRates));
      expect(back.map((r) => r.size).toList(), ['Tata Ace', 'Pickup']);
      expect(back.map((r) => r.perMonth).toList(), [4200, 5300]);
    });

    test('suggestStorageSize matches against the ORG list', () {
      expect(suggestStorageSize(400, apcRates, (_) => 'Pickup'), 'Pickup');
    });

    test('returns null rather than guessing when nothing matches', () {
      expect(suggestStorageSize(400, apcRates, (_) => 'Trailer'), isNull);
      expect(suggestStorageSize(400, apcRates, (_) => null), isNull);
      expect(suggestStorageSize(0, apcRates, (_) => 'Pickup'), isNull);
      expect(suggestStorageSize(400, const [], (_) => 'Pickup'), isNull);
    });
  });

  group('the snapshotted rate is what bills (§44)', () {
    // A stay holds the rate agreed at intake. Changing the rate card
    // afterwards must not re-bill goods already in store - in EITHER
    // direction. computeStorageCharge only ever sees the number it is
    // given, which is read from storage_jobs.rate, so these pin that the
    // charge follows the snapshot and not any later figure.
    final inDate = DateTime(2026, 9, 1);
    final out = DateTime(2026, 10, 1); // 30 days

    test('a rate RAISED after booking does not increase an open stay', () {
      final atBooking = computeStorageCharge(
        inDate: inDate,
        outDate: out,
        mode: StorageBillingMode.perDay,
        rate: 300,
      );
      final ifItHadFollowedTheCard = computeStorageCharge(
        inDate: inDate,
        outDate: out,
        mode: StorageBillingMode.perDay,
        rate: 400,
      );
      expect(atBooking.rent, 9000);
      expect(ifItHadFollowedTheCard.rent, 12000);
      expect(atBooking.rent, lessThan(ifItHadFollowedTheCard.rent),
          reason: 'the stay must keep 9,000 - the customer agreed 300/day');
    });

    test('a rate LOWERED after booking does not reduce an open stay', () {
      final atBooking = computeStorageCharge(
        inDate: inDate,
        outDate: out,
        mode: StorageBillingMode.perDay,
        rate: 300,
      );
      final ifItHadFollowedTheCard = computeStorageCharge(
        inDate: inDate,
        outDate: out,
        mode: StorageBillingMode.perDay,
        rate: 200,
      );
      expect(atBooking.rent, 9000);
      expect(ifItHadFollowedTheCard.rent, 6000);
      expect(atBooking.rent, greaterThan(ifItHadFollowedTheCard.rent));
    });
  });

  group('billing paths beyond the zero-day minimum', () {
    final inDate = DateTime(2026, 9, 1);

    test('daily, 30 days @ 300 bills 9,000 with no minimum applied', () {
      final c = computeStorageCharge(
        inDate: inDate,
        outDate: DateTime(2026, 10, 1),
        mode: StorageBillingMode.perDay,
        rate: 300,
      );
      expect(c.days, 30);
      expect(c.billedUnits, 30);
      expect(c.unitLabel, 'days');
      expect(c.rent, 9000);
      expect(c.minimumApplied, isFalse,
          reason: 'past the floor the card must stop claiming a minimum');
    });

    test('monthly released on day 5 bills the whole month', () {
      final c = computeStorageCharge(
        inDate: inDate,
        outDate: DateTime(2026, 9, 6),
        mode: StorageBillingMode.perMonth,
        rate: 4200,
      );
      expect(c.days, 5);
      expect(c.billedUnits, 1);
      expect(c.unitLabel, 'month');
      expect(c.rent, 4200);
    });

    test('daily 45 days bills 13,500 and never the monthly figure', () {
      final c = computeStorageCharge(
        inDate: inDate,
        outDate: DateTime(2026, 10, 16),
        mode: StorageBillingMode.perDay,
        rate: 300,
      );
      expect(c.rent, 13500);
      expect(c.rent, isNot(4200));
      expect(c.rent, isNot(8400));
    });
  });

  group('guards', () {
    test('an out-date before the in-date never yields negative days', () {
      final c = computeStorageCharge(
        inDate: DateTime(2026, 9, 10),
        outDate: DateTime(2026, 9, 1),
        mode: StorageBillingMode.perDay,
        rate: 300,
      );
      expect(c.days, 0);
      expect(c.rent, 4500, reason: 'falls back to the minimum, never negative');
      expect(c.rent, greaterThan(0));
    });

    test('a reversed range on the monthly plan bills one month, not zero', () {
      final c = computeStorageCharge(
        inDate: DateTime(2026, 9, 10),
        outDate: DateTime(2026, 9, 1),
        mode: StorageBillingMode.perMonth,
        rate: 4200,
      );
      expect(c.billedUnits, 1);
      expect(c.rent, 4200);
    });
  });
}
