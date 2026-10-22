import '/app_session.dart';
import '/backend/approval_queue.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/field_expenses.dart';
import '/flutter_flow/ng_tokens.dart';
// kNotAvailableReasons — the same labels the supervisor chose from, so
// the owner reads exactly what the supervisor selected.
import '/supervisor_job_page/supervisor_job_page_model.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/backend/order_stages.dart';
import '/backend/module_navigation.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'operations_page_model.dart';
export 'operations_page_model.dart';

/// Operations — live shifting board (rewrite).
///
/// The FlutterFlow version was pure decoration: hardcoded "TN-01-AB-1234
/// Suresh (Driver) Chennai → Vellore" cards that never went away no matter
/// what the real data was. Now driven from real orders and vehicle_trips:
///   * "Awaiting Approval" = supervisor_status 'completed_pending', not
///     yet closed/cancelled — jobs the field team finished that the owner
///     hasn't closed out. A LIST, not a workflow: the approval action is
///     `🔒 Close Order` on Order Details, already built in Session 1.
///   * "Active Shifting" = orders mid-flow between booking and delivery
///     (see _activeStatuses for which values are real vs. legacy)
///   * "Upcoming" = confirmed / booked orders with move_date >= today
///   * "Vehicle Trip Log" = last 25 vehicle_trips for the org
/// Tap any card to open Order Details.
class OperationsPageWidget extends StatefulWidget {
  const OperationsPageWidget({super.key});

  static String routeName = 'OperationsPage';
  static String routePath = '/operations';

  @override
  State<OperationsPageWidget> createState() => _OperationsPageWidgetState();
}

class _OperationsPageWidgetState extends State<OperationsPageWidget>
    with RefreshOnPopMixin<OperationsPageWidget> {
  late OperationsPageModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();

  // Refresh-after-write fix (parity brief Part 1): re-run the load when a
  // pushed route (e.g. Order Details after an approve/reopen) is popped.
  @override
  void onPageRefresh() => _load();

  List<OrdersRow> _awaiting = [];
  List<OrdersRow> _orders = [];

  /// Crew names per order, from `order_staff` joined to `staff`.
  Map<String, List<String>> _crew = {};
  List<VehiclesRow> _vehicles = [];
  List<MaterialsRow> _lowStock = [];

  /// 0 = Today, 1 = Tomorrow (the handoff's segmented control).
  int _day = 0;
  bool _loading = true;

  /// supervisor_id -> staff name, and order_id -> balance due, both only
  /// populated for the (small) awaiting list.
  Map<String, String> _supervisorNames = {};
  Map<String, double> _awaitingBalances = {};

  /// What the supervisor spent on each awaiting job, and how many
  /// entries make it up.
  ///
  /// Arun, 3 Sept 2026: *"we cant simply approve what ever the
  /// supervisor update"*. The queue showed the money coming IN (balance
  /// due) and nothing about the money going OUT, so approving was a
  /// click-through: the one number a reviewer most needs to sanity-check
  /// — what this job was claimed to have cost — was only visible by
  /// opening the order.
  Map<String, ({double total, int count})> _awaitingSpend = {};

  /// How each awaiting job was completed, from `pod_records` — so an
  /// unsigned completion is visible IN THE ROW, not behind a tap. Arun,
  /// 18 Aug 2026: "The owner approving twenty jobs won't open each one."
  /// Maps order_id -> (completion_method, not_available_reason).
  Map<String, (String?, String?)> _awaitingPod = {};

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => OperationsPageModel());
    SchedulerBinding.instance.addPostFrameCallback((_) => _load());
    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        OrdersTable()
            .queryRows(queryFn: (q) => OrgScope.read(q).order('move_date')),
        OrderStaffTable().queryRows(queryFn: (q) => OrgScope.read(q)),
        StaffTable().queryRows(queryFn: (q) => OrgScope.read(q)),
        VehiclesTable().queryRows(queryFn: (q) => OrgScope.read(q)),
        MaterialsTable().queryRows(queryFn: (q) => OrgScope.read(q)),
      ]);
      _orders = (results[0] as List).cast<OrdersRow>();
      final names = {
        for (final st in (results[2] as List).cast<StaffRow>())
          if (st.id != null) st.id!: st.name
      };
      final crew = <String, List<String>>{};
      for (final r in (results[1] as List).cast<OrderStaffRow>()) {
        if (r.orderId == null) continue;
        crew.putIfAbsent(r.orderId!, () => []).add(names[r.staffId] ?? '');
      }
      _crew = crew;
      _vehicles = (results[3] as List).cast<VehiclesRow>();
      // Low stock is the vendor's own threshold; an item without one is
      // never flagged rather than judged against a number we made up.
      _lowStock = (results[4] as List)
          .cast<MaterialsRow>()
          .where((m) =>
              (m.minStock ?? 0) > 0 && (m.quantity ?? 0) <= m.minStock!)
          .toList();
      // Same filter as ApprovalQueue.awaitingFilter, applied client-side
      // because this page has the rows in hand already.
      _awaiting = _orders.where((o) {
        final st = (o.status ?? '').toLowerCase();
        return o.supervisorStatus == 'completed_pending' &&
            st != 'closed' &&
            st != 'cancelled';
      }).toList();
      await _loadAwaitingDetail();
      ApprovalQueue.instance.pendingCount.value = _awaiting.length;
    } catch (_) {}
    _loading = false;
    if (mounted) setState(() {});
  }

  /// Supervisor names + balance due for the awaiting cards only. Two
  /// bounded extra queries (the queue is a work list, not a full table),
  /// both skipped entirely when nothing is awaiting.
  Future<void> _loadAwaitingDetail() async {
    _supervisorNames = {};
    _awaitingBalances = {};
    _awaitingSpend = {};
    _awaitingPod = {};
    if (_awaiting.isEmpty) return;
    final orderIds = _awaiting.map((o) => o.id).whereType<String>().toList();

    // Balance due deliberately uses Close Order's OWN formula
    // (quote_total + non-cancelled addons - paid_total), not the
    // plain-amount one QuickPaymentSection uses. The whole point of
    // showing it here is that the owner sees the same number Close Order
    // will hard-warn about, so the queue can't set up a surprise at the
    // dialog. If those two formulas are ever reconciled, reconcile this
    // with _markComplete, not with QuickPaymentSection.
    final addonTotals = <String, double>{};
    if (orderIds.isNotEmpty) {
      try {
        final addonRows = await OrgScope.read(
                SupaFlow.client.from('addons').select('order_id,amount,status'))
            .inFilter('order_id', orderIds)
            .neq('status', 'cancelled');
        for (final r in addonRows) {
          final oid = r['order_id'] as String?;
          if (oid == null) continue;
          addonTotals[oid] =
              (addonTotals[oid] ?? 0) + (num.tryParse('${r['amount']}') ?? 0);
        }
      } catch (_) {}
    }
    // What the supervisor spent. Read from BOTH stores for the same
    // reason the order P&L does: entries made before 3 Sept 2026 live in
    // orders.field_expenses (jsonb) and everything since is a real
    // `expenses` row. Showing one would under-report the claim the owner
    // is being asked to approve.
    try {
      final expRows = await ExpensesTable().queryRows(
        queryFn: (q) => OrgScope.read(q).inFilter('order_id', orderIds),
      );
      for (final e in expRows) {
        final oid = e.orderId;
        if (oid == null) continue;
        final cur = _awaitingSpend[oid] ?? (total: 0.0, count: 0);
        _awaitingSpend[oid] =
            (total: cur.total + (e.amount ?? 0), count: cur.count + 1);
      }
    } catch (_) {}
    for (final o in _awaiting) {
      if (o.id == null) continue;
      final (fieldTotal, fieldCount) =
          sumFieldExpenses(o.data['field_expenses']);
      if (fieldTotal == 0 && fieldCount == 0) continue;
      final cur = _awaitingSpend[o.id!] ?? (total: 0.0, count: 0);
      _awaitingSpend[o.id!] =
          (total: cur.total + fieldTotal, count: cur.count + fieldCount);
    }

    // One bounded query for the whole queue — the completion method is
    // the difference between "done, signed" and "done, nobody signed",
    // which are different risks and must not look identical here.
    try {
      final podRows = await OrgScope.read(SupaFlow.client
              .from('pod_records')
              .select('order_id,completion_method,not_available_reason'))
          .inFilter('order_id', orderIds);
      for (final r in podRows) {
        final oid = r['order_id'] as String?;
        if (oid == null) continue;
        _awaitingPod[oid] = (
          r['completion_method'] as String?,
          r['not_available_reason'] as String?,
        );
      }
    } catch (_) {}

    for (final o in _awaiting) {
      if (o.id == null) continue;
      // quote_total falls back to amount for directly-booked orders —
      // must stay identical to _markComplete's own calculation, or this
      // queue would show ₹0 due on exactly the orders Close Order is
      // about to warn on. See order_pnl_section._revenueBase.
      final base =
          (o.quoteTotal ?? 0) != 0 ? (o.quoteTotal ?? 0) : (o.amount ?? 0);
      final revenueFinal = base + (addonTotals[o.id!] ?? 0);
      _awaitingBalances[o.id!] = revenueFinal - o.paidTotal;
    }

    final supIds =
        _awaiting.map((o) => o.supervisorId).whereType<String>().toSet();
    if (supIds.isNotEmpty) {
      try {
        final staffRows = await StaffTable().queryRows(
          queryFn: (q) => OrgScope.read(q).inFilter('id', supIds.toList()),
        );
        for (final s in staffRows) {
          if (s.id != null) _supervisorNames[s.id!] = s.name;
        }
      } catch (_) {}
    }
  }

  void _openOrder(OrdersRow o) {
    // Match orders page: mask customer/phone in the URL for supervisors on
    // completed orders (this page won't show completed orders, but the
    // masking helper still keeps it defensive).
    final hide = AppSession.instance.isSupervisorSession &&
        ['delivered', 'closed', 'done', 'completed']
            .contains((o.status ?? '').toLowerCase());
    context.pushNamed(
      OrderDetailPageWidget.routeName,
      queryParameters: {
        'orderId': serializeParam(o.id, ParamType.String),
        'orderCustomer': serializeParam(
            hide ? 'Customer (hidden)' : o.customer, ParamType.String),
        'orderPhone': serializeParam(hide ? null : o.phone, ParamType.String),
        'orderFromCity': serializeParam(o.fromCity, ParamType.String),
        'orderToCity': serializeParam(o.toCity, ParamType.String),
        'orderAmount': serializeParam(o.amount?.toString(), ParamType.String),
        'orderStatus': serializeParam(o.status, ParamType.String),
        'orderMoveDate':
            serializeParam(o.moveDateOrNull?.toString(), ParamType.String),
      }.withoutNulls,
    );
  }

  /// Awaiting-approval card. Richer than a job card on purpose: this is a
  /// decision queue, so it carries the three things the owner needs before
  /// tapping through — who ran the job, when they finished, and what is
  /// still owed.
  Widget _approvalCard(OrdersRow o) {
    final ng = NgPalette.of(context);
    final gold = NgPalette.of(context).amber;
    final balance = _awaitingBalances[o.id] ?? 0;
    final spend = _awaitingSpend[o.id];
    final supervisor = o.supervisorId == null
        ? null
        : _supervisorNames[o.supervisorId!];
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openOrder(o),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ng.s1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: gold.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${o.id} · ${o.customer}',
                      overflow: TextOverflow.ellipsis,
                      style: NgFonts.geist(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: ng.text)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('⏳ AWAITING',
                      style: NgFonts.geist(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: gold)),
                ),
              ],
            ),
            // Unsigned completions are called out IN THE ROW, with the
            // reason, so an owner working through twenty jobs can triage
            // without opening each one. A signed job gets a quiet tick;
            // an unsigned one gets an amber line naming why.
            if (_awaitingPod[o.id] != null) ...[
              const SizedBox(height: 6),
              Builder(builder: (context) {
                final (method, reason) = _awaitingPod[o.id]!;
                final unsigned = method == 'not_available';
                final colour = unsigned ? Colors.orange.shade800 : ng.green;
                return Row(
                  children: [
                    Icon(
                        unsigned
                            ? Icons.person_off_outlined
                            : Icons.draw_outlined,
                        size: 13,
                        color: colour),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        unsigned
                            ? 'Completed — ${kNotAvailableReasons[reason] ?? 'no signature'}'
                            : 'Completed — signed by customer',
                        overflow: TextOverflow.ellipsis,
                        style: NgFonts.geist(
                            fontSize: 11.5,
                            fontWeight:
                                unsigned ? FontWeight.w700 : FontWeight.w500,
                            color: colour),
                      ),
                    ),
                  ],
                );
              }),
            ],
            const SizedBox(height: 4),
            Text(
              '${o.fromCity ?? '—'} to ${o.toCity ?? '—'}',
              style:
                  NgFonts.geist(fontSize: 11.5, color: ng.mute),
            ),
            const SizedBox(height: 2),
            Text(
              [
                'Supervisor: ${supervisor ?? '—'}',
                if (o.jobEndTime != null)
                  'Finished ${dateTimeFormat('d MMM, h:mm a', o.jobEndTime)}',
              ].join('  ·  '),
              style:
                  NgFonts.geist(fontSize: 11.5, color: ng.mute),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Balance due',
                    style: NgFonts.geist(
                        fontSize: 11.5, color: ng.mute)),
                Text(
                  '₹${balance.toStringAsFixed(0)}',
                  style: NgFonts.geist(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    // Non-zero balance is the thing worth chasing before
                    // closing — Close Order will hard-warn on exactly this.
                    color: balance > 0 ? ng.red : ng.green,
                  ),
                ),
              ],
            ),
            // What the supervisor CLAIMED to have spent, on the card, so
            // approving is a review rather than a click-through. Arun,
            // 3 Sept 2026: "we cant simply approve what ever the
            // supervisor update".
            if (spend != null) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      'Spent by supervisor  ·  '
                      '${spend.count} item${spend.count == 1 ? '' : 's'}',
                      style: NgFonts.geist(
                          fontSize: 11.5, color: ng.mute)),
                  Text('₹${spend.total.toStringAsFixed(0)}',
                      style: NgFonts.geist(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: ng.amber)),
                ],
              ),
            ] else ...[
              const SizedBox(height: 4),
              // Stated, not omitted. "Nothing claimed" is itself worth
              // seeing on a job that ran all day - a blank row would read
              // as "not loaded" instead.
              Text('No expenses claimed on this job',
                  style: NgFonts.geist(
                      fontSize: 11.5, color: ng.mute)),
            ],
          ],
        ),
      ),
    );
  }

  // ---- Handoff layout ("OPS"): Today/Tomorrow, three tiles, Needs
  // attention, Jobs, Fleet. The awaiting-approval queue stays, as its own
  // section under the alerts, because it is the owner's decision queue.

  bool _onDay(OrdersRow o, int dayOffset) {
    final d = o.moveDateOrNull;
    if (d == null) return false;
    final n = DateTime.now().add(Duration(days: dayOffset));
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  bool _isLive(OrdersRow o) {
    final st = (o.status ?? '').toLowerCase();
    return !['cancelled', 'closed', 'delivered', 'done', 'completed']
        .contains(st);
  }

  List<OrdersRow> _jobsFor(int dayOffset) => _orders
      .where((o) => _isLive(o) && _onDay(o, dayOffset))
      .toList();

  Widget _tile(IconData icon, Color color, String value, String of,
      String label) {
    final c = NgPalette.of(context);
    return NgCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: NgFonts.geist(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.44,
                      color: c.text)),
              if (of.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(of, style: NgFonts.geist(fontSize: 13, color: c.faint)),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
        ],
      ),
    );
  }

  /// One row of "Needs attention": tinted icon, title and detail, and the
  /// action that resolves it.
  Widget _alertRow({
    required IconData icon,
    required NgStatus tone,
    required String title,
    required String sub,
    required String action,
    required VoidCallback onAction,
    bool primary = false,
  }) {
    final c = NgPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          NgIconTile(icon: icon, status: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: c.text)),
                const SizedBox(height: 2),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: Material(
              color: primary ? c.accBtn : c.s2,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onAction,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    child: Text(action,
                        style: NgFonts.geist(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: primary ? NgPalette.onAcc : c.text)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _alerts(List<OrdersRow> jobs) {
    final l = AppLocalizations.of(context);
    final out = <Widget>[];
    for (final o in jobs.where((o) => (_crew[o.id] ?? const []).isEmpty)) {
      out.add(_alertRow(
        icon: Icons.group_add_outlined,
        tone: NgStatus.red,
        title: l.ngOpsNoCrew(o.customer),
        sub: '${o.fromCity ?? '-'} → ${o.toCity ?? '-'}',
        action: l.ngOpsAssign,
        primary: true,
        onAction: () => _openOrder(o),
      ));
    }
    final soon = DateTime.now().add(const Duration(days: 30));
    for (final v in _vehicles) {
      final exp = v.insuranceExpiry;
      if (exp == null || exp.isAfter(soon)) continue;
      final days = exp.difference(DateTime.now()).inDays;
      out.add(_alertRow(
        icon: Icons.shield_outlined,
        tone: days < 0 ? NgStatus.red : NgStatus.amber,
        title: days < 0
            ? l.ngOpsInsuranceExpired
            : l.ngOpsInsuranceExpires(days),
        sub: [v.regNo, v.vehicleType ?? ''].where((x) => x.isNotEmpty).join(' · '),
        action: l.ngOpsView,
        onAction: () => openModule(context, 'FleetPage'),
      ));
    }
    for (final m in _lowStock) {
      out.add(_alertRow(
        icon: Icons.inventory_2_outlined,
        tone: NgStatus.amber,
        title: l.ngOpsLowStock(m.name),
        sub: l.ngOpsStockLeft(
            '${(m.quantity ?? 0).toStringAsFixed(0)} ${m.unit ?? ''}'.trim()),
        action: l.ngOpsReorder,
        onAction: () => openModule(context, 'MaterialsPage'),
      ));
    }
    return out;
  }

  Widget _jobCard(OrdersRow o) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final idx = orderStageIndex(o.trackingStatus, o.status);
    final color = c.status(orderStageTone(idx)).fg;
    final crew = _crew[o.id] ?? const <String>[];
    final svc = (o.service ?? '').trim();
    final start = o.jobStartTime;
    return NgCard(
      radius: 20,
      onTap: () => _openOrder(o),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    '${orderStageLabel(kOrderStages[idx])} · ${idx + 1}/${kOrderStages.length}',
                    style: NgFonts.geist(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ),
              if (start != null)
                Text(DateFormat('h:mm a').format(start.toLocal()),
                    style: NgFonts.mono(fontSize: 12.5, color: c.soft)),
            ],
          ),
          const SizedBox(height: 12),
          Text(o.customer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NgFonts.geist(
                  fontSize: 15.5, fontWeight: FontWeight.w600, color: c.text)),
          const SizedBox(height: 2),
          Text(
            '${o.fromCity ?? '-'} → ${o.toCity ?? '-'}${svc.isEmpty ? '' : ' · $svc'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NgFonts.geist(fontSize: 12.5, color: c.mute),
          ),
          const SizedBox(height: 12),
          NgStageBar(
              done: idx + 1, total: kOrderStages.length, color: color),
          const SizedBox(height: 12),
          if (crew.isEmpty)
            InkWell(
              onTap: () => _openOrder(o),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.red),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.group_add_outlined, size: 18, color: c.red),
                    const SizedBox(width: 6),
                    Text(l.ngOpsAssignCrew,
                        style: NgFonts.geist(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: c.red)),
                  ],
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.w06))),
              child: Row(
                children: [
                  SizedBox(
                    width: 26.0 + 18.0 * (crew.take(3).length - 1),
                    height: 26,
                    child: Stack(
                      children: [
                        for (var i = 0; i < crew.take(3).length; i++)
                          Positioned(
                            left: 18.0 * i,
                            child: Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: c.s3,
                                shape: BoxShape.circle,
                                border: Border.all(color: c.s1, width: 2),
                              ),
                              child: Text(
                                  crew[i].isEmpty
                                      ? '?'
                                      : crew[i].characters.first.toUpperCase(),
                                  style: NgFonts.geist(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: c.soft)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      crew.length == 1
                          ? crew.first
                          : '${crew.first} +${crew.length - 1}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NgFonts.geist(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: c.text),
                    ),
                  ),
                  if ((o.vehicleNo ?? '').isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.s2,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(o.vehicleNo!,
                          style: NgFonts.mono(fontSize: 11.5, color: c.soft)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  ({String label, NgStatus tone}) _vehicleState(VehiclesRow v, Set<String> busy) {
    final l = AppLocalizations.of(context);
    final st = (v.status ?? '').toLowerCase();
    if (st.contains('service') || st.contains('repair')) {
      return (label: l.ngOpsInService, tone: NgStatus.red);
    }
    if (busy.contains(v.regNo.replaceAll(' ', '').toUpperCase())) {
      return (label: l.ngOpsOnJob, tone: NgStatus.amber);
    }
    return (label: l.ngOpsFree, tone: NgStatus.green);
  }

  Widget _fleetSection(List<OrdersRow> jobs) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final busy = {
      for (final o in jobs)
        if ((o.vehicleNo ?? '').isNotEmpty)
          o.vehicleNo!.replaceAll(' ', '').toUpperCase()
    };
    final free =
        _vehicles.where((v) => _vehicleState(v, busy).tone == NgStatus.green);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NgSectionHeader(l.ngOpsFleet,
            trailing: l.ngOpsFleetSummary(free.length, _vehicles.length),
            onTrailing: () => openModule(context, 'FleetPage')),
        const SizedBox(height: 10),
        NgCardList(children: [
          for (final v in _vehicles)
            Builder(builder: (context) {
              final s = _vehicleState(v, busy);
              final col = c.status(s.tone).fg;
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.local_shipping_outlined,
                        size: 20, color: c.faint),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(v.regNo,
                              style: NgFonts.mono(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: c.text)),
                          if ((v.vehicleType ?? '').isNotEmpty)
                            Text(v.vehicleType!,
                                style: NgFonts.geist(
                                    fontSize: 12, color: c.mute)),
                        ],
                      ),
                    ),
                    Container(
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(color: col, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(s.label,
                        style: NgFonts.geist(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: col)),
                  ],
                ),
              );
            }),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final jobs = _jobsFor(_day);
    final crewed = jobs.where((o) => (_crew[o.id] ?? const []).isNotEmpty);
    final busy = {
      for (final o in jobs)
        if ((o.vehicleNo ?? '').isNotEmpty)
          o.vehicleNo!.replaceAll(' ', '').toUpperCase()
    };
    final freeVehicles = _vehicles
        .where((v) => _vehicleState(v, busy).tone == NgStatus.green)
        .length;
    final alerts = _alerts(jobs);
    final sections = <Widget>[
      NgScreenTitle(
        l.ngOpsTitle,
        large: true,
        action: NgPrimaryButton(
          compact: true,
          icon: Icons.add_rounded,
          label: l.ngOpsNewTrip,
          onPressed: () => openModule(context, 'TripsPage'),
        ),
      ),
      NgSegmented(
        labels: [l.ngToday, l.ngTomorrow],
        counts: [_jobsFor(0).length, _jobsFor(1).length],
        selected: _day,
        onSelect: (i) => setState(() => _day = i),
      ),
      Row(
        children: [
          Expanded(
              child: _tile(Icons.local_shipping_outlined, c.acc,
                  '${jobs.length}', '', l.ngTodayMoves)),
          const SizedBox(width: 8),
          Expanded(
              child: _tile(Icons.groups_outlined, c.blue, '${crewed.length}',
                  '/ ${jobs.length}', l.ngOpsCrewsOut)),
          const SizedBox(width: 8),
          Expanded(
              child: _tile(Icons.fire_truck_outlined, c.green,
                  '$freeVehicles', '/ ${_vehicles.length}', l.ngOpsVehiclesFree)),
        ],
      ),
      if (alerts.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NgSectionHeader(l.ngOpsAttention, trailing: '${alerts.length}'),
            const SizedBox(height: 10),
            NgCardList(children: alerts),
          ],
        ),
      // Discovery-only queue: finished jobs waiting on the owner. Hidden
      // when empty, as before.
      if (_awaiting.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NgSectionHeader(l.ngOpsAwaiting, trailing: '${_awaiting.length}'),
            const SizedBox(height: 10),
            ..._awaiting.map(_approvalCard),
          ],
        ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NgSectionHeader(l.ngOpsJobs),
          const SizedBox(height: 10),
          if (jobs.isEmpty)
            NgCard(
              child: Text(l.ngOpsNoJobs,
                  textAlign: TextAlign.center,
                  style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
            )
          else
            for (var i = 0; i < jobs.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _jobCard(jobs[i]),
            ],
        ],
      ),
      if (_vehicles.isNotEmpty) _fleetSection(jobs),
    ];
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: c.bg,
      appBar: NgTopBar(onRefresh: _load),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  for (var i = 0; i < sections.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    sections[i],
                  ],
                ],
              ),
            ),
    );
  }
}
