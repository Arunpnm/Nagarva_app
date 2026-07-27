import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
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

  static final _currency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  List<OrdersRow> _allOrders = [];
  List<ExpensesRow> _allExpenses = [];
  List<OrderStaffRow> _allOrderStaff = [];
  List<LeadsRow> _allLeads = [];
  bool _porterEnabled = false;

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
      ]);
      _allOrders = results[0].cast<OrdersRow>();
      _allExpenses = results[1].cast<ExpensesRow>();
      _allOrderStaff = results[2].cast<OrderStaffRow>();
      _allLeads = results[3].cast<LeadsRow>();
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
    // See accounts_page_widget.dart's _computeDailyRows comment: this app
    // stores the porter commission % directly (`is_porter` +
    // `porter_commission_pct`), it doesn't derive 16%/19% from a
    // local/outstation order_type like the reference web app.
    final porterCommission = fo
        .where((o) => o.isPorter ?? (o.orderSource == 'porter'))
        .fold(
            0.0,
            (s, o) =>
                s +
                ((o.amount ?? 0) * ((o.porterCommissionPct ?? 16) / 100))
                    .roundToDouble());

    _model.revenue = revenue;
    _model.labour = labour;
    _model.orderExpenses = orderExpenses;
    _model.otherExpenses = otherExpenses;
    _model.porterCommission = _porterEnabled ? porterCommission : 0.0;

    _model.branchPL = kPLReportBranches.map((branch) {
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
            'P&L Report',
            style: FlutterFlowTheme.of(context).titleLarge.override(
                  font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                  fontSize: 22.0,
                  fontWeight: FontWeight.w600,
                ),
          ),
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
                            'Could not load report:\n${_model.loadError}',
                            textAlign: TextAlign.center),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView(
                        padding: const EdgeInsets.all(16.0),
                        children: [
                          _periodSelector(context),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                  child: _statCard(
                                      context,
                                      Icons.trending_up,
                                      'Revenue',
                                      _model.revenue,
                                      FlutterFlowTheme.of(context).primary)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _statCard(
                                      context,
                                      Icons.trending_down,
                                      'Expenses',
                                      _model.orderExpenses +
                                          _model.otherExpenses +
                                          _model.labour +
                                          _model.porterCommission,
                                      FlutterFlowTheme.of(context).error)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                  child: _statCard(
                                      context,
                                      Icons.account_balance_wallet,
                                      'Net Profit',
                                      _model.netProfit,
                                      _model.netProfit >= 0
                                          ? FlutterFlowTheme.of(context).primary
                                          : FlutterFlowTheme.of(context)
                                              .error)),
                              const SizedBox(width: 12),
                              Expanded(child: _marginCard(context)),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text('Branch P&L',
                              style: FlutterFlowTheme.of(context).titleMedium),
                          const SizedBox(height: 8),
                          ..._buildBranchRows(context),
                          const SizedBox(height: 20),
                          Text('Lead Source Conversion',
                              style: FlutterFlowTheme.of(context).titleMedium),
                          const SizedBox(height: 8),
                          if (_model.leadSources.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text('No leads in this period.',
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                          font: GoogleFonts.inter(),
                                          color: FlutterFlowTheme.of(context)
                                              .secondaryText)),
                            )
                          else
                            ..._model.leadSources
                                .map((s) => _leadSourceRow(context, s)),
                          const SizedBox(height: 20),
                          Text('GST Summary (5%, approx.)',
                              style: FlutterFlowTheme.of(context).titleMedium),
                          const SizedBox(height: 8),
                          _gstSummary(context),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _periodSelector(BuildContext context) {
    final options = {
      'month': 'Month',
      'quarter': 'Quarter',
      'year': 'Year',
      'all': 'All',
    };
    return Wrap(
      spacing: 8,
      children: options.entries.map((e) {
        final selected = _model.period == e.key;
        return ChoiceChip(
          label: Text(e.value),
          selected: selected,
          onSelected: (_) => _setPeriod(e.key),
          selectedColor: FlutterFlowTheme.of(context).primary,
          labelStyle: TextStyle(
            color: selected
                ? FlutterFlowTheme.of(context).primaryBackground
                : FlutterFlowTheme.of(context).primaryText,
          ),
        );
      }).toList(),
    );
  }

  Widget _statCard(BuildContext context, IconData icon, String label,
      double value, Color color) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22.0),
            const SizedBox(height: 4),
            Text(_currency.format(value.abs()),
                style: FlutterFlowTheme.of(context).headlineSmall.override(
                    font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                    color: FlutterFlowTheme.of(context).primaryText)),
            Text(label,
                style: FlutterFlowTheme.of(context).labelMedium.override(
                    font: GoogleFonts.inter(),
                    color: FlutterFlowTheme.of(context).secondaryText)),
          ],
        ),
      ),
    );
  }

  Widget _marginCard(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.percent,
                color: FlutterFlowTheme.of(context).primary, size: 22.0),
            const SizedBox(height: 4),
            Text('${_model.margin.toStringAsFixed(1)}%',
                style: FlutterFlowTheme.of(context).headlineSmall.override(
                    font: GoogleFonts.interTight(fontWeight: FontWeight.w600))),
            Text('Margin',
                style: FlutterFlowTheme.of(context).labelMedium.override(
                    font: GoogleFonts.inter(),
                    color: FlutterFlowTheme.of(context).secondaryText)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBranchRows(BuildContext context) {
    final double maxRevenue = _model.branchPL.isEmpty
        ? 1.0
        : _model.branchPL
            .map((b) => b.revenue)
            .fold<double>(0.0, (a, b) => a > b ? a : b)
            .clamp(1.0, double.infinity)
            .toDouble();
    return _model.branchPL.map((b) {
      final double fraction =
          (b.revenue / maxRevenue).clamp(0.0, 1.0).toDouble();
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(b.branch,
                    style: FlutterFlowTheme.of(context).bodyMedium.override(
                        font: GoogleFonts.inter(fontWeight: FontWeight.w600))),
                Text(
                  '${_currency.format(b.profit.abs())} ${b.profit >= 0 ? 'profit' : 'loss'} · ${b.margin.toStringAsFixed(0)}%',
                  style: FlutterFlowTheme.of(context).bodySmall.override(
                      font: GoogleFonts.inter(),
                      color: b.profit >= 0
                          ? FlutterFlowTheme.of(context).primary
                          : FlutterFlowTheme.of(context).error),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: FlutterFlowTheme.of(context).alternate,
                valueColor: AlwaysStoppedAnimation(
                    FlutterFlowTheme.of(context).primary),
              ),
            ),
            const SizedBox(height: 4),
            Text('Rev ${_currency.format(b.revenue)}',
                style: FlutterFlowTheme.of(context).bodySmall.override(
                    font: GoogleFonts.inter(),
                    color: FlutterFlowTheme.of(context).secondaryText)),
          ],
        ),
      );
    }).toList();
  }

  Widget _leadSourceRow(BuildContext context, LeadSourceStat s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(s.source,
              style: FlutterFlowTheme.of(context)
                  .bodyMedium
                  .override(font: GoogleFonts.inter())),
          Text('${s.converted}/${s.total} · ${s.rate.toStringAsFixed(0)}%',
              style: FlutterFlowTheme.of(context).titleSmall.override(
                  font: GoogleFonts.interTight(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _gstSummary(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _gstRow(context, 'Taxable Value', _model.gstTaxable),
          _gstRow(context, 'CGST (2.5%)', _model.gstHalf),
          _gstRow(context, 'SGST (2.5%)', _model.gstHalf),
          const Divider(),
          _gstRow(context, 'Total GST', _model.gstTotal, bold: true),
        ],
      ),
    );
  }

  Widget _gstRow(BuildContext context, String label, double value,
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
          Text(_currency.format(value),
              style: (bold
                      ? FlutterFlowTheme.of(context).titleSmall
                      : FlutterFlowTheme.of(context).bodyMedium)
                  .override(
                      font:
                          GoogleFonts.interTight(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
