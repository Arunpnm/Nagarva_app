import '/backend/edge_function_errors.dart';
import '/config/app_config.dart';
import '/components/ng_widgets.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_drop_down.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/ng_tokens.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/l10n/gen/app_localizations.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/form_field_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'quick_expense_page_model.dart';
export 'quick_expense_page_model.dart';

/// Quickly record a business expense.
class QuickExpensePageWidget extends StatefulWidget {
  const QuickExpensePageWidget({super.key});

  static String routeName = 'QuickExpensePage';
  static String routePath = '/quick-expense';

  @override
  State<QuickExpensePageWidget> createState() => _QuickExpensePageWidgetState();
}

class _QuickExpensePageWidgetState extends State<QuickExpensePageWidget> {
  late QuickExpensePageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => QuickExpensePageModel());

    _model.expAmountFieldTextController ??= TextEditingController();
    _model.expAmountFieldFocusNode ??= FocusNode();

    // Load recent orders for the optional link dropdown.
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      final rows = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).order('created_at').limit(25),
      );
      _model.recentOrders = rows.toList().cast<OrdersRow>();
      safeSetState(() {});
    });

    _model.expDateFieldTextController ??= TextEditingController();
    _model.expDateFieldFocusNode ??= FocusNode();

    _model.expOrderIdFieldTextController ??= TextEditingController();
    _model.expOrderIdFieldFocusNode ??= FocusNode();

    _model.expDescFieldTextController ??= TextEditingController();
    _model.expDescFieldFocusNode ??= FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
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
        backgroundColor: NgPalette.of(context).bg,
        appBar: NgSimpleBar(title: AppLocalizations.of(context).quickExpense, close: true),
        body: SafeArea(
          top: true,
          child: Container(
            decoration: BoxDecoration(
              color: NgPalette.of(context).bg,
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
                                  AppLocalizations.of(context).expenseDetails,
                                  style: FlutterFlowTheme.of(context)
                                      .titleSmall
                                      .override(
                                        font: NgFonts.geist(
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
                                      _model.expAmountFieldTextController,
                                  focusNode: _model.expAmountFieldFocusNode,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText:
                                        AppLocalizations.of(context).amount,
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
                                  validator: _model
                                      .expAmountFieldTextControllerValidator
                                      .asValidator(context),
                                ),
                                FlutterFlowDropDown<String>(
                                  controller: _model
                                          .expCategoryDropdownValueController ??=
                                      FormFieldController<String>(null),
                                  // Saved VALUES stay the English strings already in the
                                  // database; only the labels follow the app language.
                                  // Localising `options` itself would write translated text
                                  // into the column (Oct 2026, when the ARBs were filled).
                                  options: const ['Fuel', 'Vehicle Maintenance', 'Office', 'Material', 'Salary', 'Other'],
                                  optionLabels: [
                                    AppLocalizations.of(context).fuel,
                                    AppLocalizations.of(context).vehicleMaintenance,
                                    AppLocalizations.of(context).office,
                                    AppLocalizations.of(context).material,
                                    AppLocalizations.of(context).salary,
                                    AppLocalizations.of(context).other
                                  ],
                                  onChanged: (val) async {
                                    safeSetState(() =>
                                        _model.expCategoryDropdownValue = val);
                                    _model.expCategory =
                                        _model.expCategoryDropdownValue;
                                    safeSetState(() {});
                                  },
                                  textStyle: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .override(
                                        font: NgFonts.geist(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontStyle,
                                        ),
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                  hintText: AppLocalizations.of(context).selectCategory,
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
                                      NgPalette.of(context).w08,
                                  borderWidth: 1.0,
                                  borderRadius: 8.0,
                                  margin: const EdgeInsetsDirectional.fromSTEB(
                                      12.0, 0.0, 12.0, 0.0),
                                  hidesUnderline: true,
                                  isOverButton: false,
                                  isSearchable: false,
                                  isMultiSelect: false,
                                  labelText:
                                      AppLocalizations.of(context).category,
                                  labelTextStyle: const TextStyle(),
                                ),
                                // Was a free-text "yyyy-MM-dd" box written straight into
                                // the `date` column: a blank or mistyped date made
                                // Postgres refuse the insert, with nothing shown. Now a
                                // picker, defaulting to today.
                                NgCard(
                                  onTap: () async {
                                    final p = await showDatePicker(
                                      context: context,
                                      initialDate: _model.expDate,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now()
                                          .add(const Duration(days: 365)),
                                    );
                                    if (p != null) {
                                      safeSetState(() => _model.expDate = p);
                                    }
                                  },
                                  child: Row(children: [
                                    Icon(Icons.calendar_month_outlined,
                                        size: 20,
                                        color: NgPalette.of(context).acc),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                          AppLocalizations.of(context).date,
                                          style: NgFonts.geist(
                                              fontSize: 14,
                                              color: NgPalette.of(context)
                                                  .mute)),
                                    ),
                                    Text(
                                        DateFormat('d MMM yyyy')
                                            .format(_model.expDate),
                                        style: NgFonts.geist(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                NgPalette.of(context).text)),
                                  ]),
                                ),
                                // Was a free-text "Linked Order ID" — typing UUIDs by hand
                                // invited typos, and an empty string crashed the uuid cast on
                                // insert. Now an optional dropdown of this org's recent orders.
                                DropdownButtonFormField<String>(
                                  value: _model.linkedOrderId,
                                  isExpanded: true,
                                  dropdownColor:
                                      NgPalette.of(context).s1,
                                  style: NgFonts.geist(
                                      color: NgPalette.of(context).text,
                                      fontSize: 13.5),
                                  decoration: InputDecoration(
                                    labelText: 'Linked Order (optional)',
                                    labelStyle: NgFonts.geist(
                                        color: NgPalette.of(context).mute,
                                        fontSize: 12.5),
                                    filled: true,
                                    fillColor:
                                        NgPalette.of(context).s1,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                          color: FlutterFlowTheme.of(context)
                                              .secondaryText
                                              .withOpacity(0.2)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                          color: FlutterFlowTheme.of(context)
                                              .secondaryText
                                              .withOpacity(0.2)),
                                    ),
                                  ),
                                  hint: Text('No linked order',
                                      style: NgFonts.geist(
                                          color: NgPalette.of(context).mute,
                                          fontSize: 13)),
                                  items: [
                                    const DropdownMenuItem<String>(
                                        value: '', child: Text('No linked order')),
                                    for (final o in _model.recentOrders)
                                      DropdownMenuItem(
                                        value: o.id,
                                        child: Text(
                                      '${o.customer} · ${o.fromCity ?? ''} to ${o.toCity ?? ''}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (v) => safeSetState(
                                      () => _model.linkedOrderId = (v ?? '').isEmpty ? null : v),
                                ),
                                TextFormField(
                                  controller: _model.expDescFieldTextController,
                                  focusNode: _model.expDescFieldFocusNode,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText:
                                        AppLocalizations.of(context).description,
                                    hintText:
                                        AppLocalizations.of(context).briefDescription,
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
                                      .expDescFieldTextControllerValidator
                                      .asValidator(context),
                                ),
                                // Cash book needs to know which expenses
                                // left the cash box. Behind a flag until
                                // the column exists — see app_config.
                                if (kExpensePaymentModeLive)
                                  Wrap(spacing: 8, runSpacing: 8, children: [
                                    for (final m in const [
                                      ('cash', 'Cash'),
                                      ('upi', 'UPI'),
                                      ('bank', 'Bank'),
                                      ('card', 'Card'),
                                    ])
                                      NgChip(
                                        label: m.$2,
                                        selected: _model.expPaymentMode == m.$1,
                                        onTap: () => safeSetState(
                                            () => _model.expPaymentMode = m.$1),
                                      ),
                                  ]),
                              ].divide(const SizedBox(height: 14.0)),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 16.0, 0.0, 16.0),
                          child: FFButtonWidget(
                            onPressed: () async {
                              final amount = double.tryParse(_model
                                  .expAmountFieldTextController!.text
                                  .trim());
                              if (amount == null || amount <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Enter the amount spent.')));
                                return;
                              }
                              // Both date columns get the picked day:
                              // `date` is what this form always wrote,
                              // and expense_date is what Expenses, the
                              // Dashboard and Accounts read — it used to
                              // keep its default (today), so a backdated
                              // expense showed up on today.
                              final day = DateFormat('yyyy-MM-dd')
                                  .format(_model.expDate);
                              try {
                              _model.savedExpense =
                                  await ExpensesTable().insert({
                                // Phase 1 multi-tenancy pass — see
                                // supabase/phase1_add_org_id.sql.
                                ...OrgScope.stamp(),
                                'amount': amount,
                                'category': _model.expCategory,
                                'date': day,
                                'expense_date': day,
                                // Null (not '') when unlinked — an empty
                                // string used to crash the uuid cast.
                                'order_id': _model.linkedOrderId,
                                'description':
                                    _model.expDescFieldTextController.text,
                                if (kExpensePaymentModeLive &&
                                    _model.expPaymentMode != null)
                                  'payment_mode': _model.expPaymentMode,
                              });
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(extractDbErrorMessage(e,
                                          fallback:
                                              'Could not save the expense. Please try again.')),
                                    ),
                                  );
                                }
                                return;
                              }
                              if (!context.mounted) return;
                              context.pop();

                              safeSetState(() {});
                            },
                            text: AppLocalizations.of(context).saveExpense,
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
                              color: NgPalette.of(context).acc,
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
