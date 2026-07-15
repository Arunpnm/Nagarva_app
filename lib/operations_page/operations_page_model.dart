import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'operations_page_widget.dart' show OperationsPageWidget;
import 'package:flutter/material.dart';

class OperationsPageModel extends FlutterFlowModel<OperationsPageWidget> {
  ///  Local state fields for this page.

  List<VehicleTripsRow> tripsList = [];
  void addToTripsList(VehicleTripsRow item) => tripsList.add(item);
  void removeFromTripsList(VehicleTripsRow item) => tripsList.remove(item);
  void removeAtIndexFromTripsList(int index) => tripsList.removeAt(index);
  void insertAtIndexInTripsList(int index, VehicleTripsRow item) =>
      tripsList.insert(index, item);
  void updateTripsListAtIndex(int index, Function(VehicleTripsRow) updateFn) =>
      tripsList[index] = updateFn(tripsList[index]);

  List<TripsViewRow> tripsViewList = [];
  void addToTripsViewList(TripsViewRow item) => tripsViewList.add(item);
  void removeFromTripsViewList(TripsViewRow item) => tripsViewList.remove(item);
  void removeAtIndexFromTripsViewList(int index) =>
      tripsViewList.removeAt(index);
  void insertAtIndexInTripsViewList(int index, TripsViewRow item) =>
      tripsViewList.insert(index, item);
  void updateTripsViewListAtIndex(int index, Function(TripsViewRow) updateFn) =>
      tripsViewList[index] = updateFn(tripsViewList[index]);

  ///  State fields for stateful widgets in this page.

  // Stores action output result for [Backend Call - Query Rows] action in OperationsPage widget.
  List<TripsViewRow>? tripsViewOut;

  // Orders awaiting owner approval after a supervisor marks the field job
  // complete (orders.supervisor_status == 'completed_pending') — the
  // owner-side half of the supervisor OTP workflow ported from
  // apc_webapp App.jsx's Dashboard pendingApprovals (lines ~1394-1416).
  List<OrdersRow> pendingApprovals = [];

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
