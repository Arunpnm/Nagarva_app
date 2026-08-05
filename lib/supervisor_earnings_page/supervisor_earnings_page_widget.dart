import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/supervisor_menu_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
    final theme = FlutterFlowTheme.of(context);
    final total = _byMonth.values.fold(0.0, (s, v) => s + v);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        elevation: 0,
        centerTitle: true,
        title: Text('My Earnings',
            style: theme.titleLarge.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600))),
        actions: const [SupervisorMenuButton()],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.secondaryBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total earned',
                                style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    color: theme.secondaryText)),
                            Text('₹${total.toStringAsFixed(0)}',
                                style: GoogleFonts.interTight(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: theme.primaryText)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Advance balance',
                                style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    color: theme.secondaryText)),
                            Text('₹${_advanceBalance.toStringAsFixed(0)}',
                                style: GoogleFonts.interTight(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: theme.error)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_byMonth.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Center(
                        child: Text('No job-staff earnings on record yet.',
                            style:
                                GoogleFonts.inter(color: theme.secondaryText)),
                      ),
                    )
                  else
                    ..._byMonth.entries.map((e) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: theme.secondaryBackground,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e.key,
                                  style: GoogleFonts.inter(
                                      fontSize: 13, color: theme.primaryText)),
                              Text('₹${e.value.toStringAsFixed(0)}',
                                  style: GoogleFonts.interTight(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: theme.primaryText)),
                            ],
                          ),
                        )),
                ],
              ),
      ),
    );
  }
}
