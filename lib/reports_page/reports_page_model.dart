import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import 'reports_page_widget.dart' show ReportsPageWidget;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class BranchRevenue {
  BranchRevenue({
    required this.branch,
    required this.orderCount,
    required this.revenue,
    required this.labour,
    required this.expenses,
  });
  final String branch;
  final int orderCount;
  final double revenue;
  final double labour;
  final double expenses;
  double get profit => revenue - labour - expenses;
  double get margin => revenue > 0 ? (profit / revenue) * 100 : 0;
}

class MonthlyVolume {
  MonthlyVolume(
      {required this.label, required this.orderCount, required this.revenue});
  final String label;
  final int orderCount;
  final double revenue;
}

class TopCustomer {
  TopCustomer({
    required this.customer,
    required this.orderCount,
    required this.revenue,
    required this.lastDate,
  });
  final String customer;
  final int orderCount;
  final double revenue;
  final DateTime lastDate;
}

class ServiceMixStat {
  ServiceMixStat({required this.service, required this.count});
  final String service;
  final int count;
}

class ReportsPageModel extends FlutterFlowModel<ReportsPageWidget> {
  bool isLoading = true;
  String? loadError;

  /// month | quarter | year | all
  String period = 'month';
  String searchQuery = '';

  List<BranchRevenue> branchRevenue = [];
  List<MonthlyVolume> monthlyVolume = [];
  List<TopCustomer> topCustomers = [];
  List<ServiceMixStat> serviceMix = [];
  int filteredOrderCount = 0;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
