import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Session 2 Part C — My Attendance (`sup-att`). This supervisor's own
/// `attendance` rows for the current month. Kept as a simple date list
/// rather than a full calendar-grid widget — a thin screen, per the
/// brief's own scope note.
class SupervisorAttendancePageWidget extends StatefulWidget {
  const SupervisorAttendancePageWidget({super.key});

  static String routeName = 'SupervisorAttendancePage';
  static String routePath = '/sup-att';

  @override
  State<SupervisorAttendancePageWidget> createState() =>
      _SupervisorAttendancePageWidgetState();
}

class _SupervisorAttendancePageWidgetState
    extends State<SupervisorAttendancePageWidget> {
  bool _loading = true;
  final Map<String, String> _byDate = {}; // 'yyyy-MM-dd' -> status

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
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final rows = await SupaFlow.client
          .from('attendance')
          .select('attendance_date,status')
          .eq('org_id', orgId)
          .eq('staff_id', staffId)
          .gte('attendance_date', monthStart.toIso8601String().split('T').first)
          .order('attendance_date', ascending: false);
      if (mounted) {
        setState(() {
          _byDate
            ..clear()
            ..addEntries(rows.map((r) => MapEntry(
                r['attendance_date'] as String, r['status'] as String? ?? '')));
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _statusColor(FlutterFlowTheme theme, String status) {
    switch (status) {
      case 'present':
        return theme.success;
      case 'absent':
        return theme.error;
      default:
        return theme.secondaryText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final daysInMonth = DateUtils.getDaysInMonth(
        DateTime.now().year, DateTime.now().month);
    final presentCount = _byDate.values.where((s) => s == 'present').length;
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        elevation: 0,
        centerTitle: true,
        title: Text('My Attendance',
            style: theme.titleLarge.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600))),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(DateFormat('MMMM y').format(DateTime.now()),
                      style: GoogleFonts.interTight(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: theme.primaryText)),
                  const SizedBox(height: 4),
                  Text('$presentCount of $daysInMonth days marked present',
                      style: GoogleFonts.inter(
                          fontSize: 12.5, color: theme.secondaryText)),
                  const SizedBox(height: 12),
                  for (var d = 1; d <= daysInMonth; d++)
                    Builder(builder: (context) {
                      final date = DateTime(
                          DateTime.now().year, DateTime.now().month, d);
                      if (date.isAfter(DateTime.now())) {
                        return const SizedBox.shrink();
                      }
                      final key = date.toIso8601String().split('T').first;
                      final status = _byDate[key];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                                width: 90,
                                child: Text(DateFormat('EEE, d MMM').format(date),
                                    style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        color: theme.primaryText))),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: _statusColor(
                                        theme, status ?? 'unmarked')
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(status ?? 'Not marked',
                                  style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      color: _statusColor(
                                          theme, status ?? 'unmarked'))),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
      ),
    );
  }
}
