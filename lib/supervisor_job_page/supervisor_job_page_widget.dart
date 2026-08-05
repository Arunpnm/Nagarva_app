import '/app_session.dart';
import '/backend/audit_log_service.dart';
import '/backend/crew_sync_service.dart';
import '/backend/tracking_service.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/supervisor_menu_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'supervisor_job_page_model.dart';
export 'supervisor_job_page_model.dart';

/// Expanded from 6 to 16 per Arun's master-brief §6.3 list (unavailable in
/// this session when the field job screen was first rebuilt, so 6 more
/// weren't invented to match a document not in hand — flagged then, filled
/// in now). The original 6 are kept as-is per instruction; 'Food' and
/// 'Packing Material' already covered two of the 12 he sent, so only the
/// other 10 were appended.
const List<String> kJobExpenseCategories = [
  'Fuel',
  'Toll',
  'Loading/Unloading',
  'Packing Material',
  'Food',
  'Miscellaneous',
  '🚚 Extra vehicle',
  '❄️ AC install/uninstall',
  '📺 TV install/uninstall',
  '🚿 Geyser install/uninstall',
  '🔨 Carpenter',
  '🪜 Crane/hydra',
  '🅿️ Parking',
  '🔧 Vehicle repair',
  '🧹 Cleaning',
  '💵 Other',
];

/// On-site field job workflow for a single order — Session 2 rebuild.
///
/// Reached from the supervisor's My Jobs list (`sup-jobs`,
/// `supervisor_jobs_page_widget.dart`), which is the actual `sup-jobs` nav
/// destination; this page is opened per-order from there (or from Order
/// Details' "Open Field Job").
///
/// Corrections vs. the master parity brief this session's kickoff caught:
///   - The closing odometer reading lives in `vehicle_trips`
///     (`km_start`/`km_end`, keyed by `order_id`), NOT `orders` — there is
///     no `orders.start_km`.
///   - Verified completion also creates a `pod_records` row and marks
///     `attendance` for the crew — neither was in the original brief.
///
/// Security: OTP verification re-fetches `orders.job_otp` from the DB and
/// checks against that, never trusting only the in-memory value.
class SupervisorJobPageWidget extends StatefulWidget {
  const SupervisorJobPageWidget({super.key, this.orderId});

  final String? orderId;

  static String routeName = 'SupervisorJobPage';
  static String routePath = '/supervisor-job';

  @override
  State<SupervisorJobPageWidget> createState() =>
      _SupervisorJobPageWidgetState();
}

class _SupervisorJobPageWidgetState extends State<SupervisorJobPageWidget> {
  late SupervisorJobPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => SupervisorJobPageModel());

    _model.notesController ??= TextEditingController();
    _model.expenseAmountController ??= TextEditingController();
    _model.expenseNoteController ??= TextEditingController();
    _model.enteredOtpController ??= TextEditingController()
      ..addListener(() => safeSetState(() {}));
    _model.kmStartController ??= TextEditingController();
    _model.kmEndController ??= TextEditingController();
    _model.receivedByNameController ??= TextEditingController();
    _model.receivedByPhoneController ??= TextEditingController();
    _model.packagesDeliveredController ??= TextEditingController();
    _model.packagesShortController ??= TextEditingController();
    _model.damageDescriptionController ??= TextEditingController();

    SchedulerBinding.instance.addPostFrameCallback((_) => _loadData());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  Future<void> _loadData() async {
    if (widget.orderId == null) {
      _model.isLoading = false;
      _model.loadError = 'No order specified.';
      safeSetState(() {});
      return;
    }
    try {
      final results = await Future.wait([
        OrdersTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('id', widget.orderId!),
        ),
        StaffTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eqOrNull('active', true),
        ),
        OrderStaffTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('order_id', widget.orderId!),
        ),
        VehicleTripsTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('order_id', widget.orderId!),
        ),
      ]);
      final orders = results[0].cast<OrdersRow>();
      if (orders.isEmpty) {
        _model.isLoading = false;
        _model.loadError = 'Order not found.';
        safeSetState(() {});
        return;
      }
      _model.order = orders.first;
      _model.staffList = results[1].cast<StaffRow>();
      // Session 2 Part A: crew now read from order_staff — the table
      // CrewSyncService keeps in sync with job_team — not job_team itself.
      _model.crew = results[2].cast<OrderStaffRow>();
      final trips = results[3].cast<VehicleTripsRow>();
      _model.vehicleTrip = trips.isNotEmpty ? trips.first : null;
      _model.kmStartController!.text =
          _model.vehicleTrip?.kmStart?.toStringAsFixed(0) ?? '';
      _model.kmEndController!.text =
          _model.vehicleTrip?.kmEnd?.toStringAsFixed(0) ?? '';

      _model.fieldExpenses = _parseFieldExpenses(_model.order!.data['field_expenses']);

      final team = _model.order!.jobTeam;
      if (team is List) {
        _model.selectedTeamIds = team.map((e) => e.toString()).toSet();
      }
      _model.notesController!.text = _model.order!.supervisorNotes ?? '';
      _model.step = _inferStep(_model.order!);
      _model.isLoading = false;
      _model.loadError = null;
    } catch (e) {
      _model.isLoading = false;
      _model.loadError = e.toString();
    }
    safeSetState(() {});
  }

  List<Map<String, dynamic>> _parseFieldExpenses(dynamic raw) {
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  SupervisorJobStep _inferStep(OrdersRow o) {
    if (o.status == 'delivered' ||
        o.status == 'closed' ||
        o.supervisorStatus == 'completed_pending' ||
        o.supervisorStatus == 'approved') {
      return SupervisorJobStep.done;
    }
    if (o.status == 'transit') return SupervisorJobStep.shifting;
    if (o.supervisorStatus == 'in_progress') return SupervisorJobStep.team;
    return SupervisorJobStep.start;
  }

  /// Mirrors the reference app's central `changeOrderStatus` helper: writes
  /// orders.status and logs the change. `TrackingService.logStatus` is what
  /// writes `order_status_history` (Session 2 B5 step 5) — already existed,
  /// nothing new needed there.
  Future<void> _changeStatus(String newStatus, String note) async {
    await OrdersTable().update(
      data: {'status': newStatus},
      matchingRows: (q) => OrgScope.write(q).eq('id', widget.orderId!),
    );
    await OrderTrackingTable().insert({
      ...OrgScope.stamp(),
      'order_id': widget.orderId,
      'status': newStatus,
      'note': note,
      'tracked_by': AppSession.instance.currentStaffName ?? 'Supervisor',
    });
    await TrackingService.logStatus(
      orderId: widget.orderId!,
      status: newStatus,
      note: note,
    );
  }

  Future<void> _startJob() async {
    setState(() => _model.saving = true);
    try {
      await OrdersTable().update(
        data: {'supervisor_status': 'in_progress'},
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.orderId!),
      );
      _model.order!.supervisorStatus = 'in_progress';
      _model.step = SupervisorJobStep.team;
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _model.saving = false);
    }
  }

  Future<void> _startShifting() async {
    if (_model.selectedTeamIds.isEmpty) {
      _showError('Select at least one team member first.');
      return;
    }
    setState(() => _model.saving = true);
    try {
      final teamIds = _model.selectedTeamIds.toList();
      await OrdersTable().update(
        data: {
          'job_team': teamIds,
          'job_start_time': DateTime.now().toIso8601String(),
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.orderId!),
      );
      // Session 2, Part A: propagate to order_staff on every job_team
      // write — the fix for the P&L Staff Salary under-report.
      await CrewSyncService.syncFromJobTeam(
          orderId: widget.orderId!, teamIds: teamIds);
      await _changeStatus('transit', '📦 Shifting started — team assigned');
      _model.order!.status = 'transit';
      // Refresh crew from order_staff now that the sync has run.
      final crewRows = await OrderStaffTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('order_id', widget.orderId!),
      );
      _model.crew = crewRows;
      _model.step = SupervisorJobStep.shifting;
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _model.saving = false);
    }
  }

  /// Session 2 B2 correction: field expenses append to
  /// `orders.field_expenses` (migration 007 shape) instead of the
  /// `expenses` table the previous build of this page used.
  Future<void> _addFieldExpense() async {
    final amount = double.tryParse(_model.expenseAmountController!.text);
    if (amount == null || amount <= 0) {
      _showError('Enter a valid expense amount.');
      return;
    }
    setState(() => _model.saving = true);
    try {
      final entry = {
        'type': _model.expenseType,
        'amount': amount,
        'note': _model.expenseNoteController!.text.trim(),
        'at': DateTime.now().toIso8601String().split('T').first,
      };
      final updated = [..._model.fieldExpenses, entry];
      await OrdersTable().update(
        data: {'field_expenses': updated},
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.orderId!),
      );
      _model.fieldExpenses = updated;
      _model.expenseAmountController!.clear();
      _model.expenseNoteController!.clear();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _model.saving = false);
    }
  }

  /// Session 2 B3: reads/writes `vehicle_trips`, not `orders`. Creates the
  /// row on first save (with whichever of km_start/km_end was entered);
  /// updates it on subsequent saves.
  Future<void> _saveOdometer() async {
    final kmStart = double.tryParse(_model.kmStartController!.text.trim());
    final kmEnd = double.tryParse(_model.kmEndController!.text.trim());
    if (kmStart == null && kmEnd == null) return;
    setState(() => _model.saving = true);
    try {
      final orgId = OrgScope.currentOrgId!;
      final existing = _model.vehicleTrip;
      final data = {
        if (kmStart != null) 'km_start': kmStart,
        if (kmEnd != null) 'km_end': kmEnd,
      };
      if (existing?.id != null) {
        await SupaFlow.client
            .from('vehicle_trips')
            .update(data)
            .eq('id', existing!.id!);
      } else {
        final o = _model.order!;
        final inserted = await SupaFlow.client
            .from('vehicle_trips')
            .insert({
              ...OrgScope.stamp(orgId: orgId),
              'order_id': widget.orderId,
              'vehicle_no': o.vehicleNo,
              'driver_name': o.driverName,
              'trip_date': DateTime.now().toIso8601String().split('T').first,
              'trip_type': 'order',
              ...data,
            })
            .select()
            .single();
        _model.vehicleTrip = VehicleTripsTable().createRow(inserted);
      }
      // Re-read so kmStart/kmEnd reflect exactly what's persisted.
      final rows = await VehicleTripsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('order_id', widget.orderId!),
      );
      if (rows.isNotEmpty) _model.vehicleTrip = rows.first;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Odometer saved.')));
      }
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _model.saving = false);
    }
  }

  /// B3's gate: disabled while an opening reading exists but no closing
  /// one does. Never blocks when no opening reading was ever captured —
  /// the vehicle may be third-party.
  bool get _shiftingCompletionBlocked {
    final trip = _model.vehicleTrip;
    if (trip == null) return false;
    return trip.kmStart != null && trip.kmEnd == null;
  }

  Future<void> _generateOtp() async {
    setState(() => _model.saving = true);
    try {
      final otp = (1000 + Random().nextInt(9000)).toString();
      await OrdersTable().update(
        data: {
          'job_otp': otp,
          'supervisor_notes': _model.notesController!.text,
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.orderId!),
      );
      _model.displayedOtp = otp;
      _model.otpError = false;
      _model.step = SupervisorJobStep.otpEntry;
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _model.saving = false);
    }
  }

  /// Session 2 B5 — the full 9-step verified-completion transaction.
  Future<void> _verifyAndComplete() async {
    setState(() => _model.saving = true);
    try {
      // Re-fetch from the DB rather than trusting only the in-memory OTP.
      final fresh = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', widget.orderId!),
      );
      final dbOtp = fresh.isNotEmpty ? fresh.first.jobOtp : null;
      if (dbOtp == null || _model.enteredOtpController!.text.trim() != dbOtp) {
        // Step: wrong OTP writes nothing at all.
        setState(() => _model.otpError = true);
        return;
      }

      final orgId = OrgScope.currentOrgId!;
      final o = _model.order!;
      final wasDelivered = o.status == 'delivered' || o.status == 'closed';
      final now = DateTime.now();

      // 1-3: supervisor_status, supervisor_notes, job_end_time.
      final teamIds = _model.selectedTeamIds.toList();
      final orderUpdate = <String, dynamic>{
        'supervisor_status': 'completed_pending',
        'supervisor_notes': _model.notesController!.text,
        'job_end_time': now.toIso8601String(),
        'job_team': teamIds,
      };
      // 4: advance to delivered + stamp delivered_at, if not already.
      if (!wasDelivered) {
        orderUpdate['status'] = 'delivered';
        orderUpdate['delivered_at'] = now.toIso8601String();
      }
      await OrdersTable().update(
        data: orderUpdate,
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.orderId!),
      );
      await CrewSyncService.syncFromJobTeam(
          orderId: widget.orderId!, teamIds: teamIds);

      // 5: order_status_history (+ legacy order_tracking, same call site
      // as the rest of the app) — only fire the status-change side once.
      if (!wasDelivered) {
        await _changeStatus(
            'delivered', '🎉 Job completed by supervisor, OTP confirmed');
      } else {
        await TrackingService.logStatus(
          orderId: widget.orderId!,
          status: 'delivered',
          note: 'Completed by supervisor, OTP verified',
        );
      }

      // 6: pod_records. Photo capture and GPS coordinates are left null —
      // no Storage bucket is confirmed for POD photos and no location
      // package is in pubspec.yaml (this app's environment rules warn
      // against casually adding one — pinned Flutter SDK, real version
      // risk elsewhere in the app). Flagged in the session report rather
      // than guessed at.
      String? lrId;
      try {
        final lr = await SupaFlow.client
            .from('lr_register')
            .select('id')
            .eq('order_id', widget.orderId!)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        lrId = lr?['id'] as String?;
      } catch (_) {}
      final packagesDelivered =
          int.tryParse(_model.packagesDeliveredController!.text.trim()) ?? 0;
      final packagesShort =
          int.tryParse(_model.packagesShortController!.text.trim()) ?? 0;
      await SupaFlow.client.from('pod_records').insert({
        'org_id': orgId,
        'order_id': widget.orderId,
        if (lrId != null) 'lr_id': lrId,
        'otp_verified': true,
        'delivered_at': now.toIso8601String(),
        'captured_by': AppSession.instance.currentStaffName ?? 'Supervisor',
        if (_model.receivedByNameController!.text.trim().isNotEmpty)
          'received_by_name': _model.receivedByNameController!.text.trim(),
        if (_model.receivedByPhoneController!.text.trim().isNotEmpty)
          'received_by_phone': _model.receivedByPhoneController!.text.trim(),
        'relationship': _model.relationship,
        'packages_delivered': packagesDelivered,
        'packages_short': packagesShort,
        'damage_noted': _model.damageNoted,
        if (_model.damageNoted)
          'damage_description': _model.damageDescriptionController!.text.trim(),
      });

      // 7: mark attendance present for each crew member for today, if not
      // already marked.
      final today = now.toIso8601String().split('T').first;
      for (final c in _model.crew) {
        if (c.staffId == null) continue;
        try {
          final already = await SupaFlow.client
              .from('attendance')
              .select('id')
              .eq('org_id', orgId)
              .eq('staff_id', c.staffId!)
              .eq('attendance_date', today)
              .maybeSingle();
          if (already != null) continue;
          await SupaFlow.client.from('attendance').insert({
            'org_id': orgId,
            'staff_id': c.staffId,
            'attendance_date': today,
            'status': 'present',
            'marked_by': AppSession.instance.currentStaffName ?? 'Supervisor',
          });
        } catch (_) {
          // One crew member's attendance failing to write must not abort
          // the completion transaction for everyone else.
        }
      }

      // 8: audit_log.
      await AuditLogService.log(
        entityType: 'orders',
        entityId: widget.orderId!,
        action: 'supervisor_completed',
        oldValue: {'status': o.status, 'supervisor_status': o.supervisorStatus},
        newValue: {
          'status': orderUpdate['status'] ?? o.status,
          'supervisor_status': 'completed_pending',
        },
        changedFields: [
          'supervisor_status',
          'supervisor_notes',
          'job_end_time',
          'job_team',
          if (!wasDelivered) ...['status', 'delivered_at'],
        ],
      );

      _model.order!.supervisorStatus = 'completed_pending';
      _model.step = SupervisorJobStep.done;
      _model.otpError = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('🎉 Job complete! Awaiting owner approval.')));
      }
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _model.saving = false);
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            'Field Job',
            style: FlutterFlowTheme.of(context).titleLarge.override(
                  font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                  fontSize: 22.0,
                  fontWeight: FontWeight.w600,
                ),
          ),
          centerTitle: true,
          elevation: 0.0,
          actions: const [SupervisorMenuButton()],
        ),
        body: SafeArea(
          top: true,
          child: _model.isLoading
              ? const Center(child: CircularProgressIndicator())
              : _model.loadError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_model.loadError!, textAlign: TextAlign.center),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ListView(
                        children: [
                          _orderSummaryCard(context),
                          const SizedBox(height: 16),
                          _stepBody(context),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _orderSummaryCard(BuildContext context) {
    final o = _model.order!;
    final completed = o.status == 'delivered' ||
        o.status == 'closed' ||
        o.supervisorStatus == 'completed_pending' ||
        o.supervisorStatus == 'approved';
    final hideCustomer =
        completed && AppSession.instance.isSupervisorSession;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Privacy hold (post-job contact / lead-poaching prevention,
          // same rule as OrdersPage/OperationsPage) still hides the name,
          // but keeps the order id visible — device-test follow-up: a
          // supervisor with several completed jobs in a row had no way to
          // tell which one they'd tapped into once the name disappeared.
          Text(
              hideCustomer
                  ? '${o.id} · Customer (hidden)'
                  : o.customer,
              style: FlutterFlowTheme.of(context)
                  .titleMedium
                  .override(font: GoogleFonts.interTight(fontWeight: FontWeight.w600))),
          const SizedBox(height: 4),
          Text('${o.fromCity ?? ''} → ${o.toCity ?? ''}',
              style: FlutterFlowTheme.of(context).bodySmall.override(
                  font: GoogleFonts.inter(),
                  color: FlutterFlowTheme.of(context).secondaryText)),
          const SizedBox(height: 4),
          if ((o.vehicleNo ?? '').isNotEmpty || (o.driverName ?? '').isNotEmpty)
            Text(
                'Vehicle: ${o.vehicleNo ?? '—'}'
                '${(o.driverName ?? '').isEmpty ? '' : ' · ${o.driverName}'}',
                style: FlutterFlowTheme.of(context).bodySmall.override(
                    font: GoogleFonts.inter(),
                    color: FlutterFlowTheme.of(context).secondaryText)),
          const SizedBox(height: 8),
          Text('Status: ${o.status ?? '—'} · Supervisor: ${o.supervisorStatus ?? 'not started'}',
              style: FlutterFlowTheme.of(context).bodySmall.override(
                  font: GoogleFonts.inter(),
                  color: FlutterFlowTheme.of(context).secondaryText)),
        ],
      ),
    );
  }

  Widget _stepBody(BuildContext context) {
    switch (_model.step) {
      case SupervisorJobStep.start:
        return _actionCard(
          context,
          title: 'Ready to start this job?',
          body: 'Accepting will let you pick the labour team and begin shifting.',
          buttonLabel: 'Accept Job',
          onPressed: _startJob,
        );
      case SupervisorJobStep.team:
        return _teamSelectionCard(context);
      case SupervisorJobStep.shifting:
        return _shiftingCard(context);
      case SupervisorJobStep.completing:
        return _actionCard(
          context,
          title: 'Ready to complete?',
          body: 'This will generate a one-time code to confirm the job with the customer.',
          buttonLabel: 'Generate Completion Code',
          onPressed: _generateOtp,
        );
      case SupervisorJobStep.otpEntry:
        return _otpCard(context);
      case SupervisorJobStep.done:
        return _doneCard(context);
    }
  }

  Widget _actionCard(BuildContext context,
      {required String title,
      required String body,
      required String buttonLabel,
      required Future<void> Function() onPressed}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: FlutterFlowTheme.of(context).titleSmall),
          const SizedBox(height: 4),
          Text(body,
              style: FlutterFlowTheme.of(context).bodySmall.override(
                  font: GoogleFonts.inter(),
                  color: FlutterFlowTheme.of(context).secondaryText)),
          const SizedBox(height: 12),
          FFButtonWidget(
            onPressed: _model.saving ? null : onPressed,
            text: _model.saving ? 'Please wait…' : buttonLabel,
            options: FFButtonOptions(
              width: double.infinity,
              color: FlutterFlowTheme.of(context).primary,
              textStyle:
                  TextStyle(color: FlutterFlowTheme.of(context).primaryBackground),
              borderRadius: BorderRadius.circular(8.0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamSelectionCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select Labour Team', style: FlutterFlowTheme.of(context).titleSmall),
          const SizedBox(height: 8),
          if (_model.staffList.isEmpty)
            Text('No active staff found.',
                style: FlutterFlowTheme.of(context).bodySmall.override(
                    font: GoogleFonts.inter(),
                    color: FlutterFlowTheme.of(context).secondaryText))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _model.staffList.map((s) {
                final selected = _model.selectedTeamIds.contains(s.id);
                return FilterChip(
                  label: Text(s.name),
                  selected: selected,
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        _model.selectedTeamIds.add(s.id ?? '');
                      } else {
                        _model.selectedTeamIds.remove(s.id);
                      }
                    });
                  },
                  selectedColor: FlutterFlowTheme.of(context).primary,
                  labelStyle: TextStyle(
                    color: selected
                        ? FlutterFlowTheme.of(context).primaryBackground
                        : FlutterFlowTheme.of(context).primaryText,
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 12),
          FFButtonWidget(
            onPressed: _model.saving ? null : _startShifting,
            text: _model.saving ? 'Please wait…' : 'Start Shifting',
            options: FFButtonOptions(
              width: double.infinity,
              color: FlutterFlowTheme.of(context).primary,
              textStyle:
                  TextStyle(color: FlutterFlowTheme.of(context).primaryBackground),
              borderRadius: BorderRadius.circular(8.0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _crewCard(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Crew', style: theme.titleSmall),
          const SizedBox(height: 6),
          if (_model.crew.isEmpty)
            Text('No crew on record for this order yet.',
                style: theme.bodySmall.override(
                    font: GoogleFonts.inter(), color: theme.secondaryText))
          else
            ..._model.crew.map((c) {
              final s = _model.staffList
                  .where((s) => s.id == c.staffId)
                  .firstOrNull;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• ${s?.name ?? 'Staff'}',
                    style: theme.bodySmall
                        .override(font: GoogleFonts.inter())),
              );
            }),
        ],
      ),
    );
  }

  Widget _fieldExpensesCard(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final total = _model.fieldExpenses.fold<double>(
        0, (s, e) => s + (num.tryParse('${e['amount']}') ?? 0));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Field Expenses', style: theme.titleSmall),
          const SizedBox(height: 8),
          ..._model.fieldExpenses.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                          '${e['type']}${(e['note'] ?? '').toString().isEmpty ? '' : ' — ${e['note']}'}',
                          style: theme.bodySmall
                              .override(font: GoogleFonts.inter())),
                    ),
                    Text('₹${(num.tryParse('${e['amount']}') ?? 0).toStringAsFixed(0)}',
                        style: theme.bodySmall),
                  ],
                ),
              )),
          if (_model.fieldExpenses.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('Total: ₹${total.toStringAsFixed(0)}',
                  style: theme.bodyMedium.override(
                      font: GoogleFonts.inter(fontWeight: FontWeight.w600))),
            ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _model.expenseType,
            items: kJobExpenseCategories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _model.expenseType = v ?? 'Fuel'),
            decoration: const InputDecoration(labelText: 'Type'),
          ),
          TextField(
            controller: _model.expenseAmountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount (₹)'),
          ),
          TextField(
            controller: _model.expenseNoteController,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 8),
          FFButtonWidget(
            onPressed: _model.saving ? null : _addFieldExpense,
            text: 'Add Expense',
            options: FFButtonOptions(
              width: double.infinity,
              color: theme.secondaryBackground,
              textStyle: TextStyle(color: theme.primary),
              borderSide: BorderSide(color: theme.primary),
              borderRadius: BorderRadius.circular(8.0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _odometerCard(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vehicle Odometer', style: theme.titleSmall),
          const SizedBox(height: 4),
          Text('Optional — leave blank for a third-party vehicle.',
              style: theme.bodySmall.override(
                  font: GoogleFonts.inter(), color: theme.secondaryText)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _model.kmStartController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Opening KM'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _model.kmEndController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Closing KM'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FFButtonWidget(
            onPressed: _model.saving ? null : _saveOdometer,
            text: 'Save Odometer',
            options: FFButtonOptions(
              width: double.infinity,
              color: theme.secondaryBackground,
              textStyle: TextStyle(color: theme.primary),
              borderSide: BorderSide(color: theme.primary),
              borderRadius: BorderRadius.circular(8.0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shiftingCard(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _crewCard(context),
        const SizedBox(height: 16),
        _fieldExpensesCard(context),
        const SizedBox(height: 16),
        _odometerCard(context),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.secondaryBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Notes', style: theme.titleSmall),
              TextField(
                controller: _model.notesController,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'Any notes for the office…'),
              ),
              const SizedBox(height: 8),
              if (_shiftingCompletionBlocked)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '⚠ Closing KM is required before completion — an opening '
                    'reading was recorded for this vehicle.',
                    style: TextStyle(
                        color: theme.error,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              FFButtonWidget(
                onPressed: _shiftingCompletionBlocked
                    ? null
                    : () => setState(
                        () => _model.step = SupervisorJobStep.completing),
                text: '🏁 Shifting Completed — Get OTP',
                options: FFButtonOptions(
                  width: double.infinity,
                  color: theme.primary,
                  textStyle: TextStyle(color: theme.primaryBackground),
                  borderRadius: BorderRadius.circular(8.0),
                  disabledColor: theme.alternate,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _otpFieldColor(FlutterFlowTheme theme) {
    if (_model.otpError) return theme.error;
    if ((_model.enteredOtpController!.text).length == 4) return theme.success;
    return theme.alternate;
  }

  Widget _podCaptureFields(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Proof of Delivery', style: theme.titleSmall),
        const SizedBox(height: 4),
        Text('Optional, but recommended.',
            style: theme.bodySmall.override(
                font: GoogleFonts.inter(), color: theme.secondaryText)),
        const SizedBox(height: 8),
        TextField(
          controller: _model.receivedByNameController,
          decoration: const InputDecoration(labelText: 'Received by (name)'),
        ),
        TextField(
          controller: _model.receivedByPhoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Received by (phone)'),
        ),
        DropdownButtonFormField<String>(
          initialValue: _model.relationship,
          items: kRelationshipOptions
              .map((r) => DropdownMenuItem(value: r, child: Text(r)))
              .toList(),
          onChanged: (v) => setState(() => _model.relationship = v ?? 'self'),
          decoration: const InputDecoration(labelText: 'Relationship to customer'),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _model.packagesDeliveredController,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Packages delivered'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _model.packagesShortController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Packages short'),
              ),
            ),
          ],
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _model.damageNoted,
          onChanged: (v) => setState(() => _model.damageNoted = v ?? false),
          title: const Text('Damage noted'),
        ),
        if (_model.damageNoted)
          TextField(
            controller: _model.damageDescriptionController,
            decoration: const InputDecoration(labelText: 'Damage description'),
          ),
      ],
    );
  }

  Widget _otpCard(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Confirm with Customer', style: theme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Show this code to the customer and ask them to confirm the job is done, then type it back in below.',
            style: theme.bodySmall.override(
                font: GoogleFonts.inter(), color: theme.secondaryText),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              _model.displayedOtp ?? '----',
              style: GoogleFonts.robotoMono(
                fontSize: 48,
                fontWeight: FontWeight.w700,
                letterSpacing: 8.0,
                color: theme.primary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _model.enteredOtpController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: GoogleFonts.robotoMono(fontSize: 20, letterSpacing: 4),
            decoration: InputDecoration(
              labelText: 'Enter code',
              errorText: _model.otpError ? '❌ Wrong OTP. Try again.' : null,
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: _otpFieldColor(theme), width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: _otpFieldColor(theme), width: 2),
              ),
            ),
          ),
          _podCaptureFields(context),
          const SizedBox(height: 12),
          FFButtonWidget(
            onPressed: _model.saving ? null : _verifyAndComplete,
            text: _model.saving ? 'Verifying…' : 'Verify & Complete',
            options: FFButtonOptions(
              width: double.infinity,
              color: theme.primary,
              textStyle: TextStyle(color: theme.primaryBackground),
              borderRadius: BorderRadius.circular(8.0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _doneCard(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final ownerClosed = _model.order?.status == 'closed';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.secondaryBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(Icons.celebration, color: theme.primary, size: 40),
              const SizedBox(height: 8),
              Text(
                  _model.order?.supervisorStatus == 'approved'
                      ? 'Approved by the office.'
                      : '⏳ Awaiting owner approval.',
                  style: theme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Odometer and the completion code are locked now.'
                '${ownerClosed ? '' : ' Field expenses stay open until the order is closed.'}',
                textAlign: TextAlign.center,
                style: theme.bodySmall.override(
                    font: GoogleFonts.inter(), color: theme.secondaryText),
              ),
            ],
          ),
        ),
        // B6: field expenses stay editable until the owner closes the
        // order — everything else on this page (odometer, OTP) is
        // implicitly locked simply by the step machine landing here.
        if (!ownerClosed) ...[
          const SizedBox(height: 16),
          _fieldExpensesCard(context),
        ],
      ],
    );
  }
}
