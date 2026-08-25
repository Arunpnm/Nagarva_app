import '/app_session.dart';
import '/backend/session_logout.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/components/global_search_delegate.dart';
import '/components/notification_bell.dart';
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
  // Current-state fields from dashboard_kpis_view that do NOT follow the
  // period filter (see HomePageModel.periodType doc comment).
  double _activeLeads = 0;
  double _outstandingAmount = 0;
  double _remindersToday = 0;

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

    final revenue = periodOrders.fold(0.0, (s, o) => s + (o.amount ?? 0));
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
    final expenses = _allExpenses
        .where((e) => _inRange(
            e.orderId != null
                ? (e.expenseDate ?? DateTime.now())
                : (e.expenseDate ?? e.createdAt ?? DateTime.now()),
            start,
            end))
        .fold(0.0, (s, e) => s + (e.amount ?? 0));
    final porterCommission = _model.porterEnabled
        ? periodOrders
            .where((o) => o.isPorter ?? (o.orderSource == 'porter'))
            .fold(
                0.0,
                (s,
                        o) =>
                    s +
                    ((o.amount ?? 0) * ((o.porterCommissionPct ?? 16) / 100))
                        .roundToDouble())
        : 0.0;

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
    // items (SupJobsComingSoon, MyAttComingSoon, ...) aren't in
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
                        FFLocalizations.of(context).getText(
                          'qnj2ddkf' /* Logout */,
                        ),
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
          title: Text(
            FFLocalizations.of(context).getText(
              'h4khyrfl' /* Dashboard */,
            ),
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
                        Container(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                16.0, 0.0, 16.0, 0.0),
                            child: Builder(
                              builder: (context) {
                                final kpiListItem = _model.kpiList.toList();

                                return ListView.builder(
                                  padding: EdgeInsets.zero,
                                  primary: false,
                                  shrinkWrap: true,
                                  scrollDirection: Axis.vertical,
                                  itemCount: kpiListItem.length,
                                  itemBuilder: (context, kpiListItemIndex) {
                                    final kpiListItemItem =
                                        kpiListItem[kpiListItemIndex];
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        // REVENUE / LABOUR / EXPENSES.
                                        //
                                        // MISSED BY 6380f32 (25 Aug 2026).
                                        // That commit retargeted the period
                                        // selector and MONTHLY TARGET to
                                        // canActive() but left these three on
                                        // the session-shape test, because the
                                        // condition is line-wrapped as
                                        // `currentStaffId ==\n null` and the
                                        // sweep grepped for the unwrapped
                                        // form. So the reported fix was only
                                        // two thirds applied and a manager
                                        // still lost exactly the cards Arun
                                        // originally reported missing.
                                        //
                                        // Tiered per the 25 Aug split:
                                        // revenue is financials.view; labour
                                        // and expenses are cost, so the block
                                        // needs the margin tier too. Gated on
                                        // the broader of the two here and the
                                        // cost cards re-checked individually
                                        // as the redesign splits this row.
                                        if (StaffPermissions.canActive(
                                            'financials', 'view'))
                                          Column(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                _periodLabel(),
                                                style: FlutterFlowTheme.of(
                                                        context)
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
                                                      color:
                                                          FlutterFlowTheme.of(
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
                                              SingleChildScrollView(
                                                scrollDirection:
                                                    Axis.horizontal,
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.max,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.start,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    InkWell(
                                                      splashColor:
                                                          Colors.transparent,
                                                      focusColor:
                                                          Colors.transparent,
                                                      hoverColor:
                                                          Colors.transparent,
                                                      highlightColor:
                                                          Colors.transparent,
                                                      onTap: () async {
                                                        context.pushNamed(
                                                            AccountsPageWidget
                                                                .routeName);
                                                      },
                                                      child: Container(
                                                        width: 110.0,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .secondaryBackground,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(12.0),
                                                          child: Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .start,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                FFLocalizations.of(
                                                                        context)
                                                                    .getText(
                                                                  'hcn3mg5q' /* REVENUE */,
                                                                ),
                                                                maxLines: 1,
                                                                style: FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelSmall
                                                                    .override(
                                                                      font: GoogleFonts
                                                                          .inter(
                                                                        fontWeight: FlutterFlowTheme.of(context)
                                                                            .labelSmall
                                                                            .fontWeight,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .labelSmall
                                                                            .fontStyle,
                                                                      ),
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .secondaryText,
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
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                              Text(
                                                                functions.inrFormat(
                                                                    kpiListItemItem
                                                                        .revenueThisMonth)!,
                                                                style: FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleMedium
                                                                    .override(
                                                                      font: GoogleFonts
                                                                          .interTight(
                                                                        fontWeight: FlutterFlowTheme.of(context)
                                                                            .titleMedium
                                                                            .fontWeight,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .titleMedium
                                                                            .fontStyle,
                                                                      ),
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .primary,
                                                                      letterSpacing:
                                                                          0.0,
                                                                      fontWeight: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleMedium
                                                                          .fontWeight,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleMedium
                                                                          .fontStyle,
                                                                    ),
                                                              ),
                                                            ].divide(
                                                                const SizedBox(
                                                                    height:
                                                                        6.0)),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    InkWell(
                                                      splashColor:
                                                          Colors.transparent,
                                                      focusColor:
                                                          Colors.transparent,
                                                      hoverColor:
                                                          Colors.transparent,
                                                      highlightColor:
                                                          Colors.transparent,
                                                      onTap: () async {
                                                        context.pushNamed(
                                                            SalaryPageWidget
                                                                .routeName);
                                                      },
                                                      child: Container(
                                                        width: 110.0,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .secondaryBackground,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(12.0),
                                                          child: Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .start,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                FFLocalizations.of(
                                                                        context)
                                                                    .getText(
                                                                  'rfsdygn1' /* LABOUR */,
                                                                ),
                                                                maxLines: 1,
                                                                style: FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelSmall
                                                                    .override(
                                                                      font: GoogleFonts
                                                                          .inter(
                                                                        fontWeight: FlutterFlowTheme.of(context)
                                                                            .labelSmall
                                                                            .fontWeight,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .labelSmall
                                                                            .fontStyle,
                                                                      ),
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .secondaryText,
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
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                              Text(
                                                                functions.inrFormat(
                                                                    kpiListItemItem
                                                                        .labourThisMonth)!,
                                                                style: FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleMedium
                                                                    .override(
                                                                      font: GoogleFonts
                                                                          .interTight(
                                                                        fontWeight: FlutterFlowTheme.of(context)
                                                                            .titleMedium
                                                                            .fontWeight,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .titleMedium
                                                                            .fontStyle,
                                                                      ),
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .secondary,
                                                                      letterSpacing:
                                                                          0.0,
                                                                      fontWeight: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleMedium
                                                                          .fontWeight,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleMedium
                                                                          .fontStyle,
                                                                    ),
                                                              ),
                                                            ].divide(
                                                                const SizedBox(
                                                                    height:
                                                                        6.0)),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    InkWell(
                                                      splashColor:
                                                          Colors.transparent,
                                                      focusColor:
                                                          Colors.transparent,
                                                      hoverColor:
                                                          Colors.transparent,
                                                      highlightColor:
                                                          Colors.transparent,
                                                      onTap: () async {
                                                        context.pushNamed(
                                                            ExpensePageWidget
                                                                .routeName);
                                                      },
                                                      child: Container(
                                                        width: 110.0,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .secondaryBackground,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(12.0),
                                                          child: Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .start,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                FFLocalizations.of(
                                                                        context)
                                                                    .getText(
                                                                  'kvr8zst0' /* EXPENSES */,
                                                                ),
                                                                maxLines: 1,
                                                                style: FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelSmall
                                                                    .override(
                                                                      font: GoogleFonts
                                                                          .inter(
                                                                        fontWeight: FlutterFlowTheme.of(context)
                                                                            .labelSmall
                                                                            .fontWeight,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .labelSmall
                                                                            .fontStyle,
                                                                      ),
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .secondaryText,
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
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                              Text(
                                                                functions.inrFormat(
                                                                    kpiListItemItem
                                                                        .expensesThisMonth)!,
                                                                style: FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleMedium
                                                                    .override(
                                                                      font: GoogleFonts
                                                                          .interTight(
                                                                        fontWeight: FlutterFlowTheme.of(context)
                                                                            .titleMedium
                                                                            .fontWeight,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .titleMedium
                                                                            .fontStyle,
                                                                      ),
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .error,
                                                                      letterSpacing:
                                                                          0.0,
                                                                      fontWeight: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleMedium
                                                                          .fontWeight,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleMedium
                                                                          .fontStyle,
                                                                    ),
                                                              ),
                                                            ].divide(
                                                                const SizedBox(
                                                                    height:
                                                                        6.0)),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    // Porter is Bengaluru/APC-specific — pan-India vendors may not
                                                    // use Porter at all, so the card only shows when the vendor
                                                    // turns it on (settings key 'porter_enabled', read on load).
                                                    if (_model.porterEnabled)
                                                      InkWell(
                                                        splashColor:
                                                            Colors.transparent,
                                                        focusColor:
                                                            Colors.transparent,
                                                        hoverColor:
                                                            Colors.transparent,
                                                        highlightColor:
                                                            Colors.transparent,
                                                        onTap: () async {
                                                          context.pushNamed(
                                                              AccountsPageWidget
                                                                  .routeName);
                                                        },
                                                        child: Container(
                                                          width: 110.0,
                                                          decoration:
                                                              BoxDecoration(
                                                            color: FlutterFlowTheme
                                                                    .of(context)
                                                                .secondaryBackground,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        12.0),
                                                          ),
                                                          child: Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .all(12.0),
                                                            child: Column(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .start,
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                  FFLocalizations.of(
                                                                          context)
                                                                      .getText(
                                                                    'qw1ilngk' /* PORTER */,
                                                                  ),
                                                                  maxLines: 1,
                                                                  style: FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelSmall
                                                                      .override(
                                                                        font: GoogleFonts
                                                                            .inter(
                                                                          fontWeight: FlutterFlowTheme.of(context)
                                                                              .labelSmall
                                                                              .fontWeight,
                                                                          fontStyle: FlutterFlowTheme.of(context)
                                                                              .labelSmall
                                                                              .fontStyle,
                                                                        ),
                                                                        color: FlutterFlowTheme.of(context)
                                                                            .secondaryText,
                                                                        letterSpacing:
                                                                            0.0,
                                                                        fontWeight: FlutterFlowTheme.of(context)
                                                                            .labelSmall
                                                                            .fontWeight,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .labelSmall
                                                                            .fontStyle,
                                                                      ),
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                                Text(
                                                                  functions.inrFormat(
                                                                      kpiListItemItem
                                                                          .porterCommThisMonth)!,
                                                                  style: FlutterFlowTheme.of(
                                                                          context)
                                                                      .titleMedium
                                                                      .override(
                                                                        font: GoogleFonts
                                                                            .interTight(
                                                                          fontWeight: FlutterFlowTheme.of(context)
                                                                              .titleMedium
                                                                              .fontWeight,
                                                                          fontStyle: FlutterFlowTheme.of(context)
                                                                              .titleMedium
                                                                              .fontStyle,
                                                                        ),
                                                                        color: FlutterFlowTheme.of(context)
                                                                            .tertiary,
                                                                        letterSpacing:
                                                                            0.0,
                                                                        fontWeight: FlutterFlowTheme.of(context)
                                                                            .titleMedium
                                                                            .fontWeight,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .titleMedium
                                                                            .fontStyle,
                                                                      ),
                                                                ),
                                                              ].divide(
                                                                  const SizedBox(
                                                                      height:
                                                                          6.0)),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    InkWell(
                                                      splashColor:
                                                          Colors.transparent,
                                                      focusColor:
                                                          Colors.transparent,
                                                      hoverColor:
                                                          Colors.transparent,
                                                      highlightColor:
                                                          Colors.transparent,
                                                      onTap: () async {
                                                        context.pushNamed(
                                                            PLReportPageWidget
                                                                .routeName);
                                                      },
                                                      child: Container(
                                                        width: 110.0,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .secondaryBackground,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(12.0),
                                                          child: Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .start,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                FFLocalizations.of(
                                                                        context)
                                                                    .getText(
                                                                  'menno776' /* NET PROFIT */,
                                                                ),
                                                                maxLines: 1,
                                                                style: FlutterFlowTheme.of(
                                                                        context)
                                                                    .labelSmall
                                                                    .override(
                                                                      font: GoogleFonts
                                                                          .inter(
                                                                        fontWeight: FlutterFlowTheme.of(context)
                                                                            .labelSmall
                                                                            .fontWeight,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .labelSmall
                                                                            .fontStyle,
                                                                      ),
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .secondaryText,
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
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                              Text(
                                                                functions.inrFormat(
                                                                    kpiListItemItem
                                                                        .netProfitThisMonth)!,
                                                                style: FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleMedium
                                                                    .override(
                                                                      font: GoogleFonts
                                                                          .interTight(
                                                                        fontWeight: FlutterFlowTheme.of(context)
                                                                            .titleMedium
                                                                            .fontWeight,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .titleMedium
                                                                            .fontStyle,
                                                                      ),
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .primary,
                                                                      letterSpacing:
                                                                          0.0,
                                                                      fontWeight: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleMedium
                                                                          .fontWeight,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleMedium
                                                                          .fontStyle,
                                                                    ),
                                                              ),
                                                            ].divide(
                                                                const SizedBox(
                                                                    height:
                                                                        6.0)),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ].divide(const SizedBox(
                                                      width: 10.0)),
                                                ),
                                              ),
                                            ].divide(
                                                const SizedBox(height: 8.0)),
                                          ),
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment:
                                              MainAxisAlignment.start,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.max,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.start,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Flexible(
                                                  flex: 1,
                                                  child: InkWell(
                                                    splashColor:
                                                        Colors.transparent,
                                                    focusColor:
                                                        Colors.transparent,
                                                    hoverColor:
                                                        Colors.transparent,
                                                    highlightColor:
                                                        Colors.transparent,
                                                    onTap: () async {
                                                      context.pushNamed(
                                                          LeadsPageWidget
                                                              .routeName);
                                                    },
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        color: FlutterFlowTheme
                                                                .of(context)
                                                            .secondaryBackground,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12.0),
                                                      ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(14.0),
                                                        child: Column(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .start,
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .max,
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .spaceBetween,
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .center,
                                                              children: [
                                                                Text(
                                                                  FFLocalizations.of(
                                                                          context)
                                                                      .getText(
                                                                    'sqtdznm5' /* ACTIVE LEADS */,
                                                                  ),
                                                                  maxLines: 1,
                                                                  style: FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelSmall
                                                                      .override(
                                                                        font: GoogleFonts
                                                                            .inter(
                                                                          fontWeight: FlutterFlowTheme.of(context)
                                                                              .labelSmall
                                                                              .fontWeight,
                                                                          fontStyle: FlutterFlowTheme.of(context)
                                                                              .labelSmall
                                                                              .fontStyle,
                                                                        ),
                                                                        color: FlutterFlowTheme.of(context)
                                                                            .secondaryText,
                                                                        letterSpacing:
                                                                            0.0,
                                                                        fontWeight: FlutterFlowTheme.of(context)
                                                                            .labelSmall
                                                                            .fontWeight,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .labelSmall
                                                                            .fontStyle,
                                                                      ),
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                                Icon(
                                                                  Icons.people,
                                                                  color: FlutterFlowTheme.of(
                                                                          context)
                                                                      .primary,
                                                                  size: 16.0,
                                                                ),
                                                              ],
                                                            ),
                                                            Text(
                                                              functions.numStr(
                                                                  kpiListItemItem
                                                                      .activeLeads)!,
                                                              style: FlutterFlowTheme
                                                                      .of(context)
                                                                  .titleLarge
                                                                  .override(
                                                                    font: GoogleFonts
                                                                        .interTight(
                                                                      fontWeight: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleLarge
                                                                          .fontWeight,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleLarge
                                                                          .fontStyle,
                                                                    ),
                                                                    color: FlutterFlowTheme.of(
                                                                            context)
                                                                        .primaryText,
                                                                    letterSpacing:
                                                                        0.0,
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontStyle,
                                                                  ),
                                                            ),
                                                          ].divide(
                                                              const SizedBox(
                                                                  height: 8.0)),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Flexible(
                                                  flex: 1,
                                                  child: InkWell(
                                                    splashColor:
                                                        Colors.transparent,
                                                    focusColor:
                                                        Colors.transparent,
                                                    hoverColor:
                                                        Colors.transparent,
                                                    highlightColor:
                                                        Colors.transparent,
                                                    onTap: () async {
                                                      context.pushNamed(
                                                          OrdersPageWidget
                                                              .routeName);
                                                    },
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        color: FlutterFlowTheme
                                                                .of(context)
                                                            .secondaryBackground,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12.0),
                                                      ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(14.0),
                                                        child: Column(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .start,
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .max,
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .spaceBetween,
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .center,
                                                              children: [
                                                                Text(
                                                                  FFLocalizations.of(
                                                                          context)
                                                                      .getText(
                                                                    'pf004ktv' /* ORDERS/MONTH */,
                                                                  ),
                                                                  maxLines: 1,
                                                                  style: FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelSmall
                                                                      .override(
                                                                        font: GoogleFonts
                                                                            .inter(
                                                                          fontWeight: FlutterFlowTheme.of(context)
                                                                              .labelSmall
                                                                              .fontWeight,
                                                                          fontStyle: FlutterFlowTheme.of(context)
                                                                              .labelSmall
                                                                              .fontStyle,
                                                                        ),
                                                                        color: FlutterFlowTheme.of(context)
                                                                            .secondaryText,
                                                                        letterSpacing:
                                                                            0.0,
                                                                        fontWeight: FlutterFlowTheme.of(context)
                                                                            .labelSmall
                                                                            .fontWeight,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .labelSmall
                                                                            .fontStyle,
                                                                      ),
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                                Icon(
                                                                  Icons
                                                                      .assignment,
                                                                  color: FlutterFlowTheme.of(
                                                                          context)
                                                                      .primary,
                                                                  size: 16.0,
                                                                ),
                                                              ],
                                                            ),
                                                            Text(
                                                              functions.numStr(
                                                                  kpiListItemItem
                                                                      .ordersThisMonth)!,
                                                              style: FlutterFlowTheme
                                                                      .of(context)
                                                                  .titleLarge
                                                                  .override(
                                                                    font: GoogleFonts
                                                                        .interTight(
                                                                      fontWeight: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleLarge
                                                                          .fontWeight,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleLarge
                                                                          .fontStyle,
                                                                    ),
                                                                    color: FlutterFlowTheme.of(
                                                                            context)
                                                                        .primaryText,
                                                                    letterSpacing:
                                                                        0.0,
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontStyle,
                                                                  ),
                                                            ),
                                                          ].divide(
                                                              const SizedBox(
                                                                  height: 8.0)),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ].divide(
                                                  const SizedBox(width: 10.0)),
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.max,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.start,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                // OUTSTANDING. Same miss as
                                                // the block above — see its
                                                // comment. Outstanding is
                                                // receivables, not margin, so
                                                // it sits in financials.view.
                                                if (StaffPermissions.canActive(
                                                    'financials', 'view'))
                                                  Flexible(
                                                    flex: 1,
                                                    child: InkWell(
                                                      splashColor:
                                                          Colors.transparent,
                                                      focusColor:
                                                          Colors.transparent,
                                                      hoverColor:
                                                          Colors.transparent,
                                                      highlightColor:
                                                          Colors.transparent,
                                                      onTap: () async {
                                                        context.pushNamed(
                                                            PaymentsPageWidget
                                                                .routeName);
                                                      },
                                                      child: Container(
                                                        decoration:
                                                            BoxDecoration(
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .secondaryBackground,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12.0),
                                                        ),
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(14.0),
                                                          child: Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .start,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Row(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .max,
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .spaceBetween,
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .center,
                                                                children: [
                                                                  Text(
                                                                    FFLocalizations.of(
                                                                            context)
                                                                        .getText(
                                                                      'ro873yv3' /* OUTSTANDING */,
                                                                    ),
                                                                    maxLines: 1,
                                                                    style: FlutterFlowTheme.of(
                                                                            context)
                                                                        .labelSmall
                                                                        .override(
                                                                          font:
                                                                              GoogleFonts.inter(
                                                                            fontWeight:
                                                                                FlutterFlowTheme.of(context).labelSmall.fontWeight,
                                                                            fontStyle:
                                                                                FlutterFlowTheme.of(context).labelSmall.fontStyle,
                                                                          ),
                                                                          color:
                                                                              FlutterFlowTheme.of(context).secondaryText,
                                                                          letterSpacing:
                                                                              0.0,
                                                                          fontWeight: FlutterFlowTheme.of(context)
                                                                              .labelSmall
                                                                              .fontWeight,
                                                                          fontStyle: FlutterFlowTheme.of(context)
                                                                              .labelSmall
                                                                              .fontStyle,
                                                                        ),
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                  Icon(
                                                                    Icons
                                                                        .payments,
                                                                    color: FlutterFlowTheme.of(
                                                                            context)
                                                                        .primary,
                                                                    size: 16.0,
                                                                  ),
                                                                ],
                                                              ),
                                                              Text(
                                                                functions.inrFormat(
                                                                    kpiListItemItem
                                                                        .outstandingAmount)!,
                                                                style: FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleLarge
                                                                    .override(
                                                                      font: GoogleFonts
                                                                          .interTight(
                                                                        fontWeight: FlutterFlowTheme.of(context)
                                                                            .titleLarge
                                                                            .fontWeight,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .titleLarge
                                                                            .fontStyle,
                                                                      ),
                                                                      color: FlutterFlowTheme.of(
                                                                              context)
                                                                          .primaryText,
                                                                      letterSpacing:
                                                                          0.0,
                                                                      fontWeight: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleLarge
                                                                          .fontWeight,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleLarge
                                                                          .fontStyle,
                                                                    ),
                                                              ),
                                                            ].divide(
                                                                const SizedBox(
                                                                    height:
                                                                        8.0)),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                Flexible(
                                                  flex: 1,
                                                  child: InkWell(
                                                    splashColor:
                                                        Colors.transparent,
                                                    focusColor:
                                                        Colors.transparent,
                                                    hoverColor:
                                                        Colors.transparent,
                                                    highlightColor:
                                                        Colors.transparent,
                                                    onTap: () async {
                                                      context.pushNamed(
                                                          CalendarPageWidget
                                                              .routeName);
                                                    },
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        color: FlutterFlowTheme
                                                                .of(context)
                                                            .secondaryBackground,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12.0),
                                                      ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(14.0),
                                                        child: Column(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .start,
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .max,
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .spaceBetween,
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .center,
                                                              children: [
                                                                Text(
                                                                  FFLocalizations.of(
                                                                          context)
                                                                      .getText(
                                                                    '5iyib1aw' /* REMINDERS */,
                                                                  ),
                                                                  maxLines: 1,
                                                                  style: FlutterFlowTheme.of(
                                                                          context)
                                                                      .labelSmall
                                                                      .override(
                                                                        font: GoogleFonts
                                                                            .inter(
                                                                          fontWeight: FlutterFlowTheme.of(context)
                                                                              .labelSmall
                                                                              .fontWeight,
                                                                          fontStyle: FlutterFlowTheme.of(context)
                                                                              .labelSmall
                                                                              .fontStyle,
                                                                        ),
                                                                        color: FlutterFlowTheme.of(context)
                                                                            .secondaryText,
                                                                        letterSpacing:
                                                                            0.0,
                                                                        fontWeight: FlutterFlowTheme.of(context)
                                                                            .labelSmall
                                                                            .fontWeight,
                                                                        fontStyle: FlutterFlowTheme.of(context)
                                                                            .labelSmall
                                                                            .fontStyle,
                                                                      ),
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                                Icon(
                                                                  Icons
                                                                      .notifications,
                                                                  color: FlutterFlowTheme.of(
                                                                          context)
                                                                      .primary,
                                                                  size: 16.0,
                                                                ),
                                                              ],
                                                            ),
                                                            Text(
                                                              functions.numStr(
                                                                  kpiListItemItem
                                                                      .remindersToday)!,
                                                              style: FlutterFlowTheme
                                                                      .of(context)
                                                                  .titleLarge
                                                                  .override(
                                                                    font: GoogleFonts
                                                                        .interTight(
                                                                      fontWeight: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleLarge
                                                                          .fontWeight,
                                                                      fontStyle: FlutterFlowTheme.of(
                                                                              context)
                                                                          .titleLarge
                                                                          .fontStyle,
                                                                    ),
                                                                    color: FlutterFlowTheme.of(
                                                                            context)
                                                                        .primaryText,
                                                                    letterSpacing:
                                                                        0.0,
                                                                    fontWeight: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontWeight,
                                                                    fontStyle: FlutterFlowTheme.of(
                                                                            context)
                                                                        .titleLarge
                                                                        .fontStyle,
                                                                  ),
                                                            ),
                                                          ].divide(
                                                              const SizedBox(
                                                                  height: 8.0)),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ].divide(
                                                  const SizedBox(width: 10.0)),
                                            ),
                                          ].divide(
                                              const SizedBox(height: 10.0)),
                                        ),
                                      ].divide(const SizedBox(height: 16.0)),
                                    );
                                  },
                                );
                              },
                            ),
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
                                            FFLocalizations.of(context).getText(
                                              'sxcnle6g' /* MONTHLY TARGET */,
                                            ),
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
                                            text: FFLocalizations.of(context)
                                                .getText(
                                              'obpyg706' /* Edit */,
                                            ),
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
                                                functions.inrFormat(
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
                                              Text(
                                                FFLocalizations.of(context)
                                                    .getText(
                                                  'znesy4lh' /* target this month */,
                                                ),
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
                                                        FFLocalizations.of(
                                                                context)
                                                            .getText(
                                                      '00jbmaqj' /* e.g. 200000 */,
                                                    ),
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
                                                  _model.monthlyTarget =
                                                      functions.parseDouble(_model
                                                          .targetInputFieldTextController
                                                          .text);
                                                  safeSetState(() {});
                                                  _model.showEditTarget = false;
                                                  safeSetState(() {});
                                                },
                                                text:
                                                    FFLocalizations.of(context)
                                                        .getText(
                                                  'n6etw2aj' /* Save */,
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
                                      FFLocalizations.of(context).getText(
                                        'xfquvso3' /* Upcoming Orders */,
                                      ),
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
                                      text: FFLocalizations.of(context).getText(
                                        'nabcn7ke' /* Calendar -> */,
                                      ),
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
                                      FFLocalizations.of(context).getText(
                                        'rk49x1s9' /* Hot Leads */,
                                      ),
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
                                      text: FFLocalizations.of(context).getText(
                                        '6rjhf88o' /* View All -> */,
                                      ),
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
                                    FFLocalizations.of(context).getText(
                                      'i093rsaw' /* BRANCH PERFORMANCE */,
                                    ),
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
                                                        functions.marginPct(
                                                            branchStatItem
                                                                .netProfit,
                                                            branchStatItem
                                                                .revenue)!,
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
