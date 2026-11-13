import '/backend/quote_design.dart';
import '/backend/supabase/org_scope.dart';
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
    this.city,
    this.state,
    this.stateCode,
    this.pincode,
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

  /// City / state / state code / PIN, kept separate from [address]
  /// because Rule 46 and the place-of-supply rules need them
  /// individually, not as one blob.
  ///
  /// **`state_code` does NOT decide CGST+SGST vs IGST.** This comment
  /// claimed it did until 10 Sept 2026. The split is computed from the
  /// ORDER's own cities — `isInterState(_orderFromCity, _orderToCity)`,
  /// `order_detail_page_widget.dart:941` — and never reads this field.
  /// `state_code` reaches exactly two places: the LR's address line, and
  /// `invoiceComplianceIssues`, which lists it as a Rule 46 required
  /// field and cross-checks it against the GSTIN's leading two digits.
  /// Counted 10 Sept 2026: null on all three orgs, and no tax figure
  /// moves because of it.
  ///
  /// Whether origin-city vs destination-city is the RIGHT test is a tax
  /// question for Arun's CA, not a code one — place of supply for goods
  /// transport normally turns on the supplier's registration state
  /// rather than the pickup city. Flagged 10 Sept 2026, not changed.
  final String? city;
  final String? state;
  final int? stateCode;
  final String? pincode;
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
      city: _s(org?.city) ?? bp('city'),
      state: _s(org?.state) ?? bp('state'),
      // int, so no trim - but a blank/garbage jsonb value must not become
      // a wrong state code: it would print the wrong state on the LR's
      // address line and either silence a real GSTIN mismatch or invent a
      // false one. It does NOT flip CGST/SGST to IGST — that claim was
      // wrong here too, corrected 10 Sept 2026; see the note on [city].
      stateCode: org?.stateCode ?? int.tryParse(bp('state_code') ?? ''),
      pincode: _s(org?.pincode) ?? bp('pincode'),
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
/// The terms every document carries until the vendor writes their own.
///
/// **These are OPERATIONAL statements, not a liability position.** Each
/// one describes what the mover does or what the customer must do — the
/// deliberate choice being that a SaaS product must not draft the legal
/// terms governing a vendor's exposure. A default indemnity or liability
/// cap would be this app deciding, on a vendor's behalf and without their
/// lawyer, what they are on the hook for.
///
/// That is the same reasoning as "No suggested money. Ever." applied to
/// words instead of figures: a plausible default is indistinguishable
/// from a decision once printed, and these get printed on documents that
/// settle disputes.
///
/// Overridden per tenant by `app_settings` key `document_terms`, one
/// term per line.
const List<String> kDefaultStandardTerms = [
  'Goods are accepted for transport at the owner\'s risk unless transit '
      'insurance has been arranged separately and is stated on this '
      'document.',
  'Any shortage or damage must be reported to us in writing within 48 '
      'hours of delivery, with the consignment note number.',
  'Cash, jewellery, documents and other valuables must be retained by the '
      'customer and are not accepted for transport.',
  'Delivery dates are estimates and may be affected by traffic, weather, '
      'permits or conditions outside our control.',
  'Payment is due as agreed on the quotation. Goods may be held until '
      'payment of the agreed amount is received.',
];

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

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
    // CORRECTIONS.md A4: no invented money. Free days and the daily rate
    // are the vendor's own figures (app_settings); unset prints nothing.
    this.demurrageFreeDays,
    this.demurrageRatePerDay,
    this.demurrageText = 'Demurrage charge after more than {days} day(s) '
        '@ Rs.{rate} per day + handling & local transportation charges.',
    this.goodsDescriptionDefault =
        'Old and Used Household Goods For Personal Usage Only, Not For Sale',
    this.invoiceNote = 'Please keep your Cash/Jewellery and all important '
        'documents in your Custody/Lock. Carrying Liquor, Gas Cylinder, '
        'Acid of any type of Liquids (like Ghee Tin, Oil etc.) is totally '
        'prohibited.',
    this.quotationTerms = const [],
    this.standardTerms = kDefaultStandardTerms,
  });

  final String docFooterText;
  final String lrNoticeText;
  final int? demurrageFreeDays;
  final int? demurrageRatePerDay;
  final String demurrageText;
  final String goodsDescriptionDefault;
  final String invoiceNote;
  final List<String> quotationTerms;

  /// The short terms printed on EVERY document.
  ///
  /// Arun, 7 Sept 2026: "i need the basic terms and conditons in all
  /// documents ... by deafult".
  ///
  /// Distinct from [quotationTerms], which is the long list on the
  /// quotation's own third page. These are the four or five lines that
  /// belong on an invoice, a receipt, an LR and a POD alike.
  ///
  /// **Tenant-editable, and they should be edited.** Sourced from
  /// `app_settings` key `document_terms`, one per line, falling back to
  /// [kDefaultStandardTerms]. See that constant for why the shipped set
  /// is worded the way it is.
  final List<String> standardTerms;

  /// The demurrage sentence with {days}/{rate} substituted, or '' when
  /// the vendor has not set both figures — a sentence quoting a rate
  /// nobody chose is worse than no sentence.
  String get demurrageSentence {
    final days = demurrageFreeDays;
    final rate = demurrageRatePerDay;
    if (days == null || rate == null || rate <= 0) return '';
    return demurrageText
        .replaceAll('{days}', days.toString())
        .replaceAll('{rate}', rate.toString());
  }

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
      goodsDescriptionDefault:
          str('goods_description_default') ?? fallback.goodsDescriptionDefault,
      invoiceNote: str('invoice_note') ?? fallback.invoiceNote,
      standardTerms: (str('document_terms') ?? '')
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList()
          .let((v) => v.isEmpty ? fallback.standardTerms : v),
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
  static Future<PdfFonts> loadFonts() async {
    await refreshDesign();
    return PdfFonts(
      regular: await PdfGoogleFonts.notoSansRegular(),
      bold: await PdfGoogleFonts.notoSansBold(),
    );
  }

  // ---- Document design (13 Nov 2026) ----------------------------------
  //
  // Arun: "if all vendors share the same design of document they might
  // feel the same vendor is sharing in a different name, so we need
  // multiple designs and layouts."
  //
  // The quotation already had six layouts and a brand colour (Settings >
  // Quote design). Every OTHER document - invoice, LR, money receipt,
  // proforma, packing list, the declarations, credit note, survey -
  // printed one fixed navy band. They now follow the same saved choice:
  // six header layouts, each in the vendor's colour, and the tables,
  // totals and headings take that colour too.
  //
  // A company that never chose keeps the navy band exactly as before.
  //
  // Read once per document by [loadFonts], which every generator already
  // awaits first, so no generator had to learn a new step.

  /// The design the documents being generated right now use.
  static QuoteDesign design = QuoteDesign.standard;

  /// Set in tests and by the Settings preview to try a design without
  /// saving it; while set, nothing is read from the database.
  static QuoteDesign? designOverride;

  static String? _designOrg;
  static DateTime? _designAt;

  static Future<void> refreshDesign() async {
    final o = designOverride;
    if (o != null) {
      design = o;
      return;
    }
    try {
      final org = OrgScope.currentOrgId;
      if (org == null) {
        design = QuoteDesign.standard;
        return;
      }
      final fresh = _designOrg == org &&
          _designAt != null &&
          DateTime.now().difference(_designAt!) < const Duration(seconds: 30);
      if (fresh) return;
      design = await QuoteDesign.load();
      _designOrg = org;
      _designAt = DateTime.now();
    } catch (_) {
      // No session (tests) or no network: print the standard design.
      design = QuoteDesign.standard;
    }
  }

  /// Call after the design is saved so the next document reads it afresh.
  static void forgetDesign() {
    _designOrg = null;
    _designAt = null;
  }

  static bool get _standard =>
      design.theme == QuoteDesign.standard.theme &&
      design.color == QuoteDesign.standard.color;

  /// The vendor's colour: headings, table headers, total boxes.
  static PdfColor get primary =>
      _standard ? navy : PdfColor.fromInt(design.colorValue);

  /// Text on a [primary] block. Gold belongs to the navy band only.
  static PdfColor get accent => _standard ? gold : PdfColors.white;

  /// A pale wash of [primary] for alternate rows and panels.
  static PdfColor get tint {
    if (_standard) return lightRow;
    final c = primary;
    double mix(double v) => v + (1 - v) * 0.93;
    return PdfColor(mix(c.red), mix(c.green), mix(c.blue));
  }

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
    return _header(
      fonts: fonts,
      logoBytes: logoBytes,
      name: orgName,
      tagline: p(profile, 'tagline'),
      address: p(profile, 'address'),
      contact: [
        if (p(profile, 'phone1').isNotEmpty) 'Ph: ${p(profile, 'phone1')}',
        if (p(profile, 'phone2').isNotEmpty) p(profile, 'phone2'),
        if (p(profile, 'email').isNotEmpty) p(profile, 'email'),
      ].join('  |  '),
      docLabel: docLabel,
      ids: [
        if (p(profile, 'gstin').isNotEmpty) 'GSTIN: ${p(profile, 'gstin')}',
      ],
    );
  }

  /// One header, six layouts (the quotation's theme ids, so one choice in
  /// Settings dresses every document):
  ///   1a Classic     name in colour on white, rule under
  ///   1b Bold band   full colour band (the original)
  ///   1c Sidebar     thick colour bar down the left, pale panel
  ///   1d Minimal     black on white, hairline
  ///   1e Corporate   colour strip on top, label in a colour box
  ///   1f Letterhead  centred name, label centred between rules
  static pw.Widget _header({
    required PdfFonts fonts,
    required Uint8List? logoBytes,
    required String name,
    required String tagline,
    required String address,
    required String contact,
    required String docLabel,
    required List<String> ids,
    PdfColor? bandColor,
  }) {
    final theme = bandColor != null ? '1b' : design.theme;
    final col = bandColor ?? primary;
    final onBand = theme == '1b';
    final hi = bandColor != null
        ? (bandColor == navy ? gold : PdfColors.white)
        : accent;
    const dark = PdfColor.fromInt(0xFF1A1A1A);
    final nameColor = onBand ? PdfColors.white : (theme == '1e' ? dark : col);
    final subColor = onBand ? PdfColors.grey300 : grey;

    pw.Widget? logo({double size = 52}) => logoBytes == null
        ? null
        : pw.Container(
            width: size,
            height: size,
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            padding: const pw.EdgeInsets.all(4),
            child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
          );

    List<pw.Widget> identity(pw.TextAlign align) => [
          pw.Text(name.toUpperCase(),
              textAlign: align,
              style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: theme == '1f' ? 18 : 16,
                  color: nameColor)),
          if (tagline.isNotEmpty)
            pw.Text(tagline,
                textAlign: align,
                style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 9,
                    color: onBand ? hi : grey)),
          if (address.isNotEmpty)
            pw.Text(address,
                textAlign: align,
                style: pw.TextStyle(
                    font: fonts.regular, fontSize: 8, color: subColor)),
          if (contact.isNotEmpty)
            pw.Text(contact,
                textAlign: align,
                style: pw.TextStyle(
                    font: fonts.regular, fontSize: 8, color: subColor)),
        ];

    List<pw.Widget> idLines(PdfColor c) => [
          for (final t in ids)
            pw.Text(t,
                style: pw.TextStyle(
                    font: fonts.regular, fontSize: 8.5, color: c)),
        ];

    // The row every side-by-side layout shares: logo, identity, label.
    pw.Widget row(pw.Widget label) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logoBytes != null) ...[logo()!, pw.SizedBox(width: 12)],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: identity(pw.TextAlign.left),
              ),
            ),
            pw.SizedBox(width: 10),
            label,
          ],
        );

    pw.Widget plainLabel(PdfColor c, PdfColor idc) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(docLabel,
                style: pw.TextStyle(font: fonts.bold, fontSize: 13, color: c)),
            ...idLines(idc),
          ],
        );

    switch (theme) {
      case '1a': // Classic
        return pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: col, width: 2)),
          ),
          child: row(plainLabel(col, dark)),
        );
      case '1c': // Sidebar
        return pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: pw.BoxDecoration(
            color: tint,
            border: pw.Border(left: pw.BorderSide(color: col, width: 8)),
          ),
          child: row(plainLabel(col, dark)),
        );
      case '1d': // Minimal
        return pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey600, width: .6)),
          ),
          child: row(plainLabel(dark, dark)),
        );
      case '1e': // Corporate
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(height: 6, color: col),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              color: const PdfColor.fromInt(0xFFF4F5F7),
              child: row(pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: pw.BoxDecoration(
                      color: col,
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                    child: pw.Text(docLabel,
                        style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 11.5,
                            color: PdfColors.white)),
                  ),
                  pw.SizedBox(height: 4),
                  ...idLines(dark),
                ],
              )),
            ),
          ],
        );
      case '1f': // Letterhead
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (logoBytes != null) ...[
              pw.Center(child: logo(size: 46)),
              pw.SizedBox(height: 6),
            ],
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: identity(pw.TextAlign.center),
            ),
            pw.SizedBox(height: 8),
            pw.Container(height: 1.5, color: col),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 5),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(ids.isEmpty ? '' : ids.first,
                        style: pw.TextStyle(
                            font: fonts.regular, fontSize: 8.5, color: dark)),
                  ),
                  pw.Text(docLabel,
                      style: pw.TextStyle(
                          font: fonts.bold,
                          fontSize: 13,
                          letterSpacing: 1.2,
                          color: col)),
                  pw.Expanded(
                    child: pw.Text(ids.length > 1 ? ids[1] : '',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                            font: fonts.regular, fontSize: 8.5, color: dark)),
                  ),
                ],
              ),
            ),
            pw.Container(height: .6, color: col),
          ],
        );
      default: // 1b Bold band
        return pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: col,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: row(plainLabel(hi, PdfColors.white)),
        );
    }
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
    /// Only the quotation passes this: it draws its own theme and
    /// wants the plain band in its colour. Everything else leaves it
    /// null and gets the company's document design.
    PdfColor? color,
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
        _header(
          fonts: fonts,
          logoBytes: logoBytes,
          name: org.name,
          tagline: org.tagline ?? '',
          address: org.address ?? '',
          contact: [
            if (org.phones.isNotEmpty) 'Ph: ${org.phones.join(', ')}',
            if ((org.landline ?? '').isNotEmpty) 'Landline: ${org.landline}',
            if ((org.website ?? '').isNotEmpty) org.website!,
            if ((org.email ?? '').isNotEmpty) org.email!,
          ].join('  |  '),
          docLabel: docLabel,
          ids: [
            if ((org.gstin ?? '').isNotEmpty) 'GSTIN: ${org.gstin}',
            if ((org.pan ?? '').isNotEmpty) 'PAN: ${org.pan}',
          ],
          bandColor: color,
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
                style: pw.TextStyle(
                    font: fonts.regular, fontSize: 9, color: grey)),
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
        // NOT "Generated by Nagarva". Arun, 7 Sept 2026: "we are
        // creating a saas product so the name should be according to the
        // vendor" — a customer of Arun Packers opening their proforma
        // and finding a company they have never heard of cannot tell
        // whether the document is genuine, and the vendor looks like
        // they are borrowing someone else's stationery.
        //
        // The line says what it needs to say (this was not hand-signed)
        // without naming anyone. Naming the VENDOR here would be wrong
        // too — the header already carries their identity, and repeating
        // it in the footer reads as a watermark.
        pw.Text(
          'This is a computer-generated document.',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: fonts.regular, fontSize: 7.5, color: grey),
        ),
      ],
    );
  }

  /// A compact terms block, for the foot of any document.
  ///
  /// Returns an empty widget when there are no terms, so a vendor who
  /// clears them gets a clean document rather than an empty heading.
  static pw.Widget termsBlock(
    PdfFonts fonts,
    List<String> terms, {
    String heading = 'TERMS & CONDITIONS',
  }) {
    if (terms.isEmpty) return pw.SizedBox();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(heading,
            style: pw.TextStyle(font: fonts.bold, fontSize: 7.5, color: navy)),
        pw.SizedBox(height: 2),
        for (var i = 0; i < terms.length; i++)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 1.5),
            child: pw.Text('${i + 1}. ${terms[i]}',
                style: pw.TextStyle(
                    font: fonts.regular, fontSize: 6.8, color: grey)),
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
            style:
                pw.TextStyle(font: fonts.regular, fontSize: 7.5, color: grey),
          ),
      ],
    );
  }

  static String fmtDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
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
