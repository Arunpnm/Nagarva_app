import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '/backend/supabase/database/database.dart';

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

/// Resolved tenant identity for a document header (Session 3, Tier 2).
///
/// Dual-source by design, per the owner's explicit call: read the
/// `organizations` columns (migrations 006/009) first — the multi-tenant-
/// correct source going forward — and fall back to that SAME org's
/// `settings.business_profile` jsonb blob (the pre-existing source
/// `BusinessSettingsSection`/the old inlined `InvoicePdf` header used)
/// only where the `organizations` column is still null. Never falls back
/// to a different org's data or a hardcoded default — an unfilled field
/// with no source in either place is simply blank, same convention the
/// old header already used.
///
/// `nagarva_migration_010_org_profile_backfill.sql` copies the jsonb
/// values into `organizations` (where null) so this fallback eventually
/// becomes dead code — see that file for the exact key mapping, which
/// [resolve] below mirrors field-for-field.
class OrgProfile {
  const OrgProfile({
    required this.name,
    this.tagline,
    this.address,
    this.gstin,
    this.pan,
    this.phones = const [],
    this.landline,
    this.udyamNo,
    this.affiliationText,
    this.branchListText,
    this.website,
    this.email,
    this.signatoryName,
    this.signatoryImageUrl,
    this.beneficiaryName,
    this.bankName,
    this.bankAccountNo,
    this.bankIfsc,
    this.upiId,
    this.upiDisplayNumber,
  });

  final String name;
  final String? tagline;
  final String? address;
  final String? gstin;
  final String? pan;

  /// Primary first, then secondary/tertiary/quaternary — already deduped
  /// and trimmed of blanks by [resolve].
  final List<String> phones;
  final String? landline;
  final String? udyamNo;
  final String? affiliationText;
  final String? branchListText;
  final String? website;
  final String? email;
  final String? signatoryName;
  final String? signatoryImageUrl;
  final String? beneficiaryName;
  final String? bankName;
  final String? bankAccountNo;
  final String? bankIfsc;
  final String? upiId;
  final String? upiDisplayNumber;

  static String? _s(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  /// [businessProfile] is the org's `settings` row keyed 'business_profile'
  /// (decoded jsonb map) — pass `const {}` when unavailable. [legacyESignUrl]
  /// is the separate `settings` key 'signature_url' (the drawn e-sign PNG,
  /// never part of the business_profile blob) — pass null when unavailable.
  factory OrgProfile.resolve(
    OrganizationsRow? org, {
    Map<String, dynamic> businessProfile = const {},
    String? legacyESignUrl,
  }) {
    String? bp(String key) => _s(businessProfile[key]);
    final phones = <String>{
      ...[_s(org?.phone) ?? bp('phone1')].whereType<String>(),
      ...[_s(org?.phoneSecondary) ?? bp('phone2')].whereType<String>(),
      ...[_s(org?.phoneTertiary)].whereType<String>(),
      ...[_s(org?.phoneQuaternary)].whereType<String>(),
    }.toList();

    return OrgProfile(
      name: org?.name ?? '',
      tagline: _s(org?.tagline) ?? bp('tagline'),
      address: _s(org?.address) ?? bp('address'),
      gstin: _s(org?.gstin) ?? bp('gstin'),
      pan: _s(org?.pan) ?? bp('pan'),
      phones: phones,
      landline: _s(org?.landline),
      udyamNo: _s(org?.udyamNo),
      affiliationText: _s(org?.affiliationText),
      branchListText: _s(org?.branchListText),
      website: _s(org?.website) ?? bp('website'),
      email: _s(org?.supportEmail) ?? bp('email'),
      signatoryName: _s(org?.signatoryName),
      signatoryImageUrl: _s(org?.signatoryImageUrl) ?? legacyESignUrl,
      beneficiaryName: _s(org?.beneficiaryName),
      bankName: _s(org?.bankName) ?? bp('bank_name'),
      bankAccountNo: _s(org?.bankAccountNo) ?? bp('account_no'),
      bankIfsc: _s(org?.bankIfsc) ?? bp('ifsc'),
      upiId: _s(org?.upiId) ?? bp('upi_id'),
      upiDisplayNumber: _s(org?.upiDisplayNumber),
    );
  }
}

/// Tenant-editable document boilerplate — `app_settings` rows, category
/// 'documents' (migration 006/009). Seeded per org by migration 009 with
/// the defaults shown here as fallback text, so a document still renders
/// sensibly in the (should-never-happen, seed runs per org) case the row
/// is missing rather than printing a blank.
class DocumentBoilerplate {
  const DocumentBoilerplate({
    this.docFooterText = 'This is a computer-generated document. '
        'SAVE PAPER - SAVE TREES | BE DIGITAL - GO GREEN',
    this.lrNoticeText = 'The consignment by the lorry receipt shall be '
        'stored at the destination under the control of the transport '
        'operator and shall be delivered to the order of the consignee '
        'whose name is mentioned in the lorry receipt. It will under no '
        'circumstances be delivered to anyone without written '
        'authorization from the consignee on its order.',
    this.demurrageFreeDays = 5,
    this.demurrageRatePerDay = 500,
    this.demurrageText = 'Demurrage charge after more than {days} day(s) '
        '@ Rs.{rate} per day + handling & local transportation charges.',
    this.goodsDescriptionDefault =
        'Old and Used Household Goods For Personal Usage Only, Not For Sale',
    this.invoiceNote = 'Please keep your Cash/Jewellery and all important '
        'documents in your Custody/Lock. Carrying Liquor, Gas Cylinder, '
        'Acid of any type of Liquids (like Ghee Tin, Oil etc.) is totally '
        'prohibited.',
    this.quotationTerms = const [],
  });

  final String docFooterText;
  final String lrNoticeText;
  final int demurrageFreeDays;
  final int demurrageRatePerDay;
  final String demurrageText;
  final String goodsDescriptionDefault;
  final String invoiceNote;
  final List<String> quotationTerms;

  /// The demurrage sentence with {days}/{rate} substituted.
  String get demurrageSentence => demurrageText
      .replaceAll('{days}', demurrageFreeDays.toString())
      .replaceAll('{rate}', demurrageRatePerDay.toString());

  /// [rows] is every `app_settings` row for this org with
  /// `category = 'documents'`, keyed by `key`.
  factory DocumentBoilerplate.resolve(List<AppSettingsRow> rows) {
    String? str(String key) {
      final row = rows.where((r) => r.key == key).firstOrNull;
      final v = row?.value;
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? intVal(String key) {
      final row = rows.where((r) => r.key == key).firstOrNull;
      final v = row?.value;
      if (v == null) return null;
      if (v is num) return v.round();
      return int.tryParse(v.toString());
    }

    const fallback = DocumentBoilerplate();
    return DocumentBoilerplate(
      docFooterText: str('doc_footer_text') ?? fallback.docFooterText,
      lrNoticeText: str('lr_notice_text') ?? fallback.lrNoticeText,
      demurrageFreeDays:
          intVal('demurrage_free_days') ?? fallback.demurrageFreeDays,
      demurrageRatePerDay:
          intVal('demurrage_rate_per_day') ?? fallback.demurrageRatePerDay,
      demurrageText: str('demurrage_text') ?? fallback.demurrageText,
      goodsDescriptionDefault: str('goods_description_default') ??
          fallback.goodsDescriptionDefault,
      invoiceNote: str('invoice_note') ?? fallback.invoiceNote,
      quotationTerms: (str('quotation_terms') ?? '')
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList(),
    );
  }
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

  /// Full statutory header per the Session 3 field spec (§1): an optional
  /// top strip (affiliation text left / Udyam No. right — only rendered
  /// when at least one is present), then the navy identity band with
  /// logo · name · tagline · full address · GSTIN · PAN · every phone
  /// number comma-separated · landline · website · email, and — only for
  /// documents that need it (Money Receipt) — the branch list line below
  /// the band. Reads exclusively from [org] (already-resolved,
  /// organizations-first/business_profile-fallback — see [OrgProfile]),
  /// never a second, independent fallback.
  static pw.Widget headerFull({
    required OrgProfile org,
    required String docLabel,
    required PdfFonts fonts,
    Uint8List? logoBytes,
    bool showBranchList = false,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if ((org.affiliationText ?? '').isNotEmpty ||
            (org.udyamNo ?? '').isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(org.affiliationText ?? '',
                    style: pw.TextStyle(
                        font: fonts.regular, fontSize: 7.5, color: grey)),
                if ((org.udyamNo ?? '').isNotEmpty)
                  pw.Text('Udyam No: ${org.udyamNo}',
                      style: pw.TextStyle(
                          font: fonts.regular, fontSize: 7.5, color: grey)),
              ],
            ),
          ),
        pw.Container(
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
                  child:
                      pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(width: 12),
              ],
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(org.name.toUpperCase(),
                        style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 16,
                            color: PdfColors.white)),
                    if ((org.tagline ?? '').isNotEmpty)
                      pw.Text(org.tagline!,
                          style: pw.TextStyle(
                              font: fonts.regular, fontSize: 9, color: gold)),
                    if ((org.address ?? '').isNotEmpty)
                      pw.Text(org.address!,
                          style: pw.TextStyle(
                              font: fonts.regular,
                              fontSize: 8,
                              color: PdfColors.grey300)),
                    pw.Text(
                      [
                        if (org.phones.isNotEmpty)
                          'Ph: ${org.phones.join(', ')}',
                        if ((org.landline ?? '').isNotEmpty)
                          'Landline: ${org.landline}',
                        if ((org.website ?? '').isNotEmpty) org.website!,
                        if ((org.email ?? '').isNotEmpty) org.email!,
                      ].join('  |  '),
                      style: pw.TextStyle(
                          font: fonts.regular,
                          fontSize: 8,
                          color: PdfColors.grey300),
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(docLabel,
                      style: pw.TextStyle(
                          font: fonts.bold, fontSize: 13, color: gold)),
                  if ((org.gstin ?? '').isNotEmpty)
                    pw.Text('GSTIN: ${org.gstin}',
                        style: pw.TextStyle(
                            font: fonts.regular,
                            fontSize: 8.5,
                            color: PdfColors.white)),
                  if ((org.pan ?? '').isNotEmpty)
                    pw.Text('PAN: ${org.pan}',
                        style: pw.TextStyle(
                            font: fonts.regular,
                            fontSize: 8.5,
                            color: PdfColors.white)),
                ],
              ),
            ],
          ),
        ),
        if (showBranchList && (org.branchListText ?? '').isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(org.branchListText!,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: fonts.regular, fontSize: 7.5)),
          ),
      ],
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

  /// Footer per the Session 3 field spec (§1): the tenant's own
  /// `doc_footer_text` (from [boilerplate], `app_settings` category
  /// 'documents' — see [DocumentBoilerplate]), then "For Any Query
  /// contact us: {phones}" from [org]. Distinct from [footer] (which the
  /// pre-Session-3 Survey/Quote/SimpleDocument PDFs already use and keep
  /// using) — this is the statutory footer for the four rebuilt documents.
  static pw.Widget footerFull(
    PdfFonts fonts, {
    required OrgProfile org,
    required DocumentBoilerplate boilerplate,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Divider(color: PdfColors.grey400, thickness: .5),
        pw.Text(
          boilerplate.docFooterText,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: fonts.bold, fontSize: 8, color: navy),
        ),
        if (org.phones.isNotEmpty)
          pw.Text(
            'For Any Query contact us: ${org.phones.join(', ')}',
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
