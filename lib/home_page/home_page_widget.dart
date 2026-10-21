import '/app_session.dart';
import '/backend/commission_pricing.dart';
import '/backend/field_expenses.dart';
import '/backend/storage_billing.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/margin_availability.dart';
import '/backend/detail_navigation.dart';
import '/backend/lead_status.dart';
import '/backend/order_stages.dart';
import '/components/dashboard_kpi_grid.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/backend/module_navigation.dart';
import '/backend/reminders_service.dart';
import 'dashboard_sections.dart';
import '/index.dart';
import '/nav_items.dart';
import '/permissions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

  /// Open reminders due today, for Today's plan, and the overdue count
  /// for its row (item 10.5, formerly FollowUpSummaryCard).
  List<RemindersRow> _todayReminders = const [];
  int _overdueFollowUps = 0;

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
    // Item 10.7: a follow-up completed on a lead must update the
    // dashboard count on the way back; _loadDashboard reloads reminders.
    _loadDashboard();
  }

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
    await _loadReminders();
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

  Future<void> _loadReminders() async {
    try {
      final rows = await RemindersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('status', kReminderOpen),
      );
      final now = DateTime.now();
      final today = <RemindersRow>[];
      var overdue = 0;
      for (final r in rows) {
        final d = r.dueDate?.toLocal();
        if (d == null) continue;
        final sameDay =
            d.year == now.year && d.month == now.month && d.day == now.day;
        if (sameDay) {
          today.add(r);
        } else if (d.isBefore(now)) {
          overdue++;
        }
      }
      _todayReminders = today;
      _overdueFollowUps = overdue;
    } catch (_) {
      // A failed read leaves the agenda without reminders rather than
      // blanking the dashboard.
      _todayReminders = const [];
      _overdueFollowUps = 0;
    }
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
            style: NgFonts.geist(color: theme.secondaryText, fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onAction,
            child: Text(
              actionLabel,
              style: NgFonts.geist(
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

  /// Where each dashboard tile leads.
  ///
  /// Arun, 3 Sept 2026: *"in dashboard we can check all our reports or
  /// status, like how many enquires, quotes, bookings, revenue etc, can
  /// u wire everything so that if i press that it should take to that
  /// page, now its just viewable"*. `DashboardKpiGrid` has taken an
  /// `onTapTile` since it was built and HomePage never passed one, so
  /// every populated tile was inert - a number with no way through to
  /// the rows behind it.
  ///
  /// Reminders leads to the Calendar because that is the only screen
  /// that renders `reminders_view`. It is also the one destination with
  /// no permission module of its own, so [_canOpen] leaves the tile
  /// inert for a staff session rather than sending them somewhere the
  /// nav guard will bounce them out of.
  static const _kTileDestinations = <String, String>{
    'enquiries': 'LeadsPage',
    'quotes': 'SurveyQuoteHubPage',
    'bookings': 'OrdersPage',
    'active_moves': 'OperationsPage',
    'reminders': 'CalendarPage',
    // Revenue opens ACCOUNTS, not Payments (Arun, 3 Sept 2026).
    // Accounts is the Daily Accounts Register - revenue, collections and
    // costs by day, which is the breakdown BEHIND the revenue figure.
    // Payments is a list of who still owes, which is what Outstanding
    // means and is a different question about the same money.
    'revenue': 'AccountsPage',
    'outstanding': 'PaymentsPage',
    'labour': 'SalaryPage',
    'profit': 'PLReportPage',
    'expenses': 'ExpensePage',
  };

  /// Mirrors the drawer and the nav rail exactly, so a tile can never
  /// offer a route those two hide. Owner: everything.
  bool _canOpen(String pageName) {
    final allowed =
        isOwnerOrManagerSession && AppSession.instance.currentStaffId != null
            ? (StaffPermissions.activeStaffPages ??
                const {'HomePage', 'OrdersPage', 'OperationsPage'})
            : null;
    return allowed == null || allowed.contains(pageName);
  }

  void _openKpiTile(String tileId) {
    final page = _kTileDestinations[tileId];
    if (page == null || !_canOpen(page)) return;
    openModule(context, page);
  }

  // ---- Sections (Claude Design handoff, "DASHBOARD A : Focus") ---------
  //
  // Top to bottom, as in the handoff: date and greeting, plan card,
  // Payments due (plus overdue follow-ups when there are any), the three
  // "today" tiles, Today's plan, This month, Hot leads. Branch cards,
  // which the handoff does not draw, stay at the bottom and only render
  // once a branch exists.

  /// Name for the greeting. Owner: `owner_name` from signup metadata;
  /// staff: their own name. Empty when unknown, and the greeting then
  /// stands alone rather than addressing someone by a guess.
  String _greetName() {
    final s = AppSession.instance;
    String full;
    if (s.currentStaffId != null) {
      full = s.currentStaffName ?? '';
    } else {
      final meta = SupaFlow.client.auth.currentUser?.userMetadata ?? {};
      full = (meta['owner_name'] ?? meta['name'] ?? meta['full_name'] ?? '')
          .toString();
    }
    full = full.trim();
    return full.isEmpty ? '' : full.split(RegExp(r'\s+')).first;
  }

  Widget _greeting(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final h = DateTime.now().hour;
    final hello = h < 12
        ? l.ngGreetMorning
        : (h < 17 ? l.ngGreetAfternoon : l.ngGreetEvening);
    final name = _greetName();
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('EEEE, d MMMM', locale).format(DateTime.now()),
            style: NgFonts.geist(fontSize: 13, color: c.mute),
          ),
          const SizedBox(height: 4),
          Text(
            name.isEmpty ? hello : '$hello, $name',
            style: NgFonts.geist(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.52,
              color: c.text,
            ),
          ),
        ],
      ),
    );
  }

  /// Moves on the road, follow-ups due today, and money to collect. The
  /// third tile is money and so sits behind the same 'financials' gate as
  /// every other figure on this page; without it the slot shows open
  /// leads instead of going blank.
  Widget _todayRow(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final money = StaffPermissions.canActive('financials', 'view');
    VoidCallback? go(String page) =>
        _canOpen(page) ? () => openModule(context, page) : null;
    return Row(
      children: [
        Expanded(
          child: NgStatTile(
            icon: Icons.local_shipping_outlined,
            color: c.acc,
            value: functions.numStr(_activeMoves)!,
            label: l.ngTodayMoves,
            onTap: go('OperationsPage'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: NgStatTile(
            icon: Icons.phone_in_talk_outlined,
            color: c.amber,
            value: functions.numStr(_remindersToday)!,
            label: l.ngTodayFollowUps,
            onTap: go('LeadsPage'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: money
              ? NgStatTile(
                  icon: Icons.payments_outlined,
                  color: c.green,
                  value: functions.inrFormat(_outstandingAmount)!,
                  label: l.ngToCollect,
                  onTap: go('PaymentsPage'),
                )
              : NgStatTile(
                  icon: Icons.person_search_outlined,
                  color: c.blue,
                  value: functions.numStr(_activeLeads)!,
                  label: l.ngOpenLeads,
                  onTap: go('LeadsPage'),
                ),
        ),
      ],
    );
  }

  /// Orders the customer still owes on. `payment_status` is maintained by
  /// the trigger on `payment_entries`, so this agrees with Record Payment
  /// without re-deriving the balance here.
  int get _paymentsDueCount => _allOrders.where((o) {
        final st = (o.status ?? '').toLowerCase();
        if (st == 'cancelled') return false;
        final base = (o.quoteTotal ?? 0) > 0 ? o.quoteTotal! : (o.amount ?? 0);
        return base > 0 && o.paymentStatus != 'paid';
      }).length;

  Widget _infoRows(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final rows = <Widget>[];
    if (StaffPermissions.canActive('financials', 'view')) {
      final n = _paymentsDueCount;
      rows.add(DashInfoRow(
        icon: Icons.payments_outlined,
        iconColor: c.amber,
        title: l.ngPaymentsDue,
        value: '$n',
        note: n == 0 ? null : l.ngPaymentsDueSub(n),
        onTap: _canOpen('PaymentsPage')
            ? () => openModule(context, 'PaymentsPage')
            : null,
      ));
    }
    // Item 10.5's overdue count, in the handoff's widget-row form. Not
    // money-gated: staff chase leads too. Hidden at zero.
    if (_overdueFollowUps > 0) {
      rows.add(DashInfoRow(
        icon: Icons.phone_missed_outlined,
        iconColor: c.red,
        title: l.ngOverdueFollowUps,
        value: '$_overdueFollowUps',
        note: l.ngOverdueFollowUpsSub,
        onTap: () => context.pushNamed(LeadsPageWidget.routeName),
      ));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          rows[i],
        ],
      ],
    );
  }

  bool _isToday(DateTime? d) {
    if (d == null) return false;
    final x = d.toLocal(), n = DateTime.now();
    return x.year == n.year && x.month == n.month && x.day == n.day;
  }

  (String, String) _clock(DateTime t) {
    final x = t.toLocal();
    return (DateFormat('h:mm').format(x), DateFormat('a').format(x));
  }

  Widget _agendaSection(BuildContext context) {
    final l = AppLocalizations.of(context);
    final today = <(DateTime?, DashAgendaItem)>[];

    for (final o in _allOrders) {
      final st = (o.status ?? '').toLowerCase();
      if (st == 'cancelled' || !_isToday(o.moveDateOrNull)) continue;
      final start = o.jobStartTime;
      final (t, ap) = start == null ? (l.ngAllDay, '') : _clock(start);
      final stage = orderStageIndex(o.trackingStatus, o.status);
      today.add((
        start,
        DashAgendaItem(
          time: t,
          ampm: ap,
          icon: Icons.local_shipping_outlined,
          tone: NgStatus.accent,
          title: l.ngAgendaMove(o.customer),
          sub: [
            '${o.fromCity ?? ''} → ${o.toCity ?? ''}',
            orderStageLabel(kOrderStages[stage]),
          ].where((x) => x.trim().isNotEmpty).join(' · '),
          onTap: () => openOrderDetail(context, o),
        ),
      ));
    }
    for (final r in _todayReminders) {
      final due = r.dueDate;
      final (t, ap) = due == null ? (l.ngAllDay, '') : _clock(due);
      final isLead = r.entityType == kEntityLead || r.leadId != null;
      today.add((
        due,
        DashAgendaItem(
          time: t,
          ampm: ap,
          icon: isLead ? Icons.call_outlined : Icons.task_alt_outlined,
          tone: isLead ? NgStatus.amber : NgStatus.blue,
          title: r.title ?? '',
          sub: r.description ?? '',
          onTap: () => context.pushNamed(
              isLead ? LeadsPageWidget.routeName : CalendarPageWidget.routeName),
        ),
      ));
    }
    // Untimed items (a move with no start yet) first, then by time.
    today.sort((a, b) {
      if (a.$1 == null) return b.$1 == null ? 0 : -1;
      if (b.$1 == null) return 1;
      return a.$1!.compareTo(b.$1!);
    });

    // Moves booked for the coming days, so the dashboard still shows
    // what is next once today's list is short.
    final later = _model.upcomingOrders
        .where((o) => !_isToday(o.moveDateOrNull))
        .take(3)
        .map((o) => DashAgendaItem(
              time: o.moveDateOrNull == null
                  ? '—'
                  : '${o.moveDateOrNull!.day}',
              ampm: o.moveDateOrNull == null
                  ? ''
                  : DateFormat('MMM').format(o.moveDateOrNull!),
              icon: Icons.local_shipping_outlined,
              tone: orderStageTone(
                  orderStageIndex(o.trackingStatus, o.status)),
              title: l.ngAgendaMove(o.customer),
              sub: '${o.fromCity ?? ''} → ${o.toCity ?? ''}',
              onTap: () => openOrderDetail(context, o),
            ))
        .toList();

    return DashAgenda(
      today: [for (final t in today) t.$2],
      later: later,
      emptyAction: NgSecondaryButton(
        label: l.ngCreateFirstOrder,
        icon: Icons.add_rounded,
        onPressed: () => context.pushNamed(NewOrderPageWidget.routeName),
      ),
    );
  }

  String _periodTitle(AppLocalizations l) {
    final now = DateTime.now();
    final m = _model.visibleMonth;
    switch (_model.periodType) {
      case '3m':
        return l.ngPeriod3m;
      case 'fy':
        return l.ngPeriodFy;
      case 'all':
        return l.ngPeriodAll;
      default:
        if (m.year == now.year && m.month == now.month) {
          return l.ngPeriodThisMonth;
        }
        final prev = DateTime(now.year, now.month - 1);
        if (m.year == prev.year && m.month == prev.month) {
          return l.ngPeriodLastMonth;
        }
        return DateFormat('MMMM yyyy').format(m);
    }
  }

  /// The handoff's "Oct 2026 ▾": the same five periods the old chip row
  /// offered, plus month stepping, in a sheet.
  Future<void> _pickPeriod() async {
    final l = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: NgPalette.of(context).sheet,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(NgRadius.sheet))),
      builder: (ctx) {
        final c = NgPalette.of(ctx);
        Widget opt(String label, bool on, VoidCallback f) => ListTile(
              title: Text(label,
                  style: NgFonts.geist(
                      fontSize: 14.5,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                      color: c.text)),
              trailing: on
                  ? Icon(Icons.check_rounded, color: c.acc, size: 20)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                f();
              },
            );
        final now = DateTime.now();
        final m = _model.visibleMonth;
        final month = _model.periodType == 'month';
        final isThis = month && m.year == now.year && m.month == now.month;
        final prev = DateTime(now.year, now.month - 1);
        final isLast = month && m.year == prev.year && m.month == prev.month;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(l.ngPickPeriod,
                      style: NgFonts.geist(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: c.text)),
                ),
                opt(l.ngPeriodThisMonth, isThis, () => _setPeriodType('month')),
                opt(l.ngPeriodLastMonth, isLast, _setLastMonth),
                opt(l.ngPeriod3m, _model.periodType == '3m',
                    () => _setPeriodType('3m')),
                opt(l.ngPeriodFy, _model.periodType == 'fy',
                    () => _setPeriodType('fy')),
                opt(l.ngPeriodAll, _model.periodType == 'all',
                    () => _setPeriodType('all')),
                if (month)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Previous month',
                        icon: Icon(Icons.chevron_left_rounded, color: c.soft),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _shiftMonth(-1);
                        },
                      ),
                      Text(DateFormat('MMM yyyy').format(m),
                          style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
                      IconButton(
                        tooltip: 'Next month',
                        icon: Icon(Icons.chevron_right_rounded, color: c.soft),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _shiftMonth(1);
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _periodShort() {
    final m = _model.visibleMonth;
    switch (_model.periodType) {
      case '3m':
        return '3M';
      case 'fy':
        return _periodLabel();
      case 'all':
        return AppLocalizations.of(context).ngPeriodAll;
      default:
        return DateFormat('MMM yyyy').format(m);
    }
  }

  Future<void> _editTarget() async {
    final l = AppLocalizations.of(context);
    final ctrl = TextEditingController(
        text: _model.monthlyTarget == null
            ? ''
            : _model.monthlyTarget!.toStringAsFixed(0));
    final entered = await showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.ngEditTarget),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(prefixText: '₹ '),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                  MaterialLocalizations.of(ctx).cancelButtonLabel)),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, functions.parseDouble(ctrl.text)),
              child: Text(l.save)),
        ],
      ),
    );
    if (entered == null) return;
    try {
      await SettingsTable().upsert(
        {
          ...OrgScope.stamp(),
          'key': 'monthly_target',
          'value': entered.toStringAsFixed(0),
        },
        onConflict: 'org_id,key',
      );
      _model.monthlyTarget = entered;
      safeSetState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save target: $e')));
      }
    }
  }

  Widget _monthSection(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = NgPalette.of(context);
    final kpi = _model.kpiList.isNotEmpty ? _model.kpiList.first : null;
    final canMargin = StaffPermissions.canActive('financials_margin', 'view');
    final margin = kpi == null
        ? null
        : DashboardKpiGrid.marginState(kpi, _model.unpricedCommissionCount);

    // Target block. Measured in PROFIT, not revenue (Arun, 2 Sep 2026:
    // "in target we need profit not revenue"). Only shown when profit is
    // honest; a target bar over a profit that ignores missing expenses
    // would read as progress that has not happened.
    Widget? target;
    if (canMargin) {
      final t = _model.monthlyTarget ?? 0;
      if (t <= 0) {
        target = DashTargetBlock(
          label: l.ngProfitTarget,
          value: l.ngSetTarget,
          target: '—',
          fraction: 0,
          percentLabel: '',
          note: l.ngSetTargetSub,
          onTap: _editTarget,
        );
      } else if (margin?.showable ?? false) {
        final done = _model.periodNetProfit;
        final pct = (done / t * 100).round();
        target = DashTargetBlock(
          label: l.ngProfitTarget,
          value: functions.inrFormat(done)!,
          target: functions.inrFormat(t)!,
          fraction: (done <= 0 ? 0.0 : done / t).clamp(0.0, 1.0),
          percentLabel: '$pct%',
          barColor: done <= 0 ? c.red : (done >= t ? c.green : null),
          note: done <= 0
              ? l.ngNoProfitYet
              : (done >= t ? l.ngTargetDone : null),
          onTap: _editTarget,
        );
      } else {
        target = DashTargetBlock(
          label: l.ngProfitTarget,
          value: '—',
          target: functions.inrFormat(t)!,
          fraction: 0,
          percentLabel: '',
          note: margin?.title,
          onTap: _editTarget,
        );
      }
    }

    Widget? profit;
    if (canMargin && kpi != null && margin != null) {
      profit = margin.showable
          ? DashProfitRow(
              title: l.ngProfit,
              sub: l.ngProfitAfter(
                  functions.inrFormat(kpi.labourThisMonth)!,
                  functions.inrFormat(kpi.expensesThisMonth)!),
              value: functions.inrFormat(kpi.netProfitThisMonth),
              onTap: () => _openKpiTile('profit'),
            )
          : DashProfitRow(
              title: l.ngProfit,
              sub: margin.title,
              action: l.ngAddExpense,
              onTap: () =>
                  context.pushNamed(QuickExpensePageWidget.routeName),
            );
    }

    final grid = DashboardKpiGrid(
      kpi: kpi,
      unpricedCommissionCount: _model.unpricedCommissionCount,
      onAddExpense: () => context.pushNamed(QuickExpensePageWidget.routeName),
      onTapTile: _openKpiTile,
    );
    return DashMonthPanel(
      title: _periodTitle(l),
      periodLabel: _periodShort(),
      onPickPeriod: _pickPeriod,
      target: target,
      grid: grid,
      profit: profit,
    );
  }

  Widget _hotLeadsSection(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final leads = _model.hotLeads.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NgSectionHeader(
          l.ngHotLeads,
          trailing: l.ngSeeAll,
          onTrailing: () => context.pushNamed(LeadsPageWidget.routeName),
        ),
        const SizedBox(height: 10),
        if (leads.isEmpty)
          NgCard(
            child: _dashboardEmptyState(
              context,
              icon: Icons.person_add_alt_1_outlined,
              message: l.ngNoLeadsYet,
              actionLabel: l.ngAddLead,
              onAction: () => context.pushNamed(NewLeadPageWidget.routeName),
            ),
          )
        else
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.zero,
              itemCount: leads.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final ld = leads[i];
                final tone = leadStatusTone(ld.status);
                return SizedBox(
                  width: 200,
                  child: NgCard(
                    onTap: () => openLeadDetail(context, ld),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            NgAvatar(ld.customer, status: tone),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ld.customer,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: NgFonts.geist(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: c.text),
                                  ),
                                  Text(
                                    leadStatusLabel(ld.status),
                                    style: NgFonts.geist(
                                        fontSize: 12,
                                        color: c.status(tone).fg),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${ld.fromCity ?? ''} → ${ld.toCity ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NgFonts.geist(fontSize: 12.5, color: c.mute),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// Per-branch figures. Not in the handoff's dashboard; kept because it
  /// works today, and hidden until a branch exists (17 Aug 2026: a
  /// "Branch Performance" title over nothing reads worse than nothing).
  Widget _branchSection(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NgSectionHeader(l.ngBranches),
        const SizedBox(height: 10),
        NgCardList(children: [
          for (final b in _model.branchStats)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  const NgIconTile(icon: Icons.store_mall_directory_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.branch ?? '',
                            style: NgFonts.geist(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                                color: c.text)),
                        Text(l.ngOrdersN((b.orderCount ?? 0).toInt()),
                            style:
                                NgFonts.geist(fontSize: 12.5, color: c.mute)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(functions.inrFormat(b.revenue)!,
                          style: NgFonts.geist(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: c.text)),
                      // Branch margin is suppressed, not zeroed:
                      // branch_kpis_view has no expense column, so its
                      // net_profit is revenue minus commission only until
                      // NG-046 fixes the view. The hardcoded 0 becomes the
                      // real column then, and the margin starts rendering.
                      Text(
                        marginIsMeaningful(
                          expensesTotal: 0,
                          orderCount: (b.orderCount ?? 0).toInt(),
                        )
                            ? functions.marginPct(b.netProfit, b.revenue)!
                            : kMarginUnavailableTitle,
                        style: NgFonts.geist(fontSize: 12, color: c.mute),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final s = AppSession.instance;
    final showInfo = StaffPermissions.canActive('financials', 'view') ||
        _overdueFollowUps > 0;
    final sections = <Widget>[
      _greeting(context),
      if (s.currentStaffId == null && (s.planName ?? '').trim().isNotEmpty)
        const DashPlanCard(),
      if (showInfo) _infoRows(context),
      _todayRow(context),
      _agendaSection(context),
      if (StaffPermissions.canActive('reports', 'view') ||
          StaffPermissions.canActive('financials', 'view'))
        _monthSection(context),
      _hotLeadsSection(context),
      if (_model.branchStats.isNotEmpty) _branchSection(context),
    ];
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: c.bg,
        // Quick Entry and the module menu live in the shell (main.dart's
        // NavBarPage + components/more_sheet.dart), so they are on every
        // tab, not just this one.
        appBar: NgTopBar(onRefresh: _loadDashboard),
        body: SafeArea(
          top: true,
          child: RefreshIndicator(
            onRefresh: _loadDashboard,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
              children: [
                for (var i = 0; i < sections.length; i++) ...[
                  if (i > 0) const SizedBox(height: 22),
                  sections[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
