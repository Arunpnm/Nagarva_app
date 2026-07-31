import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '/backend/pricing_defaults.dart';
import '/components/pdf_branding.dart';

/// Quotation PDF (Part 8 addendum, item 2 — quote half).
///
/// Deliberately separate from [SurveyPdf] (Rev B, Q2 decision: two
/// documents, not one combined) — this one only makes sense once a quote
/// exists, unlike the survey which goes out earlier in the pipeline.
///
/// Renders `quote_charges`/`quotations.charges`: a flat key -> value map
/// from `kDefaultChargeFields`, with a *per-key* included/additional
/// toggle (`_billingMode`) for the 5 billable fields (packing/unpacking/
/// loading/unloading/materials).
///
/// Each value is either a plain number (legacy/lumpsum — no basis
/// breakdown to show) or, since Part 8 Rev B item 4, an object
/// `{amount, basis, qty, rate}` (or `{amount, basis, declaredValue, rate}`
/// for percent_of_declared_value) for any of the 6 basis-aware keys
/// (transport/packing/unpacking/loading/unloading/materials) the vendor
/// has priced by CFT/floor/trip/km/actuals/declared-value instead of a
/// flat lumpsum. [detailed] toggles whether that breakdown — plus the
/// Inclusions/Exclusions block — is shown; false renders the same
/// Summary view as before Item 4 existed.
class QuotePdf {
  static Future<Uint8List> generate({
    required String leadRef,
    required String customerName,
    String? customerPhone,
    String? fromAddress,
    String? toAddress,
    String? fromCity,
    String? toCity,
    required Map<String, dynamic> charges,
    required double subtotal,
    required double gstPct,
    required double gstAmount,
    required double total,
    required bool interstate,
    required String orgName,
    Map<String, dynamic> profile = const {},
    Uint8List? logoBytes,
    Uint8List? customerSignatureBytes,
    String? customerSignedByName,
    DateTime? customerSignedAt,
    DateTime? generatedAt,
    bool detailed = false,
  }) async {
    final fonts = await PdfBranding.loadFonts();
    final now = generatedAt ?? DateTime.now();
    final validUntil = now.add(const Duration(days: 15));

    // A charge value is either a plain number (legacy/lumpsum) or an
    // {amount, basis, ...} object (item 4). Reader rule: a number is
    // always legacy lumpsum, regardless of what pricing_config says today
    // — never re-derive basis from current config for an already-saved
    // quote, or reprinting it later would silently disagree with what the
    // customer actually accepted.
    Map<String, dynamic>? detail(String key) {
      final v = charges[key];
      return v is Map ? Map<String, dynamic>.from(v) : null;
    }

    num amt(String key) {
      final v = charges[key];
      if (v is num) return v;
      final d = detail(key);
      if (d != null && d['amount'] is num) return d['amount'] as num;
      return num.tryParse('$v') ?? 0;
    }

    String? basisDescription(String key) {
      final d = detail(key);
      if (d == null) return null;
      final basis = d['basis'] as String? ?? 'lumpsum';
      switch (basis) {
        case 'per_cft':
        case 'per_floor':
        case 'per_trip':
        case 'per_km':
          final qty = d['qty'];
          final rate = d['rate'];
          final unit = {
            'per_cft': 'CFT',
            'per_floor': 'Floor(s)',
            'per_trip': 'Trip(s)',
            'per_km': 'KM',
          }[basis];
          return '$qty $unit × ${PdfBranding.rupees(rate is num ? rate : 0)}';
        case 'percent_of_declared_value':
          final declared = d['declaredValue'];
          final rate = d['rate'];
          return '${PdfBranding.rupees(declared is num ? declared : 0)} × $rate%';
        case 'at_actuals':
          return 'At actuals';
        case 'lumpsum':
        default:
          return null;
      }
    }

    final billingMode = charges['_billingMode'] is Map
        ? Map<String, dynamic>.from(charges['_billingMode'] as Map)
        : const <String, dynamic>{};
    bool isIncluded(ChargeField f) =>
        f.billable && (billingMode[f.key] ?? 'included') == 'included';

    final includedLabels = kDefaultChargeFields
        .where((f) => isIncluded(f) && amt(f.key) == 0)
        .map((f) => f.label)
        .toList();
    // A billable field marked "included" but with its own amount also
    // entered is shown as its own line anyway — the toggle only suppresses
    // the footnote-vs-line distinction when the amount is genuinely zero,
    // never silently drops a non-zero figure the vendor typed in.
    final lines = kDefaultChargeFields.where((f) {
      if (f.key == 'discount' || f.key == 'advanceOnQuote') return false;
      if (isIncluded(f) && amt(f.key) == 0) return false;
      return amt(f.key) != 0;
    }).toList();

    final discount = amt('discount');
    final advance = amt('advanceOnQuote');
    final balanceDue = total - advance;
    final amountWords = _amountInWords(total);

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
                  docLabel: 'QUOTATION',
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
                  PdfBranding.kv('Date', PdfBranding.fmtDate(now), fonts),
                  PdfBranding.kv('Valid Until', PdfBranding.fmtDate(validUntil), fonts),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 14),

          // ---- Charge lines ----
          pw.Table(
            columnWidths: detailed
                ? const {
                    0: pw.FlexColumnWidth(5),
                    1: pw.FlexColumnWidth(4),
                    2: pw.FlexColumnWidth(2),
                  }
                : const {
                    0: pw.FlexColumnWidth(6),
                    1: pw.FlexColumnWidth(2),
                  },
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: .5),
            ),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfBranding.navy),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: pw.Text('DESCRIPTION',
                        style: pw.TextStyle(
                            font: fonts.bold, fontSize: 9, color: PdfColors.white)),
                  ),
                  if (detailed)
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: pw.Text('BASIS',
                          style: pw.TextStyle(
                              font: fonts.bold, fontSize: 9, color: PdfColors.white)),
                    ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: pw.Text('AMOUNT',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                            font: fonts.bold, fontSize: 9, color: PdfColors.white)),
                  ),
                ],
              ),
              for (final f in lines)
                pw.TableRow(children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: pw.Text(f.label,
                        style: pw.TextStyle(font: fonts.regular, fontSize: 9)),
                  ),
                  if (detailed)
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      child: pw.Text(basisDescription(f.key) ?? '—',
                          style: pw.TextStyle(
                              font: fonts.regular, fontSize: 8, color: PdfBranding.grey)),
                    ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    // `lines` already excludes zero/null-amount fields
                    // (below) — Rev A's "never print ₹0" rule is met by
                    // omission, the rule's other allowed option.
                    child: pw.Text(PdfBranding.rupees(amt(f.key)),
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(font: fonts.regular, fontSize: 9)),
                  ),
                ]),
              if (discount > 0)
                pw.TableRow(children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: pw.Text('Discount',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 9)),
                  ),
                  if (detailed) pw.SizedBox(),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: pw.Text('- ${PdfBranding.rupees(discount)}',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(font: fonts.regular, fontSize: 9)),
                  ),
                ]),
            ],
          ),
          if (includedLabels.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              '${includedLabels.join(', ')} included in Freight & Transportation.',
              style: pw.TextStyle(
                  font: fonts.regular, fontSize: 7.5, color: PdfBranding.grey),
            ),
          ],
          pw.SizedBox(height: 10),

          // ---- Totals ----
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 240,
              child: pw.Column(
                children: [
                  _totalRow('Subtotal', PdfBranding.rupees(subtotal), fonts),
                  if (interstate)
                    _totalRow('IGST @ ${gstPct.toStringAsFixed(0)}%',
                        PdfBranding.rupees(gstAmount), fonts)
                  else ...[
                    _totalRow('CGST @ ${(gstPct / 2).toStringAsFixed(1)}%',
                        PdfBranding.rupees(gstAmount / 2), fonts),
                    _totalRow('SGST @ ${(gstPct / 2).toStringAsFixed(1)}%',
                        PdfBranding.rupees(gstAmount / 2), fonts),
                  ],
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 4),
                    padding:
                        const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: PdfBranding.navy,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('GRAND TOTAL',
                            style: pw.TextStyle(
                                font: fonts.bold, fontSize: 10, color: PdfColors.white)),
                        pw.Text(PdfBranding.rupees(total),
                            style: pw.TextStyle(
                                font: fonts.bold, fontSize: 11, color: PdfBranding.gold)),
                      ],
                    ),
                  ),
                  if (advance > 0) ...[
                    pw.SizedBox(height: 6),
                    _totalRow('Less: Advance Paid', PdfBranding.rupees(advance), fonts),
                    _totalRow('Balance Due', PdfBranding.rupees(balanceDue), fonts,
                        bold: true),
                  ],
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Amount in words: $amountWords',
              style: pw.TextStyle(
                  font: fonts.regular, fontSize: 8.5, fontStyle: pw.FontStyle.italic)),
          pw.SizedBox(height: 14),

          // ---- Inclusions / Exclusions (Rev A brief, item 4 — detailed
          // variant only). Content comes from the vendor's own Settings
          // (quote_inclusions/quote_exclusions, same convention as
          // invoice_terms) rather than invented generic business terms —
          // "exclusions are where disputes come from" is exactly why this
          // shouldn't be text this generator makes up on the vendor's
          // behalf. Degrades to a hint, not fabricated content, when empty.
          if (detailed) ...[
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _inclusionsBlock(
                    fonts,
                    title: 'INCLUSIONS',
                    color: PdfColors.green700,
                    text: PdfBranding.p(profile, 'quote_inclusions'),
                    hint: 'Add what\'s included in Settings to show it here.',
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  child: _inclusionsBlock(
                    fonts,
                    title: 'EXCLUSIONS',
                    color: PdfColors.red700,
                    text: PdfBranding.p(profile, 'quote_exclusions'),
                    hint: 'Add what\'s excluded in Settings to show it here.',
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 14),
          ],

          // ---- Terms ----
          if (PdfBranding.p(profile, 'quote_terms').isNotEmpty) ...[
            pw.Text('TERMS & CONDITIONS',
                style: pw.TextStyle(font: fonts.bold, fontSize: 8.5, color: PdfBranding.navy)),
            pw.SizedBox(height: 3),
            ...PdfBranding.p(profile, 'quote_terms')
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
                            font: fonts.regular, fontSize: 7.5, color: PdfBranding.grey),
                      ),
                    )),
            pw.SizedBox(height: 14),
          ],

          // ---- Payment terms + signature block ----
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Text(
                  'Payment terms: as agreed with $orgName. This quotation is '
                  'valid until ${PdfBranding.fmtDate(validUntil)}.',
                  style: pw.TextStyle(
                      font: fonts.regular, fontSize: 8, color: PdfBranding.grey),
                ),
              ),
              pw.SizedBox(width: 24),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (customerSignatureBytes != null) ...[
                    pw.Container(
                      height: 42,
                      child: pw.Image(pw.MemoryImage(customerSignatureBytes),
                          fit: pw.BoxFit.contain),
                    ),
                    pw.Container(width: 150, height: .8, color: PdfColors.grey600),
                    pw.SizedBox(height: 3),
                    pw.Text('Accepted by ${customerSignedByName ?? 'Customer'}',
                        style: pw.TextStyle(font: fonts.bold, fontSize: 8.5)),
                    if (customerSignedAt != null)
                      pw.Text(PdfBranding.fmtDate(customerSignedAt),
                          style: pw.TextStyle(
                              font: fonts.regular, fontSize: 8, color: PdfBranding.grey)),
                  ] else
                    pw.Text('Awaiting customer signature',
                        style: pw.TextStyle(
                            font: fonts.regular,
                            fontSize: 9,
                            fontStyle: pw.FontStyle.italic,
                            color: PdfBranding.grey)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _totalRow(String label, String value, PdfFonts fonts,
      {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  font: bold ? fonts.bold : fonts.regular, fontSize: 9)),
          pw.Text(value,
              style: pw.TextStyle(font: fonts.bold, fontSize: 9)),
        ],
      ),
    );
  }

  static pw.Widget _inclusionsBlock(
    PdfFonts fonts, {
    required String title,
    required PdfColor color,
    required String text,
    required String hint,
  }) {
    final items = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfBranding.lightRow,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border(left: pw.BorderSide(color: color, width: 2.5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style: pw.TextStyle(font: fonts.bold, fontSize: 8.5, color: color)),
          pw.SizedBox(height: 4),
          if (items.isEmpty)
            pw.Text(hint,
                style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 7.5,
                    fontStyle: pw.FontStyle.italic,
                    color: PdfBranding.grey))
          else
            for (final line in items)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 1.5),
                child: pw.Text('• ${line.trim()}',
                    style: pw.TextStyle(
                        font: fonts.regular, fontSize: 8, color: PdfBranding.grey)),
              ),
        ],
      ),
    );
  }

  /// Indian numbering (lakh/crore) amount-to-words, rupees only (no PDF
  /// document here needs paise precision — quotes/invoices round to the
  /// rupee already via the existing rupees() formatter's inputs).
  static String _amountInWords(num amount) {
    final rupeesPart = amount.floor();
    if (rupeesPart == 0) return 'Rupees Zero Only';
    return 'Rupees ${_numToWords(rupeesPart)} Only';
  }

  static const _ones = [
    '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
    'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
    'Seventeen', 'Eighteen', 'Nineteen',
  ];
  static const _tens = [
    '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety',
  ];

  static String _twoDigits(int n) {
    if (n < 20) return _ones[n];
    return '${_tens[n ~/ 10]}${n % 10 == 0 ? '' : ' ${_ones[n % 10]}'}';
  }

  static String _threeDigits(int n) {
    final h = n ~/ 100;
    final rest = n % 100;
    if (h == 0) return _twoDigits(rest);
    return '${_ones[h]} Hundred${rest == 0 ? '' : ' ${_twoDigits(rest)}'}';
  }

  static String _numToWords(int n) {
    if (n == 0) return 'Zero';
    final parts = <String>[];
    final crore = n ~/ 10000000;
    n %= 10000000;
    final lakh = n ~/ 100000;
    n %= 100000;
    final thousand = n ~/ 1000;
    n %= 1000;
    final hundred = n;
    if (crore > 0) parts.add('${_threeDigits(crore)} Crore');
    if (lakh > 0) parts.add('${_threeDigits(lakh)} Lakh');
    if (thousand > 0) parts.add('${_threeDigits(thousand)} Thousand');
    if (hundred > 0) parts.add(_threeDigits(hundred));
    return parts.join(' ');
  }

  /// `Nagarva_Quote_<lead_ref>_<yyyyMMdd>.pdf`
  static String filename(String leadRef, DateTime date) {
    final d = '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final safeRef = leadRef.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return 'Nagarva_Quote_${safeRef}_$d.pdf';
  }
}
