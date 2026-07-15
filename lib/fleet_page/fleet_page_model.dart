import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import 'fleet_page_widget.dart' show FleetPageWidget;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class FleetPageModel extends FlutterFlowModel<FleetPageWidget> {
  ///  Local state fields for this page.

  List<VehiclesRow> vehiclesList = [];
  void addToVehiclesList(VehiclesRow item) => vehiclesList.add(item);
  void removeFromVehiclesList(VehiclesRow item) => vehiclesList.remove(item);
  void removeAtIndexFromVehiclesList(int index) => vehiclesList.removeAt(index);
  void insertAtIndexInVehiclesList(int index, VehiclesRow item) =>
      vehiclesList.insert(index, item);
  void updateVehiclesListAtIndex(int index, Function(VehiclesRow) updateFn) =>
      vehiclesList[index] = updateFn(vehiclesList[index]);

  ///  State fields for stateful widgets in this page.

  // Stores action output result for [Backend Call - Query Rows] action in FleetPage widget.
  List<VehiclesRow>? vehiclesOut;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
