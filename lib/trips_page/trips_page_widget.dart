import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'trip_detail_page_widget.dart';

/// Trips (Session 4, Part C-9) — a vehicle trip that may carry multiple
/// orders (part-load), distinct from vehicle_trips (1:1 odometer capture
/// on a single order, see CLAUDE.md). Live schema confirmed directly
/// against the DB: trips + trip_orders + trip_expenses + trip_pnl_view.
class TripsPageWidget extends StatefulWidget {
  const TripsPageWidget({super.key});

  static String routeName = 'TripsPage';
  static String routePath = '/trips';

  @override
  State<TripsPageWidget> createState() => _TripsPageWidgetState();
}

class _TripsPageWidgetState extends State<TripsPageWidget>
    with RefreshOnPopMixin<TripsPageWidget> {
  bool _loading = true;
  List<TripsRow> _all = [];
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onPageRefresh() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _all = await TripsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('start_date', ascending: false),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load trips: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _statuses => _all.map((t) => t.status).toSet().toList()..sort();

  List<TripsRow> get _filtered =>
      _statusFilter == null ? _all : _all.where((t) => t.status == _statusFilter).toList();

  Future<void> _newTrip() async {
    final tripNoCtrl = TextEditingController();
    final vehicleNoCtrl = TextEditingController();
    final driverNameCtrl = TextEditingController();
    final driverPhoneCtrl = TextEditingController();
    final fromCtrl = TextEditingController();
    final toCtrl = TextEditingController();
    String tripType = 'own';
    DateTime startDate = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('New Trip'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: tripNoCtrl,
                      decoration: const InputDecoration(labelText: 'Trip No'),
                      autofocus: true),
                  DropdownButtonFormField<String>(
                    initialValue: tripType,
                    decoration: const InputDecoration(labelText: 'Trip Type'),
                    items: const [
                      DropdownMenuItem(value: 'own', child: Text('Own Vehicle')),
                      DropdownMenuItem(value: 'hired', child: Text('Hired Vehicle')),
                    ],
                    onChanged: (v) => setDialogState(() => tripType = v ?? 'own'),
                  ),
                  TextField(
                      controller: vehicleNoCtrl,
                      decoration: const InputDecoration(labelText: 'Vehicle No')),
                  TextField(
                      controller: driverNameCtrl,
                      decoration: const InputDecoration(labelText: 'Driver Name')),
                  TextField(
                      controller: driverPhoneCtrl,
                      decoration: const InputDecoration(labelText: 'Driver Phone'),
                      keyboardType: TextInputType.phone),
                  TextField(
                      controller: fromCtrl,
                      decoration: const InputDecoration(labelText: 'From')),
                  TextField(
                      controller: toCtrl,
                      decoration: const InputDecoration(labelText: 'To')),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Start Date'),
                    subtitle: Text(DateFormat('d MMM yyyy').format(startDate)),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: dialogCtx,
                          initialDate: startDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100));
                      if (picked != null) setDialogState(() => startDate = picked);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final inserted = await TripsTable().insert({
        ...OrgScope.stamp(),
        if (tripNoCtrl.text.trim().isNotEmpty) 'trip_no': tripNoCtrl.text.trim(),
        'trip_type': tripType,
        'is_hired': tripType == 'hired',
        if (vehicleNoCtrl.text.trim().isNotEmpty) 'vehicle_no': vehicleNoCtrl.text.trim(),
        if (driverNameCtrl.text.trim().isNotEmpty) 'driver_name': driverNameCtrl.text.trim(),
        if (driverPhoneCtrl.text.trim().isNotEmpty)
          'driver_phone': driverPhoneCtrl.text.trim(),
        if (fromCtrl.text.trim().isNotEmpty) 'from_loc': fromCtrl.text.trim(),
        if (toCtrl.text.trim().isNotEmpty) 'to_loc': toCtrl.text.trim(),
        'start_date': startDate.toIso8601String().split('T').first,
        'status': 'planned',
      });
      await _load();
      if (mounted && inserted.id != null) {
        context.pushNamed(
          TripDetailPageWidget.routeName,
          queryParameters: {'tripId': serializeParam(inserted.id, ParamType.String)},
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create trip: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        automaticallyImplyLeading: true,
        title: Text('Trips',
            style: theme.titleLarge.override(
                font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                fontSize: 22,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newTrip,
        icon: const Icon(Icons.add),
        label: const Text('New Trip'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                children: [
                  if (_statuses.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                            label: const Text('All'),
                            selected: _statusFilter == null,
                            onSelected: (_) => setState(() => _statusFilter = null)),
                        for (final s in _statuses)
                          ChoiceChip(
                              label: Text(s),
                              selected: _statusFilter == s,
                              onSelected: (_) => setState(() => _statusFilter = s)),
                      ],
                    ),
                  const SizedBox(height: 10),
                  if (_filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text('No trips found.',
                          style: GoogleFonts.inter(color: theme.secondaryText)),
                    )
                  else
                    for (final t in _filtered) _tripRow(theme, t),
                ],
              ),
            ),
    );
  }

  Widget _statusChip(FlutterFlowTheme theme, String status) {
    final color = {
          'planned': Colors.blueGrey,
          'ongoing': Colors.blue,
          'completed': Colors.green,
          'cancelled': Colors.red,
        }[status] ??
        Colors.grey;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
      child: Text(status, style: GoogleFonts.inter(fontSize: 10.5, color: color, fontWeight: FontWeight.w700)),
    );
  }

  Widget _tripRow(FlutterFlowTheme theme, TripsRow t) {
    return InkWell(
      onTap: () => context.pushNamed(
        TripDetailPageWidget.routeName,
        queryParameters: {'tripId': serializeParam(t.id, ParamType.String)},
      ),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: theme.secondaryBackground, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.tripNo ?? '(no trip no)',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(
                    [
                      if ((t.vehicleNo ?? '').isNotEmpty) t.vehicleNo,
                      '${t.fromLoc ?? '—'} → ${t.toLoc ?? '—'}',
                    ].whereType<String>().join(' · '),
                    style: GoogleFonts.inter(fontSize: 11.5, color: theme.secondaryText),
                  ),
                ],
              ),
            ),
            _statusChip(theme, t.status),
          ],
        ),
      ),
    );
  }
}
