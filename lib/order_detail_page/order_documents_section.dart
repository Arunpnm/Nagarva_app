import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '/app_session.dart';
import '/backend/audit_log_service.dart';
import '/backend/tracking_service.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/upi_payment.dart';
import '/components/pdf_branding.dart';
import '/components/lr_pdf.dart';
import '/components/money_receipt_pdf.dart';
import '/components/signature_pad.dart';
import '/components/pod_pdf.dart';
import '/components/simple_document_pdf.dart';
import '/config/app_config.dart';
import '/flutter_flow/flutter_flow_theme.dart';

/// Order Details Session 1, item 4 — the documents grid + signature
/// companion + utility row.
///
/// Tax Invoice is deliberately NOT generated here — `InvoicePdf` already
/// exists (Part 8 addendum) with its own signature-inheritance and GST
/// logic on the parent page; duplicating that here would fork behaviour
/// two ways for one document. [onGenerateInvoice] delegates back to it.
///
/// Schema realities that shaped this file:
///   - Migration 007 widened `document_signatures.document_type`'s CHECK
///     constraint (was `('quote','invoice')` only) and added `order_id` +
///     `is_persistent`, specifically so the companion signature captured
///     here durably persists for all 4 companion types (invoice, receipt,
///     lr, voucher) — see [_persistToAllCompanionTypes]/
///     [_loadHeldSignature]. Before 007 this only worked for Invoice.
///   - Migration 007 also added `next_lr_number(org, branch, fy)` — an
///     atomic, row-locked allocator for `lr_series`, same contract as
///     `next_doc_number`. LR generation uses it instead of the
///     read-then-write this file used before 007 landed.
///   - Packing List / Loading Slip items still have no backing table in
///     any migration, so they're entered fresh each time via the shared
///     item modal and are not persisted between generations — not a gap
///     007 addressed.
class OrderDocumentsSection extends StatefulWidget {
  const OrderDocumentsSection({
    super.key,
    required this.orderId,
    required this.duplicating,
    required this.onDuplicate,
    required this.onGenerateInvoice,
  });

  final String orderId;
  final bool duplicating;
  final VoidCallback onDuplicate;

  /// Tax Invoice generation stays on the parent page — it already has its
  /// own `InvoicePdf` + signature-inheritance logic (Part 8 addendum) —
  /// this just triggers it, matching onDuplicate/onSaved/onCrewChanged's
  /// callback pattern rather than duplicating that logic here.
  final VoidCallback onGenerateInvoice;

  @override
  State<OrderDocumentsSection> createState() => _OrderDocumentsSectionState();
}

class _OrderDocumentsSectionState extends State<OrderDocumentsSection> {
  Uint8List? _heldSignature;
  DateTime? _heldSignatureAt;
  bool _busy = false;
  OrdersRow? _order;

  /// Every document type whose PDF can carry the captured companion
  /// signature. Kept as one list so capture/reload/clear all iterate the
  /// same set — Tax Invoice's row is the same (org_id, 'invoice',
  /// document_id=orderId) row the parent page's pre-existing Send-for-
  /// Signature flow already reads, so persisting here makes that flow
  /// pick it up too with no direct wiring between the two widgets.
  static const _companionDocTypes = ['invoice', 'receipt', 'lr', 'voucher'];

  @override
  void initState() {
    super.initState();
    _loadOrder();
    _loadHeldSignature();
  }

  Future<void> _loadOrder() async {
    final rows = await OrdersTable().queryRows(
      queryFn: (q) => OrgScope.read(q).eq('id', widget.orderId),
    );
    if (mounted) setState(() => _order = rows.isNotEmpty ? rows.first : null);
  }

  /// Migration 007: document_signatures gained `order_id` + `is_persistent`
  /// specifically so a captured companion signature reloads after leaving
  /// and returning to the page, instead of only lasting the session.
  Future<void> _loadHeldSignature() async {
    final orgId = OrgScope.currentOrgId;
    if (orgId == null) return;
    try {
      final rows = await SupaFlow.client
          .from('document_signatures')
          .select('signature_data,signed_at')
          .eq('org_id', orgId)
          .eq('order_id', widget.orderId)
          .eq('is_persistent', true)
          .eq('status', 'signed')
          .order('signed_at', ascending: false)
          .limit(1);
      if (rows.isEmpty || !mounted) return;
      final data = rows.first['signature_data'] as String?;
      if (data == null) return;
      final signedAt = rows.first['signed_at'] as String?;
      setState(() {
        _heldSignature = base64Decode(data);
        _heldSignatureAt = signedAt == null ? null : DateTime.tryParse(signedAt);
      });
    } catch (_) {
      // Best-effort — a reload failure just means the banner starts
      // uncaptured, same as before 007; it doesn't block the page.
    }
  }

  // Fixed alongside OrderDetailPage.currentFy() (RLS/numbering audit, 12
  // Aug 2026) — was emitting '2627', which never matched number_series'
  // hyphenated 'YYYY-YY' seed values, so LR/proforma/voucher numbering
  // silently drew from an auto-created unprefixed series instead of the
  // intended one.
  String _currentFy() {
    final now = DateTime.now();
    final startYear = now.month >= 4 ? now.year : now.year - 1;
    return '$startYear-${((startYear + 1) % 100).toString().padLeft(2, '0')}';
  }

  String _rupees(num v) => '₹${v.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  Future<Uint8List?> _fetchBytes(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) return res.bodyBytes;
    } catch (_) {}
    return null;
  }

  /// Same business_profile/logo lookup the Tax Invoice already uses, kept
  /// local here rather than shared to avoid a cross-file dependency for a
  /// handful of lines — matches this codebase's existing per-page
  /// duplication convention (see _nextOrderId in new_order_page/
  /// order_detail_page/lead_detail_page).
  Future<(Map<String, dynamic>, Uint8List?)> _loadBranding() async {
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
    final logoBytes = await _fetchBytes(AppSession.instance.currentOrgLogoUrl);
    return (profile, logoBytes);
  }

  /// Dual-source branding (Session 3, task #41) + document boilerplate —
  /// the resolved form the rebuilt LR/Money Receipt/Quotation generators
  /// use, as opposed to [_loadBranding]'s raw jsonb map (kept for the
  /// SimpleDocumentPdf-based documents this session didn't rebuild).
  Future<(OrgProfile, DocumentBoilerplate, Uint8List?)> _loadOrgProfile() async {
    final (profile, logoBytes) = await _loadBranding();
    String? signatureUrl;
    try {
      final rows = await SettingsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('key', 'signature_url'),
      );
      if (rows.isNotEmpty) signatureUrl = rows.first.value;
    } catch (_) {}
    OrganizationsRow? orgRow;
    try {
      final orgId = OrgScope.currentOrgId;
      if (orgId != null) {
        final rows =
            await OrganizationsTable().queryRows(queryFn: (q) => q.eq('id', orgId));
        if (rows.isNotEmpty) orgRow = rows.first;
      }
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

    return (org, boilerplate, logoBytes);
  }

  // ---- Signature companion -------------------------------------------

  Future<void> _captureSignature() async {
    final padKey = GlobalKey<SignaturePadState>();
    bool hasStroke = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
          title: const Text('Capture Signature'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Hand the device to the customer to sign. This applies to '
                  'every document generated for this order until cleared.',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SignaturePad(
                    key: padKey,
                    onChanged: (v) => setDialogState(() => hasStroke = v),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      padKey.currentState?.clear();
                      setDialogState(() => hasStroke = false);
                    },
                    child: const Text('Clear'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: !hasStroke
                    ? null
                    : () => Navigator.of(dialogContext).pop(true),
                child: const Text('Use Signature')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final b64 = await padKey.currentState?.toPngBase64();
    if (b64 == null) return;
    setState(() {
      _heldSignature = base64Decode(b64);
      _heldSignatureAt = DateTime.now();
    });
    await _persistToAllCompanionTypes();
  }

  /// Clears the in-memory hold AND turns off `is_persistent` on every
  /// companion row for this order — "Clear only on explicit user action"
  /// per the brief. Rows are updated, not deleted: the signed record
  /// stays for whichever documents already went out with it, it just
  /// stops being the thing new documents automatically carry.
  Future<void> _clearHeldSignature() async {
    setState(() {
      _heldSignature = null;
      _heldSignatureAt = null;
    });
    final orgId = OrgScope.currentOrgId;
    if (orgId == null) return;
    try {
      await SupaFlow.client
          .from('document_signatures')
          .update({'is_persistent': false})
          .eq('org_id', orgId)
          .eq('order_id', widget.orderId)
          .eq('is_persistent', true);
    } catch (_) {}
  }

  /// Persists the held signature against every companion document type at
  /// once (migration 007 widened the CHECK constraint from `('quote',
  /// 'invoice')` to include receipt/lr/voucher/etc, and added `order_id` +
  /// `is_persistent` for exactly this). Captured once here, rather than
  /// per-generation, so it's already reloadable the moment it's captured —
  /// including by the parent page's pre-existing Tax Invoice signature
  /// flow, which reads the same (org_id, 'invoice', document_id=orderId)
  /// row independently.
  Future<void> _persistToAllCompanionTypes() async {
    final sig = _heldSignature;
    if (sig == null) return;
    final orgId = OrgScope.currentOrgId;
    if (orgId == null) return;
    final signedAt = (_heldSignatureAt ?? DateTime.now()).toIso8601String();
    final encoded = base64Encode(sig);
    for (final docType in _companionDocTypes) {
      try {
        await SupaFlow.client.from('document_signatures').upsert({
          'org_id': orgId,
          'document_type': docType,
          'document_id': widget.orderId,
          'order_id': widget.orderId,
          'is_persistent': true,
          'customer_name': _order?.customer,
          'signature_data': encoded,
          'signed_at': signedAt,
          'status': 'signed',
        }, onConflict: 'org_id,document_type,document_id');
      } catch (_) {
        // Best-effort per type — a PDF generated this session still
        // carries the signature image from _heldSignature either way;
        // this only affects whether that specific type reloads later.
      }
    }
  }

  // ---- Shared print/share dialog --------------------------------------

  Future<void> _showDocDialog(
      String title, String filename, Future<Uint8List> Function() build) {
    var busy = false;
    return showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: Text(busy
              ? 'Preparing PDF…'
              : 'Your document is ready. Download to share on WhatsApp/'
                  'email, or print it directly.'),
          actions: [
            // Every other dialog in the app can be dismissed. This one had
            // Print and Download only, so it could be closed just by tapping
            // the scrim - undiscoverable, and impossible on a build that
            // hangs.
            TextButton(
              onPressed:
                  busy ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() => busy = true);
                      final bytes = await build();
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
                      final bytes = await build();
                      await Printing.sharePdf(bytes: bytes, filename: filename);
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('$filename downloaded.')));
                      }
                    },
              child: const Text('Download'),
            ),
          ],
        ),
      ),
    );
  }

  /// Label of the document currently generating, so its tile can show a
  /// spinner instead of looking untouched. Null when idle.
  String? _pendingLabel;

  /// Documents that a customer's signature belongs on.
  ///
  /// Arun, 3 Sept 2026: *"customer sign is must in doc"*. Not every
  /// document needs one — a packing list or a loading slip is an internal
  /// working sheet — but anything that settles what was delivered or what
  /// is owed should carry the customer's signature, or it is worth
  /// nothing in a dispute months later.
  static const _needsCustomerSignature = <String>{
    'Tax Invoice',
    'Money Receipt',
    'LR / Bilty',
    'Proof of Delivery',
  };

  /// Warns before generating a signature-bearing document with no
  /// signature held.
  ///
  /// A WARNING, not a block. A vendor legitimately prints an invoice
  /// before the customer has signed anything, and refusing would stop
  /// real work. But generating one silently is how a POD ends up filed
  /// with an empty signature box that nobody notices until it is needed.
  /// Returns true to proceed.
  Future<bool> _confirmUnsigned(String label) async {
    if (_heldSignature != null) return true;
    if (!_needsCustomerSignature.contains(label)) return true;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
        title: const Text('No customer signature'),
        content: Text('This $label will be generated without the '
            'customer signature.\n\nUse "Capture Signature" above to take '
            'it on this device first, if the customer is with you.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Generate anyway')),
        ],
      ),
    );
    return go == true;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not generate: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pendingLabel = null;
        });
      }
    }
  }

  // ---- Money Receipt (field spec §4 — rebuild, task #45) -----------------
  //
  // Consolidated by design: every payment_entries row for this order that
  // hasn't been receipted yet (receipt_id null) is folded into ONE new
  // receipt, matching APC's own receipts showing up to three UPI
  // transaction ids on one document rather than one receipt per payment.

  Future<void> _genMoneyReceipt() => _run(() async {
        final o = _order;
        if (o == null) return;
        final orgId = OrgScope.currentOrgId!;

        final unreceipted = await PaymentEntriesTable().queryRows(
          queryFn: (q) => OrgScope.read(q)
              .eq('order_id', o.id!)
              .isFilter('receipt_id', null)
              .order('created_at', ascending: true),
        );

        List<PaymentEntriesRow> toReceipt = unreceipted;
        ReceiptsRow? existingReceipt;
        if (unreceipted.isEmpty) {
          // Nothing new to receipt — reprint the most recent existing one
          // instead of erroring, so the button still does something useful
          // on an order that's already fully receipted.
          final rows = await ReceiptsTable().queryRows(
            queryFn: (q) => OrgScope.read(q)
                .eq('order_id', o.id!)
                .order('created_at', ascending: false),
          );
          if (rows.isEmpty) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('No payments recorded for this order yet.')));
            return;
          }
          existingReceipt = rows.first;
        }

        final (org, boilerplate, logoBytes) = await _loadOrgProfile();

        String receiptNo;
        DateTime receiptDate;
        num amount;
        String paymentMode;
        String? referenceNos;
        bool isFinal;
        String receiptId;
        DateTime? invoiceDate;

        if (existingReceipt != null) {
          receiptNo = existingReceipt.receiptNo;
          receiptDate = existingReceipt.receiptDate ?? DateTime.now();
          amount = existingReceipt.totalAmount ?? 0;
          paymentMode = existingReceipt.paymentMode ?? 'cash';
          referenceNos = existingReceipt.referenceNos;
          isFinal = existingReceipt.isFinal;
          receiptId = existingReceipt.id!;
          invoiceDate = existingReceipt.invoiceDate;
        } else {
          // One org-wide series per doc type per FY, not per-branch (12
          // Aug 2026 numbering-scheme decision — see
          // order_detail_page_widget.dart's _nextInvoiceNo).
          receiptNo = await SupaFlow.client.rpc('next_doc_number', params: {
            'p_org': orgId,
            'p_doc_type': 'receipt',
            'p_branch': null,
            'p_fy': _currentFy(),
          }) as String;
          receiptDate = DateTime.now();
          amount = toReceipt.fold<num>(0, (s, p) => s + p.amount);
          final modes = toReceipt.map((p) => p.mode).toSet();
          paymentMode = modes.length == 1 ? modes.first : 'multiple';
          referenceNos = toReceipt
              .map((p) => p.reference ?? '')
              .where((r) => r.isNotEmpty)
              .join(', ');
          // orders.quote_total/amount fallback — same convention as the P&L
          // card, Close Order's balance warning, and the Awaiting Approval
          // queue (see CLAUDE.md's changelog on the quote_total/amount
          // split): a directly-booked order has no quote_total.
          final revenueBase =
              (o.quoteTotal ?? 0) != 0 ? o.quoteTotal! : (o.amount ?? 0);
          isFinal = o.paidTotal >= revenueBase && revenueBase > 0;

          String? amountInWords;
          try {
            amountInWords = await SupaFlow.client.rpc('amount_in_words',
                params: {'amt': amount}) as String?;
          } catch (_) {}

          // orders.invoice_issued_at (stamped once, at first Tax Invoice
          // generation — see order_detail_page_widget.dart._generateInvoice)
          // is the real source for "Dated {invoice_date}"; null on an
          // order that hasn't been invoiced yet, which the PDF already
          // omits cleanly rather than guessing.
          invoiceDate = o.invoiceIssuedAt;

          final inserted = await ReceiptsTable().insert({
            'org_id': orgId,
            'receipt_no': receiptNo,
            'receipt_date': receiptDate.toIso8601String(),
            'order_id': o.id,
            'customer_id': o.customerId,
            'invoice_no': o.invoiceNo,
            'invoice_date': invoiceDate?.toIso8601String(),
            'total_amount': amount,
            'amount_in_words': amountInWords,
            'payment_mode': paymentMode,
            'reference_nos': referenceNos,
            'is_final': isFinal,
            'created_by': AppSession.instance.currentStaffId,
          });
          receiptId = inserted.id!;

          // NOTE the absence of 'receipt_no' here, and do not add it back.
          //
          // `payment_receipt_no_uniq` is a UNIQUE index on
          // payment_entries (org_id, receipt_no). This receipt deliberately
          // consolidates SEVERAL payments onto ONE document, so stamping its
          // number on every entry made the second UPDATE violate that index
          // and the whole generation failed with a 409 - but only ever on an
          // order with two or more unreceipted payments, which is why it
          // survived until a full-cycle test (2 Sep 2026).
          //
          // The link that matters is `receipt_id`, which has no uniqueness
          // constraint; the consolidated number lives on the receipts row
          // itself and is read back through that FK. Any entry that already
          // carries a per-payment acknowledgement number from Quick Payment
          // keeps it, which is correct - that number was shown to the
          // customer at the time and is not this document's number.
          try {
            for (final p in toReceipt) {
              await PaymentEntriesTable().update(
                data: {
                  'receipt_id': receiptId,
                  'is_final_payment': isFinal,
                  if (o.invoiceNo != null) 'invoice_no': o.invoiceNo,
                  if (invoiceDate != null)
                    'invoice_date': invoiceDate.toIso8601String(),
                },
                matchingRows: (q) => OrgScope.write(q).eq('id', p.id),
              );
            }
          } catch (e) {
            // These are separate PostgREST calls with no surrounding
            // transaction, so a failure part-way leaves a receipts row
            // claiming money that nothing is linked to - which is exactly
            // the corrupt state the 409 produced. Undo it and rethrow so
            // _run surfaces the real reason rather than leaving the books
            // inconsistent behind a snackbar.
            try {
              await ReceiptsTable().delete(
                matchingRows: (q) => OrgScope.write(q).eq('id', receiptId),
              );
            } catch (_) {}
            rethrow;
          }
        }

        // Reused from insert above for a new receipt; re-read for a reprint
        // of an existing one.
        final amountInWords = existingReceipt?.amountInWords ??
            await () async {
              try {
                return await SupaFlow.client.rpc('amount_in_words',
                    params: {'amt': amount}) as String?;
              } catch (_) {
                return null;
              }
            }();

        await _showDocDialog(
            'Money Receipt $receiptNo', 'Receipt_$receiptNo.pdf', () async {
          return MoneyReceiptPdf.generate(
            org: org,
            boilerplate: boilerplate,
            receiptNo: receiptNo,
            receiptDate: receiptDate,
            logoBytes: logoBytes,
            signatureBytes: await _fetchBytes(org.signatoryImageUrl),
            receivedFrom: o.customer,
            phone: o.phone,
            invoiceNo: o.invoiceNo,
            invoiceDate: invoiceDate,
            isFinalPayment: isFinal,
            fromPlace: o.fromCity,
            toPlace: o.toCity,
            paymentMode: paymentMode,
            referenceNos: referenceNos,
            amount: amount,
            amountInWords: amountInWords,
          );
        });
        await AuditLogService.log(
          entityType: 'orders',
          entityId: o.id!,
          action: 'document_generated',
          newValue: {
            'doc_type': 'receipt',
            'doc_no': receiptNo,
            'consolidated_entries': toReceipt.map((p) => p.id).toList(),
          },
        );
      });

  // ---- Proforma (doc_type: proforma) -----------------------------------

  Future<void> _genProforma() => _run(() async {
        final o = _order;
        if (o == null) return;
        final orgId = OrgScope.currentOrgId!;
        // One org-wide series per doc type per FY, not per-branch (12 Aug
        // 2026 numbering-scheme decision).
        final docNo = await SupaFlow.client.rpc('next_doc_number', params: {
          'p_org': orgId,
          'p_doc_type': 'proforma',
          'p_branch': null,
          'p_fy': _currentFy(),
        }) as String;
        final amount = o.quoteTotal ?? o.amount ?? 0;
        final (profile, logoBytes) = await _loadBranding();
        await _showDocDialog('Proforma $docNo', 'Proforma_$docNo.pdf',
            () => SimpleDocumentPdf.generate(
                  docLabel: 'PROFORMA INVOICE',
                  docNo: docNo,
                  orgName: AppSession.instance.currentOrgName ?? 'Nagarva',
                  profile: profile,
                  logoBytes: logoBytes,
                  metaLeft: [
                    MapEntry('Prepared For', o.customer),
                    if ((o.phone ?? '').isNotEmpty)
                      MapEntry('Phone', o.phone!),
                    MapEntry('Route',
                        '${o.fromCity ?? '—'} to ${o.toCity ?? '—'}'),
                  ],
                  metaRight: [
                    MapEntry('No', docNo),
                    MapEntry('Date', PdfBranding.fmtDate(DateTime.now())),
                  ],
                  tableHeaders: const ['DESCRIPTION', 'AMOUNT'],
                  tableRows: [
                    ['Estimated moving charges', _rupees(amount)],
                  ],
                  totalLabel: 'ESTIMATED TOTAL',
                  totalValue: _rupees(amount),
                  notesBlock:
                      'This is a preliminary estimate, not a tax invoice. '
                      'Final billed amount may vary based on actuals.',
                ));
        await AuditLogService.log(
          entityType: 'orders',
          entityId: o.id!,
          action: 'document_generated',
          newValue: {'doc_type': 'proforma', 'doc_no': docNo},
        );
      });

  // ---- LR / Bilty (field spec §2 — full rebuild, task #43) --------------

  static const _lrCopyTypes = ['driver', 'consignor', 'consignee', 'transporter'];

  Future<void> _genLr() => _run(() async {
        final o = _order;
        if (o == null) return;
        final orgId = OrgScope.currentOrgId!;
        final fy = _currentFy();

        // Migration 007: next_lr_number(org, branch, fy) is the atomic,
        // row-locked allocator — same contract as next_doc_number, just
        // scoped to lr_series instead of number_series (the two aren't
        // consolidated yet; 007 mirrors the counter into number_series
        // under doc_type 'lr' so a future consolidation is a no-op). One
        // org-wide series per FY, not per-branch — same 12 Aug 2026
        // numbering-scheme decision as every other doc type here.
        final lrNo = await SupaFlow.client.rpc('next_lr_number', params: {
          'p_org': orgId,
          'p_branch': null,
          'p_fy': fy,
        }) as String;

        // Consignee from the linked customer record when available;
        // falls back to the order's own plain fields otherwise.
        String? consigneeName = o.customer;
        String? consigneeAddress = o.toAddress;
        String? consigneeGstin;
        if (o.customerId != null) {
          try {
            final cust = await SupaFlow.client
                .from('customers')
                .select('name,gstin,billing_address')
                .eq('id', o.customerId!)
                .maybeSingle();
            if (cust != null) {
              consigneeName = (cust['name'] as String?) ?? consigneeName;
              consigneeGstin = cust['gstin'] as String?;
              consigneeAddress =
                  (cust['billing_address'] as String?) ?? consigneeAddress;
            }
          } catch (_) {}
        }

        String? ewayId;
        try {
          final eway = await SupaFlow.client
              .from('eway_bills')
              .select('id')
              .eq('order_id', o.id!)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
          ewayId = eway?['id'] as String?;
        } catch (_) {}

        final (org, boilerplate, logoBytes) = await _loadOrgProfile();
        final freight = o.amount ?? 0;

        final inserted = await SupaFlow.client
            .from('lr_register')
            .insert({
              'org_id': orgId,
              'lr_no': lrNo,
              'order_id': o.id,
              if (ewayId != null) 'eway_bill_id': ewayId,
              'consignor_name': org.name,
              'consignor_gstin': org.gstin,
              'consignor_address': org.address ?? '',
              'consignee_name': consigneeName,
              'consignee_gstin': consigneeGstin,
              'consignee_address': consigneeAddress,
              'consignee_phone': o.phone,
              'from_place': o.fromCity,
              'to_place': o.toCity,
              'vehicle_no': o.vehicleNo,
              'driver_name': o.driverName,
              'freight_amount': freight,
              'basic_freight': freight,
              'total_amount': freight,
              'invoice_no': o.invoiceNo,
              'branch': o.branch,
            })
            .select()
            .single();

        final lrId = inserted['id'] as String;
        final gstPayableBy = (inserted['gst_payable_by'] as String?) ?? 'consignor';

        await _showDocDialog(
            'LR $lrNo', 'LR_${lrNo.replaceAll('/', '-')}.pdf', () async {
          return LrPdf.generate(
            org: org,
            boilerplate: boilerplate,
            copyTypes: _lrCopyTypes,
            lrNo: lrNo,
            lrDate: DateTime.now(),
            logoBytes: logoBytes,
            signatureBytes: await _fetchBytes(org.signatoryImageUrl),
            consignorName: org.name,
            consignorGstin: org.gstin,
            consignorAddress: org.address,
            consignorPhone: org.phones.isNotEmpty ? org.phones.first : null,
            consigneeName: consigneeName,
            consigneeGstin: consigneeGstin,
            consigneeAddress: consigneeAddress,
            consigneePhone: o.phone,
            fromPlace: o.fromCity,
            toPlace: o.toCity,
            vehicleNo: o.vehicleNo,
            driverName: o.driverName,
            description: (inserted['description'] as String?),
            packageCount: (inserted['package_count'] as int?) ?? 0,
            actualWeightKg: (inserted['actual_weight_kg'] as num?) ?? 0,
            chargedWeightKg: (inserted['charged_weight_kg'] as num?) ?? 0,
            freightMode: (inserted['freight_mode'] as String?) ?? 'paid',
            freightAmount: freight,
            basicFreight: freight,
            gstPct: 0,
            gstAmount: 0,
            totalAmount: freight,
            invoiceNo: o.invoiceNo,
            gstPayableBy:
                gstPayableBy[0].toUpperCase() + gstPayableBy.substring(1),
          );
        });

        // field spec §2.1: "generate all four ... record each in lr_copies
        // with copy_type/pdf_url." pdf_url stays null — this app never
        // uploads generated PDFs to storage for any document (Invoice/
        // Receipt/etc. are all regenerate-on-demand, not persisted files)
        // and this LR doesn't start that pattern; the row still records
        // that each copy type was generated, which is what the queue/audit
        // trail actually needs.
        try {
          await SupaFlow.client.from('lr_copies').insert(_lrCopyTypes
              .map((ct) => {
                    'org_id': orgId,
                    'lr_id': lrId,
                    'copy_type': ct,
                    'generated_by': AppSession.instance.currentStaffId,
                  })
              .toList());
        } catch (_) {
          // Best-effort tracking row — the PDF itself already generated
          // successfully above; a tracking-insert failure shouldn't be
          // reported as the LR generation having failed.
        }

        await AuditLogService.log(
          entityType: 'orders',
          entityId: o.id!,
          action: 'document_generated',
          newValue: {'doc_type': 'lr', 'lr_no': lrNo, 'copies': _lrCopyTypes},
        );
      });

  // ---- Packing List / Loading Slip (shared item modal) -------------------

  Future<List<String>?> _showItemModal(String title) async {
    final controllers = <TextEditingController>[TextEditingController()];
    return showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < controllers.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: controllers[i],
                        decoration: InputDecoration(
                          labelText: 'Item ${i + 1}',
                          isDense: true,
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setDialogState(
                          () => controllers.add(TextEditingController())),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add item'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(null),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final items = controllers
                    .map((c) => c.text.trim())
                    .where((t) => t.isNotEmpty)
                    .toList();
                Navigator.of(dialogContext).pop(items);
              },
              child: const Text('Generate'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _genPackingList() => _run(() async {
        final o = _order;
        if (o == null) return;
        final items = await _showItemModal('Add all items being packed');
        if (items == null || items.isEmpty) return;
        final (profile, logoBytes) = await _loadBranding();
        await _showDocDialog('Packing List', 'PackingList_${o.id}.pdf',
            () => SimpleDocumentPdf.generate(
                  docLabel: 'PACKING LIST',
                  docNo: o.id!,
                  orgName: AppSession.instance.currentOrgName ?? 'Nagarva',
                  profile: profile,
                  logoBytes: logoBytes,
                  metaLeft: [
                    MapEntry('Customer', o.customer),
                    MapEntry(
                        'Route', '${o.fromCity ?? '—'} to ${o.toCity ?? '—'}'),
                  ],
                  metaRight: [
                    MapEntry('Order Ref', o.id!),
                    MapEntry('Date', PdfBranding.fmtDate(DateTime.now())),
                  ],
                  tableHeaders: const ['#', 'ITEM'],
                  tableRows: [
                    for (var i = 0; i < items.length; i++)
                      ['${i + 1}', items[i]],
                  ],
                ));
      });

  Future<void> _genLoadingSlip() => _run(() async {
        final o = _order;
        if (o == null) return;
        final items = await _showItemModal('Add all items being loaded');
        if (items == null || items.isEmpty) return;
        final (profile, logoBytes) = await _loadBranding();
        await _showDocDialog('Loading Slip', 'LoadingSlip_${o.id}.pdf',
            () => SimpleDocumentPdf.generate(
                  docLabel: 'LOADING SLIP',
                  docNo: o.id!,
                  orgName: AppSession.instance.currentOrgName ?? 'Nagarva',
                  profile: profile,
                  logoBytes: logoBytes,
                  metaLeft: [
                    MapEntry('Customer', o.customer),
                    if ((o.vehicleNo ?? '').isNotEmpty)
                      MapEntry('Vehicle No', o.vehicleNo!),
                    if ((o.driverName ?? '').isNotEmpty)
                      MapEntry('Driver', o.driverName!),
                  ],
                  metaRight: [
                    MapEntry('Order Ref', o.id!),
                    MapEntry('Date', PdfBranding.fmtDate(DateTime.now())),
                  ],
                  tableHeaders: const ['#', 'ITEM'],
                  tableRows: [
                    for (var i = 0; i < items.length; i++)
                      ['${i + 1}', items[i]],
                  ],
                ));
      });

  // ---- Vehicle Condition ---------------------------------------------

  Future<void> _genVehicleCondition() => _run(() async {
        final o = _order;
        if (o == null) return;
        const checklist = [
          'Exterior body / paint',
          'Windshield & glass',
          'Tyres & spare',
          'Interior / seats',
          'Existing dents or scratches',
          'Fuel level',
        ];
        final (profile, logoBytes) = await _loadBranding();
        await _showDocDialog(
            'Vehicle Condition Report',
            'VehicleCondition_${o.id}.pdf',
            () => SimpleDocumentPdf.generate(
                  docLabel: 'VEHICLE CONDITION REPORT',
                  docNo: o.id!,
                  orgName: AppSession.instance.currentOrgName ?? 'Nagarva',
                  profile: profile,
                  logoBytes: logoBytes,
                  metaLeft: [
                    MapEntry('Vehicle No', o.vehicleNo ?? '—'),
                    MapEntry('Driver', o.driverName ?? '—'),
                  ],
                  metaRight: [
                    MapEntry('Order Ref', o.id!),
                    MapEntry('Date', PdfBranding.fmtDate(DateTime.now())),
                  ],
                  tableHeaders: const ['CHECK POINT', 'CONDITION (OK / NOTE)'],
                  tableRows: [
                    for (final c in checklist) [c, ''],
                  ],
                  notesBlock:
                      'To be filled and signed by the driver/supervisor at '
                      'pickup and delivery.',
                ));
      });

  // ---- Payment Voucher (doc_type: voucher) ------------------------------

  /// Proof of Delivery. Generated on demand from `pod_records` — never
  /// stored, so it cannot drift from the record it renders (Arun, 18 Aug
  /// 2026). Lives here with the other seven rather than beside the
  /// delivery data: one place for documents, because "a special location
  /// is how a feature gets built and never found."
  Future<void> _genPod() => _run(() async {
        final o = _order;
        if (o == null) return;
        final bytes = await PodPdf.generateForOrder(o.id!);
        if (bytes == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                    'No delivery record yet — the supervisor completes the '
                    'job to create one.')));
          }
          return;
        }
        await _showDocDialog(
            'Proof of Delivery', 'POD-${o.id}.pdf', () async => bytes);
      });

  Future<void> _genVoucher() => _run(() async {
        final o = _order;
        if (o == null) return;
        final paidToCtrl = TextEditingController();
        final amountCtrl = TextEditingController();
        final purposeCtrl = TextEditingController();
        final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
            title: const Text('Payment Voucher'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: paidToCtrl,
                  decoration: const InputDecoration(labelText: 'Paid To'),
                ),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Amount (₹)'),
                ),
                TextField(
                  controller: purposeCtrl,
                  decoration: const InputDecoration(labelText: 'Purpose'),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Generate')),
            ],
          ),
        );
        if (ok != true) return;
        final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
        if (amount <= 0 || paidToCtrl.text.trim().isEmpty) return;

        final orgId = OrgScope.currentOrgId!;
        // One org-wide series per doc type per FY, not per-branch (12 Aug
        // 2026 numbering-scheme decision).
        final docNo = await SupaFlow.client.rpc('next_doc_number', params: {
          'p_org': orgId,
          'p_doc_type': 'voucher',
          'p_branch': null,
          'p_fy': _currentFy(),
        }) as String;
        final (profile, logoBytes) = await _loadBranding();
        await _showDocDialog('Voucher $docNo', 'Voucher_$docNo.pdf',
            () async {
          return SimpleDocumentPdf.generate(
            docLabel: 'PAYMENT VOUCHER',
            docNo: docNo,
            orgName: AppSession.instance.currentOrgName ?? 'Nagarva',
            profile: profile,
            logoBytes: logoBytes,
            metaLeft: [
              MapEntry('Paid To', paidToCtrl.text.trim()),
              MapEntry('Purpose', purposeCtrl.text.trim().isEmpty
                  ? '—'
                  : purposeCtrl.text.trim()),
              MapEntry('Against Order', o.id!),
            ],
            metaRight: [
              MapEntry('No', docNo),
              MapEntry('Date', PdfBranding.fmtDate(DateTime.now())),
            ],
            totalLabel: 'AMOUNT PAID',
            totalValue: _rupees(amount),
            signatureBytes: _heldSignature,
            signatureLabel: 'Received by',
          );
        });
        await AuditLogService.log(
          entityType: 'orders',
          entityId: o.id!,
          action: 'document_generated',
          newValue: {
            'doc_type': 'voucher',
            'doc_no': docNo,
            'amount': amount,
            'paid_to': paidToCtrl.text.trim(),
          },
        );
      });

  // ---- Utility row ------------------------------------------------------

  // Item 19 Phase 1 (19 Aug 2026): both of these predate the item and
  // each rolled their own `organizations.upi_id` read. They now go
  // through `lib/backend/upi_payment.dart` — one resolver, one link
  // format, one place where the per-tenant VPA rule lives. Extending
  // these was Arun's explicit call over adding a parallel path.
  Future<void> _copyUpi() async {
    try {
      final payee = await resolveOrgUpiPayee();
      if (payee == null || !isPlausibleVpa(payee.vpa)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Set your UPI ID in Settings → Business Profile.')));
        return;
      }
      await Clipboard.setData(ClipboardData(text: payee.vpa));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('UPI ID copied: ${payee.vpa}')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not copy UPI: $e')));
      }
    }
  }

  /// Sends the customer a real `upi://pay` link for the outstanding
  /// balance, not just the VPA as text.
  ///
  /// Before Item 19 this appended "Pay via UPI: <id>" and left the
  /// customer to open their app, pick the payee and type the amount —
  /// three chances to send the wrong sum to the wrong address. The
  /// amount and payee now travel in the link itself.
  Future<void> _sendPayLink() async {
    final o = _order;
    if (o == null) return;
    UpiPayee? payee;
    try {
      payee = await resolveOrgUpiPayee();
    } catch (_) {}

    final balance = (o.amount ?? 0) - (o.advancePaid ?? 0) - o.paidTotal;
    final String message;
    if (payee != null && isPlausibleVpa(payee.vpa) && balance > 0) {
      message = buildUpiRequestMessage(
        orgName: payee.name,
        customerName: o.customer.trim().isEmpty ? 'there' : o.customer,
        orderId: o.id ?? '',
        amount: balance,
        vpa: payee.vpa,
        upiUri: buildUpiUri(
          vpa: payee.vpa,
          payeeName: payee.name,
          amount: balance,
          note: 'Order ${o.id}',
        ),
      );
    } else {
      // No usable UPI ID (or nothing outstanding) — still send the
      // reminder rather than blocking on a setting the vendor may not
      // have filled in yet.
      message = 'Hello ${o.customer}, your balance due for order '
          '${o.id} is ${_rupees(balance)}.';
    }

    try {
      final ok = await launchUrl(
        Uri.parse(buildWhatsAppLink(phone: o.phone, message: message)),
        mode: LaunchMode.externalApplication,
      );
      if (ok) return;
    } catch (_) {
      // Fall through to the clipboard path.
    }
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: message));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not open WhatsApp — message copied instead.')));
  }

  Future<void> _copyTrackLink() async {
    final o = _order;
    if (o == null) return;
    try {
      final token = await TrackingService.tokenForOrder(o.id!);
      if (token == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('This order has no tracking token yet.')));
        return;
      }
      // Reuses the existing token-keyed /track link (same mechanism as the
      // "Share Tracking Link" button above) rather than the brief's literal
      // "{origin}?track={orderId}" shape — that would expose tracking by
      // guessable order id with no token check, a real regression versus
      // the token-based access control already built for this link.
      await Clipboard.setData(ClipboardData(text: buildTokenLink('/track', token)));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Tracking link copied.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not copy link: $e')));
      }
    }
  }

  // ---- Build --------------------------------------------------------

  Widget _docButton(String label, IconData icon, VoidCallback onTap) {
    final theme = FlutterFlowTheme.of(context);
    final isPending = _pendingLabel == label;
    return InkWell(
      onTap: _busy
          ? null
          : () async {
              // Checked HERE, not inside _run: 'Tax Invoice' is wired to
              // widget.onGenerateInvoice and never passes through _run,
              // so a guard there would have skipped the one document that
              // matters most.
              if (!await _confirmUnsigned(label)) return;
              if (!mounted) return;
              setState(() => _pendingLabel = label);
              onTap();
            },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 104,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: theme.primaryBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.alternate),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPending)
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: theme.primary),
              )
            else
              Icon(icon,
                  size: 22,
                  color: _busy ? theme.secondaryText : theme.primary),
            const SizedBox(height: 6),
            Text(isPending ? 'Working…' : label,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: theme.primaryText)),
          ],
        ),
      ),
    );
  }

  Widget _utilityButton(String label, IconData icon, VoidCallback? onTap,
      {Color? color}) {
    final theme = FlutterFlowTheme.of(context);
    final c = color ?? theme.primary;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: c),
      label: Text(label,
          style: GoogleFonts.inter(fontSize: 11.5, color: c)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: c),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final o = _order;
    final paid = o?.paymentStatus == 'paid';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Documents',
              style: GoogleFonts.interTight(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: theme.primaryText)),
          const SizedBox(height: 4),
          if (_heldSignature != null)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: theme.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: theme.success),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '✅ Customer signature captured'
                      '${_heldSignatureAt == null ? '' : ' at ${TimeOfDay.fromDateTime(_heldSignatureAt!).format(context)}'}'
                      ' — will appear on next document',
                      style: GoogleFonts.inter(
                          fontSize: 11.5, color: theme.primaryText),
                    ),
                  ),
                  TextButton(
                    onPressed: _clearHeldSignature,
                    child: const Text('Clear'),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _captureSignature,
                  icon: const Icon(Icons.draw, size: 16),
                  label: const Text('✍️ Capture Signature'),
                ),
              ),
            ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _docButton(
                  'Tax Invoice', Icons.receipt_long, widget.onGenerateInvoice),
              _docButton('Money Receipt', Icons.receipt, _genMoneyReceipt),
              _docButton('Proforma', Icons.description, _genProforma),
              _docButton('LR / Bilty', Icons.local_shipping, _genLr),
              _docButton(
                  'Packing List', Icons.inventory_2, _genPackingList),
              _docButton('Loading Slip', Icons.numbers, _genLoadingSlip),
              _docButton('Vehicle Condition', Icons.directions_car,
                  _genVehicleCondition),
              _docButton(
                  'Payment Voucher', Icons.payments, _genVoucher),
              _docButton(
                  'Proof of Delivery', Icons.assignment_turned_in, _genPod),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!paid)
                _utilityButton('Copy UPI', Icons.content_copy, _copyUpi),
              if (!paid)
                _utilityButton(
                    'Send Pay Link', Icons.send, _sendPayLink),
              // See kTrackLinkHosted — /track is built but unhosted.
              if (kTrackLinkHosted)
                _utilityButton('Copy Track Link', Icons.link, _copyTrackLink),
              // "Duplicate Order", not "Copy". Arun, 3 Sept 2026: "there
              // is copy upi and send paylink then again copy what is that
              // last copy is for". Sitting third in a row whose other two
              // buttons copy things to the CLIPBOARD, a button labelled
              // "Copy" reads as a third clipboard action - when it
              // actually creates a whole new order. The icon said
              // copy_all, which made it worse.
              _utilityButton(
                  'Duplicate Order',
                  Icons.control_point_duplicate,
                  widget.duplicating ? null : widget.onDuplicate,
                  color: const Color(0xFF7C3AED)),
            ],
          ),
        ],
      ),
    );
  }
}
