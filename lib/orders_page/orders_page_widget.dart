import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import '/components/keyboard_scroll_view.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
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

  /// Top filter tab (All / Pending / Completed / Cancelled). These four
  /// were static FlutterFlow decoration with no onTap — now wired to
  /// _model.selectedTab and the live list below filters accordingly.
  /// (The four duplicated non-clickable chip blocks and the hardcoded
  /// ORD-001 placeholder cards that used to follow the list were removed
  /// in the same pass — the page went from 12,696 to ~800 lines.)
  Widget _topTab(String label) {
    final selected = _model.selectedTab == label;
    final theme = FlutterFlowTheme.of(context);
    return Flexible(
      flex: 1,
      child: InkWell(
        splashColor: Colors.transparent,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: () => safeSetState(() => _model.selectedTab = label),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: selected ? theme.primary : theme.secondaryBackground,
            borderRadius: BorderRadius.circular(20.0),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(0.0, 10.0, 0.0, 10.0),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.labelMedium.override(
                font: GoogleFonts.inter(),
                color: selected ? theme.primaryBackground : theme.primaryText,
                letterSpacing: 0.0,
              ),
            ),
          ),
        ),
      ),
    );
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
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            context.pushNamed(NewOrderPageWidget.routeName);
          },
          backgroundColor: FlutterFlowTheme.of(context).primary,
          tooltip: 'New Order',
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          automaticallyImplyLeading: true,
          title: Text(
            AppLocalizations.of(context).orders,
            style: FlutterFlowTheme.of(context).titleLarge.override(
                  font: GoogleFonts.interTight(
                    fontWeight: FontWeight.w600,
                    fontStyle:
                        FlutterFlowTheme.of(context).titleLarge.fontStyle,
                  ),
                  fontSize: 22.0,
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.w600,
                  fontStyle: FlutterFlowTheme.of(context).titleLarge.fontStyle,
                ),
          ),
          actions: const [],
          centerTitle: true,
          elevation: 0.0,
        ),
        body: SafeArea(
          top: true,
          child: Container(
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).primaryBackground,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: KeyboardScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _topTab('All'),
                        _topTab('Pending'),
                        _topTab('Completed'),
                        _topTab('Cancelled'),
                      ].divide(const SizedBox(width: 8.0)),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          AppLocalizations.of(context).orders,
                          style:
                              FlutterFlowTheme.of(context).titleSmall.override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .titleSmall
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .titleSmall
                                          .fontStyle,
                                    ),
                                    color: FlutterFlowTheme.of(context).primary,
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .titleSmall
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .titleSmall
                                        .fontStyle,
                                  ),
                        ),
                        Builder(
                          builder: (context) {
                            // Filter by the top tab. Statuses live lowercase in the DB
                            // (pending/confirmed/transit/delivered|done/cancelled).
                            // Completed = delivered/done/completed; Cancelled =
                            // cancelled; Pending = everything still in progress.
                            final ordersListItem = _model.ordersList.where((o) {
                              final st = (o.status ?? '').toLowerCase();
                              switch (_model.selectedTab) {
                                case 'Completed':
                                  // Order Details Session 1, item 5: Mark
                                  // Order Complete introduces status
                                  // 'closed' (financial close, distinct
                                  // from 'delivered'/job-complete) — must
                                  // land here, not fall through to
                                  // Pending by omission.
                                  return st == 'delivered' ||
                                      st == 'done' ||
                                      st == 'completed' ||
                                      st == 'closed';
                                case 'Cancelled':
                                  return st == 'cancelled';
                                case 'Pending':
                                  return st != 'delivered' &&
                                      st != 'done' &&
                                      st != 'completed' &&
                                      st != 'cancelled' &&
                                      st != 'closed';
                                default:
                                  return true;
                              }
                            }).toList();

                            return ListView.separated(
                              padding: EdgeInsets.zero,
                              primary: false,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              scrollDirection: Axis.vertical,
                              itemCount: ordersListItem.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12.0),
                              itemBuilder: (context, ordersListItemIndex) {
                                final ordersListItemItem =
                                    ordersListItem[ordersListItemIndex];
                                return InkWell(
                                  splashColor: Colors.transparent,
                                  focusColor: Colors.transparent,
                                  hoverColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
                                  onTap: () async {
                                    context.pushNamed(
                                      OrderDetailPageWidget.routeName,
                                      queryParameters: {
                                        'orderId': serializeParam(
                                          ordersListItemItem.id,
                                          ParamType.String,
                                        ),
                                        // Masked for supervisors on
                                        // completed orders — the detail
                                        // page renders its own fallback.
                                        'orderCustomer': serializeParam(
                                          _hideCustomerFor(ordersListItemItem)
                                              ? 'Customer (hidden)'
                                              : ordersListItemItem.customer,
                                          ParamType.String,
                                        ),
                                        'orderPhone': serializeParam(
                                          _hideCustomerFor(ordersListItemItem)
                                              ? null
                                              : ordersListItemItem.phone,
                                          ParamType.String,
                                        ),
                                        'orderFromCity': serializeParam(
                                          ordersListItemItem.fromCity,
                                          ParamType.String,
                                        ),
                                        'orderToCity': serializeParam(
                                          ordersListItemItem.toCity,
                                          ParamType.String,
                                        ),
                                        'orderFromAddress': serializeParam(
                                          ordersListItemItem.fromAddress,
                                          ParamType.String,
                                        ),
                                        'orderToAddress': serializeParam(
                                          ordersListItemItem.toAddress,
                                          ParamType.String,
                                        ),
                                        'orderFromFloor': serializeParam(
                                          ordersListItemItem.fromFloor
                                              ?.toString(),
                                          ParamType.String,
                                        ),
                                        'orderToFloor': serializeParam(
                                          ordersListItemItem.toFloor
                                              ?.toString(),
                                          ParamType.String,
                                        ),
                                        'orderMoveDate': serializeParam(
                                          ordersListItemItem.moveDateOrNull
                                              ?.toString(),
                                          ParamType.String,
                                        ),
                                        'orderAmount': serializeParam(
                                          ordersListItemItem.amount?.toString(),
                                          ParamType.String,
                                        ),
                                        'orderAdvancePaid': serializeParam(
                                          ordersListItemItem.advancePaid
                                              ?.toString(),
                                          ParamType.String,
                                        ),
                                        'orderStatus': serializeParam(
                                          ordersListItemItem.status,
                                          ParamType.String,
                                        ),
                                        'orderPaymentStatus': serializeParam(
                                          ordersListItemItem.paymentStatus,
                                          ParamType.String,
                                        ),
                                        'orderTrackingStatus': serializeParam(
                                          ordersListItemItem.trackingStatus,
                                          ParamType.String,
                                        ),
                                        'orderService': serializeParam(
                                          ordersListItemItem.service,
                                          ParamType.String,
                                        ),
                                        'orderBranch': serializeParam(
                                          ordersListItemItem.branch,
                                          ParamType.String,
                                        ),
                                        'orderType': serializeParam(
                                          ordersListItemItem.orderType,
                                          ParamType.String,
                                        ),
                                        'orderNotes': serializeParam(
                                          ordersListItemItem.notes,
                                          ParamType.String,
                                        ),
                                      }.withoutNulls,
                                    );
                                  },
                                  child: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryBackground,
                                      borderRadius: BorderRadius.circular(12.0),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.max,
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                _hideCustomerFor(
                                                        ordersListItemItem)
                                                    ? 'Customer (hidden)'
                                                    : ordersListItemItem
                                                        .customer,
                                                style:
                                                    FlutterFlowTheme.of(context)
                                                        .titleSmall
                                                        .override(
                                                          font: GoogleFonts
                                                              .interTight(
                                                            fontWeight:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleSmall
                                                                    .fontWeight,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleSmall
                                                                    .fontStyle,
                                                          ),
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .primaryText,
                                                          letterSpacing: 0.0,
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .titleSmall
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .titleSmall
                                                                  .fontStyle,
                                                        ),
                                              ),
                                              Container(
                                                decoration: BoxDecoration(
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .primaryBackground,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12.0),
                                                ),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsetsDirectional
                                                          .fromSTEB(
                                                          10.0, 4.0, 10.0, 4.0),
                                                  child: Text(
                                                    ordersListItemItem.status ??
                                                        '-',
                                                    style: FlutterFlowTheme.of(
                                                            context)
                                                        .labelSmall
                                                        .override(
                                                          font:
                                                              GoogleFonts.inter(
                                                            fontWeight:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelSmall
                                                                    .fontWeight,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelSmall
                                                                    .fontStyle,
                                                          ),
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .primaryText,
                                                          letterSpacing: 0.0,
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .labelSmall
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .labelSmall
                                                                  .fontStyle,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.max,
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.place,
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .secondaryText,
                                                size: 14.0,
                                              ),
                                              Text(
                                                ordersListItemItem.fromCity ??
                                                    '-',
                                                style: FlutterFlowTheme.of(
                                                        context)
                                                    .bodySmall
                                                    .override(
                                                      font: GoogleFonts.inter(
                                                        fontWeight:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodySmall
                                                                .fontWeight,
                                                        fontStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodySmall
                                                                .fontStyle,
                                                      ),
                                                      color:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .secondaryText,
                                                      letterSpacing: 0.0,
                                                      fontWeight:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .bodySmall
                                                              .fontWeight,
                                                      fontStyle:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .bodySmall
                                                              .fontStyle,
                                                    ),
                                              ),
                                              Icon(
                                                Icons.arrow_forward,
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .secondaryText,
                                                size: 14.0,
                                              ),
                                              Text(
                                                ordersListItemItem.toCity ??
                                                    '-',
                                                style: FlutterFlowTheme.of(
                                                        context)
                                                    .bodySmall
                                                    .override(
                                                      font: GoogleFonts.inter(
                                                        fontWeight:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodySmall
                                                                .fontWeight,
                                                        fontStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodySmall
                                                                .fontStyle,
                                                      ),
                                                      color:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .secondaryText,
                                                      letterSpacing: 0.0,
                                                      fontWeight:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .bodySmall
                                                              .fontWeight,
                                                      fontStyle:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .bodySmall
                                                              .fontStyle,
                                                    ),
                                              ),
                                            ].divide(
                                                const SizedBox(width: 4.0)),
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.max,
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                ordersListItemItem
                                                        .moveDateOrNull
                                                        ?.toString() ??
                                                    '—',
                                                style: FlutterFlowTheme.of(
                                                        context)
                                                    .bodySmall
                                                    .override(
                                                      font: GoogleFonts.inter(
                                                        fontWeight:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodySmall
                                                                .fontWeight,
                                                        fontStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodySmall
                                                                .fontStyle,
                                                      ),
                                                      color:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .secondaryText,
                                                      letterSpacing: 0.0,
                                                      fontWeight:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .bodySmall
                                                              .fontWeight,
                                                      fontStyle:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .bodySmall
                                                              .fontStyle,
                                                    ),
                                              ),
                                              Text(
                                                (ordersListItemItem.amount ?? 0)
                                                    .toString(),
                                                style:
                                                    FlutterFlowTheme.of(context)
                                                        .titleSmall
                                                        .override(
                                                          font: GoogleFonts
                                                              .interTight(
                                                            fontWeight:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleSmall
                                                                    .fontWeight,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleSmall
                                                                    .fontStyle,
                                                          ),
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .primary,
                                                          letterSpacing: 0.0,
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .titleSmall
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .titleSmall
                                                                  .fontStyle,
                                                        ),
                                              ),
                                            ],
                                          ),
                                        ].divide(const SizedBox(height: 8.0)),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ].divide(const SizedBox(height: 12.0)),
                    ),
                  ].divide(const SizedBox(height: 16.0)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
