import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_branding.dart';

/// LR / Consignment Note (A4) — Session 3, task #43. Field spec §2, the
/// document furthest from the APC reference at kickoff: four copies
/// (Driver/Consignor/Consignee/Transporter — identical body, different
/// label, tracked in `lr_copies`), a three-column risk/notice/LR-meta
/// band, freight-mode columns, and a full freight breakdown with the
/// invoice cross-reference.
///
/// Pure renderer — every value is a plain parameter resolved by the
/// caller from `lr_register` (+ [OrgProfile]/[DocumentBoilerplate] for
/// branding/boilerplate), same convention as [InvoicePdf].
class LrPdf {
  static Future<Uint8List> generate({
    required OrgProfile org,
    required DocumentBoilerplate boilerplate,
    // One page per entry — 'generate all four' (field spec §2.1) passes
    // const ['driver','consignor','consignee','transporter'] to get one
    // combined, four-page PDF instead of four separate files; a reprint of
    // a single copy just passes a one-element list.
    required List<String> copyTypes,
    required String lrNo,
    required DateTime lrDate,
    Uint8List? logoBytes,
    Uint8List? signatureBytes,
    // Consignor — defaults to the org's own identity when a field isn't
    // explicitly captured on this LR (consignor_* columns are nullable).
    String? consignorName,
    String? consignorGstin,
    String? consignorAddress,
    String? consignorCity,
    String? consignorState,
    int? consignorStateCode,
    String? consignorPincode,
    String? consignorPhone,
    // Consignee
    String? consigneeName,
    String? consigneeGstin,
    String? consigneeAddress,
    String? consigneeCity,
    String? consigneeState,
    int? consigneeStateCode,
    String? consigneePincode,
    String? consigneePhone,
    String? fromPlace,
    String? toPlace,
    String? vehicleNo,
    // Risk declaration — sets the centre panel heading (2.2).
    String riskType = 'owner', // owner | carrier
    bool materialInsured = false,
    String? insurerName,
    String? policyNo,
    DateTime? insuranceDate,
    num? insuredAmount,
    int? distanceKm,
    String? driverName,
    String? driverPhone,
    // Goods (2.5)
    String? description,
    int packageCount = 0,
    num actualWeightKg = 0,
    num chargedWeightKg = 0,
    String? remark,
    // Freight mode column (2.4) — the amount prints only under the active
    // mode, "--" in the other two.
    String freightMode = 'paid', // paid | to_pay | tbb
    required num freightAmount,
    // Freight breakdown (2.6) — a zero/null line prints "--", not "₹0.00".
    num? basicFreight,
    num? loadingCharge,
    num? unloadingCharge,
    num? stCharge,
    num? otherCharges,
    num? lrCnCharge,
    num gstPct = 18,
    num? gstAmount,
    required num totalAmount,
    num? goodsValue,
    String? invoiceNo,
    DateTime? invoiceDate,
    String? gstPayableBy,
  }) async {
    final fonts = await PdfBranding.loadFonts();
    final doc = pw.Document();

    pw.Widget kv(String label, String value, {bool boldValue = false}) =>
        PdfBranding.kv(label, value, fonts, boldValue: boldValue);

    String amtOrDash(num? v) =>
        (v == null || v == 0) ? '--' : PdfBranding.rupees(v);

    String cityStateLine(
        String? city, String? state, int? stateCode, String? pincode) {
      final parts = <String>[];
      if ((city ?? '').isNotEmpty) parts.add(city!);
      var stateBit = state ?? '';
      if (stateCode != null) stateBit = '$stateBit ($stateCode)';
      if (stateBit.trim().isNotEmpty) parts.add(stateBit.trim());
      var line = parts.join(', ');
      if ((pincode ?? '').isNotEmpty) {
        line = line.isEmpty ? '- $pincode' : '$line - $pincode';
      }
      return line;
    }

    pw.Widget partyBlock({
      required String title,
      required String? name,
      required String? phone,
      required String? gstin,
      required String? address,
      required String cityStateLineText,
    }) {
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: .5),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 8.5,
                      color: PdfBranding.navy)),
              pw.SizedBox(height: 2),
              pw.Text((name ?? '').isEmpty ? '—' : name!,
                  style: pw.TextStyle(font: fonts.bold, fontSize: 9.5)),
              kv('Mobile', (phone ?? '').isEmpty ? 'N/A' : phone!),
              kv('GST No', (gstin ?? '').isEmpty ? 'N/A' : gstin!),
              if ((address ?? '').isNotEmpty)
                pw.Text(address!,
                    style: pw.TextStyle(font: fonts.regular, fontSize: 8)),
              if (cityStateLineText.isNotEmpty)
                pw.Text(cityStateLineText,
                    style: pw.TextStyle(font: fonts.regular, fontSize: 8)),
            ],
          ),
        ),
      );
    }

    pw.Widget freightModeBox(String label, String modeKey) {
      final active = freightMode == modeKey;
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: .5),
            color: active ? PdfBranding.lightRow : null,
          ),
          child: pw.Column(
            children: [
              pw.Text(label,
                  style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 8,
                      color: active ? PdfBranding.navy : PdfBranding.grey)),
              pw.SizedBox(height: 3),
              pw.Text(active ? PdfBranding.rupees(freightAmount) : '--',
                  style: pw.TextStyle(
                      font: active ? fonts.bold : fonts.regular, fontSize: 9)),
            ],
          ),
        ),
      );
    }

    final subtotal = (basicFreight ?? 0) +
        (loadingCharge ?? 0) +
        (unloadingCharge ?? 0) +
        (stCharge ?? 0) +
        (otherCharges ?? 0) +
        (lrCnCharge ?? 0);
    final gst = gstAmount ?? (subtotal * gstPct / 100);

    for (final copyType in copyTypes) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              PdfBranding.headerFull(
                org: org,
                docLabel: 'LORRY RECEIPT',
                fonts: fonts,
                logoBytes: logoBytes,
              ),
              pw.SizedBox(height: 10),

              // ---- 2.3 Consignor / Consignee ----------------------------
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  partyBlock(
                    title: 'CONSIGNOR',
                    name: (consignorName ?? '').isEmpty
                        ? org.name
                        : consignorName,
                    phone: consignorPhone ?? org.phones.firstOrNull,
                    gstin: consignorGstin ?? org.gstin,
                    address: consignorAddress ?? org.address,
                    cityStateLineText: cityStateLine(consignorCity,
                        consignorState, consignorStateCode, consignorPincode),
                  ),
                  pw.SizedBox(width: 8),
                  partyBlock(
                    title: 'CONSIGNEE',
                    name: consigneeName,
                    phone: consigneePhone,
                    gstin: consigneeGstin,
                    address: consigneeAddress,
                    cityStateLineText: cityStateLine(consigneeCity,
                        consigneeState, consigneeStateCode, consigneePincode),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),

              // ---- 2.2 Three-column band ---------------------------------
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(6),
                      decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                              color: PdfColors.grey400, width: .5)),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('NOTICE',
                              style: pw.TextStyle(
                                  font: fonts.bold,
                                  fontSize: 8,
                                  color: PdfBranding.navy)),
                          pw.SizedBox(height: 2),
                          pw.Text(boilerplate.lrNoticeText,
                              style: pw.TextStyle(
                                  font: fonts.regular,
                                  fontSize: 6.5,
                                  color: PdfBranding.grey)),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 4),
                  pw.Expanded(
                    flex: 4,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(6),
                      decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                              color: PdfColors.grey400, width: .5)),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                              riskType == 'carrier'
                                  ? "AT CARRIER'S RISK"
                                  : "AT OWNER'S RISK",
                              style: pw.TextStyle(
                                  font: fonts.bold,
                                  fontSize: 8,
                                  color: PdfBranding.navy)),
                          pw.SizedBox(height: 2),
                          kv('Material Insured',
                              materialInsured ? 'Yes' : 'No'),
                          kv('Insurance Co',
                              (insurerName ?? '').isEmpty ? '—' : insurerName!),
                          kv('Policy No',
                              (policyNo ?? '').isEmpty ? '—' : policyNo!),
                          kv(
                              'Insurance Date',
                              insuranceDate == null
                                  ? '—'
                                  : PdfBranding.fmtDate(insuranceDate)),
                          kv('Insured Amount', amtOrDash(insuredAmount)),
                          kv('Distance',
                              distanceKm == null ? '—' : '$distanceKm km'),
                          kv(
                              'Driver',
                              [
                                if ((driverName ?? '').isNotEmpty) driverName,
                                if ((driverPhone ?? '').isNotEmpty) driverPhone,
                              ].whereType<String>().join(' / ').isEmpty
                                  ? '—'
                                  : [
                                      if ((driverName ?? '').isNotEmpty)
                                        driverName,
                                      if ((driverPhone ?? '').isNotEmpty)
                                        driverPhone,
                                    ].whereType<String>().join(' / ')),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 4),
                  pw.Expanded(
                    flex: 3,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(6),
                      decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                              color: PdfColors.grey400, width: .5)),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          kv('LR No', lrNo, boldValue: true),
                          kv('Date', PdfBranding.fmtDate(lrDate)),
                          kv('Move From', fromPlace ?? '—'),
                          kv('Move To', toPlace ?? '—'),
                          kv('Vehicle No', vehicleNo ?? '—'),
                          pw.SizedBox(height: 3),
                          pw.Container(
                            width: double.infinity,
                            padding: const pw.EdgeInsets.symmetric(vertical: 4),
                            alignment: pw.Alignment.center,
                            decoration: pw.BoxDecoration(
                              color: PdfBranding.navy,
                              borderRadius: pw.BorderRadius.circular(3),
                            ),
                            child: pw.Text('${copyType.toUpperCase()} COPY',
                                style: pw.TextStyle(
                                    font: fonts.bold,
                                    fontSize: 8,
                                    color: PdfColors.white)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),

              // ---- 2.4 Freight mode columns -------------------------------
              pw.Row(
                children: [
                  freightModeBox('PAID', 'paid'),
                  pw.SizedBox(width: 4),
                  freightModeBox('TO PAY', 'to_pay'),
                  pw.SizedBox(width: 4),
                  freightModeBox('TO BE BILLED', 'tbb'),
                ],
              ),
              pw.SizedBox(height: 8),

              // ---- 2.5 Goods description / packages / weight / remark -----
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400, width: .5)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    kv(
                        'Description',
                        (description ?? '').isEmpty
                            ? boilerplate.goodsDescriptionDefault
                            : description!),
                    kv('No. of Packages', '$packageCount'),
                    kv('Weight',
                        'Actual: ${actualWeightKg}kg   Charged: ${chargedWeightKg}kg'),
                    if ((remark ?? '').isNotEmpty) kv('Remark', remark!),
                    pw.SizedBox(height: 3),
                    pw.Text(boilerplate.demurrageSentence,
                        style: pw.TextStyle(
                            font: fonts.regular,
                            fontSize: 6.5,
                            fontStyle: pw.FontStyle.italic,
                            color: PdfBranding.grey)),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),

              // ---- 2.6 Freight breakdown -----------------------------------
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      children: [
                        _breakdownRow('Basic Freight', amtOrDash(basicFreight),
                            fonts.regular, fonts.bold),
                        _breakdownRow('Loading', amtOrDash(loadingCharge),
                            fonts.regular, fonts.bold),
                        _breakdownRow('Unloading', amtOrDash(unloadingCharge),
                            fonts.regular, fonts.bold),
                        _breakdownRow('S.T. Charge', amtOrDash(stCharge),
                            fonts.regular, fonts.bold),
                        _breakdownRow('Other Charge', amtOrDash(otherCharges),
                            fonts.regular, fonts.bold),
                        _breakdownRow('LR / CN Charge', amtOrDash(lrCnCharge),
                            fonts.regular, fonts.bold),
                        pw.Divider(color: PdfColors.grey400, thickness: .5),
                        _breakdownRow('Subtotal', PdfBranding.rupees(subtotal),
                            fonts.regular, fonts.bold),
                        _breakdownRow('GST @$gstPct%', PdfBranding.rupees(gst),
                            fonts.regular, fonts.bold),
                        pw.Container(
                          margin: const pw.EdgeInsets.only(top: 3),
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
                              pw.Text('TOTAL',
                                  style: pw.TextStyle(
                                      font: fonts.bold,
                                      fontSize: 9,
                                      color: PdfColors.white)),
                              pw.Text(PdfBranding.rupees(totalAmount),
                                  style: pw.TextStyle(
                                      font: fonts.bold,
                                      fontSize: 10,
                                      color: PdfBranding.gold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 16),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        kv('Goods Value', amtOrDash(goodsValue)),
                        kv(
                            'Inv No. & Date',
                            (invoiceNo ?? '').isEmpty
                                ? '—'
                                : '$invoiceNo'
                                    '${invoiceDate == null ? '' : ' dt. ${PdfBranding.fmtDate(invoiceDate)}'}'),
                        kv('GST Paid By',
                            (gstPayableBy ?? '').isEmpty ? '—' : gstPayableBy!),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 14),

              // ---- 2.7 Declaration + signature ------------------------------
              pw.Text(
                'I/We hereby declare that the consignment tendered above for '
                'transportation contains no arms, ammunition, explosives, '
                'contraband or any other prohibited goods, and the particulars '
                'furnished above are true and correct to the best of my/our '
                'knowledge.',
                style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 7,
                    fontStyle: pw.FontStyle.italic,
                    color: PdfBranding.grey),
              ),
              pw.SizedBox(height: 16),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                          width: 150, height: .8, color: PdfColors.grey600),
                      pw.SizedBox(height: 3),
                      pw.Text("Consignor's Signature",
                          style:
                              pw.TextStyle(font: fonts.regular, fontSize: 8.5)),
                    ],
                  ),
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
              pw.Spacer(),
              PdfBranding.footerFull(fonts, org: org, boilerplate: boilerplate),
            ],
          ),
        ),
      );
    }

    return doc.save();
  }

  static pw.Widget _breakdownRow(
          String label, String value, pw.Font regular, pw.Font bold) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: pw.TextStyle(font: regular, fontSize: 8.5)),
            pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 8.5)),
          ],
        ),
      );
}
