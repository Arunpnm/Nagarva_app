/// When is a margin figure honest?
///
/// Added 25 Aug 2026 for the dashboard redesign, but deliberately NOT
/// put in the dashboard: `net_profit_this_month` surfaces on the
/// dashboard, on branch KPI cards, in the P&L report and (once built)
/// in exports. All four read the same starved input, so all four would
/// tell the same lie independently.
///
/// **The lie is specific and expensive.** `expenses` has 0 live rows.
/// Net profit is computed as `revenue − labour − expenses − porter
/// commission`, so with no expenses recorded it reports revenue almost
/// unchanged and renders as a ~100% margin. A vendor reading "₹1.85L
/// profit" on a month where they spent real money on diesel, labour and
/// packing material is being handed a number that is not merely
/// imprecise — it is wrong in the direction that feels good, which is
/// the direction nobody questions.
///
/// A zero is worse than a blank here. `₹0 expenses` looks like a
/// measurement; a blank looks like a gap, and a gap is what it is.
///
/// **Self-healing by construction:** the moment the first expense row is
/// recorded, [marginIsMeaningful] returns true everywhere at once and
/// every surface starts showing the figure. There is no flag to flip and
/// nothing to remember — which is the point, since the person who
/// records that first expense will not be thinking about dashboards.
library;

/// The one rule, so the four surfaces cannot drift apart.
///
/// Margin is suppressed when no expenses are recorded for a period that
/// nonetheless had orders. Both halves matter:
///
/// * `expensesTotal == 0` alone would suppress margin for a brand-new
///   org with no activity at all, where a blank is just noise.
/// * `orderCount > 0` is what makes it a contradiction: work happened,
///   so costs certainly happened, so a zero-cost margin is fiction
///   rather than a genuine "nothing to report".
///
/// Returns true when the figure may be shown.
bool marginIsMeaningful({
  required double expensesTotal,
  required int orderCount,
}) {
  if (orderCount <= 0) return true; // nothing claimed, nothing to mislead
  return expensesTotal > 0;
}

/// Copy for the suppressed Profit tile. Exact wording set by Arun,
/// 25 Aug 2026 — keep it, do not paraphrase.
const String kMarginUnavailableTitle = 'Needs expense data';
const String kMarginUnavailableBody = 'Record expenses to see margin';

/// Copy for the Expenses tile when nothing has been recorded. The tile
/// is tappable and opens expense entry — an empty state that offers the
/// action that fixes it, rather than one that just reports emptiness.
const String kNoExpensesTitle = 'No expenses recorded';
const String kNoExpensesBody = 'Tap to add';
