import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import '/backend/detail_navigation.dart';
import '/backend/order_stages.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'orders_page_model.dart';
export 'orders_page_model.dart';

/// Order management with status filter tabs.
class OrdersPageWidget extends StatefulWidget {
  const OrdersPageWidget({super.key});

  static String routeName = 'OrdersPage';
  static String routePath = '/orders';

  @override
  State<OrdersPageWidget> createState() => _OrdersPageWidgetState();
}

class _OrdersPageWidgetState extends State<OrdersPageWidget>
    with RefreshOnPopMixin<OrdersPageWidget> {
  late OrdersPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => OrdersPageModel());

    // On page load action.
    SchedulerBinding.instance.addPostFrameCallback((_) => _loadOrders());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  // Refresh-after-write fix (parity brief Part 1): re-run on load and every
  // time a pushed route (New/Edit Order, Order Detail) is popped back to.
  @override
  void onPageRefresh() => _loadOrders();

  Future<void> _loadOrders() async {
    // Phase 1 multi-tenancy pass: every tab below was unscoped and would
    // list orders across all orgs. Requires supabase/phase1_add_org_id.sql
    // to be run first (see that file's header).
    _model.allOut = await OrdersTable().queryRows(
      queryFn: (q) => OrgScope.read(q).order('created_at'),
    );
    _model.ordersList = (_model.allOut ?? []).toList().cast<OrdersRow>();
    safeSetState(() {});
    // The five per-status queries that used to follow (pending/confirmed/
    // transit/done/cancelled) fed the four duplicated chip blocks that
    // were removed — filtering is client-side on ordersList now, so one
    // query replaces six.
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  /// Privacy: supervisors must not see customer identity on completed
  /// orders (post-job contact / lead-poaching prevention). Owner/vendor
  /// sessions are unaffected.
  bool _hideCustomerFor(OrdersRow o) {
    if (!AppSession.instance.isSupervisorSession) return false;
    final st = (o.status ?? '').toLowerCase();
    return st == 'delivered' ||
        st == 'done' ||
        st == 'completed' ||
        st == 'closed';
  }

  static const _tabs = ['All', 'Pending', 'Completed', 'Cancelled'];

  static String _tabLabel(BuildContext context, String tab) {
    final l = AppLocalizations.of(context);
    return switch (tab) {
      'Pending' => l.ngTabPending,
      'Completed' => l.ngTabCompleted,
      'Cancelled' => l.ngTabCancelled,
      _ => l.ngTabAll,
    };
  }

  /// Filter by the top tab. Statuses live lowercase in the DB
  /// (pending/confirmed/transit/delivered|done/cancelled). Completed =
  /// delivered/done/completed/closed — 'closed' is Mark Order Complete's
  /// financial close (Order Details Session 1, item 5) and must land here,
  /// not fall through to Pending by omission. Cancelled = cancelled;
  /// Pending = everything still in progress.
  static bool _inTab(OrdersRow o, String tab) {
    final st = (o.status ?? '').toLowerCase();
    final done = st == 'delivered' ||
        st == 'done' ||
        st == 'completed' ||
        st == 'closed';
    switch (tab) {
      case 'Completed':
        return done;
      case 'Cancelled':
        return st == 'cancelled';
      case 'Pending':
        return !done && st != 'cancelled';
      default:
        return true;
    }
  }

  /// The redesign shows Orders as a schedule grouped by move day. Upcoming
  /// days run soonest first; on the Completed tab the most recent day
  /// leads instead, since that is the one being looked for. Orders with no
  /// move date sit in their own group at the end.
  List<({String title, String sub, Color dot, List<OrdersRow> items})>
      _groups(BuildContext context, List<OrdersRow> orders) {
    final c = NgPalette.of(context);
    final today = DateTime.now();
    final t0 = DateTime(today.year, today.month, today.day);
    final dated = orders.where((o) => o.moveDateOrNull != null).toList()
      ..sort((a, b) => _model.selectedTab == 'Completed'
          ? b.moveDateOrNull!.compareTo(a.moveDateOrNull!)
          : a.moveDateOrNull!.compareTo(b.moveDateOrNull!));
    final out = <({String title, String sub, Color dot, List<OrdersRow> items})>[];
    DateTime? cur;
    for (final o in dated) {
      final d = o.moveDateOrNull!;
      final day = DateTime(d.year, d.month, d.day);
      if (cur == null || day != cur) {
        cur = day;
        final diff = day.difference(t0).inDays;
        final l = AppLocalizations.of(context);
        final title = diff == 0
            ? l.ngToday
            : diff == 1
                ? l.ngTomorrow
                : diff == -1
                    ? l.ngYesterday
                    : DateFormat('EEE, d MMM').format(day);
        out.add((
          title: title,
          sub: diff.abs() <= 1 ? DateFormat('d MMM').format(day) : '',
          dot: diff == 0 ? c.acc : (diff > 0 ? c.blue : c.faint),
          items: [],
        ));
      }
      out.last.items.add(o);
    }
    final undated = orders.where((o) => o.moveDateOrNull == null).toList();
    if (undated.isNotEmpty) {
      out.add((
        title: AppLocalizations.of(context).ngNoMoveDate,
        sub: '',
        dot: c.faint,
        items: undated,
      ));
    }
    return out;
  }

  ({String label, Color color}) _payLook(
      AppLocalizations l, NgPalette c, OrdersRow o) {
    switch ((o.paymentStatus ?? '').toLowerCase()) {
      case 'paid':
        return (label: l.ngPaid, color: c.green);
      case 'partial':
        return (label: l.ngPartPaid, color: c.amber);
      default:
        return (label: l.ngDue, color: c.red);
    }
  }

  Widget _orderCard(BuildContext context, OrdersRow o) {
    final c = NgPalette.of(context);
    final hidden = _hideCustomerFor(o);
    final st = (o.status ?? '').toLowerCase();
    final cancelled = st == 'cancelled';
    final idx = orderStageIndex(o.trackingStatus, o.status);
    final stageColor =
        cancelled ? c.red : c.status(orderStageTone(idx)).fg;
    final l = AppLocalizations.of(context);
    final stageLabel =
        cancelled ? l.ngTabCancelled : orderStageLabel(kOrderStages[idx]);
    final pay = _payLook(l, c, o);
    final svc = (o.service ?? '').trim();
    return Material(
      color: c.s1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NgRadius.tile),
        side: BorderSide(color: c.w06),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openOrderDetail(context, o, hideCustomer: hidden),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: stageColor, width: 3)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hidden ? 'Customer (hidden)' : o.customer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NgFonts.geist(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    stageLabel,
                    style: NgFonts.geist(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: stageColor),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${o.fromCity ?? '-'} → ${o.toCity ?? '-'}${svc.isEmpty ? '' : ' · $svc'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NgFonts.geist(fontSize: 12.5, color: c.mute),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      functions.inrFormat(o.amount ?? 0)!,
                      style: NgFonts.geist(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.text),
                    ),
                  ),
                  if (!cancelled) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(color: pay.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      pay.label,
                      style: NgFonts.geist(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: pay.color),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final orders =
        _model.ordersList
        .where((o) => _inTab(o, _model.selectedTab ?? 'All'))
        .toList();
    final groups = _groups(context, orders);
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: c.bg,
        // Redesign: shared top bar; "new order" moves from the FAB into
        // the screen header beside a calendar shortcut.
        appBar: const NgTopBar(),
        body: RefreshIndicator(
          onRefresh: _loadOrders,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              NgScreenTitle(
                AppLocalizations.of(context).orders,
                action: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NgHeaderButton(
                      onTap: () =>
                          context.pushNamed(CalendarPageWidget.routeName),
                      child: Icon(Icons.calendar_month_rounded,
                          size: 20, color: c.soft),
                    ),
                    const SizedBox(width: 6),
                    NgPrimaryButton(
                      compact: true,
                      icon: Icons.add_rounded,
                      label: AppLocalizations.of(context).ngNewOrder,
                      onPressed: () =>
                          context.pushNamed(NewOrderPageWidget.routeName),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              NgChipRow(
                edge: 0,
                chips: [
                  for (final tab in _tabs)
                    NgChip(
                      // `tab` stays the English state key; only the
                      // label is localised.
                      label: _tabLabel(context, tab),
                      count: _model.ordersList
                          .where((o) => _inTab(o, tab))
                          .length,
                      selected: _model.selectedTab == tab,
                      onTap: () =>
                          safeSetState(() => _model.selectedTab = tab),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (orders.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(Icons.assignment_outlined, size: 42, color: c.mute),
                      const SizedBox(height: 12),
                      Text(
                        AppLocalizations.of(context).ngNoOrdersHere,
                        style: NgFonts.geist(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: c.text),
                      ),
                    ],
                  ),
                )
              else
                for (final g in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: g.dot, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          g.title,
                          style: NgFonts.geist(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.text),
                        ),
                        if (g.sub.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(g.sub,
                              style:
                                  NgFonts.geist(fontSize: 13, color: c.faint)),
                        ],
                        const Spacer(),
                        Text('${g.items.length}',
                            style: NgFonts.mono(fontSize: 12, color: c.faint)),
                      ],
                    ),
                  ),
                  for (var i = 0; i < g.items.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _orderCard(context, g.items[i]),
                  ],
                  const SizedBox(height: 16),
                ],
            ],
          ),
        ),
      ),
    );
  }
}
