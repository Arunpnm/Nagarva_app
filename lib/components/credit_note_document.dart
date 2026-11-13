import 'dart:typed_data';

import 'package:flutter/material.dart';

import '/app_session.dart';
import '/backend/detail_navigation.dart';
import '/backend/edge_function_errors.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/backend/vendor_identity.dart';
import '/components/pdf_actions_sheet.dart';
import '/components/pdf_branding.dart';
import '/components/simple_document_pdf.dart';
import '/flutter_flow/ng_tokens.dart';

/// The printable credit note (13 Nov 2026). Credit notes were recorded
/// and numbered but had no document: nothing to hand the customer when an
/// invoice is reduced or money is refunded. Arun, checking the document
/// list: "I want all".
///
/// Prints exactly what the `credit_notes` row holds. The taxable value
/// and GST lines show only when the row has them; nothing is worked out
/// here, so the paper can never disagree with the register.
class CreditNoteDocument {
  CreditNoteDocument._();

  static String _rupees(num v) => '₹${v.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  static Future<(Uint8List, String)> build(Map<String, dynamic> r) async {
    Map<String, dynamic> profile = const {};
    try {
      final rows = await SettingsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('key', 'business_profile'),
      );
      profile = rows.isEmpty ? {} : (rows.first.valueJson ?? {});
    } catch (_) {}
    final logo =
        await PdfBranding.fetchBytes(AppSession.instance.currentOrgLogoUrl);

    // The customer comes from the order the note is against, when there
    // is one. A note with no order prints without a customer block.
    String? customer;
    String? phone;
    final orderId = '${r['order_id'] ?? ''}'.trim();
    if (orderId.isNotEmpty) {
      try {
        final rows = await OrdersTable()
            .queryRows(queryFn: (q) => OrgScope.read(q).eq('id', orderId));
        if (rows.isNotEmpty) {
          customer = rows.first.customer;
          phone = rows.first.phone;
        }
      } catch (_) {}
    }

    final no = '${r['note_no'] ?? ''}'.trim();
    final refund = r['note_type'] == 'refund';
    final date = DateTime.tryParse('${r['note_date'] ?? ''}') ?? DateTime.now();
    final total = _num(r['total_amount']);
    final taxable = _num(r['taxable_amount']);
    final gst = _num(r['gst_amount']);
    final pct = _num(r['gst_pct']);
    final invoice = '${r['original_invoice_no'] ?? ''}'.trim();
    final reason = '${r['reason'] ?? ''}'.trim();

    final bytes = await SimpleDocumentPdf.generate(
      docLabel: 'CREDIT NOTE',
      docNo: no.isEmpty ? '-' : no,
      orgName: VendorIdentity.forDocument,
      profile: profile,
      logoBytes: logo,
      metaLeft: [
        if ((customer ?? '').isNotEmpty) MapEntry('Issued To', customer!),
        if ((phone ?? '').isNotEmpty) MapEntry('Phone', phone!),
        if (invoice.isNotEmpty) MapEntry('Against Invoice', invoice),
        if (orderId.isNotEmpty) MapEntry('Order Ref', orderId),
      ],
      metaRight: [
        MapEntry('No', no.isEmpty ? '-' : no),
        MapEntry('Date', PdfBranding.fmtDate(date)),
        MapEntry('Type', refund ? 'Refund' : 'Invoice reduced'),
      ],
      tableHeaders: const ['DESCRIPTION', 'AMOUNT'],
      tableRows: [
        if (taxable > 0) ...[
          [reason.isEmpty ? 'Credit' : reason, _rupees(taxable)],
          if (gst > 0)
            ['GST${pct > 0 ? ' @ ${pct.toStringAsFixed(pct % 1 == 0 ? 0 : 2)}%' : ''}', _rupees(gst)],
        ] else
          [reason.isEmpty ? 'Credit' : reason, _rupees(total)],
      ],
      totalLabel: refund ? 'AMOUNT REFUNDED' : 'AMOUNT CREDITED',
      totalValue: _rupees(total),
      signatureLabel: 'Authorised Signatory',
      notesBlock: refund
          ? 'This amount has been refunded to the customer against the '
              'invoice named above.'
          : 'The invoice named above is reduced by this amount.',
    );
    final safe = (no.isEmpty ? 'draft' : no)
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
    return (bytes, 'CreditNote_$safe.pdf');
  }

  /// Tapping a credit note: its document, or the order it is against.
  static Future<void> showActions(
      BuildContext context, Map<String, dynamic> r) {
    final orderId = '${r['order_id'] ?? ''}'.trim();
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: NgPalette.of(context).s1,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheet) {
        final c = NgPalette.of(sheet);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.picture_as_pdf_outlined, color: c.acc),
                title: Text('Credit note PDF',
                    style: NgFonts.geist(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.text)),
                subtitle: Text('View, share or print',
                    style: NgFonts.geist(fontSize: 12.5, color: c.mute)),
                onTap: () async {
                  Navigator.of(sheet).pop();
                  try {
                    final (bytes, file) = await build(r);
                    if (!context.mounted) return;
                    await PdfActionsSheet.show(context,
                        title: 'Credit note', filename: file, bytes: bytes);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            'Could not make the credit note: ${friendlyError(e)}')));
                  }
                },
              ),
              if (orderId.isNotEmpty)
                ListTile(
                  leading: Icon(Icons.assignment_outlined, color: c.mute),
                  title: Text('Open the order',
                      style: NgFonts.geist(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.text)),
                  subtitle: Text(orderId,
                      style: NgFonts.mono(fontSize: 12.5, color: c.mute)),
                  onTap: () {
                    Navigator.of(sheet).pop();
                    openOrderJourneyById(context, orderId);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
