import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '/app_session.dart';
import '/backend/crew_checkin.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/flutter_flow_util.dart' show launchURL;
import '/flutter_flow/ng_tokens.dart';

/// My team › today's job: the rotating crew check-in code, the crew with
/// how each one checked in, the supervisor's own GPS + selfie check-in,
/// and "Mark present" (with a reason) for someone without a phone.
///
/// Renders nothing when the supervisor has no job today, or before the
/// check-in migration has run.
class CrewCheckinCard extends StatefulWidget {
  const CrewCheckinCard({super.key});
  @override
  State<CrewCheckinCard> createState() => _CrewCheckinCardState();
}

class _CrewCheckinCardState extends State<CrewCheckinCard> {
  List<OrdersRow> _jobs = const [];
  String? _orderId;
  List<Map<String, dynamic>> _crew = const [];
  Map<String, Map<String, dynamic>> _checkins = const {};
  String? _payload;
  int _left = 0;
  Timer? _tick;
  bool _ready = false;
  bool _busy = false;
  String? _codeError;

  String? get _me => AppSession.instance.currentStaffId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final me = _me;
    if (me == null) return;
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final jobs = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q)
            .eq('supervisor_id', me)
            .eq('move_date', today)
            .not('status', 'in', '(closed,cancelled)'),
      );
      _jobs = jobs;
      _orderId = jobs.any((j) => j.id == _orderId) ? _orderId : jobs.firstOrNull?.id;
      await _loadCrew();
      if (mounted) setState(() => _ready = true);
      _startCode();
    } catch (_) {
      if (mounted) setState(() => _ready = false);
    }
  }

  Future<void> _loadCrew() async {
    final id = _orderId;
    if (id == null) return;
    final db = SupaFlow.client;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final r = await Future.wait([
      db.from('order_staff').select('staff_id, staff(id,name,role,phone)').eq('order_id', id),
      db.from('crew_checkins').select().eq('order_id', id).eq('day', today),
    ]);
    _crew = [
      for (final x in r[0] as List)
        if (x['staff'] is Map) Map<String, dynamic>.from(x['staff'] as Map)
    ];
    _checkins = {for (final c in r[1] as List) '${c['staff_id']}': Map<String, dynamic>.from(c)};
  }

  void _startCode() {
    _tick?.cancel();
    if (_orderId == null) return;
    _fetchCode();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left <= 1) {
        _fetchCode();
        // Refresh who has checked in each time the code turns over.
        _loadCrew().then((_) => mounted ? setState(() {}) : null).catchError((_) {});
      } else {
        setState(() => _left--);
      }
    });
  }

  Future<void> _fetchCode() async {
    final id = _orderId;
    if (id == null) return;
    try {
      final c = await CrewCheckin.code(id);
      if (mounted) {
        setState(() {
          _payload = c.payload;
          _left = c.secondsLeft;
          _codeError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _codeError = checkinError(e));
    }
  }

  void _toast(String s) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(s)));

  Future<void> _selfCheckIn() async {
    setState(() => _busy = true);
    try {
      final msg = await CrewCheckin.supervisorCheckIn(_orderId!);
      if (msg != null) _toast(msg);
      await _loadCrew();
    } catch (e) {
      _toast(checkinError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mark(Map<String, dynamic> s) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mark ${s['name']} present'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Why can\'t they scan?', hintText: 'e.g. Phone battery dead'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark present')),
        ],
      ),
    );
    final reason = ctrl.text.trim();
    // After the close animation - see support_tickets_page.dart (BUG-020).
    Future.delayed(const Duration(milliseconds: 600), ctrl.dispose);
    if (ok != true) return;
    try {
      await CrewCheckin.markPresent(_orderId!, '${s['id']}', reason);
      await _loadCrew();
      if (mounted) setState(() {});
      _toast('${s['name']} marked present. The owner will see why.');
    } catch (e) {
      _toast(checkinError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _jobs.isEmpty) return const SizedBox.shrink();
    final c = NgPalette.of(context);
    final job = _jobs.firstWhere((j) => j.id == _orderId, orElse: () => _jobs.first);
    final crew = _crew.where((s) => s['id'] != _me).toList();
    final mine = _checkins[_me];
    final checked = crew.where((s) => _checkins.containsKey(s['id'])).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_jobs.length > 1) ...[
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final j in _jobs)
            NgChip(
                label: '${j.id}',
                selected: j.id == _orderId,
                onTap: () async {
                  setState(() => _orderId = j.id);
                  await _loadCrew();
                  _startCode();
                }),
        ]),
        const SizedBox(height: 10),
      ],
      NgCard(
        radius: 20,
        child: Column(children: [
          Row(children: [
            Expanded(
              child: Text('Crew check-in code',
                  style: NgFonts.geist(fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
            ),
            Text('$checked of ${crew.length} checked in',
                style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
          ]),
          const SizedBox(height: 12),
          if (_codeError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(_codeError!,
                  textAlign: TextAlign.center, style: NgFonts.geist(fontSize: 13, color: c.red)),
            )
          else if (_payload == null)
            const Padding(
                padding: EdgeInsets.all(40), child: CircularProgressIndicator())
          else
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.white, // QR needs a light ground in every theme
              child: QrImageView(data: _payload!, size: 210, backgroundColor: Colors.white),
            ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.autorenew_rounded, size: 16, color: c.acc),
            const SizedBox(width: 6),
            Text('New code in ${_left}s', style: NgFonts.geist(fontSize: 13, color: c.soft)),
          ]),
          const SizedBox(height: 6),
          Text('Crew scan this from their own phone to check in. Keep it on screen at the site.',
              textAlign: TextAlign.center,
              style: NgFonts.geist(fontSize: 12.5, color: c.mute, height: 1.4)),
          const SizedBox(height: 12),
          if (mine == null)
            NgSecondaryButton(
              label: _busy ? 'Checking in…' : 'Check myself in (location + selfie)',
              icon: Icons.my_location_rounded,
              onPressed: _busy ? null : _selfCheckIn,
            )
          else
            Text('You checked in at ${_time(mine['checked_in_at'])}',
                style: NgFonts.geist(fontSize: 12.5, color: c.green)),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: NgSectionHeader("Today's crew · ${job.customer}")),
        Text('${job.id}', style: NgFonts.mono(fontSize: 12, color: c.mute)),
      ]),
      const SizedBox(height: 8),
      if (crew.isEmpty)
        Text('No crew on this job yet. Add them on the job\'s crew stage.',
            style: NgFonts.geist(fontSize: 13, color: c.faint))
      else
        NgCardList(children: [
          for (final s in crew) _crewRow(c, s),
        ]),
      const SizedBox(height: 8),
      Text('Mark present only for someone without a working phone. The owner sees who marked it and why.',
          textAlign: TextAlign.center,
          style: NgFonts.geist(fontSize: 12, color: c.faint, height: 1.4)),
      const SizedBox(height: 18),
    ]);
  }

  String _time(dynamic ts) {
    final t = DateTime.tryParse('${ts ?? ''}')?.toLocal();
    return t == null ? '' : DateFormat('h:mm a').format(t);
  }

  Widget _crewRow(NgPalette c, Map<String, dynamic> s) {
    final ci = _checkins['${s['id']}'];
    final phone = '${s['phone'] ?? ''}'.trim();
    final (label, color) = ci == null
        ? ('Absent', c.red)
        : ci['late'] == true
            ? ('Late', c.amber)
            : ('Present', c.green);
    final how = switch (ci?['method']) {
      'code' => 'code',
      'manual' => 'marked',
      'supervisor_gps' => 'GPS',
      _ => '',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(children: [
        NgAvatar('${s['name']}',
            status: ci == null ? NgStatus.red : (ci['late'] == true ? NgStatus.amber : NgStatus.green)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s['name']}', style: NgFonts.geist(fontSize: 14.5, color: c.text)),
            Text(_role('${s['role'] ?? ''}'), style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
          ]),
        ),
        if (ci == null)
          TextButton(onPressed: () => _mark(s), child: const Text('Mark present'))
        else
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(label, style: NgFonts.geist(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
            Text('${_time(ci['checked_in_at'])} · $how',
                style: NgFonts.geist(fontSize: 11.5, color: c.mute)),
          ]),
        if (ci == null)
          Text(label, style: NgFonts.geist(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Call',
          onPressed: phone.isEmpty ? null : () => launchURL('tel:$phone'),
          icon: Icon(Icons.call_rounded, size: 18, color: phone.isEmpty ? c.faint : c.green),
        ),
      ]),
    );
  }

  static String _role(String r) => r.isEmpty ? 'Staff' : r[0].toUpperCase() + r.substring(1);
}
