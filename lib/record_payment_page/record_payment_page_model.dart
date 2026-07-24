import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'record_payment_page_widget.dart' show RecordPaymentPageWidget;
import 'package:flutter/material.dart';

/// Week 3a rewrite: payments are now payment_entries rows (part-payments
/// with mode), not blind overwrites of orders.advance_paid. Old dropdown/
/// status fields removed — payment_status is trigger-maintained.
class RecordPaymentPageModel extends FlutterFlowModel<RecordPaymentPageWidget> {
  /// Orders that still have a balance due.
  List<OrdersRow> unpaidOrders = [];

  /// Currently selected order (null until picked).
  OrdersRow? selected;

  /// Payment history for the selected order.
  List<PaymentEntriesRow> history = [];

  /// cash | upi | bank
  String mode = 'cash';

  bool loading = true;
  bool saving = false;

  FocusNode? amountFocusNode;
  TextEditingController? amountController;
  FocusNode? noteFocusNode;
  TextEditingController? noteController;

  @override
  void initState(BuildContext context) {
    amountController = TextEditingController();
    amountFocusNode = FocusNode();
    noteController = TextEditingController();
    noteFocusNode = FocusNode();
  }

  @override
  void dispose() {
    amountFocusNode?.dispose();
    amountController?.dispose();
    noteFocusNode?.dispose();
    noteController?.dispose();
  }
}
