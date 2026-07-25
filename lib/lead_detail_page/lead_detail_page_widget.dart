import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'lead_detail_page_model.dart';
export 'lead_detail_page_model.dart';

/// Read-only view of a single lead with convert-to-order action.
class LeadDetailPageWidget extends StatefulWidget {
  const LeadDetailPageWidget({
    super.key,
    this.leadId,
    this.leadCustomer,
    this.leadPhone,
    this.leadEmail,
    this.leadFromCity,
    this.leadToCity,
    this.leadApproxDate,
    this.leadService,
    this.leadSource,
    this.leadStatus,
    this.leadBranch,
    this.leadNotes,
  });

  final String? leadId;
  final String? leadCustomer;
  final String? leadPhone;
  final String? leadEmail;
  final String? leadFromCity;
  final String? leadToCity;
  final String? leadApproxDate;
  final String? leadService;
  final String? leadSource;
  final String? leadStatus;
  final String? leadBranch;
  final String? leadNotes;

  static String routeName = 'LeadDetailPage';
  static String routePath = '/lead-detail';

  @override
  State<LeadDetailPageWidget> createState() => _LeadDetailPageWidgetState();
}

class _LeadDetailPageWidgetState extends State<LeadDetailPageWidget> {
  late LeadDetailPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  bool _converting = false;

  // ---- Item 8 (CORE V1): Survey -> Quotation -> Order flow ---------------
  // See supabase/20260725_survey_quote_flow.sql for the scope assumption.
  // Deliberately scoped to this one file rather than also modifying
  // quotation_page_widget.dart (a large, separate standalone quote-
  // creation form that still works fine on its own for ad-hoc quotes not
  // tied to a lead) — this is a simpler, self-contained lead-linked path:
  // request a survey, get a quote back with a single total (not a full
  // line-item builder), share it, convert once accepted.
  SurveysRow? _survey;
  QuotationsRow? _quotation;
  bool _loadingLinked = true;
  bool _requestingSurvey = false;
  bool _creatingQuote = false;
  bool _convertingQuote = false;

  /// "Convert to Order" used to just navigate to a blank NewOrderPage,
  /// discarding all the lead's data and never marking the lead as
  /// converted (so it could never show up as a win in PLReportPage's lead
  /// source conversion rate, which checks leads.status == 'confirmed').
  /// Fixed to actually create the order from the lead's fields and flip
  /// the lead's status. Amount isn't known from a lead, so the order is
  /// created with amount 0 / status 'booked' — the office still needs to
  /// fill in the real quote via Edit Order once that flow exists (see
  /// CLAUDE.md's OrderDetailPage/NewOrderPage edit-mode gap).
  /// Generates a human-readable order id like NGV-1007. orders.id is TEXT
  /// (not uuid) and has NOT-NULL / no default, so the insert crashes with
  /// 23502 unless we supply one. Counter lives in the settings table, per-
  /// org, with the same PK convention as _nextInvoiceNo on OrderDetailPage.
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

  Future<void> _convertToOrder() async {
    if (widget.leadId == null) return;
    setState(() => _converting = true);
    try {
      DateTime moveDate;
      try {
        moveDate = DateTime.parse(widget.leadApproxDate ?? '');
      } catch (_) {
        moveDate = DateTime.now();
      }

      final newOrderId = await _nextOrderId();
      final order = await OrdersTable().insert({
        ...OrgScope.stamp(),
        'id': newOrderId,
        'lead_id': widget.leadId,
        'customer': widget.leadCustomer ?? '',
        'phone': widget.leadPhone,
        'from_city': widget.leadFromCity,
        'to_city': widget.leadToCity,
        'move_date': supaSerialize<DateTime>(moveDate),
        'amount': 0.0,
        'service': widget.leadService,
        'branch': widget.leadBranch,
        'notes': widget.leadNotes,
        'status': 'booked',
        'payment_status': 'pending',
        'tracking_status': 'Booked',
        'advance_paid': 0.0,
      });

      // LEAK_AUDIT.md write-gap fix: matched only on id before.
      await LeadsTable().update(
        data: {'status': 'confirmed'},
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.leadId!),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lead converted to order')),
      );
      context.pushNamed(
        OrderDetailPageWidget.routeName,
        queryParameters: {
          'orderId': serializeParam(order.id, ParamType.String),
          'orderCustomer':
              serializeParam(order.customer, ParamType.String),
          'orderPhone': serializeParam(order.phone, ParamType.String),
          'orderFromCity':
              serializeParam(order.fromCity, ParamType.String),
          'orderToCity': serializeParam(order.toCity, ParamType.String),
          'orderMoveDate':
              serializeParam(order.moveDate.toString(), ParamType.String),
          'orderAmount':
              serializeParam(order.amount?.toString(), ParamType.String),
          'orderAdvancePaid': serializeParam(
              order.advancePaid?.toString(), ParamType.String),
          'orderStatus': serializeParam(order.status, ParamType.String),
          'orderPaymentStatus':
              serializeParam(order.paymentStatus, ParamType.String),
          'orderTrackingStatus':
              serializeParam(order.trackingStatus, ParamType.String),
          'orderService': serializeParam(order.service, ParamType.String),
          'orderBranch': serializeParam(order.branch, ParamType.String),
        }.withoutNulls,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not convert lead: $e')),
      );
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => LeadDetailPageModel());
    _loadLinked();

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  Future<void> _loadLinked() async {
    if (widget.leadId == null) {
      setState(() => _loadingLinked = false);
      return;
    }
    try {
      final surveys = await SurveysTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('lead_id', widget.leadId!),
      );
      final quotations = await QuotationsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('lead_id', widget.leadId!),
      );
      setState(() {
        _survey = surveys.isNotEmpty ? surveys.first : null;
        _quotation = quotations.isNotEmpty ? quotations.first : null;
        _loadingLinked = false;
      });
    } catch (_) {
      setState(() => _loadingLinked = false);
    }
  }

  String _shareLink(String path, String token) =>
      '${Uri.base.origin}$path?token=$token';

  void _showLinkDialog(String title, String link) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SelectableText(link),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied')),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestSurvey() async {
    if (widget.leadId == null) return;
    setState(() => _requestingSurvey = true);
    try {
      final row = await SurveysTable().insert({
        ...OrgScope.stamp(),
        'lead_id': widget.leadId,
        'customer_name': widget.leadCustomer,
        'customer_phone': widget.leadPhone,
      });
      setState(() => _survey = row);
      if (!mounted) return;
      _showLinkDialog(
          'Survey link — share with the customer', _shareLink('/survey', row.token));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create survey link: $e')),
      );
    } finally {
      if (mounted) setState(() => _requestingSurvey = false);
    }
  }

  Future<void> _createQuote() async {
    if (widget.leadId == null) return;
    final result = await showDialog<({double subtotal, double gstPct})>(
      context: context,
      builder: (_) => _QuoteAmountDialog(
        initialNotes: _survey?.specialInstructions,
      ),
    );
    if (result == null) return;
    setState(() => _creatingQuote = true);
    try {
      final gstAmount =
          (result.subtotal * result.gstPct / 100).roundToDouble();
      final row = await QuotationsTable().insert({
        ...OrgScope.stamp(),
        'lead_id': widget.leadId,
        'customer': widget.leadCustomer,
        'phone': widget.leadPhone,
        'from_address': _survey?.fromAddress ?? widget.leadFromCity,
        'to_address': _survey?.toAddress ?? widget.leadToCity,
        'items': const [],
        'charges': const [],
        'subtotal': result.subtotal,
        'gst_pct': result.gstPct,
        'gst_amount': gstAmount,
        'total': result.subtotal + gstAmount,
        'status': 'sent',
      });
      setState(() => _quotation = row);
      if (!mounted) return;
      _showLinkDialog(
          'Quote link — share with the customer', _shareLink('/quote', row.token!));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create quote: $e')),
      );
    } finally {
      if (mounted) setState(() => _creatingQuote = false);
    }
  }

  /// Same shape as _convertToOrder above, but seeded from the accepted
  /// quotation's real pricing instead of amount 0 — the whole point of
  /// routing a lead through Survey -> Quote first.
  Future<void> _convertQuoteToOrder() async {
    if (widget.leadId == null || _quotation == null) return;
    setState(() => _convertingQuote = true);
    try {
      DateTime moveDate;
      try {
        moveDate = DateTime.parse(widget.leadApproxDate ?? '');
      } catch (_) {
        moveDate = DateTime.now();
      }
      final newOrderId = await _nextOrderId();
      final order = await OrdersTable().insert({
        ...OrgScope.stamp(),
        'id': newOrderId,
        'lead_id': widget.leadId,
        'customer': _quotation!.customer ?? widget.leadCustomer ?? '',
        'phone': _quotation!.phone ?? widget.leadPhone,
        'from_city': widget.leadFromCity,
        'to_city': widget.leadToCity,
        'move_date': supaSerialize<DateTime>(moveDate),
        'amount': _quotation!.total ?? 0.0,
        'service': widget.leadService,
        'branch': widget.leadBranch,
        'notes': widget.leadNotes,
        'status': 'booked',
        'payment_status': 'pending',
        'tracking_status': 'Booked',
        'advance_paid': 0.0,
      });
      await LeadsTable().update(
        data: {'status': 'confirmed'},
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.leadId!),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quote converted to order')),
      );
      context.pushNamed(
        OrderDetailPageWidget.routeName,
        queryParameters: {
          'orderId': serializeParam(order.id, ParamType.String),
          'orderCustomer': serializeParam(order.customer, ParamType.String),
          'orderPhone': serializeParam(order.phone, ParamType.String),
          'orderFromCity': serializeParam(order.fromCity, ParamType.String),
          'orderToCity': serializeParam(order.toCity, ParamType.String),
          'orderMoveDate':
              serializeParam(order.moveDate.toString(), ParamType.String),
          'orderAmount':
              serializeParam(order.amount?.toString(), ParamType.String),
          'orderStatus': serializeParam(order.status, ParamType.String),
        }.withoutNulls,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not convert quote: $e')),
      );
    } finally {
      if (mounted) setState(() => _convertingQuote = false);
    }
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  Widget _surveyQuoteSection(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final survey = _survey;
    final quotation = _quotation;
    return Container(
      width: double.infinity,
      margin: const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 14.0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Survey & Quote',
              style: GoogleFonts.interTight(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: theme.primaryText)),
          const SizedBox(height: 10),
          // Step 1: survey
          if (survey == null)
            OutlinedButton.icon(
              onPressed: _requestingSurvey ? null : _requestSurvey,
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: Text(_requestingSurvey
                  ? 'Creating link…'
                  : 'Request Survey (send customer a link)'),
            )
          else if (survey.status == 'pending')
            OutlinedButton.icon(
              onPressed: () => _showLinkDialog('Survey link',
                  _shareLink('/survey', survey.token)),
              icon: const Icon(Icons.hourglass_top, size: 18),
              label: const Text('Survey sent — awaiting customer response'),
            )
          else
            Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: theme.success),
                const SizedBox(width: 6),
                const Expanded(child: Text('Survey response received')),
              ],
            ),
          const SizedBox(height: 10),
          // Step 2: quote (needs a survey submitted first, or can be
          // skipped straight from the lead — vendor's call).
          if (quotation == null)
            OutlinedButton.icon(
              onPressed: _creatingQuote ? null : _createQuote,
              icon: const Icon(Icons.request_quote_outlined, size: 18),
              label: Text(
                  _creatingQuote ? 'Creating…' : 'Create Quote'),
            )
          else if (quotation.status == 'accepted')
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, size: 18, color: theme.success),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(
                            'Quote accepted by ${quotation.acceptedByName ?? 'customer'}')),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed:
                      _convertingQuote ? null : _convertQuoteToOrder,
                  icon: const Icon(Icons.assignment_turned_in, size: 18),
                  label: Text(_convertingQuote
                      ? 'Converting…'
                      : 'Convert Quote to Order'),
                ),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: () => _showLinkDialog(
                  'Quote link', _shareLink('/quote', quotation.token!)),
              icon: const Icon(Icons.hourglass_top, size: 18),
              label: const Text('Quote sent — awaiting customer acceptance'),
            ),
        ],
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
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          automaticallyImplyLeading: true,
          title: Text(
            FFLocalizations.of(context).getText(
              'glfe14qd' /* Lead Details */,
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
                    Container(
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
                            Text(
                              widget.leadCustomer!,
                              style: FlutterFlowTheme.of(context)
                                  .titleMedium
                                  .override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .titleMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .titleMedium
                                          .fontStyle,
                                    ),
                                    color: FlutterFlowTheme.of(context)
                                        .primaryText,
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .titleMedium
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .titleMedium
                                        .fontStyle,
                                  ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: FlutterFlowTheme.of(context)
                                    .primaryBackground,
                                borderRadius: BorderRadius.circular(16.0),
                              ),
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    12.0, 6.0, 12.0, 6.0),
                                child: Text(
                                  widget.leadStatus!,
                                  style: FlutterFlowTheme.of(context)
                                      .labelMedium
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .labelMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .labelMedium
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .primary,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .labelMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .labelMedium
                                            .fontStyle,
                                      ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: FlutterFlowTheme.of(context).secondaryBackground,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              FFLocalizations.of(context).getText(
                                'oy47i3en' /* Contact */,
                              ),
                              style: FlutterFlowTheme.of(context)
                                  .labelMedium
                                  .override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .labelMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .labelMedium
                                          .fontStyle,
                                    ),
                                    color: FlutterFlowTheme.of(context).primary,
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontStyle,
                                  ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  FFLocalizations.of(context).getText(
                                    'iskevrrz' /* Phone */,
                                  ),
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontStyle,
                                      ),
                                ),
                                Text(
                                  widget.leadPhone!,
                                  style: FlutterFlowTheme.of(context)
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
                                        color: FlutterFlowTheme.of(context)
                                            .primaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  FFLocalizations.of(context).getText(
                                    '4i6yk1ea' /* Email */,
                                  ),
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontStyle,
                                      ),
                                ),
                                Text(
                                  widget.leadEmail!,
                                  style: FlutterFlowTheme.of(context)
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
                                        color: FlutterFlowTheme.of(context)
                                            .primaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  FFLocalizations.of(context).getText(
                                    '8c0s3oih' /* Source */,
                                  ),
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontStyle,
                                      ),
                                ),
                                Text(
                                  widget.leadSource!,
                                  style: FlutterFlowTheme.of(context)
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
                                        color: FlutterFlowTheme.of(context)
                                            .primaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  FFLocalizations.of(context).getText(
                                    'gusutnn1' /* Branch */,
                                  ),
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontStyle,
                                      ),
                                ),
                                Text(
                                  widget.leadBranch!,
                                  style: FlutterFlowTheme.of(context)
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
                                        color: FlutterFlowTheme.of(context)
                                            .primaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                ),
                              ],
                            ),
                          ].divide(const SizedBox(height: 10.0)),
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: FlutterFlowTheme.of(context).secondaryBackground,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              FFLocalizations.of(context).getText(
                                '7cmbhbkt' /* Move Details */,
                              ),
                              style: FlutterFlowTheme.of(context)
                                  .labelMedium
                                  .override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .labelMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .labelMedium
                                          .fontStyle,
                                    ),
                                    color: FlutterFlowTheme.of(context).primary,
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontStyle,
                                  ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  FFLocalizations.of(context).getText(
                                    'bnry6xmg' /* From */,
                                  ),
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontStyle,
                                      ),
                                ),
                                Text(
                                  widget.leadFromCity!,
                                  style: FlutterFlowTheme.of(context)
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
                                        color: FlutterFlowTheme.of(context)
                                            .primaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  FFLocalizations.of(context).getText(
                                    'b3srrufj' /* To */,
                                  ),
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontStyle,
                                      ),
                                ),
                                Text(
                                  widget.leadToCity!,
                                  style: FlutterFlowTheme.of(context)
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
                                        color: FlutterFlowTheme.of(context)
                                            .primaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  FFLocalizations.of(context).getText(
                                    'qh6mzcvp' /* Approx. Date */,
                                  ),
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontStyle,
                                      ),
                                ),
                                Text(
                                  widget.leadApproxDate!,
                                  style: FlutterFlowTheme.of(context)
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
                                        color: FlutterFlowTheme.of(context)
                                            .primaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  FFLocalizations.of(context).getText(
                                    '5eva5mrh' /* Service */,
                                  ),
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontStyle,
                                      ),
                                ),
                                Text(
                                  widget.leadService!,
                                  style: FlutterFlowTheme.of(context)
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
                                        color: FlutterFlowTheme.of(context)
                                            .primaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                ),
                              ],
                            ),
                          ].divide(const SizedBox(height: 10.0)),
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: FlutterFlowTheme.of(context).secondaryBackground,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              FFLocalizations.of(context).getText(
                                'fvws5owh' /* Notes */,
                              ),
                              style: FlutterFlowTheme.of(context)
                                  .labelMedium
                                  .override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .labelMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .labelMedium
                                          .fontStyle,
                                    ),
                                    color: FlutterFlowTheme.of(context).primary,
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontStyle,
                                  ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  FFLocalizations.of(context).getText(
                                    '4rncj062' /* Notes */,
                                  ),
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontStyle,
                                      ),
                                ),
                                Text(
                                  widget.leadNotes!,
                                  style: FlutterFlowTheme.of(context)
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
                                        color: FlutterFlowTheme.of(context)
                                            .primaryText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                ),
                              ],
                            ),
                          ].divide(const SizedBox(height: 10.0)),
                        ),
                      ),
                    ),
                    if (!_loadingLinked) _surveyQuoteSection(context),
                    Padding(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(0.0, 14.0, 0.0, 14.0),
                      child: FFButtonWidget(
                        onPressed: _converting ? null : _convertToOrder,
                        text: _converting
                            ? 'Converting…'
                            : FFLocalizations.of(context).getText(
                                'se81on2i' /* Convert to Order */,
                              ),
                        icon: const Icon(
                          Icons.assignment_turned_in,
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
                    Padding(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(0.0, 14.0, 0.0, 14.0),
                      child: FFButtonWidget(
                        onPressed: () async {
                          context.pushNamed(
                            NewLeadPageWidget.routeName,
                            queryParameters: {
                              'leadId': serializeParam(
                                  widget.leadId, ParamType.String),
                            }.withoutNulls,
                          );
                        },
                        text: FFLocalizations.of(context).getText(
                          'mqy6axdn' /* Edit Lead */,
                        ),
                        icon: const Icon(
                          Icons.edit,
                          size: 20.0,
                        ),
                        options: FFButtonOptions(
                          width: double.infinity,
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          iconPadding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          iconColor: FlutterFlowTheme.of(context).primary,
                          color: Colors.transparent,
                          textStyle: TextStyle(
                            color: FlutterFlowTheme.of(context).primary,
                          ),
                          borderSide: BorderSide(
                            color: FlutterFlowTheme.of(context).primary,
                            width: 1.0,
                          ),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                    ),
                  ].divide(const SizedBox(height: 12.0)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Minimal quote-amount dialog for the lead-linked quote flow — a single
/// total + GST%, not a line-item builder (that already exists as its own
/// standalone form in quotation_page_widget.dart; this is deliberately
/// simpler since it's meant to be fast to fire off after a survey comes
/// back).
class _QuoteAmountDialog extends StatefulWidget {
  const _QuoteAmountDialog({this.initialNotes});

  final String? initialNotes;

  @override
  State<_QuoteAmountDialog> createState() => _QuoteAmountDialogState();
}

class _QuoteAmountDialogState extends State<_QuoteAmountDialog> {
  final _amountCtrl = TextEditingController();
  final _gstCtrl = TextEditingController(text: '5');

  @override
  void dispose() {
    _amountCtrl.dispose();
    _gstCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Quote'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.initialNotes != null && widget.initialNotes!.isNotEmpty) ...[
            Text('From the survey: ${widget.initialNotes}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Quote amount (₹)'),
            autofocus: true,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _gstCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'GST %'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(_amountCtrl.text.trim());
            if (amount == null || amount <= 0) return;
            final gst = double.tryParse(_gstCtrl.text.trim()) ?? 0;
            Navigator.of(context)
                .pop((subtotal: amount, gstPct: gst));
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
