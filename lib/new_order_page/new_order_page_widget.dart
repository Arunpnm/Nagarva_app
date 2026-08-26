import '/app_session.dart';
import '/backend/customer_lookup.dart';
import '/backend/edge_function_errors.dart';
import '/backend/pricing_defaults.dart';
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
import 'new_order_page_model.dart';
export 'new_order_page_model.dart';

/// Create a new moving order, or edit an existing one when [orderId] is
/// passed.
class NewOrderPageWidget extends StatefulWidget {
  const NewOrderPageWidget({super.key, this.orderId});

  final String? orderId;

  static String routeName = 'NewOrderPage';
  static String routePath = '/new-order';

  @override
  State<NewOrderPageWidget> createState() => _NewOrderPageWidgetState();
}

class _NewOrderPageWidgetState extends State<NewOrderPageWidget> {
  late NewOrderPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => NewOrderPageModel());

    _model.ordCustomerFieldTextController ??= TextEditingController();
    _model.ordCustomerFieldFocusNode ??= FocusNode();

    _model.ordPhoneFieldTextController ??= TextEditingController();
    _model.ordPhoneFieldFocusNode ??= FocusNode();

    _model.ordFromCityFieldTextController ??= TextEditingController();
    _model.ordFromCityFieldFocusNode ??= FocusNode();

    _model.ordToCityFieldTextController ??= TextEditingController();
    _model.ordToCityFieldFocusNode ??= FocusNode();

    _model.ordFromAddressFieldTextController ??= TextEditingController();
    _model.ordFromAddressFieldFocusNode ??= FocusNode();

    _model.ordToAddressFieldTextController ??= TextEditingController();
    _model.ordToAddressFieldFocusNode ??= FocusNode();

    _model.ordFromFloorFieldTextController ??= TextEditingController();
    _model.ordFromFloorFieldFocusNode ??= FocusNode();

    _model.ordToFloorFieldTextController ??= TextEditingController();
    _model.ordToFloorFieldFocusNode ??= FocusNode();

    _model.ordAmountFieldTextController ??= TextEditingController();
    _model.ordAmountFieldFocusNode ??= FocusNode();

    _model.ordNotesFieldTextController ??= TextEditingController();
    _model.ordNotesFieldFocusNode ??= FocusNode();

    _model.ordGstinFieldTextController ??= TextEditingController();
    _model.ordGstinFieldFocusNode ??= FocusNode();

    _model.ordPorterCashCollectFieldTextController ??= TextEditingController();
    _model.ordPorterCashCollectFieldFocusNode ??= FocusNode();

    SchedulerBinding.instance.addPostFrameCallback((_) => _loadBranches());
    if (widget.orderId != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _loadExistingOrder());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  /// Same convention as lead_detail_page._nextOrderId — orders.id is text
  /// with no default, must be supplied on insert or NOT-NULL fires (23502).
  Future<String> _nextOrderId() async {
    final prefix =
        (AppSession.instance.currentOrgSlug?.toUpperCase() ?? 'NGV');
    const key = 'order_id_seq';
    final rows = await SettingsTable().queryRows(
      queryFn: (q) => OrgScope.read(q).eq('key', key),
    );
    final current = rows.isNotEmpty
        ? (int.tryParse(rows.first.value ?? '1000') ?? 1000)
        : 1000;
    final next = current + 1;
    await SettingsTable().upsert(
      {
        'key': key,
        ...OrgScope.stamp(),
        'value': next.toString(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'org_id,key',
    );
    return '$prefix-$next';
  }

  /// Item 5: block New Order rather than let it reach an insert the
  /// `(org_id, branch)` FK on `orders` can only reject. Two distinct
  /// causes get two distinct messages — "go set one up" is only correct
  /// when the ORG has no branch row at all; a staff session whose own
  /// `staff.branch` doesn't match any active branch needs a different fix
  /// (their staff row, not a missing branch) and telling them to go create
  /// an org branch they likely can't reach would be actively misleading.
  Widget _buildNoBranchState(BuildContext context) {
    final noOrgBranches = _model.orgHasAnyBranches == false;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.domain_disabled,
              size: 48.0,
              color: FlutterFlowTheme.of(context).secondaryText,
            ),
            const SizedBox(height: 16.0),
            Text(
              noOrgBranches
                  ? 'Set up a branch first'
                  : 'Your account has no active branch',
              style: FlutterFlowTheme.of(context).titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8.0),
            Text(
              noOrgBranches
                  ? 'This org has no branch set up yet, so a new order '
                      "has nowhere valid to belong to. Add one in Settings, "
                      'then come back here.'
                  : "Your staff record isn't assigned to one of this "
                      "org's active branches. Ask the owner to fix this in "
                      'Settings before creating an order.',
              style: FlutterFlowTheme.of(context).bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20.0),
            if (noOrgBranches)
              FFButtonWidget(
                onPressed: () =>
                    context.pushNamed(SettingsPageWidget.routeName),
                text: 'Go to Settings',
                options: FFButtonOptions(
                  height: 44.0,
                  padding: const EdgeInsetsDirectional.fromSTEB(
                      24.0, 0.0, 24.0, 0.0),
                  color: FlutterFlowTheme.of(context).primary,
                  textStyle: FlutterFlowTheme.of(context)
                      .titleSmall
                      .override(color: Colors.white),
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Loads this org's active branches for OrdBranchDropdown, replacing the
  /// old hardcoded Chennai/Bengaluru/Coimbatore list — a fixed list minted
  /// from APC's own branches, the same shape of defect as NG-050's
  /// default_pricing_config (an APC-shaped default leaking into every
  /// tenant's product). An org with zero branches (e.g. one that predates
  /// the branch backfill, or never got one seeded) blocks New Order rather
  /// than defaulting to a branch name that doesn't exist for it — the old
  /// hardcoded default sent exactly this case into an FK it could never
  /// satisfy.
  Future<void> _loadBranches() async {
    final rows = await BranchesTable().queryRows(
      queryFn: (q) => OrgScope.read(q).eq('active', true).order('name'),
    );
    final orgBranches = rows.map((r) => r.name).toList();
    _model.orgHasAnyBranches = orgBranches.isNotEmpty;
    final isOwner = AppSession.instance.currentStaffId == null;
    final ownBranch = AppSession.instance.currentStaffBranch;

    // The options a NON-OWNER may even see, not just the one pre-selected —
    // restricting, not merely defaulting, is the point (a manager picking
    // another branch is a cross-branch write nothing else stops on
    // insert). An owner sees every active branch and gets no default, so
    // an org with more than one branch forces an explicit pick rather than
    // silently choosing one for them. If a staff row's own branch isn't
    // (or no longer is) one of the org's active branches, that's the same
    // "nothing valid to pick" case as an org with zero branches — block
    // rather than silently falling back to the full list, which would
    // reopen the exact leak this fixes.
    _model.availableBranches = isOwner
        ? orgBranches
        : (ownBranch != null && orgBranches.contains(ownBranch)
            ? [ownBranch]
            : const []);
    _model.branchesLoaded = true;

    // Only for a fresh order — an existing one's branch is set by
    // _loadExistingOrder() below and must not be overwritten here.
    if (widget.orderId == null) {
      final picked = (!isOwner && _model.availableBranches.length == 1)
          ? _model.availableBranches.first
          : null;
      _model.ordBranch = picked;
      _model.ordBranchDropdownValue = picked;
      _model.ordBranchDropdownValueController?.value = picked;
    }

    safeSetState(() {});
  }

  Future<void> _loadExistingOrder() async {
    // LEAK_AUDIT.md leak #3 (Stage 1 fix): matched only on id — a foreign
    // orderId (bad deep link, tampered query param) would have silently
    // loaded and displayed another org's order into this edit form.
    final rows = await OrdersTable().queryRows(
      queryFn: (q) => OrgScope.read(q).eq('id', widget.orderId!),
    );
    if (rows.isEmpty) return;
    final order = rows.first;

    _model.ordCustomerFieldTextController!.text = order.customer;
    _model.ordPhoneFieldTextController!.text = order.phone ?? '';
    _model.ordFromCityFieldTextController!.text = order.fromCity ?? '';
    _model.ordToCityFieldTextController!.text = order.toCity ?? '';
    _model.ordFromAddressFieldTextController!.text = order.fromAddress ?? '';
    _model.ordToAddressFieldTextController!.text = order.toAddress ?? '';
    _model.ordFromFloorFieldTextController!.text =
        order.fromFloor?.toString() ?? '';
    _model.ordToFloorFieldTextController!.text =
        order.toFloor?.toString() ?? '';
    _model.ordAmountFieldTextController!.text =
        order.amount?.toString() ?? '';
    _model.ordNotesFieldTextController!.text = order.notes ?? '';
    // GST, edit mode. Without this the form would show the default (on,
    // 5%) for every existing order regardless of what is stored, and
    // saving would overwrite the real value — the classic way a new field
    // silently rewrites history the first time somebody edits a record.
    //
    // 0 means a deliberate no-GST order, so the toggle goes off. NULL is
    // a legacy order that predates this field: it shows the default, and
    // because the toggle and the live total are both on screen the person
    // editing can see exactly what they are about to save.
    final storedGst = order.quoteGstPct;
    _model.ordGstApplicable = storedGst == null || storedGst > 0;
    _model.ordGstPct = (storedGst != null && storedGst > 0)
        ? storedGst.toStringAsFixed(0)
        : '$kGstDefaultPct';
    _model.ordGstinFieldTextController!.text = order.billingPartyGstin ?? '';
    _model.ordPorterCashCollectFieldTextController!.text =
        order.porterCashCollect?.toString() ?? '';

    _model.ordMoveDate = order.moveDate;
    _model.ordMoveDatePicked = true;

    // See new_lead_page_widget.dart's _loadExistingLead for why both the
    // model field and the dropdown's own FormFieldController need setting.
    _model.ordService = order.service;
    _model.ordServiceDropdownValue = order.service;
    _model.ordServiceDropdownValueController?.value = order.service;

    _model.ordBranch = order.branch;
    _model.ordBranchDropdownValue = order.branch;
    _model.ordBranchDropdownValueController?.value = order.branch;

    _model.ordType = order.orderType;
    _model.ordTypeDropdownValue = order.orderType;
    _model.ordTypeDropdownValueController?.value = order.orderType;

    final pctStr = order.porterCommissionPct != null
        ? order.porterCommissionPct!.toStringAsFixed(0)
        : '16';
    _model.ordPorterComm = pctStr;
    _model.ordPorterCommDropdownValue = pctStr;
    _model.ordPorterCommDropdownValueController?.value = pctStr;

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
            widget.orderId != null
                ? 'Edit Order'
                : FFLocalizations.of(context).getText(
                    'r5yeqjot' /* New Order */,
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
        body: (_model.branchesLoaded &&
                _model.availableBranches.isEmpty &&
                widget.orderId == null)
            ? _buildNoBranchState(context)
            : SafeArea(
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
                                    'awzv09jd' /* Customer */,
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
                                      _model.ordCustomerFieldTextController,
                                  focusNode: _model.ordCustomerFieldFocusNode,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText:
                                        FFLocalizations.of(context).getText(
                                      '5eykr8yi' /* Customer Name * */,
                                    ),
                                    hintText:
                                        FFLocalizations.of(context).getText(
                                      'inzvayo2' /* Full name */,
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
                                      .ordCustomerFieldTextControllerValidator
                                      .asValidator(context),
                                ),
                                TextFormField(
                                  controller:
                                      _model.ordPhoneFieldTextController,
                                  focusNode: _model.ordPhoneFieldFocusNode,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText:
                                        FFLocalizations.of(context).getText(
                                      'qj78jpcl' /* Phone * */,
                                    ),
                                    hintText:
                                        FFLocalizations.of(context).getText(
                                      'kzh2zgf1' /* +91 XXXXX XXXXX */,
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
                                      .ordPhoneFieldTextControllerValidator
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
                                    'mamavt7j' /* Move Details */,
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
                                      _model.ordFromCityFieldTextController,
                                  focusNode: _model.ordFromCityFieldFocusNode,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText:
                                        FFLocalizations.of(context).getText(
                                      'pqtmtigy' /* From City * */,
                                    ),
                                    hintText:
                                        FFLocalizations.of(context).getText(
                                      '7t7zx16p' /* Origin city */,
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
                                      .ordFromCityFieldTextControllerValidator
                                      .asValidator(context),
                                ),
                                TextFormField(
                                  controller:
                                      _model.ordToCityFieldTextController,
                                  focusNode: _model.ordToCityFieldFocusNode,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText:
                                        FFLocalizations.of(context).getText(
                                      '7uknf493' /* To City * */,
                                    ),
                                    hintText:
                                        FFLocalizations.of(context).getText(
                                      'rpzj35pp' /* Destination city */,
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
                                      .ordToCityFieldTextControllerValidator
                                      .asValidator(context),
                                ),
                                TextFormField(
                                  controller:
                                      _model.ordFromAddressFieldTextController,
                                  focusNode:
                                      _model.ordFromAddressFieldFocusNode,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText:
                                        FFLocalizations.of(context).getText(
                                      'wpim6v1x' /* From Address */,
                                    ),
                                    hintText:
                                        FFLocalizations.of(context).getText(
                                      'xmvalzhf' /* Pickup address */,
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
                                      .ordFromAddressFieldTextControllerValidator
                                      .asValidator(context),
                                ),
                                TextFormField(
                                  controller:
                                      _model.ordToAddressFieldTextController,
                                  focusNode: _model.ordToAddressFieldFocusNode,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText:
                                        FFLocalizations.of(context).getText(
                                      '7qgwc0ts' /* To Address */,
                                    ),
                                    hintText:
                                        FFLocalizations.of(context).getText(
                                      'gjo6q6u9' /* Drop address */,
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
                                      .ordToAddressFieldTextControllerValidator
                                      .asValidator(context),
                                ),
                                TextFormField(
                                  controller:
                                      _model.ordFromFloorFieldTextController,
                                  focusNode: _model.ordFromFloorFieldFocusNode,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText:
                                        FFLocalizations.of(context).getText(
                                      'ptpbyftb' /* From Floor */,
                                    ),
                                    hintText:
                                        FFLocalizations.of(context).getText(
                                      'cqx4d0tm' /* e.g. 2nd floor */,
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
                                      .ordFromFloorFieldTextControllerValidator
                                      .asValidator(context),
                                ),
                                TextFormField(
                                  controller:
                                      _model.ordToFloorFieldTextController,
                                  focusNode: _model.ordToFloorFieldFocusNode,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText:
                                        FFLocalizations.of(context).getText(
                                      '37ivzayq' /* To Floor */,
                                    ),
                                    hintText:
                                        FFLocalizations.of(context).getText(
                                      'gkhw0lho' /* e.g. Ground floor */,
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
                                      .ordToFloorFieldTextControllerValidator
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
                                                '87o00u95' /* Move Date * */,
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
                                            if (!(_model.ordMoveDatePicked ??
                                                false))
                                              Container(
                                                child: Text(
                                                  FFLocalizations.of(context)
                                                      .getText(
                                                    '98chvhj9' /* Tap to pick date */,
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
                                            if ((_model.ordMoveDatePicked ??
                                                    false) &&
                                                _model.ordMoveDate != null)
                                              Container(
                                                child: Text(
                                                  dateTimeFormat(
                                                      'd MMM y',
                                                      _model.ordMoveDate),
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
                                                // order's saved move date;
                                                // allow past dates so
                                                // editing an old order
                                                // doesn't assert.
                                                initialDate:
                                                    _model.ordMoveDate ??
                                                        getCurrentTimestamp,
                                                firstDate: DateTime(2020),
                                                lastDate: DateTime(2050),
                                                builder: (context, child) {
                                                  // FlutterFlow artifact fix:
                                                  // generated wrapper used
                                                  // fully transparent colors,
                                                  // rendering the ghost
                                                  // calendar. Same themed
                                                  // builder as the leads
                                                  // page fix.
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
                                              // dismissing used to null
                                              // ordMoveDate while setting
                                              // picked=true (crash).
                                              if (datePickedDate != null) {
                                                safeSetState(() {
                                                  _model.datePicked = DateTime(
                                                    datePickedDate.year,
                                                    datePickedDate.month,
                                                    datePickedDate.day,
                                                  );
                                                  _model.ordMoveDate =
                                                      _model.datePicked;
                                                  _model.ordMoveDatePicked =
                                                      true;
                                                });
                                              }
                                            },
                                            text: FFLocalizations.of(context)
                                                .getText(
                                              'cdnifhil' /* Pick Date */,
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
                                    'nco7t7r5' /* Pricing & Classification */,
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
                                      _model.ordAmountFieldTextController,
                                  focusNode: _model.ordAmountFieldFocusNode,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText:
                                        FFLocalizations.of(context).getText(
                                      'ksnfzp2x' /* Amount (₹) * */,
                                    ),
                                    hintText:
                                        FFLocalizations.of(context).getText(
                                      'j6tfu4aq' /* 0.00 */,
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
                                  onChanged: (_) => safeSetState(() {}),
                                  validator: _model
                                      .ordAmountFieldTextControllerValidator
                                      .asValidator(context),
                                ),
                                FlutterFlowDropDown<String>(
                                  controller: _model
                                          .ordServiceDropdownValueController ??=
                                      FormFieldController<String>(null),
                                  options: [
                                    FFLocalizations.of(context).getText(
                                      'vmn2hl08' /* House Shifting */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      'izvd10wn' /* Office Shifting */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      'xwgt552n' /* Vehicle Transport */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      'avp5p7ec' /* Storage */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      'f2jjjz82' /* Packing Only */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      'ob0kcq3s' /* Long Distance */,
                                    )
                                  ],
                                  onChanged: (val) async {
                                    safeSetState(() =>
                                        _model.ordServiceDropdownValue = val);
                                    _model.ordService =
                                        _model.ordServiceDropdownValue;
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
                                    'aaujq7tf' /* Select service */,
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
                                    'do548kxy' /* Service * */,
                                  ),
                                  labelTextStyle: const TextStyle(),
                                ),
                                FlutterFlowDropDown<String>(
                                  controller: _model
                                          .ordBranchDropdownValueController ??=
                                      FormFieldController<String>(null),
                                  // Was a hardcoded Chennai/Bengaluru/
                                  // Coimbatore list — an APC-shaped default
                                  // (NG-050 had the same disease in
                                  // default_pricing_config). Now the org's
                                  // real branches.dart rows, already
                                  // restricted to just the caller's own
                                  // branch for a non-owner session — see
                                  // _loadBranches().
                                  options: _model.availableBranches,
                                  onChanged: (val) async {
                                    safeSetState(() =>
                                        _model.ordBranchDropdownValue = val);
                                    _model.ordBranch =
                                        _model.ordBranchDropdownValue;
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
                                    'iugzql5f' /* Select branch */,
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
                                    'laad7rkm' /* Branch * */,
                                  ),
                                  labelTextStyle: const TextStyle(),
                                ),
                                FlutterFlowDropDown<String>(
                                  controller:
                                      _model.ordTypeDropdownValueController ??=
                                          FormFieldController<String>(null),
                                  options: [
                                    FFLocalizations.of(context).getText(
                                      'buwnzpqf' /* Direct */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      'n7wrocei' /* Porter */,
                                    )
                                  ],
                                  onChanged: (val) async {
                                    safeSetState(() =>
                                        _model.ordTypeDropdownValue = val);
                                    _model.ordType =
                                        _model.ordTypeDropdownValue;
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
                                    '4znc9ke0' /* Select type */,
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
                                    '581zy15a' /* Order Type * */,
                                  ),
                                  labelTextStyle: const TextStyle(),
                                ),
                                if (_model.ordType == 'Porter')
                                  SizedBox(
                                    width: double.infinity,
                                    child: FlutterFlowDropDown<String>(
                                      controller: _model
                                              .ordPorterCommDropdownValueController ??=
                                          FormFieldController<String>(null),
                                      options: [
                                        FFLocalizations.of(context).getText(
                                          'wl21eo0f' /* 16 */,
                                        ),
                                        FFLocalizations.of(context).getText(
                                          '8m4tknb1' /* 19 */,
                                        )
                                      ],
                                      onChanged: (val) async {
                                        safeSetState(() => _model
                                            .ordPorterCommDropdownValue = val);
                                        _model.ordPorterComm =
                                            _model.ordPorterCommDropdownValue;
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
                                            fontWeight:
                                                FlutterFlowTheme.of(context)
                                                    .bodyMedium
                                                    .fontWeight,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .bodyMedium
                                                    .fontStyle,
                                          ),
                                      hintText:
                                          FFLocalizations.of(context).getText(
                                        '4g75at47' /* Select commission */,
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
                                      borderColor: FlutterFlowTheme.of(context)
                                          .alternate,
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
                                        '3kefljy6' /* Porter Commission % */,
                                      ),
                                      labelTextStyle: const TextStyle(),
                                    ),
                                  ),
                                if (_model.ordType == 'Porter')
                                  TextFormField(
                                    controller: _model
                                        .ordPorterCashCollectFieldTextController,
                                    focusNode: _model
                                        .ordPorterCashCollectFieldFocusNode,
                                    obscureText: false,
                                    decoration: InputDecoration(
                                      labelText: FFLocalizations.of(context)
                                          .getText(
                                        'porcashcol1' /* Cash Collected by Porter (₹) */,
                                      ),
                                      hintText: FFLocalizations.of(context)
                                          .getText(
                                        'porcashcol2' /* Leave blank if none collected yet */,
                                      ),
                                      filled: true,
                                    ),
                                    style: const TextStyle(),
                                    keyboardType: TextInputType.number,
                                    onChanged: (_) => safeSetState(() {}),
                                  ),
                                if (_model.ordType == 'Porter')
                                  Builder(builder: (context) {
                                    // Settlement preview — ported from
                                    // apc_webapp App.jsx's order-form
                                    // preview (lines ~3719-3731).
                                    final amt = double.tryParse(_model
                                                .ordAmountFieldTextController
                                                .text) ??
                                            0.0;
                                    final cashCollect = double.tryParse(_model
                                                .ordPorterCashCollectFieldTextController
                                                .text) ??
                                        0.0;
                                    final pct =
                                        (double.tryParse(
                                                    _model.ordPorterComm ??
                                                        '16') ??
                                                16) /
                                            100;
                                    final adv = (amt - cashCollect)
                                        .clamp(0.0, double.infinity)
                                        .toDouble();
                                    final comm = (amt * pct).roundToDouble();
                                    final net = amt - comm;
                                    return Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: FlutterFlowTheme.of(context)
                                            .primaryBackground,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border: Border.all(
                                            color: FlutterFlowTheme.of(
                                                    context)
                                                .alternate),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Porter Settlement Preview',
                                              style: FlutterFlowTheme.of(
                                                      context)
                                                  .labelMedium),
                                          const SizedBox(height: 6),
                                          _settlementLine(context,
                                              'Advance (Porter paid)', adv),
                                          _settlementLine(context,
                                              'Commission (${_model.ordPorterComm}%)',
                                              comm),
                                          _settlementLine(context,
                                              'Net to APC (Quote − Comm)',
                                              net,
                                              bold: true),
                                        ],
                                      ),
                                    );
                                  }),
                                // ---- GST (20 Aug 2026) --------------------
                                // Toggle first, rate second: whether GST
                                // applies at all is the decision the office
                                // actually makes, and a rate dropdown shown
                                // for a non-GST job is a field to ignore.
                                // Writes the EXISTING quote_gst_* columns —
                                // no schema change — so a directly-booked
                                // order carries GST the same way a
                                // quote-converted one does, and the invoice
                                // generator reads one set of fields.
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  value: _model.ordGstApplicable,
                                  onChanged: (v) => safeSetState(
                                      () => _model.ordGstApplicable = v),
                                  title: const Text('Charge GST'),
                                  subtitle: Text(
                                    _model.ordGstApplicable
                                        ? 'Added on top of the amount above.'
                                        : 'No GST on this order.',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                if (_model.ordGstApplicable)
                                  Builder(builder: (context) {
                                    final amt = double.tryParse(_model
                                            .ordAmountFieldTextController
                                            .text) ??
                                        0.0;
                                    final pct = double.tryParse(
                                            _model.ordGstPct ??
                                                '$kGstDefaultPct') ??
                                        kGstDefaultPct.toDouble();
                                    final gst =
                                        (amt * pct / 100).roundToDouble();
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        DropdownButtonFormField<String>(
                                          initialValue: _model.ordGstPct,
                                          decoration: const InputDecoration(
                                            labelText: 'GST rate',
                                            filled: true,
                                          ),
                                          items: [
                                            // 0 is filtered out on purpose:
                                            // the toggle above already means
                                            // "no GST", so offering 0% here
                                            // creates a second, contradictory
                                            // way to say the same thing.
                                            for (final r in kGstRateOptions
                                                .where((r) => r > 0))
                                              DropdownMenuItem(
                                                value: '$r',
                                                child: Text('$r%'),
                                              ),
                                          ],
                                          onChanged: (v) => safeSetState(() =>
                                              _model.ordGstPct =
                                                  v ?? '$kGstDefaultPct'),
                                        ),
                                        const SizedBox(height: 6),
                                        // Says the total out loud, because
                                        // "Amount" alone is ambiguous about
                                        // whether tax is inside it.
                                        Text(
                                          'Taxable ₹${amt.toStringAsFixed(0)}'
                                          '  +  GST ₹${gst.toStringAsFixed(0)}'
                                          '  =  ₹${(amt + gst).toStringAsFixed(0)}',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 10),
                                      ],
                                    );
                                  }),
                                TextFormField(
                                  controller:
                                      _model.ordNotesFieldTextController,
                                  focusNode: _model.ordNotesFieldFocusNode,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText:
                                        FFLocalizations.of(context).getText(
                                      'viyeogi2' /* Notes */,
                                    ),
                                    hintText:
                                        FFLocalizations.of(context).getText(
                                      'c6uor7wa' /* Additional details */,
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
                                      .ordNotesFieldTextControllerValidator
                                      .asValidator(context),
                                ),
                                // RLS/GST audit, 12 Aug 2026: needed on a
                                // B2B tax invoice for the customer's input
                                // credit. Pre-filled from the matched
                                // customer's own gstin at save time when
                                // left blank (see the Save button below) —
                                // this field is for correcting or manually
                                // supplying it per order, not the only path
                                // it can come from.
                                TextFormField(
                                  controller: _model.ordGstinFieldTextController,
                                  focusNode: _model.ordGstinFieldFocusNode,
                                  textCapitalization: TextCapitalization.characters,
                                  obscureText: false,
                                  decoration: const InputDecoration(
                                    labelText: 'Customer GSTIN (optional)',
                                    hintText: '15-character GSTIN, for a B2B tax invoice',
                                    filled: true,
                                  ),
                                  style: const TextStyle(),
                                  validator: _model
                                      .ordGstinFieldTextControllerValidator
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
                              // Forces the explicit pick item 4 asks for
                              // (owner, multi-branch org, no default) and
                              // is also what stops a save going through
                              // with no branch at all if the org has zero
                              // active branches (item 5) or a staff row's
                              // own branch didn't resolve to one.
                              if (_model.ordBranch == null ||
                                  _model.ordBranch!.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Select a branch first.'),
                                  ),
                                );
                                return;
                              }

                              _model.ordSaveSuccess = false;
                              safeSetState(() {});

                              final isEditing = widget.orderId != null;
                              final isPorterOrder = _model.ordType == 'Porter';
                              // RLS/GST audit, 12 Aug 2026 — non-empty means
                              // a manual entry/correction on this form, which
                              // always wins. Empty on a NEW order triggers
                              // the copy-through from the matched customer's
                              // own gstin, below, once customer_id is known.
                              final gstinFieldText =
                                  _model.ordGstinFieldTextController.text.trim();
                              final amt = double.tryParse(
                                      _model.ordAmountFieldTextController.text) ??
                                  0.0;
                              // Porter settlement — see the settlement
                              // preview above and apc_webapp App.jsx
                              // lines ~3656-3736: cash the porter collects
                              // from the customer on delivery; whatever's
                              // left of the order amount is treated as the
                              // advance the porter already paid APC.
                              final cashCollect = isPorterOrder
                                  ? (double.tryParse(_model
                                              .ordPorterCashCollectFieldTextController
                                              .text) ??
                                      0.0)
                                  : 0.0;
                              final porterAdvance = isPorterOrder
                                  ? (amt - cashCollect)
                                      .clamp(0.0, double.infinity)
                                      .toDouble()
                                  : 0.0;

                              final editablePayload = {
                                'customer':
                                    _model.ordCustomerFieldTextController.text,
                                'phone':
                                    _model.ordPhoneFieldTextController.text,
                                'from_city':
                                    _model.ordFromCityFieldTextController.text,
                                'to_city':
                                    _model.ordToCityFieldTextController.text,
                                'from_address': _model
                                    .ordFromAddressFieldTextController.text,
                                'to_address':
                                    _model.ordToAddressFieldTextController.text,
                                'from_floor': int.tryParse(_model
                                    .ordFromFloorFieldTextController.text),
                                'to_floor': int.tryParse(
                                    _model.ordToFloorFieldTextController.text),
                                'move_date':
                                    supaSerialize<DateTime>(_model.ordMoveDate),
                                'amount': amt,
                                'service': _model.ordService,
                                'branch': _model.ordBranch,
                                // 'order_type' here has always meant
                                // Direct/Porter in this app (not the
                                // local/outstation split the reference web
                                // app uses that column for — this app has
                                // no local/outstation field at all).
                                'order_type': _model.ordType,
                                // Porter commission fields — previously
                                // captured in the form (ordPorterComm) but
                                // never actually saved. Fixed as part of
                                // porting the porter settlement feature.
                                'is_porter': isPorterOrder,
                                'order_source': isPorterOrder ? 'porter' : null,
                                'porter_commission_pct': isPorterOrder
                                    ? double.tryParse(
                                        _model.ordPorterComm ?? '16')
                                    : null,
                                'porter_cash_collect':
                                    isPorterOrder ? cashCollect : null,
                                // GST: reuses the existing quote_gst_*
                                // columns so a directly-booked order and a
                                // quote-converted one are read the same way
                                // by the invoice generator. 0 means
                                // "deliberately no GST", which is different
                                // from null ("never specified") — the 24
                                // legacy orders carrying null must stay
                                // distinguishable from a conscious choice.
                                'quote_gst_pct': _model.ordGstApplicable
                                    ? (double.tryParse(_model.ordGstPct ??
                                            '$kGstDefaultPct') ??
                                        kGstDefaultPct.toDouble())
                                    : 0.0,
                                'quote_gst_amount': _model.ordGstApplicable
                                    ? (amt *
                                            (double.tryParse(
                                                    _model.ordGstPct ??
                                                        '$kGstDefaultPct') ??
                                                kGstDefaultPct.toDouble()) /
                                            100)
                                        .roundToDouble()
                                    : 0.0,
                                'notes':
                                    _model.ordNotesFieldTextController.text,
                                // RLS/GST audit, 12 Aug 2026: a B2B tax
                                // invoice needs this for the customer's
                                // input credit. Manual entry here always
                                // wins; an empty field on a NEW order gets
                                // the copy-through fill below instead of
                                // staying null.
                                'billing_party_gstin':
                                    gstinFieldText.isEmpty ? null : gstinFieldText,
                              };

                              // Item 32: the insert below can be refused
                              // by the monthly-order-limit trigger or the
                              // expired-trial read-only guard, both of
                              // which raise P0001 with a sentence written
                              // for the vendor. Captured here so the
                              // failure branch can show it instead of the
                              // generic "Failed to save order".
                              String? saveError;
                              try {
                                if (isEditing) {
                                  // Editing an existing order: only touch
                                  // the fields on this form. status,
                                  // payment_status, tracking_status,
                                  // advance_paid etc. are left as-is —
                                  // editing shipment/customer details
                                  // shouldn't silently reset payment
                                  // progress or job status.
                                  // LEAK_AUDIT.md write-gap fix: matched
                                  // only on id before — now also requires
                                  // the row to belong to the current org.
                                  await OrdersTable().update(
                                    data: editablePayload,
                                    matchingRows: (q) => OrgScope.write(q)
                                        .eq('id', widget.orderId!),
                                  );
                                } else {
                                  final newOrderId = await _nextOrderId();
                                  // Order Details Session 1: this is the one
                                  // real place orders.customer_id should get
                                  // set (find-or-create by phone) — payment
                                  // time only re-resolves it defensively for
                                  // orders created before this fix landed.
                                  final customerId =
                                      await CustomerLookup.findOrCreate(
                                    orgId: OrgScope.currentOrgId!,
                                    name: _model
                                        .ordCustomerFieldTextController.text,
                                    phone: _model
                                        .ordPhoneFieldTextController.text,
                                  );
                                  // RLS/GST audit, 12 Aug 2026: only look up
                                  // the matched customer's own GSTIN when
                                  // the form field was left blank — a
                                  // manual entry above already won and this
                                  // must not overwrite it. Null for a
                                  // brand-new customer (nothing to copy)
                                  // stays null, same as before this fix.
                                  final copiedGstin = gstinFieldText.isEmpty
                                      ? await CustomerLookup.gstinFor(customerId)
                                      : null;
                                  _model.createdOrder =
                                      await OrdersTable().insert({
                                    'id': newOrderId,
                                    // Phase 1 multi-tenancy pass: stamp
                                    // every insert with the current org
                                    // (requires supabase/phase1_add_org_id.sql
                                    // to be run first).
                                    ...OrgScope.stamp(),
                                    ...editablePayload,
                                    if (customerId != null)
                                      'customer_id': customerId,
                                    if (copiedGstin != null)
                                      'billing_party_gstin': copiedGstin,
                                    'status': 'booked',
                                    'payment_status':
                                        isPorterOrder && porterAdvance > 0
                                            ? 'partial'
                                            : 'pending',
                                    'tracking_status': 'Booked',
                                    'advance_paid':
                                        isPorterOrder ? porterAdvance : 0.0,
                                  });
                                }
                                _model.ordSaveSuccess = true;
                              } catch (e) {
                                _model.ordSaveSuccess = false;
                                saveError = extractDbErrorMessage(e,
                                    fallback: '');
                              }
                              safeSetState(() {});
                              if (_model.ordSaveSuccess!) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isEditing
                                          ? 'Order updated successfully!'
                                          : 'Order saved successfully!',
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
                                  context
                                      .pushNamed(OrdersPageWidget.routeName);
                                }
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      (saveError != null &&
                                              saveError.isNotEmpty)
                                          ? saveError
                                          : 'Failed to save order. Please try again.',
                                      style: const TextStyle(),
                                    ),
                                    duration:
                                        const Duration(milliseconds: 5000),
                                  ),
                                );
                              }

                              safeSetState(() {});
                            },
                            text: widget.orderId != null
                                ? 'Update Order'
                                : FFLocalizations.of(context).getText(
                                    'j7jprv8l' /* Save Order */,
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

  Widget _settlementLine(BuildContext context, String label, double value,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: bold
                  ? FlutterFlowTheme.of(context).bodyMedium.override(
                      font: GoogleFonts.inter(fontWeight: FontWeight.w600))
                  : FlutterFlowTheme.of(context).bodySmall.override(
                      font: GoogleFonts.inter(),
                      color: FlutterFlowTheme.of(context).secondaryText)),
          Text('₹${value.toStringAsFixed(0)}',
              style: FlutterFlowTheme.of(context)
                  .bodyMedium
                  .override(
                      font: GoogleFonts.interTight(
                          fontWeight: FontWeight.w600),
                      color: FlutterFlowTheme.of(context).primary)),
        ],
      ),
    );
  }
}
