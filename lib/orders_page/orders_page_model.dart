import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/index.dart';
import 'orders_page_widget.dart' show OrdersPageWidget;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class OrdersPageModel extends FlutterFlowModel<OrdersPageWidget> {
  ///  Local state fields for this page.

  List<OrdersRow> ordersList = [];
  void addToOrdersList(OrdersRow item) => ordersList.add(item);
  void removeFromOrdersList(OrdersRow item) => ordersList.remove(item);
  void removeAtIndexFromOrdersList(int index) => ordersList.removeAt(index);
  void insertAtIndexInOrdersList(int index, OrdersRow item) =>
      ordersList.insert(index, item);
  void updateOrdersListAtIndex(int index, Function(OrdersRow) updateFn) =>
      ordersList[index] = updateFn(ordersList[index]);

  List<OrdersRow> confirmedOrders = [];
  void addToConfirmedOrders(OrdersRow item) => confirmedOrders.add(item);
  void removeFromConfirmedOrders(OrdersRow item) =>
      confirmedOrders.remove(item);
  void removeAtIndexFromConfirmedOrders(int index) =>
      confirmedOrders.removeAt(index);
  void insertAtIndexInConfirmedOrders(int index, OrdersRow item) =>
      confirmedOrders.insert(index, item);
  void updateConfirmedOrdersAtIndex(int index, Function(OrdersRow) updateFn) =>
      confirmedOrders[index] = updateFn(confirmedOrders[index]);

  List<OrdersRow> doneOrders = [];
  void addToDoneOrders(OrdersRow item) => doneOrders.add(item);
  void removeFromDoneOrders(OrdersRow item) => doneOrders.remove(item);
  void removeAtIndexFromDoneOrders(int index) => doneOrders.removeAt(index);
  void insertAtIndexInDoneOrders(int index, OrdersRow item) =>
      doneOrders.insert(index, item);
  void updateDoneOrdersAtIndex(int index, Function(OrdersRow) updateFn) =>
      doneOrders[index] = updateFn(doneOrders[index]);

  List<OrdersRow> pendingOrders = [];
  void addToPendingOrders(OrdersRow item) => pendingOrders.add(item);
  void removeFromPendingOrders(OrdersRow item) => pendingOrders.remove(item);
  void removeAtIndexFromPendingOrders(int index) =>
      pendingOrders.removeAt(index);
  void insertAtIndexInPendingOrders(int index, OrdersRow item) =>
      pendingOrders.insert(index, item);
  void updatePendingOrdersAtIndex(int index, Function(OrdersRow) updateFn) =>
      pendingOrders[index] = updateFn(pendingOrders[index]);

  List<OrdersRow> cancelledOrders = [];
  void addToCancelledOrders(OrdersRow item) => cancelledOrders.add(item);
  void removeFromCancelledOrders(OrdersRow item) =>
      cancelledOrders.remove(item);
  void removeAtIndexFromCancelledOrders(int index) =>
      cancelledOrders.removeAt(index);
  void insertAtIndexInCancelledOrders(int index, OrdersRow item) =>
      cancelledOrders.insert(index, item);
  void updateCancelledOrdersAtIndex(int index, Function(OrdersRow) updateFn) =>
      cancelledOrders[index] = updateFn(cancelledOrders[index]);

  List<OrdersRow> transitOrders = [];
  void addToTransitOrders(OrdersRow item) => transitOrders.add(item);
  void removeFromTransitOrders(OrdersRow item) => transitOrders.remove(item);
  void removeAtIndexFromTransitOrders(int index) =>
      transitOrders.removeAt(index);
  void insertAtIndexInTransitOrders(int index, OrdersRow item) =>
      transitOrders.insert(index, item);
  void updateTransitOrdersAtIndex(int index, Function(OrdersRow) updateFn) =>
      transitOrders[index] = updateFn(transitOrders[index]);

  String? selectedTab = 'All';

  ///  State fields for stateful widgets in this page.

  // Stores action output result for [Backend Call - Query Rows] action in OrdersPage widget.
  List<OrdersRow>? allOut;
  // Stores action output result for [Backend Call - Query Rows] action in OrdersPage widget.
  List<OrdersRow>? pendingOut;
  // Stores action output result for [Backend Call - Query Rows] action in OrdersPage widget.
  List<OrdersRow>? confirmedOut;
  // Stores action output result for [Backend Call - Query Rows] action in OrdersPage widget.
  List<OrdersRow>? transitOut;
  // Stores action output result for [Backend Call - Query Rows] action in OrdersPage widget.
  List<OrdersRow>? doneOut;
  // Stores action output result for [Backend Call - Query Rows] action in OrdersPage widget.
  List<OrdersRow>? cancelledOut;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
