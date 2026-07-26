import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'reports_page_model.dart';
export 'reports_page_model.dart';

const List<String> _kReportBranches = [
  'Chennai',
  'Bengaluru',
  'Coimbatore',
  'Hyderabad',
];

/// Detailed business reports and analytics for the current org.
///
/// Ported from reference/APC Web App JSX/App.jsx's ReportsPage component
/// (lines ~7249-7445): branch-wise revenue, last-6-months order volume,
/// all-time top customers (by name, not period-filtered per the reference
/// app), and service mix within the selected period.
class ReportsPageWidget extends StatefulWidget {
  const ReportsPageWidget({super.key});

  static String routeName = 'ReportsPage';
  static String routePath = '/reports';

  @override
  State<ReportsPageWidget> createState() => _ReportsPageWidgetState();
}

class _ReportsPageWidgetState extends State<ReportsPageWidget> {
  late ReportsPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  static final _currency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  static final _monthFormat = DateFormat('MMM yyyy');
  static final _dayFormat = DateFormat('MMM d');

  List<OrdersRow> _allOrders = [];
  List<ExpensesRow> _allExpenses = [];
  List<OrderStaffRow> _allOrderStaff = [];

  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => ReportsPageModel());

    SchedulerBinding.instance.addPostFrameCallback((_) => _loadData());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();
    _searchController.dispose();

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
      ]);
      _allOrders = results[0].cast<OrdersRow>();
      _allExpenses = results[1].cast<ExpensesRow>();
      _allOrderStaff = results[2].cast<OrderStaffRow>();
      _recompute();
      _model.isLoading = false;
      _model.loadError = null;
    } catch (e) {
      _model.isLoading = false;
      _model.loadError = e.toString();
    }
    safeSetState(() {});
  }

  List<OrdersRow> get _filteredOrders {
    final q = _model.searchQuery.trim().toLowerCase();
    return _allOrders.where((o) {
      final move = o.moveDateOrNull;
      if (move == null || !_inPeriod(move, _model.period)) return false;
      if (q.isEmpty) return true;
      return o.customer.toLowerCase().contains(q) ||
          (o.fromCity ?? '').toLowerCase().contains(q) ||
          (o.toCity ?? '').toLowerCase().contains(q);
    }).toList();
  }

  void _recompute() {
    final fo = _filteredOrders;
    _model.filteredOrderCount = fo.length;

    _model.branchRevenue = _kReportBranches.map((branch) {
      final branchOrders = fo.where((o) => o.branch == branch).toList();
      final ids = branchOrders.map((o) => o.id).toSet();
      final rev = branchOrders.fold(0.0, (s, o) => s + (o.amount ?? 0));
      final labour = branchOrders.fold(
          0.0,
          (s, o) =>
              s +
              _allOrderStaff
                  .where((os) => os.orderId == o.id)
                  .fold(0.0, (a, os) => a + (os.salaryAmount ?? 0)));
      final exp = _allExpenses
          .where((e) => e.orderId != null && ids.contains(e.orderId))
          .fold(0.0, (s, e) => s + (e.amount ?? 0));
      return BranchRevenue(
          branch: branch,
          orderCount: branchOrders.length,
          revenue: rev,
          labour: labour,
          expenses: exp);
    }).toList();

    // Last 6 months, walking back from the current month — not affected by
    // the period selector (matches the reference app).
    final now = DateTime.now();
    final months = List.generate(6, (i) {
      final m = DateTime(now.year, now.month - (5 - i), 1);
      return m;
    });
    _model.monthlyVolume = months.map((m) {
      final inMonth = _allOrders.where((o) {
        final move = o.moveDateOrNull;
        return move != null && move.year == m.year && move.month == m.month;
      });
      return MonthlyVolume(
        label: _monthFormat.format(m),
        orderCount: inMonth.length,
        revenue: inMonth.fold(0.0, (s, o) => s + (o.amount ?? 0)),
      );
    }).toList();

    // Top customers — all-time, not period-filtered (matches reference app).
    final byCustomer = <String, List<OrdersRow>>{};
    for (final o in _allOrders) {
      byCustomer.putIfAbsent(o.customer, () => []).add(o);
    }
    final top = byCustomer.entries.map((e) {
      final orders = e.value;
      final dates = orders.map((o) => o.moveDateOrNull).whereType<DateTime>();
      return TopCustomer(
        customer: e.key,
        orderCount: orders.length,
        revenue: orders.fold(0.0, (s, o) => s + (o.amount ?? 0)),
        // Orders with no move_date at all fall back to the epoch rather
        // than crashing — this is a display-only "last move" string.
        lastDate: dates.isEmpty
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : dates.reduce((a, b) => a.isAfter(b) ? a : b),
      );
    }).toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    _model.topCustomers = top.take(10).toList();

    final byService = <String, int>{};
    for (final o in fo) {
      final svc = o.service ?? 'Other';
      byService[svc] = (byService[svc] ?? 0) + 1;
    }
    _model.serviceMix = byService.entries
        .map((e) => ServiceMixStat(service: e.key, count: e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
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
            'Reports',
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
                            'Could not load reports:\n${_model.loadError}',
                            textAlign: TextAlign.center),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView(
                        padding: const EdgeInsets.all(16.0),
                        children: [
                          _periodSelector(context),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search customer or city…',
                              prefixIcon: const Icon(Icons.search),
                              filled: true,
                              fillColor:
                                  FlutterFlowTheme.of(context).secondaryBackground,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (v) {
                              _model.searchQuery = v;
                              _recompute();
                              safeSetState(() {});
                            },
                          ),
                          const SizedBox(height: 20),
                          Text('Branch-wise Revenue',
                              style: FlutterFlowTheme.of(context).titleMedium),
                          const SizedBox(height: 8),
                          ..._model.branchRevenue.map((b) => _branchCard(context, b)),
                          const SizedBox(height: 20),
                          Text('Monthly Volume (Last 6 Months)',
                              style: FlutterFlowTheme.of(context).titleMedium),
                          const SizedBox(height: 8),
                          _monthlyVolumeChart(context),
                          const SizedBox(height: 20),
                          Text('Top Customers',
                              style: FlutterFlowTheme.of(context).titleMedium),
                          const SizedBox(height: 8),
                          if (_model.topCustomers.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text('No orders yet.',
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                          font: GoogleFonts.inter(),
                                          color: FlutterFlowTheme.of(context)
                                              .secondaryText)),
                            )
                          else
                            ..._model.topCustomers
                                .map((c) => _topCustomerRow(context, c)),
                          const SizedBox(height: 20),
                          Text('Service Mix',
                              style: FlutterFlowTheme.of(context).titleMedium),
                          const SizedBox(height: 8),
                          ..._serviceMixRows(context),
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

  Widget _branchCard(BuildContext context, BranchRevenue b) {
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
              Text('${b.orderCount} orders',
                  style: FlutterFlowTheme.of(context).bodySmall.override(
                      font: GoogleFonts.inter(),
                      color: FlutterFlowTheme.of(context).secondaryText)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Revenue ${_currency.format(b.revenue)}',
                  style: FlutterFlowTheme.of(context).bodySmall.override(
                      font: GoogleFonts.inter(),
                      color: FlutterFlowTheme.of(context).secondaryText)),
              Text(
                '${_currency.format(b.profit.abs())} ${b.profit >= 0 ? 'profit' : 'loss'} · ${b.margin.toStringAsFixed(0)}%',
                style: FlutterFlowTheme.of(context).titleSmall.override(
                    font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                    color: b.profit >= 0
                        ? FlutterFlowTheme.of(context).primary
                        : FlutterFlowTheme.of(context).error),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _monthlyVolumeChart(BuildContext context) {
    final double maxRevenue = _model.monthlyVolume.isEmpty
        ? 1.0
        : _model.monthlyVolume
            .map((m) => m.revenue)
            .fold<double>(0.0, (a, b) => a > b ? a : b)
            .clamp(1.0, double.infinity)
            .toDouble();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: _model.monthlyVolume.map((m) {
          final double fraction =
              (m.revenue / maxRevenue).clamp(0.0, 1.0).toDouble();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                    width: 64,
                    child: Text(m.label,
                        style: FlutterFlowTheme.of(context).bodySmall.override(
                            font: GoogleFonts.inter(),
                            color:
                                FlutterFlowTheme.of(context).secondaryText))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 10,
                      backgroundColor: FlutterFlowTheme.of(context).alternate,
                      valueColor: AlwaysStoppedAnimation(
                          FlutterFlowTheme.of(context).primary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${m.orderCount}',
                    style: FlutterFlowTheme.of(context).bodySmall.override(
                        font: GoogleFonts.inter(),
                        color: FlutterFlowTheme.of(context).secondaryText)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _topCustomerRow(BuildContext context, TopCustomer c) {
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.customer,
                    style: FlutterFlowTheme.of(context)
                        .bodyMedium
                        .override(font: GoogleFonts.inter(fontWeight: FontWeight.w600))),
                Text(
                    '${c.orderCount} order${c.orderCount == 1 ? '' : 's'} · last ${_dayFormat.format(c.lastDate)}',
                    style: FlutterFlowTheme.of(context).bodySmall.override(
                        font: GoogleFonts.inter(),
                        color: FlutterFlowTheme.of(context).secondaryText)),
              ],
            ),
          ),
          Text(_currency.format(c.revenue),
              style: FlutterFlowTheme.of(context).titleSmall.override(
                  font: GoogleFonts.interTight(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  List<Widget> _serviceMixRows(BuildContext context) {
    final total = _model.filteredOrderCount == 0 ? 1 : _model.filteredOrderCount;
    return _model.serviceMix.map((s) {
      final pct = (s.count / total * 100);
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
            Text(s.service,
                style: FlutterFlowTheme.of(context)
                    .bodyMedium
                    .override(font: GoogleFonts.inter())),
            Text('${s.count} · ${pct.toStringAsFixed(0)}%',
                style: FlutterFlowTheme.of(context).titleSmall.override(
                    font: GoogleFonts.interTight(fontWeight: FontWeight.w600))),
          ],
        ),
      );
    }).toList();
  }
}
