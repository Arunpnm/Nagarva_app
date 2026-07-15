import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'expense_page_widget.dart' show ExpensePageWidget;
import 'package:flutter/material.dart';

class ExpensePageModel extends FlutterFlowModel<ExpensePageWidget> {
  ///  Local state fields for this page.

  List<ExpensesRow> expensesList = [];
  void addToExpensesList(ExpensesRow item) => expensesList.add(item);
  void removeFromExpensesList(ExpensesRow item) => expensesList.remove(item);
  void removeAtIndexFromExpensesList(int index) => expensesList.removeAt(index);
  void insertAtIndexInExpensesList(int index, ExpensesRow item) =>
      expensesList.insert(index, item);
  void updateExpensesListAtIndex(int index, Function(ExpensesRow) updateFn) =>
      expensesList[index] = updateFn(expensesList[index]);

  ///  State fields for stateful widgets in this page.

  // Stores action output result for [Backend Call - Query Rows] action in ExpensePage widget.
  List<ExpensesRow>? expensesOut;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
