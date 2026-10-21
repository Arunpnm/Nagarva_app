import '/backend/soft_delete.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/delete_action.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

  static IconData _catIcon(String? cat) {
    final k = (cat ?? '').toLowerCase();
    if (k.contains('fuel') || k.contains('diesel')) {
      return Icons.local_gas_station_outlined;
    }
    if (k.contains('toll')) return Icons.toll_outlined;
    if (k.contains('material') || k.contains('carton')) {
      return Icons.inventory_2_outlined;
    }
    if (k.contains('repair') || k.contains('maint') || k.contains('service')) {
      return Icons.build_outlined;
    }
    if (k.contains('food') || k.contains('bata')) {
      return Icons.restaurant_outlined;
    }
    if (k.contains('labour') || k.contains('wage')) return Icons.groups_outlined;
    if (k.contains('rent')) return Icons.home_work_outlined;
    return Icons.receipt_long_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final rows = _filteredExpenses
      ..sort((a, b) => (b.expenseDate ?? b.createdAt ?? DateTime(0))
          .compareTo(a.expenseDate ?? a.createdAt ?? DateTime(0)));
    final total = _filteredTotal;
    final last = _lastMonthTotal;
    String sub = l.ngExpCount(rows.length);
    Color subColor = c.mute;
    if (last != null && last > 0) {
      final pct = ((total - last) / last) * 100;
      sub = '$sub · ${pct >= 0 ? '↑' : '↓'} ${l.ngExpVsLast(pct.abs().round())}';
      subColor = pct >= 0 ? c.red : c.green;
    }
    final cats = _byCategory;
    final periods = [
      ('week', l.ngExpThisWeek),
      ('month', l.ngPeriodThisMonth),
      ('all', l.ngTabAll),
    ];
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: c.bg,
      appBar: NgTopBar(onRefresh: _loadExpenses),
      body: RefreshIndicator(
        onRefresh: _loadExpenses,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            NgModuleHeader(
              l.homePageExpenses,
              actions: [
                NgPrimaryButton(
                  compact: true,
                  height: 40,
                  icon: Icons.add_rounded,
                  label: l.ngAddExpense,
                  onPressed: () =>
                      context.pushNamed(QuickExpensePageWidget.routeName),
                ),
              ],
            ),
            const SizedBox(height: 14),
            NgCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      periods
                          .firstWhere((p) => p.$1 == _model.periodFilter,
                              orElse: () => periods[1])
                          .$2,
                      style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
                  const SizedBox(height: 6),
                  Text(_money(total),
                      style: NgFonts.mono(
                          fontSize: 30,
                          fontWeight: FontWeight.w600,
                          color: c.text)),
                  const SizedBox(height: 6),
                  Text(rows.isEmpty ? l.ngExpNone : sub,
                      style: NgFonts.geist(fontSize: 12.5, color: subColor)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            NgChipRow(
              edge: 0,
              chips: [
                for (final p in periods)
                  NgChip(
                    label: p.$2,
                    selected: _model.periodFilter == p.$1,
                    onTap: () =>
                        safeSetState(() => _model.periodFilter = p.$1),
                  ),
                NgChip(
                  label: l.ngExpOrderOnly,
                  selected: _model.orderWiseOnly,
                  onTap: () => safeSetState(
                      () => _model.orderWiseOnly = !_model.orderWiseOnly),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (rows.isEmpty)
              NgCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(l.ngExpNone,
                      textAlign: TextAlign.center,
                      style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
                ),
              )
            else
              NgCardList(children: [
                for (final e in rows)
                  NgListRow(
                    icon: _catIcon(e.category),
                    title: (e.category ?? '').trim().isEmpty
                        ? l.ngExpUncategorised
                        : e.category!.trim(),
                    subtitle: [
                      if ((e.expenseDate ?? e.createdAt) != null)
                        DateFormat('d MMM yyyy')
                            .format((e.expenseDate ?? e.createdAt)!),
                      if ((e.orderId ?? '').isNotEmpty) e.orderId!,
                      if ((e.description ?? '').trim().isNotEmpty)
                        e.description!.trim(),
                    ].join(' · '),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_money(e.amount ?? 0),
                            style: NgFonts.mono(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: c.text)),
                        IconButton(
                          tooltip: l.ngExpDelete,
                          icon: Icon(Icons.delete_outline_rounded,
                              size: 19, color: c.faint),
                          onPressed: () => _deleteExpense(e),
                        ),
                      ],
                    ),
                  ),
              ]),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(l.ngExpByCategory,
                  style: NgFonts.geist(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.text)),
            ),
            const SizedBox(height: 10),
            if (cats.isEmpty)
              NgCard(
                child: Column(
                  children: [
                    Icon(Icons.pie_chart_outline_rounded,
                        size: 30, color: c.faint),
                    const SizedBox(height: 6),
                    Text(l.ngExpNoCat,
                        style: NgFonts.geist(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: c.text)),
                    const SizedBox(height: 2),
                    Text(l.ngExpNoCatSub,
                        textAlign: TextAlign.center,
                        style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
                  ],
                ),
              )
            else
              NgCardList(children: [
                for (final g in cats)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(_catIcon(g.name), size: 18, color: c.faint),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(g.name,
                                  style: NgFonts.geist(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: c.text)),
                            ),
                            Text(
                                total <= 0
                                    ? ''
                                    : '${(g.amount / total * 100).round()}%',
                                style: NgFonts.geist(
                                    fontSize: 12.5, color: c.mute)),
                            const SizedBox(width: 10),
                            Text(_money(g.amount),
                                style: NgFonts.mono(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: c.text)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        NgProgressBar(
                            value: total <= 0 ? 0 : g.amount / total,
                            color: c.accBtn),
                      ],
                    ),
                  ),
              ]),
          ],
        ),
      ),
    );
  }
}
