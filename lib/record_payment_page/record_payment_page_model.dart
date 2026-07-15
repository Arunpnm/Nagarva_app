import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/form_field_controller.dart';
import 'record_payment_page_widget.dart' show RecordPaymentPageWidget;
import 'package:flutter/material.dart';

class RecordPaymentPageModel extends FlutterFlowModel<RecordPaymentPageWidget> {
  ///  Local state fields for this page.

  List<OrdersRow> pendingPayOrders = [];
  void addToPendingPayOrders(OrdersRow item) => pendingPayOrders.add(item);
  void removeFromPendingPayOrders(OrdersRow item) =>
      pendingPayOrders.remove(item);
  void removeAtIndexFromPendingPayOrders(int index) =>
      pendingPayOrders.removeAt(index);
  void insertAtIndexInPendingPayOrders(int index, OrdersRow item) =>
      pendingPayOrders.insert(index, item);
  void updatePendingPayOrdersAtIndex(int index, Function(OrdersRow) updateFn) =>
      pendingPayOrders[index] = updateFn(pendingPayOrders[index]);

  String? selectedPayOrderId = '';

  String? selectedPayCustomer = '';

  String? selectedPayTotalAmount = '';

  String? selectedPayAdvancePaid = '';

  String? newPayStatus = 'partial';

  ///  State fields for stateful widgets in this page.

  // Stores action output result for [Backend Call - Query Rows] action in RecordPaymentPage widget.
  List<OrdersRow>? pendingPayOut;
  // State field(s) for PayAmountField widget.
  FocusNode? payAmountFieldFocusNode;
  TextEditingController? payAmountFieldTextController;
  String? Function(BuildContext, String?)?
      payAmountFieldTextControllerValidator;
  // State field(s) for PayStatusDropdown widget.
  String? payStatusDropdownValue;
  FormFieldController<String>? payStatusDropdownValueController;
  // Stores action output result for [Backend Call - Update Row(s)] action in SavePaymentBtn widget.
  List<OrdersRow>? rows;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    payAmountFieldFocusNode?.dispose();
    payAmountFieldTextController?.dispose();
  }
}
