import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import 'payments_page_widget.dart' show PaymentsPageWidget;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class PaymentsPageModel extends FlutterFlowModel<PaymentsPageWidget> {
  ///  Local state fields for this page.

  List<OrdersRow> pendingList = [];
  void addToPendingList(OrdersRow item) => pendingList.add(item);
  void removeFromPendingList(OrdersRow item) => pendingList.remove(item);
  void removeAtIndexFromPendingList(int index) => pendingList.removeAt(index);
  void insertAtIndexInPendingList(int index, OrdersRow item) =>
      pendingList.insert(index, item);
  void updatePendingListAtIndex(int index, Function(OrdersRow) updateFn) =>
      pendingList[index] = updateFn(pendingList[index]);

  ///  State fields for stateful widgets in this page.

  // Stores action output result for [Backend Call - Query Rows] action in PaymentsPage widget.
  List<OrdersRow>? pendingOut;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
