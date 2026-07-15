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

    _model.ordPorterCashCollectFieldTextController ??= TextEditingController();
    _model.ordPorterCashCollectFieldFocusNode ??= FocusNode();

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
                                            if (!_model.ordMoveDatePicked!)
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
                                            if (_model.ordMoveDatePicked ??
                                                true)
                                              Container(
                                                child: Text(
                                                  _model.ordMoveDate!
                                                      .toString(),
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
                                                initialDate:
                                                    getCurrentTimestamp,
                                                firstDate: getCurrentTimestamp,
                                                lastDate: DateTime(2050),
                                                builder: (context, child) {
                                                  return wrapInMaterialDatePickerTheme(
                                                    context,
                                                    child!,
                                                    headerBackgroundColor:
                                                        const Color(0x00000000),
                                                    headerForegroundColor:
                                                        const Color(0x00000000),
                                                    headerTextStyle:
                                                        const TextStyle(),
                                                    pickerBackgroundColor:
                                                        const Color(0x00000000),
                                                    pickerForegroundColor:
                                                        const Color(0x00000000),
                                                    selectedDateTimeBackgroundColor:
                                                        const Color(0x00000000),
                                                    selectedDateTimeForegroundColor:
                                                        const Color(0x00000000),
                                                    actionButtonForegroundColor:
                                                        const Color(0x00000000),
                                                    iconSize: 24,
                                                  );
                                                },
                                              );

                                              if (datePickedDate != null) {
                                                safeSetState(() {
                                                  _model.datePicked = DateTime(
                                                    datePickedDate.year,
                                                    datePickedDate.month,
                                                    datePickedDate.day,
                                                  );
                                                });
                                              } else if (_model.datePicked !=
                                                  null) {
                                                safeSetState(() {
                                                  _model.datePicked =
                                                      getCurrentTimestamp;
                                                });
                                              }
                                              _model.ordMoveDate =
                                                  _model.datePicked;
                                              safeSetState(() {});
                                              _model.ordMoveDatePicked = true;
                                              safeSetState(() {});
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
                                  options: [
                                    FFLocalizations.of(context).getText(
                                      'd51qs0x3' /* Chennai */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      'g7j9rilc' /* Bengaluru */,
                                    ),
                                    FFLocalizations.of(context).getText(
                                      '0kll1iju' /* Coimbatore */,
                                    )
                                  ],
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
                              ].divide(const SizedBox(height: 14.0)),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 16.0, 0.0, 16.0),
                          child: FFButtonWidget(
                            onPressed: () async {
                              _model.ordSaveSuccess = false;
                              safeSetState(() {});

                              final isEditing = widget.orderId != null;
                              final isPorterOrder = _model.ordType == 'Porter';
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
                                'notes':
                                    _model.ordNotesFieldTextController.text,
                              };

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
                                  _model.createdOrder =
                                      await OrdersTable().insert({
                                    // Phase 1 multi-tenancy pass: stamp
                                    // every insert with the current org
                                    // (requires supabase/phase1_add_org_id.sql
                                    // to be run first).
                                    ...OrgScope.stamp(),
                                    ...editablePayload,
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
                              } catch (_) {
                                _model.ordSaveSuccess = false;
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
                                  const SnackBar(
                                    content: Text(
                                      'Failed to save order. Please try again.',
                                      style: TextStyle(),
                                    ),
                                    duration: Duration(milliseconds: 4000),
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
