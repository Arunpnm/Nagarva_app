import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Business tax-invoice PDF (A4) for the packers & movers trade.
///
/// Layout follows the APC invoice template that was the functional spec:
/// navy header band with logo + company identity, bill-to / invoice-meta
/// two-column block, SAC 996719 service table, GST breakdown (IGST for
/// interstate, CGST+SGST split for intrastate), amount-in-words strip,
/// bank + UPI details, and the authorized signatory (drawn e-sign from
/// Settings) above the signature line.
///
/// [profile] is the vendor's business_profile from the settings table —
/// every field is optional and the layout degrades gracefully, so a brand
/// new vendor with an empty Settings page still gets a clean invoice.
///
/// Fonts: Noto Sans via PdfGoogleFonts (fetched once, cached) because the
/// built-in Helvetica has no ₹ glyph.
class InvoicePdf {
  static const _navy = PdfColor.fromInt(0xFF16324F);
  static const _gold = PdfColor.fromInt(0xFFE6A400);
  static const _grey = PdfColor.fromInt(0xFF6B7280);
  static const _lightRow = PdfColor.fromInt(0xFFF3F6FA);

  static Future<Uint8List> generate({
    required String invoiceNo,
    required String customerName,
    String? customerPhone,
    String? fromCity,
    String? toCity,
    required double baseAmount,
    required bool interstate,
    required double igst,
    required double cgst,
    required double sgst,
    required double total,
    required String orgName,
    Map<String, dynamic> profile = const {},
    Uint8List? logoBytes,
    Uint8List? signatureBytes,
    // Customer's e-signature captured via the public /sign link
    // (fix brief #2, item 3). All three are null on an unsigned invoice.
    Uint8List? customerSignatureBytes,
    String? customerSignedByName,
    DateTime? customerSignedAt,
    // Part 8 addendum item 3: true when customerSignatureBytes came from
    // the QUOTE's signature (documentType: 'quote'), not an invoice-
    // specific one — the invoice lookup found nothing and this order's
    // quotation_id was used to fall back. Must never be presented as if
    // signed on the invoice itself; see the provenance line below. Ignored
    // when customerSignatureBytes is null.
    bool signatureInherited = false,
    String? inheritedFromQuoteRef,
  }) async {
    final regular = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();

    String p(String key) => (profile[key] ?? '').toString().trim();
    String rupees(double v) =>
        '₹${v.toStringAsFixed(2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

    final doc = pw.Document();

    pw.Widget kv(String label, String value, {bool boldValue = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                    text: '$label: ',
                    style: pw.TextStyle(
                        font: regular, fontSize: 9, color: _grey)),
                pw.TextSpan(
                    text: value,
                    style: pw.TextStyle(
                        font: boldValue ? bold : regular, fontSize: 9)),
              ],
            ),
          ),
        );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // ---- Header band ------------------------------------------------
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: _navy,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logoBytes != null) ...[
                    pw.Container(
                      width: 52,
                      height: 52,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Image(pw.MemoryImage(logoBytes),
                          fit: pw.BoxFit.contain),
                    ),
                    pw.SizedBox(width: 12),
                  ],
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(orgName.toUpperCase(),
                            style: pw.TextStyle(
                                font: bold,
                                fontSize: 16,
                                color: PdfColors.white)),
                        if (p('tagline').isNotEmpty)
                          pw.Text(p('tagline'),
                              style: pw.TextStyle(
                                  font: regular,
                                  fontSize: 9,
                                  color: _gold)),
                        if (p('address').isNotEmpty)
                          pw.Text(p('address'),
                              style: pw.TextStyle(
                                  font: regular,
                                  fontSize: 8,
                                  color: PdfColors.grey300)),
                        pw.Text(
                          [
                            if (p('phone1').isNotEmpty) 'Ph: ${p('phone1')}',
                            if (p('phone2').isNotEmpty) p('phone2'),
                            if (p('email').isNotEmpty) p('email'),
                          ].join('  |  '),
                          style: pw.TextStyle(
                              font: regular,
                              fontSize: 8,
                              color: PdfColors.grey300),
                        ),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('TAX INVOICE',
                          style: pw.TextStyle(
                              font: bold, fontSize: 13, color: _gold)),
                      if (p('gstin').isNotEmpty)
                        pw.Text('GSTIN: ${p('gstin')}',
                            style: pw.TextStyle(
                                font: regular,
                                fontSize: 8.5,
                                color: PdfColors.white)),
                      if (p('pan').isNotEmpty)
                        pw.Text('PAN: ${p('pan')}',
                            style: pw.TextStyle(
                                font: regular,
                                fontSize: 8.5,
                                color: PdfColors.white)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            // ---- Bill-to + meta --------------------------------------------
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('BILL TO',
                          style: pw.TextStyle(
                              font: bold, fontSize: 9, color: _navy)),
                      pw.SizedBox(height: 3),
                      pw.Text(customerName,
                          style: pw.TextStyle(font: bold, fontSize: 11)),
                      if ((customerPhone ?? '').isNotEmpty)
                        kv('Phone', customerPhone!),
                      kv('Route',
                          '${fromCity ?? '—'}  to  ${toCity ?? '—'}'),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    kv('Invoice No', invoiceNo, boldValue: true),
                    kv('Date',
                        '${DateTime.now().day.toString().padLeft(2, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().year}'),
                    kv('Place of Supply', fromCity ?? '—'),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 14),

            // ---- Service table ---------------------------------------------
            pw.Table(
              columnWidths: {
                0: const pw.FlexColumnWidth(6),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(2),
              },
              border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: _navy),
                  children: [
                    for (final h in ['DESCRIPTION', 'SAC', 'AMOUNT'])
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: pw.Text(h,
                            textAlign: h == 'AMOUNT'
                                ? pw.TextAlign.right
                                : pw.TextAlign.left,
                            style: pw.TextStyle(
                                font: bold,
                                fontSize: 9,
                                color: PdfColors.white)),
                      ),
                  ],
                ),
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: _lightRow),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: pw.Text(
                          'Freight & Moving Services\nOld and used household goods for personal usage only, not for sale',
                          style: pw.TextStyle(font: regular, fontSize: 9)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: pw.Text('996719',
                          style: pw.TextStyle(font: regular, fontSize: 9)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: pw.Text(rupees(baseAmount),
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(font: regular, fontSize: 9)),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),

            // ---- Totals ----------------------------------------------------
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      kv('GST Payable by', 'Consignee'),
                      kv('Reverse Charge', 'No'),
                      kv('Tax Type',
                          interstate ? 'IGST (Interstate)' : 'CGST + SGST (Intrastate)'),
                    ],
                  ),
                ),
                pw.SizedBox(
                  width: 220,
                  child: pw.Column(
                    children: [
                      _totalRow('Taxable Value', rupees(baseAmount),
                          regular, bold),
                      if (interstate)
                        _totalRow('IGST @ 5%', rupees(igst), regular, bold)
                      else ...[
                        _totalRow('CGST @ 2.5%', rupees(cgst), regular, bold),
                        _totalRow('SGST @ 2.5%', rupees(sgst), regular, bold),
                      ],
                      pw.Container(
                        margin: const pw.EdgeInsets.only(top: 4),
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: pw.BoxDecoration(
                          color: _navy,
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Row(
                          mainAxisAlignment:
                              pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('GRAND TOTAL',
                                style: pw.TextStyle(
                                    font: bold,
                                    fontSize: 10,
                                    color: PdfColors.white)),
                            pw.Text(rupees(total),
                                style: pw.TextStyle(
                                    font: bold,
                                    fontSize: 11,
                                    color: _gold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),

            // ---- Bank + signature ------------------------------------------
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: _lightRow,
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('PAYMENT DETAILS',
                            style: pw.TextStyle(
                                font: bold, fontSize: 9, color: _navy)),
                        pw.SizedBox(height: 4),
                        if (p('bank_name').isNotEmpty)
                          kv('Bank', p('bank_name')),
                        if (p('account_no').isNotEmpty)
                          kv('A/c No', p('account_no')),
                        if (p('ifsc').isNotEmpty) kv('IFSC', p('ifsc')),
                        if (p('upi_id').isNotEmpty) kv('UPI', p('upi_id')),
                        if (p('bank_name').isEmpty &&
                            p('upi_id').isEmpty)
                          pw.Text(
                              'Add bank & UPI details in Settings to show them here.',
                              style: pw.TextStyle(
                                  font: regular,
                                  fontSize: 8,
                                  color: _grey)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 24),
                // Customer acceptance block (fix brief #2, item 3; Part 8
                // addendum item 3). Always rendered now — an unsigned
                // invoice used to show nothing here at all, which the
                // addendum's own acceptance test calls out as worse than a
                // visible "Awaiting" line: a blank area on a document sent
                // to a customer reads as an oversight, not a status.
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (customerSignatureBytes != null) ...[
                      pw.Container(
                        height: 42,
                        child: pw.Image(
                            pw.MemoryImage(customerSignatureBytes),
                            fit: pw.BoxFit.contain),
                      ),
                      pw.Container(
                          width: 150, height: .8, color: PdfColors.grey600),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Accepted by ${customerSignedByName ?? 'Customer'}',
                        style: pw.TextStyle(font: bold, fontSize: 8.5),
                      ),
                      if (customerSignedAt != null)
                        pw.Text(
                          _fmtSignedAt(customerSignedAt),
                          style: pw.TextStyle(
                              font: regular, fontSize: 8, color: _grey),
                        ),
                      // Provenance line — an inherited quote signature must
                      // never read as if it were signed on the invoice
                      // itself (Rev B, item 3): quote acceptance and
                      // delivery confirmation are legally different things,
                      // so this is stated, not left implicit.
                      if (signatureInherited)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 2),
                          child: pw.Text(
                            'Signature carried forward from quotation'
                            '${inheritedFromQuoteRef == null ? '' : ' $inheritedFromQuoteRef'}',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                                font: regular,
                                fontSize: 7,
                                fontStyle: pw.FontStyle.italic,
                                color: _grey),
                          ),
                        ),
                    ] else
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 14),
                        child: pw.Text(
                          'Awaiting customer signature',
                          style: pw.TextStyle(
                              font: regular,
                              fontSize: 8.5,
                              fontStyle: pw.FontStyle.italic,
                              color: _grey),
                        ),
                      ),
                  ],
                ),
                pw.SizedBox(width: 24),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (signatureBytes != null)
                      pw.Container(
                        height: 42,
                        child: pw.Image(pw.MemoryImage(signatureBytes),
                            fit: pw.BoxFit.contain),
                      )
                    else
                      pw.SizedBox(height: 42),
                    pw.Container(
                        width: 150, height: .8, color: PdfColors.grey600),
                    pw.SizedBox(height: 3),
                    pw.Text('Authorized Signatory',
                        style: pw.TextStyle(font: regular, fontSize: 8.5)),
                    pw.Text('for $orgName',
                        style: pw.TextStyle(
                            font: regular, fontSize: 8, color: _grey)),
                  ],
                ),
              ],
            ),
            if (p('invoice_terms').isNotEmpty) ...[
              pw.SizedBox(height: 14),
              pw.Text('TERMS & CONDITIONS',
                  style:
                      pw.TextStyle(font: bold, fontSize: 8.5, color: _navy)),
              pw.SizedBox(height: 3),
              ...p('invoice_terms')
                  .split('\n')
                  .where((l) => l.trim().isNotEmpty)
                  .toList()
                  .asMap()
                  .entries
                  .map((e) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 1.5),
                        child: pw.Text(
                          '${e.key + 1}. ${e.value.trim().replaceFirst(RegExp(r'^\d+[.)]\s*'), '')}',
                          style: pw.TextStyle(
                              font: regular, fontSize: 7.5, color: _grey),
                        ),
                      )),
            ],
            pw.Spacer(),
            pw.Divider(color: PdfColors.grey400, thickness: .5),
            pw.Text(
              'This is a computer-generated invoice. '
              'Subject to ${p('address').isNotEmpty ? p('address').split(',').last.trim() : 'local'} jurisdiction. '
              'Generated by Nagarva.',
              textAlign: pw.TextAlign.center,
              style:
                  pw.TextStyle(font: regular, fontSize: 7.5, color: _grey),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  /// Local formatter so this file needs no intl import for one label.
  static String _fmtSignedAt(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final l = dt.toLocal();
    return '${l.day} ${months[l.month - 1]} ${l.year}';
  }

  static pw.Widget _totalRow(
          String label, String value, pw.Font regular, pw.Font bold) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: pw.TextStyle(font: regular, fontSize: 9)),
            pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 9)),
          ],
        ),
      );
}
