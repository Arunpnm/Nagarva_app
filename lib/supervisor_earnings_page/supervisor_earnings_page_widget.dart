import '/components/ng_widgets.dart';
import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/supervisor_menu_button.dart';
import '/components/ng_top_bar.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/flutter_flow/ng_tokens.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Session 2 Part C — My Earnings (`sup-sal`). This supervisor's own
/// `order_staff` rows (their per-job salary_amount, same table Order
/// Details' P&L card and Team & Salary section read), grouped by month,
/// plus their `staff_advances` balance.
class SupervisorEarningsPageWidget extends StatefulWidget {
  const SupervisorEarningsPageWidget({super.key});

  static String routeName = 'SupervisorEarningsPage';
  static String routePath = '/sup-sal';

  @override
  State<SupervisorEarningsPageWidget> createState() =>
      _SupervisorEarningsPageWidgetState();
}

class _SupervisorEarningsPageWidgetState
    extends State<SupervisorEarningsPageWidget> {
  bool _loading = true;
  final Map<String, double> _byMonth = {};
  double _advanceBalance = 0;

  /// One line per job worked: (move date, order id, wage). Newest first.
  List<({DateTime? date, String orderId, double amount})> _jobs = const [];

  /// Pending advances: (date, amount, note).
  List<({String date, double amount, String note})> _advances = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final staffId = AppSession.instance.currentStaffId;
    if (staffId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final orgId = OrgScope.currentOrgId!;
      final rows = await SupaFlow.client
          .from('order_staff')
          .select('salary_amount,order_id,orders!inner(move_date)')
          .eq('org_id', orgId)
          .eq('staff_id', staffId);

      final byMonth = <String, double>{};
      final jobs = <({DateTime? date, String orderId, double amount})>[];
      for (final r in rows) {
        final moveDate = r['orders']?['move_date'] as String?;
        final date = moveDate == null ? null : DateTime.tryParse(moveDate);
        final key =
            date == null ? 'Unscheduled' : DateFormat('MMM y').format(date);
        final amount = (r['salary_amount'] as num?)?.toDouble() ?? 0;
        byMonth[key] = (byMonth[key] ?? 0) + amount;
        jobs.add((
          date: date,
          orderId: (r['order_id'] ?? '').toString(),
          amount: amount
        ));
      }
      jobs.sort((x, y) =>
          (y.date ?? DateTime(0)).compareTo(x.date ?? DateTime(0)));

      final advanceRows = await SupaFlow.client
          .from('staff_advances')
          .select('amount,advance_date,note')
          .eq('org_id', orgId)
          .eq('staff_id', staffId)
          .eq('status', 'pending');
      final advances = [
        for (final r in advanceRows)
          (
            date: (r['advance_date'] ?? '').toString(),
            amount: (r['amount'] as num?)?.toDouble() ?? 0,
            note: (r['note'] ?? '').toString(),
          ),
      ];
      final balance = advances.fold<double>(0, (s, a) => s + a.amount);

      if (mounted) {
        setState(() {
          _byMonth
            ..clear()
            ..addAll(byMonth);
          _jobs = jobs;
          _advances = advances;
          _advanceBalance = balance;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final now = DateTime.now();
    final monthJobs = _jobs
        .where((j) =>
            j.date != null &&
            j.date!.year == now.year &&
            j.date!.month == now.month)
        .toList();
    final monthGross = monthJobs.fold<double>(0, (s, j) => s + j.amount);
    final total = _byMonth.values.fold(0.0, (s, v) => s + v);
    final balance = total - _advanceBalance;
    Widget line(String label, String sub, String amt, Color color, bool first) =>
        Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
              border: first
                  ? null
                  : Border(top: BorderSide(color: c.w06))),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: NgFonts.geist(fontSize: 14, color: c.text)),
                    if (sub.isNotEmpty)
                      Text(sub,
                          style: NgFonts.mono(fontSize: 12, color: c.faint)),
                  ],
                ),
              ),
              Text(amt,
                  style: NgFonts.geist(
                      fontSize: 14.5, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        );
    Widget tile(String label, String value, Color color) => Expanded(
          child: NgCard(
            radius: 16,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(fontSize: 12, color: c.mute)),
                const SizedBox(height: 4),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(
                        fontSize: 16, fontWeight: FontWeight.w600, color: color)),
              ],
            ),
          ),
        );
    return Scaffold(
      backgroundColor: c.bg,
      appBar: const NgTopBar(extraActions: [SupervisorMenuButton()]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text('Earnings',
                        style: NgFonts.geist(
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.52,
                            color: c.text)),
                  ),
                  Text(DateFormat('MMMM y').format(now),
                      style: NgFonts.geist(fontSize: 13, color: c.mute)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              NgCard(
                radius: 20,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Earned this month',
                        style: NgFonts.geist(fontSize: 13, color: c.mute)),
                    const SizedBox(height: 4),
                    Text(functions.inrFull(monthGross),
                        style: NgFonts.geist(
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.64,
                            color: c.text)),
                    const SizedBox(height: 2),
                    Text(
                        '${monthJobs.length} job${monthJobs.length == 1 ? '' : 's'}'
                        ' · balance ${functions.inrFull(balance < 0 ? 0 : balance)}',
                        style: NgFonts.geist(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: c.green)),
                    const SizedBox(height: 14),
                    line(
                        'Job wages',
                        '${monthJobs.length} × job',
                        functions.inrFull(monthGross),
                        c.text,
                        true),
                    for (final a in _advances)
                      line(
                          'Advance taken',
                          [a.date, a.note]
                              .where((x) => x.trim().isNotEmpty)
                              .join(' · '),
                          '−${functions.inrFull(a.amount)}',
                          c.red,
                          false),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  tile('Earned', functions.inrFull(total), c.text),
                  const SizedBox(width: 8),
                  tile('Advances', '−${functions.inrFull(_advanceBalance)}',
                      c.red),
                  const SizedBox(width: 8),
                  tile('Balance', functions.inrFull(balance < 0 ? 0 : balance),
                      c.green),
                ],
              ),
              const SizedBox(height: 18),
              const NgSectionHeader('Recent'),
              const SizedBox(height: 10),
              if (_jobs.isEmpty)
                const NgEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No earnings yet',
                  subtitle: 'Wages show here once you are put on a job.',
                )
              else
                NgCard(
                  radius: 20,
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (var i = 0; i < _jobs.length && i < 20; i++)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 13),
                        decoration: BoxDecoration(
                            border: i == 0
                                ? null
                                : Border(top: BorderSide(color: c.w06))),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 56,
                              child: Text(
                                  _jobs[i].date == null
                                      ? '—'
                                      : DateFormat('d MMM')
                                          .format(_jobs[i].date!),
                                  style: NgFonts.mono(
                                      fontSize: 12.5, color: c.mute)),
                            ),
                            Expanded(
                              child: Text(_jobs[i].orderId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: NgFonts.geist(
                                      fontSize: 13.5, color: c.text)),
                            ),
                            Text(functions.inrFull(_jobs[i].amount),
                                style: NgFonts.geist(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: c.text)),
                          ],
                        ),
                      ),
                  ]),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
