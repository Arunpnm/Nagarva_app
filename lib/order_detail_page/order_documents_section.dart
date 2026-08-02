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
import '/components/pdf_branding.dart';
import '/components/signature_pad.dart';
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

  String _currentFy() {
    final now = DateTime.now();
    return now.month >= 4
        ? '${(now.year % 100).toString().padLeft(2, '0')}${((now.year + 1) % 100).toString().padLeft(2, '0')}'
        : '${((now.year - 1) % 100).toString().padLeft(2, '0')}${(now.year % 100).toString().padLeft(2, '0')}';
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
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- Money Receipt (doc_type: receipt) -------------------------------

  Future<void> _genMoneyReceipt() => _run(() async {
        final o = _order;
        if (o == null) return;
        final payments = await PaymentEntriesTable().queryRows(
          queryFn: (q) => OrgScope.read(q)
              .eq('order_id', o.id!)
              .order('created_at', ascending: false),
        );
        if (payments.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No payments recorded for this order yet.')));
          return;
        }
        final latest = payments.first;
        final orgId = OrgScope.currentOrgId!;
        final docNo = await SupaFlow.client.rpc('next_doc_number', params: {
          'p_org': orgId,
          'p_doc_type': 'receipt',
          'p_branch': o.branch,
          'p_fy': _currentFy(),
        }) as String;
        final (profile, logoBytes) = await _loadBranding();
        await _showDocDialog('Money Receipt $docNo', 'Receipt_$docNo.pdf',
            () async {
          return SimpleDocumentPdf.generate(
            docLabel: 'MONEY RECEIPT',
            docNo: docNo,
            orgName: AppSession.instance.currentOrgName ?? 'Nagarva',
            profile: profile,
            logoBytes: logoBytes,
            metaLeft: [
              MapEntry('Received From', o.customer),
              if ((o.phone ?? '').isNotEmpty) MapEntry('Phone', o.phone!),
              MapEntry('Order Ref', o.id!),
            ],
            metaRight: [
              MapEntry('No', docNo),
              MapEntry('Date', PdfBranding.fmtDate(DateTime.now())),
              MapEntry('Mode', latest.mode.toUpperCase()),
            ],
            totalLabel: 'AMOUNT RECEIVED',
            totalValue: _rupees(latest.amount),
            notesBlock: (latest.note ?? '').isEmpty ? null : latest.note,
            signatureBytes: _heldSignature,
            signatureLabel: 'Received by',
          );
        });
        await AuditLogService.log(
          entityType: 'orders',
          entityId: o.id!,
          action: 'document_generated',
          newValue: {'doc_type': 'receipt', 'doc_no': docNo},
        );
      });

  // ---- Proforma (doc_type: proforma) -----------------------------------

  Future<void> _genProforma() => _run(() async {
        final o = _order;
        if (o == null) return;
        final orgId = OrgScope.currentOrgId!;
        final docNo = await SupaFlow.client.rpc('next_doc_number', params: {
          'p_org': orgId,
          'p_doc_type': 'proforma',
          'p_branch': o.branch,
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

  // ---- LR / Bilty --------------------------------------------------------

  Future<void> _genLr() => _run(() async {
        final o = _order;
        if (o == null) return;
        final orgId = OrgScope.currentOrgId!;
        final fy = _currentFy();

        // Migration 007: next_lr_number(org, branch, fy) is the atomic,
        // row-locked allocator — same contract as next_doc_number, just
        // scoped to lr_series instead of number_series (the two aren't
        // consolidated yet; 007 mirrors the counter into number_series
        // under doc_type 'lr' so a future consolidation is a no-op).
        // Replaces the read-then-write this used before 007 landed.
        final lrNo = await SupaFlow.client.rpc('next_lr_number', params: {
          'p_org': orgId,
          'p_branch': o.branch,
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

        final profile = (await _loadBranding()).$1;
        final orgName = AppSession.instance.currentOrgName ?? 'Nagarva';
        final freight = o.amount ?? 0;

        final inserted = await SupaFlow.client
            .from('lr_register')
            .insert({
              'org_id': orgId,
              'lr_no': lrNo,
              'order_id': o.id,
              if (ewayId != null) 'eway_bill_id': ewayId,
              'consignor_name': orgName,
              'consignor_address': profile['address'] ?? '',
              'consignee_name': consigneeName,
              'consignee_gstin': consigneeGstin,
              'consignee_address': consigneeAddress,
              'consignee_phone': o.phone,
              'from_place': o.fromCity,
              'to_place': o.toCity,
              'freight_amount': freight,
              'total_amount': freight,
              'branch': o.branch,
            })
            .select()
            .single();

        final (loadedProfile, logoBytes) = await _loadBranding();
        await _showDocDialog('LR $lrNo', 'LR_${lrNo.replaceAll('/', '-')}.pdf',
            () async {
          return SimpleDocumentPdf.generate(
            docLabel: 'LORRY RECEIPT',
            docNo: lrNo,
            orgName: orgName,
            profile: loadedProfile,
            logoBytes: logoBytes,
            metaLeft: [
              MapEntry('Consignor', orgName),
              MapEntry('Consignee', consigneeName ?? '—'),
              if ((consigneeGstin ?? '').isNotEmpty)
                MapEntry('Consignee GSTIN', consigneeGstin!),
              MapEntry('Delivery Address', consigneeAddress ?? '—'),
            ],
            metaRight: [
              MapEntry('No', lrNo),
              MapEntry('Date', PdfBranding.fmtDate(DateTime.now())),
              MapEntry('From', o.fromCity ?? '—'),
              MapEntry('To', o.toCity ?? '—'),
            ],
            tableHeaders: const ['DESCRIPTION', 'PACKAGES', 'FREIGHT'],
            tableRows: [
              [
                (inserted['description'] as String?) ?? 'Household Goods',
                '${inserted['package_count'] ?? 0}',
                _rupees(freight),
              ],
            ],
            totalLabel: 'FREIGHT TOTAL',
            totalValue: _rupees(freight),
            signatureBytes: _heldSignature,
            signatureLabel: 'Consignee Signature',
          );
        });
        await AuditLogService.log(
          entityType: 'orders',
          entityId: o.id!,
          action: 'document_generated',
          newValue: {'doc_type': 'lr', 'lr_no': lrNo},
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
        final docNo = await SupaFlow.client.rpc('next_doc_number', params: {
          'p_org': orgId,
          'p_doc_type': 'voucher',
          'p_branch': o.branch,
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

  Future<void> _copyUpi() async {
    final orgId = OrgScope.currentOrgId;
    if (orgId == null) return;
    try {
      final rows = await OrganizationsTable().queryRows(
        queryFn: (q) => q.eq('id', orgId),
      );
      final upi = rows.isNotEmpty ? rows.first.upiId : null;
      if (upi == null || upi.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No UPI ID set — add one in Settings.')));
        return;
      }
      await Clipboard.setData(ClipboardData(text: upi));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('UPI ID copied: $upi')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not copy UPI: $e')));
      }
    }
  }

  Future<void> _sendPayLink() async {
    final o = _order;
    if (o == null) return;
    final orgId = OrgScope.currentOrgId;
    String? upi;
    if (orgId != null) {
      try {
        final rows = await OrganizationsTable().queryRows(
          queryFn: (q) => q.eq('id', orgId),
        );
        upi = rows.isNotEmpty ? rows.first.upiId : null;
      } catch (_) {}
    }
    final balance = (o.amount ?? 0) - (o.advancePaid ?? 0) - o.paidTotal;
    final message = 'Hello ${o.customer}, your balance due for order '
        '${o.id} is ${_rupees(balance)}.'
        '${(upi ?? '').isEmpty ? '' : ' Pay via UPI: $upi'}';
    final uri = Uri.parse(buildWhatsAppLink(phone: o.phone, message: message));
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      await Clipboard.setData(ClipboardData(text: message));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open WhatsApp — message copied instead.')));
    }
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
    return InkWell(
      onTap: _busy ? null : onTap,
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
            Icon(icon, size: 22, color: theme.primary),
            const SizedBox(height: 6),
            Text(label,
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
              _utilityButton('Copy Track Link', Icons.link, _copyTrackLink),
              _utilityButton(
                  '⧉ Copy',
                  Icons.copy_all,
                  widget.duplicating ? null : widget.onDuplicate,
                  color: const Color(0xFF7C3AED)),
            ],
          ),
        ],
      ),
    );
  }
}
