import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'home_page_widget.dart' show HomePageWidget;
import 'package:flutter/material.dart';

class HomePageModel extends FlutterFlowModel<HomePageWidget> {
  ///  Local state fields for this page.

  /// Vendor choice: show the Porter commission KPI card. Porter is
  /// Bengaluru/APC-specific; pan-India vendors opt in via Settings
  /// (settings key 'porter_enabled', jsonb 'true'/'false'). Defaults off
  /// for new orgs; APC seeds it on (see 20260717_notifications_and_settings.sql).
  bool porterEnabled = false;

  List<DashboardKpisViewRow> kpiList = [];
  void addToKpiList(DashboardKpisViewRow item) => kpiList.add(item);
  void removeFromKpiList(DashboardKpisViewRow item) => kpiList.remove(item);
  void removeAtIndexFromKpiList(int index) => kpiList.removeAt(index);
  void insertAtIndexInKpiList(int index, DashboardKpisViewRow item) =>
      kpiList.insert(index, item);
  void updateKpiListAtIndex(
          int index, Function(DashboardKpisViewRow) updateFn) =>
      kpiList[index] = updateFn(kpiList[index]);

  List<BranchKpisViewRow> branchStats = [];
  void addToBranchStats(BranchKpisViewRow item) => branchStats.add(item);
  void removeFromBranchStats(BranchKpisViewRow item) =>
      branchStats.remove(item);
  void removeAtIndexFromBranchStats(int index) => branchStats.removeAt(index);
  void insertAtIndexInBranchStats(int index, BranchKpisViewRow item) =>
      branchStats.insert(index, item);
  void updateBranchStatsAtIndex(
          int index, Function(BranchKpisViewRow) updateFn) =>
      branchStats[index] = updateFn(branchStats[index]);

  List<OrdersRow> upcomingOrders = [];
  void addToUpcomingOrders(OrdersRow item) => upcomingOrders.add(item);
  void removeFromUpcomingOrders(OrdersRow item) => upcomingOrders.remove(item);
  void removeAtIndexFromUpcomingOrders(int index) =>
      upcomingOrders.removeAt(index);
  void insertAtIndexInUpcomingOrders(int index, OrdersRow item) =>
      upcomingOrders.insert(index, item);
  void updateUpcomingOrdersAtIndex(int index, Function(OrdersRow) updateFn) =>
      upcomingOrders[index] = updateFn(upcomingOrders[index]);

  List<LeadsRow> hotLeads = [];
  void addToHotLeads(LeadsRow item) => hotLeads.add(item);
  void removeFromHotLeads(LeadsRow item) => hotLeads.remove(item);
  void removeAtIndexFromHotLeads(int index) => hotLeads.removeAt(index);
  void insertAtIndexInHotLeads(int index, LeadsRow item) =>
      hotLeads.insert(index, item);
  void updateHotLeadsAtIndex(int index, Function(LeadsRow) updateFn) =>
      hotLeads[index] = updateFn(hotLeads[index]);

  double? monthlyTarget = 200000.0;

  bool? showEditTarget = false;

  String? targetInputStr = '';

  /// Dashboard period filter (item 4, NAGARVA_STATUS.md): 'month' | '3m' |
  /// 'fy' | 'all'. Only affects the financial KPI row (Revenue/Labour/
  /// Expenses/Net Profit) and the orders-in-period count — Active Leads/
  /// Outstanding/Reminders stay current-state regardless, since "active
  /// leads in March" isn't a meaningful backward-looking metric.
  String periodType = 'month';

  /// Anchor month for periodType == 'month', steppable via the arrows.
  /// "This"/"Last" chips jump this to the current/previous month; 3M/FY/All
  /// ignore it entirely.
  DateTime visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);

  ///  State fields for stateful widgets in this page.

  // Stores action output result for [Backend Call - Query Rows] action in HomePage widget.
  List<DashboardKpisViewRow>? dashKpiOut;
  // Stores action output result for [Backend Call - Query Rows] action in HomePage widget.
  List<OrdersRow>? dashUpcomingOut;
  // Stores action output result for [Backend Call - Query Rows] action in HomePage widget.
  List<LeadsRow>? dashHotLeadsOut;
  // Stores action output result for [Backend Call - Query Rows] action in HomePage widget.
  List<BranchKpisViewRow>? dashBranchOut;
  // State field(s) for TargetInputField widget.
  FocusNode? targetInputFieldFocusNode;
  TextEditingController? targetInputFieldTextController;
  String? Function(BuildContext, String?)?
      targetInputFieldTextControllerValidator;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    targetInputFieldFocusNode?.dispose();
    targetInputFieldTextController?.dispose();
  }
}
