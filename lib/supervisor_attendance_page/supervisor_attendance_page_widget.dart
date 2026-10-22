import '/components/ng_widgets.dart';
import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/supervisor_menu_button.dart';
import '/components/ng_top_bar.dart';
import '/flutter_flow/ng_tokens.dart';
import 'package:flutter/material.dart';
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

  NgStatus _tone(String? status) => switch (status) {
        'present' => NgStatus.green,
        'absent' => NgStatus.red,
        'half_day' || 'leave' => NgStatus.amber,
        _ => NgStatus.neutral,
      };

  String _label(String? status) {
    final v = (status ?? '').replaceAll('_', ' ').trim();
    if (v.isEmpty) return 'Not marked';
    return v[0].toUpperCase() + v.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final now = DateTime.now();
    final presentCount = _byDate.values.where((s) => s == 'present').length;
    final days = [
      for (var d = now.day; d >= 1; d--) DateTime(now.year, now.month, d),
    ];
    return Scaffold(
      backgroundColor: c.bg,
      appBar: const NgTopBar(extraActions: [SupervisorMenuButton()]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            NgScreenTitle('My attendance',
                large: true, subtitle: DateFormat('MMMM y').format(now)),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('$presentCount',
                            style: NgFonts.geist(
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.56,
                                color: c.text)),
                        const SizedBox(width: 6),
                        Text('of ${now.day} days present',
                            style: NgFonts.geist(fontSize: 13, color: c.mute)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    NgProgressBar(
                        value: presentCount / now.day, color: c.green),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const NgSectionHeader('Days'),
              const SizedBox(height: 10),
              NgCardList(children: [
                for (final date in days)
                  Builder(builder: (context) {
                    final status =
                        _byDate[date.toIso8601String().split('T').first];
                    return NgListRow(
                      leading: NgIconTile(
                        icon: status == 'present'
                            ? Icons.check_rounded
                            : status == 'absent'
                                ? Icons.close_rounded
                                : Icons.remove_rounded,
                        status: _tone(status),
                      ),
                      title: DateFormat('EEE, d MMM').format(date),
                      trailing: NgPill(_label(status), status: _tone(status)),
                    );
                  }),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
