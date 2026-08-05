import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_branding.dart';

/// Business tax-invoice PDF (A4) for the packers & movers trade.
///
/// Layout follows the APC invoice template that was the functional spec —
/// see `nagarva_document_field_spec.md` §3 for the full field-by-field diff
/// this file was extended to close (Session 3, Tier 2, task #42): Bill No/
/// LR cross-reference/Delivery Date/Vehicle No, a Bill To block distinct
/// from Move From (billing party can differ from the consignor), package/
/// weight info, HSN/SAC 996719, Payment Remark/Remark, GST Paid By +
/// Reverse Charge YES/NO, Total Freight In Words, and a PAID watermark.
///
/// Branding is [org] (an already-resolved [OrgProfile] — organizations
/// columns first, that same org's `settings.business_profile` jsonb as
/// fallback, see pdf_branding.dart) and [boilerplate] (`app_settings`
/// category 'documents', for the footer). This file used to inline its own
/// header/footer/branding-map lookup (from before [OrgProfile]/
/// [DocumentBoilerplate] existed) — folded onto the shared builder now,
/// per the "follow-up can fold it in later" note that used to sit on
/// PdfBranding.headerBand.
///
/// Fonts: Noto Sans via PdfGoogleFonts (fetched once, cached) because the
/// built-in Helvetica has no ₹ glyph.
class InvoicePdf {
  static Future<Uint8List> generate({
    required String invoiceNo,
    required OrgProfile org,
    required DocumentBoilerplate boilerplate,
    required String customerName,
    String? customerPhone,
    String? fromCity,
    String? toCity,
    String? fromAddress,
    String? toAddress,
    required double baseAmount,
    required bool interstate,
    required double igst,
    required double cgst,
    required double sgst,
    required double total,
    Uint8List? logoBytes,
    Uint8List? signatureBytes,
    // Customer's e-signature captured via the public /sign link
    // (fix brief #2, item 3). All three are null on an unsigned invoice.
    Uint8List? customerSignatureBytes,
    String? customerSignedByName,
    String? customerSignedByPhone,
    DateTime? customerSignedAt,
    // Part 8 addendum item 3: true when customerSignatureBytes came from
    // the QUOTE's signature (documentType: 'quote'), not an invoice-
    // specific one — the invoice lookup found nothing and this order's
    // quotation_id was used to fall back. Must never be presented as if
    // signed on the invoice itself; see the provenance line below. Ignored
    // when customerSignatureBytes is null.
    bool signatureInherited = false,
    String? inheritedFromQuoteRef,
    // ---- Tier A additions (Session 3, field spec §3) ---------------------
    DateTime? billingDate,
    String? lrNo,
    DateTime? deliveryDate,
    String? vehicleNo,
    // Billing party can differ from the consignor (corporate relocation
    // billed to the employer, not the employee) — orders.billing_party_*
    // (migration 009). Falls back to the consignor/customer when null.
    String? billingPartyName,
    String? billingPartyGstin,
    String? billingPartyAddress,
    String? billingPartyPhone,
    int? packageCount,
    num? actualWeightKg,
    num? chargedWeightKg,
    String hsnSacCode = '996719',
    String? paymentRemark,
    String? remark,
    // Same charge heads the quotation shows (kDefaultChargeFields labels),
    // non-zero only — the caller resolves this (quotations.charges when
    // the order has a linked quote, else a single fallback line built from
    // [baseAmount]) so this file stays a pure renderer.
    List<MapEntry<String, num>> particulars = const [],
    // No dedicated orders column exists for this (field spec §3: "GST Paid
    // By — [SCHEMA GAP]") — the caller resolves it from the linked
    // lr_register row's gst_payable_by when one exists. Null renders the
    // same "Consignee" default this file has always shown.
    String? gstPayableBy,
    bool reverseCharge = false,
    // Total (freight) in words — via the DB's amount_in_words() RPC, never
    // reimplemented in Dart (Indian lakh/crore numbering has enough edge
    // cases that duplicating it client-side would drift). Null just omits
    // the strip rather than guessing.
    String? amountInWords,
    // Diagonal green semi-transparent stamp when the order is settled.
    bool isPaid = false,
  }) async {
    final fonts = await PdfBranding.loadFonts();
    final billedOn = billingDate ?? DateTime.now();

    final doc = pw.Document();

    pw.Widget kv(String label, String value, {bool boldValue = false}) =>
        PdfBranding.kv(label, value, fonts, boldValue: boldValue);

    final resolvedBillToName =
        (billingPartyName ?? '').trim().isNotEmpty ? billingPartyName! : customerName;
    final resolvedBillToGstin = billingPartyGstin;
    final resolvedBillToAddress = billingPartyAddress;
    final resolvedBillToPhone =
        (billingPartyPhone ?? '').trim().isNotEmpty ? billingPartyPhone : customerPhone;

    final particularsRows = particulars.isNotEmpty
        ? particulars
        : [MapEntry('Freight & Moving Services', baseAmount)];

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        build: (ctx) => pw.Stack(
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // ---- Header ----------------------------------------------
                PdfBranding.headerFull(
                  org: org,
                  docLabel: 'BILL (TAX INVOICE)',
                  fonts: fonts,
                  logoBytes: logoBytes,
                ),
                pw.SizedBox(height: 14),

                // ---- Bill To / Move From-To + invoice meta --------------
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('BILL TO',
                              style: pw.TextStyle(
                                  font: fonts.bold,
                                  fontSize: 9,
                                  color: PdfBranding.navy)),
                          pw.SizedBox(height: 3),
                          pw.Text(resolvedBillToName,
                              style:
                                  pw.TextStyle(font: fonts.bold, fontSize: 11)),
                          if ((resolvedBillToPhone ?? '').isNotEmpty)
                            kv('Phone', resolvedBillToPhone!),
                          if ((resolvedBillToGstin ?? '').isNotEmpty)
                            kv('GSTIN', resolvedBillToGstin!),
                          if ((resolvedBillToAddress ?? '').isNotEmpty)
                            kv('Address', resolvedBillToAddress!),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 14),
                    pw.Expanded(
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text('MOVE FROM',
                                    style: pw.TextStyle(
                                        font: fonts.bold,
                                        fontSize: 8.5,
                                        color: PdfBranding.navy)),
                                pw.Text(fromAddress ?? fromCity ?? '—',
                                    style: pw.TextStyle(
                                        font: fonts.regular, fontSize: 8.5)),
                              ],
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text('MOVE TO',
                                    style: pw.TextStyle(
                                        font: fonts.bold,
                                        fontSize: 8.5,
                                        color: PdfBranding.navy)),
                                pw.Text(toAddress ?? toCity ?? '—',
                                    style: pw.TextStyle(
                                        font: fonts.regular, fontSize: 8.5)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 14),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        kv('Bill No', invoiceNo, boldValue: true),
                        kv('Billing Date', PdfBranding.fmtDate(billedOn)),
                        if ((lrNo ?? '').isNotEmpty) kv('LR No', lrNo!),
                        if (deliveryDate != null)
                          kv('Delivery Date', PdfBranding.fmtDate(deliveryDate)),
                        if ((vehicleNo ?? '').isNotEmpty)
                          kv('Vehicle No', vehicleNo!),
                        kv('Place of Supply', fromCity ?? '—'),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),

                // ---- Package / weight / HSN info row ---------------------
                pw.Wrap(
                  spacing: 16,
                  runSpacing: 2,
                  children: [
                    if (packageCount != null)
                      kv('Packages', '$packageCount'),
                    if (actualWeightKg != null)
                      kv('Actual Weight', '${actualWeightKg} Kg'),
                    if (chargedWeightKg != null)
                      kv('Charged Weight', '${chargedWeightKg} Kg'),
                    kv('HSN/SAC', hsnSacCode),
                  ],
                ),
                pw.SizedBox(height: 10),

                // ---- Particulars table ------------------------------------
                pw.Table(
                  columnWidths: {
                    0: const pw.FlexColumnWidth(6),
                    1: const pw.FlexColumnWidth(2),
                    2: const pw.FlexColumnWidth(2),
                  },
                  border:
                      pw.TableBorder.all(color: PdfColors.grey400, width: .5),
                  children: [
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfBranding.navy),
                      children: [
                        for (final h in ['PARTICULARS', 'SAC', 'AMOUNT'])
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            child: pw.Text(h,
                                textAlign: h == 'AMOUNT'
                                    ? pw.TextAlign.right
                                    : pw.TextAlign.left,
                                style: pw.TextStyle(
                                    font: fonts.bold,
                                    fontSize: 9,
                                    color: PdfColors.white)),
                          ),
                      ],
                    ),
                    for (var i = 0; i < particularsRows.length; i++)
                      pw.TableRow(
                        decoration: pw.BoxDecoration(
                            color: i.isOdd
                                ? PdfBranding.lightRow
                                : PdfColors.white),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            child: pw.Text(particularsRows[i].key,
                                style:
                                    pw.TextStyle(font: fonts.regular, fontSize: 9)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            child: pw.Text(hsnSacCode,
                                style:
                                    pw.TextStyle(font: fonts.regular, fontSize: 9)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            child: pw.Text(
                                PdfBranding.rupees(particularsRows[i].value),
                                textAlign: pw.TextAlign.right,
                                style:
                                    pw.TextStyle(font: fonts.regular, fontSize: 9)),
                          ),
                        ],
                      ),
                  ],
                ),
                pw.SizedBox(height: 8),
                if ((paymentRemark ?? '').isNotEmpty)
                  kv('Payment Remark', paymentRemark!),
                if ((remark ?? '').isNotEmpty) kv('Remark', remark!),
                pw.SizedBox(height: 10),

                // ---- Totals ------------------------------------------------
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          kv('GST Payable by', gstPayableBy ?? 'Consignee'),
                          kv('Reverse Charge', reverseCharge ? 'YES' : 'NO'),
                          kv(
                              'Tax Type',
                              interstate
                                  ? 'IGST (Interstate)'
                                  : 'CGST + SGST (Intrastate)'),
                        ],
                      ),
                    ),
                    pw.SizedBox(
                      width: 220,
                      child: pw.Column(
                        children: [
                          _totalRow('Taxable Value', PdfBranding.rupees(baseAmount),
                              fonts.regular, fonts.bold),
                          if (interstate)
                            _totalRow('IGST @ 5%', PdfBranding.rupees(igst),
                                fonts.regular, fonts.bold)
                          else ...[
                            _totalRow('CGST @ 2.5%', PdfBranding.rupees(cgst),
                                fonts.regular, fonts.bold),
                            _totalRow('SGST @ 2.5%', PdfBranding.rupees(sgst),
                                fonts.regular, fonts.bold),
                          ],
                          pw.Container(
                            margin: const pw.EdgeInsets.only(top: 4),
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            decoration: pw.BoxDecoration(
                              color: PdfBranding.navy,
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                            child: pw.Row(
                              mainAxisAlignment:
                                  pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text('GRAND TOTAL',
                                    style: pw.TextStyle(
                                        font: fonts.bold,
                                        fontSize: 10,
                                        color: PdfColors.white)),
                                pw.Text(PdfBranding.rupees(total),
                                    style: pw.TextStyle(
                                        font: fonts.bold,
                                        fontSize: 11,
                                        color: PdfBranding.gold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if ((amountInWords ?? '').isNotEmpty) ...[
                  pw.SizedBox(height: 8),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: PdfBranding.lightRow,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.RichText(
                      text: pw.TextSpan(children: [
                        pw.TextSpan(
                            text: 'Total Freight In Words: ',
                            style: pw.TextStyle(
                                font: fonts.bold,
                                fontSize: 8.5,
                                color: PdfBranding.navy)),
                        pw.TextSpan(
                            text: amountInWords,
                            style:
                                pw.TextStyle(font: fonts.regular, fontSize: 8.5)),
                      ]),
                    ),
                  ),
                ],
                pw.SizedBox(height: 16),

                // ---- Bank + signature ------------------------------------
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Expanded(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(10),
                        decoration: pw.BoxDecoration(
                          color: PdfBranding.lightRow,
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('PAYMENT DETAILS',
                                style: pw.TextStyle(
                                    font: fonts.bold,
                                    fontSize: 9,
                                    color: PdfBranding.navy)),
                            pw.SizedBox(height: 4),
                            if ((org.beneficiaryName ?? '').isNotEmpty)
                              kv('Beneficiary', org.beneficiaryName!),
                            if ((org.bankName ?? '').isNotEmpty)
                              kv('Bank', org.bankName!),
                            if ((org.bankAccountNo ?? '').isNotEmpty)
                              kv('A/c No', org.bankAccountNo!),
                            if ((org.bankIfsc ?? '').isNotEmpty)
                              kv('IFSC', org.bankIfsc!),
                            if ((org.upiId ?? '').isNotEmpty)
                              kv('UPI', org.upiId!),
                            if ((org.upiDisplayNumber ?? '').isNotEmpty)
                              kv('PhonePe/GPay', org.upiDisplayNumber!),
                            if ((org.bankName ?? '').isEmpty &&
                                (org.upiId ?? '').isEmpty)
                              pw.Text(
                                  'Add bank & UPI details in Settings to show them here.',
                                  style: pw.TextStyle(
                                      font: fonts.regular,
                                      fontSize: 8,
                                      color: PdfBranding.grey)),
                          ],
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 24),
                    // Customer acceptance block (fix brief #2, item 3; Part 8
                    // addendum item 3; field spec §3: name + phone + date/
                    // time). Always rendered — an unsigned invoice used to
                    // show nothing here at all, which reads as an oversight
                    // on a document sent to a customer, not a status.
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
                            style: pw.TextStyle(font: fonts.bold, fontSize: 8.5),
                          ),
                          if ((customerSignedByPhone ?? '').isNotEmpty)
                            pw.Text(
                              customerSignedByPhone!,
                              style: pw.TextStyle(
                                  font: fonts.regular,
                                  fontSize: 7.5,
                                  color: PdfBranding.grey),
                            ),
                          if (customerSignedAt != null)
                            pw.Text(
                              PdfBranding.fmtDateTime(customerSignedAt),
                              style: pw.TextStyle(
                                  font: fonts.regular,
                                  fontSize: 8,
                                  color: PdfBranding.grey),
                            ),
                          // Provenance line — an inherited quote signature
                          // must never read as if it were signed on the
                          // invoice itself (Rev B, item 3): quote acceptance
                          // and delivery confirmation are legally different
                          // things, so this is stated, not left implicit.
                          if (signatureInherited)
                            pw.Padding(
                              padding: const pw.EdgeInsets.only(top: 2),
                              child: pw.Text(
                                'Signature carried forward from quotation'
                                '${inheritedFromQuoteRef == null ? '' : ' $inheritedFromQuoteRef'}',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                    font: fonts.regular,
                                    fontSize: 7,
                                    fontStyle: pw.FontStyle.italic,
                                    color: PdfBranding.grey),
                              ),
                            ),
                        ] else
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(vertical: 14),
                            child: pw.Text(
                              'Awaiting customer signature',
                              style: pw.TextStyle(
                                  font: fonts.regular,
                                  fontSize: 8.5,
                                  fontStyle: pw.FontStyle.italic,
                                  color: PdfBranding.grey),
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
                        pw.Text(
                            (org.signatoryName ?? '').isNotEmpty
                                ? org.signatoryName!
                                : 'Authorized Signatory',
                            style:
                                pw.TextStyle(font: fonts.regular, fontSize: 8.5)),
                        pw.Text('for ${org.name}',
                            style: pw.TextStyle(
                                font: fonts.regular,
                                fontSize: 8,
                                color: PdfBranding.grey)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 14),
                pw.Text('NOTE',
                    style: pw.TextStyle(
                        font: fonts.bold, fontSize: 8.5, color: PdfBranding.navy)),
                pw.SizedBox(height: 3),
                pw.Text(boilerplate.invoiceNote,
                    style: pw.TextStyle(
                        font: fonts.regular, fontSize: 7.5, color: PdfBranding.grey)),
                pw.Spacer(),
                PdfBranding.footerFull(fonts, org: org, boilerplate: boilerplate),
              ],
            ),
            if (isPaid)
              pw.Positioned.fill(
                child: pw.Center(
                  child: pw.Transform.rotate(
                    angle: 0.5,
                    child: pw.Opacity(
                      opacity: 0.28,
                      child: pw.Text(
                        'PAID',
                        style: pw.TextStyle(
                          font: fonts.bold,
                          fontSize: 96,
                          color: PdfColors.green700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return doc.save();
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
