import 'dart:convert';
import 'dart:typed_data';

import '/backend/gst_state_codes.dart';

import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import '/app_session.dart';
import '/backend/signature_service.dart';
import '/backend/soft_delete.dart';
import '/components/delete_action.dart';
import '/components/detail_row.dart';
import '/backend/tracking_service.dart';
import '/components/invoice_pdf.dart';
import '/components/share_link_sheet.dart';
import '/config/app_config.dart';
import 'order_crew_section.dart';
import 'quotation_breakdown_section.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/components/keyboard_scroll_view.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:google_fonts/google_fonts.dart';
import 'order_detail_page_model.dart';
export 'order_detail_page_model.dart';

/// Read-only view of a single order.
class OrderDetailPageWidget extends StatefulWidget {
  const OrderDetailPageWidget({
    super.key,
    this.orderId,
    this.orderCustomer,
    this.orderPhone,
    this.orderFromCity,
    this.orderToCity,
    this.orderFromAddress,
    this.orderToAddress,
    this.orderFromFloor,
    this.orderToFloor,
    this.orderMoveDate,
    this.orderAmount,
    this.orderAdvancePaid,
    this.orderStatus,
    this.orderPaymentStatus,
    this.orderTrackingStatus,
    this.orderService,
    this.orderBranch,
    this.orderType,
    this.orderNotes,
  });

  final String? orderId;
  final String? orderCustomer;
  final String? orderPhone;
  final String? orderFromCity;
  final String? orderToCity;
  final String? orderFromAddress;
  final String? orderToAddress;
  final String? orderFromFloor;
  final String? orderToFloor;
  final String? orderMoveDate;
  final String? orderAmount;
  final String? orderAdvancePaid;
  final String? orderStatus;
  final String? orderPaymentStatus;
  final String? orderTrackingStatus;
  final String? orderService;
  final String? orderBranch;
  final String? orderType;
  final String? orderNotes;

  static String routeName = 'OrderDetailPage';
  static String routePath = '/order-detail';

  @override
  State<OrderDetailPageWidget> createState() => _OrderDetailPageWidgetState();
}

class _OrderDetailPageWidgetState extends State<OrderDetailPageWidget>
    with RefreshOnPopMixin<OrderDetailPageWidget> {
  late OrderDetailPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  bool _generatingInvoice = false;

  // ---- Item 3: customer signature ---------------------------------------
  SignatureRequest? _signature;
  bool _sendingSignature = false;

  // ---- Item 6: tracking link --------------------------------------------
  bool _sharingTracking = false;

  // ---- Item 11: delete --------------------------------------------------
  bool _deleting = false;

  /// Owner-only, and blocked entirely once payments exist or a GST invoice
  /// has been issued — the guard is `can_delete_order()` server-side, so
  /// the UI is not the only thing enforcing it.
  Future<void> _deleteOrder() async {
    if (widget.orderId == null) return;
    setState(() => _deleting = true);
    try {
      final deleted = await DeleteAction.run(
        context,
        table: 'orders',
        id: widget.orderId!,
        entityLabel: 'order',
        // Mandatory reason for orders, per item 11.4.
        reasonRequired: true,
        check: () => SoftDeleteService.canDeleteOrder(widget.orderId!),
        onAlternative: (alt) {
          if (alt == 'cancel_order') _cancelOrder();
        },
      );
      if (deleted && mounted) context.pop();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  /// The alternative offered when an order can't be deleted: keeps the row
  /// and its financial record, takes it out of active jobs, and lands on
  /// the customer-facing timeline like any other status change.
  Future<void> _cancelOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: const Text(
          'The order and its payment history are kept, but it moves out of '
          'your active jobs. This is the right choice for an order that was '
          'called off.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
                foregroundColor: FlutterFlowTheme.of(context).error),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await TrackingService.setStatus(
        orderId: widget.orderId!,
        status: 'cancelled',
        note: 'Order cancelled',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order cancelled')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not cancel: $e')),
        );
      }
    }
  }

  /// Refresh-after-write: re-read the signature so the chip flips from
  /// "Awaiting" to "Signed" when returning to this page, without a
  /// restart. The customer signs on their own phone, so there is no
  /// in-app event to hook — reconciling on refresh is the only way.
  @override
  void onPageRefresh() {
    _loadSignature();
    // Item 2: re-pull the linked quote so an edited quote's lines,
    // charges and GST show without a restart.
    _breakdownKey.currentState?.reload();
  }

  final _breakdownKey = GlobalKey<QuotationBreakdownSectionState>();

  Future<void> _loadSignature() async {
    if (widget.orderId == null) return;
    try {
      final sig = await SignatureService.find(
        documentType: 'invoice',
        documentId: widget.orderId!,
      );
      if (mounted) setState(() => _signature = sig);
    } catch (_) {
      // Supplemental — a failure here must not blank the page.
    }
  }

  Future<void> _sendForSignature() async {
    if (widget.orderId == null) return;
    setState(() => _sendingSignature = true);
    try {
      final sig = await SignatureService.getOrCreate(
        documentType: 'invoice',
        documentId: widget.orderId!,
        customerName: widget.orderCustomer,
      );
      if (!mounted) return;
      setState(() => _signature = sig);
      final org = AppSession.instance.currentOrgName ?? 'Nagarva';
      await ShareLinkSheet.show(
        context,
        title: sig.isSigned ? 'Already signed' : 'Send for signature',
        subtitle: sig.isSigned
            ? 'Signed by ${sig.customerName ?? 'the customer'}'
                '${sig.signedAt == null ? '' : ' on ${DateFormat('d MMM yyyy').format(sig.signedAt!.toLocal())}'}.'
                ' The link still opens a read-only copy.'
            : 'The customer opens this link, reviews the invoice and signs '
                'on their phone. No login needed.',
        link: sig.link,
        phone: widget.orderPhone,
        message: 'Hello${widget.orderCustomer == null ? '' : ' ${widget.orderCustomer}'}, '
            'please review and accept your invoice from $org:',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create signature link: $e')),
      );
    } finally {
      if (mounted) setState(() => _sendingSignature = false);
    }
  }

  Future<void> _shareTrackingLink() async {
    if (widget.orderId == null) return;
    setState(() => _sharingTracking = true);
    try {
      final token = await TrackingService.tokenForOrder(widget.orderId!);
      if (token == null) {
        throw Exception(
            'This order has no tracking token yet. Run the 28 Jul migration.');
      }
      if (!mounted) return;
      final org = AppSession.instance.currentOrgName ?? 'Nagarva';
      await ShareLinkSheet.show(
        context,
        title: 'Share tracking link',
        subtitle: 'The customer can follow their move status live. No login '
            'needed — the link itself is the access.',
        link: buildTokenLink('/track', token),
        phone: widget.orderPhone,
        message: 'Hello${widget.orderCustomer == null ? '' : ' ${widget.orderCustomer}'}, '
            'you can track your move with $org here:',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create tracking link: $e')),
      );
    } finally {
      if (mounted) setState(() => _sharingTracking = false);
    }
  }

  Widget _signatureStatusChip(BuildContext context) {
    final sig = _signature;
    if (sig == null) return const SizedBox.shrink();
    final theme = FlutterFlowTheme.of(context);
    final signed = sig.isSigned;
    final color = signed ? theme.tertiary : theme.warning;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(signed ? Icons.verified : Icons.hourglass_empty,
              size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              signed
                  ? 'Signed by ${sig.customerName ?? 'customer'}'
                      '${sig.signedAt == null ? '' : ' on ${DateFormat('d MMM yyyy').format(sig.signedAt!.toLocal())}'}'
                  : 'Awaiting customer signature',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: theme.primaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Formats a money field that arrives as a nav-param String. Falls back
  /// to the raw value rather than hiding it if it won't parse — a number
  /// we can't format is still better than a blank cell on a money row.
  String? _money(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final v = double.tryParse(raw.trim());
    return v == null ? raw : _currency.format(v);
  }

  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  /// Sequential invoice numbering — ported from apc_webapp App.jsx's
  /// DB.getNextInvoiceNo (lines ~1139-1148). Financial year is Apr-Mar.
  /// Same caveat as the reference app: this is read-then-upsert, not an
  /// atomic DB sequence, so it's not safe under truly concurrent invoice
  /// creation — acceptable for a single-office mobile app for now, flagged
  /// here for whoever eventually hardens it.
  Future<String> _nextInvoiceNo() async {
    final now = DateTime.now();
    final fy = now.month >= 4
        ? '${(now.year % 100).toString().padLeft(2, '0')}${((now.year + 1) % 100).toString().padLeft(2, '0')}'
        : '${((now.year - 1) % 100).toString().padLeft(2, '0')}${(now.year % 100).toString().padLeft(2, '0')}';
    final prefix = AppSession.instance.currentOrgSlug?.toUpperCase() ?? 'APC';
    // LEAK_AUDIT.md leak #6 (Stage 1 fix): the key used to be
    // 'inv_seq_<SLUG>_<FY>' — namespaced by string content instead of the
    // org_id column, so two orgs with colliding slug prefixes would share a
    // counter. Now that every read/write below filters on org_id, the key
    // only needs to vary by financial year; the display-facing invoice
    // number below still uses the org slug prefix for humans, that part is
    // unaffected. See migration in supabase/phase1_rename_settings_keys.sql.
    final key = 'inv_seq_$fy';

    final rows = await SettingsTable().queryRows(
      queryFn: (q) => OrgScope.read(q).eq('key', key),
    );
    final current =
        rows.isNotEmpty ? (int.tryParse(rows.first.value ?? '0') ?? 0) : 0;
    final next = current + 1;

    // `settings` now has a real composite PK on (org_id, key) (added
    // 2026-07-14), so a single upsert replaces the old insert-if-empty /
    // org-scoped-update-otherwise branch — and it's still org-scoped via
    // OrgScope.stamp() (org_id is part of the payload the constraint
    // matches on).
    await SettingsTable().upsert(
      {
        'key': key,
        ...OrgScope.stamp(),
        'value': next.toString(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'org_id,key',
    );
    return '$prefix/$fy/${next.toString().padLeft(3, '0')}';
  }

  Future<void> _generateInvoice() async {
    if (widget.orderId == null) return;
    setState(() => _generatingInvoice = true);

    try {
      // Reuse the order's invoice_no if it already has one (one invoice
      // number per order, cached — matches the reference app).
      // LEAK_AUDIT.md leak #5 (Stage 1 fix): matched only on id before.
      final existing = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', widget.orderId!),
      );
      String invoiceNo;
      if (existing.isNotEmpty && (existing.first.invoiceNo ?? '').isNotEmpty) {
        invoiceNo = existing.first.invoiceNo!;
      } else {
        invoiceNo = await _nextInvoiceNo();
        // LEAK_AUDIT.md write-gap fix: matched only on id before.
        await OrdersTable().update(
          data: {'invoice_no': invoiceNo},
          matchingRows: (q) => OrgScope.write(q).eq('id', widget.orderId!),
        );
      }

      final amount = double.tryParse(widget.orderAmount ?? '') ?? 0.0;
      const gstPct = 5.0; // no per-order gst_pct column yet — flat default,
      // same as the reference app's default.
      final interstate =
          isInterState(widget.orderFromCity, widget.orderToCity);
      final igst = interstate ? (amount * gstPct / 100).roundToDouble() : 0.0;
      final sgst =
          interstate ? 0.0 : (amount * (gstPct / 2) / 100).roundToDouble();
      final cgst = sgst;
      final baseAmount = amount - (interstate ? igst : sgst + cgst);

      if (!mounted) return;
      _showInvoiceDialog(
        invoiceNo: invoiceNo,
        baseAmount: baseAmount,
        interstate: interstate,
        igst: igst,
        sgst: sgst,
        cgst: cgst,
        total: amount,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate invoice: $e')),
      );
    } finally {
      if (mounted) setState(() => _generatingInvoice = false);
    }
  }

  /// Fetches bytes for a public image URL (logo/signature). Best-effort:
  /// invoice generation never fails just because an image is missing.
  Future<Uint8List?> _fetchBytes(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) return res.bodyBytes;
    } catch (_) {}
    return null;
  }

  /// Loads the vendor's business profile + branding saved on the Settings
  /// page (settings keys business_profile / signature_url, org logo_url)
  /// and builds the branded A4 PDF.
  Future<Uint8List> _buildInvoicePdfBytes({
    required String invoiceNo,
    required double baseAmount,
    required bool interstate,
    required double igst,
    required double sgst,
    required double cgst,
    required double total,
  }) async {
    Map<String, dynamic> profile = const {};
    String? signatureUrl;
    try {
      final rows = await SettingsTable().queryRows(
        queryFn: (q) => OrgScope.read(q)
            .inFilter('key', ['business_profile', 'signature_url']),
      );
      for (final r in rows) {
        if (r.key == 'business_profile' && (r.value ?? '').isNotEmpty) {
          final decoded = jsonDecode(r.value!);
          if (decoded is Map) profile = Map<String, dynamic>.from(decoded);
        }
        if (r.key == 'signature_url') signatureUrl = r.value;
      }
    } catch (_) {}
    final logoBytes =
        await _fetchBytes(AppSession.instance.currentOrgLogoUrl);
    final signatureBytes = await _fetchBytes(signatureUrl);

    // Item 3: embed the customer's e-signature once they've signed via
    // the public /sign link. Re-read rather than trusting the cached
    // _signature, so a PDF generated right after they sign isn't stale.
    SignatureRequest? sig = _signature;
    try {
      sig = await SignatureService.find(
            documentType: 'invoice',
            documentId: widget.orderId!,
          ) ??
          sig;
    } catch (_) {}

    return InvoicePdf.generate(
      customerSignatureBytes:
          (sig?.isSigned ?? false) ? sig!.signatureBytes : null,
      customerSignedByName: (sig?.isSigned ?? false) ? sig!.customerName : null,
      customerSignedAt: (sig?.isSigned ?? false) ? sig!.signedAt : null,
      invoiceNo: invoiceNo,
      customerName: _hideCustomer
          ? 'Customer (hidden)'
          : (widget.orderCustomer ?? '—'),
      customerPhone: _hideCustomer ? null : widget.orderPhone,
      fromCity: widget.orderFromCity,
      toCity: widget.orderToCity,
      baseAmount: baseAmount,
      interstate: interstate,
      igst: igst,
      cgst: cgst,
      sgst: sgst,
      total: total,
      orgName: AppSession.instance.currentOrgName ?? 'Nagarva',
      profile: profile,
      logoBytes: logoBytes,
      signatureBytes: signatureBytes,
    );
  }

  void _showInvoiceDialog({
    required String invoiceNo,
    required double baseAmount,
    required bool interstate,
    required double igst,
    required double sgst,
    required double cgst,
    required double total,
  }) {
    final safeName = invoiceNo.replaceAll('/', '-');
    var busy = false;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Invoice $invoiceNo'),
          content: Text(
            busy
                ? 'Preparing PDF…'
                : 'Your tax invoice is ready. Download the PDF to share on '
                    'WhatsApp/email, or print it directly.',
          ),
          actions: [
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() => busy = true);
                      final bytes = await _buildInvoicePdfBytes(
                        invoiceNo: invoiceNo,
                        baseAmount: baseAmount,
                        interstate: interstate,
                        igst: igst,
                        sgst: sgst,
                        cgst: cgst,
                        total: total,
                      );
                      await Printing.layoutPdf(onLayout: (_) async => bytes);
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
              child: const Text('Print'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() => busy = true);
                      final bytes = await _buildInvoicePdfBytes(
                        invoiceNo: invoiceNo,
                        baseAmount: baseAmount,
                        interstate: interstate,
                        igst: igst,
                        sgst: sgst,
                        cgst: cgst,
                        total: total,
                      );
                      // Browser download on web with a proper filename.
                      await Printing.sharePdf(
                          bytes: bytes,
                          filename: 'Invoice_$safeName.pdf');
                      // Job done — close the dialog instead of leaving the
                      // user staring at the same screen (Arun's feedback).
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  'Invoice_$safeName.pdf downloaded — check your Downloads bar.')),
                        );
                      }
                    },
              child: const Text('Download PDF'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => OrderDetailPageModel());
    _loadSignature();

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  /// Privacy: supervisors must not see customer identity once the order is
  /// completed (belt-and-braces on top of the OrdersPage masking, since this
  /// page is also reachable by deep link with arbitrary params).
  bool get _hideCustomer {
    if (!AppSession.instance.isSupervisorSession) return false;
    final st = (widget.orderStatus ?? '').toLowerCase();
    return st == 'delivered' || st == 'done' || st == 'completed' ||
        st == 'closed';
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
              '8dc01xr1' /* Order Details */,
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
              child: KeyboardScrollView(
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
                              _hideCustomer
                                  ? 'Customer (hidden)'
                                  : (widget.orderCustomer ?? '—'),
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
                                  (widget.orderStatus ?? '—'),
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
                    // Item 4.4: these four cards each hand-rolled every
                    // row as Row(spaceBetween, [Text(label), Text(value)])
                    // with two UNCONSTRAINED Texts — 17 of them — so a
                    // long address or service name overflowed the row
                    // instead of wrapping, and the vertical rhythm drifted
                    // between cards. All of them now go through the same
                    // shared DetailRow as Lead Details, so the two screens
                    // sit on one grid.
                    //
                    // Money now runs through _currency, which was declared
                    // in this file and never actually used — Amount and
                    // Advance Paid were rendering the raw string
                    // ("15000.0") on an ERP money field.
                    DetailCard(
                      title: 'Customer',
                      children: [
                        DetailRow(
                          label: 'Phone',
                          value: _hideCustomer
                              ? '••••••••••'
                              : widget.orderPhone,
                        ),
                        DetailRow(label: 'Service', value: widget.orderService),
                        DetailRow(label: 'Branch', value: widget.orderBranch),
                        DetailRow(label: 'Type', value: widget.orderType),
                      ],
                    ),
                    DetailCard(
                      title: 'Move Details',
                      children: [
                        DetailRow(label: 'From', value: widget.orderFromCity),
                        DetailRow(label: 'To', value: widget.orderToCity),
                        DetailRow(
                          label: 'Address (From)',
                          value: widget.orderFromAddress,
                          hideWhenEmpty: true,
                        ),
                        DetailRow(
                          label: 'Address (To)',
                          value: widget.orderToAddress,
                          hideWhenEmpty: true,
                        ),
                        DetailRow(
                          label: 'Floor (From)',
                          value: widget.orderFromFloor,
                          hideWhenEmpty: true,
                        ),
                        DetailRow(
                          label: 'Floor (To)',
                          value: widget.orderToFloor,
                          hideWhenEmpty: true,
                        ),
                        DetailRow(
                          label: 'Move Date',
                          value: widget.orderMoveDate,
                        ),
                      ],
                    ),
                    DetailCard(
                      title: 'Payment',
                      children: [
                        DetailRow(
                          label: 'Amount',
                          value: _money(widget.orderAmount),
                        ),
                        DetailRow(
                          label: 'Advance Paid',
                          value: _money(widget.orderAdvancePaid),
                        ),
                        DetailRow(
                          label: 'Payment Status',
                          value: widget.orderPaymentStatus,
                        ),
                        DetailRow(
                          label: 'Tracking Status',
                          value: widget.orderTrackingStatus,
                        ),
                      ],
                    ),
                    // Item 4.3: this had the same "Notes / Notes" duplicate
                    // as Lead Details — a section header wrapping a row
                    // whose label was also "Notes".
                    DetailCard(
                      title: 'Notes',
                      children: [
                        DetailNote(text: widget.orderNotes),
                      ],
                    ),
                    // Parity brief Part 3e: itemized quotation breakdown,
                    // if this order has one linked — was previously just a
                    // bare total with no itemisation.
                    if (widget.orderId != null)
                      QuotationBreakdownSection(
                          key: _breakdownKey, orderId: widget.orderId!),
                    // Assign supervisor + labour/salary (owner view) —
                    // was missing from the order flow entirely.
                    if (widget.orderId != null)
                      OrderCrewSection(orderId: widget.orderId!),
                    // Items 3 + 6: signature status and the two customer
                    // share actions.
                    _signatureStatusChip(context),
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          0.0, 14.0, 0.0, 0.0),
                      child: FFButtonWidget(
                        onPressed:
                            _sendingSignature ? null : _sendForSignature,
                        text: _sendingSignature
                            ? 'Preparing…'
                            : (_signature?.isSigned ?? false)
                                ? 'View signed copy'
                                : 'Send for Signature',
                        icon: const Icon(Icons.draw, size: 20.0),
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
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          0.0, 14.0, 0.0, 0.0),
                      child: FFButtonWidget(
                        onPressed: _sharingTracking ? null : _shareTrackingLink,
                        text: _sharingTracking
                            ? 'Preparing…'
                            : 'Share Tracking Link',
                        icon: const Icon(Icons.share_location, size: 20.0),
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
                    Padding(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(0.0, 14.0, 0.0, 0.0),
                      child: FFButtonWidget(
                        onPressed: () {
                          context.pushNamed(
                            SupervisorJobPageWidget.routeName,
                            queryParameters: {
                              'orderId': serializeParam(
                                  widget.orderId, ParamType.String),
                            }.withoutNulls,
                          );
                        },
                        text: 'Open Field Job',
                        icon: const Icon(
                          Icons.local_shipping,
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
                    Padding(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(0.0, 14.0, 0.0, 0.0),
                      child: FFButtonWidget(
                        onPressed:
                            _generatingInvoice ? null : _generateInvoice,
                        text: _generatingInvoice
                            ? 'Generating…'
                            : 'Generate Invoice',
                        icon: const Icon(
                          Icons.receipt_long,
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
                            NewOrderPageWidget.routeName,
                            queryParameters: {
                              'orderId': serializeParam(
                                  widget.orderId, ParamType.String),
                            }.withoutNulls,
                          );
                        },
                        text: FFLocalizations.of(context).getText(
                          '0h0xt5ip' /* Edit Order */,
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
                    // Item 11: owner-only, destructive, at the very bottom.
                    // Staff don't see it at all rather than seeing a
                    // button that always refuses.
                    if (widget.orderId != null && SoftDeleteService.isOwner)
                      DeleteAction.button(
                        context: context,
                        busy: _deleting,
                        label: 'Delete Order',
                        onPressed: _deleteOrder,
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
