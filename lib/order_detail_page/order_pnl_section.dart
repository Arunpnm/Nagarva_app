import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/commission_pricing.dart';
import '/backend/field_expenses.dart';
import '/backend/storage_billing.dart';
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
/// `orders.commission_expected` (gate) and `orders.commission_pct` (the
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
  /// GST-exclusive quote figure and the tax on it. See [_revenueBase]:
  /// GST is collected for the government, never revenue.
  double _quoteSubtotal = 0;
  double _quoteGstAmount = 0;
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

  /// Warehouse rent + handling earned on this order. Storage is a REVENUE
  /// line inside the order (brief §37), not a separate order and not a
  /// cost - so it is added to revenue, never subtracted.
  double _storageIncome = 0;

  /// Null when the goods are still in store, in which case the figure is
  /// an accrual rather than a settled charge and the card says so.
  bool _storageOpen = false;
  /// Snapshotted at order time from the lead source — see
  /// `OrdersRow.commissionExpected`. Never re-derived here.
  bool _commissionExpected = false;

  /// Null means NOT PRICED, and must stay null all the way to the render.
  /// It used to default to 16 — APC's porter rate — so an unpriced order
  /// silently carried a commission cost nobody had agreed.
  double? _commissionPct;
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
  /// **GST IS NOT REVENUE AND NOT PROFIT.** (Arun, 2 Sept 2026 — a
  /// standing rule, stated for the dashboard and applying everywhere.)
  ///
  /// GST collected on an invoice is money held for the government and
  /// remitted; treating it as revenue overstates profit by the whole tax
  /// amount, in the flattering direction — the direction nobody
  /// questions. On the first Coimbatore order this card read Net Profit
  /// ₹35,990 where the true figure was ₹30,500, while the DASHBOARD read
  /// ₹30,500 for the same order because it already excludes GST. Two
  /// screens, two profits for one job, with nothing saying which is
  /// which — the exact disease CLAUDE.md records between
  /// `dashboard_kpis_view` and `branch_kpis_view`.
  ///
  /// `quote_subtotal` is the GST-exclusive figure and is preferred.
  /// Falling back to `total - gst` rather than to `total` matters for
  /// rows written before subtotal was stored. An order with no quote and
  /// no GST (a direct booking) lands on `amount` unchanged.
  double get _revenueBase {
    if (_quoteSubtotal != 0) return _quoteSubtotal;
    final gross = _quoteTotal != 0 ? _quoteTotal : _amount;
    return gross - _quoteGstAmount;
  }

  double get _revenueFinal =>
      _revenueBase + _addonsTotal + _storageIncome;

  CommissionState get _commissionState => commissionStateFor(
        commissionExpected: _commissionExpected,
        commissionPct: _commissionPct,
      );

  /// Null when the order is commission-bearing but unpriced. Net profit
  /// below is deliberately NOT computed in that case — see [_netProfit].
  double? get _commission {
    switch (_commissionState) {
      case CommissionState.none:
        return 0;
      case CommissionState.unpriced:
        return null;
      case CommissionState.priced:
        return _revenueFinal * (_commissionPct! / 100);
    }
  }

  /// Null when commission is unpriced.
  ///
  /// Net profit MUST follow commission into unavailability rather than
  /// quietly dropping the cost: subtracting nothing would overstate profit
  /// by the whole commission, which is the flattering direction — the one
  /// nobody questions. Same reasoning as `marginIsMeaningful` in
  /// /backend/margin_availability.dart, which already suppresses margin
  /// rather than reporting it over starved expense data.
  double? get _netProfit {
    final comm = _commission;
    if (comm == null) return null;
    return _revenueFinal -
        _salaryTotal -
        _expensesTotal -
        _vendorCostTotal -
        _materialsTotal -
        comm;
  }

  double? get _marginPct {
    final net = _netProfit;
    if (net == null) return null;
    return _revenueFinal <= 0 ? 0 : (net / _revenueFinal) * 100;
  }

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
  /// Delegates to the shared parser so this card and the dashboard can
  /// never drift apart on what a field expense is worth.
  (double, int) _sumFieldExpenses(dynamic raw) => sumFieldExpenses(raw);

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
        // Warehouse storage on this order. Revenue, not cost - rent the
        // vendor earns while holding the customer's goods (brief §37).
        OrgScope.read(SupaFlow.client.from('storage_jobs').select(
                'in_date,out_date,billing_mode,rate,min_billing_days,'
                'handling_in_charge,handling_out_charge'))
            .eq('order_id', widget.orderId)
            .then((v) => v),
      ]);

      final addonsRows = results[0];
      final crewRows = results[1] as List<OrderStaffRow>;
      final expenseRows = results[2] as List<ExpensesRow>;
      final vendorBillRows = results[3]
          .where((r) => r['deleted_at'] == null && r['status'] != 'cancelled')
          .toList();
      final stockRows = results[4];
      final storageRows = results[5];

      if (!mounted) return;
      setState(() {
        _quoteTotal = order.quoteTotal ?? 0;
        _quoteSubtotal = order.quoteSubtotal ?? 0;
        _quoteGstAmount = order.quoteGstAmount ?? 0;
        _amount = order.amount ?? 0;
        _commissionExpected = order.commissionExpected ?? false;
        _commissionPct = order.commissionPct;
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

        // Priced by the same function the storage card uses, so the two
        // can never quote a different number for the same stay.
        _storageIncome = 0;
        _storageOpen = false;
        for (final r in storageRows) {
          final rawIn = r['in_date'];
          if (rawIn == null) continue;
          final inDate = DateTime.tryParse('$rawIn');
          if (inDate == null) continue;
          final rawOut = r['out_date'];
          final outDate =
              rawOut == null ? null : DateTime.tryParse('$rawOut');
          if (outDate == null) _storageOpen = true;
          final charge = computeStorageCharge(
            inDate: inDate,
            outDate: outDate,
            mode: storageBillingModeFromWire(r['billing_mode'] as String?),
            rate: _asNum(r['rate']).toDouble(),
            minBillingDays: _asNum(r['min_billing_days']).toInt(),
            handlingIn: _asNum(r['handling_in_charge']).toDouble(),
            handlingOut: _asNum(r['handling_out_charge']).toDouble(),
            customAmount: _asNum(r['rate']).toDouble(),
          );
          _storageIncome += charge.total;
        }

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

    // Health dot thresholds, computed against Revenue (Final). A null
    // margin (commission unpriced) shows a neutral dot and no percentage
    // — a green dot over an unknown cost is the most confident possible
    // way to be wrong.
    final margin = _marginPct;
    final Color dot;
    if (margin == null) {
      dot = theme.secondaryText;
    } else if (margin >= 25) {
      dot = theme.success;
    } else if (margin >= 10) {
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
              Text(margin == null ? '--' : '${margin.toStringAsFixed(0)}%',
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
          // GST is shown being REMOVED, rather than silently absent from
          // the total. Without this line the card printed
          // "Quote Amount 35,990" and "Revenue (Final) 37,640" with a
          // 7,140 storage line between them - three numbers that do not
          // add up, which reads as an arithmetic bug rather than as tax
          // being excluded. Same reasoning as the 'Order Amount'
          // fallback row directly above: the column has to visibly add
          // up, or the vendor cannot check it.
          if (_quoteGstAmount > 0)
            _row(theme,
                label: 'Less GST (collected for govt)',
                amount: -_quoteGstAmount),
          if (_addonsCount > 0)
            _row(theme, label: 'Add-ons ($_addonsCount)', amount: _addonsTotal),
          // Storage rent is revenue, and it is shown as its own line so a
          // vendor can see what the godown earned on this job rather than
          // finding it folded anonymously into the total. Labelled as an
          // accrual while the goods are still in store, because that
          // figure will keep growing.
          if (_storageIncome > 0)
            _row(theme,
                label: _storageOpen
                    ? 'Storage (accruing)'
                    : 'Storage',
                amount: _storageIncome),
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
          if (_commissionState == CommissionState.priced)
            _row(theme,
                label: 'Commission '
                    '(${_commissionPct!.toStringAsFixed(_commissionPct! % 1 == 0 ? 0 : 2)}%)',
                amount: _commission,
                negative: true,
                color: theme.error),
          // An unpriced commission is stated, not rendered as "—". A dash
          // in a cost column reads as "nothing to pay"; this order has a
          // cost nobody has quantified yet, which is a different fact and
          // the only one that prompts anybody to fix it.
          if (_commissionState == CommissionState.unpriced)
            _unpricedCommissionRow(theme),
          const Divider(height: 16),
          if (_netProfit == null)
            _unavailableNetProfitRow(theme)
          else
            _row(theme,
                label: 'Net Profit',
                amount: _netProfit,
                bold: true,
                large: true,
                color: _netProfit! >= 0 ? theme.success : theme.error),
        ],
      ),
    );
  }

  /// Commission is owed on this order but has no rate. Tappable, because
  /// an empty state that offers the action fixing it beats one that only
  /// reports emptiness (same shape as the dashboard's Expenses tile).
  Widget _unpricedCommissionRow(FlutterFlowTheme theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Commission',
                    style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: theme.secondaryText)),
                Text(kCommissionUnpricedBody,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: theme.warning)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(kCommissionUnpricedLabel,
              style: GoogleFonts.interTight(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: theme.warning)),
        ],
      ),
    );
  }

  /// Net profit cannot be stated while a cost is unknown. Showing the
  /// figure minus nothing would overstate it by the entire commission.
  Widget _unavailableNetProfitRow(FlutterFlowTheme theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Net Profit',
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: theme.secondaryText)),
                Text('Set the commission % to see profit',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: theme.secondaryText)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text('Unavailable',
              style: GoogleFonts.interTight(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: theme.warning)),
        ],
      ),
    );
  }
}
