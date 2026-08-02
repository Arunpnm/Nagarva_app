import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/nav/nav.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Session 2 Part B1 — "My Jobs": every open order assigned to the
/// current supervisor. This is the real `sup-jobs` nav destination — a
/// list view across all of a supervisor's jobs, distinct from
/// `SupervisorJobPageWidget` (the field-side workflow for one specific
/// order, opened by tapping a card here).
class SupervisorJobsListPageWidget extends StatefulWidget {
  const SupervisorJobsListPageWidget({super.key});

  static String routeName = 'SupervisorJobsListPage';
  static String routePath = '/sup-jobs';

  @override
  State<SupervisorJobsListPageWidget> createState() =>
      _SupervisorJobsListPageWidgetState();
}

class _SupervisorJobsListPageWidgetState
    extends State<SupervisorJobsListPageWidget>
    with RefreshOnPopMixin<SupervisorJobsListPageWidget> {
  bool _loading = true;
  List<OrdersRow> _jobs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onPageRefresh() => _load();

  Future<void> _load() async {
    final staffId = AppSession.instance.currentStaffId;
    if (staffId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      // Plain .neq (not .neqOrNull — that helper's "OrNull" refers to the
      // filter argument being nullable, not the row's column, and 'closed'/
      // 'cancelled' are always non-null literals here). A NULL status row
      // would be excluded by .neq at the DB level, so the client-side
      // re-filter below is the actual correctness guarantee for that case.
      final rows = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q)
            .eq('supervisor_id', staffId)
            .neq('status', 'closed')
            .neq('status', 'cancelled')
            .order('move_date', ascending: true),
      );
      if (mounted) {
        setState(() {
          _jobs = rows
              .where((o) => o.status != 'closed' && o.status != 'cancelled')
              .toList();
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
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        elevation: 0,
        centerTitle: true,
        title: Text('My Jobs',
            style: theme.titleLarge.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600))),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _jobs.isEmpty
                ? Center(
                    child: Text('No open jobs assigned to you.',
                        style: GoogleFonts.inter(color: theme.secondaryText)))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _jobs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => _jobCard(context, _jobs[i]),
                    ),
                  ),
      ),
    );
  }

  Widget _jobCard(BuildContext context, OrdersRow o) {
    final theme = FlutterFlowTheme.of(context);
    final awaiting = o.supervisorStatus == 'completed_pending';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.pushNamed(
        SupervisorJobPageWidget.routeName,
        queryParameters: {'orderId': o.id}.withoutNulls,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${o.id} · ${o.customer}',
                      style: GoogleFonts.interTight(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: theme.primaryText)),
                  const SizedBox(height: 3),
                  Text('${o.fromCity ?? '—'} → ${o.toCity ?? '—'}',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: theme.secondaryText)),
                  const SizedBox(height: 2),
                  Text(
                      o.moveDateOrNull == null
                          ? 'No date'
                          : DateFormat('d MMM y').format(o.moveDateOrNull!),
                      style: GoogleFonts.inter(
                          fontSize: 11.5, color: theme.secondaryText)),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: awaiting
                    ? const Color(0xFFE0A82E).withValues(alpha: 0.15)
                    : theme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                awaiting ? '⏳ Awaiting' : (o.status ?? '—'),
                style: GoogleFonts.interTight(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: awaiting ? const Color(0xFFE0A82E) : theme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
