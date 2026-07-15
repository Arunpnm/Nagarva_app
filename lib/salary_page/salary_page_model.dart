import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import 'salary_page_widget.dart' show SalaryPageWidget;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class SalaryPageModel extends FlutterFlowModel<SalaryPageWidget> {
  ///  Local state fields for this page.

  List<StaffRow> staffList = [];
  void addToStaffList(StaffRow item) => staffList.add(item);
  void removeFromStaffList(StaffRow item) => staffList.remove(item);
  void removeAtIndexFromStaffList(int index) => staffList.removeAt(index);
  void insertAtIndexInStaffList(int index, StaffRow item) =>
      staffList.insert(index, item);
  void updateStaffListAtIndex(int index, Function(StaffRow) updateFn) =>
      staffList[index] = updateFn(staffList[index]);

  List<AttendanceRow> attendanceList = [];
  void addToAttendanceList(AttendanceRow item) => attendanceList.add(item);
  void removeFromAttendanceList(AttendanceRow item) =>
      attendanceList.remove(item);
  void removeAtIndexFromAttendanceList(int index) =>
      attendanceList.removeAt(index);
  void insertAtIndexInAttendanceList(int index, AttendanceRow item) =>
      attendanceList.insert(index, item);
  void updateAttendanceListAtIndex(
          int index, Function(AttendanceRow) updateFn) =>
      attendanceList[index] = updateFn(attendanceList[index]);

  List<StaffAdvancesRow> advancesList = [];
  void addToAdvancesList(StaffAdvancesRow item) => advancesList.add(item);
  void removeFromAdvancesList(StaffAdvancesRow item) =>
      advancesList.remove(item);
  void removeAtIndexFromAdvancesList(int index) => advancesList.removeAt(index);
  void insertAtIndexInAdvancesList(int index, StaffAdvancesRow item) =>
      advancesList.insert(index, item);
  void updateAdvancesListAtIndex(
          int index, Function(StaffAdvancesRow) updateFn) =>
      advancesList[index] = updateFn(advancesList[index]);

  List<AttendanceViewRow> attendanceViewList = [];
  void addToAttendanceViewList(AttendanceViewRow item) =>
      attendanceViewList.add(item);
  void removeFromAttendanceViewList(AttendanceViewRow item) =>
      attendanceViewList.remove(item);
  void removeAtIndexFromAttendanceViewList(int index) =>
      attendanceViewList.removeAt(index);
  void insertAtIndexInAttendanceViewList(int index, AttendanceViewRow item) =>
      attendanceViewList.insert(index, item);
  void updateAttendanceViewListAtIndex(
          int index, Function(AttendanceViewRow) updateFn) =>
      attendanceViewList[index] = updateFn(attendanceViewList[index]);

  List<AdvancesViewRow> advancesViewList = [];
  void addToAdvancesViewList(AdvancesViewRow item) =>
      advancesViewList.add(item);
  void removeFromAdvancesViewList(AdvancesViewRow item) =>
      advancesViewList.remove(item);
  void removeAtIndexFromAdvancesViewList(int index) =>
      advancesViewList.removeAt(index);
  void insertAtIndexInAdvancesViewList(int index, AdvancesViewRow item) =>
      advancesViewList.insert(index, item);
  void updateAdvancesViewListAtIndex(
          int index, Function(AdvancesViewRow) updateFn) =>
      advancesViewList[index] = updateFn(advancesViewList[index]);

  ///  State fields for stateful widgets in this page.

  // Stores action output result for [Backend Call - Query Rows] action in SalaryPage widget.
  List<AttendanceViewRow>? attendanceViewOut;
  // Stores action output result for [Backend Call - Query Rows] action in SalaryPage widget.
  List<AdvancesViewRow>? advancesViewOut;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
