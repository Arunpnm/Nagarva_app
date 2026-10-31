import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '/app_session.dart';
import '/backend/crew_checkin.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/components/supervisor_menu_button.dart';
import '/flutter_flow/flutter_flow_util.dart' show launchURL;
import '/flutter_flow/ng_tokens.dart';

/// Field staff › Attendance (design role-03): scan the supervisor's
/// check-in code at the site, today's job, and this week at a glance.
/// There is no self check-in: the code on the supervisor's phone changes
/// every 30 seconds, so a scan proves you were there.
class FieldAttendancePageWidget extends StatefulWidget {
  const FieldAttendancePageWidget({super.key});

  static String routeName = 'FieldAttendancePage';
  static String routePath = '/my-att';

  @override
  State<FieldAttendancePageWidget> createState() => _FieldAttendancePageWidgetState();
}

class _FieldAttendancePageWidgetState extends State<FieldAttendancePageWidget> {
  bool _loading = true;
  Map<String, dynamic>? _job;
  Map<String, dynamic>? _supervisor;
  Set<String> _presentDays = {};
  bool _checkedInToday = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = AppSession.instance.currentStaffId;
    final org = OrgScope.currentOrgId;
    if (me == null || org == null) {
      setState(() => _loading = false);
      return;
    }
    final db = SupaFlow.client;
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final monday = now.subtract(Duration(days: now.weekday - 1));
    try {
      final r = await Future.wait([
        db
            .from('order_staff')
            .select('orders(id,customer,from_city,to_city,from_address,move_date,move_time,supervisor_id,status,vehicle_no)')
            .eq('staff_id', me),
        db
            .from('attendance')
            .select('attendance_date')
            .eq('org_id', org)
            .eq('staff_id', me)
            .gte('attendance_date', DateFormat('yyyy-MM-dd').format(monday)),
      ]);
      final jobs = [
        for (final x in r[0] as List)
          if (x['orders'] is Map && '${x['orders']['move_date']}' == today
              && !const {'closed', 'cancelled'}.contains(x['orders']['status']))
            Map<String, dynamic>.from(x['orders'] as Map)
      ];
      _job = jobs.firstOrNull;
      _presentDays = {for (final a in r[1] as List) '${a['attendance_date']}'};
      _checkedInToday = _presentDays.contains(today);
      _supervisor = null;
      final sup = _job?['supervisor_id'];
      if (sup != null) {
        _supervisor = await db.from('staff').select('name,phone').eq('id', sup).maybeSingle();
      }
    } catch (_) {
      // Shown as "no job today"; the scan still works.
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _scan() async {
    final payload = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const _ScanPage(), fullscreenDialog: true));
    if (payload == null || !mounted) return;
    ({bool ok, String message}) r;
    try {
      r = await CrewCheckin.scan(payload);
    } catch (e) {
      r = (ok: false, message: checkinError(e));
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(r.ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            color: r.ok ? NgPalette.of(ctx).green : NgPalette.of(ctx).red, size: 40),
        content: Text(r.message, textAlign: TextAlign.center),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
    if (r.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final job = _job;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: const NgTopBar(extraActions: [SupervisorMenuButton()]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Text(DateFormat('EEEE, d MMMM').format(now), style: NgFonts.geist(fontSize: 13, color: c.mute)),
            const SizedBox(height: 4),
            Text('Attendance',
                style: NgFonts.geist(fontSize: 26, fontWeight: FontWeight.w600, color: c.text)),
            const SizedBox(height: 16),
            NgCard(
              radius: 24,
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
              child: Column(children: [
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _scan,
                  child: Container(
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _checkedInToday ? c.greenBg : c.acc.withValues(alpha: 0.10),
                      border: Border.all(color: _checkedInToday ? c.green : c.acc),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(_checkedInToday ? Icons.check_rounded : Icons.qr_code_scanner_rounded,
                          size: 46, color: _checkedInToday ? c.green : c.acc),
                      const SizedBox(height: 8),
                      Text(_checkedInToday ? 'Checked in today' : 'Scan to check in',
                          style: NgFonts.geist(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _checkedInToday ? c.green : c.acc)),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: c.inset, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    Icon(Icons.qr_code_2_rounded, color: c.mute, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          'Scan the code on your supervisor\'s phone at the site. It changes every 30 seconds, so it only works when you are there.',
                          style: NgFonts.geist(fontSize: 12.5, color: c.soft, height: 1.4)),
                    ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (job == null)
              Text('No job for you today.', style: NgFonts.geist(fontSize: 13, color: c.faint))
            else
              NgCard(
                radius: 20,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text("TODAY'S JOB",
                          style: NgFonts.geist(
                              fontSize: 12, fontWeight: FontWeight.w700, color: c.acc, letterSpacing: 0.6)),
                    ),
                    if ('${job['vehicle_no'] ?? ''}'.isNotEmpty)
                      Text('${job['vehicle_no']}', style: NgFonts.mono(fontSize: 12, color: c.mute)),
                  ]),
                  const SizedBox(height: 4),
                  Text('${job['customer'] ?? ''}',
                      style: NgFonts.geist(fontSize: 18, fontWeight: FontWeight.w600, color: c.text)),
                  Text(
                      [
                        '${job['from_city'] ?? ''} → ${job['to_city'] ?? ''}',
                        if (job['move_time'] != null) '${job['move_time']}'.substring(0, 5),
                      ].join(' · '),
                      style: NgFonts.geist(fontSize: 13, color: c.mute)),
                  const SizedBox(height: 12),
                  Row(children: [
                    if ('${_supervisor?['phone'] ?? ''}'.isNotEmpty)
                      Expanded(
                        child: NgSecondaryButton(
                          label: '${_supervisor!['name']}',
                          icon: Icons.call_rounded,
                          iconColor: c.green,
                          onPressed: () => launchURL('tel:${_supervisor!['phone']}'),
                        ),
                      ),
                    if ('${job['from_address'] ?? ''}'.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: NgSecondaryButton(
                          label: 'Maps',
                          icon: Icons.navigation_outlined,
                          iconColor: c.blue,
                          onPressed: () => launchURL(
                              'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('${job['from_address']}')}'),
                        ),
                      ),
                    ],
                  ]),
                ]),
              ),
            const SizedBox(height: 14),
            NgCard(
              radius: 20,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('This week',
                    style: NgFonts.geist(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 10),
                Row(children: [
                  for (var i = 0; i < 7; i++)
                    () {
                      final d = monday.add(Duration(days: i));
                      final key = DateFormat('yyyy-MM-dd').format(d);
                      final present = _presentDays.contains(key);
                      final isToday = key == DateFormat('yyyy-MM-dd').format(now);
                      return Expanded(
                        child: Column(children: [
                          Text(DateFormat('E').format(d).substring(0, 1),
                              style: NgFonts.geist(fontSize: 12, color: c.mute)),
                          const SizedBox(height: 6),
                          Container(
                            height: 36,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: present ? c.greenBg : (isToday ? c.amberBg : c.inset),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: present
                                ? Icon(Icons.check_rounded, size: 18, color: c.green)
                                : isToday
                                    ? Icon(Icons.radio_button_unchecked, size: 16, color: c.amber)
                                    : null,
                          ),
                        ]),
                      );
                    }(),
                ]),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen camera that returns the first Nagarva check-in code it sees.
class _ScanPage extends StatefulWidget {
  const _ScanPage();
  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Scan the supervisor\'s code'),
        ),
        body: Stack(alignment: Alignment.center, children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_done) return;
              for (final b in capture.barcodes) {
                final v = b.rawValue;
                if (v != null && v.startsWith('NGV1|')) {
                  _done = true;
                  Navigator.of(context).pop(v);
                  return;
                }
              }
            },
            errorBuilder: (context, error) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? 'Nagarva needs the camera to scan the code. Allow it in your phone\'s settings.'
                    : 'The camera could not start.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
          IgnorePointer(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ]),
      );
}
