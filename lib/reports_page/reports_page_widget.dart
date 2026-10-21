import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'reports_page_model.dart';
export 'reports_page_model.dart';

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

class _ReportsPageWidgetState extends State<ReportsPageWidget>
    with RefreshOnPopMixin<ReportsPageWidget> {
  late ReportsPageModel _model;

  // Refresh-after-write fix (parity brief Part 1).
  @override
  void onPageRefresh() => _loadData();

  final scaffoldKey = GlobalKey<ScaffoldState>();

  static final _monthFormat = DateFormat('MMM yyyy');
  static final _dayFormat = DateFormat('MMM d');

  List<OrdersRow> _allOrders = [];
  List<ExpensesRow> _allExpenses = [];
  List<OrderStaffRow> _allOrderStaff = [];
  // Was a hardcoded Chennai/Bengaluru/Coimbatore/Hyderabad const
  // (_kReportBranches, same APC-shaped default as p_l_report_page's
  // kPLReportBranches) — now the org's real active branches.
  List<String> _branchNames = [];

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
        BranchesTable().queryRows(
            queryFn: (q) => OrgScope.read(q).eq('active', true)),
      ]);
      _allOrders = results[0].cast<OrdersRow>();
      _allExpenses = results[1].cast<ExpensesRow>();
      _allOrderStaff = results[2].cast<OrderStaffRow>();
      _branchNames = results[3].cast<BranchesRow>().map((b) => b.name).toList();
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

    _model.branchRevenue = _branchNames.map((branch) {
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
    final c = NgPalette.of(context);
    Widget section(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
          child: Text(t,
              style: NgFonts.geist(
                  fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
        );
    Widget empty(String t) => NgCard(
          child: Text(t, style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
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
                    child: Text('Could not load reports:\n${_model.loadError}',
                        textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      const NgModuleHeader('Reports'),
                      const SizedBox(height: 14),
                      _periodSelector(context),
                      const SizedBox(height: 14),
                      NgSearchField(
                        controller: _searchController,
                        hint: 'Search customer or city',
                        onChanged: (v) {
                          _model.searchQuery = v;
                          _recompute();
                          safeSetState(() {});
                        },
                      ),
                      section('Branch-wise revenue'),
                      if (_model.branchRevenue.isEmpty)
                        empty('No orders in this period.')
                      else
                        NgCardList(children: [
                          for (final b in _model.branchRevenue)
                            _branchCard(context, b),
                        ]),
                      section('Monthly volume (last 6 months)'),
                      _monthlyVolumeChart(context),
                      section('Top customers'),
                      if (_model.topCustomers.isEmpty)
                        empty('No orders yet.')
                      else
                        NgCardList(children: [
                          for (final tc in _model.topCustomers)
                            _topCustomerRow(context, tc),
                        ]),
                      section('Service mix'),
                      if (_model.serviceMix.isEmpty)
                        empty('No orders in this period.')
                      else
                        NgCardList(children: _serviceMixRows(context)),
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

  Widget _branchCard(BuildContext context, BranchRevenue b) {
    final c = NgPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(b.branch,
                    style: NgFonts.geist(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: c.text)),
              ),
              Text('${b.orderCount} orders',
                  style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text('Revenue ${functions.inrFull(b.revenue)}',
                    style: NgFonts.mono(fontSize: 12.5, color: c.mute)),
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
        ],
      ),
    );
  }

  /// Vertical bars, order count over each, month under — the handoff's
  /// chart.
  Widget _monthlyVolumeChart(BuildContext context) {
    final c = NgPalette.of(context);
    final maxCount = _model.monthlyVolume.isEmpty
        ? 1
        : _model.monthlyVolume
            .map((m) => m.orderCount)
            .fold<int>(0, (a, b) => a > b ? a : b)
            .clamp(1, 1 << 30);
    return NgCard(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      child: SizedBox(
        height: 170,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final m in _model.monthlyVolume)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('${m.orderCount}',
                          style: NgFonts.geist(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: c.text)),
                      const SizedBox(height: 4),
                      Container(
                        height: 110 * (m.orderCount / maxCount) + 2,
                        decoration: BoxDecoration(
                          color: c.accBtn,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(m.label.split(' ').first,
                          style: NgFonts.geist(fontSize: 11.5, color: c.mute)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _topCustomerRow(BuildContext context, TopCustomer tc) {
    final c = NgPalette.of(context);
    return NgListRow(
      leading: NgAvatar(tc.customer),
      title: tc.customer,
      subtitle:
          '${tc.orderCount} order${tc.orderCount == 1 ? '' : 's'} · last ${_dayFormat.format(tc.lastDate)}',
      trailing: Text(functions.inrFull(tc.revenue),
          style: NgFonts.mono(
              fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
    );
  }

  List<Widget> _serviceMixRows(BuildContext context) {
    final c = NgPalette.of(context);
    final total =
        _model.filteredOrderCount == 0 ? 1 : _model.filteredOrderCount;
    return _model.serviceMix.map((s) {
      final pct = s.count / total;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(s.service,
                      style: NgFonts.geist(fontSize: 14, color: c.text)),
                ),
                Text('${s.count} · ${(pct * 100).toStringAsFixed(0)}%',
                    style: NgFonts.mono(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.text)),
              ],
            ),
            const SizedBox(height: 8),
            NgProgressBar(value: pct, color: c.accBtn),
          ],
        ),
      );
    }).toList();
  }
}
