import '/components/ng_widgets.dart';
import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/supervisor_menu_button.dart';
import '/components/ng_top_bar.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/nav/nav.dart';
import '/index.dart';
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

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final today = _active
        .where((o) =>
            o.moveDateOrNull != null &&
            DateUtils.isSameDay(o.moveDateOrNull, DateTime.now()))
        .length;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: const NgTopBar(extraActions: [SupervisorMenuButton()]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            NgScreenTitle('My jobs',
                large: true,
                subtitle: _loading
                    ? null
                    : today == 0
                        ? '${_active.length} open'
                        : '$today today · ${_active.length} open'),
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
              for (var i = 0; i < _active.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _jobCard(context, _active[i]),
              ],
              if (_awaiting.isNotEmpty) ...[
                const SizedBox(height: 22),
                NgSectionHeader('Awaiting approval',
                    trailing: '${_awaiting.length}'),
                const SizedBox(height: 10),
                for (var i = 0; i < _awaiting.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _jobCard(context, _awaiting[i]),
                ],
              ],
              if (_recentlyDelivered.isNotEmpty) ...[
                const SizedBox(height: 22),
                NgSectionHeader(
                  'Recently delivered (${_recentlyDelivered.length})',
                  trailing: _showDelivered ? 'Hide' : 'Show',
                  onTrailing: () =>
                      setState(() => _showDelivered = !_showDelivered),
                ),
                if (_showDelivered) ...[
                  const SizedBox(height: 10),
                  for (var i = 0; i < _recentlyDelivered.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _jobCard(context, _recentlyDelivered[i]),
                  ],
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  ({String label, NgStatus tone}) _stage(OrdersRow o) {
    if (o.supervisorStatus == 'completed_pending') {
      return (label: 'Awaiting approval', tone: NgStatus.amber);
    }
    switch ((o.status ?? '').toLowerCase()) {
      case 'transit':
      case 'in_transit':
        return (label: 'In progress', tone: NgStatus.blue);
      case 'delivered':
        return (label: 'Delivered', tone: NgStatus.green);
      case 'team_assigned':
      case 'confirmed':
      case 'booked':
        return (label: 'Assigned', tone: NgStatus.accent);
      default:
        final s = (o.status ?? '').trim();
        return (
          label: s.isEmpty ? 'Pending' : s[0].toUpperCase() + s.substring(1),
          tone: NgStatus.neutral
        );
    }
  }

  Widget _jobCard(BuildContext context, OrdersRow o) {
    final c = NgPalette.of(context);
    final st = _stage(o);
    return NgCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      onTap: () => context.pushNamed(
        SupervisorJobPageWidget.routeName,
        queryParameters: {'orderId': o.id}.withoutNulls,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(o.id ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.mono(fontSize: 12, color: c.faint)),
              ),
              Icon(Icons.event_outlined, size: 16, color: c.mute),
              const SizedBox(width: 5),
              Text(
                  o.moveDateOrNull == null
                      ? 'No date'
                      : DateFormat('d MMM').format(o.moveDateOrNull!),
                  style: NgFonts.geist(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: c.soft)),
            ],
          ),
          const SizedBox(height: 12),
          Text(o.customer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NgFonts.geist(
                  fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
          const SizedBox(height: 3),
          Row(
            children: [
              Flexible(
                child: Text(o.fromCity ?? '-',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(fontSize: 13, color: c.mute)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child:
                    Icon(Icons.arrow_forward_rounded, size: 15, color: c.faint),
              ),
              Flexible(
                child: Text(o.toCity ?? '-',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(fontSize: 13, color: c.mute)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration:
                BoxDecoration(border: Border(top: BorderSide(color: c.w06))),
            child: Row(
              children: [
                NgPill(st.label, status: st.tone),
                const Spacer(),
                Text('Open job',
                    style: NgFonts.geist(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.acc)),
                Icon(Icons.chevron_right_rounded, size: 18, color: c.acc),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
