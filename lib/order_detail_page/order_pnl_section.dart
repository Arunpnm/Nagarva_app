import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// Order P&L card — Order Details Session 1, item 1.
///
/// Revenue Final = orders.quote_total + non-cancelled addons. Costs pull
/// from four sources APC's own P&L never had: staff salary and order
/// expenses (which APC did have), plus vendor_bills and stock_movements
/// consumption (which APC's schema had no equivalent of at all — a
/// subcontracted or materials-heavy job silently overstated profit
/// there). Gating (canActive('reports','view'), absent not disabled) is
/// applied by the caller, not here — matches OrderCrewSection's
/// existing pattern one section up.
///
/// Porter commission correction vs. the kickoff brief: the brief's
/// formula keys off `orders.order_type` with local/outstation values.
/// That's wrong for this app specifically — order_type here has always
/// meant Direct/Porter (a prior session already found and fixed this
/// exact confusion in AccountsPage/PLReportPage). The real fields are
/// `orders.is_porter` (gate) and `orders.porter_commission_pct` (the
/// office-picked rate, stored per order, not derived) — using those
/// instead, since re-deriving from order_type would silently misfire on
/// every Porter job exactly the way the brief warned against.
class OrderPnlSection extends StatefulWidget {
  const OrderPnlSection({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderPnlSection> createState() => OrderPnlSectionState();
}

class OrderPnlSectionState extends State<OrderPnlSection> {
  bool _loading = true;
  bool _notFound = false;

  double _quoteTotal = 0;
  double _amount = 0;
  double _addonsTotal = 0;
  int _addonsCount = 0;
  double _salaryTotal = 0;
  int _staffCount = 0;
  double _expensesTotal = 0;
  int _expensesCount = 0;
  double _vendorCostTotal = 0;
  int _vendorCount = 0;
  double _materialsTotal = 0;
  int _materialsCount = 0;
  bool _isPorter = false;
  double _porterCommissionPct = 16;
  String? _status;

  /// The order's value before add-ons: `quote_total` when it came from a
  /// quote, otherwise `amount`.
  ///
  /// `quote_total` is only populated for orders created from a quote — an
  /// order booked directly carries its figure in `amount`. Reading
  /// `quote_total` alone made Revenue (Final), Net Profit and the margin
  /// all read ₹0 with a red 0% dot on every directly-booked order, while
  /// Quick Payment on the same screen correctly showed a real balance from
  /// `amount`. On a directly-booked order both now read `amount`, so that
  /// contradiction is gone. (A quoted order still bases P&L on
  /// `quote_total` while Quick Payment's balance uses `amount` — a
  /// pre-existing divergence, deliberately left alone here since
  /// `quote_total` is the right revenue basis when a quote exists.)
  double get _revenueBase => _quoteTotal != 0 ? _quoteTotal : _amount;

  double get _revenueFinal => _revenueBase + _addonsTotal;

  double get _porterCommission =>
      _isPorter ? _revenueFinal * (_porterCommissionPct / 100) : 0;

  double get _netProfit =>
      _revenueFinal -
      _salaryTotal -
      _expensesTotal -
      _vendorCostTotal -
      _materialsTotal -
      _porterCommission;

  double get _marginPct =>
      _revenueFinal <= 0 ? 0 : (_netProfit / _revenueFinal) * 100;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Public so OrderDetailPage's onPageRefresh (and, later, Quick Payment /
  /// Duplicate / document-generation actions) can re-pull this card via a
  /// GlobalKey — same wiring as QuotationBreakdownSectionState.reload().
  Future<void> reload() => _load();

  num _asNum(dynamic v) => v is num ? v : (num.tryParse('$v') ?? 0);

  /// `orders.field_expenses` shape is now pinned by migration 007:
  /// `[{"type": text, "amount": numeric, "note": text, "at": date}]`,
  /// default `'[]'`, every existing row normalised to an array. This was
  /// written against the guessed shape before 007 landed and turned out
  /// to match — kept defensive (`e is Map`/null-checked `amount`) rather
  /// than trusting the DB-level normalisation alone, since a row written
  /// by a future caller that doesn't follow the documented contract
  /// should degrade to 0, not throw.
  ///
  /// Returns (total, count). Device-test bug: the first version only
  /// tracked the total, so "Order Expenses (0 items)" showed ₹5,650 next
  /// to a count of 0 for an order whose costs came entirely from field
  /// expenses — the `expenses` table's row count was being shown as if it
  /// were the count of everything in `_expensesTotal`.
  (double, int) _sumFieldExpenses(dynamic raw) {
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

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final orderRows = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', widget.orderId),
      );
      if (orderRows.isEmpty) {
        if (mounted) setState(() {
          _loading = false;
          _notFound = true;
        });
        return;
      }
      final order = orderRows.first;
      final (fieldExpensesTotal, fieldExpensesCount) =
          _sumFieldExpenses(order.data['field_expenses']);

      final results = await Future.wait<List<dynamic>>([
        OrgScope.read(SupaFlow.client.from('addons').select('amount,status'))
            .eq('order_id', widget.orderId)
            .neq('status', 'cancelled')
            .then((v) => v),
        OrderStaffTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('order_id', widget.orderId),
        ),
        ExpensesTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('order_id', widget.orderId),
        ),
        OrgScope.read(SupaFlow.client
                .from('vendor_bills')
                .select('total_amount,status,deleted_at'))
            .eq('order_id', widget.orderId)
            .then((v) => v),
        OrgScope.read(
                SupaFlow.client.from('stock_movements').select('value'))
            .eq('order_id', widget.orderId)
            .eq('movement_type', 'consumption')
            .then((v) => v),
      ]);

      final addonsRows = results[0];
      final crewRows = results[1] as List<OrderStaffRow>;
      final expenseRows = results[2] as List<ExpensesRow>;
      final vendorBillRows = results[3]
          .where((r) => r['deleted_at'] == null && r['status'] != 'cancelled')
          .toList();
      final stockRows = results[4];

      if (!mounted) return;
      setState(() {
        _quoteTotal = order.quoteTotal ?? 0;
        _amount = order.amount ?? 0;
        _isPorter = order.isPorter ?? false;
        _porterCommissionPct = order.porterCommissionPct ?? 16;
        _status = order.status;

        _addonsTotal =
            addonsRows.fold(0.0, (s, r) => s + _asNum(r['amount']));
        _addonsCount = addonsRows.length;

        _salaryTotal =
            crewRows.fold(0.0, (s, c) => s + (c.salaryAmount ?? 0));
        _staffCount = crewRows.length;

        _expensesTotal =
            expenseRows.fold(0.0, (s, e) => s + (e.amount ?? 0)) +
                fieldExpensesTotal;
        _expensesCount = expenseRows.length + fieldExpensesCount;

        _vendorCostTotal = vendorBillRows.fold(
            0.0, (s, r) => s + _asNum(r['total_amount']));
        _vendorCount = vendorBillRows.length;

        _materialsTotal =
            stockRows.fold(0.0, (s, r) => s + _asNum(r['value']).abs());
        _materialsCount = stockRows.length;

        _loading = false;
        _notFound = false;
      });
    } catch (_) {
      // A P&L card that fails to load must not blank the whole order
      // screen — everything above it (detail fields) still renders.
      if (mounted) setState(() {
        _loading = false;
        _notFound = true;
      });
    }
  }

  String _rupees(double v) {
    final neg = v < 0;
    final s = v.abs().toStringAsFixed(0).replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return '${neg ? '-' : ''}₹$s';
  }

  Widget _row(
    FlutterFlowTheme theme, {
    required String label,
    required double? amount,
    bool negative = false,
    bool bold = false,
    Color? color,
    bool large = false,
  }) {
    // A cost row (negative: true) at exactly ₹0 reads as "—", not "₹0" in
    // red — device-test finding: Staff Salary showing a red ₹0 when no
    // salary had been entered yet read like a real zero cost rather than
    // "nothing entered". Revenue/Net Profit are unaffected (negative is
    // never true for those) — their own sign-based colour still applies
    // even at exactly ₹0.
    final isEmptyCost = negative && (amount == null || amount == 0);
    final display = (amount == null || isEmptyCost)
        ? '—'
        : (negative ? '- ${_rupees(amount)}' : _rupees(amount));
    final resolvedColor = isEmptyCost ? theme.secondaryText : color;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: large ? 14 : 12.5,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: theme.secondaryText)),
          Text(display,
              style: GoogleFonts.interTight(
                  fontSize: large ? 17 : 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: resolvedColor ?? theme.primaryText)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    if (_loading) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
            child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (_notFound) return const SizedBox.shrink();

    // Health dot thresholds, computed against Revenue (Final).
    final Color dot;
    if (_marginPct >= 25) {
      dot = theme.success;
    } else if (_marginPct >= 10) {
      dot = const Color(0xFFE0A82E);
    } else {
      dot = theme.error;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Profit & Loss',
                  style: GoogleFonts.interTight(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: theme.primaryText)),
              if ((_status ?? '').toLowerCase() == 'closed') ...[
                const SizedBox(width: 6),
                Icon(Icons.lock, size: 13, color: theme.secondaryText),
              ],
              const Spacer(),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text('${_marginPct.toStringAsFixed(0)}%',
                  style: GoogleFonts.interTight(
                      fontSize: 12, fontWeight: FontWeight.w700, color: dot)),
            ],
          ),
          const SizedBox(height: 8),
          // Stays honest at ₹0 when the order never came from a quote,
          // rather than quietly relabelling `amount` as a quote.
          _row(theme, label: 'Quote Amount', amount: _quoteTotal),
          // Shown only when falling back, so the column still visibly adds
          // up to Revenue (Final) instead of a non-zero total appearing
          // under a ₹0 line and reading like an arithmetic bug.
          if (_quoteTotal == 0 && _amount != 0)
            _row(theme, label: 'Order Amount', amount: _amount),
          if (_addonsCount > 0)
            _row(theme, label: 'Add-ons ($_addonsCount)', amount: _addonsTotal),
          const Divider(height: 16),
          _row(theme,
              label: 'Revenue (Final)',
              amount: _revenueFinal,
              bold: true,
              color: theme.success),
          const SizedBox(height: 6),
          _row(theme,
              label: 'Staff Salary ($_staffCount staff)',
              // No count-based null check needed — _row already renders
              // "—" for a negative row at exactly ₹0. The old
              // `_staffCount == 0 ? null : ...` masked the real device-test
              // bug (3 staff, ₹0 total, shown as a red ₹0) instead of
              // fixing it, since it only special-cased zero *staff*, not
              // zero *salary*.
              amount: _salaryTotal,
              negative: true,
              color: theme.error),
          _row(theme,
              label: 'Order Expenses ($_expensesCount items)',
              // Previous condition compared _salaryTotal to _expensesTotal
              // — two unrelated totals — which is almost certainly a
              // copy-paste leftover, not intentional logic; removed.
              amount: _expensesTotal,
              negative: true,
              color: theme.error),
          if (_vendorCount > 0)
            _row(theme,
                label: 'Vendor Cost ($_vendorCount)',
                amount: _vendorCostTotal,
                negative: true,
                color: theme.error),
          if (_materialsCount > 0)
            _row(theme,
                label: 'Materials ($_materialsCount)',
                amount: _materialsTotal,
                negative: true,
                color: theme.error),
          if (_isPorter)
            _row(theme,
                label:
                    'Porter Commission (${_porterCommissionPct.toStringAsFixed(0)}%)',
                amount: _porterCommission,
                negative: true,
                color: theme.error),
          const Divider(height: 16),
          _row(theme,
              label: 'Net Profit',
              amount: _netProfit,
              bold: true,
              large: true,
              color: _netProfit >= 0 ? theme.success : theme.error),
        ],
      ),
    );
  }
}
