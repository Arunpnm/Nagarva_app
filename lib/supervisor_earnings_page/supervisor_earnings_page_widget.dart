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

/// My Earnings (`sup-sal`) — for EVERY staff session since 4 Nov 2026
/// (supervisor, driver, helper, packer; BUG-055 — field staff had a
/// "coming soon" page and could not see their own pay).
///
/// Same money rule as the owner's Salary ledger (staff_ledger_sheet.dart),
/// so the two can never disagree:
///   earned this month  = job wages on orders moving this month
///                        + overtime & incentives dated this month
///   paid this month    = salary_payments this month (incl. advance
///                        recovered from salary)
///   balance to be paid = earned − paid
///   advance            = pending staff_advances (all time)
/// Before this the balance was ALL-TIME wages minus advances, ignoring
/// every salary already paid.
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

  /// This month's overtime & incentives: (date, kind, amount).
  List<({String date, String kind, double amount})> _incentives = const [];

  /// Salary paid this month (incl. advance recovered from salary).
  double _paidThisMonth = 0;

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
          // A LEFT join (4 Nov 2026): with `!inner` a wage vanished whenever
          // this person could not read the order itself — e.g. an order with
          // no branch is hidden from every staff session by branch_isolation,
          // so a helper's ₹600 for a job he worked simply disappeared. The
          // wage row is his; the order's date is only for grouping.
          .select('salary_amount,order_id,created_at,orders(move_date)')
          .eq('org_id', orgId)
          .eq('staff_id', staffId);

      final byMonth = <String, double>{};
      final jobs = <({DateTime? date, String orderId, double amount})>[];
      for (final r in rows) {
        final moveDate = (r['orders'] is Map ? r['orders']['move_date'] : null)
            as String?;
        // Order not readable: the day he was put on the crew stands in.
        final date = DateTime.tryParse(moveDate ?? '') ??
            DateTime.tryParse('${r['created_at'] ?? ''}')?.toLocal();
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

      final now = DateTime.now();
      final from = DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month));
      final to =
          DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month + 1));
      var incentives = <({String date, String kind, double amount})>[];
      var paid = 0.0;
      try {
        final inc = await SupaFlow.client
            .from('staff_incentives')
            .select('entry_date,kind,amount')
            .eq('org_id', orgId)
            .eq('staff_id', staffId)
            .gte('entry_date', from)
            .lt('entry_date', to);
        incentives = [
          for (final r in inc)
            (
              date: (r['entry_date'] ?? '').toString(),
              kind: (r['kind'] ?? '').toString(),
              amount: (r['amount'] as num?)?.toDouble() ?? 0,
            ),
        ];
        final pay = await SupaFlow.client
            .from('salary_payments')
            .select('amount')
            .eq('org_id', orgId)
            .eq('staff_id', staffId)
            .gte('paid_date', from)
            .lt('paid_date', to);
        paid = pay.fold<double>(
            0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0));
      } catch (_) {}

      if (mounted) {
        setState(() {
          _incentives = incentives;
          _paidThisMonth = paid;
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
    final monthWages = monthJobs.fold<double>(0, (s, j) => s + j.amount);
    final monthIncentives =
        _incentives.fold<double>(0, (s, i) => s + i.amount);
    final monthGross = monthWages + monthIncentives;
    final balance = monthGross - _paidThisMonth;
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
                        ' · still to be paid ${functions.inrFull(balance < 0 ? 0 : balance)}',
                        style: NgFonts.geist(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: c.green)),
                    const SizedBox(height: 14),
                    line(
                        'Job wages',
                        '${monthJobs.length} × job',
                        functions.inrFull(monthWages),
                        c.text,
                        true),
                    for (final i in _incentives)
                      line(
                          i.kind.toLowerCase().contains('over')
                              ? 'Overtime'
                              : 'Incentive',
                          i.date,
                          functions.inrFull(i.amount),
                          c.text,
                          false),
                    if (_paidThisMonth > 0)
                      line('Paid this month', '',
                          '−${functions.inrFull(_paidThisMonth)}', c.mute,
                          false),
                    for (final a in _advances)
                      line(
                          'Advance to be recovered',
                          [a.date, a.note]
                              .where((x) => x.trim().isNotEmpty)
                              .join(' · '),
                          functions.inrFull(a.amount),
                          c.red,
                          false),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  tile('Earned', functions.inrFull(monthGross), c.text),
                  const SizedBox(width: 8),
                  tile('Paid', functions.inrFull(_paidThisMonth), c.mute),
                  const SizedBox(width: 8),
                  tile('Advance due', functions.inrFull(_advanceBalance),
                      c.red),
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
