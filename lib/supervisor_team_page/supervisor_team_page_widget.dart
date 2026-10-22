import '/components/ng_widgets.dart';
import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/supervisor_menu_button.dart';
import '/components/ng_top_bar.dart';
import '/flutter_flow/ng_tokens.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '/flutter_flow/flutter_flow_util.dart' show launchURL;

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
    final c = NgPalette.of(context);
    final present = _team.where((s) => _presentToday.contains(s.id)).length;
    final tiles = [
      ('Present', present, c.green),
      ('Not marked', _team.length - present, c.amber),
      ('In team', _team.length, c.mute),
    ];
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(DateFormat('EEEE, d MMMM').format(DateTime.now()),
                      style: NgFonts.geist(fontSize: 13, color: c.mute)),
                  const SizedBox(height: 4),
                  Text('My team',
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
            else if (_team.isEmpty)
              const NgEmptyState(
                icon: Icons.groups_outlined,
                title: 'No staff in your branch',
                subtitle: 'Ask the owner to add staff to your branch.',
              )
            else ...[
              Row(
                children: [
                  for (var k = 0; k < tiles.length; k++) ...[
                    if (k > 0) const SizedBox(width: 8),
                    Expanded(
                      child: NgCard(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                  color: tiles[k].$3, shape: BoxShape.circle),
                            ),
                            const SizedBox(height: 8),
                            Text('${tiles[k].$2}',
                                style: NgFonts.geist(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.44,
                                    color: c.text)),
                            const SizedBox(height: 2),
                            Text(tiles[k].$1,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: NgFonts.geist(
                                    fontSize: 12.5, color: c.mute)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              const NgSectionHeader("Today's crew"),
              const SizedBox(height: 10),
              NgCard(
                radius: 20,
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (var i = 0; i < _team.length; i++)
                    _memberRow(context, _team[i], first: i == 0),
                ]),
              ),
              const SizedBox(height: 10),
              Text('Tap a name to mark them present',
                  textAlign: TextAlign.center,
                  style: NgFonts.geist(fontSize: 12.5, color: c.faint)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _memberRow(BuildContext context, StaffRow s, {required bool first}) {
    final c = NgPalette.of(context);
    final present = _presentToday.contains(s.id);
    final phone = (s.phone ?? '').trim();
    return InkWell(
      onTap: present || _busy ? null : () => _markPresent(s),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
            border: first ? null : Border(top: BorderSide(color: c.w06))),
        child: Row(
          children: [
            NgAvatar(s.name,
                status: present ? NgStatus.green : NgStatus.neutral,
                size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name,
                      style: NgFonts.geist(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: c.text)),
                  const SizedBox(height: 1),
                  Text(_roleLabel(s.role),
                      style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
                ],
              ),
            ),
            Text(present ? 'Present' : 'Not marked',
                style: NgFonts.geist(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: present ? c.green : c.amber)),
            const SizedBox(width: 10),
            SizedBox(
              width: 36,
              height: 36,
              child: Material(
                color: c.greenBg,
                borderRadius: BorderRadius.circular(11),
                child: InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: phone.isEmpty ? null : () => launchURL('tel:$phone'),
                  child: Icon(Icons.call_rounded,
                      size: 18, color: phone.isEmpty ? c.faint : c.green),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _roleLabel(String? r) {
    final v = (r ?? '').trim();
    if (v.isEmpty) return 'Staff';
    return v[0].toUpperCase() + v.substring(1);
  }
}
