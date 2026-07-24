import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'calendar_page_widget.dart' show CalendarPageWidget;
import 'package:flutter/material.dart';

class CalendarPageModel extends FlutterFlowModel<CalendarPageWidget> {
  ///  Local state fields for this page.

  /// First day of the month currently shown in the grid.
  DateTime visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);

  /// Day tapped in the grid; null = show all reminders below.
  DateTime? selectedDay;

  /// Orders shown as calendar events on their move_date (like the APC
  /// reference app's calendar).
  List<OrdersRow> ordersList = [];

  List<RemindersRow> remindersList = [];
  void addToRemindersList(RemindersRow item) => remindersList.add(item);
  void removeFromRemindersList(RemindersRow item) => remindersList.remove(item);
  void removeAtIndexFromRemindersList(int index) =>
      remindersList.removeAt(index);
  void insertAtIndexInRemindersList(int index, RemindersRow item) =>
      remindersList.insert(index, item);
  void updateRemindersListAtIndex(int index, Function(RemindersRow) updateFn) =>
      remindersList[index] = updateFn(remindersList[index]);

  List<RemindersViewRow> remindersViewList = [];
  void addToRemindersViewList(RemindersViewRow item) =>
      remindersViewList.add(item);
  void removeFromRemindersViewList(RemindersViewRow item) =>
      remindersViewList.remove(item);
  void removeAtIndexFromRemindersViewList(int index) =>
      remindersViewList.removeAt(index);
  void insertAtIndexInRemindersViewList(int index, RemindersViewRow item) =>
      remindersViewList.insert(index, item);
  void updateRemindersViewListAtIndex(
          int index, Function(RemindersViewRow) updateFn) =>
      remindersViewList[index] = updateFn(remindersViewList[index]);

  ///  State fields for stateful widgets in this page.

  // Stores action output result for [Backend Call - Query Rows] action in CalendarPage widget.
  List<RemindersViewRow>? remindersViewOut;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
