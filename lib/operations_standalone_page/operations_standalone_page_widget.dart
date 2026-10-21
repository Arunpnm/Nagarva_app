import 'package:flutter/material.dart';

import '/backend/order_stages.dart';
import '/backend/tracking_service.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';

/// Operations standalone (Session 4, Part C-4) — two tabs over
/// `order_tracking` (the staff-side milestone log, distinct from
/// `order_status_history`, which TrackingService already writes for the
/// public customer timeline) and `complaints`.
///
/// "Tracking entries update order status via a label map" — reuses the
/// existing kOrderStages/orderStageLabel label map (order_stages.dart,
/// already built for the public tracking page) rather than inventing a
/// second vocabulary. Logging an entry here writes to order_tracking AND
/// calls TrackingService.setStatus, so the order's own status, the public
/// timeline, and this staff-side log all move together.
class OperationsStandalonePageWidget extends StatefulWidget {
  const OperationsStandalonePageWidget({super.key});

  static String routeName = 'OperationsStandalonePage';
  static String routePath = '/ops-standalone';

  @override
  State<OperationsStandalonePageWidget> createState() =>
      _OperationsStandalonePageWidgetState();
}

class _OperationsStandalonePageWidgetState
    extends State<OperationsStandalonePageWidget>
    with SingleTickerProviderStateMixin, RefreshOnPopMixin<OperationsStandalonePageWidget> {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  bool _loading = true;
  List<OrderTrackingRow> _tracking = [];
  List<ComplaintsRow> _complaints = [];
  String? _complaintStatusFilter;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
    _load();
  }

  @override
  void onPageRefresh() => _load();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _tracking = await OrderTrackingTable().queryRows(
        queryFn: (q) =>
            OrgScope.read(q).order('tracked_at', ascending: false).limit(100),
      );
      _complaints = await ComplaintsTable().queryRows(
        queryFn: (q) =>
            OrgScope.read(q).order('reported_at', ascending: false),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logTrackingUpdate() async {
    final orderIdCtrl = TextEditingController();
    String stage = kStageConfirmed;
    final noteCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Log Tracking Update'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: orderIdCtrl,
                decoration: const InputDecoration(labelText: 'Order ID'),
                autofocus: true,
              ),
              DropdownButtonFormField<String>(
                initialValue: stage,
                decoration: const InputDecoration(labelText: 'Stage'),
                items: [
                  for (final s in kOrderStages)
                    DropdownMenuItem(value: s, child: Text(orderStageLabel(s))),
                ],
                onChanged: (v) => setDialogState(() => stage = v ?? stage),
              ),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Log')),
          ],
        ),
      ),
    );
    if (result != true || orderIdCtrl.text.trim().isEmpty) return;
    final orderId = orderIdCtrl.text.trim();
    try {
      await OrderTrackingTable().insert({
        ...OrgScope.stamp(),
        'order_id': orderId,
        'status': stage,
        if (noteCtrl.text.trim().isNotEmpty) 'note': noteCtrl.text.trim(),
        'tracked_at': DateTime.now().toIso8601String(),
      });
      // Keeps orders.tracking_status and the public timeline
      // (order_status_history) in step with this log — same helper every
      // other status-changing call site in the app already uses.
      await TrackingService.setStatus(
        orderId: orderId,
        trackingStatus: orderStageLabel(stage),
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      );
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not log: $e')));
      }
    }
  }

  Future<void> _newComplaint() async {
    final orderIdCtrl = TextEditingController();
    final typeCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New Complaint'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: orderIdCtrl,
              decoration: const InputDecoration(labelText: 'Order ID'),
              autofocus: true),
          TextField(
              controller: typeCtrl,
              decoration: const InputDecoration(labelText: 'Type')),
          TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Log Complaint')),
        ],
      ),
    );
    if (result != true) return;
    try {
      await ComplaintsTable().insert({
        ...OrgScope.stamp(),
        if (orderIdCtrl.text.trim().isNotEmpty) 'order_id': orderIdCtrl.text.trim(),
        if (typeCtrl.text.trim().isNotEmpty) 'type': typeCtrl.text.trim(),
        'description': descCtrl.text.trim(),
        'status': 'open',
        'reported_at': DateTime.now().toIso8601String(),
      });
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not log: $e')));
      }
    }
  }

  Future<void> _resolveComplaint(ComplaintsRow c) async {
    if (c.id == null) return;
    final resolutionCtrl = TextEditingController(text: c.resolution ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Resolve Complaint'),
        content: TextField(
          controller: resolutionCtrl,
          decoration: const InputDecoration(labelText: 'Resolution'),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Mark Resolved')),
        ],
      ),
    );
    if (result != true) return;
    try {
      await ComplaintsTable().update(
        data: {
          'status': 'resolved',
          'resolution': resolutionCtrl.text.trim().isEmpty
              ? null
              : resolutionCtrl.text.trim(),
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', c.id!),
      );
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    }
  }

  List<String> get _complaintStatuses =>
      _complaints.map((c) => c.status).toSet().toList()..sort();

  List<ComplaintsRow> get _filteredComplaints => _complaintStatusFilter == null
      ? _complaints
      : _complaints.where((c) => c.status == _complaintStatusFilter).toList();

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final onTracking = _tabs.index == 0;
    Widget tabButton(int i, String label) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _tabs.animateTo(i)),
            child: Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _tabs.index == i ? c.sel : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(label,
                  style: NgFonts.geist(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: _tabs.index == i ? c.text : c.mute)),
            ),
          ),
        );
    return Scaffold(
      backgroundColor: c.bg,
      appBar: NgTopBar(onRefresh: _load),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              children: [
                const NgModuleHeader('Ops log'),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                            color: c.s1,
                            borderRadius: BorderRadius.circular(14)),
                        child: Row(children: [
                          tabButton(0, 'Tracking'),
                          tabButton(1, 'Complaints'),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    NgPrimaryButton(
                      compact: true,
                      height: 44,
                      icon: Icons.add_rounded,
                      label: onTracking ? 'Log update' : 'New complaint',
                      onPressed: () => onTracking
                          ? _logTrackingUpdate()
                          : _newComplaint(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(controller: _tabs, children: [
                    _trackingTab(),
                    _complaintsTab(),
                  ]),
          ),
        ],
      ),
    );
  }

  Color _stageDot(String status) {
    final c = NgPalette.of(context);
    final st = canonicalOrderStage(status);
    if (st == null) return c.faint;
    final i = kOrderStages.indexOf(st);
    return c.status(orderStageTone(i < 0 ? 0 : i)).fg;
  }

  Widget _trackingTab() {
    final c = NgPalette.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (_tracking.isEmpty)
            NgCard(
              child: Text('No tracking entries yet.',
                  textAlign: TextAlign.center,
                  style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
            )
          else
            NgCardList(children: [
              for (final t in _tracking)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                              color: _stageDot(t.status),
                              shape: BoxShape.circle),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${t.orderId ?? '—'} · ${orderStageLabel(canonicalOrderStage(t.status) ?? t.status)}',
                                style: NgFonts.geist(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: c.text)),
                            const SizedBox(height: 2),
                            Text(
                                [
                                  if (t.trackedAt != null)
                                    DateFormat('d MMM, h:mm a')
                                        .format(t.trackedAt!.toLocal()),
                                  if ((t.note ?? '').isNotEmpty) t.note,
                                ].whereType<String>().join(' · '),
                                style: NgFonts.geist(
                                    fontSize: 12.5,
                                    height: 1.35,
                                    color: c.mute)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ]),
        ],
      ),
    );
  }

  Widget _complaintsTab() {
    final c = NgPalette.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (_complaintStatuses.isNotEmpty) ...[
            NgChipRow(edge: 0, chips: [
              NgChip(
                  label: 'All',
                  selected: _complaintStatusFilter == null,
                  onTap: () => setState(() => _complaintStatusFilter = null)),
              for (final s in _complaintStatuses)
                NgChip(
                    label: s[0].toUpperCase() + s.substring(1),
                    selected: _complaintStatusFilter == s,
                    onTap: () => setState(() => _complaintStatusFilter = s)),
            ]),
            const SizedBox(height: 14),
          ],
          if (_filteredComplaints.isEmpty)
            NgCard(
              child: Text('No complaints logged.',
                  textAlign: TextAlign.center,
                  style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
            )
          else
            NgCardList(children: [
              for (final cp in _filteredComplaints)
                NgListRow(
                  icon: Icons.report_problem_outlined,
                  iconStatus: cp.status == 'resolved' || cp.status == 'closed'
                      ? NgStatus.green
                      : NgStatus.amber,
                  title: cp.type?.isNotEmpty == true ? cp.type! : 'Complaint',
                  subtitle: [
                    if ((cp.description ?? '').isNotEmpty) cp.description!,
                    [
                      if (cp.orderId != null) cp.orderId!,
                      cp.status,
                    ].join(' · '),
                  ].join('\n'),
                  trailing: cp.status != 'resolved' && cp.status != 'closed'
                      ? NgSecondaryButton(
                          height: 34,
                          label: 'Resolve',
                          onPressed: () => _resolveComplaint(cp),
                        )
                      : null,
                ),
            ]),
        ],
      ),
    );
  }
}
