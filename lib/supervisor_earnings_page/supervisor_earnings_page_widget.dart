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
      for (final r in rows) {
        final moveDate = r['orders']?['move_date'] as String?;
        final key = moveDate == null
            ? 'Unscheduled'
            : DateFormat('MMM y').format(DateTime.parse(moveDate));
        final amount = (r['salary_amount'] as num?)?.toDouble() ?? 0;
        byMonth[key] = (byMonth[key] ?? 0) + amount;
      }

      final advanceRows = await SupaFlow.client
          .from('staff_advances')
          .select('amount')
          .eq('org_id', orgId)
          .eq('staff_id', staffId)
          .eq('status', 'pending');
      final balance = advanceRows.fold<double>(
          0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0));

      if (mounted) {
        setState(() {
          _byMonth
            ..clear()
            ..addAll(byMonth);
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
    final total = _byMonth.values.fold(0.0, (s, v) => s + v);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: const NgTopBar(extraActions: [SupervisorMenuButton()]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const NgScreenTitle('My earnings',
                large: true, subtitle: 'From the jobs you were on'),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: NgStatTile(
                      icon: Icons.account_balance_wallet_outlined,
                      value: functions.inrFull(total),
                      label: 'Total earned',
                      color: c.green,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NgStatTile(
                      icon: Icons.payments_outlined,
                      value: functions.inrFull(_advanceBalance),
                      label: 'Advance balance',
                      color: _advanceBalance > 0 ? c.red : c.mute,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const NgSectionHeader('By month'),
              const SizedBox(height: 10),
              if (_byMonth.isEmpty)
                const NgEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No earnings yet',
                  subtitle: 'Wages show here once you are put on a job.',
                )
              else
                NgCardList(children: [
                  for (final e in _byMonth.entries)
                    NgListRow(
                      icon: Icons.calendar_month_outlined,
                      title: e.key,
                      trailing: Text(functions.inrFull(e.value),
                          style: NgFonts.mono(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: c.text)),
                    ),
                ]),
            ],
          ],
        ),
      ),
    );
  }
}
