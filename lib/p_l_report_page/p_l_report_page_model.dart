import '/flutter_flow/flutter_flow_util.dart';
import '/backend/margin_availability.dart';
import 'p_l_report_page_widget.dart' show PLReportPageWidget;
import 'package:flutter/material.dart';

/// Fixed lead-source list, matching apc_webapp App.jsx's SOURCES constant.
const List<String> kPLReportSources = [
  'phone',
  'porter',
  'justdial',
  'referral',
  'website',
  'whatsapp',
  'walkin',
  'other',
];

class BranchPL {
  BranchPL({
    required this.branch,
    required this.revenue,
    required this.labour,
    required this.expenses,
    required this.profit,
  });
  final String branch;
  final double revenue;
  final double labour;
  final double expenses;
  final double profit;
  double get margin => revenue > 0 ? (profit / revenue) * 100 : 0;
}

class LeadSourceStat {
  LeadSourceStat(
      {required this.source, required this.total, required this.converted});
  final String source;
  final int total;
  final int converted;
  double get rate => total > 0 ? (converted / total) * 100 : 0;
}

class PLReportPageModel extends FlutterFlowModel<PLReportPageWidget> {
  bool isLoading = true;
  String? loadError;

  /// month | quarter | year | all — mirrors the reference app's period filter.
  String period = 'month';

  double revenue = 0;
  double labour = 0;
  double orderExpenses = 0;
  double otherExpenses = 0;
  double porterCommission = 0;
  /// Orders counted in the current period. Needed by [marginIsShowable]:
  /// "no expenses" only contradicts reality if work actually happened.
  int orderCount = 0;

  /// Orders in the period from a commission-bearing source with no rate
  /// set. Their commission is excluded from [porterCommission], which is
  /// therefore a FLOOR while this is above zero — see
  /// /backend/commission_pricing.dart.
  int unpricedCommissionCount = 0;

  bool get hasUnpricedCommission => unpricedCommissionCount > 0;

  double get grossProfit => revenue - labour;
  double get netProfit =>
      grossProfit - orderExpenses - otherExpenses - porterCommission;
  double get margin => revenue > 0 ? (netProfit / revenue) * 100 : 0;

  /// False when no expenses are recorded for a period that had orders.
  ///
  /// Shares [marginIsMeaningful] with the dashboard deliberately — the
  /// same starved input feeds both, so without one rule they would tell
  /// the same lie independently. `expenses` currently has 0 live rows,
  /// which makes [netProfit] collapse to roughly [revenue] and render as
  /// a ~100% margin. Suppress the figure rather than print it.
  ///
  /// Also false while a commission is unpriced: that is a second, unrelated
  /// missing cost, and [netProfit] silently omits it. Both conditions must
  /// clear before a profit figure is honest.
  bool get marginIsShowable =>
      marginIsMeaningful(
        expensesTotal: orderExpenses + otherExpenses,
        orderCount: orderCount,
      ) &&
      !hasUnpricedCommission;

  List<BranchPL> branchPL = [];
  List<LeadSourceStat> leadSources = [];

  // GST summary — reference app only computes the 5% bracket, others are
  // dead code there too. This app doesn't have a per-order gst_pct column
  // yet, so a flat 5% is assumed for the whole period's order revenue.
  double get gstTaxable => (revenue / 1.05).roundToDouble();
  double get gstTotal => revenue - gstTaxable;
  double get gstHalf => gstTotal / 2;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
