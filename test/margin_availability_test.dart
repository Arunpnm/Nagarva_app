import 'package:flutter_test/flutter_test.dart';
import 'package:arun_p_k_r_s/backend/margin_availability.dart';

/// The suppression rule has to behave identically on the dashboard, the
/// branch cards, the P&L report and (later) exports. Four call sites
/// reading one starved input is exactly how four surfaces come to tell
/// the same lie independently, so the rule is tested once here rather
/// than re-derived at each.
void main() {
  group('suppress margin only when it would be a lie', () {
    test('orders but no expenses -> suppressed', () {
      // The live case: 25 orders, expenses table empty. Net profit
      // collapses to revenue and renders as a ~100% margin.
      expect(marginIsMeaningful(expensesTotal: 0, orderCount: 25), isFalse);
    });

    test('orders and expenses -> shown', () {
      expect(marginIsMeaningful(expensesTotal: 1, orderCount: 25), isTrue);
    });

    test('self-heals on the very first rupee of expense', () {
      // No threshold, no flag to flip. The person recording that first
      // expense will not be thinking about dashboards.
      expect(marginIsMeaningful(expensesTotal: 0.01, orderCount: 1), isTrue);
    });

    test('no orders -> shown, because nothing is being claimed', () {
      // A brand-new org with no activity should not be nagged. The
      // contradiction requires work to have happened.
      expect(marginIsMeaningful(expensesTotal: 0, orderCount: 0), isTrue);
    });

    test('negative or absent order count is treated as no activity', () {
      expect(marginIsMeaningful(expensesTotal: 0, orderCount: -1), isTrue);
    });
  });

  group('copy is fixed', () {
    test('exact wording, not paraphrased', () {
      // Set by Arun 25 Aug 2026. Pinned so a later tidy-up cannot soften
      // "Needs expense data" into something that reads like an error.
      expect(kMarginUnavailableTitle, 'Needs expense data');
      expect(kMarginUnavailableBody, 'Record expenses to see margin');
      expect(kNoExpensesTitle, 'No expenses recorded');
      expect(kNoExpensesBody, 'Tap to add');
    });

    test('no copy implies a zero or a dash', () {
      // The suppressed state must not read as a measurement.
      for (final s in [
        kMarginUnavailableTitle,
        kMarginUnavailableBody,
        kNoExpensesTitle,
        kNoExpensesBody,
      ]) {
        expect(s, isNot(contains('₹')));
        expect(s, isNot(contains('0')));
        expect(s.trim(), isNot('—'));
      }
    });
  });
}
