import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Session 2 Part C — My Team (`sup-team`). Staff in the supervisor's own
/// branch, with today's attendance state and a mark-present action.
class SupervisorTeamPageWidget extends StatefulWidget {
  const SupervisorTeamPageWidget({super.key});

  static String routeName = 'SupervisorTeamPage';
  static String routePath = '/sup-team';

  @override
  State<SupervisorTeamPageWidget> createState() =>
      _SupervisorTeamPageWidgetState();
}

class _SupervisorTeamPageWidgetState extends State<SupervisorTeamPageWidget> {
  bool _loading = true;
  List<StaffRow> _team = [];
  Set<String> _presentToday = {};
  bool _busy = false;

  String get _today => DateTime.now().toIso8601String().split('T').first;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final staffId = AppSession.instance.currentStaffId;
      String? myBranch;
      if (staffId != null) {
        final me = await StaffTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('id', staffId),
        );
        myBranch = me.firstOrNull?.branch;
      }
      final rows = await StaffTable().queryRows(
        queryFn: (q) => OrgScope.read(q)
            .eqOrNull('active', true)
            .eqOrNull('branch', myBranch),
      );
      final orgId = OrgScope.currentOrgId!;
      final attRows = await SupaFlow.client
          .from('attendance')
          .select('staff_id')
          .eq('org_id', orgId)
          .eq('attendance_date', _today);
      if (mounted) {
        setState(() {
          _team = rows;
          _presentToday =
              attRows.map((r) => r['staff_id'] as String).toSet();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markPresent(StaffRow s) async {
    if (s.id == null || _presentToday.contains(s.id)) return;
    setState(() => _busy = true);
    try {
      final orgId = OrgScope.currentOrgId!;
      await SupaFlow.client.from('attendance').insert({
        'org_id': orgId,
        'staff_id': s.id,
        'attendance_date': _today,
        'status': 'present',
        'marked_by': AppSession.instance.currentStaffName ?? 'Supervisor',
      });
      if (mounted) setState(() => _presentToday.add(s.id!));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not mark: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
        title: Text('My Team',
            style: theme.titleLarge.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600))),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _team.isEmpty
                ? Center(
                    child: Text('No staff found for your branch.',
                        style: GoogleFonts.inter(color: theme.secondaryText)))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _team.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final s = _team[i];
                      final present = _presentToday.contains(s.id);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
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
                                  Text(s.name,
                                      style: GoogleFonts.interTight(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5,
                                          color: theme.primaryText)),
                                  Text(s.role ?? '—',
                                      style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          color: theme.secondaryText)),
                                ],
                              ),
                            ),
                            present
                                ? Chip(
                                    label: const Text('Present'),
                                    backgroundColor:
                                        theme.success.withValues(alpha: 0.15),
                                    labelStyle:
                                        TextStyle(color: theme.success),
                                  )
                                : OutlinedButton(
                                    onPressed:
                                        _busy ? null : () => _markPresent(s),
                                    child: const Text('Mark Present'),
                                  ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
