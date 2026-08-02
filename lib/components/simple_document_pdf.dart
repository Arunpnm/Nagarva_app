import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_branding.dart';

/// Generic single-page A4 document — Order Details Session 1, item 4.
///
/// Six of the eight documents in the grid (Money Receipt, Proforma, LR/
/// Bilty, Packing List, Loading Slip, Vehicle Condition, Payment Voucher —
/// everything except the already-existing bespoke Tax Invoice) share the
/// same real shape: a branded header, an order/party meta block, an
/// optional line-items table, an optional total, and an optional signature
/// block. Building seven near-identical bespoke layouts would just be the
/// same document copy-pasted with different labels, so this is one
/// generator parameterised by content, built on PdfBranding's shared
/// header/kv/footer primitives (the same ones the Tax Invoice itself pulled
/// out of, and the Survey/Quote PDFs already use).
class SimpleDocumentPdf {
  static Future<Uint8List> generate({
    required String docLabel,
    required String docNo,
    required String orgName,
    Map<String, dynamic> profile = const {},
    Uint8List? logoBytes,
    List<MapEntry<String, String>> metaLeft = const [],
    List<MapEntry<String, String>> metaRight = const [],
    List<String> tableHeaders = const [],
    List<List<String>> tableRows = const [],
    String? totalLabel,
    String? totalValue,
    Uint8List? signatureBytes,
    String signatureLabel = 'Customer Signature',
    String? notesBlock,
    String? footerNote,
  }) async {
    final fonts = await PdfBranding.loadFonts();
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            PdfBranding.headerBand(
              orgName: orgName,
              docLabel: docLabel,
              fonts: fonts,
              profile: profile,
              logoBytes: logoBytes,
            ),
            pw.SizedBox(height: 14),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      for (final e in metaLeft)
                        PdfBranding.kv(e.key, e.value, fonts,
                            boldValue: metaLeft.first == e),
                    ],
                  ),
                ),
                if (metaRight.isNotEmpty)
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      for (final e in metaRight)
                        PdfBranding.kv(e.key, e.value, fonts,
                            boldValue: e.key == 'No'),
                    ],
                  ),
              ],
            ),
            if (tableHeaders.isNotEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Table(
                border:
                    pw.TableBorder.all(color: PdfColors.grey400, width: .5),
                columnWidths: {
                  for (var i = 0; i < tableHeaders.length; i++)
                    i: i == 0
                        ? const pw.FlexColumnWidth(4)
                        : const pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    decoration:
                        const pw.BoxDecoration(color: PdfBranding.navy),
                    children: [
                      for (var i = 0; i < tableHeaders.length; i++)
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          child: pw.Text(tableHeaders[i],
                              textAlign: i == 0
                                  ? pw.TextAlign.left
                                  : pw.TextAlign.right,
                              style: pw.TextStyle(
                                  font: fonts.bold,
                                  fontSize: 9,
                                  color: PdfColors.white)),
                        ),
                    ],
                  ),
                  for (var r = 0; r < tableRows.length; r++)
                    pw.TableRow(
                      decoration: pw.BoxDecoration(
                          color:
                              r.isOdd ? PdfBranding.lightRow : PdfColors.white),
                      children: [
                        for (var i = 0; i < tableRows[r].length; i++)
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            child: pw.Text(tableRows[r][i],
                                textAlign: i == 0
                                    ? pw.TextAlign.left
                                    : pw.TextAlign.right,
                                style:
                                    pw.TextStyle(font: fonts.regular, fontSize: 9)),
                          ),
                      ],
                    ),
                ],
              ),
            ],
            if (totalLabel != null && totalValue != null) ...[
              pw.SizedBox(height: 10),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  width: 220,
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: PdfBranding.navy,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(totalLabel,
                          style: pw.TextStyle(
                              font: fonts.bold,
                              fontSize: 10,
                              color: PdfColors.white)),
                      pw.Text(totalValue,
                          style: pw.TextStyle(
                              font: fonts.bold,
                              fontSize: 11,
                              color: PdfBranding.gold)),
                    ],
                  ),
                ),
              ),
            ],
            if (notesBlock != null && notesBlock.trim().isNotEmpty) ...[
              pw.SizedBox(height: 14),
              pw.Text('NOTES',
                  style: pw.TextStyle(
                      font: fonts.bold, fontSize: 8.5, color: PdfBranding.navy)),
              pw.SizedBox(height: 3),
              pw.Text(notesBlock,
                  style: pw.TextStyle(font: fonts.regular, fontSize: 8.5)),
            ],
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
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
                    pw.Text(signatureLabel,
                        style: pw.TextStyle(font: fonts.regular, fontSize: 8.5)),
                  ],
                ),
              ],
            ),
            pw.Spacer(),
            PdfBranding.footer(fonts, extraLine: footerNote),
          ],
        ),
      ),
    );

    return doc.save();
  }
}
