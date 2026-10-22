import '/components/ng_widgets.dart';
import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/supervisor_menu_button.dart';
import '/components/ng_top_bar.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/nav/nav.dart';
import '/index.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/supervisor_job_page/supervisor_job_page_model.dart';
import 'package:flutter/material.dart';
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

  /// Collapsed by default — device-test follow-up: as volume grows,
  /// delivered-but-not-yet-closed jobs would otherwise bury the active
  /// ones a supervisor actually needs to act on today.
  bool _showDelivered = false;

  List<OrdersRow> get _awaiting =>
      _jobs.where((o) => o.supervisorStatus == 'completed_pending').toList();

  List<OrdersRow> get _active => _jobs
      .where((o) =>
          o.supervisorStatus != 'completed_pending' && o.status != 'delivered')
      .toList();

  /// Owner already approved (or the job reached 'delivered' some other
  /// way) but the order isn't closed yet — a narrow but real state
  /// distinct from "awaiting", since it's no longer waiting on the owner.
  List<OrdersRow> get _recentlyDelivered => _jobs
      .where((o) =>
          o.supervisorStatus != 'completed_pending' && o.status == 'delivered')
      .toList();

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

  static const _kSteps = ['Accept', 'Arrival code', 'Crew & odometer', 'Shifting', 'Handover'];
  static const _kNextAction = [
    'Accept job',
    'Enter arrival code',
    'Pick the crew',
    'Continue shifting',
    'Hand over',
  ];

  int _stepIndex(OrdersRow o) => switch (supervisorStepFor(o)) {
        SupervisorJobStep.start => 0,
        SupervisorJobStep.arrivalCode => 1,
        SupervisorJobStep.team => 2,
        SupervisorJobStep.shifting => 3,
        SupervisorJobStep.completing => 4,
        SupervisorJobStep.done => 5,
      };

  void _openJob(OrdersRow o) => context.pushNamed(
        SupervisorJobPageWidget.routeName,
        queryParameters: {'orderId': o.id}.withoutNulls,
      );

  void _openMaps(OrdersRow o) {
    String place(String? addr, String? city) =>
        [addr, city].where((x) => (x ?? '').trim().isNotEmpty).join(', ');
    final from = place(o.fromAddress, o.fromCity);
    final to = place(o.toAddress, o.toCity);
    launchURL(Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      if (from.isNotEmpty) 'origin': from,
      if (to.isNotEmpty) 'destination': to,
    }).toString());
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final current = _active.isEmpty ? null : _active.first;
    final upNext = _active.skip(1).toList();
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
                  Text('My jobs',
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
            else if (_jobs.isEmpty)
              const NgEmptyState(
                icon: Icons.work_outline_rounded,
                title: 'No jobs assigned to you',
                subtitle: 'Jobs the office gives you show up here.',
              )
            else ...[
              if (current != null) ...[
                _currentJobCard(context, current),
                const SizedBox(height: 16),
                _closeTodayCard(context, current),
                const SizedBox(height: 16),
              ],
              if (upNext.isNotEmpty) ...[
                const NgSectionHeader('Up next'),
                const SizedBox(height: 8),
                for (final o in upNext) ...[
                  _upNextRow(context, o),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
              ],
              if (_awaiting.isNotEmpty) ...[
                NgSectionHeader('Awaiting approval',
                    trailing: '${_awaiting.length}'),
                const SizedBox(height: 8),
                for (final o in _awaiting) ...[
                  _upNextRow(context, o,
                      pill: const NgPill('Awaiting', status: NgStatus.amber)),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
              ],
              if (_recentlyDelivered.isNotEmpty) ...[
                NgSectionHeader(
                  'Recently delivered (${_recentlyDelivered.length})',
                  trailing: _showDelivered ? 'Hide' : 'Show',
                  onTrailing: () =>
                      setState(() => _showDelivered = !_showDelivered),
                ),
                if (_showDelivered) ...[
                  const SizedBox(height: 8),
                  for (final o in _recentlyDelivered) ...[
                    _upNextRow(context, o,
                        pill: const NgPill('Delivered',
                            status: NgStatus.green)),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// The design's "Current job" card: who and where, the field steps as a
  /// checklist, the next action, then Call / Maps. Advancing a step needs
  /// the field screen (arrival code, crew, signature), so the button opens
  /// it at the step the job is on rather than skipping those gates.
  Widget _currentJobCard(BuildContext context, OrdersRow o) {
    final c = NgPalette.of(context);
    final js = _stepIndex(o);
    final meta = [
      if ((o.service ?? '').trim().isNotEmpty) o.service!.trim(),
      if (o.moveDateOrNull != null)
        DateUtils.isSameDay(o.moveDateOrNull, DateTime.now())
            ? 'Today'
            : DateFormat('EEE d MMM').format(o.moveDateOrNull!),
    ].join(' · ');
    final phone = (o.phone ?? '').trim();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.s1,
        border: Border.all(color: c.w06),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('CURRENT JOB',
                    style: NgFonts.geist(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.75,
                        color: c.acc)),
              ),
              Text(o.id ?? '',
                  style: NgFonts.mono(fontSize: 12, color: c.faint)),
            ],
          ),
          const SizedBox(height: 16),
          Text(o.customer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NgFonts.geist(
                  fontSize: 19, fontWeight: FontWeight.w600, color: c.text)),
          const SizedBox(height: 4),
          Text(
              '${o.fromCity ?? '-'} → ${o.toCity ?? '-'}'
              '${meta.isEmpty ? '' : ' · $meta'}',
              style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
          const SizedBox(height: 16),
          for (var k = 0; k < _kSteps.length; k++)
            SizedBox(
              height: 34,
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: k < js
                          ? c.green
                          : k == js
                              ? c.accBtn
                              : Colors.transparent,
                      border: Border.all(
                          width: 1.5,
                          color: k < js
                              ? c.green
                              : k == js
                                  ? c.accBtn
                                  : c.hairline(0.2)),
                    ),
                    child: k < js
                        ? const Icon(Icons.check_rounded,
                            size: 14, color: NgPalette.onAcc)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Text(_kSteps[k],
                      style: NgFonts.geist(
                          fontSize: 14,
                          fontWeight:
                              k == js ? FontWeight.w600 : FontWeight.w400,
                          color: k <= js ? c.text : c.faint)),
                ],
              ),
            ),
          const SizedBox(height: 16),
          NgPrimaryButton(
            icon: Icons.check_circle_rounded,
            label: js >= _kSteps.length ? 'All done' : _kNextAction[js],
            height: 52,
            onPressed: () => _openJob(o),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: NgSecondaryButton(
                  icon: Icons.call_rounded,
                  iconColor: c.green,
                  label: 'Call',
                  onPressed:
                      phone.isEmpty ? null : () => launchURL('tel:$phone'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NgSecondaryButton(
                  icon: Icons.navigation_rounded,
                  iconColor: c.blue,
                  label: 'Maps',
                  onPressed: () => _openMaps(o),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "Close today": the day-close crew sheet for the job in hand (crew,
  /// food, costs, vehicle). Advances are recorded by the manager, not
  /// here (corrections A3).
  Widget _closeTodayCard(BuildContext context, OrdersRow o) {
    final c = NgPalette.of(context);
    return NgCard(
      padding: const EdgeInsets.all(14),
      onTap: () => context
          .pushNamed(CrewSheetPageWidget.routeName,
              queryParameters: {'orderId': o.id ?? ''})
          .then((_) => _load()),
      child: Row(
        children: [
          NgIconTile(
              icon: Icons.event_note_rounded,
              status: NgStatus.amber,
              size: 44,
              iconSize: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Close today',
                    style: NgFonts.geist(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.text)),
                const SizedBox(height: 2),
                Text('Crew, food, costs, vehicle',
                    style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 20, color: c.faint),
        ],
      ),
    );
  }

  Widget _upNextRow(BuildContext context, OrdersRow o, {Widget? pill}) {
    final c = NgPalette.of(context);
    final d = o.moveDateOrNull;
    return NgCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: () => _openJob(o),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Text(d == null ? '—' : DateFormat('d').format(d),
                    style: NgFonts.mono(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.text)),
                Text(
                    d == null
                        ? 'No date'
                        : DateUtils.isSameDay(d, DateTime.now())
                            ? 'Today'
                            : DateFormat('EEE').format(d),
                    style: NgFonts.geist(fontSize: 10.5, color: c.faint)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.customer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: c.text)),
                const SizedBox(height: 2),
                Text('${o.fromCity ?? '-'} → ${o.toCity ?? '-'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
              ],
            ),
          ),
          if (pill != null) ...[pill, const SizedBox(width: 4)],
          Icon(Icons.chevron_right_rounded, size: 20, color: c.faint),
        ],
      ),
    );
  }
}
