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

  /// Handoff tabs: Active, Done, Cancelled, All. The keys stay English
  /// state; only labels are localised.
  static const _tabs = ['Active', 'Completed', 'Cancelled', 'All'];

  static String _tabLabel(BuildContext context, String tab) {
    final l = AppLocalizations.of(context);
    return switch (tab) {
      'Active' => l.active,
      'Completed' => l.ngTabDone,
      'Cancelled' => l.ngTabCancelled,
      _ => l.ngTabAll,
    };
  }

  static bool _isDone(OrdersRow o) {
    final st = (o.status ?? '').toLowerCase();
    return st == 'delivered' ||
        st == 'done' ||
        st == 'completed' ||
        st == 'closed';
  }

  static bool _inTab(OrdersRow o, String tab) {
    final st = (o.status ?? '').toLowerCase();
    switch (tab) {
      case 'Completed':
        return _isDone(o);
      case 'Cancelled':
        return st == 'cancelled';
      case 'Active':
        return !_isDone(o) && st != 'cancelled';
      default:
        return true;
    }
  }

  /// Soonest move first while work is open; most recent first once done.
  List<OrdersRow> _sorted(List<OrdersRow> rows, String tab) {
    final far = DateTime(9999);
    final out = rows.toList()
      ..sort((a, b) {
        final da = a.moveDateOrNull ?? far, db = b.moveDateOrNull ?? far;
        return tab == 'Active' ? da.compareTo(db) : db.compareTo(da);
      });
    return out;
  }

  ({String label, NgStatus tone}) _payLook(
      AppLocalizations l, NgPalette c, OrdersRow o) {
    switch ((o.paymentStatus ?? '').toLowerCase()) {
      case 'paid':
        return (label: l.ngPaid, tone: NgStatus.green);
      case 'partial':
        return (label: l.ngPartPaid, tone: NgStatus.amber);
      default:
        return (label: l.ngDue, tone: NgStatus.red);
    }
  }

  /// The handoff's order card: number and date, customer and route, the
  /// six-step stage bar with its label and the service, then the amount
  /// and a payment pill under a hairline.
  Widget _orderCard(BuildContext context, OrdersRow o) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final hidden = _hideCustomerFor(o);
    final cancelled = (o.status ?? '').toLowerCase() == 'cancelled';
    final idx = orderStageIndex(o.trackingStatus, o.status);
    final stageColor = cancelled ? c.red : c.status(orderStageTone(idx)).fg;
    final stageLabel = cancelled
        ? l.ngTabCancelled
        : '${orderStageLabel(kOrderStages[idx])} · ${idx + 1}/${kOrderStages.length}';
    final pay = _payLook(l, c, o);
    final svc = (o.service ?? '').trim();
    final total = (o.quoteTotal ?? 0) > 0 ? o.quoteTotal! : (o.amount ?? 0);
    return NgCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      onTap: () => openOrderDetail(context, o, hideCustomer: hidden),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(o.id ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.mono(fontSize: 12, color: c.faint)),
              ),
              if (o.moveDateOrNull != null) ...[
                Icon(Icons.event_outlined, size: 16, color: c.mute),
                const SizedBox(width: 5),
                Text(DateFormat('d MMM').format(o.moveDateOrNull!),
                    style: NgFonts.geist(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: c.soft)),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Text(
            hidden ? 'Customer (hidden)' : o.customer,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NgFonts.geist(
                fontSize: 16, fontWeight: FontWeight.w600, color: c.text),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Flexible(
                child: Text(o.fromCity ?? '-',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(fontSize: 13, color: c.mute)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child:
                    Icon(Icons.arrow_forward_rounded, size: 15, color: c.faint),
              ),
              Flexible(
                child: Text(o.toCity ?? '-',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(fontSize: 13, color: c.mute)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          NgStageBar(
              done: cancelled ? 0 : idx + 1,
              total: kOrderStages.length,
              color: stageColor),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: Text(stageLabel,
                    style: NgFonts.geist(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: stageColor)),
              ),
              if (svc.isNotEmpty)
                Text(svc, style: NgFonts.geist(fontSize: 12.5, color: c.faint)),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration:
                BoxDecoration(border: Border(top: BorderSide(color: c.w06))),
            child: Row(
              children: [
                Expanded(
                  child: Text(functions.inrFull(total),
                      style: NgFonts.geist(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.17,
                          color: c.text)),
                ),
                if (!cancelled) NgPill(pay.label, status: pay.tone),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final tab = _tabs.contains(_model.selectedTab)
        ? _model.selectedTab!
        : 'Active';
    final orders = _sorted(
        _model.ordersList.where((o) => _inTab(o, tab)).toList(), tab);
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
                large: true,
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
              NgSegmented(
                labels: [for (final t in _tabs) _tabLabel(context, t)],
                counts: [
                  for (final t in _tabs)
                    _model.ordersList.where((o) => _inTab(o, t)).length,
                ],
                selected: _tabs.indexOf(tab),
                onSelect: (i) =>
                    safeSetState(() => _model.selectedTab = _tabs[i]),
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
                for (var i = 0; i < orders.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  _orderCard(context, orders[i]),
                ],
            ],
          ),
        ),
      ),
    );
  }
}
