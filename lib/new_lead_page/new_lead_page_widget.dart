import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_drop_down.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/form_field_controller.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'new_lead_page_model.dart';
export 'new_lead_page_model.dart';

/// Create a new CRM lead, or edit an existing one when [leadId] is passed.
class NewLeadPageWidget extends StatefulWidget {
  const NewLeadPageWidget({super.key, this.leadId});

  final String? leadId;

  static String routeName = 'NewLeadPage';
  static String routePath = '/new-lead';

  @override
  State<NewLeadPageWidget> createState() => _NewLeadPageWidgetState();
}

class _NewLeadPageWidgetState extends State<NewLeadPageWidget> {
  late NewLeadPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => NewLeadPageModel());

    _model.ldCustomerFieldTextController ??= TextEditingController();
    _model.ldCustomerFieldFocusNode ??= FocusNode();

    _model.ldPhoneFieldTextController ??= TextEditingController();
    _model.ldPhoneFieldFocusNode ??= FocusNode();

    _model.ldEmailFieldTextController ??= TextEditingController();
    _model.ldEmailFieldFocusNode ??= FocusNode();

    _model.ldFromCityFieldTextController ??= TextEditingController();
    _model.ldFromCityFieldFocusNode ??= FocusNode();

    _model.ldToCityFieldTextController ??= TextEditingController();
    _model.ldToCityFieldFocusNode ??= FocusNode();

    _model.ldNotesFieldTextController ??= TextEditingController();
    _model.ldNotesFieldFocusNode ??= FocusNode();

    SchedulerBinding.instance.addPostFrameCallback((_) => _loadBranches());
    if (widget.leadId != null) {
      _model.isLoadingExisting = true;
      SchedulerBinding.instance.addPostFrameCallback((_) => _loadExistingLead());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  /// Mirrors new_order_page_widget.dart's _loadBranches() exactly — same
  /// bug (a hardcoded Chennai/Bengaluru/Coimbatore list defaulting to
  /// 'Bengaluru'), same fix: read `branches`, org-scoped; restrict a
  /// non-owner to just their own branch instead of merely defaulting to
  /// it; owner sees every active branch with no default.
  Future<void> _loadBranches() async {
    final rows = await BranchesTable().queryRows(
      queryFn: (q) => OrgScope.read(q).eq('active', true).order('name'),
    );
    final orgBranches = rows.map((r) => r.name).toList();
    _model.orgHasAnyBranches = orgBranches.isNotEmpty;
    final isOwner = AppSession.instance.currentStaffId == null;
    final ownBranch = AppSession.instance.currentStaffBranch;
    _model.availableBranches = isOwner
        ? orgBranches
        : (ownBranch != null && orgBranches.contains(ownBranch)
            ? [ownBranch]
            : const <String>[]);
    _model.branchesLoaded = true;

    // Only for a fresh lead — an existing one's branch is set by
    // _loadExistingLead() and must not be overwritten here.
    if (widget.leadId == null) {
      final picked = (!isOwner && _model.availableBranches.length == 1)
          ? _model.availableBranches.first
          : null;
      _model.ldBranch = picked;
      _model.ldBranchDropdownValue = picked;
      _model.ldBranchDropdownValueController?.value = picked;
    }

    safeSetState(() {});
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  Future<void> _loadExistingLead() async {
    // LEAK_AUDIT.md leak #4 (Stage 1 fix): matched only on id — a foreign
    // leadId would have silently loaded another org's lead into this form.
    final rows = await LeadsTable().queryRows(
      queryFn: (q) => OrgScope.read(q).eq('id', widget.leadId!),
    );
    if (rows.isEmpty) {
      _model.isLoadingExisting = false;
      safeSetState(() {});
      return;
    }
    final lead = rows.first;

    _model.ldCustomerFieldTextController!.text = lead.customer;
    _model.ldPhoneFieldTextController!.text = lead.phone ?? '';
    _model.ldEmailFieldTextController!.text = lead.email ?? '';
    _model.ldFromCityFieldTextController!.text = lead.fromCity ?? '';
    _model.ldToCityFieldTextController!.text = lead.toCity ?? '';
    _model.ldNotesFieldTextController!.text = lead.notes ?? '';

    _model.ldApproxDate = DateTime.tryParse(lead.approxDate ?? '');
    _model.ldApproxDatePicked = _model.ldApproxDate != null;

    // Dropdowns are backed by a lazily-created FormFieldController (see
    // form_field_controller.dart) that's already built with the field
    // defaults by the time this async load completes, so the model field
    // alone isn't enough — the controller's own value has to be updated
    // too or the dropdown keeps showing the create-mode default.
    _model.ldService = lead.service;
    _model.ldServiceDropdownValue = lead.service;
    _model.ldServiceDropdownValueController?.value = lead.service;

    _model.ldStatus = lead.status;
    _model.ldStatusDropdownValue = lead.status;
    _model.ldStatusDropdownValueController?.value = lead.status;

    _model.ldSource = lead.source;
    _model.ldSourceDropdownValue = lead.source;
    _model.ldSourceDropdownValueController?.value = lead.source;

    _model.ldBranch = lead.branch;
    _model.ldBranchDropdownValue = lead.branch;
    _model.ldBranchDropdownValueController?.value = lead.branch;

    _model.isLoadingExisting = false;
    safeSetState(() {});
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
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          automaticallyImplyLeading: true,
          title: Text(
            widget.leadId != null
                ? 'Edit Lead'
                : FFLocalizations.of(context).getText(
                    '8abdh8kl' /* New Lead */,
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
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: FlutterFlowTheme.of(context)
                                .secondaryBackground,
                            borderRadius: BorderRadius.circular(16.0),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  FFLocalizations.of(context).getText(
                                    'g9dwuxwa' /* Contact */,
                                  ),
                                  style: FlutterFlowTheme.of(context)
                                      .titleSmall
                                      .override(
                                        font: GoogleFonts.interTight(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .titleSmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .titleSmall
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .primary,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .titleSmall
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .titleSmall
                                            .fontStyle,
                                      ),
                                ),
                                TextFormField(
                                  controller:
                                      _model.ldCustomerFieldTextController,
                                  focusNode: _model.ldCustomerFieldFocusNode,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText:
                                        FFLocalizations.of(context).getText(
                                      'qkhgnzdq' /* Customer Name * */,
                                    ),
                                    hintText:
                                        FFLocalizations.of(context).getText(
                                      '51of1xk6' /* Full name */,
                                    ),
                                    enabledBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    focusedBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    errorBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    focusedErrorBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    filled: true,
                                  ),
                                  style: const TextStyle(),
                                  maxLines: null,
                                  validator: _model
                                      .ldCustomerFieldTextControllerValidator
                                      .asValidator(context),
                                ),
                                TextFormField(
                                  controller: _model.ldPhoneFieldTextController,
                                  focusNode: _model.ldPhoneFieldFocusNode,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText:
                                        FFLocalizations.of(context).getText(
                                      'xe3mj8hc' /* Phone * */,
                                    ),
                                    hintText:
                                        FFLocalizations.of(context).getText(
                                      '9hfe6x4j' /* +91 XXXXX XXXXX */,
                                    ),
                                    enabledBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    focusedBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    errorBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    focusedErrorBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    filled: true,
                                  ),
                                  style: const TextStyle(),
                                  maxLines: null,
                                  keyboardType: TextInputType.number,
                                  validator: _model
                                      .ldPhoneFieldTextControllerValidator
                                      .asValidator(context),
                                ),
                                TextFormField(
                                  controller: _model.ldEmailFieldTextController,
                                  focusNode: _model.ldEmailFieldFocusNode,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText:
                                        FFLocalizations.of(context).getText(
                                      'vqqkih8q' /* Email */,
                                    ),
                                    hintText:
                                        FFLocalizations.of(context).getText(
                                      'giua4r66' /* email@example.com */,
                                    ),
                                    enabledBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    focusedBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    errorBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    focusedErrorBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    filled: true,
                                  ),
                                  style: const TextStyle(),
                                  maxLines: null,
                                  validator: _model
                                      .ldEmailFieldTextControllerValidator
                                      .asValidator(context),
                                ),
                              ].divide(const SizedBox(height: 14.0)),
                            ),
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: FlutterFlowTheme.of(context)
                                .secondaryBackground,
                            borderRadius: BorderRadius.circular(16.0),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  FFLocalizations.of(context).getText(
                                    'efi3vmrv' /* Move Details */,
                                  ),
                                  style: FlutterFlowTheme.of(context)
                                      .titleSmall
                                      .override(
                                        font: GoogleFonts.interTight(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .titleSmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .titleSmall
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .primary,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .titleSmall
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .titleSmall
                                            .fontStyle,
                                      ),
                                ),
                                TextFormField(
                                  controller:
                                      _model.ldFromCityFieldTextController,
                                  focusNode: _model.ldFromCityFieldFocusNode,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText:
                                        FFLocalizations.of(context).getText(
                                      'klihmzbp' /* From City */,
                                    ),
                                    hintText:
                                        FFLocalizations.of(context).getText(
                                      '4him4871' /* Origin city */,
                                    ),
                                    enabledBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    focusedBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    errorBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    focusedErrorBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    filled: true,
                                  ),
                                  style: const TextStyle(),
                                  maxLines: null,
                                  validator: _model
                                      .ldFromCityFieldTextControllerValidator
                                      .asValidator(context),
                                ),
                                TextFormField(
                                  controller:
                                      _model.ldToCityFieldTextController,
                                  focusNode: _model.ldToCityFieldFocusNode,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText:
                                        FFLocalizations.of(context).getText(
                                      '3w9vwau0' /* To City */,
                                    ),
                                    hintText:
                                        FFLocalizations.of(context).getText(
                                      'kzelw06s' /* Destination city */,
                                    ),
                                    enabledBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    focusedBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    errorBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    focusedErrorBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    filled: true,
                                  ),
                                  style: const TextStyle(),
                                  maxLines: null,
                                  validator: _model
                                      .ldToCityFieldTextControllerValidator
                                      .asValidator(context),
                                ),
                                Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: FlutterFlowTheme.of(context)
                                        .primaryBackground,
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.fromSTEB(
                                        14.0, 12.0, 14.0, 12.0),
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
                                              FFLocalizations.of(context)
                                                  .getText(
                                                'zoiv1m4b' /* Approx Date * */,
                                              ),
                                              style:
                                                  FlutterFlowTheme.of(context)
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
                                            if (!(_model.ldApproxDatePicked ??
                                                false))
                                              Container(
                                                child: Text(
                                                  FFLocalizations.of(context)
                                                      .getText(
                                                    '4rh4ggrx' /* Tap to pick date */,
                                                  ),
                                                  style: FlutterFlowTheme.of(
                                                          context)
                                                      .bodyMedium
                                                      .override(
                                                        font: GoogleFonts.inter(
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodyMedium
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodyMedium
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
                                                                .bodyMedium
                                                                .fontWeight,
                                                        fontStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodyMedium
                                                                .fontStyle,
                                                      ),
                                                ),
                                              ),
                                            if ((_model.ldApproxDatePicked ??
                                                    false) &&
                                                _model.ldApproxDate != null)
                                              Container(
                                                child: Text(
                                                  dateTimeFormat(
                                                      'd MMM y',
                                                      _model.ldApproxDate),
                                                  style: FlutterFlowTheme.of(
                                                          context)
                                                      .bodyMedium
                                                      .override(
                                                        font: GoogleFonts.inter(
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodyMedium
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodyMedium
                                                                  .fontStyle,
                                                        ),
                                                        color:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .primaryText,
                                                        letterSpacing: 0.0,
                                                        fontWeight:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodyMedium
                                                                .fontWeight,
                                                        fontStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodyMedium
                                                                .fontStyle,
                                                      ),
                                                ),
                                              ),
                                          ].divide(const SizedBox(height: 2.0)),
                                        ),
                                        Padding(
                                          padding:
                                              const EdgeInsetsDirectional.fromSTEB(
                                                  12.0, 6.0, 12.0, 6.0),
                                          child: FFButtonWidget(
                                            onPressed: () async {
                                              final datePickedDate =
                                                  await showDatePicker(
                                                context: context,
                                                // Edit mode: open on the
                                                // lead's saved date; allow
                                                // past dates so editing an
                                                // old lead doesn't assert
                                                // (initialDate must be >=
                                                // firstDate).
                                                initialDate:
                                                    _model.ldApproxDate ??
                                                        getCurrentTimestamp,
                                                firstDate: DateTime(2020),
                                                lastDate: DateTime(2050),
                                                builder: (context, child) {
                                                  // FlutterFlow artifact fix:
                                                  // the generated wrapper set
                                                  // every color to 0x00000000
                                                  // (fully transparent), which
                                                  // rendered the ghost
                                                  // calendar. Same themed
                                                  // builder as the other
                                                  // fixed pickers.
                                                  final theme =
                                                      FlutterFlowTheme.of(
                                                          context);
                                                  return wrapInMaterialDatePickerTheme(
                                                    context,
                                                    child!,
                                                    headerBackgroundColor:
                                                        theme.primary,
                                                    headerForegroundColor:
                                                        Colors.white,
                                                    headerTextStyle: theme
                                                        .headlineLarge
                                                        .override(
                                                          font: GoogleFonts
                                                              .interTight(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                          color: Colors.white,
                                                          fontSize: 30.0,
                                                        ),
                                                    pickerBackgroundColor:
                                                        theme
                                                            .secondaryBackground,
                                                    pickerForegroundColor:
                                                        theme.primaryText,
                                                    selectedDateTimeBackgroundColor:
                                                        theme.primary,
                                                    selectedDateTimeForegroundColor:
                                                        Colors.white,
                                                    actionButtonForegroundColor:
                                                        theme.primary,
                                                    iconSize: 24,
                                                  );
                                                },
                                              );

                                              // Only commit when a date
                                              // was actually chosen —
                                              // dismissing the dialog used
                                              // to null ldApproxDate while
                                              // setting picked=true, which
                                              // crashed the display below
                                              // ("Unexpected null value").
                                              if (datePickedDate != null) {
                                                safeSetState(() {
                                                  _model.datePicked = DateTime(
                                                    datePickedDate.year,
                                                    datePickedDate.month,
                                                    datePickedDate.day,
                                                  );
                                                  _model.ldApproxDate =
                                                      _model.datePicked;
                                                  _model.ldApproxDatePicked =
                                                      true;
                                                });
                                              }
                                            },
                                            text: FFLocalizations.of(context)
                                                .getText(
                                              'ot7t0qf9' /* Pick Date */,
                                            ),
                                            icon: const Icon(
                                              Icons.calendar_today,
                                              size: 20.0,
                                            ),
                                            options: FFButtonOptions(
                                              padding: const EdgeInsetsDirectional
                                                  .fromSTEB(0.0, 0.0, 0.0, 0.0),
                                              iconPadding: const EdgeInsetsDirectional
                                                  .fromSTEB(0.0, 0.0, 0.0, 0.0),
                                              iconColor:
                                                  FlutterFlowTheme.of(context)
                                                      .primary,
                                              color: Colors.transparent,
                                              textStyle: TextStyle(
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primary,
                                              ),
                                              borderSide: BorderSide(
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primary,
                                                width: 1.0,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8.0),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                FlutterFlowDropDown<String>(
                                  controller: _model
                                          .ldServiceDropdownValueController ??=
                                      FormFieldController<String>(
                                    _model.ldServiceDropdownValue ??=
                                        _model.ldService,
                                  ),
                                  options: [
                                    FFLocalizations.of(context).getText(
                                      'br2hucj0' /* House Shifting */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      '95i09bsm' /* Office Shifting */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      'qqvqqtsc' /* Vehicle Transport */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      'ucuovx6i' /* Storage */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      'e6yr7u7b' /* Packing Only */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      'wwv8vwa5' /* Long Distance */,
                                    )
                                  ],
                                  onChanged: (val) async {
                                    safeSetState(() =>
                                        _model.ldServiceDropdownValue = val);
                                    _model.ldService =
                                        _model.ldServiceDropdownValue;
                                    safeSetState(() {});
                                  },
                                  textStyle: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontStyle,
                                        ),
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                  hintText: FFLocalizations.of(context).getText(
                                    'a6f26ge0' /* Select service */,
                                  ),
                                  icon: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: FlutterFlowTheme.of(context)
                                        .secondaryText,
                                    size: 24.0,
                                  ),
                                  fillColor: FlutterFlowTheme.of(context)
                                      .secondaryBackground,
                                  elevation: 2.0,
                                  borderColor:
                                      FlutterFlowTheme.of(context).alternate,
                                  borderWidth: 1.0,
                                  borderRadius: 8.0,
                                  margin: const EdgeInsetsDirectional.fromSTEB(
                                      12.0, 0.0, 12.0, 0.0),
                                  hidesUnderline: true,
                                  isOverButton: false,
                                  isSearchable: false,
                                  isMultiSelect: false,
                                  labelText:
                                      FFLocalizations.of(context).getText(
                                    '1w25o4fm' /* Service * */,
                                  ),
                                  labelTextStyle: const TextStyle(),
                                ),
                              ].divide(const SizedBox(height: 14.0)),
                            ),
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: FlutterFlowTheme.of(context)
                                .secondaryBackground,
                            borderRadius: BorderRadius.circular(16.0),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  FFLocalizations.of(context).getText(
                                    'kc08lwlm' /* Classification */,
                                  ),
                                  style: FlutterFlowTheme.of(context)
                                      .titleSmall
                                      .override(
                                        font: GoogleFonts.interTight(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .titleSmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .titleSmall
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .primary,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .titleSmall
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .titleSmall
                                            .fontStyle,
                                      ),
                                ),
                                FlutterFlowDropDown<String>(
                                  controller:
                                      _model.ldStatusDropdownValueController ??=
                                          FormFieldController<String>(
                                    _model.ldStatusDropdownValue ??=
                                        _model.ldStatus,
                                  ),
                                  options: [
                                    FFLocalizations.of(context).getText(
                                      'inr5zv5f' /* new */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      '651htdcq' /* contacted */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      'touvbpiu' /* survey_done */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      '9cvtsnl0' /* quoted */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      '4ckdir1v' /* converted */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      'pfibdeep' /* lost */,
                                    )
                                  ],
                                  onChanged: (val) async {
                                    safeSetState(() =>
                                        _model.ldStatusDropdownValue = val);
                                    _model.ldStatus =
                                        _model.ldStatusDropdownValue;
                                    safeSetState(() {});
                                  },
                                  textStyle: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontStyle,
                                        ),
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                  hintText: FFLocalizations.of(context).getText(
                                    'm28isdvg' /* Select status */,
                                  ),
                                  icon: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: FlutterFlowTheme.of(context)
                                        .secondaryText,
                                    size: 24.0,
                                  ),
                                  fillColor: FlutterFlowTheme.of(context)
                                      .secondaryBackground,
                                  elevation: 2.0,
                                  borderColor:
                                      FlutterFlowTheme.of(context).alternate,
                                  borderWidth: 1.0,
                                  borderRadius: 8.0,
                                  margin: const EdgeInsetsDirectional.fromSTEB(
                                      12.0, 0.0, 12.0, 0.0),
                                  hidesUnderline: true,
                                  isOverButton: false,
                                  isSearchable: false,
                                  isMultiSelect: false,
                                  labelText:
                                      FFLocalizations.of(context).getText(
                                    '2px3tiys' /* Status * */,
                                  ),
                                  labelTextStyle: const TextStyle(),
                                ),
                                FlutterFlowDropDown<String>(
                                  controller:
                                      _model.ldSourceDropdownValueController ??=
                                          FormFieldController<String>(
                                    _model.ldSourceDropdownValue ??=
                                        _model.ldSource,
                                  ),
                                  options: [
                                    FFLocalizations.of(context).getText(
                                      'mhe6egjg' /* WhatsApp */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      '92hptvr2' /* Phone Call */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      'wfkjv1iw' /* Website */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      'hrzdqkgt' /* Porter */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      'r9ydgg1q' /* Referral */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      'sr6q74zu' /* Walk-in */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      '43yslz80' /* Google */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      'ow715kgl' /* JustDial */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      's6ms4ki3' /* Other */,
                                    )
                                  ],
                                  onChanged: (val) async {
                                    safeSetState(() =>
                                        _model.ldSourceDropdownValue = val);
                                    _model.ldSource =
                                        _model.ldSourceDropdownValue;
                                    safeSetState(() {});
                                  },
                                  textStyle: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontStyle,
                                        ),
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                  hintText: FFLocalizations.of(context).getText(
                                    'alsryorj' /* How did they hear about us? */,
                                  ),
                                  icon: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: FlutterFlowTheme.of(context)
                                        .secondaryText,
                                    size: 24.0,
                                  ),
                                  fillColor: FlutterFlowTheme.of(context)
                                      .secondaryBackground,
                                  elevation: 2.0,
                                  borderColor:
                                      FlutterFlowTheme.of(context).alternate,
                                  borderWidth: 1.0,
                                  borderRadius: 8.0,
                                  margin: const EdgeInsetsDirectional.fromSTEB(
                                      12.0, 0.0, 12.0, 0.0),
                                  hidesUnderline: true,
                                  isOverButton: false,
                                  isSearchable: false,
                                  isMultiSelect: false,
                                  labelText:
                                      FFLocalizations.of(context).getText(
                                    'vd433kb2' /* Source * */,
                                  ),
                                  labelTextStyle: const TextStyle(),
                                ),
                                FlutterFlowDropDown<String>(
                                  controller:
                                      _model.ldBranchDropdownValueController ??=
                                          FormFieldController<String>(
                                    _model.ldBranchDropdownValue ??=
                                        _model.ldBranch,
                                  ),
                                  // Was a hardcoded Chennai/Bengaluru/
                                  // Coimbatore list — see new_order_page
                                  // _widget.dart's identical fix note.
                                  options: _model.availableBranches,
                                  onChanged: (val) async {
                                    safeSetState(() =>
                                        _model.ldBranchDropdownValue = val);
                                    _model.ldBranch =
                                        _model.ldBranchDropdownValue;
                                    safeSetState(() {});
                                  },
                                  textStyle: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontStyle,
                                        ),
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                  hintText: FFLocalizations.of(context).getText(
                                    'znu1wq8r' /* Select branch */,
                                  ),
                                  icon: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: FlutterFlowTheme.of(context)
                                        .secondaryText,
                                    size: 24.0,
                                  ),
                                  fillColor: FlutterFlowTheme.of(context)
                                      .secondaryBackground,
                                  elevation: 2.0,
                                  borderColor:
                                      FlutterFlowTheme.of(context).alternate,
                                  borderWidth: 1.0,
                                  borderRadius: 8.0,
                                  margin: const EdgeInsetsDirectional.fromSTEB(
                                      12.0, 0.0, 12.0, 0.0),
                                  hidesUnderline: true,
                                  isOverButton: false,
                                  isSearchable: false,
                                  isMultiSelect: false,
                                  labelText:
                                      FFLocalizations.of(context).getText(
                                    'yqkoiakj' /* Branch * */,
                                  ),
                                  labelTextStyle: const TextStyle(),
                                ),
                                TextFormField(
                                  controller: _model.ldNotesFieldTextController,
                                  focusNode: _model.ldNotesFieldFocusNode,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText:
                                        FFLocalizations.of(context).getText(
                                      'kbot98z0' /* Notes */,
                                    ),
                                    hintText:
                                        FFLocalizations.of(context).getText(
                                      'lpp8v2mq' /* Any relevant notes */,
                                    ),
                                    enabledBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    focusedBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    errorBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    focusedErrorBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0x00000000),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(4.0),
                                        topRight: Radius.circular(4.0),
                                      ),
                                    ),
                                    filled: true,
                                  ),
                                  style: const TextStyle(),
                                  maxLines: 3,
                                  validator: _model
                                      .ldNotesFieldTextControllerValidator
                                      .asValidator(context),
                                ),
                              ].divide(const SizedBox(height: 14.0)),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 16.0, 0.0, 16.0),
                          child: FFButtonWidget(
                            onPressed: () async {
                              if (_model.ldBranch == null ||
                                  _model.ldBranch!.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Select a branch first.'),
                                  ),
                                );
                                return;
                              }
                              _model.ldSaveSuccess = false;
                              safeSetState(() {});
                              final isEditing = widget.leadId != null;
                              final payload = {
                                'customer':
                                    _model.ldCustomerFieldTextController.text,
                                'phone': _model.ldPhoneFieldTextController.text,
                                'email': _model.ldEmailFieldTextController.text,
                                'from_city':
                                    _model.ldFromCityFieldTextController.text,
                                'to_city':
                                    _model.ldToCityFieldTextController.text,
                                'approx_date': _model.ldApproxDate?.toString(),
                                'service': _model.ldService,
                                'source': _model.ldSource,
                                'status': _model.ldStatus,
                                'branch': _model.ldBranch,
                                'notes': _model.ldNotesFieldTextController.text,
                              };
                              try {
                                if (isEditing) {
                                  // LEAK_AUDIT.md write-gap fix: matched
                                  // only on id before — now also requires
                                  // the row to belong to the current org.
                                  await LeadsTable().update(
                                    data: payload,
                                    matchingRows: (q) => OrgScope.write(q)
                                        .eq('id', widget.leadId!),
                                  );
                                } else {
                                  _model.createdLead =
                                      await LeadsTable().insert({
                                    // Phase 1 multi-tenancy pass — see
                                    // supabase/phase1_add_org_id.sql.
                                    ...OrgScope.stamp(),
                                    ...payload,
                                  });
                                }
                                _model.ldSaveSuccess = true;
                              } catch (_) {
                                _model.ldSaveSuccess = false;
                              }
                              safeSetState(() {});
                              if (_model.ldSaveSuccess!) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isEditing
                                          ? 'Lead updated successfully!'
                                          : 'Lead saved successfully!',
                                      style: const TextStyle(),
                                    ),
                                    duration: const Duration(milliseconds: 4000),
                                  ),
                                );
                                if (isEditing) {
                                  if (Navigator.of(context).canPop()) {
                                    context.pop();
                                  }
                                } else {
                                  if (Navigator.of(context).canPop()) {
                                    context.pop();
                                  }
                                  context.pushNamed(LeadsPageWidget.routeName);
                                }
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Failed to save lead. Please try again.',
                                      style: TextStyle(),
                                    ),
                                    duration: Duration(milliseconds: 4000),
                                  ),
                                );
                              }

                              safeSetState(() {});
                            },
                            text: widget.leadId != null
                                ? 'Update Lead'
                                : FFLocalizations.of(context).getText(
                                    'sxeutefv' /* Save Lead */,
                                  ),
                            icon: const Icon(
                              Icons.save,
                              size: 20.0,
                            ),
                            options: FFButtonOptions(
                              width: double.infinity,
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  0.0, 0.0, 0.0, 0.0),
                              iconPadding: const EdgeInsetsDirectional.fromSTEB(
                                  0.0, 0.0, 0.0, 0.0),
                              iconColor: FlutterFlowTheme.of(context)
                                  .primaryBackground,
                              color: FlutterFlowTheme.of(context).primary,
                              textStyle: TextStyle(
                                color: FlutterFlowTheme.of(context)
                                    .primaryBackground,
                              ),
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                          ),
                        ),
                      ].divide(const SizedBox(height: 16.0)),
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
