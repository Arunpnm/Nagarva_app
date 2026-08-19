import 'dart:math';

import '/config/app_config.dart';
import '/backend/lead_status.dart';
import '/backend/reminders_service.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/components/keyboard_scroll_view.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import 'leads_page_model.dart';
export 'leads_page_model.dart';

/// Same scheme as lead_detail_page_widget.dart's `_generateHexToken` —
/// surveys.token has no working DB default.
String _generateSurveyToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// CRM lead pipeline for Arun Packers.
class LeadsPageWidget extends StatefulWidget {
  const LeadsPageWidget({super.key});

  static String routeName = 'LeadsPage';
  static String routePath = '/leads';

  @override
  State<LeadsPageWidget> createState() => _LeadsPageWidgetState();
}

class _LeadsPageWidgetState extends State<LeadsPageWidget>
    with RefreshOnPopMixin<LeadsPageWidget> {
  late LeadsPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => LeadsPageModel());

    // On page load action.
    SchedulerBinding.instance.addPostFrameCallback((_) => _loadLeads());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  // Refresh-after-write fix (parity brief Part 1): re-run on load and every
  // time a pushed route (New/Edit Lead, Lead Detail) is popped back to.
  @override
  void onPageRefresh() => _loadLeads();

  Future<void> _loadLeads() async {
    // Phase 1 multi-tenancy pass: every tab below was unscoped. Requires
    // supabase/phase1_add_org_id.sql to be run first.
    _model.leadsAllOut = await LeadsTable().queryRows(
      queryFn: (q) => OrgScope.read(q).order('created_at'),
    );
    _model.leadsList = (_model.leadsAllOut ?? []).toList().cast<LeadsRow>();
    safeSetState(() {});
    _model.allLeadsList = (_model.leadsAllOut ?? []).toList().cast<LeadsRow>();
    safeSetState(() {});
    // Live-test fix brief #2, item 5: every tab below matched a single
    // hand-written status string, and the "Won" tab's string was
    // 'converted' while Convert to Order actually writes 'confirmed' — so
    // won leads never appeared in it. Tabs now match against the canonical
    // value PLUS its known legacy spellings (leadStatusMatchValues), so
    // they are correct whether or not
    // supabase/20260728_lead_status_canonical.sql has been run yet.
    _model.leadsNewOut = await LeadsTable().queryRows(
      queryFn: (q) => OrgScope
          .read(q)
          .inFilter('status', leadStatusMatchValues(kLeadStatusNew)),
    );
    _model.newLeadsList = (_model.leadsNewOut ?? []).toList().cast<LeadsRow>();
    safeSetState(() {});
    _model.leadsContactedOut = await LeadsTable().queryRows(
      queryFn: (q) => OrgScope
          .read(q)
          .inFilter('status', leadStatusMatchValues(kLeadStatusFollowUp)),
    );
    _model.contactedLeadsList =
        (_model.leadsContactedOut ?? []).toList().cast<LeadsRow>();
    safeSetState(() {});
    _model.leadsQualifiedOut = await LeadsTable().queryRows(
      queryFn: (q) => OrgScope.read(q).inFilter('status', [
        ...leadStatusMatchValues(kLeadStatusSurveyDone),
        ...leadStatusMatchValues(kLeadStatusQuoted),
      ]),
    );
    _model.qualifiedLeadsList =
        (_model.leadsQualifiedOut ?? []).toList().cast<LeadsRow>();
    safeSetState(() {});
    _model.leadsWonOut = await LeadsTable().queryRows(
      queryFn: (q) => OrgScope
          .read(q)
          .inFilter('status', leadStatusMatchValues(kLeadStatusConfirmed)),
    );
    _model.wonLeadsList = (_model.leadsWonOut ?? []).toList().cast<LeadsRow>();
    safeSetState(() {});
    _model.leadsLostOut = await LeadsTable().queryRows(
      queryFn: (q) => OrgScope
          .read(q)
          .inFilter('status', leadStatusMatchValues(kLeadStatusLost)),
    );
    _model.lostLeadsList =
        (_model.leadsLostOut ?? []).toList().cast<LeadsRow>();
    safeSetState(() {});

    // Item 10.5: which leads have an overdue follow-up. One query for the
    // whole list rather than per row.
    final overdue = await RemindersService.overdueEntityIds(kEntityLead);
    if (mounted) safeSetState(() => _overdueLeadIds = overdue);

    // Leads whose customer has actually submitted the survey. Without
    // this a vendor has to open every lead to discover a response came
    // in, which is the difference between the survey link being useful
    // and being ignored. One query for the whole list, not per row.
    try {
      final submitted = await SurveysTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('status', 'submitted'),
      );
      if (mounted) {
        safeSetState(() => _surveyRespondedLeadIds = {
              for (final s in submitted)
                if (s.leadId != null) s.leadId!,
            });
      }
    } catch (_) {
      // Badge is supplemental — never block the list over it.
    }
  }

  /// Lead ids with a submitted customer survey — drives the list badge.
  Set<String> _surveyRespondedLeadIds = {};

  /// Lead ids with at least one overdue reminder — drives the list badge.
  Set<String> _overdueLeadIds = {};

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  // Parity brief Part 4b: LeadDetailPage already had "Request Survey"
  // (see its _requestSurvey) — the missing piece was a quick entry point
  // right on the list card, without needing to open the full detail page
  // first. surveys.lead_id is uuid (matches LeadsRow.id's type).
  bool _generatingSurveyFor(String? leadId) =>
      leadId != null && _model.surveyLinkLoadingLeadId == leadId;

  Future<void> _quickSurveyLink(LeadsRow lead) async {
    if (lead.id == null) return;
    safeSetState(() => _model.surveyLinkLoadingLeadId = lead.id);
    try {
      final row = await SurveysTable().insert({
        'id': const Uuid().v4(),
        'token': _generateSurveyToken(),
        ...OrgScope.stamp(),
        'lead_id': lead.id,
        'customer_name': lead.customer,
        'customer_phone': lead.phone ?? '',
        'from_address': lead.fromCity ?? '',
        'to_address': lead.toCity ?? '',
      });
      // Not Uri.base.origin — that is file:/// inside an APK and throws.
      // See kPublicBaseUrl in lib/config/app_config.dart.
      final link = buildTokenLink('/survey', row.token);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Survey link created'),
          content: SelectableText(link),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: link));
                Navigator.of(context).pop();
              },
              child: const Text('Copy & close'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create survey link: $e')),
        );
      }
    } finally {
      if (mounted) safeSetState(() => _model.surveyLinkLoadingLeadId = null);
    }
  }

  /// Corrections session, B3 (7 Aug 2026): was a bare hardcoded stat
  /// value/label pair — see the class doc comment for the fake-numbers
  /// history this replaces.
  Widget _statTile(BuildContext context, String value, String label) {
    return Flexible(
      flex: 1,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(0.0, 10.0, 0.0, 10.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                value,
                style: FlutterFlowTheme.of(context).titleMedium.override(
                      font: GoogleFonts.interTight(),
                      color: FlutterFlowTheme.of(context).primary,
                      letterSpacing: 0.0,
                    ),
              ),
              Text(
                label,
                style: FlutterFlowTheme.of(context).labelSmall.override(
                      font: GoogleFonts.inter(),
                      color: FlutterFlowTheme.of(context).secondaryText,
                      letterSpacing: 0.0,
                    ),
              ),
            ].divide(const SizedBox(height: 2.0)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            context.pushNamed(NewLeadPageWidget.routeName);
          },
          backgroundColor: FlutterFlowTheme.of(context).primary,
          tooltip: 'New Lead',
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          automaticallyImplyLeading: true,
          title: Text(
            FFLocalizations.of(context).getText(
              'fw8x20a4' /* Leads / CRM */,
            ),
            style: FlutterFlowTheme.of(context).titleLarge.override(
                  font: GoogleFonts.interTight(
                    fontWeight: FontWeight.w600,
                    fontStyle:
                        FlutterFlowTheme.of(context).titleLarge.fontStyle,
                  ),
                  fontSize: 22.0,
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.w600,
                  fontStyle: FlutterFlowTheme.of(context).titleLarge.fontStyle,
                ),
          ),
          actions: const [],
          centerTitle: true,
          elevation: 0.0,
        ),
        body: SafeArea(
          top: true,
          child: Container(
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).primaryBackground,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: KeyboardScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Corrections session, B3: New/Contacted/Qualified/Won
                    // is this page's OWN already-established bucket
                    // vocabulary — not invented here. _loadLeads() above
                    // already runs the exact same New/FollowUp/(SurveyDone+
                    // Quoted)/Confirmed queries for the tab lists below;
                    // these cards just read the lengths of those
                    // already-loaded lists instead of the old hardcoded
                    // 8/5/3/2.
                    Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _statTile(
                            context, '${_model.newLeadsList.length}', 'New'),
                        _statTile(context, '${_model.contactedLeadsList.length}',
                            'Contacted'),
                        _statTile(context, '${_model.qualifiedLeadsList.length}',
                            'Qualified'),
                        _statTile(
                            context, '${_model.wonLeadsList.length}', 'Won'),
                      ].divide(const SizedBox(width: 10.0)),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              flex: 1,
                              child: InkWell(
                                splashColor: Colors.transparent,
                                focusColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                onTap: () async {
                                  _model.leadsFilter = 'all';
                                  safeSetState(() {});
                                  _model.leadsList = _model.allLeadsList
                                      .toList()
                                      .cast<LeadsRow>();
                                  safeSetState(() {});
                                },
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: FlutterFlowTheme.of(context)
                                        .secondaryBackground,
                                    borderRadius: BorderRadius.circular(10.0),
                                  ),
                                  child: Padding(
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            0.0, 10.0, 0.0, 10.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          FFLocalizations.of(context).getText(
                                            'w3m6agqx' /* All */,
                                          ),
                                          style: FlutterFlowTheme.of(context)
                                              .labelMedium
                                              .override(
                                                font: GoogleFonts.inter(
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .labelMedium
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .labelMedium
                                                          .fontStyle,
                                                ),
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primaryText,
                                                letterSpacing: 0.0,
                                                fontWeight:
                                                    FlutterFlowTheme.of(context)
                                                        .labelMedium
                                                        .fontWeight,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .labelMedium
                                                        .fontStyle,
                                              ),
                                        ),
                                      ].divide(const SizedBox(height: 2.0)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Flexible(
                              flex: 1,
                              child: InkWell(
                                splashColor: Colors.transparent,
                                focusColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                onTap: () async {
                                  _model.leadsFilter = 'new';
                                  safeSetState(() {});
                                  _model.leadsList = _model.newLeadsList
                                      .toList()
                                      .cast<LeadsRow>();
                                  safeSetState(() {});
                                },
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: FlutterFlowTheme.of(context)
                                        .secondaryBackground,
                                    borderRadius: BorderRadius.circular(10.0),
                                  ),
                                  child: Padding(
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            0.0, 10.0, 0.0, 10.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          FFLocalizations.of(context).getText(
                                            '8kixhsec' /* New */,
                                          ),
                                          style: FlutterFlowTheme.of(context)
                                              .labelMedium
                                              .override(
                                                font: GoogleFonts.inter(
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .labelMedium
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .labelMedium
                                                          .fontStyle,
                                                ),
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primaryText,
                                                letterSpacing: 0.0,
                                                fontWeight:
                                                    FlutterFlowTheme.of(context)
                                                        .labelMedium
                                                        .fontWeight,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .labelMedium
                                                        .fontStyle,
                                              ),
                                        ),
                                      ].divide(const SizedBox(height: 2.0)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Flexible(
                              flex: 1,
                              child: InkWell(
                                splashColor: Colors.transparent,
                                focusColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                onTap: () async {
                                  _model.leadsFilter = 'contacted';
                                  safeSetState(() {});
                                  _model.leadsList = _model.contactedLeadsList
                                      .toList()
                                      .cast<LeadsRow>();
                                  safeSetState(() {});
                                },
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: FlutterFlowTheme.of(context)
                                        .secondaryBackground,
                                    borderRadius: BorderRadius.circular(10.0),
                                  ),
                                  child: Padding(
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            0.0, 10.0, 0.0, 10.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          FFLocalizations.of(context).getText(
                                            'jt2ja9lh' /* Contacted */,
                                          ),
                                          style: FlutterFlowTheme.of(context)
                                              .labelMedium
                                              .override(
                                                font: GoogleFonts.inter(
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .labelMedium
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .labelMedium
                                                          .fontStyle,
                                                ),
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primaryText,
                                                letterSpacing: 0.0,
                                                fontWeight:
                                                    FlutterFlowTheme.of(context)
                                                        .labelMedium
                                                        .fontWeight,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .labelMedium
                                                        .fontStyle,
                                              ),
                                        ),
                                      ].divide(const SizedBox(height: 2.0)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Flexible(
                              flex: 1,
                              child: InkWell(
                                splashColor: Colors.transparent,
                                focusColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                onTap: () async {
                                  _model.leadsFilter = 'qualified';
                                  safeSetState(() {});
                                  _model.leadsList = _model.qualifiedLeadsList
                                      .toList()
                                      .cast<LeadsRow>();
                                  safeSetState(() {});
                                },
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: FlutterFlowTheme.of(context)
                                        .secondaryBackground,
                                    borderRadius: BorderRadius.circular(10.0),
                                  ),
                                  child: Padding(
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            0.0, 10.0, 0.0, 10.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          FFLocalizations.of(context).getText(
                                            'upw43toz' /* Qualified */,
                                          ),
                                          style: FlutterFlowTheme.of(context)
                                              .labelMedium
                                              .override(
                                                font: GoogleFonts.inter(
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .labelMedium
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .labelMedium
                                                          .fontStyle,
                                                ),
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primaryText,
                                                letterSpacing: 0.0,
                                                fontWeight:
                                                    FlutterFlowTheme.of(context)
                                                        .labelMedium
                                                        .fontWeight,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .labelMedium
                                                        .fontStyle,
                                              ),
                                        ),
                                      ].divide(const SizedBox(height: 2.0)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Flexible(
                              flex: 1,
                              child: InkWell(
                                splashColor: Colors.transparent,
                                focusColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                onTap: () async {
                                  _model.leadsFilter = 'won';
                                  safeSetState(() {});
                                  _model.leadsList = _model.wonLeadsList
                                      .toList()
                                      .cast<LeadsRow>();
                                  safeSetState(() {});
                                },
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: FlutterFlowTheme.of(context)
                                        .secondaryBackground,
                                    borderRadius: BorderRadius.circular(10.0),
                                  ),
                                  child: Padding(
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            0.0, 10.0, 0.0, 10.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          FFLocalizations.of(context).getText(
                                            'go6fnsk1' /* Won */,
                                          ),
                                          style: FlutterFlowTheme.of(context)
                                              .labelMedium
                                              .override(
                                                font: GoogleFonts.inter(
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .labelMedium
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .labelMedium
                                                          .fontStyle,
                                                ),
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primaryText,
                                                letterSpacing: 0.0,
                                                fontWeight:
                                                    FlutterFlowTheme.of(context)
                                                        .labelMedium
                                                        .fontWeight,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .labelMedium
                                                        .fontStyle,
                                              ),
                                        ),
                                      ].divide(const SizedBox(height: 2.0)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Flexible(
                              flex: 1,
                              child: InkWell(
                                splashColor: Colors.transparent,
                                focusColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                onTap: () async {
                                  _model.leadsFilter = 'lost';
                                  safeSetState(() {});
                                  _model.leadsList = _model.lostLeadsList
                                      .toList()
                                      .cast<LeadsRow>();
                                  safeSetState(() {});
                                },
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: FlutterFlowTheme.of(context)
                                        .secondaryBackground,
                                    borderRadius: BorderRadius.circular(10.0),
                                  ),
                                  child: Padding(
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            0.0, 10.0, 0.0, 10.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          FFLocalizations.of(context).getText(
                                            'hedb3sg1' /* Lost */,
                                          ),
                                          style: FlutterFlowTheme.of(context)
                                              .labelMedium
                                              .override(
                                                font: GoogleFonts.inter(
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .labelMedium
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .labelMedium
                                                          .fontStyle,
                                                ),
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primaryText,
                                                letterSpacing: 0.0,
                                                fontWeight:
                                                    FlutterFlowTheme.of(context)
                                                        .labelMedium
                                                        .fontWeight,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .labelMedium
                                                        .fontStyle,
                                              ),
                                        ),
                                      ].divide(const SizedBox(height: 2.0)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ].divide(const SizedBox(width: 6.0)),
                        ),
                        Text(
                          FFLocalizations.of(context).getText(
                            'wknufr5y' /* Leads */,
                          ),
                          style:
                              FlutterFlowTheme.of(context).titleSmall.override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .titleSmall
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .titleSmall
                                          .fontStyle,
                                    ),
                                    color: FlutterFlowTheme.of(context).primary,
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .titleSmall
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .titleSmall
                                        .fontStyle,
                                  ),
                        ),
                        Builder(
                          builder: (context) {
                            final leadsListItem = _model.leadsList.toList();

                            // Empty state (18 Aug 2026). Until now this
                            // builder rendered nothing at all for an empty
                            // list — and directly below it sat four
                            // hardcoded FlutterFlow mockup cards (Ravi
                            // Menon, Deepa Nair, Karthik S., Meena Raj)
                            // that were never removed when the real list
                            // was wired. A brand-new vendor therefore saw
                            // four invented customers with invented phone
                            // numbers on their first visit to Leads, while
                            // the KPI row above correctly read 0/0/0/0.
                            // Mockup block deleted; this replaces it.
                            if (leadsListItem.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 36, horizontal: 16),
                                child: Column(
                                  children: [
                                    Icon(Icons.person_search_outlined,
                                        size: 42,
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No leads yet',
                                      style: GoogleFonts.interTight(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: FlutterFlowTheme.of(context)
                                            .primaryText,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Add your first enquiry with the + button '
                                      'and it will show up here.',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        height: 1.4,
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return ListView.separated(
                              padding: EdgeInsets.zero,
                              primary: false,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              scrollDirection: Axis.vertical,
                              itemCount: leadsListItem.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12.0),
                              itemBuilder: (context, leadsListItemIndex) {
                                final leadsListItemItem =
                                    leadsListItem[leadsListItemIndex];
                                return InkWell(
                                  splashColor: Colors.transparent,
                                  focusColor: Colors.transparent,
                                  hoverColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
                                  onTap: () async {
                                    context.pushNamed(
                                      LeadDetailPageWidget.routeName,
                                      queryParameters: {
                                        'leadId': serializeParam(
                                          leadsListItemItem.id,
                                          ParamType.String,
                                        ),
                                        'leadCustomer': serializeParam(
                                          leadsListItemItem.customer,
                                          ParamType.String,
                                        ),
                                        'leadPhone': serializeParam(
                                          leadsListItemItem.phone,
                                          ParamType.String,
                                        ),
                                        'leadEmail': serializeParam(
                                          leadsListItemItem.email,
                                          ParamType.String,
                                        ),
                                        'leadFromCity': serializeParam(
                                          leadsListItemItem.fromCity,
                                          ParamType.String,
                                        ),
                                        'leadToCity': serializeParam(
                                          leadsListItemItem.toCity,
                                          ParamType.String,
                                        ),
                                        'leadApproxDate': serializeParam(
                                          leadsListItemItem.approxDate,
                                          ParamType.String,
                                        ),
                                        'leadService': serializeParam(
                                          leadsListItemItem.service,
                                          ParamType.String,
                                        ),
                                        'leadSource': serializeParam(
                                          leadsListItemItem.source,
                                          ParamType.String,
                                        ),
                                        'leadStatus': serializeParam(
                                          leadsListItemItem.status,
                                          ParamType.String,
                                        ),
                                        'leadBranch': serializeParam(
                                          leadsListItemItem.branch,
                                          ParamType.String,
                                        ),
                                        'leadNotes': serializeParam(
                                          leadsListItemItem.notes,
                                          ParamType.String,
                                        ),
                                      }.withoutNulls,
                                    );
                                  },
                                  child: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryBackground,
                                      borderRadius: BorderRadius.circular(12.0),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.max,
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Column(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                leadsListItemItem.customer,
                                                style:
                                                    FlutterFlowTheme.of(context)
                                                        .titleSmall
                                                        .override(
                                                          font: GoogleFonts
                                                              .interTight(
                                                            fontWeight:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleSmall
                                                                    .fontWeight,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .titleSmall
                                                                    .fontStyle,
                                                          ),
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .primaryText,
                                                          letterSpacing: 0.0,
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .titleSmall
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .titleSmall
                                                                  .fontStyle,
                                                        ),
                                              ),
                                              Text(
                                                leadsListItemItem.phone ?? '-',
                                                style: FlutterFlowTheme.of(
                                                        context)
                                                    .bodySmall
                                                    .override(
                                                      font: GoogleFonts.inter(
                                                        fontWeight:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodySmall
                                                                .fontWeight,
                                                        fontStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodySmall
                                                                .fontStyle,
                                                      ),
                                                      color:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .secondaryText,
                                                      letterSpacing: 0.0,
                                                      fontWeight:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .bodySmall
                                                              .fontWeight,
                                                      fontStyle:
                                                          FlutterFlowTheme.of(
                                                                  context)
                                                              .bodySmall
                                                              .fontStyle,
                                                    ),
                                              ),
                                              Row(
                                                mainAxisSize: MainAxisSize.max,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    leadsListItemItem
                                                            .fromCity ??
                                                        '-',
                                                    style: FlutterFlowTheme.of(
                                                            context)
                                                        .bodySmall
                                                        .override(
                                                          font:
                                                              GoogleFonts.inter(
                                                            fontWeight:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodySmall
                                                                    .fontWeight,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodySmall
                                                                    .fontStyle,
                                                          ),
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .secondaryText,
                                                          letterSpacing: 0.0,
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodySmall
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodySmall
                                                                  .fontStyle,
                                                        ),
                                                  ),
                                                  Icon(
                                                    Icons.arrow_forward,
                                                    color: FlutterFlowTheme.of(
                                                            context)
                                                        .secondaryText,
                                                    size: 12.0,
                                                  ),
                                                  Text(
                                                    leadsListItemItem.toCity ??
                                                        '-',
                                                    style: FlutterFlowTheme.of(
                                                            context)
                                                        .bodySmall
                                                        .override(
                                                          font:
                                                              GoogleFonts.inter(
                                                            fontWeight:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodySmall
                                                                    .fontWeight,
                                                            fontStyle:
                                                                FlutterFlowTheme.of(
                                                                        context)
                                                                    .bodySmall
                                                                    .fontStyle,
                                                          ),
                                                          color: FlutterFlowTheme
                                                                  .of(context)
                                                              .secondaryText,
                                                          letterSpacing: 0.0,
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodySmall
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodySmall
                                                                  .fontStyle,
                                                        ),
                                                  ),
                                                ].divide(
                                                    const SizedBox(width: 4.0)),
                                              ),
                                            ].divide(
                                                const SizedBox(height: 4.0)),
                                          ),
                                          // Item 10.5: overdue follow-up
                                          // badge, so the list itself
                                          // shows which leads are going
                                          // quiet.
                                          // Survey response waiting to
                                          // be quoted.
                                          if (_surveyRespondedLeadIds
                                              .contains(leadsListItemItem.id))
                                            Padding(
                                              padding:
                                                  const EdgeInsetsDirectional
                                                      .fromSTEB(0, 0, 6, 0),
                                              child: Tooltip(
                                                message:
                                                    'Survey response received',
                                                child: Icon(
                                                  Icons
                                                      .assignment_turned_in,
                                                  size: 18,
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .tertiary,
                                                ),
                                              ),
                                            ),
                                          if (_overdueLeadIds
                                              .contains(leadsListItemItem.id))
                                            Padding(
                                              padding:
                                                  const EdgeInsetsDirectional
                                                      .fromSTEB(
                                                      0, 0, 6, 0),
                                              child: Tooltip(
                                                message:
                                                    'Follow-up overdue',
                                                child: Icon(
                                                  Icons
                                                      .notification_important,
                                                  size: 18,
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .error,
                                                ),
                                              ),
                                            ),
                                          // Item 5.5: was a raw
                                          // `status ?? '-'` in a single
                                          // flat colour. Now canonicalised
                                          // (so legacy 'contacted'/
                                          // 'converted' rows read
                                          // correctly) and tinted per
                                          // stage.
                                          Container(
                                            decoration: BoxDecoration(
                                              color: leadStatusColor(
                                                      leadsListItemItem.status)
                                                  .withValues(alpha: 0.14),
                                              borderRadius:
                                                  BorderRadius.circular(12.0),
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsetsDirectional
                                                      .fromSTEB(
                                                      10.0, 4.0, 10.0, 4.0),
                                              child: Text(
                                                leadStatusLabel(
                                                    leadsListItemItem.status),
                                                style: GoogleFonts.inter(
                                                  fontSize: 11.0,
                                                  fontWeight: FontWeight.w700,
                                                  color: leadStatusColor(
                                                      leadsListItemItem.status),
                                                ),
                                              ),
                                            ),
                                          ),
                                          // Parity brief Part 4b: quick
                                          // "Generate Survey Link" right on
                                          // the card — LeadDetailPage's
                                          // "Request Survey" already
                                          // covered the detail-page half.
                                          SizedBox(
                                            width: 48,
                                            height: 48,
                                            child:
                                                _generatingSurveyFor(
                                                        leadsListItemItem.id)
                                                    ? const Padding(
                                                        padding:
                                                            EdgeInsets.all(
                                                                14),
                                                        child:
                                                            CircularProgressIndicator(
                                                                strokeWidth:
                                                                    2),
                                                      )
                                                    : IconButton(
                                                        tooltip:
                                                            'Generate Survey Link',
                                                        icon: const Icon(
                                                            Icons
                                                                .assignment_outlined,
                                                            size: 20),
                                                        onPressed: () =>
                                                            _quickSurveyLink(
                                                                leadsListItemItem),
                                                      ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ].divide(const SizedBox(height: 12.0)),
                    ),
                  ].divide(const SizedBox(height: 16.0)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
