import 'dart:convert';
import 'dart:typed_data';

import '/backend/gst_state_codes.dart';

import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import '/app_session.dart';
import '/permissions.dart';
import '/backend/audit_log_service.dart';
import '/backend/signature_service.dart';
import '/backend/soft_delete.dart';
import '/components/delete_action.dart';
import '/components/detail_row.dart';
import '/backend/tracking_service.dart';
import '/backend/pricing_defaults.dart';
import '/components/invoice_pdf.dart';
import '/components/pdf_branding.dart';
import '/components/share_link_sheet.dart';
import '/config/app_config.dart';
import 'order_crew_section.dart';
import 'order_documents_section.dart';
import 'order_pnl_section.dart';
import 'payment_history_section.dart';
import 'quick_payment_section.dart';
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
import 'arrival_code_card.dart';
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

  // ---- Order Details Session 1, item 3: duplicate ------------------------
  bool _duplicating = false;

  /// Same convention as new_order_page's/lead_detail_page's own
  /// `_nextOrderId` — orders.id is text with no default, must be supplied
  /// on insert or NOT-NULL fires (23502).
  Future<String> _nextOrderId() async {
    final prefix = AppSession.instance.currentOrgSlug?.toUpperCase() ?? 'NGV';
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

  /// Clones the shipment/pricing fields only — the same field set
  /// new_order_page's own create-payload uses. Transactional/workflow
  /// state (status, payment_status, tracking_status, advance_paid,
  /// paid_total) always resets to fresh-order defaults, never carried
  /// over, so a duplicate never inherits the source order's payment
  /// history or job progress.
  Future<void> _duplicateOrder() async {
    if (widget.orderId == null) return;
    final rows = await OrdersTable().queryRows(
      queryFn: (q) => OrgScope.read(q).eq('id', widget.orderId!),
    );
    if (rows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Order not found.')));
      }
      return;
    }
    final o = rows.first;

    DateTime pickedDate = DateTime.now();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
          title: const Text('Duplicate Order'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Creates a new order for ${o.customer} with the same '
                'shipment details. Payment and job status start fresh.',
                style: GoogleFonts.inter(fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: pickedDate,
                    firstDate:
                        DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setDialogState(() => pickedDate = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Move Date'),
                  child: Text(DateFormat('d MMM y').format(pickedDate)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Duplicate')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() => _duplicating = true);
    try {
      final orgId = OrgScope.currentOrgId!;
      final newOrderId = await _nextOrderId();
      final created = await OrdersTable().insert({
        'id': newOrderId,
        ...OrgScope.stamp(orgId: orgId),
        'customer': o.customer,
        'phone': o.phone,
        if (o.customerId != null) 'customer_id': o.customerId,
        'from_city': o.fromCity,
        'to_city': o.toCity,
        'from_address': o.fromAddress,
        'to_address': o.toAddress,
        'from_floor': o.fromFloor,
        'to_floor': o.toFloor,
        'move_date': supaSerialize<DateTime>(pickedDate),
        'amount': o.amount,
        'distance_km': o.distanceKm,
        'service': o.service,
        'branch': o.branch,
        'order_type': o.orderType,
        'order_source': o.orderSource,
        if (o.rateCardId != null) 'rate_card_id': o.rateCardId,
        if (o.contractId != null) 'contract_id': o.contractId,
        // Not in the brief's literal §3 clone list, but necessary for
        // consistency: this app's actual porter-commission mechanism is
        // is_porter/porter_commission_pct (order_type is just a Direct/
        // Porter label here, not the brief's assumed local/outstation
        // split — see the P&L card's own doc comment). Cloning order_type
        // without these would silently produce a "Porter" duplicate with
        // no commission in its own P&L.
        'is_porter': o.isPorter ?? false,
        'porter_commission_pct': o.porterCommissionPct,
        // Brief §3 "Set": notes -> "Copy of {source_id}", not the
        // original notes.
        'notes': 'Copy of ${o.id}',
        // Brief §3 "Reset": pending, not new_order_page's usual 'booked' —
        // a duplicate starts one stage earlier, before advance_paid/
        // paid_total/payment_status all reset to their own zero/pending
        // defaults below. vehicle_no/driver/supervisor_id/invoice_no/
        // lr_id/job_otp/supervisor_status are satisfied by omission (a
        // fresh insert starts every unlisted column at its own default).
        'status': 'pending',
        'payment_status': 'pending',
        'tracking_status': 'Pending',
        'advance_paid': 0.0,
      });
      await AuditLogService.log(
        entityType: 'orders',
        entityId: created.id!,
        action: 'duplicated',
        newValue: {'source_order_id': o.id, 'move_date': created.moveDateOrNull?.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Duplicated as ${created.id}.')));
      context.pushNamed(
        OrderDetailPageWidget.routeName,
        queryParameters: {
          'orderId': serializeParam(created.id, ParamType.String),
          'orderCustomer':
              serializeParam(created.customer, ParamType.String),
          'orderPhone': serializeParam(created.phone, ParamType.String),
          'orderFromCity':
              serializeParam(created.fromCity, ParamType.String),
          'orderToCity': serializeParam(created.toCity, ParamType.String),
          'orderFromAddress':
              serializeParam(created.fromAddress, ParamType.String),
          'orderToAddress':
              serializeParam(created.toAddress, ParamType.String),
          'orderFromFloor':
              serializeParam(created.fromFloor?.toString(), ParamType.String),
          'orderToFloor':
              serializeParam(created.toFloor?.toString(), ParamType.String),
          'orderMoveDate': serializeParam(
              created.moveDateOrNull?.toString(), ParamType.String),
          'orderAmount':
              serializeParam(created.amount?.toString(), ParamType.String),
          'orderAdvancePaid': serializeParam(
              created.advancePaid?.toString(), ParamType.String),
          'orderStatus': serializeParam(created.status, ParamType.String),
          'orderPaymentStatus':
              serializeParam(created.paymentStatus, ParamType.String),
          'orderTrackingStatus':
              serializeParam(created.trackingStatus, ParamType.String),
          'orderService': serializeParam(created.service, ParamType.String),
          'orderBranch': serializeParam(created.branch, ParamType.String),
          'orderType': serializeParam(created.orderType, ParamType.String),
          'orderNotes': serializeParam(created.notes, ParamType.String),
        }.withoutNulls,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not duplicate: $e')));
      }
    } finally {
      if (mounted) setState(() => _duplicating = false);
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
    // Order Details Session 1, item 1: keep the P&L card current after a
    // payment update, an expense/vendor-bill write, etc. elsewhere.
    _pnlKey.currentState?.reload();
    _quickPaymentKey.currentState?.reload();
  }

  final _breakdownKey = GlobalKey<QuotationBreakdownSectionState>();
  final _pnlKey = GlobalKey<OrderPnlSectionState>();
  final _quickPaymentKey = GlobalKey<QuickPaymentSectionState>();
  final _paymentHistoryKey = GlobalKey<PaymentHistorySectionState>();

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

  // Fixed (RLS/numbering audit, 12 Aug 2026): used to emit '2627' —
  // concatenated 2-digit years, no hyphen — which never matched the
  // hyphenated 'YYYY-YY' fy values migration 009 actually seeded into
  // number_series (e.g. '2026-27'). next_doc_number() doesn't error on a
  // miss (see the migration handed back alongside this fix, which closes
  // that), it silently INSERTs a brand-new unprefixed series row — so
  // every real invoice went out on a bare, prefix-less number
  // (confirmed live: APC-1006's invoice_no is '0001', not '2026/0001')
  // instead of the intended series. This format is now the single source
  // of truth every doc-type's fy must agree on — see the identical fix in
  // quick_payment_section.dart and order_documents_section.dart.
  static String currentFy() {
    final now = DateTime.now();
    final startYear = now.month >= 4 ? now.year : now.year - 1;
    return '$startYear-${((startYear + 1) % 100).toString().padLeft(2, '0')}';
  }

  /// Sequential invoice numbering. Order Details Session 1's brief is
  /// explicit: "Use next_doc_number for every document number. Do not
  /// roll your own counter" — migration 006's `number_series`/
  /// `next_doc_number(org, doc_type, branch, fy)` is atomic (row-locked)
  /// where the old mechanism this replaced was read-then-upsert against
  /// `settings` (ported from apc_webapp's own non-atomic
  /// DB.getNextInvoiceNo). Flagged for Arun: this starts a NEW series in
  /// `number_series` — it does not continue the old `inv_seq_<fy>` counter
  /// in `settings`, so the next invoice number restarts from 1 rather than
  /// picking up after the last one issued under the old mechanism.
  ///
  /// Session 3, task #46: `next_doc_number`'s return value already IS the
  /// full formatted number — `coalesce(prefix,'') || padded_n ||
  /// coalesce(suffix,'')` (migration 006's own function body). Migration
  /// 009 rewrote every org's `number_series.prefix` for these doc_types
  /// from the old `'INV-'`-style to a calendar-year `'2026/'`-style, to
  /// match APC's real `2026/0013` format — so the RPC alone now returns
  /// e.g. `'2026/0013'`. This method used to ALSO prepend
  /// `'$orgSlug/${currentFy()}/'` on top of that, which after 009 would
  /// have doubled up into `'APC/2526/2026/0013'`. Fixed: return the RPC's
  /// result as-is.
  Future<String> _nextInvoiceNo({String? branch}) async {
    return await SupaFlow.client.rpc('next_doc_number', params: {
      'p_org': OrgScope.currentOrgId!,
      'p_doc_type': 'invoice',
      'p_branch': branch,
      'p_fy': currentFy(),
    }) as String;
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
        // Numbering-scheme decision (12 Aug 2026): one org-wide series per
        // doc type per FY, not per-branch. Under GST the invoice series
        // must be unique and gapless per registered person per FY —
        // per-branch series are for genuinely separate registrations, not
        // two branches under one GSTIN. branch: null always, now and
        // going forward; _nextInvoiceNo still accepts the parameter (kept
        // for a future tenant with real separate registrations), it's
        // just never passed a real value from here anymore.
        invoiceNo = await _nextInvoiceNo();
        // LEAK_AUDIT.md write-gap fix: matched only on id before.
        // invoice_issued_at stamped alongside invoice_no — same "once, at
        // first generation" convention as the number itself; a re-open of
        // an already-invoiced order reuses both rather than overwriting
        // the original date (see the `if` branch above).
        await OrdersTable().update(
          data: {
            'invoice_no': invoiceNo,
            'invoice_issued_at': DateTime.now().toIso8601String(),
          },
          matchingRows: (q) => OrgScope.write(q).eq('id', widget.orderId!),
        );
      }

      final amount = double.tryParse(widget.orderAmount ?? '') ?? 0.0;
      // Fixed (RLS/numbering audit, 12 Aug 2026): was a hardcoded 5.0
      // unconditionally, ignoring orders.quote_gst_pct even when it held
      // the real quoted rate — confirmed live to have wrongly invoiced at
      // least one order (18% quoted, 5% billed). quote_gst_pct falls back
      // to 5% only when the order genuinely has no stored rate (24 of 25
      // live orders today, since this column is rarely populated), never
      // as a silent override of a real one.
      final gstPct = existing.isNotEmpty ? (existing.first.quoteGstPct ?? 5.0) : 5.0;
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
        // Part 8 addendum item 3: lets _buildInvoicePdfBytes fall back to
        // the quote's signature when this order has none of its own yet.
        quotationId:
            existing.isNotEmpty ? existing.first.quotationId : null,
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
    String? quotationId,
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

    // Dual-source branding (Session 3, task #41): organizations columns
    // first, that same org's business_profile jsonb as fallback — see
    // OrgProfile.resolve's own doc comment.
    OrganizationsRow? orgRow;
    try {
      final orgRows = await OrganizationsTable().queryRows(
        queryFn: (q) => q.eq('id', OrgScope.currentOrgId!),
      );
      if (orgRows.isNotEmpty) orgRow = orgRows.first;
    } catch (_) {}
    final org = OrgProfile.resolve(orgRow,
        businessProfile: profile, legacyESignUrl: signatureUrl);

    DocumentBoilerplate boilerplate = const DocumentBoilerplate();
    try {
      final docRows = await AppSettingsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('category', 'documents'),
      );
      boilerplate = DocumentBoilerplate.resolve(docRows);
    } catch (_) {}

    final logoBytes = await _fetchBytes(AppSession.instance.currentOrgLogoUrl);
    final signatureBytes = await _fetchBytes(org.signatoryImageUrl);

    // Tier A fields (field spec §3): Bill No/LR ref/Delivery Date/Vehicle
    // No/billing party/HSN/package+weight/payment remark/remark all live on
    // the order row itself (migration 009) — not carried in the page's nav
    // params, so re-queried here same as _generateInvoice already does for
    // invoice_no/quotation_id.
    OrdersRow? order;
    try {
      final rows = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', widget.orderId!),
      );
      if (rows.isNotEmpty) order = rows.first;
    } catch (_) {}

    String? lrNo;
    int? packageCount;
    num? actualWeightKg;
    num? chargedWeightKg;
    String? gstPayableBy;
    if ((order?.lrId ?? '').isNotEmpty) {
      try {
        final lr = await SupaFlow.client
            .from('lr_register')
            .select('lr_no,package_count,actual_weight_kg,charged_weight_kg,'
                'gst_payable_by')
            .eq('id', order!.lrId!)
            .maybeSingle();
        if (lr != null) {
          lrNo = lr['lr_no'] as String?;
          packageCount = lr['package_count'] as int?;
          actualWeightKg = lr['actual_weight_kg'] as num?;
          chargedWeightKg = lr['charged_weight_kg'] as num?;
          final gpb = lr['gst_payable_by'] as String?;
          gstPayableBy = (gpb == null || gpb.isEmpty)
              ? null
              : gpb[0].toUpperCase() + gpb.substring(1);
        }
      } catch (_) {}
    }

    // Same charge heads the quotation shows (field spec §3: "Particulars
    // column same heads as quote") — only when this order has a linked
    // quote with a saved charges breakdown; otherwise InvoicePdf falls
    // back to a single freight line built from baseAmount.
    final particulars = <MapEntry<String, num>>[];
    if ((quotationId ?? '').isNotEmpty) {
      try {
        final qRows = await QuotationsTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('id', quotationId!),
        );
        final charges = qRows.isNotEmpty ? qRows.first.charges : null;
        if (charges is Map) {
          final chargesMap = Map<String, dynamic>.from(charges);
          num amt(String key) {
            final v = chargesMap[key];
            if (v is num) return v;
            if (v is Map && v['amount'] is num) return v['amount'] as num;
            return num.tryParse('$v') ?? 0;
          }

          for (final f in kDefaultChargeFields) {
            if (f.key == 'discount' || f.key == 'advanceOnQuote') continue;
            final a = amt(f.key);
            if (a != 0) particulars.add(MapEntry(f.label, a));
          }
        }
      } catch (_) {}
    }

    String? amountInWords;
    try {
      amountInWords = await SupaFlow.client
          .rpc('amount_in_words', params: {'amt': total}) as String?;
    } catch (_) {}

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

    // Part 8 addendum item 3: an invoice-specific signature always takes
    // precedence if one was captured. Only when NONE exists does this fall
    // back to the quote's signature via the order's quotation_id — the
    // invoice signature-request button (Send for Signature, below) still
    // works exactly as before and, once used, permanently overrides this
    // fallback for this order.
    var inherited = false;
    if (!(sig?.isSigned ?? false) && (quotationId ?? '').isNotEmpty) {
      try {
        final quoteSig = await SignatureService.find(
          documentType: 'quote',
          documentId: quotationId!,
        );
        if (quoteSig?.isSigned ?? false) {
          sig = quoteSig;
          inherited = true;
        }
      } catch (_) {}
    }
    final quoteRef = (quotationId ?? '').length >= 8
        ? quotationId!.substring(0, 8).toUpperCase()
        : quotationId;

    return InvoicePdf.generate(
      customerSignatureBytes:
          (sig?.isSigned ?? false) ? sig!.signatureBytes : null,
      customerSignedByName: (sig?.isSigned ?? false) ? sig!.customerName : null,
      customerSignedByPhone:
          (sig?.isSigned ?? false) ? (_hideCustomer ? null : widget.orderPhone) : null,
      customerSignedAt: (sig?.isSigned ?? false) ? sig!.signedAt : null,
      signatureInherited: inherited,
      inheritedFromQuoteRef: inherited ? quoteRef : null,
      invoiceNo: invoiceNo,
      org: org,
      boilerplate: boilerplate,
      customerName: _hideCustomer
          ? 'Customer (hidden)'
          : (widget.orderCustomer ?? '—'),
      customerPhone: _hideCustomer ? null : widget.orderPhone,
      fromCity: widget.orderFromCity,
      toCity: widget.orderToCity,
      fromAddress: order?.fromAddress,
      toAddress: order?.toAddress,
      baseAmount: baseAmount,
      interstate: interstate,
      igst: igst,
      cgst: cgst,
      sgst: sgst,
      total: total,
      logoBytes: logoBytes,
      signatureBytes: signatureBytes,
      lrNo: lrNo,
      deliveryDate: order?.deliveryDate,
      vehicleNo: order?.vehicleNo,
      billingPartyName: order?.billingPartyName,
      billingPartyGstin: order?.billingPartyGstin,
      billingPartyAddress: order?.billingPartyAddress,
      billingPartyPhone: order?.billingPartyPhone,
      packageCount: packageCount,
      actualWeightKg: actualWeightKg,
      chargedWeightKg: chargedWeightKg,
      hsnSacCode: (order?.hsnSacCode ?? '').isEmpty ? '996719' : order!.hsnSacCode!,
      paymentRemark: order?.paymentRemark,
      remark: order?.notes,
      particulars: particulars,
      gstPayableBy: gstPayableBy,
      reverseCharge: order?.reverseCharge ?? false,
      amountInWords: amountInWords,
      isPaid: order?.paymentStatus == 'paid',
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
    String? quotationId,
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
                        quotationId: quotationId,
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
                        quotationId: quotationId,
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
                    // Arrival code (19 Aug 2026). Placed high on the page
                    // on purpose: the office reads this out when a crew
                    // phones from the doorstep, so it must not be
                    // something you scroll for. Owner/manager/admin only —
                    // the widget enforces that itself too, because
                    // showing it to the supervisor would make the gate
                    // decorative (see its doc comment).
                    if (widget.orderId != null)
                      ArrivalCodeCard(orderId: widget.orderId!),
                    // Item 4.3: this had the same "Notes / Notes" duplicate
                    // as Lead Details — a section header wrapping a row
                    // whose label was also "Notes".
                    DetailCard(
                      title: 'Notes',
                      children: [
                        DetailNote(text: widget.orderNotes),
                      ],
                    ),
                    // Order Details Session 1, item 2: Quick Payment
                    // Update. Brief: gated on canActive('orders','edit')
                    // (not a payments-module permission) — the "hidden
                    // when already paid" half of the brief's gate is
                    // enforced inside the section itself (balance <= 0).
                    if (widget.orderId != null &&
                        StaffPermissions.canActive('orders', 'edit'))
                      QuickPaymentSection(
                          key: _quickPaymentKey,
                          orderId: widget.orderId!,
                          onSaved: () {
                            _pnlKey.currentState?.reload();
                            _paymentHistoryKey.currentState?.reload();
                          }),
                    // Item 11 sweep: payment-entry delete UI. Renders
                    // regardless of order/balance state (unlike
                    // QuickPaymentSection above) — always visible when
                    // canActive('orders','edit'), same gate.
                    if (widget.orderId != null &&
                        StaffPermissions.canActive('orders', 'edit'))
                      PaymentHistorySection(
                          key: _paymentHistoryKey,
                          orderId: widget.orderId!,
                          onChanged: () => _pnlKey.currentState?.reload()),
                    // Order Details Session 1, item 1: P&L card. Gated on
                    // canActive('reports','view') — absent, not disabled,
                    // for a session without reports access (matches the
                    // OrderCrewSection gate immediately below).
                    if (widget.orderId != null &&
                        StaffPermissions.canActive('reports', 'view'))
                      OrderPnlSection(
                          key: _pnlKey, orderId: widget.orderId!),
                    // Parity brief Part 3e: itemized quotation breakdown,
                    // if this order has one linked — was previously just a
                    // bare total with no itemisation.
                    if (widget.orderId != null)
                      QuotationBreakdownSection(
                          key: _breakdownKey, orderId: widget.orderId!),
                    // Assign supervisor + labour/salary (owner view) —
                    // was missing from the order flow entirely.
                    // Permission-model decision (1 Aug 2026), Step 4 sweep:
                    // absent, not disabled, for a staff session without
                    // salary.view — a supervisor must not see this section
                    // at all.
                    if (widget.orderId != null &&
                        StaffPermissions.canActive('salary', 'view'))
                      OrderCrewSection(
                          orderId: widget.orderId!,
                          onCrewChanged: () =>
                              _pnlKey.currentState?.reload()),
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
                    // Hidden until /track is actually hosted. The page and
                    // the token plumbing both work; the path has simply
                    // never been deployed, so this could only hand a
                    // customer a dead link. See kTrackLinkHosted.
                    if (kTrackLinkHosted)
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
                    // Permission-model decision (1 Aug 2026), Step 4 sweep:
                    // absent, not disabled, without orders.edit.
                    if (StaffPermissions.canActive('orders', 'edit'))
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
                    // Order Details Session 1, item 4: the 8-document grid
                    // + 4-button utility row (incl. "⧉ Copy" = Duplicate
                    // Order, per the brief's §3 placement) lives here.
                    if (widget.orderId != null)
                      OrderDocumentsSection(
                        orderId: widget.orderId!,
                        duplicating: _duplicating,
                        onDuplicate: _duplicateOrder,
                        onGenerateInvoice:
                            _generatingInvoice ? () {} : _generateInvoice,
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
