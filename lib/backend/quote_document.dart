import 'dart:typed_data';

import '/app_session.dart';
import '/backend/gst_state_codes.dart';
import '/backend/issued_documents.dart';
import '/backend/pricing_defaults.dart';
import '/backend/quote_design.dart';
import '/backend/signature_service.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/components/pdf_branding.dart';
import '/components/quote_pdf.dart';
import '/components/survey_response_section.dart';

/// Builds the quotation PDF from a quotation row alone (13 Nov 2026).
///
/// This was a private method of the lead screen, so a quote could only be
/// printed from a lead. A walk-in quote (made from Survey & Quote with no
/// lead behind it) had no PDF anywhere in the app - which is every quote a
/// Billing only company makes, since Leads is hidden there. Found while
/// checking Arun's document list ("I want all documents generated and
/// view, download, share option within app").
///
/// One copy of the logic: the lead screen now calls this too, so the two
/// can never drift apart.
class QuoteDocument {
  QuoteDocument._();

  /// What a quotation is called everywhere a person reads it: its own
  /// number, with the revision beside it once it has been revised.
  ///
  /// 13 Nov 2026, report 3.1: the customer's page and the PDF showed the
  /// row's internal id. The number is the same through every revision;
  /// only the V changes.
  static String quoteRef(QuotationsRow q) {
    final no = (q.quoteNo ?? '').trim();
    final v = q.version ?? 1;
    final base = no.isNotEmpty
        ? no
        : (q.id.length >= 8 ? q.id.substring(0, 8).toUpperCase() : 'QUOTE');
    return v > 1 ? '$base (V$v)' : base;
  }

  /// Returns the PDF bytes and its file name. Keeps the customer's copy
  /// (best effort) exactly as the lead screen did.
  ///
  /// [leadId] / city / name / phone fill gaps for a lead-linked quote;
  /// [surveyLines] may be passed when the caller already has the survey,
  /// otherwise the quote's own survey (survey_id) is read.
  static Future<(Uint8List, String)> build(
    QuotationsRow quotation, {
    String? leadId,
    String? fromCity,
    String? toCity,
    String? fallbackName,
    String? fallbackPhone,
    List<SurveyLine>? surveyLines,
    SignatureRequest? knownSignature,
    bool detailed = false,
  }) async {
    Map<String, dynamic> profile = const {};
    try {
      final rows = await SettingsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('key', 'business_profile'),
      );
      profile = rows.isEmpty ? {} : (rows.first.valueJson ?? {});
    } catch (_) {}
    final logoBytes =
        await PdfBranding.fetchBytes(AppSession.instance.currentOrgLogoUrl);

    final charges = quotation.charges is Map
        ? Map<String, dynamic>.from(quotation.charges as Map)
        : <String, dynamic>{};
    final from = fromCity ?? quotation.fromCity;
    final to = toCity ?? quotation.toCity;
    final gstType = charges['_gstType'] as String?;
    final interstate = gstType == 'inter'
        ? true
        : gstType == 'intra'
            ? false
            : isInterState(
                quotation.fromAddress ?? from ?? '',
                quotation.toAddress ?? to ?? '',
              );

    // Re-read rather than trusting a cached signature: one captured
    // moments ago on the customer's own phone must show up here.
    SignatureRequest? sig = knownSignature;
    try {
      sig = await SignatureService.find(
            documentType: 'quote',
            documentId: quotation.id,
          ) ??
          sig;
    } catch (_) {}

    String? signatureUrl;
    try {
      final rows = await SettingsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('key', 'signature_url'),
      );
      if (rows.isNotEmpty) signatureUrl = rows.first.value;
    } catch (_) {}
    OrganizationsRow? orgRow;
    try {
      final orgId = OrgScope.currentOrgId;
      if (orgId != null) {
        final rows = await OrganizationsTable()
            .queryRows(queryFn: (q) => q.eq('id', orgId));
        if (rows.isNotEmpty) orgRow = rows.first;
      }
    } catch (_) {}
    final org = OrgProfile.resolve(orgRow,
        businessProfile: profile, legacyESignUrl: signatureUrl);

    DocumentBoilerplate boilerplate = const DocumentBoilerplate();
    try {
      final docRows = await AppSettingsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('category', 'documents'),
      );
      boilerplate = DocumentBoilerplate.resolve(docRows);
    } catch (_) {}

    String? amountInWords;
    try {
      amountInWords = await SupaFlow.client.rpc('amount_in_words',
          params: {'amt': quotation.total ?? 0}) as String?;
    } catch (_) {}

    // Moving Items table: the caller's survey, else the quote's own.
    var lines = surveyLines ?? <SurveyLine>[];
    final sid = quotation.surveyId;
    if (surveyLines == null && (sid ?? '').isNotEmpty) {
      try {
        final rows = await SurveysTable()
            .queryRows(queryFn: (q) => OrgScope.read(q).eq('id', sid!));
        if (rows.isNotEmpty) lines = parseSurveyRooms(rows.first.rooms);
      } catch (_) {}
    }

    final ref = quoteRef(quotation);

    final design = await QuoteDesign.load();
    final signed = sig?.isSigned ?? false;
    final bytes = await QuotePdf.generate(
      design: design,
      leadRef: ref,
      org: org,
      boilerplate: boilerplate,
      customerName: quotation.customer ?? fallbackName ?? 'Customer',
      customerPhone: quotation.phone ?? fallbackPhone,
      fromAddress: quotation.fromAddress,
      toAddress: quotation.toAddress,
      fromCity: from,
      toCity: to,
      charges: charges,
      subtotal: quotation.subtotal ?? 0,
      gstPct: quotation.gstPct ?? kGstDefaultPct.toDouble(),
      gstAmount: quotation.gstAmount ?? 0,
      total: quotation.total ?? 0,
      interstate: interstate,
      logoBytes: logoBytes,
      customerSignatureBytes: signed ? sig!.signatureBytes : null,
      customerSignedByName: signed ? sig!.customerName : null,
      customerSignedAt: signed ? sig!.signedAt : null,
      detailed: detailed,
      loadType: quotation.loadType,
      vehicleType: quotation.vehicleType,
      transportMode: quotation.transportMode,
      packingDate: quotation.packingDate,
      deliveryDate: quotation.deliveryDate,
      movingDate: quotation.movingDate,
      fromFloor: quotation.fromFloor,
      fromHasLift: quotation.fromHasLift,
      toFloor: quotation.toFloor,
      toHasLift: quotation.toHasLift,
      declaredValue: quotation.declaredValue,
      fovPct: quotation.fovPct,
      fovAmount: quotation.fovAmount,
      easyAccess: quotation.easyAccess,
      accessRestrictions: quotation.accessRestrictions,
      accessNotes: quotation.accessNotes,
      surveyLines: lines,
      amountInWords: amountInWords,
    );
    final file = QuotePdf.filename(
            signed ? '$ref-SIGNED' : ref, DateTime.now())
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');

    // Keep the customer's copy (Arun, 7 Sept 2026). Best effort: a
    // storage failure must never stop a quote going out.
    if (quotation.id.isNotEmpty) {
      try {
        await IssuedDocuments.storeForQuotation(
          quotationId: quotation.id,
          fileName: file,
          bytes: bytes,
        );
        // The signed copy is kept separately as the final accepted
        // version (report 4.1 / 4.2).
        if (signed && sig?.signatureBytes != null) {
          await IssuedDocuments.storeForQuotation(
            quotationId: quotation.id,
            fileName: file,
            bytes: bytes,
            signed: true,
          );
        }
      } catch (_) {}
    }
    return (bytes, file);
  }
}
