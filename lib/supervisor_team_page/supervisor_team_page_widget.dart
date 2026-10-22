import '/components/ng_widgets.dart';
import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/supervisor_menu_button.dart';
import '/components/ng_top_bar.dart';
import '/flutter_flow/ng_tokens.dart';
import 'package:flutter/material.dart';

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
    return Scaffold(
      backgroundColor: c.bg,
      appBar: const NgTopBar(extraActions: [SupervisorMenuButton()]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            NgScreenTitle('My team',
                large: true,
                subtitle: _loading
                    ? null
                    : '$present of ${_team.length} present today'),
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
              NgProgressBar(
                    value: present / _team.length,
                    color: c.green),
              const SizedBox(height: 16),
              NgCardList(children: [
                for (final s in _team)
                  NgListRow(
                    leading: NgAvatar(s.name,
                        status: _presentToday.contains(s.id)
                            ? NgStatus.green
                            : NgStatus.neutral),
                    title: s.name,
                    subtitle: _roleLabel(s.role),
                    trailing: _presentToday.contains(s.id)
                        ? const NgPill('Present',
                            status: NgStatus.green,
                            icon: Icons.check_rounded)
                        : SizedBox(
                            width: 124,
                            height: 34,
                            child: NgSecondaryButton(
                              label: 'Mark present',
                              height: 34,
                              onPressed: _busy ? null : () => _markPresent(s),
                            ),
                          ),
                  ),
              ]),
            ],
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
