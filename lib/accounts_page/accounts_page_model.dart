import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'accounts_page_widget.dart' show AccountsPageWidget;
import 'package:flutter/material.dart';

/// One computed row of the Daily Accounts Register.
///
/// Mirrors the per-day cash-flow calculation in the reference APC web app
/// (reference/APC Web App JSX/App.jsx, AccountsPage, lines ~8568-8610).
/// There is no dedicated ledger table on either side — every field here is
/// derived on the fly from `orders` + `expenses` (+ `order_staff` for
/// labour salary), scoped to the current org and grouped by `orders.move_date`.
class DailyAccountRow {
  DailyAccountRow({
    required this.date,
    required this.dayOrders,
    required this.revenue,
    required this.quote,
    required this.collections,
    required this.advance,
    required this.overCollected,
    required this.pending,
    required this.salary,
    required this.orderExpenses,
    required this.otherExpenses,
    required this.porterCommission,
    this.unpricedCommissionOrderIds = const [],
  });

  final DateTime date;
  final List<OrdersRow> dayOrders;

  /// Sum of orders.amount for orders moved on this date.
  final double revenue;

  /// revenue minus logged extra charges — i.e. the original quoted amount.
  final double quote;

  /// Sum of orders.advance_paid for the day.
  final double collections;

  /// Sum of min(booking_advance, advance_paid) — the portion of collections
  /// that was actually a pre-booking advance, not day-of cash.
  final double advance;

  /// Sum of any advance_paid that exceeds orders.amount (unexplained excess).
  final double overCollected;

  /// Sum of max(0, amount - advance_paid) — still-owed balance.
  final double pending;

  /// Sum of order_staff.salary_amount for staff on this day's orders.
  final double salary;

  /// Sum of expenses linked to this day's orders (expenses.order_id set).
  final double orderExpenses;

  /// Sum of expenses NOT linked to an order, dated this day
  /// (expenses.order_id null, expenses.expense_date == date).
  final double otherExpenses;

  /// Commission on this day's commission-bearing orders, at the rate each
  /// order snapshotted at order time (`orders.commission_pct`).
  ///
  /// **A FLOOR, not a total, when [hasUnpricedCommission] is true** —
  /// orders with no rate are excluded rather than costed at a guess. This
  /// used to substitute 16% (APC's own porter rate) for any missing value,
  /// which put an invented cost into a vendor's daily register.
  final double porterCommission;

  /// Orders on this day from a commission-bearing source with no rate set.
  final List<String> unpricedCommissionOrderIds;

  bool get hasUnpricedCommission => unpricedCommissionOrderIds.isNotEmpty;

  double get totalExpenses =>
      salary + orderExpenses + otherExpenses + porterCommission;

  /// Also a floor while [hasUnpricedCommission] — real profit can only be
  /// lower, never higher, since the missing cost is a cost. The UI must
  /// mark it rather than presenting it as settled.
  double get profitLoss => revenue - totalExpenses;

  /// Set after all rows are computed: cumulative balance starting from the
  /// editable opening balance, walking forward in chronological order.
  double runningBalance = 0.0;
}

class AccountsPageModel extends FlutterFlowModel<AccountsPageWidget> {
  ///  Local state fields for this page.
  bool isLoading = true;
  String? loadError;

  /// Editable starting cash position, persisted per-org in `settings`
  /// under key `accounts_opening_balance:<orgId>` (settings.key is a plain
  /// text primary key, so it's namespaced per org rather than relying on
  /// the org_id column alone — same pattern as DB.getNextInvoiceNo's
  /// `inv_seq_<prefix>_<fy>` keys in the reference web app).
  double openingBalance = 0.0;

  /// Computed rows, newest date first (for display). Empty until loaded.
  List<DailyAccountRow> dailyRows = [];

  double get periodRevenue =>
      dailyRows.fold(0.0, (s, r) => s + r.revenue);
  double get periodExpenses =>
      dailyRows.fold(0.0, (s, r) => s + r.totalExpenses);
  double get periodProfit =>
      dailyRows.fold(0.0, (s, r) => s + r.profitLoss);
  double get currentBalance =>
      dailyRows.isEmpty ? openingBalance : dailyRows.first.runningBalance;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
