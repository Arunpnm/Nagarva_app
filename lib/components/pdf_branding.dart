import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Shared header/footer/branding builder for Nagarva's PDF documents (Part 8
/// addendum, item 2). Extracted from `InvoicePdf` so the new Survey PDF and
/// Quote PDF look consistent with the existing invoice without copy-pasting
/// its layout code — one builder, several document generators on top of it.
///
/// `InvoicePdf` itself is deliberately left untouched here: it already works
/// and is live-tested, and retrofitting it onto this shared builder in the
/// same pass as building two brand-new documents would risk regressing it
/// for no functional gain. A follow-up can fold it in later.
class PdfFonts {
  const PdfFonts({required this.regular, required this.bold});
  final pw.Font regular;
  final pw.Font bold;
}

class PdfBranding {
  static const navy = PdfColor.fromInt(0xFF16324F);
  static const gold = PdfColor.fromInt(0xFFE6A400);
  static const grey = PdfColor.fromInt(0xFF6B7280);
  static const lightRow = PdfColor.fromInt(0xFFF3F6FA);

  /// Noto Sans via PdfGoogleFonts (fetched once, cached) — the built-in
  /// Helvetica has no ₹ glyph. Same choice as InvoicePdf.
  static Future<PdfFonts> loadFonts() async => PdfFonts(
        regular: await PdfGoogleFonts.notoSansRegular(),
        bold: await PdfGoogleFonts.notoSansBold(),
      );

  static Future<Uint8List?> fetchBytes(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) return res.bodyBytes;
    } catch (_) {}
    return null;
  }

  static String rupees(num v) =>
      '₹${v.toStringAsFixed(2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  static String p(Map<String, dynamic> profile, String key) =>
      (profile[key] ?? '').toString().trim();

  /// Navy header band: logo + business identity on the left, a document
  /// label (e.g. "HOUSEHOLD SURVEY" / "QUOTATION") on the right. Degrades
  /// gracefully when [profile]/[logoBytes] are empty, same as InvoicePdf, so
  /// a brand new vendor with an unfilled Settings page still gets a clean
  /// document.
  static pw.Widget headerBand({
    required String orgName,
    required String docLabel,
    required PdfFonts fonts,
    Map<String, dynamic> profile = const {},
    Uint8List? logoBytes,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: navy,
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
              child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 12),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(orgName.toUpperCase(),
                    style: pw.TextStyle(
                        font: fonts.bold, fontSize: 16, color: PdfColors.white)),
                if (p(profile, 'tagline').isNotEmpty)
                  pw.Text(p(profile, 'tagline'),
                      style:
                          pw.TextStyle(font: fonts.regular, fontSize: 9, color: gold)),
                if (p(profile, 'address').isNotEmpty)
                  pw.Text(p(profile, 'address'),
                      style: pw.TextStyle(
                          font: fonts.regular, fontSize: 8, color: PdfColors.grey300)),
                pw.Text(
                  [
                    if (p(profile, 'phone1').isNotEmpty) 'Ph: ${p(profile, 'phone1')}',
                    if (p(profile, 'phone2').isNotEmpty) p(profile, 'phone2'),
                    if (p(profile, 'email').isNotEmpty) p(profile, 'email'),
                  ].join('  |  '),
                  style: pw.TextStyle(
                      font: fonts.regular, fontSize: 8, color: PdfColors.grey300),
                ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(docLabel,
                  style: pw.TextStyle(font: fonts.bold, fontSize: 13, color: gold)),
              if (p(profile, 'gstin').isNotEmpty)
                pw.Text('GSTIN: ${p(profile, 'gstin')}',
                    style: pw.TextStyle(
                        font: fonts.regular, fontSize: 8.5, color: PdfColors.white)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget kv(String label, String value, PdfFonts fonts,
      {bool boldValue = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
                text: '$label: ',
                style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: grey)),
            pw.TextSpan(
                text: value,
                style: pw.TextStyle(
                    font: boldValue ? fonts.bold : fonts.regular, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  static pw.Widget footer(PdfFonts fonts, {String? extraLine}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Divider(color: PdfColors.grey400, thickness: .5),
        if (extraLine != null)
          pw.Text(extraLine,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: fonts.bold, fontSize: 8, color: navy)),
        pw.Text(
          'Generated by Nagarva.',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: fonts.regular, fontSize: 7.5, color: grey),
        ),
      ],
    );
  }

  static String fmtDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final l = dt.toLocal();
    return '${l.day} ${months[l.month - 1]} ${l.year}';
  }

  static String fmtDateTime(DateTime dt) {
    final l = dt.toLocal();
    final h12 = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final ampm = l.hour < 12 ? 'am' : 'pm';
    return '${fmtDate(dt)}, ${h12.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')} $ampm';
  }
}
