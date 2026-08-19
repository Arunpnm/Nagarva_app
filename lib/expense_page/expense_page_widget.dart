import '/backend/soft_delete.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/delete_action.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/components/keyboard_scroll_view.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'expense_page_model.dart';
export 'expense_page_model.dart';

/// Expense tracking by category.
class ExpensePageWidget extends StatefulWidget {
  const ExpensePageWidget({super.key});

  static String routeName = 'ExpensePage';
  static String routePath = '/expenses';

  @override
  State<ExpensePageWidget> createState() => _ExpensePageWidgetState();
}

class _ExpensePageWidgetState extends State<ExpensePageWidget>
    with RefreshOnPopMixin<ExpensePageWidget> {
  late ExpensePageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => ExpensePageModel());

    // On page load action.
    SchedulerBinding.instance.addPostFrameCallback((_) => _loadExpenses());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  // Refresh-after-write fix (parity brief Part 1): re-run when a pushed
  // route (Quick Expense) is popped back to this list.
  @override
  void onPageRefresh() => _loadExpenses();

  // Item 11 sweep (16 Aug 2026): expenses had soft-delete columns and a
  // working recycle-bin entry but no delete UI anywhere to reach it from.
  Future<void> _deleteExpense(ExpensesRow e) async {
    final deleted = await DeleteAction.run(
      context,
      table: 'expenses',
      id: e.id!,
      entityLabel: 'expense',
      check: () async => DeleteCheck.allow,
      onDeleted: _loadExpenses,
    );
    if (deleted) await _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    // Phase 1 multi-tenancy pass — see supabase/phase1_add_org_id.sql.
    _model.expensesOut = await ExpensesTable().queryRows(
      queryFn: (q) => OrgScope.read(q),
    );
    _model.expensesList =
        (_model.expensesOut ?? []).toList().cast<ExpensesRow>();
    safeSetState(() {});
  }

  // ------------------------------------------------------------------
  // Real figures (18 Aug 2026).
  //
  // The summary card and the "By Category" bars below used to be
  // hardcoded FlutterFlow mockup content — "May 2025 Total ₹68,450",
  // "↑ 12% vs last month", and four invented category rows (Fuel 41%
  // ₹28,000, Tolls & Permits 18% ₹12,500, Maintenance 26% ₹18,000,
  // Labour 15% ₹9,950). None of it came from the database; a brand-new
  // vendor with zero expenses saw a business's worth of invented
  // spending on their first visit.
  //
  // These getters deliberately reuse the SAME filter the live list
  // below applies, so the headline total can never disagree with the
  // rows a vendor can actually see and count.
  // ------------------------------------------------------------------

  bool _matchesFilter(ExpensesRow e, DateTime now) {
    if (_model.orderWiseOnly && e.orderId == null) return false;
    final d = e.expenseDate ?? e.createdAt;
    if (_model.periodFilter == 'all' || d == null) return true;
    if (_model.periodFilter == 'week') return now.difference(d).inDays <= 7;
    return d.year == now.year && d.month == now.month;
  }

  List<ExpensesRow> get _filteredExpenses {
    final now = DateTime.now();
    return _model.expensesList.where((e) => _matchesFilter(e, now)).toList();
  }

  double get _filteredTotal =>
      _filteredExpenses.fold<double>(0, (s, e) => s + (e.amount ?? 0));

  String get _periodLabel => switch (_model.periodFilter) {
        'week' => 'This Week',
        'all' => 'All Time',
        _ => 'This Month',
      };

  /// Category -> total, highest first. Uncategorised rows are grouped
  /// under "Uncategorised" rather than dropped, so the bars always sum
  /// to the headline figure.
  List<({String name, double amount})> get _byCategory {
    final map = <String, double>{};
    for (final e in _filteredExpenses) {
      final key = (e.category ?? '').trim().isEmpty
          ? 'Uncategorised'
          : e.category!.trim();
      map[key] = (map[key] ?? 0) + (e.amount ?? 0);
    }
    final out = map.entries
        .map((e) => (name: e.key, amount: e.value))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return out;
  }

  /// Previous calendar month's total, for the comparison line. Null when
  /// there's nothing to compare against — in which case the line is
  /// hidden rather than showing a fabricated percentage.
  double? get _lastMonthTotal {
    if (_model.periodFilter != 'month') return null;
    final now = DateTime.now();
    final prev = DateTime(now.year, now.month - 1);
    var total = 0.0;
    var any = false;
    for (final e in _model.expensesList) {
      if (_model.orderWiseOnly && e.orderId == null) continue;
      final d = e.expenseDate ?? e.createdAt;
      if (d == null) continue;
      if (d.year == prev.year && d.month == prev.month) {
        total += e.amount ?? 0;
        any = true;
      }
    }
    return any ? total : null;
  }

  String _money(double v) =>
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
          .format(v);

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  Widget _filterChip(
      BuildContext context, String label, bool selected, VoidCallback onTap) {
    final theme = FlutterFlowTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? theme.primary : theme.secondaryBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: selected ? theme.primary : theme.secondaryText),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : theme.primaryText,
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
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          automaticallyImplyLeading: true,
          title: Text(
            FFLocalizations.of(context).getText(
              'nwwqh0ab' /* Expenses */,
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
                    // Real summary (18 Aug 2026) — replaces the
                    // hardcoded "May 2025 Total / Rs 68,450 / up 12% vs
                    // last month" mockup. Uses the same filter as the
                    // list below, so the two can never disagree.
                    Builder(builder: (context) {
                      final theme = FlutterFlowTheme.of(context);
                      final total = _filteredTotal;
                      final count = _filteredExpenses.length;
                      final last = _lastMonthTotal;
                      String? delta;
                      bool up = true;
                      if (last != null && last > 0) {
                        final pct = ((total - last) / last) * 100;
                        up = pct >= 0;
                        delta =
                            '${up ? '↑' : '↓'} ${pct.abs().toStringAsFixed(0)}% vs last month';
                      }
                      return Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: theme.secondaryBackground,
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$_periodLabel Total',
                                  style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      color: theme.secondaryText)),
                              const SizedBox(height: 6),
                              Text(_money(total),
                                  style: GoogleFonts.interTight(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                      color: theme.primaryText)),
                              const SizedBox(height: 6),
                              Text(
                                count == 0
                                    ? 'No expenses in this period'
                                    : '$count expense${count == 1 ? '' : 's'}'
                                        '${delta == null ? '' : '  ·  $delta'}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: delta == null
                                      ? theme.secondaryText
                                      : (up ? theme.error : theme.success),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          FFLocalizations.of(context).getText(
                            'nuqjojzx' /* Live Expenses */,
                          ),
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
                        // Parity brief Part 4a: month/week/order-wise
                        // filters — this page previously had none at all.
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final p in const [
                                ('week', 'This Week'),
                                ('month', 'This Month'),
                                ('all', 'All')
                              ])
                                _filterChip(context, p.$2,
                                    _model.periodFilter == p.$1, () {
                                  safeSetState(
                                      () => _model.periodFilter = p.$1);
                                }),
                              _filterChip(
                                  context, 'Order-linked only',
                                  _model.orderWiseOnly, () {
                                safeSetState(() =>
                                    _model.orderWiseOnly =
                                        !_model.orderWiseOnly);
                              }),
                            ],
                          ),
                        ),
                        Builder(
                          builder: (context) {
                            final now = DateTime.now();
                            final expensesListItem = _model.expensesList
                                .where((e) {
                                  if (_model.orderWiseOnly &&
                                      e.orderId == null) {
                                    return false;
                                  }
                                  final d = e.expenseDate ?? e.createdAt;
                                  if (_model.periodFilter == 'all' ||
                                      d == null) {
                                    return true;
                                  }
                                  if (_model.periodFilter == 'week') {
                                    return now.difference(d).inDays <= 7;
                                  }
                                  return d.year == now.year &&
                                      d.month == now.month;
                                })
                                .toList();

                            return ListView.separated(
                              padding: EdgeInsets.zero,
                              primary: false,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              scrollDirection: Axis.vertical,
                              itemCount: expensesListItem.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12.0),
                              itemBuilder: (context, expensesListItemIndex) {
                                final expensesListItemItem =
                                    expensesListItem[expensesListItemIndex];
                                return Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: FlutterFlowTheme.of(context)
                                        .secondaryBackground,
                                    borderRadius: BorderRadius.circular(10.0),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14.0),
                                    child: Row(
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
                                              expensesListItemItem.category ??
                                                  '-',
                                              style:
                                                  FlutterFlowTheme.of(context)
                                                      .bodyMedium
                                                      .override(
                                                        font: GoogleFonts.inter(
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodyMedium
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodyMedium
                                                                  .fontStyle,
                                                        ),
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .primaryText,
                                                        letterSpacing: 0.0,
                                                        fontWeight:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodyMedium
                                                                .fontWeight,
                                                        fontStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodyMedium
                                                                .fontStyle,
                                                      ),
                                            ),
                                            Text(
                                              dateTimeFormat(
                                                  'd MMM y',
                                                  expensesListItemItem
                                                      .expenseDate),
                                              style:
                                                  FlutterFlowTheme.of(context)
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
                                          ].divide(const SizedBox(height: 3.0)),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              (expensesListItemItem.amount ?? 0)
                                                  .toString(),
                                              style: FlutterFlowTheme.of(
                                                      context)
                                                  .titleSmall
                                                  .override(
                                                    font:
                                                        GoogleFonts.interTight(
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
                                                    color: FlutterFlowTheme.of(
                                                            context)
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
                                            IconButton(
                                              tooltip: 'Delete expense',
                                              visualDensity:
                                                  VisualDensity.compact,
                                              icon: Icon(Icons.delete_outline,
                                                  size: 18,
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .error),
                                              onPressed: () =>
                                                  _deleteExpense(
                                                      expensesListItemItem),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ].divide(const SizedBox(height: 12.0)),
                    ),
                    // Real category breakdown (18 Aug 2026) — replaces
                    // four hardcoded mockup bars (Fuel 41%, Tolls &
                    // Permits 18%, Maintenance 26%, Labour 15%). Computed
                    // from the same filtered set as the total above, so
                    // the percentages always add up to 100% of a figure
                    // the vendor can verify by counting the rows.
                    Builder(builder: (context) {
                      final theme = FlutterFlowTheme.of(context);
                      final cats = _byCategory;
                      final total = _filteredTotal;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('By Category',
                              style: GoogleFonts.interTight(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: theme.primaryText)),
                          const SizedBox(height: 12),
                          if (cats.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 26),
                              decoration: BoxDecoration(
                                color: theme.secondaryBackground,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.pie_chart_outline,
                                      size: 34, color: theme.secondaryText),
                                  const SizedBox(height: 10),
                                  Text('Nothing to break down yet',
                                      style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: theme.primaryText)),
                                  const SizedBox(height: 4),
                                  Text('Categories appear here once you record '
                                      'an expense.',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: theme.secondaryText)),
                                ],
                              ),
                            )
                          else
                            for (final c in cats)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: theme.secondaryBackground,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(c.name,
                                              style: GoogleFonts.inter(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: theme.primaryText)),
                                        ),
                                        Text(
                                          total <= 0
                                              ? '0%'
                                              : '${((c.amount / total) * 100).toStringAsFixed(0)}%',
                                          style: GoogleFonts.inter(
                                              fontSize: 12.5,
                                              color: theme.secondaryText),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(_money(c.amount),
                                            style: GoogleFonts.interTight(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: theme.primaryText)),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: total <= 0
                                            ? 0
                                            : (c.amount / total).clamp(0.0, 1.0),
                                        minHeight: 6,
                                        backgroundColor:
                                            theme.primaryBackground,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                            theme.primary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        ],
                      );
                    }),
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          0.0, 16.0, 0.0, 16.0),
                      child: FFButtonWidget(
                        // Found dead while wiring the real figures above
                        // (18 Aug 2026): this was still FlutterFlow's
                        // generated stub — it printed to the console and
                        // did nothing else, so "Add Expense" was a button
                        // that visibly worked and silently didn't. Routed
                        // to the real QuickExpensePage, which already
                        // exists and already stamps org_id. The list
                        // refreshes on pop via RefreshOnPopMixin.
                        onPressed: () =>
                            context.pushNamed(QuickExpensePageWidget.routeName),
                        text: FFLocalizations.of(context).getText(
                          'ul361nn3' /* Add Expense */,
                        ),
                        icon: const Icon(
                          Icons.add,
                          size: 20.0,
                        ),
                        options: FFButtonOptions(
                          width: double.infinity,
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          iconPadding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          iconColor:
                              FlutterFlowTheme.of(context).primaryBackground,
                          color: FlutterFlowTheme.of(context).primary,
                          textStyle: TextStyle(
                            color:
                                FlutterFlowTheme.of(context).primaryBackground,
                          ),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
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
