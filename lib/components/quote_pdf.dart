import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '/backend/pricing_defaults.dart';
import '/components/pdf_branding.dart';
import '/components/survey_response_section.dart' show SurveyLine;

/// Quotation PDF (Part 8 addendum, item 2 — quote half; rebuilt to the
/// three-page APC reference shape in Session 3, task #44 — field spec §3).
///
/// Page 1: identity/meta, consignment characteristics, Move From/To panels
/// (with floor + lift), the charge table, GST totals, FOV/insurance line,
/// total in words. Page 2: site-access answers, bank details, the
/// invoice_note warning, signatures, and the Moving Items table (from
/// `surveys.rooms` — field spec §3's own flag: "this is the piece most
/// likely to be missing", now wired through via [surveyLines]). Page 3:
/// tenant-editable Terms & Conditions from `app_settings` ([boilerplate]),
/// never hardcoded.
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
    required OrgProfile org,
    required DocumentBoilerplate boilerplate,
    required String customerName,
    String? customerPhone,
    String? customerEmail,
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
    Uint8List? logoBytes,
    Uint8List? customerSignatureBytes,
    String? customerSignedByName,
    DateTime? customerSignedAt,
    DateTime? generatedAt,
    bool detailed = false,
    // ---- Consignment characteristics (field spec §3, page 1) -----------
    String? loadType, // full_load | part_load
    String? vehicleType, // dedicated | shared
    String? transportMode, // road | rail | air | ship
    DateTime? quotationDate,
    DateTime? packingDate,
    DateTime? deliveryDate,
    DateTime? movingDate,
    int? fromFloor,
    bool? fromHasLift,
    int? toFloor,
    bool? toHasLift,
    // FOV / insurance — "@{fov_pct}% On Declaration Value Of Goods
    // ({declared_value}/-)". A zero/null fovPct or declaredValue simply
    // omits the line rather than printing a bogus "@0%".
    num? declaredValue,
    num? fovPct,
    num? fovAmount,
    // ---- Page 2 ----------------------------------------------------------
    bool? easyAccess,
    bool? accessRestrictions,
    String? accessNotes,
    // Moving Items — surveys.rooms via parseSurveyRooms(). Value INR has
    // no backing data anywhere yet (SurveyLine only carries cft/qty, not a
    // per-item price) — the column renders "—" rather than a guessed
    // number; a real fix belongs in the survey capture flow, not here.
    List<SurveyLine> surveyLines = const [],
    // Total in words — via the DB's amount_in_words() RPC, never
    // reimplemented in Dart (the old client-side lakh/crore converter this
    // file used to carry is gone; see amount_in_words() in
    // nagarva_migration_009_documents.sql).
    String? amountInWords,
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

    pw.Widget kv(String label, String value, {bool boldValue = false}) =>
        PdfBranding.kv(label, value, fonts, boldValue: boldValue);

    String yesNo(bool? v) => v == null ? '—' : (v ? 'Yes' : 'No');
    String labelize(String? s) => (s ?? '').isEmpty
        ? '—'
        : s![0].toUpperCase() + s.substring(1).replaceAll('_', ' ');

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 14),
                child: PdfBranding.headerFull(
                  org: org,
                  docLabel: 'QUOTATION',
                  fonts: fonts,
                  logoBytes: logoBytes,
                ),
              )
            : pw.SizedBox(),
        footer: (ctx) =>
            PdfBranding.footerFull(fonts, org: org, boilerplate: boilerplate),
        build: (ctx) => [
          // ══════════════════════════════════════════════════════════════
          // PAGE 1
          // ══════════════════════════════════════════════════════════════
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfBranding.navy, width: 1),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text('Quotation No: $leadRef',
                style: pw.TextStyle(
                    font: fonts.bold, fontSize: 10, color: PdfBranding.navy)),
          ),
          pw.SizedBox(height: 8),
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
                      kv('Phone', customerPhone!),
                    if ((customerEmail ?? '').isNotEmpty)
                      kv('Email', customerEmail!),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  kv('Quotation Date', PdfBranding.fmtDate(quotationDate ?? now)),
                  if (packingDate != null)
                    kv('Packing Date', PdfBranding.fmtDate(packingDate)),
                  if (deliveryDate != null)
                    kv('Delivery Date', PdfBranding.fmtDate(deliveryDate)),
                  if (movingDate != null)
                    kv('Moving Date', PdfBranding.fmtDate(movingDate)),
                  kv('Valid Until', PdfBranding.fmtDate(validUntil)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Dear ${customerName.isEmpty ? 'Customer' : customerName}, '
            'thank you for the opportunity to quote for your move from '
            '${fromCity ?? fromAddress ?? 'origin'} to '
            '${toCity ?? toAddress ?? 'destination'}.',
            style: pw.TextStyle(
                font: fonts.regular, fontSize: 8.5, color: PdfBranding.grey),
          ),
          pw.SizedBox(height: 8),

          // ---- Consignment characteristics ----------------------------
          pw.Wrap(
            spacing: 16,
            runSpacing: 2,
            children: [
              kv('Moving Type', labelize(loadType)),
              kv('Vehicle Type', labelize(vehicleType)),
              kv('Transport Mode', labelize(transportMode ?? 'road')),
            ],
          ),
          pw.SizedBox(height: 8),

          // ---- Move From / To panels ------------------------------------
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400, width: .5)),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('MOVE FROM',
                          style: pw.TextStyle(
                              font: fonts.bold,
                              fontSize: 8.5,
                              color: PdfBranding.navy)),
                      pw.SizedBox(height: 2),
                      pw.Text(fromAddress ?? fromCity ?? '—',
                          style: pw.TextStyle(font: fonts.regular, fontSize: 8.5)),
                      if (fromFloor != null) kv('Floor', '$fromFloor'),
                      kv('Is Lift Available', yesNo(fromHasLift)),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400, width: .5)),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('MOVE TO',
                          style: pw.TextStyle(
                              font: fonts.bold,
                              fontSize: 8.5,
                              color: PdfBranding.navy)),
                      pw.SizedBox(height: 2),
                      pw.Text(toAddress ?? toCity ?? '—',
                          style: pw.TextStyle(font: fonts.regular, fontSize: 8.5)),
                      if (toFloor != null) kv('Floor', '$toFloor'),
                      kv('Is Lift Available', yesNo(toHasLift)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),

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
              for (var i = 0; i < lines.length; i++)
                pw.TableRow(children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: pw.Text('${i + 1}. ${lines[i].label}',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 9)),
                  ),
                  if (detailed)
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      child: pw.Text(basisDescription(lines[i].key) ?? '—',
                          style: pw.TextStyle(
                              font: fonts.regular, fontSize: 8, color: PdfBranding.grey)),
                    ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    // `lines` already excludes zero/null-amount fields
                    // (below) — Rev A's "never print ₹0" rule is met by
                    // omission, the rule's other allowed option.
                    child: pw.Text(PdfBranding.rupees(amt(lines[i].key)),
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
              width: 260,
              child: pw.Column(
                children: [
                  _totalRow('Sub Total', PdfBranding.rupees(subtotal), fonts),
                  if (interstate)
                    _totalRow('IGST @ ${gstPct.toStringAsFixed(0)}%',
                        PdfBranding.rupees(gstAmount), fonts)
                  else ...[
                    _totalRow('CGST @ ${(gstPct / 2).toStringAsFixed(1)}%',
                        PdfBranding.rupees(gstAmount / 2), fonts),
                    _totalRow('SGST @ ${(gstPct / 2).toStringAsFixed(1)}%',
                        PdfBranding.rupees(gstAmount / 2), fonts),
                  ],
                  if ((fovPct ?? 0) > 0 && (declaredValue ?? 0) > 0)
                    _totalRow(
                        'FOV / Insurance Charge @${fovPct!.toStringAsFixed(1)}% '
                        'On Declaration Value Of Goods '
                        '(${PdfBranding.rupees(declaredValue!)}/-)',
                        PdfBranding.rupees(fovAmount ?? 0),
                        fonts),
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
                        pw.Text('TOTAL AMOUNT',
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
          if ((amountInWords ?? '').isNotEmpty)
            pw.Text('Total Amount In Words: $amountInWords',
                style: pw.TextStyle(
                    font: fonts.regular, fontSize: 8.5, fontStyle: pw.FontStyle.italic)),
          pw.SizedBox(height: 10),

          if (detailed) ...[
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _inclusionsBlock(
                    fonts,
                    title: 'INCLUSIONS',
                    color: PdfColors.green700,
                    items: includedLabels,
                    hint: 'Nothing marked included yet.',
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  child: _inclusionsBlock(
                    fonts,
                    title: 'EXCLUSIONS',
                    color: PdfColors.red700,
                    items: const [],
                    hint: 'Add exclusions on the quote form to show them here.',
                  ),
                ),
              ],
            ),
          ],

          // ══════════════════════════════════════════════════════════════
          // PAGE 2
          // ══════════════════════════════════════════════════════════════
          pw.NewPage(),

          // ---- Site access ------------------------------------------------
          pw.Text('SITE ACCESS',
              style:
                  pw.TextStyle(font: fonts.bold, fontSize: 9.5, color: PdfBranding.navy)),
          pw.SizedBox(height: 4),
          kv('Easy Access For Vehicle', yesNo(easyAccess)),
          kv('Any Access Restrictions', yesNo(accessRestrictions)),
          if ((accessNotes ?? '').isNotEmpty) kv('Access Notes', accessNotes!),
          pw.SizedBox(height: 14),

          // ---- Bank details -------------------------------------------
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfBranding.lightRow,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('BANK DETAILS',
                    style: pw.TextStyle(
                        font: fonts.bold, fontSize: 9, color: PdfBranding.navy)),
                pw.SizedBox(height: 4),
                if ((org.beneficiaryName ?? '').isNotEmpty)
                  kv('Beneficiary', org.beneficiaryName!),
                if ((org.bankName ?? '').isNotEmpty) kv('Bank', org.bankName!),
                if ((org.bankAccountNo ?? '').isNotEmpty)
                  kv('A/c No', org.bankAccountNo!),
                if ((org.bankIfsc ?? '').isNotEmpty) kv('IFSC', org.bankIfsc!),
                if ((org.upiId ?? '').isNotEmpty) kv('UPI', org.upiId!),
                if ((org.upiDisplayNumber ?? '').isNotEmpty)
                  kv('PhonePe/GPay', org.upiDisplayNumber!),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.red200, width: .8),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(boilerplate.invoiceNote,
                style: pw.TextStyle(
                    font: fonts.regular, fontSize: 7.5, color: PdfColors.red900)),
          ),
          pw.SizedBox(height: 14),

          // ---- Signatures -----------------------------------------------
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(width: 150, height: .8, color: PdfColors.grey600),
                    pw.SizedBox(height: 3),
                    pw.Text(
                        (org.signatoryName ?? '').isNotEmpty
                            ? org.signatoryName!
                            : 'Authorized Signatory',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 8.5)),
                    pw.Text('for ${org.name}',
                        style: pw.TextStyle(
                            font: fonts.regular, fontSize: 8, color: PdfBranding.grey)),
                  ],
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
                  ] else ...[
                    pw.SizedBox(height: 42),
                    pw.Container(width: 150, height: .8, color: PdfColors.grey600),
                    pw.SizedBox(height: 3),
                    pw.Text("Receiver's Signature",
                        style: pw.TextStyle(font: fonts.regular, fontSize: 8.5)),
                  ],
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),

          // ---- Moving Items list (field spec §3, page 2) -----------------
          if (surveyLines.isNotEmpty) ...[
            pw.Text('MOVING ITEMS',
                style: pw.TextStyle(
                    font: fonts.bold, fontSize: 9.5, color: PdfBranding.navy)),
            pw.SizedBox(height: 4),
            pw.Table(
              columnWidths: const {
                0: pw.FlexColumnWidth(1),
                1: pw.FlexColumnWidth(6),
                2: pw.FlexColumnWidth(2),
                3: pw.FlexColumnWidth(2),
                4: pw.FlexColumnWidth(2),
              },
              border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfBranding.navy),
                  children: [
                    for (final h in [
                      'SR NO',
                      'GOODS DESCRIPTION',
                      'QTY',
                      'VALUE INR',
                      'REMARK'
                    ])
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6, vertical: 5),
                        child: pw.Text(h,
                            style: pw.TextStyle(
                                font: fonts.bold, fontSize: 8, color: PdfColors.white)),
                      ),
                  ],
                ),
                for (var i = 0; i < surveyLines.length; i++)
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                        color: i.isOdd ? PdfBranding.lightRow : PdfColors.white),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: pw.Text('${i + 1}',
                            style: pw.TextStyle(font: fonts.regular, fontSize: 8)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: pw.Text(
                            surveyLines[i].sub.isEmpty
                                ? surveyLines[i].item
                                : '${surveyLines[i].item} - ${surveyLines[i].sub}',
                            style: pw.TextStyle(font: fonts.regular, fontSize: 8)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: pw.Text('${surveyLines[i].qty}',
                            style: pw.TextStyle(font: fonts.regular, fontSize: 8)),
                      ),
                      // No per-item price is captured anywhere in the survey
                      // flow today (SurveyLine only carries cft/qty) — this
                      // renders "—" rather than fabricate a number. A real
                      // fix belongs in the survey capture flow.
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: pw.Text('—',
                            style: pw.TextStyle(font: fonts.regular, fontSize: 8)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: pw.Text('—',
                            style: pw.TextStyle(font: fonts.regular, fontSize: 8)),
                      ),
                    ],
                  ),
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfBranding.lightRow),
                  children: [
                    pw.Padding(
                      padding:
                          const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                      child: pw.Text(''),
                    ),
                    pw.Padding(
                      padding:
                          const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                      child: pw.Text('Total Quantity',
                          style: pw.TextStyle(font: fonts.bold, fontSize: 8)),
                    ),
                    pw.Padding(
                      padding:
                          const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                      child: pw.Text(
                          '${surveyLines.fold<int>(0, (s, l) => s + l.qty)}',
                          style: pw.TextStyle(font: fonts.bold, fontSize: 8)),
                    ),
                    pw.Padding(
                      padding:
                          const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                      child: pw.Text(''),
                    ),
                    pw.Padding(
                      padding:
                          const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                      child: pw.Text(''),
                    ),
                  ],
                ),
              ],
            ),
          ],

          // ══════════════════════════════════════════════════════════════
          // PAGE 3 — Terms & Conditions (tenant-editable, never hardcoded)
          // ══════════════════════════════════════════════════════════════
          pw.NewPage(),
          pw.Text('TERMS & CONDITIONS',
              style:
                  pw.TextStyle(font: fonts.bold, fontSize: 10, color: PdfBranding.navy)),
          pw.SizedBox(height: 6),
          if (boilerplate.quotationTerms.isEmpty)
            pw.Text(
                'Add your terms & conditions in Settings to show them here.',
                style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 8.5,
                    fontStyle: pw.FontStyle.italic,
                    color: PdfBranding.grey))
          else
            for (var i = 0; i < boilerplate.quotationTerms.length; i++)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text(
                  '${i + 1}. ${boilerplate.quotationTerms[i]}',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 8.5),
                ),
              ),
          pw.SizedBox(height: 14),
          pw.Text(
            'Payment terms: as agreed with ${org.name}. This quotation is '
            'valid until ${PdfBranding.fmtDate(validUntil)}.',
            style: pw.TextStyle(
                font: fonts.regular, fontSize: 8, color: PdfBranding.grey),
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
          pw.Expanded(
            child: pw.Text(label,
                style: pw.TextStyle(
                    font: bold ? fonts.bold : fonts.regular, fontSize: 9)),
          ),
          pw.Text(value, style: pw.TextStyle(font: fonts.bold, fontSize: 9)),
        ],
      ),
    );
  }

  static pw.Widget _inclusionsBlock(
    PdfFonts fonts, {
    required String title,
    required PdfColor color,
    required List<String> items,
    required String hint,
  }) {
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
                child: pw.Text('• $line',
                    style: pw.TextStyle(
                        font: fonts.regular, fontSize: 8, color: PdfBranding.grey)),
              ),
        ],
      ),
    );
  }

  /// `Nagarva_Quote_<lead_ref>_<yyyyMMdd>.pdf`
  static String filename(String leadRef, DateTime date) {
    final d = '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final safeRef = leadRef.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return 'Nagarva_Quote_${safeRef}_$d.pdf';
  }
}
