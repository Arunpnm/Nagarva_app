import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '/backend/pricing_defaults.dart';
import '/components/pdf_branding.dart';
import '/components/survey_response_section.dart' show SurveyLine, groupSurveyLines, surveyTotalCft;

/// Household Survey PDF (Part 8 addendum, item 2 — survey half).
///
/// Reuses `parseSurveyRooms`/`groupSurveyLines`/`surveyTotalCft` from
/// survey_response_section.dart rather than re-deriving the grouping, and
/// `packageInfoForCft` from pricing_defaults.dart for the suggested-package
/// footer line — same helpers the in-app survey card already uses, so the
/// PDF can never disagree with what the vendor sees on screen.
///
/// Deliberately separate from [QuotePdf] (Rev B, Q2): the survey goes to the
/// customer before pricing exists, so it cannot depend on a quote — this
/// generator only ever needs `surveys.rooms`, never `quotations`.
class SurveyPdf {
  static Future<Uint8List> generate({
    required String leadRef,
    required String customerName,
    String? customerPhone,
    DateTime? moveDate,
    String? fromAddress,
    String? toAddress,
    String? fromCity,
    String? toCity,
    required List<SurveyLine> lines,
    required String orgName,
    Map<String, dynamic> profile = const {},
    Uint8List? logoBytes,
    List<CftRange> cftRanges = kDefaultCftRanges,
    List<PackageInfo> packages = kDefaultPackages,
  }) async {
    final fonts = await PdfBranding.loadFonts();
    final grouped = groupSurveyLines(lines);
    final totalCft = surveyTotalCft(lines);
    final totalItems = lines.fold<int>(0, (s, l) => s + l.qty);
    final pkg = totalCft <= 0
        ? null
        : packageInfoForCft(totalCft, cftRanges, packages);

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 14),
                child: PdfBranding.headerBand(
                  orgName: orgName,
                  docLabel: 'HOUSEHOLD SURVEY',
                  fonts: fonts,
                  profile: profile,
                  logoBytes: logoBytes,
                ),
              )
            : pw.SizedBox(),
        footer: (ctx) => PdfBranding.footer(fonts),
        build: (ctx) => [
          // ---- Reference block ----
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(customerName,
                        style: pw.TextStyle(font: fonts.bold, fontSize: 12)),
                    if ((customerPhone ?? '').isNotEmpty)
                      PdfBranding.kv('Phone', customerPhone!, fonts),
                    PdfBranding.kv(
                        'Route',
                        '${fromAddress ?? fromCity ?? '—'}  to  '
                            '${toAddress ?? toCity ?? '—'}',
                        fonts),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  PdfBranding.kv('Reference', leadRef, fonts, boldValue: true),
                  if (moveDate != null)
                    PdfBranding.kv('Move Date', PdfBranding.fmtDate(moveDate), fonts),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 14),

          // ---- Grouped item table ----
          if (grouped.isEmpty)
            pw.Text('No items recorded on this survey.',
                style: pw.TextStyle(
                    font: fonts.regular, fontSize: 10, color: PdfBranding.grey))
          else
            for (final entry in grouped.entries) ...[
              pw.Container(
                width: double.infinity,
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                margin: const pw.EdgeInsets.only(bottom: 3),
                decoration: pw.BoxDecoration(
                  color: PdfBranding.lightRow,
                  borderRadius: pw.BorderRadius.circular(3),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(entry.key,
                        style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 10,
                            color: PdfBranding.navy)),
                    pw.Text(
                        '${surveyTotalCft(entry.value).toStringAsFixed(0)} CFT',
                        style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 10,
                            color: PdfBranding.navy)),
                  ],
                ),
              ),
              for (final l in entry.value)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 12, bottom: 3),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        '${l.item}${l.sub.isEmpty ? '' : ' — ${l.sub}'}'
                        '${l.qty > 1 ? ' (x${l.qty})' : ''}',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 9),
                      ),
                      pw.Text('${l.lineCft.toStringAsFixed(0)} CFT',
                          style: pw.TextStyle(font: fonts.regular, fontSize: 9)),
                    ],
                  ),
                ),
              pw.SizedBox(height: 6),
            ],
          pw.SizedBox(height: 8),

          // ---- Footer totals ----
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfBranding.navy,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total: $totalItems item${totalItems == 1 ? '' : 's'}',
                    style:
                        pw.TextStyle(font: fonts.regular, fontSize: 9, color: PdfColors.white)),
                pw.Text('${totalCft.toStringAsFixed(0)} CFT',
                    style: pw.TextStyle(
                        font: fonts.bold, fontSize: 12, color: PdfBranding.gold)),
              ],
            ),
          ),
          if (pkg != null) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              'Suggested: ${pkg.type} · ${pkg.crew} crew · ${pkg.vehicle}',
              style: pw.TextStyle(
                  font: fonts.regular, fontSize: 9, color: PdfBranding.grey),
            ),
          ],
        ],
      ),
    );
    return doc.save();
  }

  /// `Nagarva_Survey_<lead_ref>_<yyyyMMdd>.pdf` — same convention as the
  /// quote (Part 8 addendum, item 2).
  static String filename(String leadRef, DateTime date) {
    final d = '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final safeRef = leadRef.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return 'Nagarva_Survey_${safeRef}_$d.pdf';
  }
}
