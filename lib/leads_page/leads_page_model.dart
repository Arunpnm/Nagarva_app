import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/index.dart';
import 'leads_page_widget.dart' show LeadsPageWidget;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class LeadsPageModel extends FlutterFlowModel<LeadsPageWidget> {
  ///  Local state fields for this page.

  List<LeadsRow> leadsList = [];
  void addToLeadsList(LeadsRow item) => leadsList.add(item);
  void removeFromLeadsList(LeadsRow item) => leadsList.remove(item);
  void removeAtIndexFromLeadsList(int index) => leadsList.removeAt(index);
  void insertAtIndexInLeadsList(int index, LeadsRow item) =>
      leadsList.insert(index, item);
  void updateLeadsListAtIndex(int index, Function(LeadsRow) updateFn) =>
      leadsList[index] = updateFn(leadsList[index]);

  List<LeadsRow> allLeadsList = [];
  void addToAllLeadsList(LeadsRow item) => allLeadsList.add(item);
  void removeFromAllLeadsList(LeadsRow item) => allLeadsList.remove(item);
  void removeAtIndexFromAllLeadsList(int index) => allLeadsList.removeAt(index);
  void insertAtIndexInAllLeadsList(int index, LeadsRow item) =>
      allLeadsList.insert(index, item);
  void updateAllLeadsListAtIndex(int index, Function(LeadsRow) updateFn) =>
      allLeadsList[index] = updateFn(allLeadsList[index]);

  List<LeadsRow> newLeadsList = [];
  void addToNewLeadsList(LeadsRow item) => newLeadsList.add(item);
  void removeFromNewLeadsList(LeadsRow item) => newLeadsList.remove(item);
  void removeAtIndexFromNewLeadsList(int index) => newLeadsList.removeAt(index);
  void insertAtIndexInNewLeadsList(int index, LeadsRow item) =>
      newLeadsList.insert(index, item);
  void updateNewLeadsListAtIndex(int index, Function(LeadsRow) updateFn) =>
      newLeadsList[index] = updateFn(newLeadsList[index]);

  List<LeadsRow> contactedLeadsList = [];
  void addToContactedLeadsList(LeadsRow item) => contactedLeadsList.add(item);
  void removeFromContactedLeadsList(LeadsRow item) =>
      contactedLeadsList.remove(item);
  void removeAtIndexFromContactedLeadsList(int index) =>
      contactedLeadsList.removeAt(index);
  void insertAtIndexInContactedLeadsList(int index, LeadsRow item) =>
      contactedLeadsList.insert(index, item);
  void updateContactedLeadsListAtIndex(
          int index, Function(LeadsRow) updateFn) =>
      contactedLeadsList[index] = updateFn(contactedLeadsList[index]);

  List<LeadsRow> qualifiedLeadsList = [];
  void addToQualifiedLeadsList(LeadsRow item) => qualifiedLeadsList.add(item);
  void removeFromQualifiedLeadsList(LeadsRow item) =>
      qualifiedLeadsList.remove(item);
  void removeAtIndexFromQualifiedLeadsList(int index) =>
      qualifiedLeadsList.removeAt(index);
  void insertAtIndexInQualifiedLeadsList(int index, LeadsRow item) =>
      qualifiedLeadsList.insert(index, item);
  void updateQualifiedLeadsListAtIndex(
          int index, Function(LeadsRow) updateFn) =>
      qualifiedLeadsList[index] = updateFn(qualifiedLeadsList[index]);

  List<LeadsRow> wonLeadsList = [];
  void addToWonLeadsList(LeadsRow item) => wonLeadsList.add(item);
  void removeFromWonLeadsList(LeadsRow item) => wonLeadsList.remove(item);
  void removeAtIndexFromWonLeadsList(int index) => wonLeadsList.removeAt(index);
  void insertAtIndexInWonLeadsList(int index, LeadsRow item) =>
      wonLeadsList.insert(index, item);
  void updateWonLeadsListAtIndex(int index, Function(LeadsRow) updateFn) =>
      wonLeadsList[index] = updateFn(wonLeadsList[index]);

  List<LeadsRow> lostLeadsList = [];
  void addToLostLeadsList(LeadsRow item) => lostLeadsList.add(item);
  void removeFromLostLeadsList(LeadsRow item) => lostLeadsList.remove(item);
  void removeAtIndexFromLostLeadsList(int index) =>
      lostLeadsList.removeAt(index);
  void insertAtIndexInLostLeadsList(int index, LeadsRow item) =>
      lostLeadsList.insert(index, item);
  void updateLostLeadsListAtIndex(int index, Function(LeadsRow) updateFn) =>
      lostLeadsList[index] = updateFn(lostLeadsList[index]);

  String? leadsFilter = 'all';

  ///  State fields for stateful widgets in this page.

  // Stores action output result for [Backend Call - Query Rows] action in LeadsPage widget.
  List<LeadsRow>? leadsAllOut;
  // Stores action output result for [Backend Call - Query Rows] action in LeadsPage widget.
  List<LeadsRow>? leadsNewOut;
  // Stores action output result for [Backend Call - Query Rows] action in LeadsPage widget.
  List<LeadsRow>? leadsContactedOut;
  // Stores action output result for [Backend Call - Query Rows] action in LeadsPage widget.
  List<LeadsRow>? leadsQualifiedOut;
  // Stores action output result for [Backend Call - Query Rows] action in LeadsPage widget.
  List<LeadsRow>? leadsWonOut;
  // Stores action output result for [Backend Call - Query Rows] action in LeadsPage widget.
  List<LeadsRow>? leadsLostOut;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
