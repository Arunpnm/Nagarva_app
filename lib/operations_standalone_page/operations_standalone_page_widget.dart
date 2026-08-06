import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/order_stages.dart';
import '/backend/tracking_service.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
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
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        title: Text('Operations',
            style: theme.titleLarge.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                fontSize: 22,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(controller: _tabs, tabs: const [
          Tab(text: 'Tracking'),
          Tab(text: 'Complaints'),
        ]),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () =>
            _tabs.index == 0 ? _logTrackingUpdate() : _newComplaint(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tabs, children: [
              _trackingTab(theme),
              _complaintsTab(theme),
            ]),
    );
  }

  Widget _trackingTab(FlutterFlowTheme theme) {
    if (_tracking.isEmpty) {
      return Center(
          child: Text('No tracking entries yet.',
              style: GoogleFonts.inter(color: theme.secondaryText)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _tracking.length,
        itemBuilder: (context, i) {
          final t = _tracking[i];
          return ListTile(
            title: Text('Order ${t.orderId ?? '—'} · ${orderStageLabel(canonicalOrderStage(t.status) ?? t.status)}'),
            subtitle: Text([
              if (t.trackedAt != null)
                DateFormat('d MMM yyyy, h:mm a').format(t.trackedAt!.toLocal()),
              if ((t.note ?? '').isNotEmpty) t.note,
            ].whereType<String>().join(' · ')),
          );
        },
      ),
    );
  }

  Widget _complaintsTab(FlutterFlowTheme theme) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_complaintStatuses.isNotEmpty)
            Wrap(spacing: 8, children: [
              ChoiceChip(
                  label: const Text('All'),
                  selected: _complaintStatusFilter == null,
                  onSelected: (_) => setState(() => _complaintStatusFilter = null)),
              for (final s in _complaintStatuses)
                ChoiceChip(
                    label: Text(s),
                    selected: _complaintStatusFilter == s,
                    onSelected: (_) => setState(() => _complaintStatusFilter = s)),
            ]),
          const SizedBox(height: 8),
          if (_filteredComplaints.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text('No complaints logged.',
                  style: GoogleFonts.inter(color: theme.secondaryText)),
            )
          else
            for (final c in _filteredComplaints)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: theme.secondaryBackground, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.type?.isNotEmpty == true ? c.type! : 'Complaint',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                          if ((c.description ?? '').isNotEmpty)
                            Text(c.description!, style: GoogleFonts.inter(fontSize: 12)),
                          Text(
                            [
                              if (c.orderId != null) 'Order ${c.orderId}',
                              c.status,
                            ].join(' · '),
                            style: GoogleFonts.inter(fontSize: 11, color: theme.secondaryText),
                          ),
                        ],
                      ),
                    ),
                    if (c.status != 'resolved' && c.status != 'closed')
                      TextButton(
                          onPressed: () => _resolveComplaint(c),
                          child: const Text('Resolve')),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
