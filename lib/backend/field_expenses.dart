/// Reading `orders.field_expenses` — the costs a supervisor logs in the
/// field (fuel, parking, crane, food) while the job is running.
///
/// These are REAL costs and they do not live in the `expenses` table. The
/// shape is pinned by migration 007:
///
///     [{"type": text, "amount": numeric, "note": text, "at": date}]
///
/// default `'[]'`, with every pre-existing row normalised to an array.
///
/// WHY THIS IS SHARED (2 Sep 2026). Order Details already summed these
/// into its P&L card, so a job showed "Order Expenses ₹2,500". The
/// dashboard summed only the `expenses` table, so the same day reported
/// "No expenses recorded" and suppressed margin with "Needs expense
/// data" — two screens disagreeing about the cost of the same job, which
/// is the exact shape of the net-profit divergence CLAUDE.md already
/// warns about between `dashboard_kpis_view` and `branch_kpis_view`.
///
/// It was also parsed twice, privately, in two files. One parser, used
/// everywhere, so a change to the stored shape cannot fix one screen and
/// leave the other wrong.
library;

num _asNum(dynamic v) => v is num ? v : (num.tryParse('$v') ?? 0);

/// Total and item count of a `field_expenses` payload.
///
/// Deliberately defensive rather than trusting the DB-level
/// normalisation: a row written by a future caller that ignores the
/// documented contract should degrade to zero, never throw on a
/// dashboard.
///
/// The count is returned because a total without one produced a real
/// device-test bug — "Order Expenses (0 items)" printed beside a non-zero
/// amount, because the `expenses` table's row count was being shown as if
/// it counted everything in the total.
(double, int) sumFieldExpenses(dynamic raw) {
  if (raw is! List) return (0, 0);
  var total = 0.0;
  var count = 0;
  for (final e in raw) {
    if (e is Map && e['amount'] != null) {
      total += _asNum(e['amount']).toDouble();
      count++;
    }
  }
  return (total, count);
}
