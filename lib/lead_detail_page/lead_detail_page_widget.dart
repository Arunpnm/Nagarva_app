import 'dart:math';

import '/app_session.dart';
import '/config/app_config.dart';
import '/backend/gst_state_codes.dart';
import '/backend/lead_status.dart';
import '/components/detail_row.dart';
import '/components/lead_status_strip.dart';
import '/backend/reminders_service.dart';
import '/backend/signature_service.dart';
import '/backend/soft_delete.dart';
import '/components/delete_action.dart';
import '/components/reminders_section.dart';
import '/backend/tracking_service.dart';
import '/components/share_link_sheet.dart';
import '/components/survey_response_section.dart';
import '/backend/pricing_defaults.dart';
import '/components/pdf_branding.dart';
import '/components/survey_pdf.dart';
import '/components/quote_pdf.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';
import 'lead_detail_page_model.dart';
export 'lead_detail_page_model.dart';

/// 24 random bytes, hex-encoded — same scheme
/// supabase/20260725_survey_quote_flow.sql documents for the DB-generated
/// survey token default. Generated client-side for quotations because,
/// found live-testing this flow: quotations.token's DB default
/// (`encode(extensions.gen_random_bytes(24), 'hex')`, added by that same
/// migration) isn't coming back populated on insert — the exact same
/// symptom that made quotations.id need a client-generated uuid (see
/// _createQuote below). surveys.token, from the same migration, works
/// fine, so this is isolated to the pre-existing quotations table, not a
/// pgcrypto/extension problem. Not fully root-caused (would need DB
/// introspection this session doesn't have access to) — this sidesteps
/// it the same safe way as the id fix, rather than leaving the flow
/// broken pending a DB investigation.
String _generateHexToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

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

class _LeadDetailPageWidgetState extends State<LeadDetailPageWidget>
    with RefreshOnPopMixin<LeadDetailPageWidget> {
  late LeadDetailPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  bool _converting = false;

  // Refresh-after-write fix (parity brief Part 1): re-run when a pushed
  // route (Request Survey / Create Quote share-link dialogs, or Edit Lead)
  // is popped back to this page, so the Survey & Quote section reflects
  // newly-created rows without needing a full back-and-forth to LeadsPage.
  @override
  void onPageRefresh() {
    _loadLinked();
    // Item 10.7: reminders added/completed in a pushed route or sheet must
    // show immediately too.
    _remindersKey.currentState?.reload();
  }

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

  // ---- Item 5: lead status pipeline ------------------------------------
  // Seeded from the nav param so the strip renders instantly, then
  // refreshed from the DB in _loadLinked (the param is a snapshot from
  // whenever LeadsPage last loaded and can be stale).
  String? _status;
  bool _savingStatus = false;

  // ---- Item 3: signature on the quote ----------------------------------
  SignatureRequest? _quoteSignature;
  bool _sendingQuoteSignature = false;

  // ---- Part 8 addendum item 2: Survey/Quote PDF export ------------------
  bool _downloadingSurveyPdf = false;
  bool _downloadingQuotePdf = false;

  // ---- Item 10: reminders ----------------------------------------------
  final _remindersKey = GlobalKey<RemindersSectionState>();
  bool _deleting = false;

  String get _canonicalStatus => canonicalLeadStatus(_status);

  /// Writes [target] to the lead, never downgrading (item 5.2: "Never
  /// auto-downgrade"). Pass [force] for an explicit manual chip tap, which
  /// is allowed to move the lead backwards or to `lost`.
  Future<void> _setLeadStatus(String target, {bool force = false}) async {
    if (widget.leadId == null) return;
    final next =
        force ? canonicalLeadStatus(target) : advanceLeadStatus(_status, target);
    if (next == _canonicalStatus) return;
    final previous = _status;
    setState(() {
      _status = next;
      _savingStatus = true;
    });
    try {
      await LeadsTable().update(
        data: {'status': next},
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.leadId!),
      );
    } catch (e) {
      // Roll the optimistic update back so the strip can't show a stage
      // the database never accepted.
      if (mounted) {
        setState(() => _status = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update status: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingStatus = false);
    }
  }

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
    final prefix = (AppSession.instance.currentOrgSlug?.toUpperCase() ?? 'NGV');
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

  /// The one place an order is created from a lead.
  ///
  /// Live-test fix brief #2, item 2: there used to be two near-identical
  /// copies of this insert — `_convertToOrder` (plain "Convert to Order"
  /// button) and `_convertQuoteToOrder` (the Survey & Quote section's
  /// button). Only the second one was ever taught about quotes, and even
  /// it only copied the *total*: it never set `quotation_id`, so
  /// `QuotationBreakdownSection` on Order Details (which resolves the
  /// order's linked quotation to render item lines, charges and GST)
  /// always found null and rendered nothing. That is the reported
  /// "detailed quote data not carried into the order".
  ///
  /// Both buttons now funnel through here, so a future change can't teach
  /// one path about quotes and silently miss the other.
  ///
  /// No schema change was needed: `orders` already has `quotation_id`,
  /// `from_address`, `to_address`, `from_floor`, `to_floor`, and the item
  /// lines / charge lines / GST split live on the linked `quotations` row
  /// (jsonb `items` + `charges`, plus `gst_pct`/`gst_amount`) rather than
  /// being duplicated onto the order.
  Future<void> _createOrderFromLead({
    required QuotationsRow? quote,
    required String successMessage,
    required String errorPrefix,
  }) async {
    if (widget.leadId == null) return;
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
        // Link back to the quote so Order Details can render its item
        // lines, and so the invoice can later be generated from the same
        // lines rather than a bare total.
        if (quote != null) 'quotation_id': quote.id,
        'customer': quote?.customer ?? widget.leadCustomer ?? '',
        'phone': quote?.phone ?? widget.leadPhone,
        'from_city': widget.leadFromCity,
        'to_city': widget.leadToCity,
        // Survey/quote captures the full street address and floor; a lead
        // only ever has the city. Prefer the richer values when present.
        if (quote?.fromAddress != null) 'from_address': quote!.fromAddress,
        if (quote?.toAddress != null) 'to_address': quote!.toAddress,
        if (quote?.fromFloor != null) 'from_floor': quote!.fromFloor,
        if (quote?.toFloor != null) 'to_floor': quote!.toFloor,
        'move_date': supaSerialize<DateTime>(moveDate),
        'amount': quote?.total ?? 0.0,
        'service': widget.leadService,
        'branch': widget.leadBranch,
        'notes': widget.leadNotes,
        'status': 'booked',
        'payment_status': 'pending',
        'tracking_status': 'Booked',
        'advance_paid': 0.0,
      });

      // Item 2: freeze the quote figures onto the order.
      if (quote != null) {
        await _writeQuoteSnapshot(newOrderId, quote);
      }

      // Item 6: seed the customer-facing tracking timeline at its first
      // stage, so a freshly-converted order already has a "Confirmed"
      // entry with a real timestamp rather than an empty timeline.
      await TrackingService.logStatus(
        orderId: newOrderId,
        status: 'booked',
        note: 'Order confirmed',
      );

      // LEAK_AUDIT.md write-gap fix: matched only on id before.
      await LeadsTable().update(
        data: {'status': kLeadStatusConfirmed},
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.leadId!),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
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
          'orderAdvancePaid':
              serializeParam(order.advancePaid?.toString(), ParamType.String),
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
        SnackBar(content: Text('$errorPrefix: $e')),
      );
    }
  }

  /// Item 2: freezes the quote's figures onto the order at conversion.
  ///
  /// Written as a SEPARATE update rather than folded into the order
  /// insert, deliberately: the snapshot columns arrive in
  /// supabase/20260729_order_quote_snapshot.sql, and if that hasn't been
  /// run yet an insert naming unknown columns would 400 and take the
  /// whole conversion with it. Isolated and swallowed, a missing column
  /// costs the snapshot only — the order, the lead status flip and the
  /// tracking entry all still land. Snapshots start populating by
  /// themselves once the migration runs, with no code change.
  ///
  /// `orders.quotation_id` remains the live link; this is the historic
  /// record of what the order was confirmed on, for when a quote is later
  /// revised (operational flow 1.2) or signed (item 3).
  Future<void> _writeQuoteSnapshot(String orderId, QuotationsRow quote) async {
    try {
      final charges = (quote.charges is Map)
          ? Map<String, dynamic>.from(quote.charges as Map)
          : <String, dynamic>{};

      // Resolve the GST mode NOW. The quote stores '_gstType' = 'auto'
      // when the surveyor let it derive from the from/to cities — but
      // that derivation re-runs against whatever the addresses say
      // later. Freezing 'auto' would re-introduce exactly the drift this
      // snapshot exists to prevent, so resolve it to inter/intra here.
      final rawMode = charges['_gstType'];
      final resolvedMode = (rawMode == 'inter' || rawMode == 'intra')
          ? rawMode as String
          : (isInterState(
                  quote.fromAddress ?? widget.leadFromCity,
                  quote.toAddress ?? widget.leadToCity)
              ? 'inter'
              : 'intra');

      num? asNum(dynamic v) => v is num ? v : num.tryParse('$v');

      await OrdersTable().update(
        data: {
          'quote_items': quote.items,
          'quote_charges': quote.charges,
          'quote_subtotal': quote.subtotal,
          'quote_gst_pct': quote.gstPct,
          'quote_gst_amount': quote.gstAmount,
          'quote_total': quote.total,
          'quote_gst_mode': resolvedMode,
          'quote_packing_type': charges['_suggestedPackage'],
          'quote_total_cft': asNum(charges['_totalCft']),
          // Versioning isn't built yet (no quotations.version column), so
          // this is 1 — which is correct, not a placeholder: the first
          // quote IS v1.
          'quote_version': quote.version ?? 1,
          'quote_snapshot_at': DateTime.now().toUtc().toIso8601String(),
        },
        matchingRows: (q) => OrgScope.write(q).eq('id', orderId),
      );
    } catch (_) {
      // See doc comment — never fail the conversion over the snapshot.
    }
  }

  /// Opens the detailed quote builder seeded from this survey's
  /// submitted selections, so the vendor doesn't re-key what the customer
  /// already entered on the public page.
  void _openQuoteBuilder(SurveysRow survey) {
    context.pushNamed(
      SurveyQuotePageWidget.routeName,
      queryParameters: {
        'surveyId': serializeParam(survey.id, ParamType.String),
        'leadId': serializeParam(widget.leadId, ParamType.String),
        'leadCustomer': serializeParam(
            survey.customerName ?? widget.leadCustomer, ParamType.String),
        'leadPhone': serializeParam(
            survey.customerPhone ?? widget.leadPhone, ParamType.String),
        'leadFromCity': serializeParam(
            survey.fromAddress ?? widget.leadFromCity, ParamType.String),
        'leadToCity': serializeParam(
            survey.toAddress ?? widget.leadToCity, ParamType.String),
      }.withoutNulls,
    );
  }

  Future<void> _convertToOrder() async {
    if (widget.leadId == null) return;
    setState(() => _converting = true);
    try {
      // Even the plain "Convert to Order" button now picks up a quote if
      // the lead has one. Re-read rather than trusting the cached
      // `_quotation`, so a quote built moments ago in another route is
      // still caught if the refresh hasn't landed yet.
      var quote = _quotation;
      try {
        final rows = await QuotationsTable().queryRows(
          queryFn: (q) => OrgScope
              .read(q)
              .eq('lead_id', widget.leadId!)
              .order('created_at', ascending: false),
        );
        quote = _pickBestQuote(rows) ?? quote;
      } catch (_) {
        // Fall back to whatever was already loaded; a lookup failure
        // shouldn't block converting the lead.
      }
      await _createOrderFromLead(
        quote: quote,
        successMessage: quote == null
            ? 'Lead converted to order'
            : 'Lead converted to order (quote attached)',
        errorPrefix: 'Could not convert lead',
      );
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => LeadDetailPageModel());
    _status = widget.leadStatus;
    _loadLinked();

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  Future<void> _loadLinked() async {
    if (widget.leadId == null) {
      setState(() => _loadingLinked = false);
      return;
    }
    try {
      // Live-test fix brief #2 item 2: both of these used to take
      // `rows.first` off an UNORDERED query, so with more than one survey
      // or quote on a lead the page showed (and Convert to Order used) an
      // arbitrary row — in practice often the older, simpler one. That is
      // the main reason a freshly-built detailed quote appeared to be
      // "lost" on conversion. Now explicitly newest-first.
      final surveys = await SurveysTable().queryRows(
        queryFn: (q) => OrgScope
            .read(q)
            .eq('lead_id', widget.leadId!)
            .order('created_at', ascending: false),
      );
      final quotations = await QuotationsTable().queryRows(
        queryFn: (q) => OrgScope
            .read(q)
            .eq('lead_id', widget.leadId!)
            .order('created_at', ascending: false),
      );
      // The nav param is a snapshot from whenever LeadsPage last loaded —
      // re-read so the progress strip reflects reality (e.g. the customer
      // submitted the survey since this page was opened).
      final leads = await LeadsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', widget.leadId!),
      );

      if (!mounted) return;
      setState(() {
        _survey = surveys.isNotEmpty ? surveys.first : null;
        _quotation = _pickBestQuote(quotations);
        if (leads.isNotEmpty) _status = leads.first.status;
        _loadingLinked = false;
      });

      // Item 3: refresh-after-write for the signature chip. The customer
      // signs on their own phone, so this reconcile-on-load is the only
      // way the chip ever flips from Awaiting to Signed.
      final quote = _quotation;
      if (quote != null) {
        try {
          final sig = await SignatureService.find(
            documentType: 'quote',
            documentId: quote.id,
          );
          if (mounted) setState(() => _quoteSignature = sig);
        } catch (_) {
          // Supplemental — never blank the page over this.
        }
      }

      // Item 5.2 auto-transitions, reconciled on every load rather than
      // only at the moment of the action: a customer submitting the survey
      // happens on their phone, so there is no in-app event to hook. This
      // catches up whenever the page is opened or refreshed. advanceOnly
      // semantics mean a lead already further along is never pulled back.
      await _reconcileStatusFromProgress();
    } catch (_) {
      if (mounted) setState(() => _loadingLinked = false);
    }
  }

  /// Derives the stage implied by the survey/quote rows and advances the
  /// lead to it if it is further along than where the lead currently sits.
  Future<void> _reconcileStatusFromProgress() async {
    final survey = _survey;
    final quote = _quotation;
    String? implied;
    if (survey != null) {
      implied = kLeadStatusFollowUp;
      if (survey.submittedAt != null) implied = kLeadStatusSurveyDone;
    }
    if (quote != null) implied = kLeadStatusQuoted;
    if (implied == null) return;
    if (advanceLeadStatus(_status, implied) == _canonicalStatus) return;
    await _setLeadStatus(implied);
  }

  /// "Detailed quote takes precedence over simple quote if both exist"
  /// (fix brief #2, item 2). [rows] must already be newest-first.
  ///
  /// A detailed quote (SurveyQuotePageWidget) writes a non-empty `items`
  /// list; the simple one-total quote created from this page's own "Create
  /// Quote" dialog writes `items: []`. So: newest quote that actually has
  /// line items, else just the newest quote of any kind.
  static QuotationsRow? _pickBestQuote(List<QuotationsRow> rows) {
    if (rows.isEmpty) return null;
    for (final r in rows) {
      if (r.items is List && (r.items as List).isNotEmpty) return r;
    }
    return rows.first;
  }

  // Was '${Uri.base.origin}$path?token=$token' — threw "Bad state: Origin is
  // only applicable schemes http and https: file:///" on a real APK, where
  // Uri.base is file:/// rather than the page URL it is on web. See
  // kPublicBaseUrl's doc comment in lib/config/app_config.dart.
  String _shareLink(String path, String token) => buildTokenLink(path, token);

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
      // Item 5.2: sending a survey moves the lead to at least follow_up.
      await _setLeadStatus(kLeadStatusFollowUp);
      // Item 10.4: chase the survey if the customer doesn't fill it in.
      await RemindersService.autoCreate(
        entityType: kEntityLead,
        entityId: widget.leadId!,
        title: 'Survey follow-up: ${widget.leadCustomer ?? 'customer'}',
        days: kDefaultSurveyFollowUpDays,
      );
      _remindersKey.currentState?.reload();
      if (!mounted) return;
      _showLinkDialog('Survey link — share with the customer',
          _shareLink('/survey', row.token));
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
      final gstAmount = (result.subtotal * result.gstPct / 100).roundToDouble();
      final row = await QuotationsTable().insert({
        // quotations.id has no DB-generated default (unlike surveys.id,
        // which does) — found live-testing this flow: the insert failed
        // with Postgres 23502 "null value in column id" every time.
        // quotation_page_widget.dart's ad-hoc quote form has the exact
        // same gap (never live-tested either) — flagged in
        // NAGARVA_STATUS.md, not fixed here since it's a separate feature.
        'id': const Uuid().v4(),
        // token's DB default doesn't come back populated either — see
        // _generateHexToken's doc comment above.
        'token': _generateHexToken(),
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
      // Item 5.2: a quote existing means the lead is at least 'quoted'.
      await _setLeadStatus(kLeadStatusQuoted);
      // Item 10.4: "a quote sitting without chase is dead revenue".
      await RemindersService.autoCreate(
        entityType: kEntityLead,
        entityId: widget.leadId!,
        title: 'Quote follow-up: ${widget.leadCustomer ?? 'customer'}',
        days: kDefaultQuoteFollowUpDays,
      );
      _remindersKey.currentState?.reload();
      if (!mounted) return;
      _showLinkDialog('Quote link — share with the customer',
          _shareLink('/quote', row.token!));
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
  /// Item 5.3: `lost` requires a confirm dialog + optional reason.
  Future<void> _confirmMarkLost() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mark lead as lost?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The lead stays in the list under "Lost" and can be reopened '
              'later.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g. went with a cheaper vendor',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
                foregroundColor: leadStatusColor(kLeadStatusLost)),
            child: const Text('Mark lost'),
          ),
        ],
      ),
    );
    final reason = reasonController.text.trim();
    reasonController.dispose();
    if (confirmed != true) return;

    await _setLeadStatus(kLeadStatusLost, force: true);

    // Append the reason to the lead's notes rather than adding a column —
    // `leads` has no lost_reason field and inventing one would mean a
    // migration for a free-text note. Only written when the status change
    // itself succeeded.
    if (reason.isEmpty || !mounted) return;
    if (_canonicalStatus != kLeadStatusLost) return;
    try {
      final stamp = DateFormat('dd MMM yyyy').format(DateTime.now());
      final existing = (widget.leadNotes ?? '').trim();
      final appended = existing.isEmpty
          ? 'Lost ($stamp): $reason'
          : '$existing\n\nLost ($stamp): $reason';
      await LeadsTable().update(
        data: {'notes': appended},
        matchingRows: (q) => OrgScope.write(q).eq('id', widget.leadId!),
      );
    } catch (_) {
      // The status change is the important part and already landed;
      // failing to record the note shouldn't surface as an error.
    }
  }

  Future<void> _convertQuoteToOrder() async {
    if (widget.leadId == null || _quotation == null) return;
    setState(() => _convertingQuote = true);
    try {
      await _createOrderFromLead(
        quote: _quotation,
        successMessage: 'Quote converted to order',
        errorPrefix: 'Could not convert quote',
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
          Row(
            children: [
              Expanded(
                child: Text('Survey & Quote',
                    style: GoogleFonts.interTight(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: theme.primaryText)),
              ),
              // Part 8 addendum item 2: two separate documents, not one
              // combined (Rev B, Q2) - the survey PDF exists before pricing
              // does, so the quote button stays disabled until a quote
              // does. Downloads survey_pdf.dart/quote_pdf.dart output via
              // Printing.sharePdf, same share/download path invoice_pdf.dart
              // already uses.
              IconButton(
                tooltip: 'Download Survey PDF',
                iconSize: 19,
                visualDensity: VisualDensity.compact,
                icon: _downloadingSurveyPdf
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.description_outlined),
                onPressed: (survey == null ||
                        survey.status == 'pending' ||
                        _downloadingSurveyPdf)
                    ? null
                    : _downloadSurveyPdf,
              ),
              IconButton(
                tooltip: 'Download Quote PDF',
                iconSize: 19,
                visualDensity: VisualDensity.compact,
                icon: _downloadingQuotePdf
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf_outlined),
                onPressed: (quotation == null || _downloadingQuotePdf)
                    ? null
                    : _downloadQuotePdf,
              ),
            ],
          ),
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
              onPressed: () => _showLinkDialog(
                  'Survey link', _shareLink('/survey', survey.token)),
              icon: const Icon(Icons.hourglass_top, size: 18),
              label: const Text('Survey sent — awaiting customer response'),
            )
          else
            // Was a bare "Survey response received" line — the items the
            // customer had gone to the trouble of listing were invisible
            // in the app, so the whole survey link delivered nothing to
            // the vendor. Now the full submission, grouped by category,
            // with the total CFT and the package it implies.
            SurveyResponseSection(
              survey: survey,
              onBuildQuote: () => _openQuoteBuilder(survey),
            ),
          const SizedBox(height: 10),
          // Step 2: quote (needs a survey submitted first, or can be
          // skipped straight from the lead — vendor's call).
          if (quotation == null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _creatingQuote ? null : _createQuote,
                  icon: const Icon(Icons.request_quote_outlined, size: 18),
                  label: Text(_creatingQuote ? 'Creating…' : 'Create Quote'),
                ),
                // Parity brief Part 3: the fuller itemized CFT survey +
                // charges/GST builder, as an alternative to the quick
                // subtotal-only dialog above.
                OutlinedButton.icon(
                  onPressed: () => context.pushNamed(
                    SurveyQuotePageWidget.routeName,
                    queryParameters: {
                      'leadId': serializeParam(widget.leadId, ParamType.String),
                      'leadCustomer':
                          serializeParam(widget.leadCustomer, ParamType.String),
                      'leadPhone':
                          serializeParam(widget.leadPhone, ParamType.String),
                      'leadFromCity':
                          serializeParam(widget.leadFromCity, ParamType.String),
                      'leadToCity':
                          serializeParam(widget.leadToCity, ParamType.String),
                    },
                  ),
                  icon: const Icon(Icons.list_alt, size: 18),
                  label: const Text('Build Detailed Quote'),
                ),
              ],
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
                  onPressed: _convertingQuote ? null : _convertQuoteToOrder,
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
          // Item 3: e-signature on the quote, alongside the plain view
          // link above. Separate action because accepting a quote and
          // signing it are different things — the customer can read the
          // quote without committing.
          const SizedBox(height: 8),
          if (_quoteSignature?.isSigned ?? false)
            Row(
              children: [
                Icon(Icons.verified, size: 17, color: theme.tertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Signed by ${_quoteSignature!.customerName ?? 'customer'}'
                    '${_quoteSignature!.signedAt == null ? '' : ' on ${DateFormat('d MMM yyyy').format(_quoteSignature!.signedAt!.toLocal())}'}',
                    style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: theme.primaryText),
                  ),
                ),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: _sendingQuoteSignature
                  ? null
                  : () => _sendQuoteForSignature(quotation!),
              icon: const Icon(Icons.draw, size: 18),
              label: Text(_sendingQuoteSignature
                  ? 'Preparing…'
                  : _quoteSignature == null
                      ? 'Send for Signature'
                      : 'Awaiting signature — resend link'),
            ),
        ],
      ),
    );
  }

  /// Item 3: creates (or reuses) the quote's signature request and opens
  /// the WhatsApp-first share sheet.
  Future<void> _sendQuoteForSignature(QuotationsRow quotation) async {
    setState(() => _sendingQuoteSignature = true);
    try {
      final sig = await SignatureService.getOrCreate(
        documentType: 'quote',
        documentId: quotation.id,
        customerName: quotation.customer ?? widget.leadCustomer,
      );
      if (!mounted) return;
      setState(() => _quoteSignature = sig);
      final org = AppSession.instance.currentOrgName ?? 'Nagarva';
      await ShareLinkSheet.show(
        context,
        title: 'Send quote for signature',
        subtitle: 'The customer reviews the quotation and signs on their '
            'phone. No login needed.',
        link: sig.link,
        phone: widget.leadPhone,
        message: 'Hello${widget.leadCustomer == null ? '' : ' ${widget.leadCustomer}'}, '
            'please review and accept your quotation from $org:',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create signature link: $e')),
      );
    } finally {
      if (mounted) setState(() => _sendingQuoteSignature = false);
    }
  }

  /// Loads the vendor's business profile + logo the same way
  /// order_detail_page_widget.dart does for the invoice, so the survey and
  /// quote PDFs carry the same branding rather than a second, possibly
  /// drifting copy of this lookup.
  Future<(Map<String, dynamic>, Uint8List?)> _loadProfileAndLogo() async {
    Map<String, dynamic> profile = const {};
    try {
      final rows = await SettingsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('key', 'business_profile'),
      );
      if (rows.isNotEmpty && (rows.first.value ?? '').isNotEmpty) {
        final decoded = jsonDecode(rows.first.value!);
        if (decoded is Map) profile = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    final logoBytes =
        await PdfBranding.fetchBytes(AppSession.instance.currentOrgLogoUrl);
    return (profile, logoBytes);
  }

  /// A short human-readable reference for PDF filenames/headers. Leads
  /// have no dedicated short code (just a uuid `id`), so this truncates it
  /// the same way orders' own text ids read as a short reference.
  String get _leadRef =>
      (widget.leadId ?? '').length >= 8
          ? widget.leadId!.substring(0, 8).toUpperCase()
          : (widget.leadId ?? 'LEAD');

  Future<void> _downloadSurveyPdf() async {
    final survey = _survey;
    if (survey == null || _downloadingSurveyPdf) return;
    setState(() => _downloadingSurveyPdf = true);
    try {
      final (profile, logoBytes) = await _loadProfileAndLogo();
      final config = await PricingConfig.loadForCurrentOrg();
      final lines = parseSurveyRooms(survey.rooms);
      final bytes = await SurveyPdf.generate(
        leadRef: _leadRef,
        customerName: survey.customerName ?? widget.leadCustomer ?? 'Customer',
        customerPhone: survey.customerPhone ?? widget.leadPhone,
        moveDate: survey.moveDate,
        fromAddress: survey.fromAddress,
        toAddress: survey.toAddress,
        fromCity: widget.leadFromCity,
        toCity: widget.leadToCity,
        lines: lines,
        orgName: AppSession.instance.currentOrgName ?? 'Nagarva',
        profile: profile,
        logoBytes: logoBytes,
        cftRanges: config.cftRanges,
        packages: config.packages,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: SurveyPdf.filename(_leadRef, DateTime.now()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate survey PDF: $e')),
      );
    } finally {
      if (mounted) setState(() => _downloadingSurveyPdf = false);
    }
  }

  Future<void> _downloadQuotePdf() async {
    final quotation = _quotation;
    if (quotation == null || _downloadingQuotePdf) return;
    setState(() => _downloadingQuotePdf = true);
    try {
      final (profile, logoBytes) = await _loadProfileAndLogo();
      final charges = quotation.charges is Map
          ? Map<String, dynamic>.from(quotation.charges as Map)
          : <String, dynamic>{};
      final gstType = charges['_gstType'] as String?;
      final interstate = gstType == 'inter'
          ? true
          : gstType == 'intra'
              ? false
              : isInterState(
                  quotation.fromAddress ?? widget.leadFromCity ?? '',
                  quotation.toAddress ?? widget.leadToCity ?? '',
                );
      // Re-read rather than trusting the cached _quoteSignature, same
      // reasoning as the invoice's signature fetch: a signature captured
      // moments ago on the customer's own phone must show up here without
      // needing the page reopened.
      SignatureRequest? sig = _quoteSignature;
      try {
        sig = await SignatureService.find(
              documentType: 'quote',
              documentId: quotation.id,
            ) ??
            sig;
      } catch (_) {}
      final bytes = await QuotePdf.generate(
        leadRef: _leadRef,
        customerName: quotation.customer ?? widget.leadCustomer ?? 'Customer',
        customerPhone: quotation.phone ?? widget.leadPhone,
        fromAddress: quotation.fromAddress,
        toAddress: quotation.toAddress,
        fromCity: widget.leadFromCity,
        toCity: widget.leadToCity,
        charges: charges,
        subtotal: quotation.subtotal ?? 0,
        gstPct: quotation.gstPct ?? kGstDefaultPct.toDouble(),
        gstAmount: quotation.gstAmount ?? 0,
        total: quotation.total ?? 0,
        interstate: interstate,
        orgName: AppSession.instance.currentOrgName ?? 'Nagarva',
        profile: profile,
        logoBytes: logoBytes,
        customerSignatureBytes:
            (sig?.isSigned ?? false) ? sig!.signatureBytes : null,
        customerSignedByName: (sig?.isSigned ?? false) ? sig!.customerName : null,
        customerSignedAt: (sig?.isSigned ?? false) ? sig!.signedAt : null,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: QuotePdf.filename(_leadRef, DateTime.now()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate quote PDF: $e')),
      );
    } finally {
      if (mounted) setState(() => _downloadingQuotePdf = false);
    }
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
                            // Item 5: was a static `widget.leadStatus!` —
                            // which also crashed outright on any lead
                            // opened without that nav param. Now driven by
                            // live state, canonicalised, and colour-coded
                            // per stage.
                            Container(
                              decoration: BoxDecoration(
                                color: leadStatusColor(_status)
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(16.0),
                              ),
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    12.0, 6.0, 12.0, 6.0),
                                child: Text(
                                  leadStatusLabel(_status),
                                  style: GoogleFonts.inter(
                                    fontSize: 12.0,
                                    fontWeight: FontWeight.w700,
                                    color: leadStatusColor(_status),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Item 4.1/4.3: the Contact and Move Details cards
                    // each hand-rolled their rows as
                    // Row(spaceBetween, [Text(label), Text(value)]) with
                    // two unconstrained Texts, so a long value (a full
                    // address, a long service name) overflowed instead of
                    // wrapping, and vertical padding drifted between
                    // cards. Every row now goes through the shared
                    // DetailRow so labels and values sit on one grid.
                    // Email uses hideWhenEmpty (item 4.3) rather than
                    // showing an orphan empty row.
                    DetailCard(
                      title: 'Contact',
                      children: [
                        DetailRow(label: 'Phone', value: widget.leadPhone),
                        DetailRow(
                          label: 'Email',
                          value: widget.leadEmail,
                          hideWhenEmpty: true,
                        ),
                        DetailRow(label: 'Source', value: widget.leadSource),
                        DetailRow(label: 'Branch', value: widget.leadBranch),
                      ],
                    ),
                    DetailCard(
                      title: 'Move Details',
                      children: [
                        DetailRow(label: 'From', value: widget.leadFromCity),
                        DetailRow(label: 'To', value: widget.leadToCity),
                        DetailRow(
                          label: 'Approx. Date',
                          value: widget.leadApproxDate,
                        ),
                        DetailRow(label: 'Service', value: widget.leadService),
                      ],
                    ),
                    // Item 4.3: this card rendered a "Notes" section
                    // header wrapping a row whose label was also "Notes"
                    // (the reported "Notes / Notes" duplicate), squeezed
                    // the note text into a right-aligned column where a
                    // paragraph cannot wrap sensibly, and read
                    // `widget.leadNotes!` - crashing outright on any lead
                    // with no notes. Now one DetailCard + DetailNote with
                    // a real empty state.
                    DetailCard(
                      title: 'Notes',
                      children: [
                        DetailNote(text: widget.leadNotes),
                      ],
                    ),
                    // Item 10: REMINDERS, above Survey & Quote as specified.
                    if (widget.leadId != null)
                      RemindersSection(
                        key: _remindersKey,
                        entityType: kEntityLead,
                        entityId: widget.leadId!,
                        customerName: widget.leadCustomer,
                        customerPhone: widget.leadPhone,
                      ),
                    // Item 5.4: pipeline progress strip, APC parity.
                    LeadStatusStrip(
                      status: _status,
                      busy: _savingStatus,
                      onStageTap: (stage) => _setLeadStatus(stage, force: true),
                      onMarkLost: _confirmMarkLost,
                    ),
                    if (!_loadingLinked) _surveyQuoteSection(context),
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          0.0, 14.0, 0.0, 14.0),
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
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          0.0, 14.0, 0.0, 14.0),
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
                    // Item 11: destructive, at the bottom, deliberately
                    // separated from the primary actions above.
                    if (widget.leadId != null)
                      DeleteAction.button(
                        context: context,
                        busy: _deleting,
                        label: 'Delete Lead',
                        onPressed: _deleteLead,
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

  /// Item 11: soft-delete this lead. Blocked once converted — the order
  /// still references it, and "Lost" is the honest state for a lead that
  /// didn't work out.
  Future<void> _deleteLead() async {
    setState(() => _deleting = true);
    try {
      final deleted = await DeleteAction.run(
        context,
        table: 'leads',
        id: widget.leadId!,
        entityLabel: 'lead',
        check: () => SoftDeleteService.canDeleteLead(widget.leadId!),
        onAlternative: (alt) {
          if (alt == 'mark_lost') _confirmMarkLost();
        },
      );
      if (deleted && mounted) {
        // Straight back to the list — staying on a detail page for a row
        // that no longer exists would just show stale data.
        context.pop();
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
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
          if (widget.initialNotes != null &&
              widget.initialNotes!.isNotEmpty) ...[
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
            Navigator.of(context).pop((subtotal: amount, gstPct: gst));
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
