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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(DateFormat('EEEE, d MMMM').format(now),
                      style: NgFonts.geist(fontSize: 13, color: c.mute)),
                  const SizedBox(height: 4),
                  Text('Attendance',
                      style: NgFonts.geist(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.52,
                          color: c.text)),
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
              _weekCard(context),
              const SizedBox(height: 16),
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
              const NgSectionHeader('This month'),
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

  /// The design's "This week" strip: Mon–Sun, a tile per day.
  Widget _weekCard(BuildContext context) {
    final c = NgPalette.of(context);
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return NgCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This week',
              style: NgFonts.geist(
                  fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var k = 0; k < 7; k++)
                Expanded(
                  child: Builder(builder: (context) {
                    final d = monday.add(Duration(days: k));
                    final future = d.isAfter(now);
                    final status =
                        _byDate[d.toIso8601String().split('T').first];
                    final tone = c.status(_tone(status));
                    return Column(
                      children: [
                        Text(DateFormat('E').format(d).substring(0, 1),
                            style:
                                NgFonts.geist(fontSize: 11.5, color: c.faint)),
                        const SizedBox(height: 8),
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: future ? Colors.transparent : tone.bg,
                            border: future ? Border.all(color: c.w08) : null,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: future
                              ? null
                              : Icon(
                                  status == 'present'
                                      ? Icons.check_rounded
                                      : status == 'absent'
                                          ? Icons.close_rounded
                                          : Icons.remove_rounded,
                                  size: 18,
                                  color: tone.fg),
                        ),
                      ],
                    );
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
