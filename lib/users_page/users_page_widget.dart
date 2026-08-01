import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/components/keyboard_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'staff_form_sheet.dart';
import 'users_page_model.dart';
export 'users_page_model.dart';

/// Staff Management (Week 2 of the v1 launch plan).
///
/// History: was an empty FlutterFlow shell with hardcoded cards, then a
/// read-only list. Now full CRUD-lite: add/edit via StaffFormSheet
/// (bottom sheet), role filter chips matching the real APC roles
/// (supervisor / driver / helper / packer / admin), active/inactive
/// sections, and plan-limit gating on add (subscription_plans.limits
/// key `max_users`, -1 = unlimited).
///
/// Org-scoped via OrgScope (reads, writes, and insert stamping) — see
/// LEAK_AUDIT.md conventions. Deleting staff is deliberately not offered:
/// staff rows are referenced by orders/attendance/salary history, so the
/// supported flow is marking them Inactive (also blocks their PIN login).
class UsersPageWidget extends StatefulWidget {
  const UsersPageWidget({super.key});

  static String routeName = 'UsersPage';
  static String routePath = '/users';

  @override
  State<UsersPageWidget> createState() => _UsersPageWidgetState();
}

class _UsersPageWidgetState extends State<UsersPageWidget>
    with RefreshOnPopMixin<UsersPageWidget> {
  late UsersPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => UsersPageModel());

    SchedulerBinding.instance.addPostFrameCallback((_) => _reload());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  // Refresh-after-write fix (parity brief Part 1): re-run when
  // StaffFormSheet (add/edit) is popped back to this list.
  @override
  void onPageRefresh() => _reload();

  Future<void> _reload() async {
    _model.staffOut = await StaffTable().queryRows(
      queryFn: (q) => OrgScope.read(q).order('name'),
    );
    _model.staffList = (_model.staffOut ?? []).toList().cast<StaffRow>();
    safeSetState(() {});
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  List<StaffRow> get _filteredStaff {
    var out = _model.staffList;
    if (_model.roleFilter != null) {
      out = out
          .where((s) => (s.role ?? '').toLowerCase() == _model.roleFilter)
          .toList();
    }
    final q = _model.searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out
          .where((s) =>
              s.name.toLowerCase().contains(q) ||
              (s.phone ?? '').toLowerCase().contains(q))
          .toList();
    }
    return out;
  }

  Future<void> _addStaff() async {
    // Plan gate: limits.max_users from the org's subscription plan.
    // Counts every staff row (active + inactive) — an inactive row still
    // occupies a seat until the org upgrades.
    final count = _model.staffList.length;
    if (AppSession.instance.isOverLimit('max_users', count)) {
      final max = AppSession.instance.getLimit('max_users');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Staff limit reached ($count/$max on the '
            '${AppSession.instance.planName ?? 'current'} plan). '
            'Upgrade to add more staff.',
          ),
          duration: const Duration(milliseconds: 4000),
        ),
      );
      return;
    }
    final saved = await StaffFormSheet.show(context);
    if (saved) _reload();
  }

  Future<void> _editStaff(StaffRow s) async {
    final saved = await StaffFormSheet.show(context, existing: s);
    if (saved) _reload();
  }

  Widget _roleChip(BuildContext context, String label, String? value) {
    final selected = _model.roleFilter == value;
    return GestureDetector(
      onTap: () => safeSetState(() => _model.roleFilter = value),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? FlutterFlowTheme.of(context).primary
              : FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(20.0),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16.0, 10.0, 16.0, 10.0),
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
    );
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _staffCard(BuildContext context, StaffRow s) {
    final active = s.active ?? true;
    final theme = FlutterFlowTheme.of(context);
    final detailBits = <String>[
      if ((s.phone ?? '').isNotEmpty) s.phone!,
      if ((s.branch ?? '').isNotEmpty) s.branch!,
      if (s.salary != null) '₹${s.salary!.toStringAsFixed(0)}/mo',
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(12.0),
      onTap: () => _editStaff(s),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: theme.primaryBackground,
                        borderRadius: BorderRadius.circular(22.0),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: Icon(
                          Icons.person,
                          color: theme.primary,
                          size: 22.0,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.name,
                            overflow: TextOverflow.ellipsis,
                            style: theme.titleSmall.override(
                              font: GoogleFonts.interTight(),
                              color: theme.primaryText,
                              letterSpacing: 0.0,
                            ),
                          ),
                          Text(
                            _cap((s.role ?? '—').toLowerCase()),
                            style: theme.bodySmall.override(
                              font: GoogleFonts.inter(),
                              color: theme.primary,
                              letterSpacing: 0.0,
                            ),
                          ),
                          Text(
                            detailBits.isEmpty ? '—' : detailBits.join(' · '),
                            overflow: TextOverflow.ellipsis,
                            style: theme.bodySmall.override(
                              font: GoogleFonts.inter(),
                              color: theme.secondaryText,
                              letterSpacing: 0.0,
                            ),
                          ),
                        ].divide(const SizedBox(height: 3.0)),
                      ),
                    ),
                  ].divide(const SizedBox(width: 12.0)),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: theme.primaryBackground,
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          8.0, 3.0, 8.0, 3.0),
                      child: Text(
                        active ? 'Active' : 'Inactive',
                        style: theme.labelSmall.override(
                          font: GoogleFonts.inter(),
                          color: active ? theme.primary : theme.error,
                          letterSpacing: 0.0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6.0),
                  Icon(Icons.edit_outlined,
                      color: theme.secondaryText, size: 18.0),
                ],
              ),
            ],
          ),
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
            'Staff',
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
              child: KeyboardScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          0.0, 14.0, 0.0, 0.0),
                      child: FFButtonWidget(
                        onPressed: _addStaff,
                        text: 'Add Staff',
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
                    // Users Kickoff Step 3.1: search by name/phone.
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          0.0, 4.0, 0.0, 0.0),
                      child: TextFormField(
                        initialValue: _model.searchQuery,
                        onChanged: (v) =>
                            safeSetState(() => _model.searchQuery = v),
                        style: GoogleFonts.inter(
                            color: FlutterFlowTheme.of(context).primaryText),
                        decoration: InputDecoration(
                          hintText: 'Search by name or phone',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          isDense: true,
                          filled: true,
                          fillColor:
                              FlutterFlowTheme.of(context).secondaryBackground,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _roleChip(context, 'All', null),
                          _roleChip(context, 'Supervisor', 'supervisor'),
                          _roleChip(context, 'Driver', 'driver'),
                          _roleChip(context, 'Helper', 'helper'),
                          _roleChip(context, 'Packer', 'packer'),
                          _roleChip(context, 'Admin', 'admin'),
                        ].divide(const SizedBox(width: 8.0)),
                      ),
                    ),
                    Text(
                      'Active Staff (${activeStaff.length})',
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
                        style: FlutterFlowTheme.of(context).bodySmall.override(
                              font: GoogleFonts.inter(),
                              color: FlutterFlowTheme.of(context).secondaryText,
                            ),
                      )
                    else
                      ...activeStaff.map((s) => _staffCard(context, s)),
                    Text(
                      'Inactive Staff (${inactiveStaff.length})',
                      style: FlutterFlowTheme.of(context).titleMedium.override(
                            font: GoogleFonts.interTight(),
                            color: FlutterFlowTheme.of(context).secondaryText,
                            letterSpacing: 0.0,
                          ),
                    ),
                    if (inactiveStaff.isEmpty)
                      Text(
                        'None.',
                        style: FlutterFlowTheme.of(context).bodySmall.override(
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
