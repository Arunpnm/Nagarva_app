import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/staff_pay_types.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/l10n/gen/app_localizations.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

  Widget _staffRow(StaffRow s) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final entries = _monthEntriesFor(s.id!);
    final earned = _sumOS(entries);
    final paid = _sumPay(_monthPaymentsFor(s.id!));
    final balance = earned - paid;
    final advance = _sumAdv(_pendingAdvancesFor(s.id!));
    final pay = StaffPayType.of(s);
    final role = (s.role ?? '').trim();
    final sub = [
      switch (pay) {
        StaffPayType.monthlyFixed => l.ngStaffMonthly,
        StaffPayType.temporary => l.ngStaffTemporary,
        _ => l.ngStaffDaily,
      },
      if (pay == StaffPayType.monthlyFixed && (s.salary ?? 0) > 0)
        functions.inrFull(s.salary)
      else
        l.ngSalJobs(entries.length),
      if (advance > 0) l.ngSalAdvance(functions.inrFull(advance)),
    ].join(' · ');
    return InkWell(
      onTap: () => _openLedger(s),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            NgAvatar(s.name, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: s.name,
                          style: NgFonts.geist(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: c.text)),
                      if (role.isNotEmpty)
                        TextSpan(
                            text:
                                ' · ${role[0].toUpperCase()}${role.substring(1)}',
                            style:
                                NgFonts.geist(fontSize: 12.5, color: c.mute)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(sub,
                      maxLines: 2,
                      style: NgFonts.geist(
                          fontSize: 12.5, height: 1.35, color: c.mute)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(functions.inrFull(balance),
                    style: NgFonts.geist(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.text)),
                Text(l.ngSalBalance,
                    style: NgFonts.geist(fontSize: 11.5, color: c.mute)),
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 20, color: c.faint),
          ],
        ),
      ),
    );
  }

  Widget _tile(String label, double v, Color color) {
    final c = NgPalette.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.w06),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
            const SizedBox(height: 4),
            Text(functions.inrFull(v),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NgFonts.geist(
                    fontSize: 18, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }

  void _shiftMonth(int d) => safeSetState(() => _model.month =
      DateTime(_model.month.year, _model.month.month + d));

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final staff = _model.staffList.where((s) => s.id != null).toList();
    double total(double Function(StaffRow) f) =>
        staff.fold(0.0, (a, s) => a + f(s));
    final earned = total((s) => _sumOS(_monthEntriesFor(s.id!)));
    final paid = total((s) => _sumPay(_monthPaymentsFor(s.id!)));
    final advances = total((s) => _sumAdv(_pendingAdvancesFor(s.id!)));
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: c.bg,
      appBar: NgTopBar(onRefresh: _load),
      body: _model.loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  NgModuleHeader(
                    l.ngSalTitle,
                    actions: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Previous month',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.chevron_left_rounded,
                                color: c.mute),
                            onPressed: () => _shiftMonth(-1),
                          ),
                          Text(DateFormat('MMM yyyy').format(_model.month),
                              style:
                                  NgFonts.geist(fontSize: 13, color: c.mute)),
                          IconButton(
                            tooltip: 'Next month',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.chevron_right_rounded,
                                color: c.mute),
                            onPressed: () => _shiftMonth(1),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _tile(l.ngSalToPay, earned - paid, c.acc),
                      const SizedBox(width: 8),
                      _tile(l.ngSalAdvances, advances, c.red),
                      const SizedBox(width: 8),
                      _tile(l.ngSalPaid, paid, c.green),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (staff.isEmpty)
                    NgCard(
                      child: Text(l.ngStaffNone,
                          textAlign: TextAlign.center,
                          style:
                              NgFonts.geist(fontSize: 13.5, color: c.mute)),
                    )
                  else
                    NgCardList(children: [
                      for (final s in staff) _staffRow(s),
                    ]),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 16, color: c.faint),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(l.ngSalNote,
                              style: NgFonts.geist(
                                  fontSize: 12, height: 1.4, color: c.mute)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
