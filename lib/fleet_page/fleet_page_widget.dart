import '/backend/soft_delete.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/delete_action.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import '/components/load_error_state.dart';
import '/components/ng_top_bar.dart';
import '/components/ng_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'fleet_page_model.dart';
import 'vehicle_detail_sheet.dart';
export 'fleet_page_model.dart';

/// Fleet vehicle management.
class FleetPageWidget extends StatefulWidget {
  const FleetPageWidget({super.key});

  static String routeName = 'FleetPage';
  static String routePath = '/fleet';

  @override
  State<FleetPageWidget> createState() => _FleetPageWidgetState();
}

class _FleetPageWidgetState extends State<FleetPageWidget>
    with RefreshOnPopMixin<FleetPageWidget> {
  late FleetPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => FleetPageModel());

    // On page load action.
    SchedulerBinding.instance.addPostFrameCallback((_) => _loadVehicles());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  // Refresh-after-write fix (parity brief Part 1): re-run when a pushed
  // route (vehicle detail/edit sheet) is popped back to this list.
  @override
  void onPageRefresh() => _loadVehicles();

  Future<void> _loadVehicles() async {
    // Phase 1 multi-tenancy pass — see supabase/phase1_add_org_id.sql.
    // Hang follow-up (7 Aug 2026): was unguarded — a failure here used to
    // leave the page permanently blank (no "Loading…" text even existed
    // for this list) with no way to tell it apart from a freeze. See
    // table.dart's new query timeout for the other half of this fix.
    try {
      _model.vehiclesOut = await VehiclesTable().queryRows(
        queryFn: (q) => OrgScope.read(q),
      );
      _model.vehiclesList =
          (_model.vehiclesOut ?? []).toList().cast<VehiclesRow>();
      _loadError = null;
    } catch (e) {
      _loadError = 'Could not load vehicles: $e';
    }
    safeSetState(() {});
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  // Item 11 sweep (16 Aug 2026): vehicles had soft-delete columns and a
  // working recycle-bin entry but no delete UI anywhere to reach it from.
  Future<void> _deleteVehicle(VehiclesRow v) async {
    final deleted = await DeleteAction.run(
      context,
      table: 'vehicles',
      id: v.id!,
      entityLabel: 'vehicle',
      check: () async => DeleteCheck.allow,
      onDeleted: _loadVehicles,
    );
    if (deleted) await _loadVehicles();
  }

  /// Insurance/permit expiry chip: red when expired, amber when due within
  /// 30 days, nothing otherwise. Shown on each vehicle so renewals can't
  /// sneak up (Arun's fleet-reminder request).
  Widget? _expiryBadge(String label, DateTime? date) {
    if (date == null) return null;
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    final now = DateTime.now();
    final days = date.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days > 30) return null;
    final expired = days < 0;
    final s = c.status(expired ? NgStatus.red : NgStatus.amber);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: s.fg),
          const SizedBox(width: 4),
          Text(
            expired
                ? l.ngFleetExpired(label, -days)
                : l.ngFleetExpires(label, days),
            style: NgFonts.geist(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: s.fg),
          ),
        ],
      ),
    );
  }

  ({String label, NgStatus tone}) _statusLook(String? st) {
    final l = AppLocalizations.of(context);
    switch ((st ?? '').toLowerCase()) {
      case 'active':
        return (label: l.ngFleetActive, tone: NgStatus.green);
      case 'maintenance':
      case 'service':
        return (label: l.ngFleetMaintenance, tone: NgStatus.amber);
      case 'inactive':
        return (label: l.ngFleetInactive, tone: NgStatus.neutral);
      default:
        return (
          label: (st ?? '').isEmpty ? '—' : st!,
          tone: NgStatus.neutral
        );
    }
  }

  Widget _tile(String value, String label) {
    final c = NgPalette.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: NgFonts.mono(
                    fontSize: 19, fontWeight: FontWeight.w600, color: c.acc)),
            const SizedBox(height: 3),
            Text(label, style: NgFonts.geist(fontSize: 12, color: c.mute)),
          ],
        ),
      ),
    );
  }

  Future<void> _openVehicle([VehiclesRow? v]) async {
    final saved = await VehicleDetailSheet.show(context, existing: v);
    if (saved) _loadVehicles();
  }

  @override
  Widget build(BuildContext context) {
    final c = NgPalette.of(context);
    final l = AppLocalizations.of(context);
    // Counted from the status vocabulary vehicle_detail_sheet.dart's form
    // actually writes (active / maintenance / inactive). A legacy value
    // outside it shows in none of the three rather than being force-fit.
    final vehicles = _model.vehiclesList;
    int count(String st) => vehicles.where((v) => v.status == st).length;
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: c.bg,
      appBar: NgTopBar(onRefresh: _loadVehicles),
      body: RefreshIndicator(
        onRefresh: _loadVehicles,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            NgModuleHeader(
              l.fleet,
              actions: [
                NgPrimaryButton(
                  compact: true,
                  height: 40,
                  icon: Icons.add_rounded,
                  label: l.ngFleetNew,
                  onPressed: () => _openVehicle(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loadError != null)
              LoadErrorState(message: _loadError!, onRetry: _loadVehicles)
            else ...[
              Row(
                children: [
                  _tile('${count('active')}', l.ngFleetActive),
                  const SizedBox(width: 8),
                  _tile('${count('maintenance')}', l.ngFleetMaintenance),
                  const SizedBox(width: 8),
                  _tile('${count('inactive')}', l.ngFleetInactive),
                ],
              ),
              const SizedBox(height: 14),
              if (vehicles.isEmpty)
                NgCard(
                  child: Text(l.ngFleetNone,
                      textAlign: TextAlign.center,
                      style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
                )
              else
                NgCardList(children: [
                  for (final v in vehicles)
                    InkWell(
                      onTap: () => _openVehicle(v),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Builder(builder: (context) {
                                    final badges = [
                                      _expiryBadge(
                                          l.ngFleetInsurance, v.insuranceExpiry),
                                      _expiryBadge(
                                          l.ngFleetPermit, v.permitExpiry),
                                    ].whereType<Widget>().toList();
                                    if (badges.isEmpty) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 5),
                                      child: Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: badges),
                                    );
                                  }),
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(v.regNo,
                                            style: NgFonts.mono(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: c.acc)),
                                      ),
                                      const SizedBox(width: 8),
                                      Builder(builder: (context) {
                                        final s = _statusLook(v.status);
                                        return NgPill(s.label, status: s.tone);
                                      }),
                                    ],
                                  ),
                                  if ((v.vehicleType ?? '').isNotEmpty) ...[
                                    const SizedBox(height: 5),
                                    Text(v.vehicleType!,
                                        style: NgFonts.geist(
                                            fontSize: 13.5, color: c.text)),
                                  ],
                                  const SizedBox(height: 5),
                                  Row(
                                    children: [
                                      Icon(Icons.person_outline_rounded,
                                          size: 15, color: c.mute),
                                      const SizedBox(width: 4),
                                      Text(
                                          (v.driverName ?? v.driver ?? '')
                                                  .trim()
                                                  .isEmpty
                                              ? '—'
                                              : (v.driverName ?? v.driver)!,
                                          style: NgFonts.geist(
                                              fontSize: 12.5, color: c.mute)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: l.ngFleetDelete,
                              icon: Icon(Icons.delete_outline_rounded,
                                  size: 19, color: c.faint),
                              onPressed: () => _deleteVehicle(v),
                            ),
                          ],
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
}
