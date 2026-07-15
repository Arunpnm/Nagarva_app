import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import 'p_l_report_page_widget.dart' show PLReportPageWidget;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

/// Fixed branch list, matching apc_webapp App.jsx's BRANCHES constant.
const List<String> kPLReportBranches = [
  'Chennai',
  'Bengaluru',
  'Coimbatore',
  'Hyderabad',
];

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
  double get grossProfit => revenue - labour;
  double get netProfit =>
      grossProfit - orderExpenses - otherExpenses - porterCommission;
  double get margin => revenue > 0 ? (netProfit / revenue) * 100 : 0;

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
