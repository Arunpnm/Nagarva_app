import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import 'calendar_page_widget.dart' show CalendarPageWidget;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class CalendarPageModel extends FlutterFlowModel<CalendarPageWidget> {
  ///  Local state fields for this page.

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
