import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'users_page_model.dart';
export 'users_page_model.dart';

/// Staff user management and access control.
///
/// Was an empty shell (CLAUDE.md "Empty shells" / Phase 2 roadmap item) —
/// every card here was hardcoded FlutterFlow placeholder data. Now backed by
/// the `staff` table, org-scoped via AppSession.instance.currentOrgId
/// (requires supabase/phase1_add_org_id.sql to be run first).
class UsersPageWidget extends StatefulWidget {
  const UsersPageWidget({super.key});

  static String routeName = 'UsersPage';
  static String routePath = '/users';

  @override
  State<UsersPageWidget> createState() => _UsersPageWidgetState();
}

class _UsersPageWidgetState extends State<UsersPageWidget> {
  late UsersPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => UsersPageModel());

    SchedulerBinding.instance.addPostFrameCallback((_) async {
      _model.staffOut = await StaffTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('name'),
      );
      _model.staffList = _model.staffOut!.toList().cast<StaffRow>();
      safeSetState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  List<StaffRow> get _filteredStaff {
    if (_model.roleFilter == null) return _model.staffList;
    return _model.staffList
        .where((s) => (s.role ?? '').toLowerCase() == _model.roleFilter)
        .toList();
  }

  Widget _roleChip(BuildContext context, String label, String? value) {
    final selected = _model.roleFilter == value;
    return Flexible(
      flex: 1,
      child: GestureDetector(
        onTap: () => safeSetState(() => _model.roleFilter = value),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: selected
                ? FlutterFlowTheme.of(context).primary
                : FlutterFlowTheme.of(context).secondaryBackground,
            borderRadius: BorderRadius.circular(20.0),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(0.0, 10.0, 0.0, 10.0),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: FlutterFlowTheme.of(context).labelMedium.override(
                    font: GoogleFonts.inter(),
                    color: selected
                        ? FlutterFlowTheme.of(context).primaryBackground
                        : FlutterFlowTheme.of(context).primaryText,
                    letterSpacing: 0.0,
                  ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _staffCard(BuildContext context, StaffRow s) {
    final active = s.active ?? true;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: FlutterFlowTheme.of(context).primaryBackground,
                    borderRadius: BorderRadius.circular(22.0),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Icon(
                      Icons.person,
                      color: FlutterFlowTheme.of(context).primary,
                      size: 22.0,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      style: FlutterFlowTheme.of(context).titleSmall.override(
                            font: GoogleFonts.interTight(),
                            color: FlutterFlowTheme.of(context).primaryText,
                            letterSpacing: 0.0,
                          ),
                    ),
                    Text(
                      s.role ?? '—',
                      style: FlutterFlowTheme.of(context).bodySmall.override(
                            font: GoogleFonts.inter(),
                            color: FlutterFlowTheme.of(context).primary,
                            letterSpacing: 0.0,
                          ),
                    ),
                    Text(
                      s.phone ?? '—',
                      style: FlutterFlowTheme.of(context).bodySmall.override(
                            font: GoogleFonts.inter(),
                            color: FlutterFlowTheme.of(context).secondaryText,
                            letterSpacing: 0.0,
                          ),
                    ),
                  ].divide(const SizedBox(height: 3.0)),
                ),
              ].divide(const SizedBox(width: 12.0)),
            ),
            Container(
              decoration: BoxDecoration(
                color: FlutterFlowTheme.of(context).primaryBackground,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(8.0, 3.0, 8.0, 3.0),
                child: Text(
                  active ? 'Active' : 'Inactive',
                  style: FlutterFlowTheme.of(context).labelSmall.override(
                        font: GoogleFonts.inter(),
                        color: active
                            ? FlutterFlowTheme.of(context).primary
                            : FlutterFlowTheme.of(context).error,
                        letterSpacing: 0.0,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeStaff =
        _filteredStaff.where((s) => (s.active ?? true) == true).toList();
    final inactiveStaff =
        _filteredStaff.where((s) => (s.active ?? true) == false).toList();

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          automaticallyImplyLeading: true,
          title: Text(
            FFLocalizations.of(context).getText(
              '23bi34ce' /* Users */,
            ),
            style: FlutterFlowTheme.of(context).titleLarge.override(
                  font: GoogleFonts.interTight(
                    fontWeight: FontWeight.w600,
                  ),
                  fontSize: 22.0,
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.w600,
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
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(0.0, 14.0, 0.0, 14.0),
                      child: FFButtonWidget(
                        onPressed: () {
                          // Adding staff still needs a real form (Phase 2
                          // remainder) — the `staff` table has PIN/role/
                          // salary/PF fields that need proper input, not a
                          // one-line prompt. Flagging instead of faking it.
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Add User form not built yet — add staff '
                                'rows directly in Supabase for now.',
                              ),
                              duration: Duration(milliseconds: 3000),
                            ),
                          );
                        },
                        text: FFLocalizations.of(context).getText(
                          'fkpmslnc' /* Add New User */,
                        ),
                        icon: const Icon(
                          Icons.person_add,
                          size: 20.0,
                        ),
                        options: FFButtonOptions(
                          width: double.infinity,
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          iconPadding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          iconColor:
                              FlutterFlowTheme.of(context).primaryBackground,
                          color: FlutterFlowTheme.of(context).primary,
                          textStyle: TextStyle(
                            color:
                                FlutterFlowTheme.of(context).primaryBackground,
                          ),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _roleChip(context, 'All', null),
                        _roleChip(context, 'Admin', 'admin'),
                        _roleChip(context, 'Driver', 'driver'),
                        _roleChip(context, 'Staff', 'staff'),
                      ].divide(const SizedBox(width: 8.0)),
                    ),
                    Text(
                      'Active Users (${activeStaff.length})',
                      style: FlutterFlowTheme.of(context).titleMedium.override(
                            font: GoogleFonts.interTight(),
                            color: FlutterFlowTheme.of(context).primaryText,
                            letterSpacing: 0.0,
                          ),
                    ),
                    if (activeStaff.isEmpty)
                      Text(
                        _model.staffOut == null
                            ? 'Loading…'
                            : 'No active staff found for this org.',
                        style: FlutterFlowTheme.of(context)
                            .bodySmall
                            .override(
                              font: GoogleFonts.inter(),
                              color: FlutterFlowTheme.of(context).secondaryText,
                            ),
                      )
                    else
                      ...activeStaff.map((s) => _staffCard(context, s)),
                    Text(
                      'Inactive Users (${inactiveStaff.length})',
                      style: FlutterFlowTheme.of(context).titleMedium.override(
                            font: GoogleFonts.interTight(),
                            color: FlutterFlowTheme.of(context).secondaryText,
                            letterSpacing: 0.0,
                          ),
                    ),
                    if (inactiveStaff.isEmpty)
                      Text(
                        'None.',
                        style: FlutterFlowTheme.of(context)
                            .bodySmall
                            .override(
                              font: GoogleFonts.inter(),
                              color: FlutterFlowTheme.of(context).secondaryText,
                            ),
                      )
                    else
                      ...inactiveStaff.map((s) => _staffCard(context, s)),
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
