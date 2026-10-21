import 'package:flutter/material.dart';

import '/backend/soft_delete.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/delete_action.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import '/l10n/gen/app_localizations.dart';
import '/flutter_flow/ng_tokens.dart';
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

  static const _kStatusOrder = ['planned', 'ongoing', 'completed', 'cancelled'];

  String _statusLabel(String st) {
    final l = AppLocalizations.of(context);
    return switch (st) {
      'planned' => l.ngTripPlanned,
      'ongoing' => l.ngTripOngoing,
      'completed' => l.ngTabCompleted,
      'cancelled' => l.ngTabCancelled,
      _ => st,
    };
  }

  NgStatus _statusTone(String st) => switch (st) {
        'planned' => NgStatus.blue,
        'ongoing' => NgStatus.amber,
        'completed' => NgStatus.green,
        'cancelled' => NgStatus.red,
        _ => NgStatus.neutral,
      };

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final statuses = [
      ..._kStatusOrder.where(_statuses.contains),
      ..._statuses.where((s) => !_kStatusOrder.contains(s)),
    ];
    return Scaffold(
      backgroundColor: c.bg,
      appBar: NgTopBar(onRefresh: _load),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  NgModuleHeader(
                    l.ngMenuTrips,
                    actions: [
                      NgPrimaryButton(
                        compact: true,
                        height: 40,
                        icon: Icons.add_rounded,
                        label: l.ngOpsNewTrip,
                        onPressed: _newTrip,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  NgChipRow(
                    edge: 0,
                    chips: [
                      NgChip(
                        label: l.ngTabAll,
                        count: _all.length,
                        selected: _statusFilter == null,
                        onTap: () => setState(() => _statusFilter = null),
                      ),
                      for (final st in statuses)
                        NgChip(
                          label: _statusLabel(st),
                          count: _all.where((t) => t.status == st).length,
                          selected: _statusFilter == st,
                          onTap: () => setState(() => _statusFilter = st),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_filtered.isEmpty)
                    NgCard(
                      child: Text(l.ngTripNone,
                          textAlign: TextAlign.center,
                          style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
                    )
                  else
                    NgCardList(children: [
                      for (final t in _filtered) _tripRow(t),
                    ]),
                ],
              ),
            ),
    );
  }

  // Item 11 sweep (17 Aug 2026): trips had a live column but no delete
  // UI. Guarded — a deleted trip must not silently change P&L for a
  // completed order or an already-costed job (see canDeleteTrip).
  Future<void> _deleteTrip(TripsRow t) async {
    if (t.id == null) return;
    final deleted = await DeleteAction.run(
      context,
      table: 'trips',
      id: t.id!,
      entityLabel: 'trip',
      check: () => SoftDeleteService.canDeleteTrip(t),
      onDeleted: _load,
    );
    if (deleted) await _load();
  }

  Widget _tripRow(TripsRow t) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    return NgListRow(
      onTap: () => context.pushNamed(
        TripDetailPageWidget.routeName,
        queryParameters: {'tripId': serializeParam(t.id, ParamType.String)},
      ),
      title: t.tripNo ?? l.ngTripNoNumber,
      titleTrailing:
          NgPill(_statusLabel(t.status), status: _statusTone(t.status)),
      subtitle: [
        [
          if ((t.vehicleNo ?? '').isNotEmpty) t.vehicleNo!,
          '${t.fromLoc ?? '—'} → ${t.toLoc ?? '—'}',
        ].join(' · '),
        [
          if (t.startDate != null) DateFormat('d MMM').format(t.startDate!),
          t.isHired ? l.ngTripHired : l.ngTripOwn,
        ].join(' · '),
      ].join('\n'),
      trailing: IconButton(
        tooltip: l.ngTripDelete,
        icon: Icon(Icons.delete_outline_rounded, size: 19, color: c.faint),
        onPressed: () => _deleteTrip(t),
      ),
    );
  }
}
