import '/backend/soft_delete.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/delete_action.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import '/components/keyboard_scroll_view.dart';
import '/components/load_error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
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
  /// 30 days, nothing otherwise. Shown on each vehicle card so renewals
  /// can't sneak up (Arun's fleet-reminder request; push reminders for
  /// these ride on the Week-3 FCM work).
  Widget _expiryBadge(String label, DateTime? date) {
    if (date == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final days = date.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days > 30) return const SizedBox.shrink();
    final expired = days < 0;
    final color = expired ? const Color(0xFFC62828) : const Color(0xFFE6A400);
    final text =
        expired ? '$label expired ${-days}d ago' : '$label expires in ${days}d';
    return Container(
      margin: const EdgeInsets.only(top: 6, right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.inter(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  /// Corrections session, B3 (7 Aug 2026): was a bare hardcoded stat
  /// value/label pair — see the class doc comment for the fake-numbers
  /// history this replaces.
  Widget _statTile(BuildContext context, String value, String label) {
    return Flexible(
      flex: 1,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(0.0, 10.0, 0.0, 10.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                value,
                style: FlutterFlowTheme.of(context).titleMedium.override(
                      font: GoogleFonts.interTight(),
                      color: FlutterFlowTheme.of(context).primary,
                      letterSpacing: 0.0,
                    ),
              ),
              Text(
                label,
                style: FlutterFlowTheme.of(context).labelSmall.override(
                      font: GoogleFonts.inter(),
                      color: FlutterFlowTheme.of(context).secondaryText,
                      letterSpacing: 0.0,
                    ),
              ),
            ].divide(const SizedBox(height: 2.0)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Corrections session, B3: computed from the same status vocabulary
    // vehicle_detail_sheet.dart's edit form actually writes
    // (_statuses = ['active', 'maintenance', 'inactive']) — NOT the
    // "Active/Idle/Service" labels the old hardcoded cards used, which
    // don't match any status this app's own UI can set (grepped: the only
    // place vehicles.status is written is that form). One live row still
    // holds 'idle' from data that predates the current vocabulary; it
    // shows up in none of these three counts rather than being force-fit
    // into one, since counting it as "Active" or "Maintenance" would be a
    // guess this app's own code doesn't support.
    final vehicles = _model.vehiclesList;
    final activeCount = vehicles.where((v) => v.status == 'active').length;
    final maintenanceCount =
        vehicles.where((v) => v.status == 'maintenance').length;
    final inactiveCount = vehicles.where((v) => v.status == 'inactive').length;
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          automaticallyImplyLeading: true,
          title: Text(
            AppLocalizations.of(context).fleet,
            style: FlutterFlowTheme.of(context).titleLarge.override(
                  font: GoogleFonts.interTight(
                    fontWeight: FontWeight.w600,
                    fontStyle:
                        FlutterFlowTheme.of(context).titleLarge.fontStyle,
                  ),
                  fontSize: 22.0,
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.w600,
                  fontStyle: FlutterFlowTheme.of(context).titleLarge.fontStyle,
                ),
          ),
          actions: const [],
          centerTitle: true,
          elevation: 0.0,
        ),
        // Parity brief Part 2c: there was previously no way to add a
        // vehicle at all.
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            final saved = await VehicleDetailSheet.show(context);
            if (saved) _loadVehicles();
          },
          backgroundColor: FlutterFlowTheme.of(context).primary,
          child: const Icon(Icons.add, color: Colors.white),
        ),
        body: SafeArea(
          top: true,
          child: Container(
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).primaryBackground,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: KeyboardScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _statTile(context, '$activeCount', 'Active'),
                        _statTile(context, '$maintenanceCount', 'Maintenance'),
                        _statTile(context, '$inactiveCount', 'Inactive'),
                      ].divide(const SizedBox(width: 10.0)),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          AppLocalizations.of(context).liveFleet,
                          style:
                              FlutterFlowTheme.of(context).titleSmall.override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .titleSmall
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .titleSmall
                                          .fontStyle,
                                    ),
                                    color: FlutterFlowTheme.of(context).primary,
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .titleSmall
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .titleSmall
                                        .fontStyle,
                                  ),
                        ),
                        Builder(
                          builder: (context) {
                            if (_loadError != null &&
                                _model.vehiclesOut == null) {
                              return LoadErrorState(
                                  message: _loadError!,
                                  onRetry: _loadVehicles);
                            }
                            final vehiclesListItem =
                                _model.vehiclesList.toList();

                            return ListView.separated(
                              padding: EdgeInsets.zero,
                              primary: false,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              scrollDirection: Axis.vertical,
                              itemCount: vehiclesListItem.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12.0),
                              itemBuilder: (context, vehiclesListItemIndex) {
                                final vehiclesListItemItem =
                                    vehiclesListItem[vehiclesListItemIndex];
                                // Parity brief Part 2c: this card had no tap
                                // handler at all — there was no way to open,
                                // view, or edit a vehicle. Now opens the
                                // detail/edit sheet and reloads the list on
                                // save (Part 1's refresh-after-write pattern
                                // via VehicleDetailSheet's bool return).
                                return Material(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(12.0),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12.0),
                                    onTap: () async {
                                      final saved =
                                          await VehicleDetailSheet.show(
                                        context,
                                        existing: vehiclesListItemItem,
                                      );
                                      if (saved) _loadVehicles();
                                    },
                                    child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: FlutterFlowTheme.of(context)
                                        .secondaryBackground,
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          children: [
                                            _expiryBadge(
                                                'Insurance',
                                                vehiclesListItemItem
                                                    .insuranceExpiry),
                                            _expiryBadge(
                                                'Permit',
                                                vehiclesListItemItem
                                                    .permitExpiry),
                                          ],
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.max,
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Text(
                                              vehiclesListItemItem.regNo,
                                              style: FlutterFlowTheme.of(
                                                      context)
                                                  .titleSmall
                                                  .override(
                                                    font:
                                                        GoogleFonts.interTight(
                                                      fontWeight:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .titleSmall
                                                              .fontWeight,
                                                      fontStyle:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .titleSmall
                                                              .fontStyle,
                                                    ),
                                                    color: FlutterFlowTheme.of(
                                                            context)
                                                        .primary,
                                                    letterSpacing: 0.0,
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .titleSmall
                                                            .fontWeight,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .titleSmall
                                                            .fontStyle,
                                                  ),
                                            ),
                                            Container(
                                              decoration: BoxDecoration(
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primaryBackground,
                                                borderRadius:
                                                    BorderRadius.circular(12.0),
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsetsDirectional
                                                        .fromSTEB(
                                                        10.0, 4.0, 10.0, 4.0),
                                                child: Text(
                                                  vehiclesListItemItem.status ??
                                                      '-',
                                                  style: FlutterFlowTheme.of(
                                                          context)
                                                      .labelSmall
                                                      .override(
                                                        font: GoogleFonts.inter(
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .labelSmall
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .labelSmall
                                                                  .fontStyle,
                                                        ),
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .primaryText,
                                                        letterSpacing: 0.0,
                                                        fontWeight:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .labelSmall
                                                                .fontWeight,
                                                        fontStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .labelSmall
                                                                .fontStyle,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          vehiclesListItemItem.vehicleType ??
                                              '-',
                                          style: FlutterFlowTheme.of(context)
                                              .bodyMedium
                                              .override(
                                                font: GoogleFonts.inter(
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontStyle,
                                                ),
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primaryText,
                                                letterSpacing: 0.0,
                                                fontWeight:
                                                    FlutterFlowTheme.of(context)
                                                        .bodyMedium
                                                        .fontWeight,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .bodyMedium
                                                        .fontStyle,
                                              ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.max,
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Text(
                                              vehiclesListItemItem.driverName ??
                                                  '-',
                                              style:
                                                  FlutterFlowTheme.of(context)
                                                      .bodySmall
                                                      .override(
                                                        font: GoogleFonts.inter(
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodySmall
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodySmall
                                                                  .fontStyle,
                                                        ),
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .secondaryText,
                                                        letterSpacing: 0.0,
                                                        fontWeight:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodySmall
                                                                .fontWeight,
                                                        fontStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodySmall
                                                                .fontStyle,
                                                      ),
                                            ),
                                            IconButton(
                                              tooltip: 'Delete vehicle',
                                              visualDensity:
                                                  VisualDensity.compact,
                                              icon: Icon(
                                                  Icons.delete_outline,
                                                  size: 18,
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .error),
                                              onPressed: vehiclesListItemItem
                                                          .id ==
                                                      null
                                                  ? null
                                                  : () => _deleteVehicle(
                                                      vehiclesListItemItem),
                                            ),
                                          ],
                                        ),
                                      ].divide(const SizedBox(height: 6.0)),
                                    ),
                                  ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ].divide(const SizedBox(height: 12.0)),
                    ),
                  ].divide(const SizedBox(height: 16.0)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
