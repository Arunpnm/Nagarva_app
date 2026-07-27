import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/keyboard_scroll_view.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'salary_page_model.dart';
import 'staff_ledger_sheet.dart';
export 'salary_page_model.dart';

/// Salary & Staff ledger (Week 3b rewrite).
///
/// Month-navigable payroll view modelled on the APC reference: header with
/// month totals (earned / paid / advances outstanding), then a card per
/// staff showing earned·paid·balance·advance at a glance. Tapping a card
/// opens StaffLedgerSheet with the full ledger and the Pay / Give Advance /
/// Settle Advance actions.
///
/// Earnings attribution: order_staff.salary_amount grouped by the linked
/// order's move_date month (order_staff had no timestamp of its own until
/// 20260718; move_date is the operationally-true month anyway).
class SalaryPageWidget extends StatefulWidget {
  const SalaryPageWidget({super.key});

  static String routeName = 'SalaryPage';
  static String routePath = '/salary';

  @override
  State<SalaryPageWidget> createState() => _SalaryPageWidgetState();
}

class _SalaryPageWidgetState extends State<SalaryPageWidget>
    with RefreshOnPopMixin<SalaryPageWidget> {
  late SalaryPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => SalaryPageModel());

    SchedulerBinding.instance.addPostFrameCallback((_) => _load());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  // Refresh-after-write fix (parity brief Part 1): re-run the load when a
  // pushed route (e.g. StaffLedgerSheet's pay/advance actions) is popped.
  @override
  void onPageRefresh() => _load();

  Future<void> _load() async {
    _model.loading = true;
    safeSetState(() {});
    final results = await Future.wait([
      StaffTable().queryRows(
          queryFn: (q) => OrgScope.read(q).order('name', ascending: true)),
      OrderStaffTable().queryRows(queryFn: (q) => OrgScope.read(q)),
      OrdersTable().queryRows(queryFn: (q) => OrgScope.read(q)),
      SalaryPaymentsTable().queryRows(queryFn: (q) => OrgScope.read(q)),
      StaffAdvancesTable().queryRows(queryFn: (q) => OrgScope.read(q)),
    ]);
    _model.staffList = (results[0] as List).cast<StaffRow>();
    _model.orderStaff = (results[1] as List).cast<OrderStaffRow>();
    final orders = (results[2] as List).cast<OrdersRow>();
    _model.ordersById = {
      for (final o in orders)
        if (o.id != null) o.id!: o
    };
    _model.payments = (results[3] as List).cast<SalaryPaymentsRow>();
    _model.advances = (results[4] as List).cast<StaffAdvancesRow>();
    _model.loading = false;
    safeSetState(() {});
  }

  bool _inMonth(DateTime? d) =>
      d != null && d.year == _model.month.year && d.month == _model.month.month;

  List<OrderStaffRow> _monthEntriesFor(String staffId) => _model.orderStaff
      .where((e) =>
          e.staffId == staffId &&
          _inMonth(_model.ordersById[e.orderId]?.moveDateOrNull))
      .toList();

  List<SalaryPaymentsRow> _monthPaymentsFor(String staffId) => _model.payments
      .where((p) => p.staffId == staffId && _inMonth(p.paidDate))
      .toList();

  List<StaffAdvancesRow> _pendingAdvancesFor(String staffId) => _model.advances
      .where((a) =>
          a.staffId == staffId &&
          (a.status ?? 'pending').toLowerCase() == 'pending')
      .toList();

  double _sumOS(List<OrderStaffRow> l) =>
      l.fold(0.0, (s, e) => s + (e.salaryAmount ?? 0));
  double _sumPay(List<SalaryPaymentsRow> l) =>
      l.fold(0.0, (s, e) => s + e.amount);
  double _sumAdv(List<StaffAdvancesRow> l) =>
      l.fold(0.0, (s, e) => s + (e.amount ?? 0));

  Future<void> _openLedger(StaffRow s) async {
    final changed = await StaffLedgerSheet.show(
      context,
      staff: s,
      month: _model.month,
      monthOrderStaff: _monthEntriesFor(s.id!),
      ordersById: _model.ordersById,
      monthPayments: _monthPaymentsFor(s.id!),
      pendingAdvances: _pendingAdvancesFor(s.id!),
    );
    if (changed) _load();
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  Widget _staffCard(StaffRow s) {
    final theme = FlutterFlowTheme.of(context);
    final earned = _sumOS(_monthEntriesFor(s.id!));
    final paid = _sumPay(_monthPaymentsFor(s.id!));
    final balance = earned - paid;
    final advance = _sumAdv(_pendingAdvancesFor(s.id!));

    Widget mini(String label, double v, Color c) => Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('₹${v.toStringAsFixed(0)}',
                style: GoogleFonts.interTight(
                    fontSize: 12.5, fontWeight: FontWeight.w800, color: c)),
            Text(label,
                style:
                    GoogleFonts.inter(fontSize: 9, color: theme.secondaryText)),
          ],
        );

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openLedger(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(19),
              ),
              child: Text(
                s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
                style: GoogleFonts.interTight(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: theme.primary),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.interTight(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: theme.primaryText)),
                  Text(
                    [
                      if ((s.role ?? '').isNotEmpty) s.role!,
                      if ((s.branch ?? '').isNotEmpty) s.branch!,
                    ].join(' · '),
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: theme.secondaryText),
                  ),
                ],
              ),
            ),
            mini('EARNED', earned, const Color(0xFF2E7D32)),
            const SizedBox(width: 12),
            mini('TO PAY', balance,
                balance > 0 ? theme.primary : theme.secondaryText),
            const SizedBox(width: 12),
            mini('ADVANCE', advance,
                advance > 0 ? theme.error : theme.secondaryText),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: theme.secondaryText),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final monthLabel = DateFormat('MMMM yyyy').format(_model.month);
    final totalEarned = _model.staffList
        .fold(0.0, (s, st) => s + _sumOS(_monthEntriesFor(st.id!)));
    final totalPaid = _model.staffList
        .fold(0.0, (s, st) => s + _sumPay(_monthPaymentsFor(st.id!)));
    final totalAdvance = _model.staffList
        .fold(0.0, (s, st) => s + _sumAdv(_pendingAdvancesFor(st.id!)));

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: theme.primaryBackground,
        appBar: AppBar(
          backgroundColor: theme.primaryBackground,
          automaticallyImplyLeading: true,
          title: Text(
            'Salary & Staff',
            style: theme.titleLarge.override(
              font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
              fontSize: 22.0,
              letterSpacing: 0.0,
            ),
          ),
          centerTitle: true,
          elevation: 0.0,
        ),
        body: SafeArea(
          top: true,
          child: _model.loading
              ? const Center(child: CircularProgressIndicator())
              : KeyboardScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ---- Month nav + payroll totals ---------------------
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.secondaryBackground,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.chevron_left,
                                      color: theme.primary),
                                  onPressed: () => safeSetState(() =>
                                      _model.month = DateTime(_model.month.year,
                                          _model.month.month - 1)),
                                ),
                                Text(monthLabel,
                                    style: GoogleFonts.interTight(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: theme.primaryText)),
                                IconButton(
                                  icon: Icon(Icons.chevron_right,
                                      color: theme.primary),
                                  onPressed: () => safeSetState(() =>
                                      _model.month = DateTime(_model.month.year,
                                          _model.month.month + 1)),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _totalCol('Earned', totalEarned,
                                    const Color(0xFF2E7D32)),
                                _totalCol('Paid Out', totalPaid,
                                    const Color(0xFF1565C0)),
                                _totalCol('To Pay', totalEarned - totalPaid,
                                    theme.primary),
                                _totalCol(
                                    'Advances', totalAdvance, theme.error),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_model.staffList.isEmpty)
                        Text(
                          'No staff yet — add your team on the Staff page '
                          'first.',
                          style: GoogleFonts.inter(
                              fontSize: 13, color: theme.secondaryText),
                        )
                      else
                        ..._model.staffList.map(_staffCard),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _totalCol(String label, double v, Color c) {
    final theme = FlutterFlowTheme.of(context);
    return Column(
      children: [
        Text('₹${v.toStringAsFixed(0)}',
            style: GoogleFonts.interTight(
                fontSize: 14.5, fontWeight: FontWeight.w800, color: c)),
        Text(label,
            style: GoogleFonts.inter(fontSize: 10, color: theme.secondaryText)),
      ],
    );
  }
}
