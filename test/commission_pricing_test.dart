import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/backend/commission_pricing.dart';
import 'package:arun_p_k_r_s/backend/supabase/supabase.dart';

/// Commission pricing — the rule four money surfaces share.
///
/// Pinned by test because the failure mode is SILENT and financial. The
/// code this replaces read `orders.porter_commission_pct ?? 16` in the
/// Daily Accounts register, the dashboard KPIs, the P&L report and the
/// per-order P&L card — so an unpriced order was costed at APC's own
/// porter rate, for every tenant, with no field showing it and no way to
/// correct it. Nothing errored, and the number looked plausible.
///
/// The specific regression to guard against is someone "tidying" a null
/// away with `?? 0` at a call site. That reads as defensive and is the
/// same bug in the flattering direction: it understates cost and
/// overstates profit.
OrdersRow orderWith({
  bool? commissionExpected,
  double? commissionPct,
  String id = 'ORD-1',
}) =>
    OrdersRow({
      'id': id,
      'customer': 'Test',
      'move_date': '2026-09-02',
      if (commissionExpected != null) 'commission_expected': commissionExpected,
      if (commissionPct != null) 'commission_pct': commissionPct,
    });

void main() {
  group('commissionStateFor', () {
    test('a set rate is priced, whatever else is true', () {
      // Checked BEFORE the expectation gate on purpose: a rate the vendor
      // actually typed must never be dropped, including the real case of a
      // one-off cut negotiated on a source that does not normally charge.
      expect(
        commissionStateFor(commissionExpected: false, commissionPct: 12),
        CommissionState.priced,
      );
      expect(
        commissionStateFor(commissionExpected: true, commissionPct: 16),
        CommissionState.priced,
      );
    });

    test('expected with no rate is UNPRICED — not zero, not a substitute', () {
      expect(
        commissionStateFor(commissionExpected: true, commissionPct: null),
        CommissionState.unpriced,
      );
    });

    test('not expected and no rate owes nothing, and must not warn', () {
      // The walk-in case. A warning here would appear on ordinary orders,
      // and a warning on everything is a warning on nothing.
      expect(
        commissionStateFor(commissionExpected: false, commissionPct: null),
        CommissionState.none,
      );
    });

    test('a paid source with a forgotten rate DOES warn', () {
      // The residual that `commission_expected` was added to close. Before
      // it existed this same order read as "no commission", because the
      // only available gate was is_porter and this is not a porter job.
      expect(
        commissionStateFor(commissionExpected: true, commissionPct: null),
        CommissionState.unpriced,
      );
    });

    test('a MISSING expectation is treated as false, not as owed', () {
      // Null here means the column was not selected, not that a commission
      // is owed. Defaulting the other way would warn on rows nobody even
      // queried the field for.
      expect(
        commissionStateFor(commissionExpected: null, commissionPct: null),
        CommissionState.none,
      );
    });

    test('zero percent is a DECISION, not a missing value', () {
      // 0 and null must never collapse into each other: one is "we agreed
      // no cut", the other is "nobody has said".
      expect(
        commissionStateFor(commissionExpected: true, commissionPct: 0),
        CommissionState.priced,
      );
    });
  });

  group('commissionAmount', () {
    test('computes against the revenue base the caller supplies', () {
      expect(
        commissionAmount(
            order: orderWith(commissionExpected: true, commissionPct: 16),
            revenueBase: 10000),
        1600,
      );
    });

    test('returns NULL for unpriced — never a substituted rate', () {
      expect(
        commissionAmount(
            order: orderWith(commissionExpected: true),
            revenueBase: 10000),
        isNull,
      );
    });

    test('returns 0 for an order that owes nothing', () {
      expect(
        commissionAmount(
            order: orderWith(commissionExpected: false), revenueBase: 10000),
        0,
      );
    });

    test('0% costs nothing, and is not confused with unpriced', () {
      expect(
        commissionAmount(
            order: orderWith(commissionExpected: true, commissionPct: 0),
            revenueBase: 10000),
        0,
      );
    });
  });

  group('rollUpCommission', () {
    test('excludes unpriced orders from the total and names them', () {
      final rollup = rollUpCommission(
        [
          orderWith(id: 'A', commissionExpected: true, commissionPct: 10),
          orderWith(id: 'B', commissionExpected: true),
          orderWith(id: 'C', commissionExpected: false),
        ],
        (_) => 1000,
      );
      // 100 from A only. B contributes NOTHING to the figure and is named
      // instead; C legitimately owes nothing.
      expect(rollup.total, 100);
      expect(rollup.unpricedOrderIds, ['B']);
      expect(rollup.unpricedCount, 1);
      expect(rollup.isComplete, isFalse);
    });

    test('a fully priced period reports complete', () {
      final rollup = rollUpCommission(
        [
          orderWith(id: 'A', commissionExpected: true, commissionPct: 10),
          orderWith(id: 'B', commissionExpected: false),
        ],
        (_) => 1000,
      );
      expect(rollup.total, 100);
      expect(rollup.isComplete, isTrue);
      expect(rollup.unpricedOrderIds, isEmpty);
    });

    test('the total is a FLOOR — it never silently absorbs the gap', () {
      // The regression this whole file exists for. If someone reintroduces
      // a substituted rate, this total moves; if someone writes `?? 0`, the
      // unpriced list empties. Either way one of these two expectations
      // fails.
      final rollup = rollUpCommission(
        [
          orderWith(id: 'A', commissionExpected: true),
          orderWith(id: 'B', commissionExpected: true),
        ],
        (_) => 50000,
      );
      expect(rollup.total, 0);
      expect(rollup.unpricedCount, 2);
    });

    test('an empty period is complete, not suspicious', () {
      final rollup = rollUpCommission(const <OrdersRow>[], (_) => 0);
      expect(rollup.total, 0);
      expect(rollup.isComplete, isTrue);
    });
  });

  group('copy', () {
    test('the aggregate caveat reads naturally at 1 and at many', () {
      expect(commissionIncompleteNote(1), startsWith('1 order has'));
      expect(commissionIncompleteNote(3), startsWith('3 orders have'));
    });
  });
}
