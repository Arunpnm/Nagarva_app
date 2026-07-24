import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'salary_page_widget.dart' show SalaryPageWidget;
import 'package:flutter/material.dart';

/// Week 3b rewrite: per-staff ledger (earned / paid / balance / advance)
/// with month navigation. Replaces the old attendance+advances dump.
class SalaryPageModel extends FlutterFlowModel<SalaryPageWidget> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  List<StaffRow> staffList = [];
  List<OrderStaffRow> orderStaff = [];
  List<SalaryPaymentsRow> payments = [];
  List<StaffAdvancesRow> advances = [];

  /// order_id -> order (for move_date month attribution + labels).
  Map<String, OrdersRow> ordersById = {};

  bool loading = true;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
