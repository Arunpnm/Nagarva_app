import '/components/ng_widgets.dart';
import '/app_session.dart';
import '/backend/whatsapp_cloud.dart';
import '/backend/audit_log_service.dart';
import '/backend/crew_sync_service.dart';
import '/backend/tracking_service.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/components/signature_pad.dart';
import '/components/supervisor_menu_button.dart';
import '/flutter_flow/custom_functions.dart' as functions;
import '/flutter_flow/ng_tokens.dart';
import '/index.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
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

      // Both stores, because entries written before 3 Sept 2026 live in
      // the jsonb and everything since lives in `expenses`. Showing only
      // one would let a supervisor re-enter money already recorded.
      final fromJson =
          _parseFieldExpenses(_model.order!.data['field_expenses']);
      final fromTable = await ExpensesTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('order_id', widget.orderId!),
      );
      _model.fieldExpenses = [
        ...fromJson,
        for (final e in fromTable)
          {
            'type': e.category ?? 'Expense',
            'amount': e.amount ?? 0,
            'note': e.description ?? '',
            'at': e.date ?? '',
          },
      ];

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

  SupervisorJobStep _inferStep(OrdersRow o) => supervisorStepFor(o);

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
      WhatsAppCloud.moveStarted(_model.order);
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

  /// Field expenses now write to the `expenses` TABLE, not to
  /// `orders.field_expenses`.
  ///
  /// CHANGED 3 Sept 2026 (Arun, option 3). The Field Job screen stays the
  /// ONE place a job expense is captured — it is where the person who
  /// actually spent the money is standing — but the jsonb it wrote to was
  /// a dead end: those rows reached the order's own P&L and NOTHING else.
  /// Not the Expenses page, not the Daily Accounts Register, not the P&L
  /// report. A vendor's diesel and carpenter money simply did not exist
  /// outside the one order screen.
  ///
  /// Writing a real row fixes that with no new UI. The alternative
  /// considered and rejected was a second expense section on Order
  /// Details, which would have made three ways to record one thing —
  /// exactly the "plenty of modules, which is for what" problem Arun
  /// raised the same day.
  ///
  /// **Existing jsonb entries are still READ** (see `_load` and the P&L's
  /// `sumFieldExpenses`) so nothing already captured disappears. Only new
  /// entries go to the table; a backfill is a separate, deliberate step.
  Future<void> _addFieldExpense() async {
    final amount = double.tryParse(_model.expenseAmountController!.text);
    if (amount == null || amount <= 0) {
      _showError('Enter a valid expense amount.');
      return;
    }
    setState(() => _model.saving = true);
    try {
      final note = _model.expenseNoteController!.text.trim();
      await ExpensesTable().insert({
        ...OrgScope.stamp(),
        'amount': amount,
        'category': _model.expenseType,
        'date': DateTime.now().toIso8601String().split('T').first,
        'order_id': widget.orderId,
        if (note.isNotEmpty) 'description': note,
      });
      // Mirrored into local state so the list on screen updates without a
      // reload. The row itself is the source of truth; this is display.
      _model.fieldExpenses = [
        ..._model.fieldExpenses,
        {
          'type': _model.expenseType,
          'amount': amount,
          'note': note,
          'at': DateTime.now().toIso8601String().split('T').first,
        }
      ];
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
      WhatsAppCloud.delivered(_model.order);
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
    final c = NgPalette.of(context);
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: c.bg,
        appBar: NgSimpleBar(
          titleWidget: Text(widget.orderId ?? 'Field job'),
          mono: true,
          actions: const [SupervisorMenuButton()],
        ),
        body: _model.isLoading
            ? const Center(child: CircularProgressIndicator())
            : _model.loadError != null
                ? Center(
                    child: NgEmptyState(
                      icon: Icons.error_outline_rounded,
                      title: 'Could not open this job',
                      subtitle: _model.loadError,
                      action: SizedBox(
                        width: 140,
                        child: NgSecondaryButton(
                            label: 'Try again', onPressed: _loadData),
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        _orderSummaryCard(context),
                        const SizedBox(height: 14),
                        _stepTracker(context),
                        const SizedBox(height: 14),
                        _stepBody(context),
                      ],
                    ),
                  ),
      ),
    );
  }

  static const _kStepLabels = [
    'Accept',
    'Arrive',
    'Crew',
    'Shifting',
    'Handover',
  ];

  int get _stepIndex => switch (_model.step) {
        SupervisorJobStep.start => 0,
        SupervisorJobStep.arrivalCode => 1,
        SupervisorJobStep.team => 2,
        SupervisorJobStep.shifting => 3,
        SupervisorJobStep.completing => 4,
        SupervisorJobStep.done => 5,
      };

  /// Where the job is, in the same 5 field steps the screen walks through.
  Widget _stepTracker(BuildContext context) {
    final c = NgPalette.of(context);
    final i = _stepIndex;
    final done = i >= _kStepLabels.length;
    return NgCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  done ? 'Job complete' : 'Step ${i + 1} of 5 · ${_kStepLabels[i]}',
                  style: NgFonts.geist(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: done ? c.green : c.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          NgStageBar(
              done: done ? 5 : i, total: 5, color: done ? c.green : c.accBtn),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var k = 0; k < _kStepLabels.length; k++)
                Expanded(
                  child: Text(
                    _kStepLabels[k],
                    textAlign: k == 0
                        ? TextAlign.left
                        : k == _kStepLabels.length - 1
                            ? TextAlign.right
                            : TextAlign.center,
                    style: NgFonts.geist(
                        fontSize: 11,
                        fontWeight:
                            k == i ? FontWeight.w600 : FontWeight.w400,
                        color: k < i || done
                            ? c.soft
                            : k == i
                                ? c.acc
                                : c.faint),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _orderSummaryCard(BuildContext context) {
    final c = NgPalette.of(context);
    final o = _model.order!;
    final completed = o.status == 'delivered' ||
        o.status == 'closed' ||
        o.supervisorStatus == 'completed_pending' ||
        o.supervisorStatus == 'approved';
    final hideCustomer =
        completed && AppSession.instance.isSupervisorSession;
    final vehicle = [
      if ((o.vehicleNo ?? '').isNotEmpty) o.vehicleNo!,
      if ((o.driverName ?? '').isNotEmpty) o.driverName!,
    ].join(' · ');
    return NgCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Privacy hold (post-job contact / lead-poaching prevention,
          // same rule as OrdersPage/OperationsPage) still hides the name;
          // the order id stays in the top bar so a supervisor with several
          // completed jobs can still tell which one is open.
          Text(hideCustomer ? 'Customer (hidden)' : o.customer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NgFonts.geist(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: c.text)),
          const SizedBox(height: 4),
          Row(
            children: [
              Flexible(
                child: Text(o.fromCity ?? '-',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
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
                    style: NgFonts.geist(fontSize: 13.5, color: c.mute)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (o.moveDateOrNull != null)
                NgPill(DateFormat('EEE, d MMM').format(o.moveDateOrNull!),
                    icon: Icons.event_outlined),
              if (vehicle.isNotEmpty)
                NgPill(vehicle, icon: Icons.local_shipping_outlined),
              if ((o.service ?? '').isNotEmpty) NgPill(o.service!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepBody(BuildContext context) {
    switch (_model.step) {
      case SupervisorJobStep.start:
        return _actionCard(
          context,
          icon: Icons.assignment_turned_in_outlined,
          title: 'Ready to start this job?',
          body: 'Accepting will let you pick the labour team and begin shifting.',
          buttonLabel: 'Accept job',
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _closingOdometerCard(context),
            const SizedBox(height: 14),
            _completionCard(context),
          ],
        );
      case SupervisorJobStep.done:
        return _doneCard(context);
    }
  }

  Widget _muted(BuildContext context, String text) => Text(text,
      style: NgFonts.geist(
          fontSize: 13, height: 1.4, color: NgPalette.of(context).mute));

  Widget _actionCard(BuildContext context,
      {required IconData icon,
      required String title,
      required String body,
      required String buttonLabel,
      required Future<void> Function() onPressed}) {
    final c = NgPalette.of(context);
    return NgCard(
      radius: 20,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NgIconTile(icon: icon, status: NgStatus.accent, size: 44, iconSize: 22),
          const SizedBox(height: 14),
          Text(title,
              style: NgFonts.geist(
                  fontSize: 17, fontWeight: FontWeight.w600, color: c.text)),
          const SizedBox(height: 4),
          _muted(context, body),
          const SizedBox(height: 16),
          NgPrimaryButton(
            label: _model.saving ? 'Please wait…' : buttonLabel,
            onPressed: _model.saving ? null : onPressed,
          ),
        ],
      ),
    );
  }

  Widget _teamSelectionCard(BuildContext context) {
    final c = NgPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NgSectionCard(
          title: 'Labour team',
          icon: Icons.groups_outlined,
          trailing: Text('${_model.selectedTeamIds.length} picked',
              style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _model.staffList.isEmpty
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _muted(context, 'No active staff found.'),
                )
              : Column(
                  children: [
                    for (final s in _model.staffList)
                      // Role alongside the name. Arun, 3 Sept 2026: two
                      // Balajis on a crew list are indistinguishable by
                      // name alone, and the wrong tick puts the wrong man on
                      // the job - which then flows into his attendance, his
                      // earnings and the job's labour cost.
                      _crewPickRow(context, s),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        // Opening reading sits WITH the crew selection, because both
        // are things you do before the vehicle moves.
        _openingOdometerCard(context),
        const SizedBox(height: 16),
        NgPrimaryButton(
          icon: Icons.play_arrow_rounded,
          label: _model.saving ? 'Please wait…' : 'Start shifting',
          onPressed: _model.saving ? null : _startShifting,
        ),
      ],
    );
  }

  Widget _crewPickRow(BuildContext context, StaffRow s) {
    final c = NgPalette.of(context);
    final selected = _model.selectedTeamIds.contains(s.id);
    final role = (s.role ?? '').trim();
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() {
        if (selected) {
          _model.selectedTeamIds.remove(s.id);
        } else {
          _model.selectedTeamIds.add(s.id ?? '');
        }
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            NgAvatar(s.name,
                status: selected ? NgStatus.accent : NgStatus.neutral),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name,
                      style: NgFonts.geist(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: c.text)),
                  if (role.isNotEmpty)
                    Text(role[0].toUpperCase() + role.substring(1),
                        style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: selected ? c.accBtn : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                    color: selected ? c.accBtn : c.w15, width: 1.5),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      size: 17, color: NgPalette.onAcc)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _crewCard(BuildContext context) {
    final c = NgPalette.of(context);
    return NgSectionCard(
      title: 'Crew',
      icon: Icons.groups_outlined,
      // Day-close crew sheet (staff-pay brief §4/§10). The brief puts day
      // close on the supervisor, so the sheet has to be reachable from the
      // job he already has open — the crew card is where he is standing
      // when he thinks about who worked.
      trailing: NgLinkButton(
        'Crew sheet',
        icon: Icons.fact_check_outlined,
        onTap: () => context
            .pushNamed(
              CrewSheetPageWidget.routeName,
              queryParameters: {'orderId': widget.orderId ?? ''},
            )
            .then((_) => _loadData()),
      ),
      child: _model.crew.isEmpty
          ? _muted(context, 'No crew on record for this order yet.')
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _model.crew)
                  Builder(builder: (context) {
                    final s = _model.staffList
                        .where((s) => s.id == m.staffId)
                        .firstOrNull;
                    return Container(
                      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                      decoration: BoxDecoration(
                        color: c.s3,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          NgAvatar(s?.name ?? 'Staff', size: 24),
                          const SizedBox(width: 6),
                          Text(s?.name ?? 'Staff',
                              style: NgFonts.geist(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: c.text)),
                        ],
                      ),
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
  /// closed the order. Now everything locks the moment completion
  /// succeeds, not at Close Order — the owner is approving a fixed set of
  /// numbers, and they must not be able to move after that.
  Widget _fieldExpensesCard(BuildContext context, {bool editable = true}) {
    final c = NgPalette.of(context);
    final total = _model.fieldExpenses.fold<double>(
        0, (s, e) => s + (num.tryParse('${e['amount']}') ?? 0));
    return NgSectionCard(
      title: 'Field expenses',
      icon: Icons.receipt_long_outlined,
      trailing: editable
          ? null
          : const NgPill('Locked', icon: Icons.lock_outline_rounded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_model.fieldExpenses.isEmpty)
            _muted(context,
                editable ? 'Nothing logged yet.' : 'No field expenses were logged.'),
          for (final e in _model.fieldExpenses)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${e['type']}',
                            style: NgFonts.geist(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: c.text)),
                        if ((e['note'] ?? '').toString().isNotEmpty)
                          Text('${e['note']}',
                              style:
                                  NgFonts.geist(fontSize: 12.5, color: c.mute)),
                      ],
                    ),
                  ),
                  Text(
                      functions
                          .inrFull((num.tryParse('${e['amount']}') ?? 0).toDouble()),
                      style: NgFonts.mono(fontSize: 13.5, color: c.text)),
                ],
              ),
            ),
          if (_model.fieldExpenses.isNotEmpty) ...[
            Divider(height: 18, color: c.w06),
            NgKeyValue('Total', functions.inrFull(total),
                mono: true, strong: true),
          ],
          if (editable) ...[
            const SizedBox(height: 14),
            const NgFieldLabel('Add an expense'),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final cat in kJobExpenseCategories) ...[
                    NgChip(
                      label: cat,
                      selected: _model.expenseType == cat,
                      onTap: () => setState(() => _model.expenseType = cat),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: NgInput(
                    controller: _model.expenseAmountController!,
                    hint: '₹ Amount',
                    keyboardType: TextInputType.number,
                    mono: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: NgInput(
                    controller: _model.expenseNoteController!,
                    hint: 'Note (optional)',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            NgSecondaryButton(
              icon: Icons.add_rounded,
              label: 'Add expense',
              onPressed: _model.saving ? null : _addFieldExpense,
            ),
          ],
        ],
      ),
    );
  }

  /// Opening odometer — captured WHEN THE JOB STARTS, beside the crew.
  ///
  /// Arun, 3 Sept 2026: *"while selecting labour make the opening odo km
  /// noted and while he marks order complete then only closing odo."*
  /// Both boxes on one card meant the supervisor could fill them in
  /// together at the END of the day — at which point the opening reading
  /// is remembered or guessed, not observed. Splitting the two is what
  /// makes the opening reading evidence instead of a reconstruction.
  Widget _openingOdometerCard(BuildContext context) {
    return NgSectionCard(
      title: 'Opening odometer',
      icon: Icons.speed_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _muted(
              context,
              'Read it off the dial before you leave. Optional — leave '
              'blank for a third-party vehicle.'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: NgInput(
                  controller: _model.kmStartController!,
                  hint: 'Opening km',
                  keyboardType: TextInputType.number,
                  mono: true,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: NgSecondaryButton(
                  label: 'Save',
                  height: 52,
                  onPressed: _model.saving ? null : _saveOdometer,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Closing odometer — only at completion. Shows the opening figure
  /// above it, so the supervisor is entering a number they can see is
  /// larger, and the distance is visible before they commit rather than
  /// discovered in a report later.
  Widget _closingOdometerCard(BuildContext context) {
    final opening = double.tryParse(_model.kmStartController.text.trim());
    final closing = double.tryParse(_model.kmEndController.text.trim());
    final distance =
        (opening != null && closing != null) ? closing - opening : null;
    return NgSectionCard(
      title: 'Closing odometer',
      icon: Icons.speed_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _muted(
              context,
              opening == null
                  ? 'No opening reading was recorded for this job, so the '
                      'distance cannot be worked out. Enter the closing '
                      'reading anyway if you have it.'
                  : 'Opening was ${opening.toStringAsFixed(0)} km.'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: NgInput(
                  controller: _model.kmEndController!,
                  hint: 'Closing km',
                  keyboardType: TextInputType.number,
                  mono: true,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: NgSecondaryButton(
                  label: 'Save',
                  height: 52,
                  onPressed: _model.saving ? null : _saveOdometer,
                ),
              ),
            ],
          ),
          if (distance != null) ...[
            const SizedBox(height: 10),
            // Flagged, not blocked: a genuine reason exists (the dial was
            // misread, or the vehicle was swapped), and refusing to save
            // would lose the reading entirely.
            Align(
              alignment: Alignment.centerLeft,
              child: NgPill(
                distance < 0
                    ? 'Closing is lower than opening — check the reading'
                    : '${distance.toStringAsFixed(0)} km this job',
                status: distance < 0 ? NgStatus.red : NgStatus.green,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _shiftingCard(BuildContext context) {
    final c = NgPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _crewCard(context),
        const SizedBox(height: 14),
        _fieldExpensesCard(context),
        const SizedBox(height: 14),
        // No odometer here on purpose. Opening was taken at the crew
        // step; closing belongs on the completion card, so the two
        // cannot be typed together at the end of the day.
        NgSectionCard(
          title: 'Notes',
          icon: Icons.sticky_note_2_outlined,
          child: NgInput(
            controller: _model.notesController!,
            hint: 'Any notes for the office…',
            maxLines: 3,
          ),
        ),
        const SizedBox(height: 16),
        if (_shiftingCompletionBlocked)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: c.red),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Closing km is required before completion — an opening '
                    'reading was recorded for this vehicle.',
                    style: NgFonts.geist(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: c.red),
                  ),
                ),
              ],
            ),
          ),
        // Leads to the handover card (signature or "customer not
        // available"); the old completion OTP was removed 18 Aug 2026.
        NgPrimaryButton(
          icon: Icons.flag_rounded,
          label: 'Shifting done — handover',
          onPressed: _shiftingCompletionBlocked
              ? null
              : () => setState(() => _model.step = SupervisorJobStep.completing),
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
    final c = NgPalette.of(context);
    final needsName = (_model.completionMethod ?? kCompletionSignature) ==
        kCompletionSignature;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Proof of delivery',
            style: NgFonts.geist(
                fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
        const SizedBox(height: 2),
        _muted(
            context,
            needsName
                ? 'Name and relationship are required when the customer signs.'
                : 'Optional, but recommended.'),
        const SizedBox(height: 12),
        NgFieldLabel(needsName ? 'Received by *' : 'Received by'),
        NgInput(controller: _model.receivedByNameController!, hint: 'Name'),
        const SizedBox(height: 8),
        NgInput(
          controller: _model.receivedByPhoneController!,
          hint: 'Phone',
          keyboardType: TextInputType.phone,
          mono: true,
        ),
        const SizedBox(height: 14),
        const NgFieldLabel('Relationship to customer'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in kRelationshipOptions)
            NgChip(
              label: r[0].toUpperCase() + r.substring(1),
              selected: _model.relationship == r,
              onTap: () => setState(() => _model.relationship = r),
            ),
        ]),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const NgFieldLabel('Packages delivered'),
                  NgInput(
                    controller: _model.packagesDeliveredController!,
                    hint: '0',
                    keyboardType: TextInputType.number,
                    mono: true,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const NgFieldLabel('Packages short'),
                  NgInput(
                    controller: _model.packagesShortController!,
                    hint: '0',
                    keyboardType: TextInputType.number,
                    mono: true,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _toggleRow(
          context,
          label: 'Damage noted',
          value: _model.damageNoted,
          onChanged: (v) => setState(() => _model.damageNoted = v),
        ),
        if (_model.damageNoted) ...[
          const SizedBox(height: 8),
          NgInput(
            controller: _model.damageDescriptionController!,
            hint: 'What was damaged?',
            maxLines: 2,
          ),
        ],
      ],
    );
  }

  Widget _toggleRow(BuildContext context,
      {required String label,
      required bool value,
      required ValueChanged<bool> onChanged}) {
    final c = NgPalette.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: NgFonts.geist(fontSize: 14.5, color: c.text)),
        ),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeTrackColor: c.accBtn,
        ),
      ],
    );
  }

  final GlobalKey<SignaturePadState> _sigKey = GlobalKey<SignaturePadState>();

  /// Arrival gate. Deliberately does NOT display the expected code —
  /// that was the flaw in the old completion OTP, where the supervisor's
  /// own screen showed them the answer before they typed it back.
  Widget _arrivalCodeCard(BuildContext context) {
    final c = NgPalette.of(context);
    final err = _model.arrivalCodeError;
    return NgCard(
      radius: 20,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NgIconTile(
              icon: Icons.pin_outlined,
              status: NgStatus.accent,
              size: 44,
              iconSize: 22),
          const SizedBox(height: 14),
          Text('Confirm you have arrived',
              style: NgFonts.geist(
                  fontSize: 17, fontWeight: FontWeight.w600, color: c.text)),
          const SizedBox(height: 4),
          _muted(
              context,
              'Ask the customer for the 4-digit arrival code from their '
              'booking confirmation.'),
          const SizedBox(height: 18),
          TextField(
            controller: _model.arrivalCodeController!,
            keyboardType: TextInputType.number,
            maxLength: 4,
            style: NgFonts.mono(
                fontSize: 32,
                letterSpacing: 14,
                fontWeight: FontWeight.w600,
                color: c.text),
            textAlign: TextAlign.center,
            cursorColor: c.acc,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) {
              if (_model.arrivalCodeError) {
                setState(() => _model.arrivalCodeError = false);
              }
            },
            decoration: InputDecoration(
              counterText: '',
              hintText: '····',
              hintStyle: NgFonts.mono(
                  fontSize: 32, letterSpacing: 14, color: c.faint),
              filled: true,
              fillColor: c.inset,
              contentPadding: const EdgeInsets.symmetric(vertical: 18),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(NgRadius.tile),
                borderSide: BorderSide(color: err ? c.red : c.w08),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(NgRadius.tile),
                borderSide: BorderSide(color: err ? c.red : c.acc, width: 1.5),
              ),
            ),
          ),
          if (err) ...[
            const SizedBox(height: 8),
            Text('That code does not match. Check with the customer.',
                style: NgFonts.geist(fontSize: 12.5, color: c.red)),
          ],
          const SizedBox(height: 16),
          NgPrimaryButton(
            icon: Icons.login_rounded,
            label: 'Confirm arrival',
            onPressed: _model.saving ? null : _verifyArrival,
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
    final c = NgPalette.of(context);
    final method = _model.completionMethod ?? kCompletionSignature;
    return NgCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Handover',
              style: NgFonts.geist(
                  fontSize: 17, fontWeight: FontWeight.w600, color: c.text)),
          const SizedBox(height: 12),
          NgSegmented(
            labels: const ['Customer signs', 'Not available'],
            selected: method == kCompletionSignature ? 0 : 1,
            onSelect: (i) => setState(() => _model.completionMethod =
                i == 0 ? kCompletionSignature : kCompletionNotAvailable),
          ),
          const SizedBox(height: 16),
          if (method == kCompletionSignature) ...[
            _muted(context, 'Ask the customer to sign below'),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(NgRadius.tile),
              child: SignaturePad(
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
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if ((_model.signatureBase64 ?? '').isNotEmpty)
                  const NgPill('Signature captured',
                      status: NgStatus.green, icon: Icons.check_rounded),
                const Spacer(),
                NgLinkButton('Clear',
                    onTap: () => setState(() {
                          _sigKey.currentState?.clear();
                          _model.signatureBase64 = null;
                        })),
              ],
            ),
          ] else ...[
            _muted(context, 'Why could the customer not sign?'),
            const SizedBox(height: 10),
            for (final e in kNotAvailableReasons.entries) ...[
              NgOptionCard(
                icon: _model.notAvailableReason == e.key
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                title: e.value,
                subtitle: '',
                selected: _model.notAvailableReason == e.key,
                onTap: () => setState(() => _model.notAvailableReason = e.key),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            NgInput(
              controller: _model.notAvailableNoteController!,
              hint: 'Add detail (optional)',
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.amberBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 17, color: c.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The owner will see this job as completed without a '
                      'signature, and why.',
                      style: NgFonts.geist(
                          fontSize: 12.5, height: 1.35, color: c.text),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Divider(height: 32, color: c.w06),
          _podCaptureFields(context),
          const SizedBox(height: 18),
          NgPrimaryButton(
            icon: Icons.check_circle_outline_rounded,
            label: _model.saving ? 'Please wait…' : 'Complete job',
            height: 54,
            onPressed: _model.saving ? null : _completeJob,
          ),
        ],
      ),
    );
  }

  Widget _doneCard(BuildContext context) {
    final c = NgPalette.of(context);
    final approved = _model.order?.supervisorStatus == 'approved';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NgCard(
          radius: 20,
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              NgIconTile(
                icon: approved
                    ? Icons.verified_rounded
                    : Icons.hourglass_top_rounded,
                status: approved ? NgStatus.green : NgStatus.amber,
                size: 52,
                iconSize: 26,
              ),
              const SizedBox(height: 12),
              Text(
                  approved
                      ? 'Approved by the office'
                      : 'Awaiting owner approval',
                  style: NgFonts.geist(
                      fontSize: 17, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(height: 4),
              // Everything locks at completion now, not at Close Order —
              // the owner is approving a fixed set of numbers.
              Text(
                'Odometer, field expenses and the crew are locked now.',
                textAlign: TextAlign.center,
                style: NgFonts.geist(fontSize: 13, color: c.mute),
              ),
            ],
          ),
        ),
        // Read-only from here on — see _fieldExpensesCard's doc comment.
        // Crew has no card here at all (never did): the step machine
        // simply doesn't render _teamSelectionCard again once `done`,
        // which is a real lock, not a UI oversight.
        const SizedBox(height: 14),
        _fieldExpensesCard(context, editable: false),
      ],
    );
  }
}
