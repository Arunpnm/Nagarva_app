import '/app_session.dart';
import '/backend/approval_queue.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/keyboard_scroll_view.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
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
  List<OrdersRow> _active = [];
  List<OrdersRow> _upcoming = [];
  List<VehicleTripsRow> _trips = [];
  bool _loading = true;

  /// supervisor_id -> staff name, and order_id -> balance due, both only
  /// populated for the (small) awaiting list.
  Map<String, String> _supervisorNames = {};
  Map<String, double> _awaitingBalances = {};

  // Statuses this app ACTUALLY writes today (grep the writers before
  // editing this set): 'booked'/'pending' (new_order_page + Duplicate),
  // 'team_assigned' (order_crew_section._assignSupervisor), 'transit'
  // (supervisor_job_page._startShifting), 'delivered'
  // (._verifyAndComplete), 'closed' (Mark Order Complete), 'cancelled'.
  //
  // 'transit' was missing here, which is a real bug, not a cosmetic one:
  // it is the ONE value that means "crew is actively shifting right now",
  // and it appears in neither this set nor _upcomingStatuses — so an
  // in-progress job written by the supervisor flow was invisible on this
  // board entirely, in both sections.
  //
  // 'accepted'/'shifting_started'/'in_transit' are reference-app names
  // that nothing in this codebase writes. Kept (harmless, and they'd
  // match if legacy rows carry them) but deliberately NOT relied on.
  static const _activeStatuses = {
    'team_assigned',
    'transit',
    'accepted',
    'shifting_started',
    'in_transit',
  };
  static const _upcomingStatuses = {'confirmed', 'booked', 'pending'};

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
        VehicleTripsTable().queryRows(
            queryFn: (q) => OrgScope.read(q).order('trip_date').limit(25)),
      ]);
      final orders = (results[0] as List).cast<OrdersRow>();
      _trips = (results[1] as List).cast<VehicleTripsRow>();
      final today = DateTime.now();
      // Filtered from the same already-fetched list rather than a second
      // query — same filter as ApprovalQueue.awaitingFilter, applied
      // client-side here because this page has the rows in hand already.
      _awaiting = orders.where((o) {
        final st = (o.status ?? '').toLowerCase();
        return o.supervisorStatus == 'completed_pending' &&
            st != 'closed' &&
            st != 'cancelled';
      }).toList();
      _active = orders
          .where(
              (o) => _activeStatuses.contains((o.status ?? '').toLowerCase()))
          .toList();
      _upcoming = orders
          .where((o) =>
              _upcomingStatuses.contains((o.status ?? '').toLowerCase()) &&
              (o.moveDateOrNull?.isAfter(
                      DateTime(today.year, today.month, today.day - 1)) ??
                  false))
          .toList();
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
    if (_awaiting.isEmpty) return;
    final orderIds = _awaiting.map((o) => o.id).whereType<String>().toList();

    // Balance due deliberately uses Close Order's OWN formula
    // (quote_total + non-cancelled addons - paid_total), not the
    // amount/advance_paid one QuickPaymentSection uses. The whole point of
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

  Color _statusColor(String st) {
    switch (st.toLowerCase()) {
      case 'transit':
      case 'in_transit':
        return const Color(0xFF1565C0);
      case 'shifting_started':
        return const Color(0xFFE6A400);
      case 'accepted':
      case 'team_assigned':
        return const Color(0xFF2E7D32);
      case 'confirmed':
      case 'booked':
      case 'pending':
        return FlutterFlowTheme.of(context).primary;
      default:
        return FlutterFlowTheme.of(context).secondaryText;
    }
  }

  String _prettyStatus(String? st) =>
      (st ?? '—').replaceAll('_', ' ').toUpperCase();

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

  Widget _sectionTitle(String s) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(s,
          style: GoogleFonts.interTight(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: theme.primaryText)),
    );
  }

  Widget _orderCard(OrdersRow o) {
    final theme = FlutterFlowTheme.of(context);
    final st = _prettyStatus(o.status);
    final color = _statusColor(o.status ?? '');
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openOrder(o),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(o.customer,
                      style: GoogleFonts.interTight(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: theme.primaryText)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(st,
                      style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: color)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                '${o.fromCity ?? '—'} to ${o.toCity ?? '—'}',
                'Move: ${dateTimeFormat('d MMM', o.moveDateOrNull)}',
                if ((o.phone ?? '').isNotEmpty) o.phone!,
              ].join('  ·  '),
              style:
                  GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
            ),
          ],
        ),
      ),
    );
  }

  /// Awaiting-approval card. Richer than _orderCard on purpose: this is a
  /// decision queue, so it carries the three things the owner needs before
  /// tapping through — who ran the job, when they finished, and what is
  /// still owed.
  Widget _approvalCard(OrdersRow o) {
    final theme = FlutterFlowTheme.of(context);
    const gold = Color(0xFFE0A82E);
    final balance = _awaitingBalances[o.id] ?? 0;
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
          color: theme.secondaryBackground,
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
                      style: GoogleFonts.interTight(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: theme.primaryText)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('⏳ AWAITING',
                      style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: gold)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${o.fromCity ?? '—'} to ${o.toCity ?? '—'}',
              style:
                  GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
            ),
            const SizedBox(height: 2),
            Text(
              [
                'Supervisor: ${supervisor ?? '—'}',
                if (o.jobEndTime != null)
                  'Finished ${dateTimeFormat('d MMM, h:mm a', o.jobEndTime)}',
              ].join('  ·  '),
              style:
                  GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Balance due',
                    style: GoogleFonts.inter(
                        fontSize: 11.5, color: theme.secondaryText)),
                Text(
                  '₹${balance.toStringAsFixed(0)}',
                  style: GoogleFonts.interTight(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    // Non-zero balance is the thing worth chasing before
                    // closing — Close Order will hard-warn on exactly this.
                    color: balance > 0 ? theme.error : theme.success,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tripCard(VehicleTripsRow t) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.local_shipping, size: 18, color: theme.secondaryText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${t.vehicleNo ?? '—'} · ${t.driverName ?? '—'}',
                  style: GoogleFonts.interTight(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: theme.primaryText),
                ),
                Text(
                  '${t.fromLoc ?? '—'} to ${t.toLoc ?? '—'}'
                  '${t.tripDate == null ? '' : ' · ${t.tripDate}'}'
                  '${(t.tripType ?? '').isEmpty ? '' : ' · ${t.tripType}'}',
                  style: GoogleFonts.inter(
                      fontSize: 11.5, color: theme.secondaryText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
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
          title: Text('Operations',
              style: theme.titleLarge.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                fontSize: 22.0,
                letterSpacing: 0.0,
              )),
          centerTitle: true,
          elevation: 0.0,
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: Icon(Icons.refresh, color: theme.primaryText),
              onPressed: _load,
            ),
          ],
        ),
        body: SafeArea(
          top: true,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : KeyboardScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Discovery-only queue, above Active Shifting: these
                      // are finished jobs waiting on the owner. Hidden
                      // entirely when empty — an always-visible "nothing
                      // awaiting" header would be noise on the common day.
                      if (_awaiting.isNotEmpty) ...[
                        _sectionTitle(
                            'Awaiting Approval (${_awaiting.length})'),
                        ..._awaiting.map(_approvalCard),
                      ],
                      _sectionTitle('Active Shifting (${_active.length})'),
                      if (_active.isEmpty)
                        Text('No jobs currently in progress.',
                            style: GoogleFonts.inter(
                                fontSize: 12.5, color: theme.secondaryText))
                      else
                        ..._active.map(_orderCard),
                      _sectionTitle('Upcoming (${_upcoming.length})'),
                      if (_upcoming.isEmpty)
                        Text('No upcoming orders.',
                            style: GoogleFonts.inter(
                                fontSize: 12.5, color: theme.secondaryText))
                      else
                        ..._upcoming.map(_orderCard),
                      _sectionTitle('Vehicle Trip Log (${_trips.length})'),
                      if (_trips.isEmpty)
                        Text(
                          'No trips logged yet. Use "Log New Trip" to '
                          'record vehicle movements (fuel, tolls, driver bata).',
                          style: GoogleFonts.inter(
                              fontSize: 12.5, color: theme.secondaryText),
                        )
                      else
                        ..._trips.map(_tripCard),
                      const SizedBox(height: 8),
                      FFButtonWidget(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Trip logging form is coming in Week 4 — '
                                  'add via Order Details for now.'),
                            ),
                          );
                        },
                        text: 'Log New Trip',
                        icon: const Icon(Icons.add_road, size: 18),
                        options: FFButtonOptions(
                          height: 46,
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          iconPadding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          color: theme.primary,
                          iconColor: theme.primaryBackground,
                          textStyle: TextStyle(color: theme.primaryBackground),
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
