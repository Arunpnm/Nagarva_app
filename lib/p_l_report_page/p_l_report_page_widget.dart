import '/backend/commission_pricing.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/margin_availability.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'p_l_report_page_model.dart';
export 'p_l_report_page_model.dart';

/// Profit and Loss report for the current org.
///
/// Ported from reference/APC Web App JSX/App.jsx's PLReport component
/// (lines ~6350-6495). Formulas:
///   grossProfit = revenue - labour
///   netProfit   = grossProfit - orderExpenses - otherExpenses - porterCommission
///   margin      = netProfit / revenue * 100
/// Porter commission uses the same 16% local / 19% outstation formula as
/// AccountsPage. Branch P&L groups the same calc over the fixed BRANCHES
/// list; lead-source analytics reads `leads.source`/`leads.status`.
class PLReportPageWidget extends StatefulWidget {
  const PLReportPageWidget({super.key});

  static String routeName = 'PLReportPage';
  static String routePath = '/pl-report';

  @override
  State<PLReportPageWidget> createState() => _PLReportPageWidgetState();
}

class _PLReportPageWidgetState extends State<PLReportPageWidget>
    with RefreshOnPopMixin<PLReportPageWidget> {
  late PLReportPageModel _model;

  // Refresh-after-write fix (parity brief Part 1).
  @override
  void onPageRefresh() => _loadData();

  final scaffoldKey = GlobalKey<ScaffoldState>();

  List<OrdersRow> _allOrders = [];
  List<ExpensesRow> _allExpenses = [];
  List<OrderStaffRow> _allOrderStaff = [];
  List<LeadsRow> _allLeads = [];
  bool _porterEnabled = false;
  // Was a hardcoded Chennai/Bengaluru/Coimbatore/Hyderabad const (kPLReportBranches,
  // "matching apc_webapp App.jsx's BRANCHES constant") — an APC-shaped
  // default that silently mis-attributed or dropped branch P&L rows for
  // any org whose real branches don't match those exact 4 names. Now the
  // org's real active branches.
  List<String> _branchNames = [];

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => PLReportPageModel());

    SchedulerBinding.instance.addPostFrameCallback((_) => _loadData());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  bool _inPeriod(DateTime date, String period) {
    final now = DateTime.now();
    switch (period) {
      case 'month':
        return date.year == now.year && date.month == now.month;
      case 'quarter':
        final currentQuarter = ((now.month - 1) ~/ 3);
        final dateQuarter = ((date.month - 1) ~/ 3);
        return date.year == now.year && dateQuarter == currentQuarter;
      case 'year':
        return date.year == now.year;
      case 'all':
      default:
        return true;
    }
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        OrdersTable().queryRows(queryFn: (q) => OrgScope.read(q)),
        ExpensesTable().queryRows(queryFn: (q) => OrgScope.read(q)),
        OrderStaffTable().queryRows(queryFn: (q) => OrgScope.read(q)),
        LeadsTable().queryRows(queryFn: (q) => OrgScope.read(q)),
        BranchesTable().queryRows(
            queryFn: (q) => OrgScope.read(q).eq('active', true)),
      ]);
      _allOrders = results[0].cast<OrdersRow>();
      _allExpenses = results[1].cast<ExpensesRow>();
      _allOrderStaff = results[2].cast<OrderStaffRow>();
      _allLeads = results[3].cast<LeadsRow>();
      _branchNames = results[4].cast<BranchesRow>().map((b) => b.name).toList();
      // Porter is a per-vendor opt-in (settings key 'porter_enabled') —
      // pan-India vendors that don't use Porter shouldn't see a commission
      // line computed off stray flags.
      final porterRows = await SettingsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('key', 'porter_enabled'),
      );
      _porterEnabled = porterRows.isNotEmpty &&
          (porterRows.first.value ?? '').toLowerCase() == 'true';
      _recompute();
      _model.isLoading = false;
      _model.loadError = null;
    } catch (e) {
      _model.isLoading = false;
      _model.loadError = e.toString();
    }
    safeSetState(() {});
  }

  void _recompute() {
    final fo = _allOrders.where((o) {
      final move = o.moveDateOrNull;
      return move != null && _inPeriod(move, _model.period);
    }).toList();
    final foIds = fo.map((o) => o.id).toSet();

    final revenue = fo.fold(0.0, (s, o) => s + (o.amount ?? 0));
    final labour = fo.fold(
        0.0,
        (s, o) =>
            s +
            _allOrderStaff
                .where((os) => os.orderId == o.id)
                .fold(0.0, (a, os) => a + (os.salaryAmount ?? 0)));
    final orderExpenses = _allExpenses
        .where((e) => e.orderId != null && foIds.contains(e.orderId))
        .fold(0.0, (s, e) => s + (e.amount ?? 0));
    // Faithful to the reference app: otherExp is NOT period-filtered there
    // (`expenses.filter(e=>!e.order_id)`, no date check) — same here.
    final otherExpenses = _allExpenses
        .where((e) => e.orderId == null)
        .fold(0.0, (s, e) => s + (e.amount ?? 0));
    // Commission at each order's own snapshotted rate, with unpriced
    // orders excluded and counted rather than costed at a substitute.
    // Read `?? 16` (APC's porter rate) until 2 Sept 2026 — see
    // /backend/commission_pricing.dart.
    final commissionRollup = rollUpCommission(fo, (o) => o.amount ?? 0);
    final porterCommission = commissionRollup.total;

    _model.revenue = revenue;
    // Drives marginIsShowable: "no expenses" is only a contradiction
    // when work actually happened in the period.
    _model.orderCount = fo.length;
    _model.labour = labour;
    _model.orderExpenses = orderExpenses;
    _model.otherExpenses = otherExpenses;
    _model.porterCommission = _porterEnabled ? porterCommission : 0.0;
    _model.unpricedCommissionCount =
        _porterEnabled ? commissionRollup.unpricedCount : 0;

    _model.branchPL = _branchNames.map((branch) {
      final branchOrders = fo.where((o) => o.branch == branch).toList();
      final branchIds = branchOrders.map((o) => o.id).toSet();
      final rev = branchOrders.fold(0.0, (s, o) => s + (o.amount ?? 0));
      final lab = branchOrders.fold(
          0.0,
          (s, o) =>
              s +
              _allOrderStaff
                  .where((os) => os.orderId == o.id)
                  .fold(0.0, (a, os) => a + (os.salaryAmount ?? 0)));
      final exp = _allExpenses
          .where((e) => e.orderId != null && branchIds.contains(e.orderId))
          .fold(0.0, (s, e) => s + (e.amount ?? 0));
      return BranchPL(
          branch: branch,
          revenue: rev,
          labour: lab,
          expenses: exp,
          profit: rev - lab - exp);
    }).toList();

    final fl = _allLeads
        .where((l) => _inPeriod(l.createdAt ?? DateTime.now(), _model.period))
        .toList();
    _model.leadSources = kPLReportSources
        .map((src) {
          final leadsForSrc = fl.where((l) => l.source == src).toList();
          final converted =
              leadsForSrc.where((l) => l.status == 'confirmed').length;
          return LeadSourceStat(
              source: src, total: leadsForSrc.length, converted: converted);
        })
        .where((s) => s.total > 0)
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
  }

  void _setPeriod(String period) {
    _model.period = period;
    _recompute();
    safeSetState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final costs = _model.orderExpenses +
        _model.otherExpenses +
        _model.labour +
        _model.porterCommission;
    Widget section(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
          child: Text(t,
              style: NgFonts.geist(
                  fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
        );
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
                    child: Text('Could not load report:\n${_model.loadError}',
                        textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      const NgModuleHeader('P&L report'),
                      const SizedBox(height: 14),
                      _periodSelector(context),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                            child: _statCard(Icons.trending_up_rounded,
                                'Revenue', _model.revenue, c.acc)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _statCard(Icons.trending_down_rounded,
                                'Expenses', costs, c.red)),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        // Suppressed entirely when no expenses are recorded
                        // for a period that had orders — see
                        // margin_availability.dart.
                        Expanded(
                            child: _statCard(
                                Icons.account_balance_wallet_outlined,
                                'Net profit',
                                _model.marginIsShowable
                                    ? _model.netProfit
                                    : null,
                                _model.netProfit >= 0 ? c.green : c.red,
                                tinted: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _marginCard(context)),
                      ]),
                      // Names why the figures above are incomplete.
                      if (_model.hasUnpricedCommission)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            commissionIncompleteNote(
                                _model.unpricedCommissionCount),
                            style:
                                NgFonts.geist(fontSize: 12, color: c.amber),
                          ),
                        ),
                      section('Where the money went'),
                      _costBreakdown(costs),
                      section('Branch P&L'),
                      if (_model.branchPL.isEmpty)
                        NgCard(
                          child: Text('No branches yet',
                              style: NgFonts.geist(
                                  fontSize: 13.5, color: c.mute)),
                        )
                      else
                        NgCardList(children: _buildBranchRows(context)),
                      section('Lead source conversion'),
                      if (_model.leadSources.isEmpty)
                        NgCard(
                          child: Text('No leads in this period.',
                              style: NgFonts.geist(
                                  fontSize: 13.5, color: c.mute)),
                        )
                      else
                        NgCardList(children: [
                          for (final s in _model.leadSources)
                            _leadSourceRow(context, s),
                        ]),
                      section('GST summary (5%, approx.)'),
                      _gstSummary(context),
                    ],
                  ),
                ),
    );
  }

  Widget _periodSelector(BuildContext context) {
    const options = {
      'month': 'Month',
      'quarter': 'Quarter',
      'year': 'Year',
      'all': 'All',
    };
    return NgChipRow(
      edge: 0,
      chips: [
        for (final e in options.entries)
          NgChip(
            label: e.value,
            selected: _model.period == e.key,
            onTap: () => _setPeriod(e.key),
          ),
      ],
    );
  }

  /// [value] null means "this figure is not honest right now" — render
  /// the reason instead of a number. Deliberately NOT a zero or a dash:
  /// both read as measurements. See margin_availability.dart.
  Widget _statCard(IconData icon, String label, double? value, Color color,
      {bool tinted = false}) {
    final c = NgPalette.of(context);
    final suppressed = value == null;
    return NgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: suppressed ? c.faint : color, size: 20),
          const SizedBox(height: 10),
          if (suppressed) ...[
            Text(kMarginUnavailableTitle,
                style: NgFonts.geist(
                    fontSize: 13.5, fontWeight: FontWeight.w600, color: c.soft)),
            Text(kMarginUnavailableBody,
                maxLines: 2,
                style: NgFonts.geist(fontSize: 11, color: c.mute)),
          ] else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(functions.inrFull(value),
                  style: NgFonts.mono(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: tinted ? color : c.text)),
            ),
          const SizedBox(height: 2),
          Text(label, style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
        ],
      ),
    );
  }

  Widget _marginCard(BuildContext context) {
    final c = NgPalette.of(context);
    // Margin is net profit over revenue, so it inherits exactly the same
    // starvation — with no expenses recorded it prints a near-100%
    // margin, the most quotable wrong number on the page.
    return NgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.percent_rounded,
              color: _model.marginIsShowable ? c.acc : c.faint, size: 20),
          const SizedBox(height: 10),
          if (_model.marginIsShowable)
            Text('${_model.margin.toStringAsFixed(1)}%',
                style: NgFonts.mono(
                    fontSize: 19, fontWeight: FontWeight.w600, color: c.text))
          else
            Text(kMarginUnavailableTitle,
                style: NgFonts.geist(
                    fontSize: 13.5, fontWeight: FontWeight.w600, color: c.soft)),
          const SizedBox(height: 2),
          Text('Margin', style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
        ],
      ),
    );
  }

  Widget _costBreakdown(double total) {
    final c = NgPalette.of(context);
    final rows = [
      ('Labour', _model.labour),
      ('Order expenses', _model.orderExpenses),
      ('Other expenses', _model.otherExpenses),
      if (_model.porterCommission > 0) ('Commission', _model.porterCommission),
    ];
    return NgCardList(children: [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(r.$1,
                        style: NgFonts.geist(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: c.text)),
                  ),
                  Text(total <= 0 ? '' : '${(r.$2 / total * 100).round()}%',
                      style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
                  const SizedBox(width: 10),
                  Text(functions.inrFull(r.$2),
                      style: NgFonts.mono(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.text)),
                ],
              ),
              const SizedBox(height: 8),
              NgProgressBar(
                  value: total <= 0 ? 0 : r.$2 / total, color: c.red),
            ],
          ),
        ),
    ]);
  }

  List<Widget> _buildBranchRows(BuildContext context) {
    final c = NgPalette.of(context);
    final double maxRevenue = _model.branchPL.isEmpty
        ? 1.0
        : _model.branchPL
            .map((b) => b.revenue)
            .fold<double>(0.0, (a, b) => a > b ? a : b)
            .clamp(1.0, double.infinity)
            .toDouble();
    return _model.branchPL.map((b) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(b.branch,
                      style: NgFonts.geist(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.text)),
                ),
                Text(
                  '${functions.inrFull(b.profit.abs())} ${b.profit >= 0 ? 'profit' : 'loss'} · ${b.margin.toStringAsFixed(0)}%',
                  style: NgFonts.geist(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: b.profit >= 0 ? c.green : c.red),
                ),
              ],
            ),
            const SizedBox(height: 8),
            NgProgressBar(
                value: (b.revenue / maxRevenue).clamp(0.0, 1.0).toDouble(),
                color: c.accBtn),
            const SizedBox(height: 4),
            Text('Revenue ${functions.inrFull(b.revenue)}',
                style: NgFonts.mono(fontSize: 12, color: c.mute)),
          ],
        ),
      );
    }).toList();
  }

  Widget _leadSourceRow(BuildContext context, LeadSourceStat s) {
    final c = NgPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(s.source,
                style: NgFonts.geist(fontSize: 14, color: c.text)),
          ),
          Text('${s.converted}/${s.total} · ${s.rate.toStringAsFixed(0)}%',
              style: NgFonts.mono(
                  fontSize: 13.5, fontWeight: FontWeight.w600, color: c.text)),
        ],
      ),
    );
  }

  Widget _gstSummary(BuildContext context) {
    final c = NgPalette.of(context);
    return NgCard(
      child: Column(
        children: [
          _gstRow(context, 'Taxable value', _model.gstTaxable),
          _gstRow(context, 'CGST (2.5%)', _model.gstHalf),
          _gstRow(context, 'SGST (2.5%)', _model.gstHalf),
          Divider(color: c.w06, height: 16),
          _gstRow(context, 'Total GST', _model.gstTotal, bold: true),
        ],
      ),
    );
  }

  Widget _gstRow(BuildContext context, String label, double value,
      {bool bold = false}) {
    final c = NgPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: NgFonts.geist(
                    fontSize: 13.5,
                    fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                    color: bold ? c.text : c.mute)),
          ),
          Text(functions.inrFull(value),
              style: NgFonts.mono(
                  fontSize: 13.5, fontWeight: FontWeight.w600, color: c.text)),
        ],
      ),
    );
  }
}
