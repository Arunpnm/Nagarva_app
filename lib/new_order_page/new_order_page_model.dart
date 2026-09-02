import '/backend/pricing_defaults.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/form_field_controller.dart';
import '/index.dart';
import 'new_order_page_widget.dart' show NewOrderPageWidget;
import 'package:flutter/material.dart';

class NewOrderPageModel extends FlutterFlowModel<NewOrderPageWidget> {
  ///  Local state fields for this page.

  String? ordService = 'House Shifting';

  // No hardcoded default (was the literal 'Bengaluru' — an APC-shaped
  // default that let every order silently land in the wrong branch unless
  // the creator noticed and changed the dropdown). Set in
  // _NewOrderPageWidgetState._loadBranches(): null for an owner session
  // (forces an explicit pick), the staff's own branch for a staff session.
  String? ordBranch;

  /// This org's active branch names (`branches.name`, org-scoped), loaded
  /// once in initState. Empty means the org hasn't set up a branch yet —
  /// the widget blocks New Order entirely in that case rather than letting
  /// the old hardcoded 3-city list paper over it.
  List<String> availableBranches = [];
  bool branchesLoaded = false;

  /// Distinct from [availableBranches] being empty: that can also mean a
  /// staff session whose own `staff.branch` isn't one of them. This one is
  /// specifically "the org itself has no active branch row yet", which is
  /// the case that needs a "go set one up" message rather than a
  /// "your account needs fixing" one.
  bool orgHasAnyBranches = true;

  String? ordType = 'Direct';

  DateTime? ordMoveDate;

  /// Lead source this job came from — `lead_sources.code`, written to
  /// `orders.order_source`. Selecting one OFFERS its configured
  /// commission rate as the default for [ordCommissionFieldTextController]
  /// (a vendor-authored rate, which CLAUDE.md's "No suggested money"
  /// convention explicitly permits — unlike the old hardcoded 16/19,
  /// which were APC's rates shown to every tenant).
  String? ordLeadSourceCode;
  List<LeadSourcesRow> leadSources = [];

  /// Whether a commission is owed on this job — the snapshot that will be
  /// written to `orders.commission_expected`.
  ///
  /// Held as STATE rather than recomputed at save time, and the difference
  /// is not cosmetic. Recomputing would read the lead source's `is_paid`
  /// as it stands at save; on an EDIT that turns any unrelated change (a
  /// corrected address, a moved date) into a silent re-pricing of a job
  /// already done, if that source has been flipped paid/unpaid since. This
  /// is set exactly where the answer legitimately changes: when the order
  /// is loaded for editing (from the stored snapshot), and when the vendor
  /// picks a lead source. Null on a fresh form means "nothing has decided
  /// yet" and the Porter toggle answers it.
  bool? ordCommissionExpected;

  /// FK to the `lead_sources` row, held as state for the same reason as
  /// [ordCommissionExpected]: resolving it from the picker at save time
  /// would write NULL whenever the source cannot be found in the list —
  /// which happens routinely, because the picker only loads ACTIVE
  /// sources. Editing an old order whose source has since been retired
  /// would silently drop its attribution.
  String? ordLeadSourceId;

  // GST (20 Aug 2026). Defaults to charging GST at the configured default
  // rate: for an Indian mover a taxable invoice is the normal case, so the
  // toggle starts ON and the exception is the thing you switch off.
  bool ordGstApplicable = true;
  String? ordGstPct = '$kGstDefaultPct';

  bool? ordSaveSuccess = false;

  bool? ordMoveDatePicked = false;

  ///  State fields for stateful widgets in this page.

  // State field(s) for OrdCustomerField widget.
  FocusNode? ordCustomerFieldFocusNode;
  TextEditingController? ordCustomerFieldTextController;
  String? Function(BuildContext, String?)?
      ordCustomerFieldTextControllerValidator;
  // State field(s) for OrdPhoneField widget.
  FocusNode? ordPhoneFieldFocusNode;
  TextEditingController? ordPhoneFieldTextController;
  String? Function(BuildContext, String?)? ordPhoneFieldTextControllerValidator;
  // State field(s) for OrdFromCityField widget.
  FocusNode? ordFromCityFieldFocusNode;
  TextEditingController? ordFromCityFieldTextController;
  String? Function(BuildContext, String?)?
      ordFromCityFieldTextControllerValidator;
  // State field(s) for OrdToCityField widget.
  FocusNode? ordToCityFieldFocusNode;
  TextEditingController? ordToCityFieldTextController;
  String? Function(BuildContext, String?)?
      ordToCityFieldTextControllerValidator;
  // State field(s) for OrdFromAddressField widget.
  FocusNode? ordFromAddressFieldFocusNode;
  TextEditingController? ordFromAddressFieldTextController;
  String? Function(BuildContext, String?)?
      ordFromAddressFieldTextControllerValidator;
  // State field(s) for OrdToAddressField widget.
  FocusNode? ordToAddressFieldFocusNode;
  TextEditingController? ordToAddressFieldTextController;
  String? Function(BuildContext, String?)?
      ordToAddressFieldTextControllerValidator;
  // State field(s) for OrdFromFloorField widget.
  FocusNode? ordFromFloorFieldFocusNode;
  TextEditingController? ordFromFloorFieldTextController;
  String? Function(BuildContext, String?)?
      ordFromFloorFieldTextControllerValidator;
  // State field(s) for OrdToFloorField widget.
  FocusNode? ordToFloorFieldFocusNode;
  TextEditingController? ordToFloorFieldTextController;
  String? Function(BuildContext, String?)?
      ordToFloorFieldTextControllerValidator;
  DateTime? datePicked;
  // State field(s) for OrdAmountField widget.
  FocusNode? ordAmountFieldFocusNode;
  TextEditingController? ordAmountFieldTextController;
  String? Function(BuildContext, String?)?
      ordAmountFieldTextControllerValidator;
  // State field(s) for OrdServiceDropdown widget.
  String? ordServiceDropdownValue;
  FormFieldController<String>? ordServiceDropdownValueController;
  // State field(s) for OrdBranchDropdown widget.
  String? ordBranchDropdownValue;
  FormFieldController<String>? ordBranchDropdownValueController;
  // State field(s) for OrdTypeDropdown widget.
  String? ordTypeDropdownValue;
  FormFieldController<String>? ordTypeDropdownValueController;
  // State field(s) for OrdLeadSourceDropdown widget.
  String? ordLeadSourceDropdownValue;
  FormFieldController<String>? ordLeadSourceDropdownValueController;
  // Commission %, free numeric entry 0-100 (2 Sept 2026). Was a hardcoded
  // 16/19 dropdown defaulting to '16' — APC's own porter rates, applied to
  // every tenant, and written to Postgres for a vendor who never chose
  // them. EMPTY means not priced and saves NULL; see
  // /backend/commission_pricing.dart for why null must never be read as a
  // rate.
  FocusNode? ordCommissionFieldFocusNode;
  TextEditingController? ordCommissionFieldTextController;
  String? Function(BuildContext, String?)?
      ordCommissionFieldTextControllerValidator;
  // State field(s) for OrdNotesField widget.
  FocusNode? ordNotesFieldFocusNode;
  TextEditingController? ordNotesFieldTextController;
  String? Function(BuildContext, String?)? ordNotesFieldTextControllerValidator;
  // State field(s) for OrdGstinField widget (RLS/GST audit, 12 Aug 2026) —
  // customer's GSTIN, needed on a B2B tax invoice for their input credit.
  // Pre-filled from customers.gstin when an existing customer is matched
  // by phone at save time; editable so it can be corrected per order.
  FocusNode? ordGstinFieldFocusNode;
  TextEditingController? ordGstinFieldTextController;
  String? Function(BuildContext, String?)? ordGstinFieldTextControllerValidator;
  // Porter settlement fields — only relevant when ordType == 'Porter'.
  // Ported from apc_webapp App.jsx's order-form settlement preview
  // (lines ~3656-3736): cash the porter/driver collects from the customer
  // on delivery; the difference between the order amount and that cash is
  // what the porter already paid APC up front (the "advance").
  FocusNode? ordPorterCashCollectFieldFocusNode;
  TextEditingController? ordPorterCashCollectFieldTextController;
  String? Function(BuildContext, String?)?
      ordPorterCashCollectFieldTextControllerValidator;
  // Stores action output result for [Backend Call - Insert Row] action in SaveOrderBtn widget.
  OrdersRow? createdOrder;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    ordPorterCashCollectFieldFocusNode?.dispose();
    ordPorterCashCollectFieldTextController?.dispose();

    ordCommissionFieldFocusNode?.dispose();
    ordCommissionFieldTextController?.dispose();

    ordCustomerFieldFocusNode?.dispose();
    ordCustomerFieldTextController?.dispose();

    ordPhoneFieldFocusNode?.dispose();
    ordPhoneFieldTextController?.dispose();

    ordFromCityFieldFocusNode?.dispose();
    ordFromCityFieldTextController?.dispose();

    ordToCityFieldFocusNode?.dispose();
    ordToCityFieldTextController?.dispose();

    ordFromAddressFieldFocusNode?.dispose();
    ordFromAddressFieldTextController?.dispose();

    ordToAddressFieldFocusNode?.dispose();
    ordToAddressFieldTextController?.dispose();

    ordFromFloorFieldFocusNode?.dispose();
    ordFromFloorFieldTextController?.dispose();

    ordToFloorFieldFocusNode?.dispose();
    ordToFloorFieldTextController?.dispose();

    ordAmountFieldFocusNode?.dispose();
    ordAmountFieldTextController?.dispose();

    ordNotesFieldFocusNode?.dispose();
    ordNotesFieldTextController?.dispose();

    ordGstinFieldFocusNode?.dispose();
    ordGstinFieldTextController?.dispose();
  }
}
