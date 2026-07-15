import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'fleet_page_widget.dart' show FleetPageWidget;
import 'package:flutter/material.dart';

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
