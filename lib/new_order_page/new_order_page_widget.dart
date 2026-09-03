import '/app_session.dart';
import '/backend/customer_lookup.dart';
import '/backend/edge_function_errors.dart';
import '/backend/pricing_defaults.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_drop_down.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/form_field_controller.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    _model.ordCommissionFieldTextController ??= TextEditingController();
    _model.ordCommissionFieldFocusNode ??= FocusNode();

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

    SchedulerBinding.instance.addPostFrameCallback((_) {
      _loadBranches();
      _loadLeadSources();
    });
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
                // Owner goes straight to the branch editor (27 Aug 2026);
                // a non-owner can't create one, so Settings is the honest
                // destination for them — Branches would only say "owner
                // only", which is what the body text above already says.
                onPressed: () => context.pushNamed(
                  AppSession.instance.currentStaffId == null
                      ? BranchesPage.routeName
                      : SettingsPageWidget.routeName,
                ),
                text: AppSession.instance.currentStaffId == null
                    ? 'Set up a branch'
                    : 'Go to Settings',
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
  /// Commission is entered whenever the job could carry one: an explicit
  /// Porter order, or any configured lead source other than direct.
  /// Deliberately WIDER than `commissionStateFor`'s unpriced test: the
  /// field is offered on any selected lead source so a one-off cut can be
  /// entered, while only an order whose `commission_expected` snapshot is
  /// true gets FLAGGED when left blank. Offering a field costs nothing; a
  /// false "unpriced" warning on every walk-in costs the warning's
  /// credibility.
  bool get _showCommissionField =>
      _model.ordType == 'Porter' || (_model.ordLeadSourceCode ?? '').isNotEmpty;
  // Note the form is DELIBERATELY wider than commissionStateFor's
  // "unpriced" test: offering the field on any selected lead source lets a
  // vendor price a paid directory, while only a porter job is FLAGGED when
  // left blank. Offering a field is free; a false "unpriced" warning on
  // every walk-in is not.

  /// True when this order names a source the picker did not load — it was
  /// deactivated after the order was placed.
  bool get _leadSourceIsRetired {
    final code = _model.ordLeadSourceCode;
    if (code == null || code.isEmpty) return false;
    return !_model.leadSources.any((src) => src.code == code);
  }

  LeadSourcesRow? get _selectedLeadSource {
    final code = _model.ordLeadSourceCode;
    if (code == null || code.isEmpty) return null;
    for (final src in _model.leadSources) {
      if (src.code == code) return src;
    }
    return null;
  }

  /// Was a commission owed on this job at all? Snapshotted, not inferred
  /// later.
  ///
  /// Taken from the selected source's `is_paid`. With NO source selected
  /// the legacy Porter toggle stands in, because that is exactly what the
  /// old `is_porter` column meant and a porter booking always owes a cut —
  /// dropping it would silently stop flagging unpriced porter jobs, which
  /// is the single most common commission-bearing order in this product.
  bool get _commissionExpected =>
      _model.ordCommissionExpected ?? (_model.ordType == 'Porter');

  /// Recompute the expectation — called ONLY when the vendor picks a lead
  /// source, which is the one moment the answer legitimately changes.
  void _refreshCommissionExpected() {
    final src = _selectedLeadSource;
    _model.ordCommissionExpected =
        src != null ? (src.isPaid ?? false) : (_model.ordType == 'Porter');
  }

  bool get _commissionIsBlank =>
      (_model.ordCommissionFieldTextController?.text ?? '').trim().isEmpty;

  /// Trimmed percentage, or null when the vendor left it blank.
  ///
  /// Null is the whole point: it reaches Postgres as NULL and reads back as
  /// "not priced". This replaces `double.tryParse(_model.ordPorterComm ??
  /// '16')`, which wrote APC's rate for a vendor who never chose one.
  double? get _commissionPctOrNull {
    if (!_showCommissionField || _commissionIsBlank) return null;
    final n = double.tryParse(
        (_model.ordCommissionFieldTextController?.text ?? '').trim());
    if (n == null || n < 0 || n > 100) return null;
    return n;
  }

  static String _leadSourceLabel(LeadSourcesRow src) {
    final pct = src.commissionPct;
    if (pct == null) return src.name;
    final asText = pct % 1 == 0 ? pct.toStringAsFixed(0) : pct.toString();
    return '${src.name} \u00b7 $asText%';
  }

  /// The rate a freshly-picked lead source offers, as field text.
  ///
  /// This is a DEFAULT, not a suggestion the app invented: the number is
  /// the vendor's own `lead_sources.commission_pct`, which CLAUDE.md's "No
  /// suggested money" convention explicitly permits ("applying
  /// vendor-configured rates ... is the vendor deciding"). A source with no
  /// rate configured yields an empty field, never a fallback.
  String _defaultCommissionFor(String? code) {
    if (code == null || code.isEmpty) return '';
    for (final src in _model.leadSources) {
      if (src.code == code) {
        final pct = src.commissionPct;
        if (pct == null) return '';
        return pct % 1 == 0 ? pct.toStringAsFixed(0) : pct.toString();
      }
    }
    return '';
  }

  Future<void> _loadLeadSources() async {
    try {
      final rows = await LeadSourcesTable().queryRows(
        queryFn: (q) =>
            OrgScope.read(q).eq('active', true).order('sort_order'),
      );
      if (!mounted) return;
      safeSetState(() => _model.leadSources = rows);
    } catch (_) {
      // A lead-source list that fails to load must not block order entry:
      // the commission field still appears for a Porter order and can be
      // typed by hand. Failing open here costs nothing, because the field
      // itself is the source of truth for what gets saved.
    }
  }

  Future<void> _loadBranches() async {
    // GUARDED. Branch is mandatory, so a failure here does not merely
    // degrade the page - it blocks the whole form, and it used to do so
    // silently: empty dropdown, and "Select a branch first" on save,
    // which blames the vendor for a query that died.
    List<String> orgBranches;
    try {
      final rows = await BranchesTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('active', true).order('name'),
      );
      orgBranches = rows.map((r) => r.name).toList();
      _model.branchLoadError = null;
    } catch (e) {
      if (!mounted) return;
      _model.branchLoadError = 'Could not load branches: $e';
      _model.branchesLoaded = false;
      safeSetState(() {});
      return;
    }
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

    // Editing shows the rate STORED ON THIS ORDER, never the lead source's
    // current rate — re-reading the source here is exactly the re-pricing
    // that brief §44 forbids. A null stays blank: the order is unpriced,
    // and opening the form must not quietly price it.
    _model.ordLeadSourceCode = order.orderSource;
    _model.ordLeadSourceDropdownValue = order.orderSource;
    _model.ordLeadSourceDropdownValueController?.value = order.orderSource;
    // The STORED expectation, not one re-derived from the source's current
    // `is_paid`. Re-deriving here would let a source flipped to unpaid
    // months later un-owe the commission on a job already delivered, just
    // because somebody opened the form.
    _model.ordCommissionExpected = order.commissionExpected ?? false;
    _model.ordLeadSourceId = order.leadSourceId;

    final pct = order.commissionPct;
    _model.ordCommissionFieldTextController?.text = pct == null
        ? ''
        : (pct % 1 == 0 ? pct.toStringAsFixed(0) : pct.toString());

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
                : AppLocalizations.of(context).newOrder,
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
                                  AppLocalizations.of(context).newOrderPageCustomer,
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
                                        AppLocalizations.of(context).newOrderPageCustomerName,
                                    hintText:
                                        AppLocalizations.of(context).fullName,
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
                                        AppLocalizations.of(context).newOrderPagePhone,
                                    hintText:
                                        AppLocalizations.of(context).n91XxxxxXxxxx,
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
                                  AppLocalizations.of(context).moveDetails,
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
                                        AppLocalizations.of(context).fromCity,
                                    hintText:
                                        AppLocalizations.of(context).originCity,
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
                                        AppLocalizations.of(context).toCity,
                                    hintText:
                                        AppLocalizations.of(context).destinationCity,
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
                                        AppLocalizations.of(context).fromAddress,
                                    hintText:
                                        AppLocalizations.of(context).pickupAddress,
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
                                        AppLocalizations.of(context).toAddress,
                                    hintText:
                                        AppLocalizations.of(context).dropAddress,
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
                                        AppLocalizations.of(context).fromFloor,
                                    hintText:
                                        AppLocalizations.of(context).eG2ndFloor,
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
                                        AppLocalizations.of(context).toFloor,
                                    hintText:
                                        AppLocalizations.of(context).eGGroundFloor,
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
                                              AppLocalizations.of(context).newOrderPageMoveDate,
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
                                                  AppLocalizations.of(context).tapToPickDate,
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
                                            text: AppLocalizations.of(context).pickDate,
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
                                  AppLocalizations.of(context).pricingClassification,
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
                                        AppLocalizations.of(context).newOrderPageAmount,
                                    hintText:
                                        AppLocalizations.of(context).n000,
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
                                    AppLocalizations.of(context).houseShifting,
                                    AppLocalizations.of(context).officeShifting,
                                    AppLocalizations.of(context).vehicleTransport,
                                    AppLocalizations.of(context).storage,
                                    AppLocalizations.of(context).packingOnly,
                                    AppLocalizations.of(context).longDistance
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
                                  hintText: AppLocalizations.of(context).selectService,
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
                                      AppLocalizations.of(context).newOrderPageService,
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
                                  hintText: AppLocalizations.of(context).selectBranch,
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
                                      AppLocalizations.of(context).branch,
                                  labelTextStyle: const TextStyle(),
                                ),
                                FlutterFlowDropDown<String>(
                                  controller:
                                      _model.ordTypeDropdownValueController ??=
                                          FormFieldController<String>(null),
                                  options: [
                                    AppLocalizations.of(context).direct,
                                    AppLocalizations.of(context).newOrderPagePorter
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
                                  hintText: AppLocalizations.of(context).selectType,
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
                                      AppLocalizations.of(context).orderType,
                                  labelTextStyle: const TextStyle(),
                                ),
                                // Lead source + commission (2 Sept 2026).
                                // Replaces the old 16/19 dropdown, which
                                // hardcoded APC's two porter rates for every
                                // tenant and wrote 16 even when untouched.
                                // Shown for any commission-bearing order, not
                                // only Porter ones — commission is now a
                                // property of WHERE THE JOB CAME FROM.
                                if (_model.leadSources.isNotEmpty)
                                  Padding(
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            0, 0, 0, 12),
                                    child: DropdownButtonFormField<String>(
                                      value: _model.ordLeadSourceCode,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        labelText: 'Lead source',
                                        filled: true,
                                        fillColor: FlutterFlowTheme.of(context)
                                            .secondaryBackground,
                                      ),
                                      items: [
                                        const DropdownMenuItem<String>(
                                          value: null,
                                          child:
                                              Text('Direct - no commission'),
                                        ),
                                        // A retired source still has to
                                        // appear, or DropdownButtonFormField
                                        // asserts on a value with no
                                        // matching item and the whole form
                                        // fails to build. Editing an old
                                        // order whose source was later
                                        // deactivated is an ordinary thing
                                        // to do, not an edge case.
                                        if (_leadSourceIsRetired)
                                          DropdownMenuItem<String>(
                                            value: _model.ordLeadSourceCode,
                                            child: Text(
                                              '${_model.ordLeadSourceCode} '
                                              '(no longer active)',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        for (final src in _model.leadSources)
                                          DropdownMenuItem<String>(
                                            value: src.code,
                                            child: Text(
                                              _leadSourceLabel(src),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                      onChanged: (val) => safeSetState(() {
                                        _model.ordLeadSourceCode = val;
                                        _refreshCommissionExpected();
                                        _model.ordLeadSourceId =
                                            _selectedLeadSource?.id;
                                        // Snapshot semantics start here: the
                                        // source's rate is COPIED into the
                                        // field, and the field is what gets
                                        // saved. Nothing re-reads the source
                                        // afterwards, so editing a lead
                                        // source's rate later cannot
                                        // re-price this order (brief §44).
                                        _model.ordCommissionFieldTextController
                                            ?.text = _defaultCommissionFor(val);
                                      }),
                                    ),
                                  ),
                                if (_showCommissionField)
                                  Padding(
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            0, 0, 0, 4),
                                    child: TextFormField(
                                      controller:
                                          _model.ordCommissionFieldTextController,
                                      focusNode:
                                          _model.ordCommissionFieldFocusNode,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(
                                            RegExp(r'[0-9.]')),
                                      ],
                                      onChanged: (_) => safeSetState(() {}),
                                      decoration: InputDecoration(
                                        labelText: 'Commission %',
                                        // No example number in the hint: an
                                        // "e.g. 16" anchors exactly the way
                                        // the old dropdown did.
                                        hintText:
                                            'Leave blank if not decided yet',
                                        suffixText: '%',
                                        filled: true,
                                        fillColor: FlutterFlowTheme.of(context)
                                            .secondaryBackground,
                                      ),
                                      validator: (v) {
                                        final t = (v ?? '').trim();
                                        if (t.isEmpty) return null;
                                        final n = double.tryParse(t);
                                        if (n == null) {
                                          return 'Enter a number, or leave blank';
                                        }
                                        // Mirrors the DB CHECK on
                                        // lead_sources.commission_pct.
                                        if (n < 0 || n > 100) {
                                          return 'Must be between 0 and 100';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                if (_showCommissionField && _commissionIsBlank)
                                  Padding(
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            0, 0, 0, 12),
                                    child: Text(
                                      'Saved as not priced. This order stays '
                                      'flagged in reports until a rate is set '
                                      '- it is never costed at a guessed rate.',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                      ),
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
                                      labelText: AppLocalizations.of(context).cashCollectedByPorter,
                                      hintText: AppLocalizations.of(context).leaveBlankIfNoneCollectedYet,
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
                                    // Null when the vendor has not priced
                                    // this yet. The preview then shows no
                                    // commission and no net rather than
                                    // computing both off a guessed rate —
                                    // a settlement preview is the single
                                    // most persuasive place to show a
                                    // wrong number, because it reads as
                                    // already agreed.
                                    final pctValue = _commissionPctOrNull;
                                    final adv = (amt - cashCollect)
                                        .clamp(0.0, double.infinity)
                                        .toDouble();
                                    final comm = pctValue == null
                                        ? null
                                        : (amt * (pctValue / 100))
                                            .roundToDouble();
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
                                          if (comm == null)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 4),
                                              child: Text(
                                                'Commission not priced — enter '
                                                'a % above to see the net.',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .secondaryText,
                                                ),
                                              ),
                                            )
                                          else ...[
                                            _settlementLine(
                                                context,
                                                'Commission '
                                                '(${_commissionPctOrNull}%)',
                                                comm),
                                            // "Net to you", not "Net to APC":
                                            // this is a multi-tenant product
                                            // and APC is one tenant.
                                            _settlementLine(context,
                                                'Net to you (Quote − Comm)',
                                                amt - comm,
                                                bold: true),
                                          ],
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
                                        AppLocalizations.of(context).notes,
                                    hintText:
                                        AppLocalizations.of(context).additionalDetails,
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
                                  SnackBar(
                                    content: Text(_model.branchLoadError != null
                                        ? 'Branches could not be loaded, so none can be picked. Pull to retry or reopen this page.'
                                        : 'Select a branch first.'),
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
                                // Commission (2 Sept 2026). `commission_pct`
                                // is a SNAPSHOT of the rate agreed at order
                                // time — copied from the lead source when
                                // one was picked, then owned by this row.
                                // Editing that source's rate later must
                                // never re-price this order (brief §44,
                                // the storage-rate rule).
                                //
                                // NULL when the vendor left it blank, and
                                // that null is load-bearing: it reads back
                                // as "not priced" and is surfaced, never
                                // costed. This used to be
                                // `?? '16'` — APC's own porter rate,
                                // written to Postgres for any vendor who
                                // never touched the dropdown.
                                // The three commission fields are written
                                // TOGETHER, as one snapshot of the terms
                                // agreed now. commission_expected comes
                                // from the source's `is_paid` at this
                                // moment; nothing re-reads the source
                                // later, so flipping a source to unpaid
                                // next month cannot un-owe a commission on
                                // a job already done (brief §44).
                                'commission_expected': _commissionExpected,
                                'commission_pct': _commissionPctOrNull,
                                'lead_source_id': _model.ordLeadSourceId,
                                'order_source': _model.ordLeadSourceCode ??
                                    (isPorterOrder ? 'porter' : null),
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
                                : AppLocalizations.of(context).saveOrder,
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
