import '/app_session.dart';
import '/backend/audit_log_service.dart';
import '/backend/crew_sync_service.dart';
import '/backend/tracking_service.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/signature_pad.dart';
import '/components/supervisor_menu_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/index.dart';
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
/// COMPLETION FLOW CHANGED 18 Aug 2026. The two-OTP model is gone.
///   Arrival    -> the supervisor enters `orders.arrival_code`, which the
///                 customer was given at confirmation. It is never shown
///                 on the supervisor's screen — that was the flaw in the
///                 old completion OTP, where `_generateOtp()` displayed
///                 the code and `_verifyAndComplete()` then checked what
///                 the supervisor typed back. The supervisor held both
///                 halves, so it proved nothing about the customer.
///   Completion -> the customer signs on the supervisor's phone. That
///                 signature IS the completion event and the POD, stored
///                 as base64 in `pod_records.signature_data`.
///   Escape     -> "Customer not available" with a structured reason,
///                 flagged distinctly to the owner. A flow with no
///                 escape hatch gets worked around in the field, and the
///                 worst workaround here is the supervisor signing it.
///
/// The nine completion writes are unchanged — only the gate in front of
/// them moved.
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
    _model.arrivalCodeController ??= TextEditingController();
    _model.notAvailableNoteController ??= TextEditingController();
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
    // in_progress means the job was accepted but shifting hasn't started,
    // so the arrival code hasn't been entered yet — resume there rather
    // than skipping the gate on a reopened screen.
    if (o.supervisorStatus == 'in_progress') {
      return SupervisorJobStep.arrivalCode;
    }
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
      // Arrival code first (18 Aug 2026) — accepting the job no longer
      // goes straight to team selection. The code is what evidences the
      // supervisor is actually on site with the customer.
      _model.step = SupervisorJobStep.arrivalCode;
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

  /// The status-history note. Says how the job was proven complete, so
  /// the timeline itself records the difference rather than requiring a
  /// join to pod_records.
  String _completionNote(String method) => method == kCompletionSignature
      ? '🎉 Job completed — signed by '
          '${_model.receivedByNameController!.text.trim()}'
      : '⚠️ Job completed WITHOUT signature — '
          '${kNotAvailableReasons[_model.notAvailableReason] ?? 'reason not given'}';

  /// Arrival gate (18 Aug 2026). The supervisor enters the code the
  /// customer was given at confirmation. Compared against the DB, not an
  /// in-memory copy — and unlike the old completion OTP, this value is
  /// never displayed on the supervisor's own screen, which is the whole
  /// point: it can only come from the customer.
  Future<void> _verifyArrival() async {
    setState(() => _model.saving = true);
    try {
      final fresh = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', widget.orderId!),
      );
      final code = fresh.isNotEmpty ? fresh.first.arrivalCode : null;
      final entered = _model.arrivalCodeController!.text.trim();
      if (code == null || code.isEmpty || entered != code) {
        setState(() => _model.arrivalCodeError = true);
        return;
      }
      _model.arrivalCodeError = false;
      _model.step = SupervisorJobStep.team;
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _model.saving = false);
    }
  }

  /// Session 2 B5's nine-write completion transaction, unchanged — only
  /// the GATE in front of it changed (18 Aug 2026). Where an OTP the
  /// supervisor could read off their own screen used to stand, there is
  /// now either the customer's signature or an explicit, reasoned
  /// "customer not available".
  ///
  /// [_model.signatureBase64] is already populated before this runs: the
  /// pad writes to model state the moment the customer lifts their
  /// finger. A failed write here therefore costs a retry, never a second
  /// signature from the customer.
  Future<void> _completeJob() async {
    final method = _model.completionMethod;
    if (method == null) {
      _showError('Choose how the job was completed first.');
      return;
    }
    if (method == kCompletionSignature) {
      if ((_model.signatureBase64 ?? '').isEmpty) {
        _showError('Ask the customer to sign, then tap Complete.');
        return;
      }
      // Required for a signature completion, per Arun (18 Aug 2026): a
      // signature with no name attached is weak evidence.
      if (_model.receivedByNameController!.text.trim().isEmpty) {
        _showError('Enter the name of the person who signed.');
        return;
      }
    } else if (method == kCompletionNotAvailable &&
        _model.notAvailableReason == null) {
      _showError('Select a reason why the customer could not sign.');
      return;
    }

    setState(() => _model.saving = true);
    try {
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
            'delivered', _completionNote(method));
      } else {
        await TrackingService.logStatus(
          orderId: widget.orderId!,
          status: 'delivered',
          note: _completionNote(method),
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
        // otp_verified is deliberately NOT written — it describes the
        // removed OTP flow and writing false would read as "the OTP
        // check failed". completion_method carries the truth instead.
        'completion_method': method,
        if (method == kCompletionSignature)
          'signature_data': _model.signatureBase64,
        if (method == kCompletionNotAvailable)
          'not_available_reason': _model.notAvailableReason,
        if (method == kCompletionNotAvailable &&
            _model.notAvailableNoteController!.text.trim().isNotEmpty)
          'remarks': _model.notAvailableNoteController!.text.trim(),
        'delivered_at': now.toIso8601String(),
        'captured_by': AppSession.instance.currentStaffName ?? 'Supervisor',
        if (_model.receivedByNameController!.text.trim().isNotEmpty)
          'received_by_name': _model.receivedByNameController!.text.trim(),
        if (_model.receivedByPhoneController!.text.trim().isNotEmpty)
          'received_by_phone': _model.receivedByPhoneController!.text.trim(),
        // Only written when somebody actually received the goods. The
        // picker defaults to 'self' and this used to be unconditional, so
        // an unsigned POD stored relationship='self' with a null
        // received_by_name — and printed "Relationship: self" directly
        // opposite "Received by: —". Found on APC-1002 in the 19 Aug 2026
        // emulator pass. A self-contradiction on the face of the one
        // document that settles a damage dispute months later.
        if (method == kCompletionSignature)
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

      // 9: notify the owner. Device-test finding: nothing reached the
      // owner on completion at all — the Awaiting Approval badge/queue
      // (OperationsPage) exists, but only if the owner happens to be
      // looking at it. Two tables, deliberately both:
      //   - `notification_log` (migration 006) is the multi-channel
      //     dispatch ledger — channel/status columns exist for an
      //     eventual push/WhatsApp pipeline this app doesn't have yet.
      //     `event_type: 'otp_completed'` is one of the values the
      //     migration's own comment already lists as expected.
      //   - `notifications` is what `NotificationBell` actually
      //     subscribes to (Supabase Realtime) and renders today. Writing
      //     only the ledger would satisfy the schema but not the actual
      //     complaint — nothing would reach the owner until a future push
      //     pipeline reads it; writing only the bell table would lose the
      //     audit trail the ledger exists for.
      // recipient_staff_id / staff_id both null — same convention the
      // existing new-lead trigger uses for "addressed to the owner", not
      // a specific staff row.
      // Best-effort: a failed notification must never fail the
      // completion transaction the supervisor is waiting on.
      final notifTitle = 'Job completed — ${o.id}';
      final notifBody = '${o.customer} · completed by '
          '${AppSession.instance.currentStaffName ?? 'supervisor'}';
      try {
        await SupaFlow.client.from('notification_log').insert({
          'org_id': orgId,
          'channel': 'in_app',
          'event_type': 'otp_completed',
          'title': notifTitle,
          'body': notifBody,
          'entity_type': 'orders',
          'entity_id': o.id,
          'status': 'sent',
        });
      } catch (_) {}
      try {
        await SupaFlow.client.from('notifications').insert({
          'org_id': orgId,
          'type': 'otp_completed',
          'title': notifTitle,
          'body': '$notifBody · awaiting your approval',
          'ref_order_id': o.id,
        });
      } catch (_) {}

      _model.order!.supervisorStatus = 'completed_pending';
      // Mirror the status change locally too (19 Aug 2026 emulator pass):
      // the DB was correctly set to 'delivered' by orderUpdate above, but
      // only supervisorStatus was copied back into the in-memory row, so
      // the done card kept reporting "Status: transit" after a successful
      // completion — the record was right and the screen was wrong.
      if (!wasDelivered) {
        _model.order!.status = 'delivered';
      }
      _model.step = SupervisorJobStep.done;
      _model.arrivalCodeError = false;
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
      case SupervisorJobStep.arrivalCode:
        return _arrivalCodeCard(context);
      case SupervisorJobStep.team:
        return _teamSelectionCard(context);
      case SupervisorJobStep.shifting:
        return _shiftingCard(context);
      case SupervisorJobStep.completing:
        // Closing reading lives WITH the handover, so it can only be
        // entered at the moment the job actually ends.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _closingOdometerCard(context),
            const SizedBox(height: 16),
            _completionCard(context),
          ],
        );
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
                  // Role alongside the name. Arun, 3 Sept 2026: "only
                  // labour name were visible their role is not visible
                  // so by this it might get confused selecting wrong
                  // person, if both were in same name". Two Balajis on
                  // a crew list are indistinguishable by name alone, and
                  // the wrong tick puts the wrong man on the job - which
                  // then flows into his attendance, his earnings and the
                  // job's labour cost.
                  label: Text(
                    (s.role ?? '').trim().isEmpty
                        ? s.name
                        : '${s.name} · ${s.role!.trim()}',
                  ),
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
          const SizedBox(height: 16),
          // Opening reading sits WITH the crew selection, because both
          // are things you do before the vehicle moves.
          _openingOdometerCard(context),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Crew', style: theme.titleSmall),
              // Day-close crew sheet (staff-pay brief §4/§10). The brief
              // puts day close on the supervisor, so the sheet has to be
              // reachable from the job he already has open — the crew card
              // is where he is standing when he thinks about who worked.
              TextButton.icon(
                onPressed: () => context
                    .pushNamed(
                      CrewSheetPageWidget.routeName,
                      queryParameters: {'orderId': widget.orderId ?? ''},
                    )
                    .then((_) => _loadData()),
                icon: const Icon(Icons.fact_check_outlined, size: 17),
                label: const Text('Crew sheet'),
              ),
            ],
          ),
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

  /// [editable] false once `supervisor_status == 'completed_pending'` —
  /// device-test decision change: field expenses (and the crew, which was
  /// already implicitly locked by the step machine simply not showing
  /// `_teamSelectionCard` again) used to stay editable until the OWNER
  /// closed the order. Now everything locks the moment OTP verification
  /// succeeds, not at Close Order — the owner is approving a fixed set of
  /// numbers, and they must not be able to move after the code is entered.
  Widget _fieldExpensesCard(BuildContext context, {bool editable = true}) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Field Expenses', style: theme.titleSmall),
              if (!editable)
                Icon(Icons.lock, size: 15, color: theme.secondaryText),
            ],
          ),
          const SizedBox(height: 8),
          if (_model.fieldExpenses.isEmpty && !editable)
            Text('No field expenses were logged.',
                style: theme.bodySmall.override(
                    font: GoogleFonts.inter(), color: theme.secondaryText)),
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
          if (editable) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _model.expenseType,
              items: kJobExpenseCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _model.expenseType = v ?? 'Fuel'),
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
        ],
      ),
    );
  }

  /// Opening odometer — captured WHEN THE JOB STARTS, beside the crew.
  ///
  /// Arun, 3 Sept 2026: *"while selecting labour make the opening odo km
  /// noted and while he marks order complete then only closing odo. now
  /// we have both at the same time which is not proper way to track"*.
  ///
  /// He is right, and the reason matters. Both boxes on one card meant
  /// the supervisor could fill them in together at the END of the day —
  /// at which point the opening reading is not observed, it is
  /// remembered or guessed. Every kilometre figure downstream (fuel per
  /// km, a driver's distance, what an outstation job really cost) is
  /// then built on a number nobody actually read off the dial. Splitting
  /// the two is what makes the opening reading evidence instead of a
  /// reconstruction.
  Widget _openingOdometerCard(BuildContext context) {
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
          Text('Opening Odometer', style: theme.titleSmall),
          const SizedBox(height: 4),
          Text(
              'Read it off the dial before you leave. Optional — leave '
              'blank for a third-party vehicle.',
              style: theme.bodySmall.override(
                  font: GoogleFonts.inter(), color: theme.secondaryText)),
          const SizedBox(height: 8),
          TextField(
            controller: _model.kmStartController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Opening KM'),
          ),
          const SizedBox(height: 8),
          FFButtonWidget(
            onPressed: _model.saving ? null : _saveOdometer,
            text: 'Save Opening KM',
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

  /// Closing odometer — only at completion, and only after an opening
  /// reading exists.
  ///
  /// Shows the opening figure read-only above it, so the supervisor is
  /// entering a number they can see is larger, and the distance is
  /// visible before they commit rather than discovered in a report later.
  Widget _closingOdometerCard(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final opening = double.tryParse(_model.kmStartController.text.trim());
    final closing = double.tryParse(_model.kmEndController.text.trim());
    final distance =
        (opening != null && closing != null) ? closing - opening : null;

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
          Text('Closing Odometer', style: theme.titleSmall),
          const SizedBox(height: 4),
          Text(
              opening == null
                  ? 'No opening reading was recorded for this job, so the '
                      'distance cannot be worked out. Enter the closing '
                      'reading anyway if you have it.'
                  : 'Opening was ${opening.toStringAsFixed(0)} km.',
              style: theme.bodySmall.override(
                  font: GoogleFonts.inter(), color: theme.secondaryText)),
          const SizedBox(height: 8),
          TextField(
            controller: _model.kmEndController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Closing KM'),
            onChanged: (_) => setState(() {}),
          ),
          if (distance != null) ...[
            const SizedBox(height: 8),
            Text(
              distance < 0
                  // Flagged, not blocked: a genuine reason exists (the
                  // dial was misread, or the vehicle was swapped), and
                  // refusing to save would lose the reading entirely.
                  ? 'Closing is lower than opening — check the reading.'
                  : 'Distance this job: ${distance.toStringAsFixed(0)} km',
              style: theme.bodySmall.override(
                  font: GoogleFonts.inter(),
                  color: distance < 0 ? theme.error : theme.primary),
            ),
          ],
          const SizedBox(height: 8),
          FFButtonWidget(
            onPressed: _model.saving ? null : _saveOdometer,
            text: 'Save Closing KM',
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
        // No odometer here on purpose. Opening was taken at the crew
        // step; closing belongs on the completion card, so the two
        // cannot be typed together at the end of the day.

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
                // Was "🏁 Shifting Completed — Get OTP" until the 19 Aug
                // 2026 emulator pass caught it: the completion OTP was
                // removed the day before, but this label on the SHIFTING
                // step still promised one. It now leads to the handover
                // card (signature or "customer not available").
                text: '🏁 Shifting Completed — Handover',
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

  /// Proof-of-delivery detail. Shared by both completion paths.
  ///
  /// Name and relationship stopped being optional for a signature
  /// completion on 18 Aug 2026 (Arun): "a signature with no name
  /// attached is weak evidence." Enforced in [_completeJob] rather than
  /// by the field itself, because they remain genuinely optional on the
  /// not-available path.
  Widget _podCaptureFields(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final needsName = (_model.completionMethod ?? kCompletionSignature) ==
        kCompletionSignature;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Proof of Delivery', style: theme.titleSmall),
        const SizedBox(height: 4),
        Text(
            needsName
                ? 'Name and relationship are required when the customer signs.'
                : 'Optional, but recommended.',
            style: theme.bodySmall.override(
                font: GoogleFonts.inter(), color: theme.secondaryText)),
        const SizedBox(height: 8),
        TextField(
          controller: _model.receivedByNameController,
          decoration: InputDecoration(
              labelText:
                  needsName ? 'Received by (name) *' : 'Received by (name)'),
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
          decoration:
              const InputDecoration(labelText: 'Relationship to customer'),
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

  final GlobalKey<SignaturePadState> _sigKey = GlobalKey<SignaturePadState>();

  /// Arrival gate. Deliberately does NOT display the expected code —
  /// that was the flaw in the old completion OTP, where the supervisor's
  /// own screen showed them the answer before they typed it back.
  Widget _arrivalCodeCard(BuildContext context) {
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
          Text('Confirm you have arrived',
              style: GoogleFonts.interTight(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: theme.primaryText)),
          const SizedBox(height: 6),
          Text(
            'Ask the customer for the 4-digit arrival code from their '
            'booking confirmation.',
            style: GoogleFonts.inter(
                fontSize: 12.5, height: 1.4, color: theme.secondaryText),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _model.arrivalCodeController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            style: GoogleFonts.robotoMono(
                fontSize: 32, letterSpacing: 10, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) {
              if (_model.arrivalCodeError) {
                setState(() => _model.arrivalCodeError = false);
              }
            },
            decoration: InputDecoration(
              counterText: '',
              hintText: '----',
              errorText: _model.arrivalCodeError
                  ? 'That code does not match. Check with the customer.'
                  : null,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: _model.saving ? null : _verifyArrival,
              icon: const Icon(Icons.login, size: 18),
              label: const Text('Confirm arrival'),
            ),
          ),
        ],
      ),
    );
  }

  /// Completion. Two paths, both explicit: the customer signs, or the
  /// supervisor records why they could not. There is no third path that
  /// silently closes the job, and no code the supervisor could enter
  /// from the office.
  Widget _completionCard(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final method = _model.completionMethod ?? kCompletionSignature;
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
          Text('Handover',
              style: GoogleFonts.interTight(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: theme.primaryText)),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: kCompletionSignature,
                  icon: Icon(Icons.draw, size: 16),
                  label: Text('Customer signs')),
              ButtonSegment(
                  value: kCompletionNotAvailable,
                  icon: Icon(Icons.person_off_outlined, size: 16),
                  label: Text('Not available')),
            ],
            selected: {method},
            onSelectionChanged: (s) =>
                setState(() => _model.completionMethod = s.first),
          ),
          const SizedBox(height: 14),
          if (method == kCompletionSignature) ...[
            Text('Ask the customer to sign below',
                style: GoogleFonts.inter(
                    fontSize: 12.5, color: theme.secondaryText)),
            const SizedBox(height: 8),
            SignaturePad(
              key: _sigKey,
              // Captured to model state the instant the customer lifts
              // their finger — BEFORE any network call. A failed write
              // must never mean asking them to sign again.
              onChanged: (_) async {
                final png = await _sigKey.currentState?.toPngBase64();
                if (png != null && mounted) {
                  setState(() {
                    _model.signatureBase64 = png;
                    _model.completionMethod = kCompletionSignature;
                  });
                }
              },
            ),
            Row(
              children: [
                if ((_model.signatureBase64 ?? '').isNotEmpty)
                  Row(children: [
                    Icon(Icons.check_circle, size: 15, color: theme.success),
                    const SizedBox(width: 4),
                    Text('Signature captured',
                        style: GoogleFonts.inter(
                            fontSize: 11.5, color: theme.success)),
                  ]),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _sigKey.currentState?.clear();
                    _model.signatureBase64 = null;
                  }),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ] else ...[
            Text('Why could the customer not sign?',
                style: GoogleFonts.inter(
                    fontSize: 12.5, color: theme.secondaryText)),
            const SizedBox(height: 8),
            for (final e in kNotAvailableReasons.entries)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: e.key,
                groupValue: _model.notAvailableReason,
                title: Text(e.value, style: GoogleFonts.inter(fontSize: 13)),
                onChanged: (v) =>
                    setState(() => _model.notAvailableReason = v),
              ),
            const SizedBox(height: 6),
            TextField(
              controller: _model.notAvailableNoteController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Add detail (optional)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade800.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'The owner will see this job as completed without a '
                'signature, and why.',
                style: GoogleFonts.inter(
                    fontSize: 11.5, height: 1.35, color: theme.primaryText),
              ),
            ),
          ],
          const SizedBox(height: 14),
          _podCaptureFields(context),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _model.saving ? null : _completeJob,
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Complete job'),
            ),
          ),
        ],
      ),
    );
  }


  Widget _doneCard(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
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
              // Device-test decision change: everything locks at OTP
              // success now, not at Close Order — the owner is approving a
              // fixed set of numbers, so field expenses and the crew must
              // not be able to move after the code is entered.
              Text(
                'Odometer, field expenses and the crew are locked now.',
                textAlign: TextAlign.center,
                style: theme.bodySmall.override(
                    font: GoogleFonts.inter(), color: theme.secondaryText),
              ),
            ],
          ),
        ),
        // Read-only from here on — see _fieldExpensesCard's own doc
        // comment. Crew has no card here at all (never did): the step
        // machine simply doesn't render _teamSelectionCard again once
        // `done`, which is a real lock, not a UI oversight.
        const SizedBox(height: 16),
        _fieldExpensesCard(context, editable: false),
      ],
    );
  }
}
