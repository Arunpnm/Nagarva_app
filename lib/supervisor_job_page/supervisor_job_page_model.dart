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
/// `arrivalCode` replaced the old `start` step's plain "Accept Job"
/// button (18 Aug 2026): the supervisor now enters the code the customer
/// was given at confirmation, which is what proves they are actually on
/// site. `otpEntry` is gone — completion is a signature now, captured on
/// the `completing` step itself. See the widget's header for why.
enum SupervisorJobStep { start, arrivalCode, team, shifting, completing, done }

const List<String> kRelationshipOptions = [
  'self',
  'family',
  'neighbour',
  'security',
];

/// How a job was completed. Mirrors `pod_records.completion_method`'s
/// CHECK constraint — keep the two in step.
const String kCompletionSignature = 'signature';
const String kCompletionNotAvailable = 'not_available';

/// Structured reasons for an unsigned completion, mirroring
/// `pod_records.not_available_reason`'s CHECK constraint.
///
/// A flow with no escape hatch gets worked around in the field, and the
/// worst workaround here is the supervisor signing it themselves — so
/// this path exists deliberately, is cheap to use, and is visibly
/// flagged to the owner rather than hidden.
const Map<String, String> kNotAvailableReasons = {
  'customer_absent': 'Customer not present at handover',
  'refused_to_sign': 'Customer refused to sign',
  'representative_took_delivery': 'A representative took delivery',
  'device_or_app_failure': 'Device or app problem',
};

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

  // ---- Arrival (18 Aug 2026) --------------------------------------
  TextEditingController? arrivalCodeController;
  bool arrivalCodeError = false;

  // ---- Completion by signature (18 Aug 2026) ----------------------
  //
  // The captured signature as a base64 PNG. Held HERE, in model state,
  // the moment the customer lifts their finger — before any network
  // call. That ordering is deliberate and load-bearing: a failed write
  // must never mean asking a customer to sign a second time.
  String? signatureBase64;

  /// null until the supervisor picks a path on the completing step.
  /// [kCompletionSignature] or [kCompletionNotAvailable].
  String? completionMethod;

  /// One of [kNotAvailableReasons]' keys, when completionMethod is
  /// [kCompletionNotAvailable].
  String? notAvailableReason;
  TextEditingController? notAvailableNoteController;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    notesController?.dispose();
    expenseAmountController?.dispose();
    expenseNoteController?.dispose();
    enteredOtpController?.dispose();
    arrivalCodeController?.dispose();
    notAvailableNoteController?.dispose();
    kmStartController?.dispose();
    kmEndController?.dispose();
    receivedByNameController?.dispose();
    receivedByPhoneController?.dispose();
    packagesDeliveredController?.dispose();
    packagesShortController?.dispose();
    damageDescriptionController?.dispose();
  }
}
