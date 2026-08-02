import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'supervisor_job_page_widget.dart' show SupervisorJobPageWidget;
import 'package:flutter/material.dart';

/// Step machine for the on-site job flow — Session 2 rebuild.
///
/// Progress within a job is tracked mainly via `orders.supervisor_status`
/// (null -> in_progress -> completed_pending -> approved), and `status`
/// only actually changes twice: to 'transit' when shifting starts, and to
/// 'delivered' on verified completion — both values every other page
/// (OrdersPage tabs, Dashboard, Reports) already knows how to show.
///
/// `shifting` now covers field expenses, the closing-odometer read
/// (`vehicle_trips`, not `orders` — Session 2 Part B3 correction) and
/// notes on one screen, matching the brief's "Job detail" framing rather
/// than a forced multi-step wizard for what's really one page's worth of
/// pre-completion actions.
enum SupervisorJobStep { start, team, shifting, completing, otpEntry, done }

const List<String> kRelationshipOptions = [
  'self',
  'family',
  'neighbour',
  'security',
];

class SupervisorJobPageModel extends FlutterFlowModel<SupervisorJobPageWidget> {
  bool isLoading = true;
  String? loadError;
  bool saving = false;

  OrdersRow? order;
  List<StaffRow> staffList = [];

  /// Session 2 Part A: the real crew, read from `order_staff` (not
  /// `job_team` directly) — this is what CrewSyncService keeps in sync.
  List<OrderStaffRow> crew = [];

  /// Parsed from `orders.field_expenses` (migration 007 shape:
  /// `[{"type","amount","note","at"}]`) — replaces the old per-job
  /// `expenses` table rows per the Session 2 brief's B2 correction.
  List<Map<String, dynamic>> fieldExpenses = [];

  /// This order's `vehicle_trips` row, if one exists yet. Null until the
  /// first odometer save (or forever, for a third-party vehicle that
  /// never gets one — see B3's "do not block" rule).
  VehicleTripsRow? vehicleTrip;

  SupervisorJobStep step = SupervisorJobStep.start;

  Set<String> selectedTeamIds = {};

  TextEditingController? notesController;
  TextEditingController? expenseAmountController;
  TextEditingController? expenseNoteController;
  TextEditingController? enteredOtpController;
  TextEditingController? kmStartController;
  TextEditingController? kmEndController;

  // ---- Completion / POD capture (Session 2 B5 step 6) --------------------
  TextEditingController? receivedByNameController;
  TextEditingController? receivedByPhoneController;
  TextEditingController? packagesDeliveredController;
  TextEditingController? packagesShortController;
  TextEditingController? damageDescriptionController;
  String relationship = 'self';
  bool damageNoted = false;

  String expenseType = 'Fuel';

  /// The OTP the supervisor's screen is currently showing (also persisted
  /// to orders.job_otp so verification can be re-checked server-side
  /// instead of trusting only this in-memory copy).
  String? displayedOtp;
  bool otpError = false;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    notesController?.dispose();
    expenseAmountController?.dispose();
    expenseNoteController?.dispose();
    enteredOtpController?.dispose();
    kmStartController?.dispose();
    kmEndController?.dispose();
    receivedByNameController?.dispose();
    receivedByPhoneController?.dispose();
    packagesDeliveredController?.dispose();
    packagesShortController?.dispose();
    damageDescriptionController?.dispose();
  }
}
