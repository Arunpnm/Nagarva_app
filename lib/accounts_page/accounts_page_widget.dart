import '/backend/commission_pricing.dart';
import '/backend/money_book.dart';
import '/backend/edge_function_errors.dart';
import '/backend/order_money.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/scheduler.dart';
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
        SettingsTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('key', 'porter_enabled'),
        ),
      ]);
      final porterRows = results[4].cast<SettingsRow>();
      _porterEnabled = porterRows.isNotEmpty &&
          (porterRows.first.value ?? '').toLowerCase() == 'true';
      // 4 Nov 2026 (BUG-051/052): every other place money is recorded,
      // for the shared MoneyBook the dashboard and P&L report also use.
      _extras = await MoneyExtras.load();
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
      _model.loadError = friendlyError(e);
    }
    safeSetState(() {});
  }

  /// Everything MoneyBook needs beyond orders/expenses/crew.
  MoneyExtras _extras = MoneyExtras();
  bool _porterEnabled = false;

  /// Mirrors apc_webapp App.jsx AccountsPage's `dailyRows` computation
  /// (lines ~8568-8610) — see accounts_page_model.dart's DailyAccountRow
  /// doc comment for the exact formula each field follows.
  List<DailyAccountRow> _computeDailyRows(
    List<OrdersRow> orders,
    List<ExpensesRow> expenses,
    List<OrderStaffRow> orderStaff,
  ) {
    DateTime day(DateTime d) {
      final l = d.toLocal();
      return DateTime(l.year, l.month, l.day);
    }

    final byDate = <DateTime, List<OrdersRow>>{};
    for (final o in orders) {
      if ((o.status ?? '').toLowerCase() == 'cancelled') continue;
      final move = o.moveDateOrNull;
      if (move == null) continue;
      byDate.putIfAbsent(day(move), () => []).add(o);
    }
    // A day with only office costs (rent, fuel, a vendor bill) is still a
    // row: its costs belong in the running balance (4 Nov 2026). Before,
    // only days with a move appeared and those costs vanished here while
    // the P&L report counted them.
    final days = <DateTime>{...byDate.keys};
    for (final e in expenses) {
      if (e.orderId != null) continue;
      final d = DateTime.tryParse(e.date ?? '') ?? e.expenseDate ?? e.createdAt;
      if (d != null) days.add(day(d));
    }
    for (final c in _extras.otherCosts) {
      if (c.date != null) days.add(day(c.date!));
    }
    for (final r in _extras.incentives) {
      final d = DateTime.tryParse('${r['entry_date']}');
      if (d != null) days.add(day(d));
    }

    final rows = <DailyAccountRow>[];
    for (final date in days) {
      final dayOrders = byDate[date] ?? const <OrdersRow>[];
      // Revenue, labour, costs and commission: the shared MoneyBook, so
      // this register, the dashboard and the P&L report agree.
      final m = MoneyBook.compute(
        orders: orders,
        expenses: expenses,
        orderStaff: orderStaff,
        extras: _extras,
        inPeriod: (d) => day(d) == date,
        porterEnabled: _porterEnabled,
      );
      const orderLinked = {'Order expenses', 'Field expenses', 'Materials'};
      double kinds(bool linked) => m.expensesByKind.entries
          .where((e) => orderLinked.contains(e.key) == linked)
          .fold(0.0, (s, e) => s + e.value);

      // Cash columns: what the customer owes includes GST billed; only
      // revenue is before GST.
      double quote = 0, collections = 0, advance = 0;
      double overCollected = 0, pending = 0;
      final unpriced = <String>[];
      for (final o in dayOrders) {
        final money =
            OrderMoney.from(o, _extras.addonsByOrder[o.id] ?? const []);
        final gross = money.total;
        quote += money.taxable;
        final received = o.paidTotal;
        collections += received;
        advance += [gross, received]
            .reduce((a, b) => a < b ? a : b)
            .clamp(0, double.infinity);
        overCollected += (received - gross).clamp(0, double.infinity);
        pending += (gross - received).clamp(0, double.infinity);
        if (_porterEnabled &&
            commissionAmount(order: o, revenueBase: money.base) == null) {
          unpriced.add(o.id ?? '—');
        }
      }

      rows.add(DailyAccountRow(
        date: date,
        dayOrders: dayOrders,
        revenue: m.revenue,
        quote: quote,
        collections: collections,
        advance: advance,
        overCollected: overCollected,
        pending: pending,
        salary: m.labour,
        orderExpenses: kinds(true),
        otherExpenses: kinds(false),
        porterCommission: m.commission,
        unpricedCommissionOrderIds: unpriced,
      ));
    }

    // Running balance walks chronologically (oldest -> newest) from the
    // opening balance by cash actually received minus spent. The reference
    // app adds profitLoss, which counts unpaid revenue as cash; this tile is
    // labelled "Cash now" next to Money in / Money out, so it must equal
    // opening + in - out (4 Nov 2026).
    rows.sort((a, b) => a.date.compareTo(b.date));
    var running = _model.openingBalance;
    for (final r in rows) {
      running += r.cashFlow;
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
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'org_id,key',
    );

    _model.openingBalance = result;
    var running = result;
    final chronological = _model.dailyRows.reversed.toList();
    for (final r in chronological) {
      running += r.cashFlow;
      r.runningBalance = running;
    }
    _model.dailyRows = chronological.reversed.toList();
    safeSetState(() {});
  }

  void _showDayDetail(DailyAccountRow row) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NgPalette.of(context).s1,
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
                    style: NgFonts.geist(fontSize: 20, fontWeight: FontWeight.w600, color: NgPalette.of(context).text),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Net ${row.profitLoss >= 0 ? 'profit' : 'loss'}: ${_currency.format(row.profitLoss.abs())}',
                    style: NgFonts.geist(fontSize: 14, 
                          color: row.profitLoss >= 0
                              ? NgPalette.of(context).acc
                              : NgPalette.of(context).red,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Text('Orders (${row.dayOrders.length})',
                      style: NgFonts.geist(fontSize: 15, fontWeight: FontWeight.w600, color: NgPalette.of(context).text)),
                  const SizedBox(height: 8),
                  ...row.dayOrders.map((o) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: NgPalette.of(context).bg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.customer,
                                style: NgFonts.geist(fontSize: 14, 
                                        fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(
                              'Value ${_currency.format(o.amount ?? 0)} · Collected ${_currency.format(o.paidTotal)} · Pending ${_currency.format(((o.amount ?? 0) - o.paidTotal).clamp(0, double.infinity))}',
                              style: NgFonts.geist(fontSize: 12.5, 
                                      color: NgPalette.of(context).mute),
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
                          color: NgPalette.of(context).amber,
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
                  ? NgFonts.geist(fontSize: 15, fontWeight: FontWeight.w600, color: NgPalette.of(context).text)
                  : NgFonts.geist(fontSize: 14, 
                      color: NgPalette.of(context).mute)),
          Text(
            '${isExpense ? '-' : ''}${_currency.format(value.abs())}',
            style: (bold
                    ? NgFonts.geist(fontSize: 15, fontWeight: FontWeight.w600, color: NgPalette.of(context).text)
                    : NgFonts.geist(fontSize: 14, color: NgPalette.of(context).text))
                .copyWith(
              fontWeight: FontWeight.w600, color: isExpense
                  ? NgPalette.of(context).red
                  : (value < 0
                      ? NgPalette.of(context).red
                      : NgPalette.of(context).acc),
            ),
          ),
        ],
      ),
    );
  }

  /// 0 = Overview, 1 = Days (the register).
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: c.bg,
      appBar: NgTopBar(onRefresh: _loadData),
      body: _model.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _model.loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load accounts data:\n${_model.loadError}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      NgModuleHeader('Accounts', actions: [
                        NgHeaderButtonBox(
                          tooltip: 'Copy as CSV',
                          icon: Icons.download_outlined,
                          onTap: _model.dailyRows.isEmpty ? null : _copyCsv,
                        ),
                      ]),
                      const SizedBox(height: 14),
                      NgSegmented(
                        labels: const ['Overview', 'Days'],
                        selected: _tab,
                        onSelect: (i) => safeSetState(() => _tab = i),
                      ),
                      const SizedBox(height: 14),
                      _openingBalanceBar(context),
                      const SizedBox(height: 14),
                      if (_model.dailyRows.isEmpty)
                        NgCard(
                          child: Text(
                            'No orders yet. The register fills in once orders have a move date.',
                            style:
                                NgFonts.geist(fontSize: 13.5, color: c.mute),
                          ),
                        )
                      else if (_tab == 0)
                        ..._overview(context)
                      else
                        _registerTable(context),
                    ],
                  ),
                ),
    );
  }

  /// Overview: net P&L, cash now, money in and out, a per-day chart, and
  /// the totals the register adds up.
  List<Widget> _overview(BuildContext context) {
    final c = NgPalette.of(context);
    final rows = _model.dailyRows;
    double sum(double Function(DailyAccountRow) f) =>
        rows.fold(0.0, (a, r) => a + f(r));
    final moneyIn = sum((r) => r.collections);
    final moneyOut = sum((r) => r.totalExpenses);
    Widget tile(String label, String value, Color color) => Expanded(
          child: NgCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: NgFonts.mono(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          color: color)),
                ),
              ],
            ),
          ),
        );
    final p = _model.periodProfit;
    final recent = rows.length > 10 ? rows.sublist(rows.length - 10) : rows;
    final peak = recent.fold<double>(
        1, (m, r) => [m, r.collections, r.totalExpenses].reduce((a, b) => a > b ? a : b));
    return [
      Row(children: [
        tile('Net P&L', '${p >= 0 ? '+' : '-'}${functions.inrFull(p.abs())}',
            p < 0 ? c.red : c.green),
        const SizedBox(width: 8),
        tile('Cash now', functions.inrFull(_model.currentBalance),
            _model.currentBalance < 0 ? c.red : c.text),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        tile('Money in', functions.inrFull(moneyIn), c.text),
        const SizedBox(width: 8),
        tile('Money out', functions.inrFull(moneyOut), c.text),
      ]),
      const SizedBox(height: 14),
      NgCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('In vs out per day',
                    style: NgFonts.geist(fontSize: 13, color: c.mute)),
              ),
              Container(width: 8, height: 8, color: c.green),
              const SizedBox(width: 4),
              Text('Money in', style: NgFonts.geist(fontSize: 11.5, color: c.mute)),
              const SizedBox(width: 10),
              Container(width: 8, height: 8, color: c.red),
              const SizedBox(width: 4),
              Text('Money out', style: NgFonts.geist(fontSize: 11.5, color: c.mute)),
            ]),
            const SizedBox(height: 14),
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final r in recent)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                  width: 7,
                                  height: 92 * r.collections / peak + 1,
                                  color: c.green),
                              const SizedBox(width: 2),
                              Container(
                                  width: 7,
                                  height: 92 * r.totalExpenses / peak + 1,
                                  color: c.red),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('${r.date.day}',
                              style: NgFonts.geist(
                                  fontSize: 10.5, color: c.mute)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      NgCardList(children: [
        for (final (label, value) in [
          ('Revenue', sum((r) => r.revenue)),
          ('Collected', moneyIn),
          ('Labour', sum((r) => r.salary)),
          ('Expenses', sum((r) => r.orderExpenses + r.otherExpenses)),
          ('Commission', sum((r) => r.porterCommission)),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Expanded(
                child: Text(label,
                    style: NgFonts.geist(fontSize: 14, color: c.text)),
              ),
              Text(functions.inrFull(value),
                  style: NgFonts.mono(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.text)),
            ]),
          ),
      ]),
    ];
  }

  /// Opening balance strip.
  ///
  /// The running Cash Bal column is meaningless without it - it is the
  /// number the whole register walks forward from - so it is stated at
  /// the top rather than hidden behind the AppBar action it used to be.
  Widget _openingBalanceBar(BuildContext context) {
    final ng = NgPalette.of(context);
    return Row(
      children: [
        Text('Opening Balance:',
            style: NgFonts.geist(
                fontSize: 12, color: ng.mute)),
        const SizedBox(width: 8),
        InkWell(
          onTap: _editOpeningBalance,
          borderRadius: BorderRadius.circular(8),
          child: NgCard(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(_currency.format(_model.openingBalance),
                style: NgFonts.geist(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ng.text)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text('starting cash before this period',
              style: NgFonts.geist(
                  fontSize: 11, color: ng.mute)),
        ),
      ],
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
    final ng = NgPalette.of(context);
    final rows = _model.dailyRows;
    double sum(double Function(DailyAccountRow) f) =>
        rows.fold(0.0, (a, r) => a + f(r));

    return Container(
      decoration: BoxDecoration(
        color: ng.s1,
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
          headingTextStyle: NgFonts.geist(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ng.mute),
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
                  ng.acc.withValues(alpha: 0.06)),
              cells: [
                DataCell(Text('TOTAL - ${rows.length} day${rows.length == 1 ? '' : 's'}',
                    style: NgFonts.geist(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: ng.text))),
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
    final ng = NgPalette.of(context);
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
                style: NgFonts.geist(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ng.text)),
            if (names.isNotEmpty)
              Text(names.join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NgFonts.geist(
                      fontSize: 10, color: ng.mute)),
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
                    size: 13, color: ng.amber),
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
                      NgFonts.geist(fontSize: 9, color: ng.red)),
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
    final ng = NgPalette.of(context);
    if (v == 0) {
      return _cell(Text('-',
          style: NgFonts.geist(fontSize: 14, color: ng.mute)));
    }
    if (plain) {
      return _cell(Text(v.toInt().toString(),
          maxLines: 1,
          softWrap: false,
          style: NgFonts.geist(
              fontSize: 14,
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
              color: ng.text)));
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
        style: NgFonts.geist(
          fontSize: 14,
          // Tabular figures so digits align vertically down the column —
          // the whole point of a register is scanning one column.
          fontFeatures: const [FontFeature.tabularFigures()],
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: v < 0 ? ng.red : ng.text,
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
