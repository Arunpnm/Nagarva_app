import '/backend/commission_pricing.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'accounts_page_model.dart';
export 'accounts_page_model.dart';

/// Daily Accounts Register — a read-only, per-day cash-flow ledger computed
/// from `orders` + `expenses` (+ `order_staff` for labour salary), with a
/// running balance seeded from an editable opening balance.
///
/// This replaces the fully-hardcoded "bank accounts" mockup that used to
/// live here. Ported from reference/APC Web App JSX/App.jsx's AccountsPage
/// (lines ~8522-8970) — see CLAUDE.md's 13 Jul 2026 changelog entry for
/// why: the "bank_accounts / five-column split" idea that page used to be
/// blocked on doesn't exist anywhere in the reference app; this daily
/// register is the real, already-shipped feature.
class AccountsPageWidget extends StatefulWidget {
  const AccountsPageWidget({super.key});

  static String routeName = 'AccountsPage';
  static String routePath = '/accounts';

  @override
  State<AccountsPageWidget> createState() => _AccountsPageWidgetState();
}

class _AccountsPageWidgetState extends State<AccountsPageWidget>
    with RefreshOnPopMixin<AccountsPageWidget> {
  late AccountsPageModel _model;

  // Refresh-after-write fix (parity brief Part 1): re-run the load when a
  // pushed route (e.g. an opening-balance edit) is popped.
  @override
  void onPageRefresh() => _loadData();

  final scaffoldKey = GlobalKey<ScaffoldState>();

  static final _currency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  static final _dayFormat = DateFormat('MMM d, yyyy');

  // LEAK_AUDIT.md leak #10 (Stage 1 fix): this used to be
  // 'accounts_opening_balance:<orgId>' — namespaced by string content
  // instead of the org_id column. Now that every read/write below filters
  // on org_id, the key can be the same simple string for every org. See
  // migration in supabase/phase1_rename_settings_keys.sql.
  static const _openingBalanceKey = 'accounts_opening_balance';

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => AccountsPageModel());

    SchedulerBinding.instance.addPostFrameCallback((_) => _loadData());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        OrdersTable().queryRows(
          queryFn: (q) => OrgScope.read(q),
        ),
        ExpensesTable().queryRows(
          queryFn: (q) => OrgScope.read(q),
        ),
        OrderStaffTable().queryRows(
          queryFn: (q) => OrgScope.read(q),
        ),
        // LEAK_AUDIT.md leak #10 (Stage 1 fix): matched only on key before.
        SettingsTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('key', _openingBalanceKey),
        ),
      ]);
      final orders = results[0].cast<OrdersRow>();
      final expenses = results[1].cast<ExpensesRow>();
      final orderStaff = results[2].cast<OrderStaffRow>();
      final settingsRows = results[3].cast<SettingsRow>();

      _model.openingBalance = settingsRows.isNotEmpty
          ? (double.tryParse(settingsRows.first.value ?? '0') ?? 0.0)
          : 0.0;
      _model.dailyRows = _computeDailyRows(orders, expenses, orderStaff);
      _model.isLoading = false;
      _model.loadError = null;
    } catch (e) {
      _model.isLoading = false;
      _model.loadError = e.toString();
    }
    safeSetState(() {});
  }

  /// Mirrors apc_webapp App.jsx AccountsPage's `dailyRows` computation
  /// (lines ~8568-8610) — see accounts_page_model.dart's DailyAccountRow
  /// doc comment for the exact formula each field follows.
  List<DailyAccountRow> _computeDailyRows(
    List<OrdersRow> orders,
    List<ExpensesRow> expenses,
    List<OrderStaffRow> orderStaff,
  ) {
    final byDate = <DateTime, List<OrdersRow>>{};
    for (final o in orders) {
      final move = o.moveDateOrNull;
      if (move == null) continue;
      final d = DateTime(move.year, move.month, move.day);
      byDate.putIfAbsent(d, () => []).add(o);
    }

    final rows = <DailyAccountRow>[];
    for (final entry in byDate.entries) {
      final date = entry.key;
      final dayOrders = entry.value;
      final dayOrderIds = dayOrders.map((o) => o.id).toSet();

      double revenue = 0, quote = 0, collections = 0, advance = 0;
      double overCollected = 0, pending = 0, salary = 0, porterCommission = 0;
      final unpricedCommission = <String>[];

      for (final o in dayOrders) {
        // GST IS NOT REVENUE. (Arun's standing rule, 2 Sept 2026.)
        //
        // This register read `orders.amount`, the GST-INCLUSIVE total, so
        // the same Coimbatore order showed Rs35,990 here, Rs37,640 on the
        // order P&L and Rs37.6K on the dashboard - three screens, three
        // revenue figures for one job. GST collected is held for the
        // government and remitted; counting it inflates revenue, profit
        // and the running cash balance together.
        //
        // Same basis as OrderPnlSection._revenueBase: prefer the stored
        // GST-exclusive subtotal, else total minus the tax, so rows
        // written before subtotal was stored still exclude it. An order
        // with no GST is unchanged.
        final gross = o.amount ?? 0;
        final subtotal = o.quoteSubtotal ?? 0;
        final amount =
            subtotal != 0 ? subtotal : gross - (o.quoteGstAmount ?? 0);
        // orderQuote(o) in the reference app: amount minus extra charges.
        // extra_charges isn't modeled as a column here yet, so quote ==
        // amount until that field is ported (tracked separately).
        // Follows revenue's tax-exclusive basis, so the Extra column
        // (revenue - quote) stays 0 rather than becoming the GST.
        final orderQuote = amount;
        final advancePaid = o.advancePaid ?? 0;
        // Collections are cash actually received, which includes the GST
        // the customer paid - so this stays on the GROSS figure. Only
        // revenue excludes tax; the money in the drawer does not.
        final bookingAdvance =
            gross; // no dedicated booking_advance column yet

        revenue += amount;
        quote += orderQuote;
        collections += advancePaid;
        advance += [bookingAdvance, advancePaid]
            .reduce((a, b) => a < b ? a : b)
            .clamp(0, double.infinity);
        // Both compare against GROSS, not the ex-GST figure. What the
        // customer still owes, and any over-payment, are cash positions -
        // the customer pays the tax too. Only `revenue` and `quote` are
        // tax-exclusive; every cash column on this register is gross, or
        // Pending would understate the bill by the GST on it.
        overCollected += (advancePaid - gross).clamp(0, double.infinity);
        pending += (gross - advancePaid).clamp(0, double.infinity);

        salary += orderStaff
            .where((os) => os.orderId == o.id)
            .fold(0.0, (s, os) => s + (os.salaryAmount ?? 0));

        // Commission is the rate SNAPSHOTTED on the order at order time
        // (`orders.commission_pct`, from the lead source it came from).
        // This used to read `?? 16` — APC's own porter rate — so an order
        // nobody had priced silently carried a cost into this register
        // and into the day's profit/loss. A day that contains an unpriced
        // order now reports commission as a floor and says so; see
        // /backend/commission_pricing.dart.
        final comm = commissionAmount(order: o, revenueBase: amount);
        if (comm == null) {
          unpricedCommission.add(o.id ?? '—');
        } else {
          porterCommission += comm;
        }
      }

      final orderExpenses = expenses
          .where((e) => e.orderId != null && dayOrderIds.contains(e.orderId))
          .fold(0.0, (s, e) => s + (e.amount ?? 0));
      final otherExpenses = expenses
          .where((e) =>
              e.orderId == null &&
              e.expenseDate != null &&
              _sameDay(e.expenseDate!, date))
          .fold(0.0, (s, e) => s + (e.amount ?? 0));

      rows.add(DailyAccountRow(
        date: date,
        dayOrders: dayOrders,
        revenue: revenue,
        quote: quote,
        collections: collections,
        advance: advance,
        overCollected: overCollected,
        pending: pending,
        salary: salary,
        orderExpenses: orderExpenses,
        otherExpenses: otherExpenses,
        porterCommission: porterCommission,
        unpricedCommissionOrderIds: unpricedCommission,
      ));
    }

    // Running balance walks chronologically (oldest -> newest) from the
    // opening balance, matching the reference app's `balance += profitLoss`.
    rows.sort((a, b) => a.date.compareTo(b.date));
    var running = _model.openingBalance;
    for (final r in rows) {
      running += r.profitLoss;
      r.runningBalance = running;
    }

    // Display newest-first.
    return rows.reversed.toList();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _editOpeningBalance() async {
    final controller = TextEditingController(
      text: _model.openingBalance.toStringAsFixed(0),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Opening Balance'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(prefixText: '₹ '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text) ?? 0),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;

    // `settings` now has a real composite PK on (org_id, key) (added
    // 2026-07-14), so a proper upsert replaces the old "insert, catch the
    // conflict, fall back to a key-only update" workaround.
    await SettingsTable().upsert(
      {
        'key': _openingBalanceKey,
        ...OrgScope.stamp(),
        'value': result.toString(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'org_id,key',
    );

    _model.openingBalance = result;
    var running = result;
    final chronological = _model.dailyRows.reversed.toList();
    for (final r in chronological) {
      running += r.profitLoss;
      r.runningBalance = running;
    }
    _model.dailyRows = chronological.reversed.toList();
    safeSetState(() {});
  }

  void _showDayDetail(DailyAccountRow row) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: ListView(
                controller: scrollController,
                children: [
                  Text(
                    _dayFormat.format(row.date),
                    style: FlutterFlowTheme.of(context).titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Net ${row.profitLoss >= 0 ? 'profit' : 'loss'}: ${_currency.format(row.profitLoss.abs())}',
                    style: FlutterFlowTheme.of(context).bodyMedium.override(
                          font: GoogleFonts.inter(),
                          color: row.profitLoss >= 0
                              ? FlutterFlowTheme.of(context).primary
                              : FlutterFlowTheme.of(context).error,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Text('Orders (${row.dayOrders.length})',
                      style: FlutterFlowTheme.of(context).titleSmall),
                  const SizedBox(height: 8),
                  ...row.dayOrders.map((o) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: FlutterFlowTheme.of(context).primaryBackground,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.customer,
                                style: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .override(
                                        font: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600))),
                            const SizedBox(height: 4),
                            Text(
                              'Value ${_currency.format(o.amount ?? 0)} · Collected ${_currency.format(o.advancePaid ?? 0)} · Pending ${_currency.format(((o.amount ?? 0) - (o.advancePaid ?? 0)).clamp(0, double.infinity))}',
                              style: FlutterFlowTheme.of(context)
                                  .bodySmall
                                  .override(
                                      font: GoogleFonts.inter(),
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryText),
                            ),
                          ],
                        ),
                      )),
                  const Divider(height: 24),
                  _detailLine(context, 'Revenue', row.revenue, false),
                  _detailLine(context, 'Staff salary', row.salary, true),
                  _detailLine(
                      context, 'Order expenses', row.orderExpenses, true),
                  _detailLine(
                      context, 'Other expenses', row.otherExpenses, true),
                  _detailLine(
                      context, 'Commission', row.porterCommission, true),
                  // Says which orders were left out, not just that some
                  // were: a count alone tells the vendor a number is
                  // wrong without telling them where to go and fix it.
                  if (row.hasUnpricedCommission)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 6),
                      child: Text(
                        '${commissionIncompleteNote(row.unpricedCommissionOrderIds.length)}'
                        ' (${row.unpricedCommissionOrderIds.join(', ')})',
                        style: TextStyle(
                          fontSize: 11,
                          color: FlutterFlowTheme.of(context).warning,
                        ),
                      ),
                    ),
                  if (row.overCollected > 0)
                    _detailLine(context, 'Over-collected (unexplained)',
                        row.overCollected, false),
                  const Divider(height: 24),
                  _detailLine(
                      context,
                      row.hasUnpricedCommission
                          ? 'Net profit/loss (at least)'
                          : 'Net profit/loss',
                      row.profitLoss,
                      false,
                      bold: true),
                  _detailLine(
                      context, 'Running balance', row.runningBalance, false,
                      bold: true),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailLine(
      BuildContext context, String label, double value, bool isExpense,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: bold
                  ? FlutterFlowTheme.of(context).titleSmall
                  : FlutterFlowTheme.of(context).bodyMedium.override(
                      font: GoogleFonts.inter(),
                      color: FlutterFlowTheme.of(context).secondaryText)),
          Text(
            '${isExpense ? '-' : ''}${_currency.format(value.abs())}',
            style: (bold
                    ? FlutterFlowTheme.of(context).titleSmall
                    : FlutterFlowTheme.of(context).bodyMedium)
                .override(
              font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
              color: isExpense
                  ? FlutterFlowTheme.of(context).error
                  : (value < 0
                      ? FlutterFlowTheme.of(context).error
                      : FlutterFlowTheme.of(context).primary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          automaticallyImplyLeading: true,
          title: Text(
            'Daily Accounts Register',
            style: FlutterFlowTheme.of(context).titleLarge.override(
                  font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                  fontSize: 22.0,
                  fontWeight: FontWeight.w600,
                ),
          ),
          actions: [
            TextButton.icon(
              onPressed: _model.dailyRows.isEmpty ? null : _copyCsv,
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('CSV'),
            ),
          ],
          centerTitle: true,
          elevation: 0.0,
        ),
        body: SafeArea(
          top: true,
          child: _model.isLoading
              ? const Center(child: CircularProgressIndicator())
              : _model.loadError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Could not load accounts data:\n${_model.loadError}',
                          textAlign: TextAlign.center,
                          style: FlutterFlowTheme.of(context).bodyMedium,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: ListView(
                          children: [
                            _openingBalanceBar(context),
                            const SizedBox(height: 12),
                            _summaryStrip(context),
                            const SizedBox(height: 16),
                            if (_model.dailyRows.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 24),
                                child: Text(
                                  'No orders yet - the register fills in once orders have a move date.',
                                  style: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .override(
                                          font: GoogleFonts.inter(),
                                          color: FlutterFlowTheme.of(context)
                                              .secondaryText),
                                ),
                              )
                            else
                              _registerTable(context),
                          ],
                        ),
                      ),
                    ),
        ),
      ),
    );
  }

  /// Opening balance strip.
  ///
  /// The running Cash Bal column is meaningless without it - it is the
  /// number the whole register walks forward from - so it is stated at
  /// the top rather than hidden behind the AppBar action it used to be.
  Widget _openingBalanceBar(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Row(
      children: [
        Text('Opening Balance:',
            style: GoogleFonts.inter(
                fontSize: 12, color: theme.secondaryText)),
        const SizedBox(width: 8),
        InkWell(
          onTap: _editOpeningBalance,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: theme.secondaryBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_currency.format(_model.openingBalance),
                style: GoogleFonts.interTight(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: theme.primaryText)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text('starting cash before this period',
              style: GoogleFonts.inter(
                  fontSize: 11, color: theme.secondaryText)),
        ),
      ],
    );
  }

  /// The seven period totals, in the same order as the reference register.
  ///
  /// EXPENSES is order + other expenses ONLY. Labour and commission are
  /// their own tiles because a mover reads them separately - and folding
  /// them in would make the tile disagree with the Total Exp column,
  /// which is the sum of all four.
  Widget _summaryStrip(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final rows = _model.dailyRows;
    double sum(double Function(DailyAccountRow) f) =>
        rows.fold(0.0, (a, r) => a + f(r));

    final tiles = <(String, double, Color)>[
      ('REVENUE', sum((r) => r.revenue), theme.primary),
      ('COLLECTED', sum((r) => r.collections), theme.success),
      ('LABOUR', sum((r) => r.salary), theme.secondaryText),
      ('EXPENSES', sum((r) => r.orderExpenses + r.otherExpenses), theme.error),
      ('COMMISSION', sum((r) => r.porterCommission), theme.error),
      ('NET P&L', _model.periodProfit,
          _model.periodProfit < 0 ? theme.error : theme.success),
      ('CLOSING BAL', _model.currentBalance,
          _model.currentBalance < 0 ? theme.error : theme.primaryText),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (label, value, colour) in tiles)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.secondaryBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_currency.format(value),
                      style: GoogleFonts.interTight(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colour)),
                  const SizedBox(height: 2),
                  Text(label,
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          letterSpacing: 0.6,
                          color: theme.secondaryText)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The register itself: one row per day, every component in its own
  /// column, and a TOTAL row.
  ///
  /// Horizontally scrollable rather than reflowed, because the columns
  /// only mean anything side by side - Quote, Advance, Bal Coll. and
  /// Pending have to line up for a vendor to check the day's cash. The
  /// page body must never scroll sideways, so the scroll lives here.
  Widget _registerTable(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final rows = _model.dailyRows;
    double sum(double Function(DailyAccountRow) f) =>
        rows.fold(0.0, (a, r) => a + f(r));

    return Container(
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          // Rows open the day detail; they are not selectable, and
          // onSelectChanged alone makes DataTable add a checkbox column.
          showCheckboxColumn: false,
          headingRowHeight: 42,
          dataRowMinHeight: 48,
          dataRowMaxHeight: 66,
          horizontalMargin: 14,
          // Roomy on purpose. At 18/11pt the figures crowded each other
          // and read as one smear of digits — Arun, 3 Sept 2026: "the
          // numbers values are not visible clearly its shrinking". A
          // register is only useful if every figure can be read at a
          // glance, so the table is allowed to be wider and scroll.
          columnSpacing: 26,
          headingTextStyle: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.secondaryText),
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Orders'), numeric: true),
            DataColumn(label: Text('Quote'), numeric: true),
            DataColumn(label: Text('Advance'), numeric: true),
            DataColumn(label: Text('Bal Coll.'), numeric: true),
            DataColumn(label: Text('Extra'), numeric: true),
            DataColumn(label: Text('Pending'), numeric: true),
            DataColumn(label: Text('Salary'), numeric: true),
            DataColumn(label: Text('Ord Exp'), numeric: true),
            DataColumn(label: Text('Oth Exp'), numeric: true),
            DataColumn(label: Text('Commission'), numeric: true),
            DataColumn(label: Text('Total Exp'), numeric: true),
            DataColumn(label: Text('P / L'), numeric: true),
            DataColumn(label: Text('Cash Bal'), numeric: true),
          ],
          rows: [
            for (final r in rows) _dataRow(context, r),
            // TOTAL. Cash Bal is the CLOSING balance, not a sum of the
            // column - adding running balances together would be
            // meaningless, and a vendor would still read it as money.
            DataRow(
              color: WidgetStatePropertyAll(
                  theme.primary.withValues(alpha: 0.06)),
              cells: [
                DataCell(Text('TOTAL - ${rows.length} day${rows.length == 1 ? '' : 's'}',
                    style: GoogleFonts.interTight(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: theme.primaryText))),
                DataCell(_num(context, sum((r) => r.dayOrders.length.toDouble()),
                    plain: true)),
                DataCell(_num(context, sum((r) => r.quote))),
                DataCell(_num(context, sum((r) => r.advance))),
                DataCell(_num(context,
                    sum((r) => (r.collections - r.advance).clamp(0, double.infinity)))),
                DataCell(_num(context, sum((r) => r.revenue - r.quote))),
                DataCell(_num(context, sum((r) => r.pending))),
                DataCell(_num(context, -sum((r) => r.salary))),
                DataCell(_num(context, -sum((r) => r.orderExpenses))),
                DataCell(_num(context, -sum((r) => r.otherExpenses))),
                DataCell(_num(context, -sum((r) => r.porterCommission))),
                DataCell(_num(context, -sum((r) => r.totalExpenses))),
                DataCell(_num(context, _model.periodProfit, bold: true)),
                DataCell(_num(context, _model.currentBalance, bold: true)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  DataRow _dataRow(BuildContext context, DailyAccountRow r) {
    final theme = FlutterFlowTheme.of(context);
    final names = r.dayOrders
        .map((o) => o.customer.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    final balColl = (r.collections - r.advance).clamp(0, double.infinity);

    return DataRow(
      onSelectChanged: (_) => _showDayDetail(r),
      cells: [
        DataCell(Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('EEE, d MMM').format(r.date),
                style: GoogleFonts.interTight(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: theme.primaryText)),
            if (names.isNotEmpty)
              Text(names.join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 10, color: theme.secondaryText)),
          ],
        )),
        DataCell(_num(context, r.dayOrders.length.toDouble(), plain: true)),
        DataCell(_num(context, r.quote)),
        DataCell(_num(context, r.advance)),
        DataCell(_num(context, balColl.toDouble())),
        DataCell(_num(context, r.revenue - r.quote)),
        DataCell(_num(context, r.pending)),
        DataCell(_num(context, -r.salary)),
        DataCell(_num(context, -r.orderExpenses)),
        DataCell(_num(context, -r.otherExpenses)),
        // Commission is a FLOOR when some order on this day has no rate:
        // the day is marked rather than presented as settled, since the
        // missing figure is a cost and real profit can only be lower.
        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
          if (r.hasUnpricedCommission)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message:
                    'At least one order has no commission rate set, so this '
                    'is a floor. Profit can only be lower.',
                child: Icon(Icons.warning_amber_rounded,
                    size: 13, color: theme.warning),
              ),
            ),
          _num(context, -r.porterCommission),
        ])),
        DataCell(_num(context, -r.totalExpenses)),
        DataCell(Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _num(context, r.profitLoss, bold: true),
            if (r.profitLoss < 0)
              Text('Loss',
                  style:
                      GoogleFonts.inter(fontSize: 9, color: theme.error)),
          ],
        )),
        DataCell(_num(context, r.runningBalance, bold: true)),
      ],
    );
  }

  /// A figure. Zero renders as an em dash rather than Rs0 so an empty
  /// column is visibly empty instead of looking like a real zero.
  Widget _num(BuildContext context, double v,
      {bool bold = false, bool plain = false}) {
    final theme = FlutterFlowTheme.of(context);
    if (v == 0) {
      return _cell(Text('-',
          style: GoogleFonts.inter(fontSize: 14, color: theme.secondaryText)));
    }
    if (plain) {
      return _cell(Text(v.toInt().toString(),
          maxLines: 1,
          softWrap: false,
          style: GoogleFonts.interTight(
              fontSize: 14,
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
              color: theme.primaryText)));
    }
    // Fixed minimum width per money cell.
    //
    // Without it DataTable sized the column to the HEADER ("Quote") and
    // clipped the figure to "Rs30,50" - a register that shows a wrong
    // number is worse than one that scrolls. A floor also makes the
    // columns line up down the page, which is how a register is read.
    return _cell(
      Text(_currency.format(v),
        maxLines: 1,
        softWrap: false,
        style: GoogleFonts.interTight(
          fontSize: 14,
          // Tabular figures so digits align vertically down the column —
          // the whole point of a register is scanning one column.
          fontFeatures: const [FontFeature.tabularFigures()],
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: v < 0 ? theme.error : theme.primaryText,
        )),
    );
  }

  /// Right-aligned cell with a minimum width, so no figure is ever
  /// clipped by a narrower heading.
  Widget _cell(Widget child) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 84),
        child: Align(alignment: Alignment.centerRight, child: child),
      );

  /// Copies the register as CSV.
  ///
  /// COPY, not download, and the button says so. This app has no file-save
  /// package on any platform (`printing` handles PDFs only, and adding a
  /// dependency would break the pinned-pubspec rule), so a "Download CSV"
  /// button would be an affordance that goes nowhere - the same trust
  /// damage as the dead share links. The clipboard genuinely works on
  /// web and Android and pastes straight into Sheets or Excel.
  Future<void> _copyCsv() async {
    final b = StringBuffer()
      ..writeln('Date,Orders,Quote,Advance,Bal Collected,Extra,Pending,'
          'Salary,Order Expenses,Other Expenses,Commission,Total Expenses,'
          'Profit/Loss,Cash Balance');
    String n(double v) => v.toStringAsFixed(2);
    for (final r in _model.dailyRows.reversed) {
      b.writeln([
        DateFormat('yyyy-MM-dd').format(r.date),
        r.dayOrders.length,
        n(r.quote),
        n(r.advance),
        n((r.collections - r.advance).clamp(0, double.infinity).toDouble()),
        n(r.revenue - r.quote),
        n(r.pending),
        n(r.salary),
        n(r.orderExpenses),
        n(r.otherExpenses),
        n(r.porterCommission),
        n(r.totalExpenses),
        n(r.profitLoss),
        n(r.runningBalance),
      ].join(','));
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Register copied as CSV - paste into Sheets or Excel.')));
    }
  }

}
