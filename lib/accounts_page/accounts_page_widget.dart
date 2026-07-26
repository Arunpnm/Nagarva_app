import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
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

class _AccountsPageWidgetState extends State<AccountsPageWidget> {
  late AccountsPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  static final _currency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  static final _dayFormat = DateFormat('MMM d, yyyy');
  static final _dayShort = DateFormat('EEE, MMM d');

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

      for (final o in dayOrders) {
        final amount = o.amount ?? 0;
        // orderQuote(o) in the reference app: amount minus extra charges.
        // extra_charges isn't modeled as a column here yet, so quote ==
        // amount until that field is ported (tracked separately).
        final orderQuote = amount;
        final advancePaid = o.advancePaid ?? 0;
        final bookingAdvance = amount; // no dedicated booking_advance column yet

        revenue += amount;
        quote += orderQuote;
        collections += advancePaid;
        advance += [bookingAdvance, advancePaid]
            .reduce((a, b) => a < b ? a : b)
            .clamp(0, double.infinity);
        overCollected += (advancePaid - amount).clamp(0, double.infinity);
        pending += (amount - advancePaid).clamp(0, double.infinity);

        salary += orderStaff
            .where((os) => os.orderId == o.id)
            .fold(0.0, (s, os) => s + (os.salaryAmount ?? 0));

        // This app stores the porter commission % directly per order
        // (`is_porter` + `porter_commission_pct`, picked 16/19 on
        // NewOrderPage) rather than deriving it from a local/outstation
        // order_type like the reference web app does — this app has no
        // local/outstation field at all. Default to 16% (the reference
        // app's "local" rate) if a porter order is missing the pct for
        // any reason.
        final isPorter = o.isPorter ?? (o.orderSource == 'porter');
        if (isPorter) {
          final pct = (o.porterCommissionPct ?? 16) / 100;
          porterCommission += (amount * pct).roundToDouble();
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
                  _detailLine(context, 'Porter commission',
                      row.porterCommission, true),
                  if (row.overCollected > 0)
                    _detailLine(
                        context, 'Over-collected (unexplained)',
                        row.overCollected, false),
                  const Divider(height: 24),
                  _detailLine(context, 'Net profit/loss', row.profitLoss,
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

  Widget _detailLine(BuildContext context, String label, double value,
      bool isExpense,
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
            'Accounts',
            style: FlutterFlowTheme.of(context).titleLarge.override(
                  font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                  fontSize: 22.0,
                  fontWeight: FontWeight.w600,
                ),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.edit_calendar_outlined,
                  color: FlutterFlowTheme.of(context).primaryText),
              tooltip: 'Edit opening balance',
              onPressed: _editOpeningBalance,
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
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color:
                                    FlutterFlowTheme.of(context).secondaryBackground,
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Current Balance',
                                      style: FlutterFlowTheme.of(context)
                                          .titleMedium,
                                    ),
                                    Text(
                                      _currency.format(_model.currentBalance),
                                      style: FlutterFlowTheme.of(context)
                                          .titleLarge
                                          .override(
                                              font: GoogleFonts.interTight(
                                                  fontWeight: FontWeight.w600),
                                              color: FlutterFlowTheme.of(context)
                                                  .primary),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                    child: _summaryChip(
                                        context,
                                        'Revenue',
                                        _model.periodRevenue,
                                        FlutterFlowTheme.of(context).primary)),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: _summaryChip(
                                        context,
                                        'Expenses',
                                        _model.periodExpenses,
                                        FlutterFlowTheme.of(context).error)),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: _summaryChip(
                                        context,
                                        'Net',
                                        _model.periodProfit,
                                        _model.periodProfit >= 0
                                            ? FlutterFlowTheme.of(context)
                                                .primary
                                            : FlutterFlowTheme.of(context)
                                                .error)),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Daily Register',
                              style: FlutterFlowTheme.of(context).titleMedium,
                            ),
                            const SizedBox(height: 8),
                            if (_model.dailyRows.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24),
                                child: Text(
                                  'No orders yet — the register fills in once orders have a move date.',
                                  style: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .override(
                                          font: GoogleFonts.inter(),
                                          color: FlutterFlowTheme.of(context)
                                              .secondaryText),
                                ),
                              )
                            else
                              ...(_model.dailyRows.map((row) => GestureDetector(
                                    onTap: () => _showDayDetail(row),
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryBackground,
                                        borderRadius:
                                            BorderRadius.circular(10.0),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(14.0),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _dayShort.format(row.date),
                                                  style: FlutterFlowTheme.of(
                                                          context)
                                                      .bodyMedium
                                                      .override(
                                                          font: GoogleFonts
                                                              .inter(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600)),
                                                ),
                                                Text(
                                                  '${row.dayOrders.length} order${row.dayOrders.length == 1 ? '' : 's'} · Rev ${_currency.format(row.revenue)}',
                                                  style: FlutterFlowTheme.of(
                                                          context)
                                                      .bodySmall
                                                      .override(
                                                          font: GoogleFonts
                                                              .inter(),
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .secondaryText),
                                                ),
                                              ],
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  '${row.profitLoss >= 0 ? '+' : '-'}${_currency.format(row.profitLoss.abs())}',
                                                  style: FlutterFlowTheme.of(
                                                          context)
                                                      .titleSmall
                                                      .override(
                                                        font: GoogleFonts
                                                            .interTight(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600),
                                                        color: row.profitLoss >=
                                                                0
                                                            ? FlutterFlowTheme
                                                                    .of(context)
                                                                .primary
                                                            : FlutterFlowTheme
                                                                    .of(context)
                                                                .error,
                                                      ),
                                                ),
                                                Text(
                                                  'Bal ${_currency.format(row.runningBalance)}',
                                                  style: FlutterFlowTheme.of(
                                                          context)
                                                      .bodySmall
                                                      .override(
                                                          font: GoogleFonts
                                                              .inter(),
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .secondaryText),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ))),
                          ],
                        ),
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _summaryChip(
      BuildContext context, String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(label,
              style: FlutterFlowTheme.of(context).bodySmall.override(
                  font: GoogleFonts.inter(),
                  color: FlutterFlowTheme.of(context).secondaryText)),
          const SizedBox(height: 2),
          Text(
            _currency.format(value.abs()),
            style: FlutterFlowTheme.of(context)
                .titleSmall
                .override(
                    font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                    color: color),
          ),
        ],
      ),
    );
  }
}
