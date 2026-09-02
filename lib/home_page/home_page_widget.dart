import '/app_session.dart';
import '/backend/session_logout.dart';
import '/backend/commission_pricing.dart';
import '/backend/field_expenses.dart';
import '/backend/storage_billing.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/margin_availability.dart';
import '/components/dashboard_kpi_grid.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/components/global_search_delegate.dart';
import '/components/notification_bell.dart';
import '/components/theme_quick_button.dart';
import '/components/keyboard_scroll_view.dart';
import '/components/follow_up_summary_card.dart';
import '/components/quick_entry_dialog.dart';
import '/index.dart';
import '/nav_items.dart';
import '/permissions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home_page_model.dart';
export 'home_page_model.dart';

/// Staff/vendor dashboard. Multi-tenant: must be scoped to
/// AppSession.instance.currentOrgId (see org_id filter added below —
/// CLAUDE.md known bug #5 follow-up / Phase 1 multi-tenancy gap).
class HomePageWidget extends StatefulWidget {
  const HomePageWidget({super.key});

  static String routeName = 'HomePage';
  static String routePath = '/home';

  @override
  State<HomePageWidget> createState() => _HomePageWidgetState();
}

class _HomePageWidgetState extends State<HomePageWidget>
    with RefreshOnPopMixin<HomePageWidget> {
  late HomePageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  // Raw, unfiltered data for the period-aware KPI row (item 4,
  // NAGARVA_STATUS.md) — fetched once, recomputed client-side per
  // selected period rather than re-querying the DB on every chip tap.
  // Mirrors p_l_report_page_widget.dart's approach.
  List<OrdersRow> _allOrders = [];
  List<ExpensesRow> _allExpenses = [];
  List<OrderStaffRow> _allOrderStaff = [];

  /// Raw `stock_movements` consumption rows (order_id + value), org-scoped.
  /// Materials are the third place a job's costs are recorded, alongside
  /// the `expenses` table and orders.field_expenses.
  List<dynamic> _allConsumption = const [];

  /// Storage stays, org-scoped. Warehouse rent is REVENUE the order earns
  /// and it lives in neither `orders.amount` nor any quote, so without
  /// this the dashboard under-reports what the business actually made -
  /// the mirror of the materials/field-expense gaps on the cost side.
  List<dynamic> _allStorage = const [];
  // Current-state fields from dashboard_kpis_view that do NOT follow the
  // period filter (see HomePageModel.periodType doc comment).
  double _activeLeads = 0;
  double _outstandingAmount = 0;
  double _remindersToday = 0;
  // Added with the Phase 1 grid. Both belong in this group rather than
  // in _recomputePeriodKpis:
  //   activeMoves      is "in flight right now" — a job booked last
  //                    month and still in transit is active today, so
  //                    scoping it to the selected period would be wrong.
  //   quotesThisMonth  is calendar-month by definition in the view,
  //                    matching how _activeLeads already behaves.
  // Consequence worth knowing: neither responds to the period toggle,
  // exactly like _activeLeads and _remindersToday today.
  double _activeMoves = 0;
  double _quotesThisMonth = 0;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => HomePageModel());

    // On page load action.
    SchedulerBinding.instance.addPostFrameCallback((_) => _loadDashboard());

    _model.targetInputFieldTextController ??= TextEditingController();
    _model.targetInputFieldFocusNode ??= FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  // Refresh-after-write fix (parity brief Part 1, 27 Jul 2026): this is the
  // exact repro from the bug report ("record a cash collection → dashboard
  // KPIs do not update"). Re-runs the whole dashboard load whenever a route
  // pushed on top of Home (Record Payment, Quick Expense, New Order/Lead,
  // ...) is popped back to it.
  @override
  void onPageRefresh() {
    _loadDashboard();
    // Item 10.7: a follow-up completed on a lead must update the
    // dashboard count on the way back.
    _followUpKey.currentState?.reload();
  }

  final _followUpKey = GlobalKey<FollowUpSummaryCardState>();

  Future<void> _loadDashboard() async {
    // Vendor choice: only show the Porter KPI card when the org turned
    // it on in Settings (settings key 'porter_enabled').
    final porterRows = await SettingsTable().queryRows(
      queryFn: (q) => OrgScope.read(q).eq('key', 'porter_enabled'),
    );
    _model.porterEnabled = porterRows.isNotEmpty &&
        (porterRows.first.value ?? '').toLowerCase() == 'true';

    // Monthly target is the vendor's own number, so it is READ, never
    // defaulted. Absent simply leaves it null and the card invites them to
    // set one.
    try {
      final targetRows = await SettingsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('key', 'monthly_target'),
      );
      _model.monthlyTarget = targetRows.isEmpty
          ? null
          : double.tryParse((targetRows.first.value ?? '').trim());
    } catch (_) {
      // A failed read must not invent a target.
      _model.monthlyTarget = null;
    }
    safeSetState(() {});
    // Phase 1 multi-tenancy pass: all four dashboard queries were
    // unscoped and would read every org's data. Filtered by
    // currentOrgId now — requires supabase/phase1_add_org_id.sql (and
    // the org_id-aware dashboard_kpis_view/branch_kpis_view) to be run
    // first, or these throw "column org_id does not exist".
    _model.dashKpiOut = await DashboardKpisViewTable().queryRows(
      queryFn: (q) => OrgScope.read(q),
    );
    final kpiRow =
        (_model.dashKpiOut ?? []).isNotEmpty ? _model.dashKpiOut!.first : null;
    _activeLeads = kpiRow?.activeLeads ?? 0;
    _outstandingAmount = kpiRow?.outstandingAmount ?? 0;
    _remindersToday = kpiRow?.remindersToday ?? 0;
    _activeMoves = kpiRow?.activeMoves ?? 0;
    _quotesThisMonth = kpiRow?.quotesThisMonth ?? 0;
    // Raw rows for the period-recomputed financial KPIs — see
    // _recomputePeriodKpis below. Unfiltered by date (filtered
    // client-side per the selected period instead).
    final results = await Future.wait([
      OrdersTable().queryRows(queryFn: (q) => OrgScope.read(q)),
      ExpensesTable().queryRows(queryFn: (q) => OrgScope.read(q)),
      OrderStaffTable().queryRows(queryFn: (q) => OrgScope.read(q)),
    ]);
    _allOrders = results[0].cast<OrdersRow>();
    _allExpenses = results[1].cast<ExpensesRow>();
    _allOrderStaff = results[2].cast<OrderStaffRow>();

    // Material consumed on a job is a cost, and it lives in
    // stock_movements - not in `expenses`, and not in
    // orders.field_expenses either. Order Details already charges it
    // ("Materials (1) - Rs2,700"); the dashboard did not, so the same job
    // showed one profit on the order and a higher one here. Same shape as
    // the field-expenses gap fixed earlier the same day - a third place
    // costs are recorded, and the dashboard knew about only one of them.
    //
    // Valued exactly as order_pnl_section values it: abs(value) on rows
    // with movement_type 'consumption', so the two cannot disagree.
    try {
      _allConsumption = await OrgScope.read(SupaFlow.client
              .from('stock_movements')
              .select('order_id,value'))
          .eq('movement_type', 'consumption');
    } catch (_) {
      // Never let a stock read blank the dashboard; costs simply stay as
      // known so far rather than the page failing.
      _allConsumption = const [];
    }

    try {
      _allStorage = await OrgScope.read(SupaFlow.client.from('storage_jobs').select(
              'order_id,in_date,out_date,billing_mode,rate,min_billing_days,'
              'handling_in_charge,handling_out_charge'))
          .isFilter('deleted_at', null);
    } catch (_) {
      _allStorage = const [];
    }
    _recomputePeriodKpis();
    safeSetState(() {});
    // "Upcoming" means move_date hasn't passed yet — without this filter
    // the query just returned the earliest-dated confirmed orders ever
    // created, so old/past moves stayed pinned at the top forever.
    final todayDateOnly = DateTime.now().toIso8601String().split('T').first;
    _model.dashUpcomingOut = await OrdersTable().queryRows(
      queryFn: (q) => OrgScope.read(q)
          .eqOrNull(
            'status',
            'confirmed',
          )
          .gte('move_date', todayDateOnly)
          .order('move_date', ascending: true),
    );
    _model.upcomingOrders =
        (_model.dashUpcomingOut ?? []).toList().cast<OrdersRow>();
    safeSetState(() {});
    _model.dashHotLeadsOut = await LeadsTable().queryRows(
      queryFn: (q) => OrgScope.read(q)
          .eqOrNull(
            'status',
            'new',
          )
          .order('created_at'),
    );
    _model.hotLeads = (_model.dashHotLeadsOut ?? []).toList().cast<LeadsRow>();
    safeSetState(() {});
    _model.dashBranchOut = await BranchKpisViewTable().queryRows(
      queryFn: (q) => OrgScope.read(q),
    );
    _model.branchStats =
        (_model.dashBranchOut ?? []).toList().cast<BranchKpisViewRow>();
    safeSetState(() {});
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  // ---- Period filter (item 4, NAGARVA_STATUS.md) --------------------------

  /// [start, end) for the selected period, or (null, null) for 'all'.
  (DateTime?, DateTime?) _periodRange() {
    final month = _model.visibleMonth;
    switch (_model.periodType) {
      case '3m':
        final now = DateTime.now();
        return (
          DateTime(now.year, now.month - 2),
          DateTime(now.year, now.month + 1),
        );
      case 'fy':
        final now = DateTime.now();
        final fyStartYear = now.month >= 4 ? now.year : now.year - 1;
        return (DateTime(fyStartYear, 4), DateTime(fyStartYear + 1, 4));
      case 'all':
        return (null, null);
      case 'month':
      default:
        return (
          DateTime(month.year, month.month),
          DateTime(month.year, month.month + 1),
        );
    }
  }

  /// Shared empty-state card for the dashboard's "titled section, zero
  /// rows" spots — Upcoming Moves / Hot Leads. A brand-new trial org's
  /// very first screen used to show these section headers with nothing
  /// rendered under them (17 Aug 2026 finding); this gives that org
  /// somewhere to go instead of a blank gap.
  Widget _dashboardEmptyState(
    BuildContext context, {
    required IconData icon,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: theme.secondaryText),
          const SizedBox(height: 10),
          Text(
            message,
            style: GoogleFonts.inter(color: theme.secondaryText, fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onAction,
            child: Text(
              actionLabel,
              style: GoogleFonts.interTight(
                color: theme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _inRange(DateTime date, DateTime? start, DateTime? end) {
    if (start == null || end == null) return true;
    return !date.isBefore(start) && date.isBefore(end);
  }

  String _periodLabel() {
    final now = DateTime.now();
    final month = _model.visibleMonth;
    switch (_model.periodType) {
      case '3m':
        return 'LAST 3 MONTHS';
      case 'fy':
        final fyStartYear = now.month >= 4 ? now.year : now.year - 1;
        return 'FY ${(fyStartYear % 100).toString().padLeft(2, '0')}-${((fyStartYear + 1) % 100).toString().padLeft(2, '0')}';
      case 'all':
        return 'ALL TIME';
      case 'month':
      default:
        if (month.year == now.year && month.month == now.month) {
          return 'THIS MONTH';
        }
        final prev = DateTime(now.year, now.month - 1);
        if (month.year == prev.year && month.month == prev.month) {
          return 'LAST MONTH';
        }
        return DateFormat('MMMM yyyy').format(month).toUpperCase();
    }
  }

  void _recomputePeriodKpis() {
    final (start, end) = _periodRange();
    // OrdersRow.moveDate throws (getField<DateTime>('move_date')!) for any
    // order whose move_date is null in the DB — found while fixing the
    // Calendar page's identical crash (item 5, NAGARVA_STATUS.md). Guard
    // here too since this method reads every org order unfiltered.
    final periodOrders = _allOrders.where((o) {
      final d = o.getField<DateTime>('move_date');
      return d != null && _inRange(d, start, end);
    }).toList();
    final periodOrderIds = periodOrders.map((o) => o.id).toSet();

    // GROSS is what the customer pays. It is NOT revenue, and it is not
    // profit: the GST component is collected on the government's behalf and
    // owed straight back to it, so counting it as earnings overstates both
    // (Arun, 2 Sep 2026 - "gst wont comes under profit").
    //
    // On the live test order that was 37,800 gross carrying 1,800 of GST -
    // so Revenue read 37.8K and Profit 34.6K when the business had actually
    // earned 36,000 and made 32,800.
    //
    // Orders with no recorded GST (quote_gst_amount null - a direct booking
    // that never went through a quote) net to their gross, which is correct:
    // no GST was charged, so none is owed.
    final grossRevenue = periodOrders.fold(0.0, (s, o) => s + (o.amount ?? 0));
    final gstCollected =
        periodOrders.fold(0.0, (s, o) => s + (o.quoteGstAmount ?? 0));
    // Storage rent earned on the period's orders, priced by the very same
    // function the order card and the P&L use so all three agree.
    final storageIncome = _allStorage.fold<double>(0.0, (s, r) {
      final oid = r['order_id'];
      if (oid == null || !periodOrderIds.contains(oid)) return s;
      final inDate = DateTime.tryParse('${r['in_date']}');
      if (inDate == null) return s;
      final rawOut = r['out_date'];
      final rate = (num.tryParse('${r['rate']}') ?? 0).toDouble();
      return s +
          computeStorageCharge(
            inDate: inDate,
            outDate: rawOut == null ? null : DateTime.tryParse('$rawOut'),
            mode: storageBillingModeFromWire(r['billing_mode'] as String?),
            rate: rate,
            minBillingDays: (num.tryParse('${r['min_billing_days']}') ?? 0)
                .toInt(),
            handlingIn:
                (num.tryParse('${r['handling_in_charge']}') ?? 0).toDouble(),
            handlingOut:
                (num.tryParse('${r['handling_out_charge']}') ?? 0).toDouble(),
            customAmount: rate,
          ).total;
    });
    final revenue = grossRevenue - gstCollected + storageIncome;
    final labour = periodOrders.fold(
        0.0,
        (s, o) =>
            s +
            _allOrderStaff
                .where((os) => os.orderId == o.id)
                .fold(0.0, (a, os) => a + (os.salaryAmount ?? 0)));
    // Unlike PLReportPage (which faithfully keeps the reference app's
    // quirk of never date-filtering non-order-linked expenses), a
    // period *toggle* on the dashboard should make "other expenses" move
    // with the selected period too — that's the whole point of the UI.
    final expensesFromTable = _allExpenses
        .where((e) => _inRange(
            e.orderId != null
                ? (e.expenseDate ?? DateTime.now())
                : (e.expenseDate ?? e.createdAt ?? DateTime.now()),
            start,
            end))
        .fold(0.0, (s, e) => s + (e.amount ?? 0));
    // Plus what supervisors logged in the field. These are real costs on
    // orders.field_expenses (fuel, parking, crane), and the dashboard used
    // to ignore them entirely: a job could carry Rs2,500 of fuel, show it
    // on the Order Details P&L, and STILL report "No expenses recorded"
    // here with margin suppressed as "Needs expense data" (found 2 Sep
    // 2026, on the very order that had just been delivered). Same period
    // window as the order itself, since a field expense belongs to its job.
    final fieldExpenses = periodOrders.fold(
        0.0, (s, o) => s + sumFieldExpenses(o.data['field_expenses']).$1);
    // Materials consumed on the period's orders. Scoped by order rather
    // than by movement date so a job's material cost always sits in the
    // same period as the job's revenue.
    final materials = _allConsumption.fold<double>(0.0, (s, r) {
      final oid = r['order_id'];
      if (oid == null || !periodOrderIds.contains(oid)) return s;
      return s + (num.tryParse('${r['value']}') ?? 0).abs().toDouble();
    });
    final expenses = expensesFromTable + fieldExpenses + materials;
    // Commission at each order's own snapshotted rate. Orders with no
    // rate are EXCLUDED and counted, never costed at a substitute — this
    // read `?? 16` (APC's porter rate) until 2 Sept 2026, which quietly
    // put an invented cost into every tenant's dashboard profit.
    final commissionRollup = _model.porterEnabled
        ? rollUpCommission(periodOrders, (o) => o.amount ?? 0)
        : CommissionRollup.empty;
    final porterCommission = commissionRollup.total;
    _model.unpricedCommissionCount = commissionRollup.unpricedCount;

    // Progress against the monthly target uses the same net figure the
    // Revenue tile shows, so the two cannot disagree on screen.
    _model.periodNetRevenue = revenue;
    _model.periodGstCollected = gstCollected;
    _model.periodNetProfit =
        revenue - labour - expenses - porterCommission;

    _model.kpiList = [
      DashboardKpisViewRow({
        'revenue_this_month': revenue,
        'labour_this_month': labour,
        'expenses_this_month': expenses,
        'porter_comm_this_month': porterCommission,
        'net_profit_this_month': revenue - labour - expenses - porterCommission,
        'orders_this_month': periodOrderIds.length.toDouble(),
        'active_leads': _activeLeads,
        'outstanding_amount': _outstandingAmount,
        'reminders_today': _remindersToday,
        'active_moves': _activeMoves,
        'quotes_this_month': _quotesThisMonth,
      })
    ];
  }

  void _setPeriodType(String type) {
    _model.periodType = type;
    if (type == 'month') {
      _model.visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
    }
    _recomputePeriodKpis();
    safeSetState(() {});
  }

  void _setLastMonth() {
    final now = DateTime.now();
    _model.periodType = 'month';
    _model.visibleMonth = DateTime(now.year, now.month - 1);
    _recomputePeriodKpis();
    safeSetState(() {});
  }

  void _shiftMonth(int delta) {
    _model.periodType = 'month';
    _model.visibleMonth =
        DateTime(_model.visibleMonth.year, _model.visibleMonth.month + delta);
    _recomputePeriodKpis();
    safeSetState(() {});
  }

  Widget _periodSelector(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final now = DateTime.now();
    final chips = <(String, String, VoidCallback)>[
      ('month-this', 'This', () => _setPeriodType('month')),
      ('month-last', 'Last', _setLastMonth),
      ('3m', '3M', () => _setPeriodType('3m')),
      ('fy', 'FY', () => _setPeriodType('fy')),
      ('all', 'All', () => _setPeriodType('all')),
    ];
    bool isSelected(String key) {
      if (_model.periodType != 'month') return key == _model.periodType;
      final isThisMonth = _model.visibleMonth.year == now.year &&
          _model.visibleMonth.month == now.month;
      if (key == 'month-this') return isThisMonth;
      if (key == 'month-last') {
        final prev = DateTime(now.year, now.month - 1);
        return _model.visibleMonth.year == prev.year &&
            _model.visibleMonth.month == prev.month;
      }
      return false;
    }

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16.0, 0.0, 16.0, 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (key, label, onTap) in chips)
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          0.0, 0.0, 6.0, 0.0),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: isSelected(key),
                        onSelected: (_) => onTap(),
                        labelStyle: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isSelected(key)
                              ? theme.primaryBackground
                              : theme.primaryText,
                        ),
                        selectedColor: theme.primary,
                        backgroundColor: theme.secondaryBackground,
                        showCheckmark: false,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_model.periodType == 'month') ...[
            // Parity brief Part 5e: these were constrained to 32x32dp,
            // under the 48dp Material minimum — a frequently-used control
            // (dashboard period navigation) worth padding out properly.
            IconButton(
              tooltip: 'Previous month',
              icon: Icon(Icons.chevron_left,
                  color: theme.secondaryText, size: 20),
              onPressed: () => _shiftMonth(-1),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
            IconButton(
              tooltip: 'Next month',
              icon: Icon(Icons.chevron_right,
                  color: theme.secondaryText, size: 20),
              onPressed: () => _shiftMonth(1),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // This drawer used to list every page unconditionally, unlike the
    // bottom nav / sidebar in main.dart's NavBarPage which filters by the
    // staff permission matrix (StaffPermissions.activeStaffPages) — a
    // staff member without e.g. Payments access could still see and tap
    // it here, only to silently bounce back to Dashboard via NavBarPage's
    // own URL guard. Mirrors the same allow-list so the two navs agree.
    //
    // Users Kickoff Step 2 (1 Aug 2026): activeStaffPages is a
    // kPermModules-derived set and only ever applies to a MANAGER
    // session — owner never filters, and supervisor/field-staff's nav
    // items (SupervisorJobsListPage, MyAttComingSoon, ...) aren't in
    // kPermModules at all and never will be (their set is fixed by role,
    // not per-person customizable — see nav_items.dart). Applying the
    // old owner-vs-any-staff branch here would have filtered a
    // supervisor/field-staff drawer down to nothing, since none of their
    // items could ever match activeStaffPages.
    final allowedDrawerPages =
        isOwnerOrManagerSession && AppSession.instance.currentStaffId != null
            ? (StaffPermissions.activeStaffPages ??
                const {'HomePage', 'OrdersPage', 'OperationsPage'})
            : null; // owner, and supervisor/field-staff: unfiltered (fixed) set
    bool showDrawerPage(String pageName) =>
        allowedDrawerPages == null || allowedDrawerPages.contains(pageName);
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
            // Popup on the same screen (matches the React web app),
            // not a navigation to /quick-entry.
            await QuickEntryDialog.show(context);
          },
          backgroundColor: FlutterFlowTheme.of(context).primary,
          tooltip: 'Quick Entry',
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Parity brief Part 5/nav-completeness fix: this drawer used
                // to hand-duplicate main.dart's nav item list and had
                // silently drifted to only 8 of the 12 real destinations
                // (Accounts/Staff/Fleet/P&L were missing outright, not
                // permission-filtered — found live-testing on a real
                // phone). Users Kickoff Step 2 (1 Aug 2026): now calls the
                // same navItemsForCurrentSession() main.dart's NavBarPage
                // uses, instead of reading kAllNavItems directly — that
                // raw list is only ever correct for an owner/manager
                // session, so reading it directly here would have shown a
                // supervisor/field-staff session the wrong 19-item drawer
                // again, the exact class of drift this fix already closed
                // once. Every tile keeps a real 48dp+ tap target via
                // ListTile's own default sizing.
                for (final item in navItemsForCurrentSession())
                  if (showDrawerPage(item.name))
                    InkWell(
                      onTap: () {
                        if (scaffoldKey.currentState!.isDrawerOpen ||
                            scaffoldKey.currentState!.isEndDrawerOpen) {
                          Navigator.pop(context);
                        }
                        if (item.name != 'HomePage') {
                          context.pushNamed(item.name);
                        }
                      },
                      child: Material(
                        color: Colors.transparent,
                        child: ListTile(
                          leading: Icon(item.icon),
                          title: Text(item.label),
                        ),
                      ),
                    ),
                InkWell(
                  splashColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  onTap: () async {
                    // Was a second, independently-drifted logout sequence
                    // (missing StaffAuth.clearStoredVendorToken()/
                    // StaffPermissions.clearActive(), and — the live bug —
                    // hardcoded context.go(LoginPageWidget.routePath)
                    // regardless of device binding, stranding a PIN-only
                    // staff member on a screen he has no credentials for).
                    // Now calls the one shared sequence directly instead of
                    // re-duplicating it a second time.
                    if (Navigator.of(context).canPop()) {
                      context.pop();
                    }
                    await performLogout(context);
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      leading: const Icon(
                        Icons.logout,
                      ),
                      title: Text(
                        AppLocalizations.of(context).logout,
                        style: const TextStyle(),
                      ),
                      dense: false,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          automaticallyImplyLeading: true,
          // Two-line title: Dashboard, with the ACTIVE ORG beneath it.
          //
          // The org line is a SAFETY NET, not decoration (27 Aug 2026).
          // Nagarva is org-per-location: an owner's Tamil Nadu, Karnataka
          // and Andhra operations are separate legal entities with
          // separate books. Since the last-used org is now restored
          // SILENTLY with no login picker (see org_resolution.dart),
          // this line is the only thing telling an owner which company
          // he is looking at. Shown unconditionally — including for
          // single-org users — so that its absence is never something
          // anyone has to notice.
          //
          // Rendered only when a name is actually known: inventing or
          // placeholder-ing a company name here would be worse than
          // showing none, given what it is for.
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                AppLocalizations.of(context).dashboard,
                style: FlutterFlowTheme.of(context).titleLarge.override(
                      font: GoogleFonts.interTight(
                        fontWeight: FontWeight.w600,
                        fontStyle:
                            FlutterFlowTheme.of(context).titleLarge.fontStyle,
                      ),
                      fontSize: 20.0,
                      letterSpacing: 0.0,
                      fontWeight: FontWeight.w600,
                      fontStyle:
                          FlutterFlowTheme.of(context).titleLarge.fontStyle,
                    ),
              ),
              if ((AppSession.instance.currentOrgName ?? '').trim().isNotEmpty)
                Text(
                  AppSession.instance.currentOrgName!.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FlutterFlowTheme.of(context).bodySmall.override(
                        font: GoogleFonts.inter(),
                        fontSize: 12.0,
                        letterSpacing: 0.0,
                        color: FlutterFlowTheme.of(context).secondaryText,
                      ),
                ),
            ],
          ),
          actions: [
            // Part 8 addendum item 1: the Dashboard AppBar (mobile) had no
            // notification entry point at all — NotificationBell already
            // existed and was wired into the wide-screen sidebar rail
            // (main.dart's NavBarPage header) but was never placed here,
            // so it was invisible on the phone-width layout this bug was
            // actually reported from. Reusing the same widget rather than
            // building a second one — it already has its own unread
            // badge, Realtime subscription, and mark-all-read popup.
            // iconColor matches whatever the search icon resolves to
            // (AppBar's default IconTheme) instead of a hardcoded colour,
            // so it stays correct across light/dark/midnight.
            NotificationBell(iconColor: IconTheme.of(context).color),
            // Theme, promoted out of Settings (Arun, 2 Sep 2026) so it is
            // one tap from wherever the vendor already is — daylight
            // outdoors, a dark flat at night. Language deliberately did
            // NOT come with it; see ThemeQuickButton's doc comment for
            // why moving a control that does nothing would be worse than
            // leaving it buried.
            ThemeQuickButton(iconColor: IconTheme.of(context).color),
            // Restored gap vs the reference app: the header "Mobile /
            // Name..." global customer search (orders + leads by name or
            // phone) — see GlobalSearchDelegate. 48x48dp default IconButton
            // target.
            IconButton(
              tooltip: 'Search orders & leads',
              icon: const Icon(Icons.search),
              onPressed: () => showSearch(
                  context: context, delegate: GlobalSearchDelegate()),
            ),
          ],
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
              padding: const EdgeInsets.all(20.0),
              child: KeyboardScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                16.0, 0.0, 16.0, 0.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  functions.timeGreeting()!,
                                  style: FlutterFlowTheme.of(context)
                                      .titleLarge
                                      .override(
                                        font: GoogleFonts.interTight(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .titleLarge
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .titleLarge
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .primaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .titleLarge
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .titleLarge
                                            .fontStyle,
                                      ),
                                ),
                                Text(
                                  functions.todayLabel()!,
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontStyle,
                                      ),
                                ),
                              ].divide(const SizedBox(height: 4.0)),
                            ),
                          ),
                        ),
                        // Money is gated on the reports permission, same
                        // guard as the KPI row below — no point letting
                        // someone pick a period for cards they can't see.
                        //
                        // Was `currentStaffId == null`, which is a SESSION
                        // SHAPE test, not a permission test: it meant only
                        // an email/vendor session saw money, so every
                        // PIN-based session lost Revenue/Labour/Expenses/
                        // Outstanding/Monthly Target — including managers,
                        // whom permissions.dart grants fullAccess(). With
                        // PIN-first login that is most sessions. Fixed
                        // 20 Aug 2026 after Arun found the cards missing on
                        // a manager session.
                        //
                        // canActive() still returns true for a vendor
                        // session, so owner behaviour is unchanged, and
                        // supervisors/drivers/packers/helpers stay excluded
                        // because the matrix does not grant them 'reports'.
                        if (StaffPermissions.canActive('financials', 'view'))
                          _periodSelector(context),
                        // Item 10.5: today's / overdue follow-up counts.
                        // Not money-gated — staff chase leads too. Renders
                        // nothing when both counts are zero.
                        FollowUpSummaryCard(key: _followUpKey),
                        // Phase 1 dashboard grid. Replaces ~1,300 lines of FlutterFlow
                        // markup that rendered these same figures as hand-nested
                        // Containers. Every tile is permission-gated inside the
                        // component via StaffPermissions.canActive; LABOUR and
                        // REMINDERS moved in as tiles rather than being dropped,
                        // since the mockup omits them but they work today.
                        Padding(
                          padding:
                              const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // The old cards each carried this label.
                              // Without it the grid shows period-filtered
                              // money with no statement of the window,
                              // which makes the selector above ambiguous
                              // — a regression, not a simplification.
                              if (StaffPermissions.canActive(
                                  'financials', 'view'))
                                Padding(
                                  padding: const EdgeInsetsDirectional.fromSTEB(
                                      2, 0, 0, 8),
                                  child: Text(
                                    _periodLabel(),
                                    style: GoogleFonts.inter(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryText,
                                    ),
                                  ),
                                ),
                              DashboardKpiGrid(
                                kpi: _model.kpiList.isNotEmpty
                                    ? _model.kpiList.first
                                    : null,
                                unpricedCommissionCount:
                                    _model.unpricedCommissionCount,
                                onAddExpense: () => context
                                    .pushNamed(QuickExpensePageWidget.routeName),
                              ),
                            ],
                          ),
                        ),
                        // Monthly Target — same reports gate as the KPI
                        // row above. See that comment for why this is a
                        // permission check and not `currentStaffId == null`.
                        if (StaffPermissions.canActive('financials', 'view'))
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                16.0, 0.0, 16.0, 0.0),
                            child: Container(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: FlutterFlowTheme.of(context)
                                      .secondaryBackground,
                                  borderRadius: BorderRadius.circular(12.0),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.max,
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            AppLocalizations.of(context).monthlyTarget,
                                            style: FlutterFlowTheme.of(context)
                                                .labelSmall
                                                .override(
                                                  font: GoogleFonts.inter(
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
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .secondaryText,
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
                                          FFButtonWidget(
                                            onPressed: () async {
                                              _model.showEditTarget =
                                                  !_model.showEditTarget!;
                                              safeSetState(() {});
                                            },
                                            text: AppLocalizations.of(context).edit,
                                            icon: const Icon(
                                              Icons.edit,
                                              size: 20.0,
                                            ),
                                            options: FFButtonOptions(
                                              padding:
                                                  const EdgeInsetsDirectional
                                                      .fromSTEB(
                                                      0.0, 0.0, 0.0, 0.0),
                                              iconPadding:
                                                  const EdgeInsetsDirectional
                                                      .fromSTEB(
                                                      0.0, 0.0, 0.0, 0.0),
                                              iconColor:
                                                  FlutterFlowTheme.of(context)
                                                      .primary,
                                              color: Colors.transparent,
                                              textStyle: TextStyle(
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primary,
                                              ),
                                              borderSide: BorderSide(
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primary,
                                                width: 1.0,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8.0),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.max,
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Column(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                // inrFormat(null) renders
                                                // "Rs0", which reads as a
                                                // real target of zero rather
                                                // than one nobody has set.
                                                _model.monthlyTarget == null
                                                    ? 'Not set'
                                                    : functions.inrFormat(
                                                        _model.monthlyTarget)!,
                                                style:
                                                    FlutterFlowTheme.of(context)
                                                        .headlineMedium
                                                        .override(
                                                          font: GoogleFonts
                                                              .interTight(
                                                            fontWeight:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .headlineMedium
                                                                    .fontWeight,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .headlineMedium
                                                                    .fontStyle,
                                                          ),
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .primaryText,
                                                          letterSpacing: 0.0,
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .headlineMedium
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .headlineMedium
                                                                  .fontStyle,
                                                        ),
                                              ),
                                              // Progress toward the target.
                                              //
                                              // Measured in PROFIT, not revenue (Arun, 2 Sep 2026: "in target
                                              // we need profit not revenue"). A revenue target rewards booking
                                              // work at any price; the number a mover actually runs the business
                                              // on is what is left after labour, expenses and commission - and
                                              // after GST, which is collected for the government and is not
                                              // earnings at all.
                                              if ((_model.monthlyTarget ?? 0) > 0) ...[
                                                const SizedBox(height: 8.0),
                                                Builder(builder: (context) {
                                                  final target = _model.monthlyTarget!;
                                                  final done = _model.periodNetProfit;
                                                  // A loss-making period must not read as progress.
                                                  final frac = (done <= 0 ? 0.0 : done / target).clamp(0.0, 1.0);
                                                  final pct = (done / target * 100).round();
                                                  final left = target - done;
                                                  final theme = FlutterFlowTheme.of(context);
                                                  return Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      // LinearProgressIndicator has no intrinsic width and this
                                                      // Column is sized by its widest child, so without an
                                                      // explicit width the bar collapses to nothing and renders
                                                      // invisibly - which is exactly what it did first time.
                                                      SizedBox(
                                                        width: 240,
                                                        child: ClipRRect(
                                                          borderRadius: BorderRadius.circular(6),
                                                          child: LinearProgressIndicator(
                                                            value: frac,
                                                            minHeight: 8,
                                                            backgroundColor: theme.alternate,
                                                            valueColor: AlwaysStoppedAnimation<Color>(done <= 0
                                                                ? theme.error
                                                                : (left <= 0 ? theme.success : theme.primary)),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 6.0),
                                                      Text(
                                                        done <= 0
                                                            ? 'No profit yet this period'
                                                            : (left <= 0
                                                                ? 'Target met — ${functions.inrFormat(done)} profit ($pct%)'
                                                                : '${functions.inrFormat(done)} profit of ${functions.inrFormat(target)} · ${functions.inrFormat(left)} to go ($pct%)'),
                                                        style: theme.bodySmall.override(
                                                          font: GoogleFonts.inter(),
                                                          color: theme.secondaryText,
                                                          letterSpacing: 0.0,
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                }),
                                                const SizedBox(height: 2.0),
                                              ],
                                              Text(
                                                // Labelled as a PROFIT target
                                                // so the big number above is
                                                // not read as revenue.
                                                'profit target this month',
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
                                                const SizedBox(height: 2.0)),
                                          ),
                                        ],
                                      ),
                                      if (_model.showEditTarget ?? true)
                                        Container(
                                          child: Row(
                                            mainAxisSize: MainAxisSize.max,
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Flexible(
                                                flex: 1,
                                                child: TextFormField(
                                                  controller: _model
                                                      .targetInputFieldTextController,
                                                  focusNode: _model
                                                      .targetInputFieldFocusNode,
                                                  obscureText: false,
                                                  decoration: InputDecoration(
                                                    hintText:
                                                        AppLocalizations.of(context).eG200000,
                                                    enabledBorder:
                                                        const OutlineInputBorder(
                                                      borderSide: BorderSide(
                                                        color:
                                                            Color(0x00000000),
                                                        width: 1.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.only(
                                                        topLeft:
                                                            Radius.circular(
                                                                4.0),
                                                        topRight:
                                                            Radius.circular(
                                                                4.0),
                                                      ),
                                                    ),
                                                    focusedBorder:
                                                        const OutlineInputBorder(
                                                      borderSide: BorderSide(
                                                        color:
                                                            Color(0x00000000),
                                                        width: 1.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.only(
                                                        topLeft:
                                                            Radius.circular(
                                                                4.0),
                                                        topRight:
                                                            Radius.circular(
                                                                4.0),
                                                      ),
                                                    ),
                                                    errorBorder:
                                                        const OutlineInputBorder(
                                                      borderSide: BorderSide(
                                                        color:
                                                            Color(0x00000000),
                                                        width: 1.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.only(
                                                        topLeft:
                                                            Radius.circular(
                                                                4.0),
                                                        topRight:
                                                            Radius.circular(
                                                                4.0),
                                                      ),
                                                    ),
                                                    focusedErrorBorder:
                                                        const OutlineInputBorder(
                                                      borderSide: BorderSide(
                                                        color:
                                                            Color(0x00000000),
                                                        width: 1.0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.only(
                                                        topLeft:
                                                            Radius.circular(
                                                                4.0),
                                                        topRight:
                                                            Radius.circular(
                                                                4.0),
                                                      ),
                                                    ),
                                                    filled: true,
                                                  ),
                                                  style: const TextStyle(),
                                                  maxLines: null,
                                                  validator: _model
                                                      .targetInputFieldTextControllerValidator
                                                      .asValidator(context),
                                                ),
                                              ),
                                              FFButtonWidget(
                                                onPressed: () async {
                                                  final entered =
                                                      functions.parseDouble(_model
                                                          .targetInputFieldTextController
                                                          .text);
                                                  // This used to setState and
                                                  // stop. Nothing was ever
                                                  // written, so the vendor's
                                                  // correction silently
                                                  // reverted on the next
                                                  // reload - a button that
                                                  // looks like it works and
                                                  // does not.
                                                  try {
                                                    await SettingsTable().upsert(
                                                      {
                                                        ...OrgScope.stamp(),
                                                        'key': 'monthly_target',
                                                        'value':
                                                            (entered ?? 0)
                                                                .toStringAsFixed(0),
                                                      },
                                                      onConflict: 'org_id,key',
                                                    );
                                                    _model.monthlyTarget = entered;
                                                    _model.showEditTarget = false;
                                                    safeSetState(() {});
                                                  } catch (e) {
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(context)
                                                          .showSnackBar(SnackBar(
                                                              content: Text(
                                                                  'Could not save target: $e')));
                                                    }
                                                  }
                                                },
                                                text:
                                                    AppLocalizations.of(context).save,
                                                options: FFButtonOptions(
                                                  padding:
                                                      const EdgeInsetsDirectional
                                                          .fromSTEB(
                                                          0.0, 0.0, 0.0, 0.0),
                                                  iconPadding:
                                                      const EdgeInsetsDirectional
                                                          .fromSTEB(
                                                          0.0, 0.0, 0.0, 0.0),
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .primary,
                                                  textStyle: const TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          8.0),
                                                ),
                                              ),
                                            ].divide(
                                                const SizedBox(width: 8.0)),
                                          ),
                                        ),
                                    ].divide(const SizedBox(height: 12.0)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Container(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                16.0, 0.0, 16.0, 0.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      AppLocalizations.of(context).upcomingOrders,
                                      style: FlutterFlowTheme.of(context)
                                          .titleSmall
                                          .override(
                                            font: GoogleFonts.interTight(
                                              fontWeight:
                                                  FlutterFlowTheme.of(context)
                                                      .titleSmall
                                                      .fontWeight,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .titleSmall
                                                      .fontStyle,
                                            ),
                                            color: FlutterFlowTheme.of(context)
                                                .primaryText,
                                            letterSpacing: 0.0,
                                            fontWeight:
                                                FlutterFlowTheme.of(context)
                                                    .titleSmall
                                                    .fontWeight,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .titleSmall
                                                    .fontStyle,
                                          ),
                                    ),
                                    FFButtonWidget(
                                      onPressed: () async {
                                        context.pushNamed(
                                            CalendarPageWidget.routeName);
                                      },
                                      text: AppLocalizations.of(context).calendar,
                                      options: FFButtonOptions(
                                        padding: const EdgeInsetsDirectional
                                            .fromSTEB(0.0, 0.0, 0.0, 0.0),
                                        iconPadding: const EdgeInsetsDirectional
                                            .fromSTEB(0.0, 0.0, 0.0, 0.0),
                                        color: Colors.transparent,
                                        textStyle: TextStyle(
                                          color: FlutterFlowTheme.of(context)
                                              .primary,
                                        ),
                                        borderSide: BorderSide(
                                          color: FlutterFlowTheme.of(context)
                                              .primary,
                                          width: 1.0,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(8.0),
                                      ),
                                    ),
                                  ],
                                ),
                                Builder(
                                  builder: (context) {
                                    final upcomingOrder =
                                        _model.upcomingOrders.toList();

                                    if (upcomingOrder.isEmpty) {
                                      return _dashboardEmptyState(
                                        context,
                                        icon: Icons.event_available_outlined,
                                        message: 'No moves scheduled yet',
                                        actionLabel: 'Create your first order',
                                        onAction: () => context.pushNamed(
                                            NewOrderPageWidget.routeName),
                                      );
                                    }

                                    return ListView.separated(
                                      padding: EdgeInsets.zero,
                                      primary: false,
                                      shrinkWrap: true,
                                      scrollDirection: Axis.vertical,
                                      itemCount: upcomingOrder.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 8.0),
                                      itemBuilder:
                                          (context, upcomingOrderIndex) {
                                        final upcomingOrderItem =
                                            upcomingOrder[upcomingOrderIndex];
                                        return Container(
                                          decoration: BoxDecoration(
                                            color: FlutterFlowTheme.of(context)
                                                .secondaryBackground,
                                            borderRadius:
                                                BorderRadius.circular(10.0),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12.0),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.max,
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Flexible(
                                                  flex: 1,
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.start,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        upcomingOrderItem
                                                            .customer,
                                                        maxLines: 1,
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .titleSmall
                                                                .override(
                                                                  font: GoogleFonts
                                                                      .interTight(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleSmall
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleSmall
                                                                        .fontStyle,
                                                                  ),
                                                                  color: FlutterFlowTheme.of(
                                                                          context)
                                                                      .primaryText,
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleSmall
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleSmall
                                                                      .fontStyle,
                                                                ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      Text(
                                                        functions.concatRoute(
                                                            upcomingOrderItem
                                                                .fromCity,
                                                            upcomingOrderItem
                                                                .toCity)!,
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodySmall
                                                                .override(
                                                                  font:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodySmall
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodySmall
                                                                        .fontStyle,
                                                                  ),
                                                                  color: FlutterFlowTheme.of(
                                                                          context)
                                                                      .secondaryText,
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodySmall
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodySmall
                                                                      .fontStyle,
                                                                ),
                                                      ),
                                                    ].divide(const SizedBox(
                                                        height: 2.0)),
                                                  ),
                                                ),
                                                Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.start,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.end,
                                                  children: [
                                                    Text(
                                                      functions.formatDate(
                                                          upcomingOrderItem
                                                              .moveDate)!,
                                                      style:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .bodySmall
                                                              .override(
                                                                font:
                                                                    GoogleFonts
                                                                        .inter(
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodySmall
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodySmall
                                                                      .fontStyle,
                                                                ),
                                                                color: FlutterFlowTheme.of(
                                                                        context)
                                                                    .primaryText,
                                                                letterSpacing:
                                                                    0.0,
                                                                fontWeight: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodySmall
                                                                    .fontWeight,
                                                                fontStyle: FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodySmall
                                                                    .fontStyle,
                                                              ),
                                                    ),
                                                    Container(
                                                      decoration: BoxDecoration(
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .primary,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12.0),
                                                      ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsetsDirectional
                                                                .fromSTEB(8.0,
                                                                2.0, 8.0, 2.0),
                                                        child: Text(
                                                          upcomingOrderItem
                                                              .status!,
                                                          style: FlutterFlowTheme
                                                                  .of(context)
                                                              .labelSmall
                                                              .override(
                                                                font:
                                                                    GoogleFonts
                                                                        .inter(
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelSmall
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelSmall
                                                                      .fontStyle,
                                                                ),
                                                                color: FlutterFlowTheme.of(
                                                                        context)
                                                                    .primaryBackground,
                                                                letterSpacing:
                                                                    0.0,
                                                                fontWeight: FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelSmall
                                                                    .fontWeight,
                                                                fontStyle: FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelSmall
                                                                    .fontStyle,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ].divide(const SizedBox(
                                                      height: 4.0)),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ].divide(const SizedBox(height: 10.0)),
                            ),
                          ),
                        ),
                        Container(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                16.0, 0.0, 16.0, 0.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      AppLocalizations.of(context).hotLeads,
                                      style: FlutterFlowTheme.of(context)
                                          .titleSmall
                                          .override(
                                            font: GoogleFonts.interTight(
                                              fontWeight:
                                                  FlutterFlowTheme.of(context)
                                                      .titleSmall
                                                      .fontWeight,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .titleSmall
                                                      .fontStyle,
                                            ),
                                            color: FlutterFlowTheme.of(context)
                                                .primaryText,
                                            letterSpacing: 0.0,
                                            fontWeight:
                                                FlutterFlowTheme.of(context)
                                                    .titleSmall
                                                    .fontWeight,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .titleSmall
                                                    .fontStyle,
                                          ),
                                    ),
                                    FFButtonWidget(
                                      onPressed: () async {
                                        context.pushNamed(
                                            LeadsPageWidget.routeName);
                                      },
                                      text: AppLocalizations.of(context).viewAll,
                                      options: FFButtonOptions(
                                        padding: const EdgeInsetsDirectional
                                            .fromSTEB(0.0, 0.0, 0.0, 0.0),
                                        iconPadding: const EdgeInsetsDirectional
                                            .fromSTEB(0.0, 0.0, 0.0, 0.0),
                                        color: Colors.transparent,
                                        textStyle: TextStyle(
                                          color: FlutterFlowTheme.of(context)
                                              .primary,
                                        ),
                                        borderSide: BorderSide(
                                          color: FlutterFlowTheme.of(context)
                                              .primary,
                                          width: 1.0,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(8.0),
                                      ),
                                    ),
                                  ],
                                ),
                                Builder(
                                  builder: (context) {
                                    final hotLead = _model.hotLeads.toList();

                                    if (hotLead.isEmpty) {
                                      return _dashboardEmptyState(
                                        context,
                                        icon: Icons.person_add_alt_outlined,
                                        message: 'No leads yet',
                                        actionLabel: 'Add a lead',
                                        onAction: () => context.pushNamed(
                                            NewLeadPageWidget.routeName),
                                      );
                                    }

                                    return ListView.separated(
                                      padding: EdgeInsets.zero,
                                      primary: false,
                                      shrinkWrap: true,
                                      scrollDirection: Axis.vertical,
                                      itemCount: hotLead.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 8.0),
                                      itemBuilder: (context, hotLeadIndex) {
                                        final hotLeadItem =
                                            hotLead[hotLeadIndex];
                                        return Container(
                                          decoration: BoxDecoration(
                                            color: FlutterFlowTheme.of(context)
                                                .secondaryBackground,
                                            borderRadius:
                                                BorderRadius.circular(10.0),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12.0),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.max,
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Flexible(
                                                  flex: 1,
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.start,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        hotLeadItem.customer,
                                                        maxLines: 1,
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .titleSmall
                                                                .override(
                                                                  font: GoogleFonts
                                                                      .interTight(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleSmall
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleSmall
                                                                        .fontStyle,
                                                                  ),
                                                                  color: FlutterFlowTheme.of(
                                                                          context)
                                                                      .primaryText,
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleSmall
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleSmall
                                                                      .fontStyle,
                                                                ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      Text(
                                                        hotLeadItem.phone!,
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodySmall
                                                                .override(
                                                                  font:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodySmall
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodySmall
                                                                        .fontStyle,
                                                                  ),
                                                                  color: FlutterFlowTheme.of(
                                                                          context)
                                                                      .secondaryText,
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodySmall
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodySmall
                                                                      .fontStyle,
                                                                ),
                                                      ),
                                                    ].divide(const SizedBox(
                                                        height: 2.0)),
                                                  ),
                                                ),
                                                Container(
                                                  decoration: BoxDecoration(
                                                    color: FlutterFlowTheme.of(
                                                            context)
                                                        .primary,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12.0),
                                                  ),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsetsDirectional
                                                            .fromSTEB(
                                                            8.0, 2.0, 8.0, 2.0),
                                                    child: Text(
                                                      hotLeadItem.status!,
                                                      style:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .labelSmall
                                                              .override(
                                                                font:
                                                                    GoogleFonts
                                                                        .inter(
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelSmall
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelSmall
                                                                      .fontStyle,
                                                                ),
                                                                color: FlutterFlowTheme.of(
                                                                        context)
                                                                    .primaryBackground,
                                                                letterSpacing:
                                                                    0.0,
                                                                fontWeight: FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelSmall
                                                                    .fontWeight,
                                                                fontStyle: FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelSmall
                                                                    .fontStyle,
                                                              ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ].divide(const SizedBox(height: 10.0)),
                            ),
                          ),
                        ),
                        // Hidden entirely (not just an empty list under the
                        // header) until at least one branch exists — a
                        // brand-new org has none yet, and a "Branch
                        // Performance" title over nothing reads worse than
                        // no section at all (17 Aug 2026 finding).
                        if (_model.branchStats.isNotEmpty)
                          Container(
                            child: Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  16.0, 0.0, 16.0, 0.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    AppLocalizations.of(context).branchPerformance,
                                    style: FlutterFlowTheme.of(context)
                                        .titleSmall
                                        .override(
                                          font: GoogleFonts.interTight(
                                            fontWeight:
                                                FlutterFlowTheme.of(context)
                                                    .titleSmall
                                                    .fontWeight,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .titleSmall
                                                    .fontStyle,
                                          ),
                                          color: FlutterFlowTheme.of(context)
                                              .primaryText,
                                          letterSpacing: 0.0,
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .titleSmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .titleSmall
                                                  .fontStyle,
                                        ),
                                  ),
                                  Builder(
                                    builder: (context) {
                                      final branchStat =
                                          _model.branchStats.toList();

                                      return ListView.separated(
                                        padding: EdgeInsets.zero,
                                        primary: false,
                                        shrinkWrap: true,
                                        scrollDirection: Axis.vertical,
                                        itemCount: branchStat.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(height: 8.0),
                                        itemBuilder:
                                            (context, branchStatIndex) {
                                          final branchStatItem =
                                              branchStat[branchStatIndex];
                                          return Container(
                                            decoration: BoxDecoration(
                                              color:
                                                  FlutterFlowTheme.of(context)
                                                      .secondaryBackground,
                                              borderRadius:
                                                  BorderRadius.circular(10.0),
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.all(12.0),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.max,
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.start,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        branchStatItem.branch!,
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .titleSmall
                                                                .override(
                                                                  font: GoogleFonts
                                                                      .interTight(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleSmall
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleSmall
                                                                        .fontStyle,
                                                                  ),
                                                                  color: FlutterFlowTheme.of(
                                                                          context)
                                                                      .primaryText,
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleSmall
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleSmall
                                                                      .fontStyle,
                                                                ),
                                                      ),
                                                      Text(
                                                        functions.numStr(
                                                            branchStatItem
                                                                .orderCount)!,
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodySmall
                                                                .override(
                                                                  font:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodySmall
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodySmall
                                                                        .fontStyle,
                                                                  ),
                                                                  color: FlutterFlowTheme.of(
                                                                          context)
                                                                      .secondaryText,
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodySmall
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodySmall
                                                                      .fontStyle,
                                                                ),
                                                      ),
                                                    ].divide(const SizedBox(
                                                        height: 4.0)),
                                                  ),
                                                  Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.start,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.end,
                                                    children: [
                                                      Text(
                                                        functions.inrFormat(
                                                            branchStatItem
                                                                .revenue)!,
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .titleSmall
                                                                .override(
                                                                  font: GoogleFonts
                                                                      .interTight(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleSmall
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleSmall
                                                                        .fontStyle,
                                                                  ),
                                                                  color: FlutterFlowTheme.of(
                                                                          context)
                                                                      .primary,
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleSmall
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleSmall
                                                                      .fontStyle,
                                                                ),
                                                      ),
                                                      Text(
                                                        // Branch margin is
                                                        // suppressed, not
                                                        // zeroed.
                                                        //
                                                        // branch_kpis_view
                                                        // carries NO expense
                                                        // column at all — its
                                                        // net_profit is
                                                        // revenue minus
                                                        // porter commission
                                                        // only, never labour
                                                        // or expenses. So
                                                        // expensesTotal is
                                                        // literally 0 here by
                                                        // construction, and
                                                        // the figure can
                                                        // never be honest
                                                        // until the view is
                                                        // fixed (scheduled
                                                        // with NG-046).
                                                        //
                                                        // Passing a hardcoded
                                                        // 0 is deliberate and
                                                        // self-correcting:
                                                        // when the view gains
                                                        // a real expenses
                                                        // column this becomes
                                                        // that field and the
                                                        // margin starts
                                                        // rendering, with no
                                                        // other change.
                                                        marginIsMeaningful(
                                                          expensesTotal: 0,
                                                          orderCount:
                                                              (branchStatItem
                                                                          .orderCount ??
                                                                      0)
                                                                  .toInt(),
                                                        )
                                                            ? functions.marginPct(
                                                                branchStatItem
                                                                    .netProfit,
                                                                branchStatItem
                                                                    .revenue)!
                                                            : kMarginUnavailableTitle,
                                                        style:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodySmall
                                                                .override(
                                                                  font:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodySmall
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .bodySmall
                                                                        .fontStyle,
                                                                  ),
                                                                  color: FlutterFlowTheme.of(
                                                                          context)
                                                                      .secondaryText,
                                                                  letterSpacing:
                                                                      0.0,
                                                                  fontWeight: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodySmall
                                                                      .fontWeight,
                                                                  fontStyle: FlutterFlowTheme.of(
                                                                          context)
                                                                      .bodySmall
                                                                      .fontStyle,
                                                                ),
                                                      ),
                                                    ].divide(const SizedBox(
                                                        height: 4.0)),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ].divide(const SizedBox(height: 10.0)),
                              ),
                            ),
                          ),
                        Container(
                          height: 100.0,
                        ),
                      ].divide(const SizedBox(height: 20.0)),
                    ),
                  ].divide(const SizedBox(height: 24.0)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
