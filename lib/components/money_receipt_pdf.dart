import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_branding.dart';

/// Money Receipt (A4) — Session 3, task #45. Field spec §4: the simplest
/// of the four documents and closest to complete at kickoff. Supports
/// consolidated receipts (one receipt covering several `payment_entries`,
/// same as APC's own receipts showing up to three UPI transaction ids on
/// one document) — the caller resolves which entries to consolidate and
/// passes their reference numbers already joined.
class MoneyReceiptPdf {
  static Future<Uint8List> generate({
    required OrgProfile org,
    required DocumentBoilerplate boilerplate,
    required String receiptNo,
    required DateTime receiptDate,
    Uint8List? logoBytes,
    Uint8List? signatureBytes,
    required String receivedFrom,
    String? phone,
    String? invoiceNo,
    DateTime? invoiceDate,
    required bool isFinalPayment,
    String? fromPlace,
    String? toPlace,
    required String paymentMode,
    String? referenceNos,
    required num amount,
    String? amountInWords,
  }) async {
    final fonts = await PdfBranding.loadFonts();
    final doc = pw.Document();

    pw.Widget kv(String label, String value, {bool boldValue = false}) =>
        PdfBranding.kv(label, value, fonts, boldValue: boldValue);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            PdfBranding.headerFull(
              org: org,
              docLabel: 'MONEY RECEIPT',
              fonts: fonts,
              logoBytes: logoBytes,
              showBranchList: true,
            ),
            pw.SizedBox(height: 16),
            pw.Center(
              child: pw.Text('MONEY RECEIPT',
                  style: pw.TextStyle(
                      font: fonts.bold, fontSize: 15, color: PdfBranding.navy)),
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                kv('Receipt No', receiptNo, boldValue: true),
                kv('Date', PdfBranding.fmtDate(receiptDate)),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.RichText(
              text: pw.TextSpan(children: [
                pw.TextSpan(
                    text: 'Received with thanks from M/s. ',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10)),
                pw.TextSpan(
                    text: receivedFrom,
                    style: pw.TextStyle(font: fonts.bold, fontSize: 10)),
              ]),
            ),
            if ((phone ?? '').isNotEmpty) kv('Phone No', phone!),
            pw.SizedBox(height: 6),
            pw.RichText(
              text: pw.TextSpan(children: [
                pw.TextSpan(
                    text: isFinalPayment
                        ? 'Towards Final Payment of Bill No. '
                        : 'Towards Part Payment of Bill No. ',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 9.5)),
                pw.TextSpan(
                    text: (invoiceNo ?? '').isEmpty ? '—' : invoiceNo,
                    style: pw.TextStyle(font: fonts.bold, fontSize: 9.5)),
                if (invoiceDate != null)
                  pw.TextSpan(
                      text: ' Dated ${PdfBranding.fmtDate(invoiceDate)}',
                      style: pw.TextStyle(font: fonts.regular, fontSize: 9.5)),
              ]),
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                pw.Expanded(child: kv('From', fromPlace ?? '—')),
                pw.Expanded(child: kv('To', toPlace ?? '—')),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.RichText(
              text: pw.TextSpan(children: [
                pw.TextSpan(
                    text: 'Received as per details by ',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 9.5)),
                pw.TextSpan(
                    text: paymentMode.toUpperCase(),
                    style: pw.TextStyle(font: fonts.bold, fontSize: 9.5)),
                if ((referenceNos ?? '').isNotEmpty) ...[
                  pw.TextSpan(
                      text: ' No. ',
                      style: pw.TextStyle(font: fonts.regular, fontSize: 9.5)),
                  pw.TextSpan(
                      text: referenceNos,
                      style: pw.TextStyle(font: fonts.bold, fontSize: 9.5)),
                ],
              ]),
            ),
            pw.SizedBox(height: 16),
            if ((amountInWords ?? '').isNotEmpty)
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: pw.BoxDecoration(
                  color: PdfBranding.lightRow,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.RichText(
                  text: pw.TextSpan(children: [
                    pw.TextSpan(
                        text: 'Amount in Words: ',
                        style: pw.TextStyle(
                            font: fonts.bold, fontSize: 9, color: PdfBranding.navy)),
                    pw.TextSpan(
                        text: amountInWords,
                        style: pw.TextStyle(font: fonts.regular, fontSize: 9)),
                  ]),
                ),
              ),
            pw.SizedBox(height: 14),
            pw.Center(
              child: pw.Text('Rs. ${amount.toStringAsFixed(2)}/-',
                  style: pw.TextStyle(
                      font: fonts.bold, fontSize: 22, color: PdfBranding.navy)),
            ),
            pw.SizedBox(height: 24),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (signatureBytes != null)
                      pw.Container(
                        height: 40,
                        child: pw.Image(pw.MemoryImage(signatureBytes),
                            fit: pw.BoxFit.contain),
                      )
                    else
                      pw.SizedBox(height: 40),
                    pw.Container(width: 150, height: .8, color: PdfColors.grey600),
                    pw.SizedBox(height: 3),
                    pw.Text(
                        (org.signatoryName ?? '').isNotEmpty
                            ? org.signatoryName!
                            : 'Authorised Signatory',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 8.5)),
                    pw.Text('for ${org.name}',
                        style: pw.TextStyle(
                            font: fonts.regular, fontSize: 8, color: PdfBranding.grey)),
                  ],
                ),
              ],
            ),
            pw.Spacer(),
            PdfBranding.footerFull(fonts, org: org, boilerplate: boilerplate),
          ],
        ),
      ),
    );

    return doc.save();
  }
}
