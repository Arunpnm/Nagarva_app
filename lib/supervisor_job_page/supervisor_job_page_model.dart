import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'supervisor_job_page_widget.dart' show SupervisorJobPageWidget;
import 'package:flutter/material.dart';

/// Step machine for the on-site job flow — adapted from apc_webapp
/// App.jsx's SupervisorJobPage (lines ~10369-10597), but mapped onto
/// *this* app's actual order.status vocabulary (booked/pending/confirmed/
/// transit/delivered/cancelled — see OrdersPage's 5 tabs), not the
/// reference app's finer-grained one (which has statuses like
/// accepted/loading/in_transit that nothing else in this app understands).
/// Progress within a job is tracked mainly via `orders.supervisor_status`
/// (null -> in_progress -> completed_pending -> approved), and `status`
/// only actually changes twice: to 'transit' when shifting starts, and to
/// 'delivered' on verified completion — both values every other page
/// (OrdersPage tabs, Dashboard, Reports) already knows how to show.
enum SupervisorJobStep { start, team, shifting, completing, otpEntry, done }

class SupervisorJobPageModel extends FlutterFlowModel<SupervisorJobPageWidget> {
  bool isLoading = true;
  String? loadError;
  bool saving = false;

  OrdersRow? order;
  List<StaffRow> staffList = [];
  List<ExpensesRow> jobExpenses = [];

  SupervisorJobStep step = SupervisorJobStep.start;

  Set<String> selectedTeamIds = {};

  // Note: this app's orders table has `job_start_time`/`job_end_time`
  // (timestamps), not the reference app's `start_km`/`end_km`
  // (odometer readings) — there's no odometer column here at all. Job
  // duration is captured automatically (now() at shift-start / at OTP
  // generation) instead of asking the supervisor to type odometer
  // numbers. Deliberate deviation from the reference app, not an
  // oversight — documented in CLAUDE.md.
  TextEditingController? notesController;
  TextEditingController? expenseAmountController;
  TextEditingController? expenseDescController;
  TextEditingController? enteredOtpController;

  String expenseCategory = 'Fuel';

  /// The OTP the supervisor's screen is currently showing (also persisted
  /// to orders.job_otp so verification can be re-checked server-side
  /// instead of trusting only this in-memory copy — the reference app
  /// only checks in-memory state, a security gap noted in CLAUDE.md and
  /// deliberately not copied here).
  String? displayedOtp;
  bool otpError = false;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    notesController?.dispose();
    expenseAmountController?.dispose();
    expenseDescController?.dispose();
    enteredOtpController?.dispose();
  }
}
