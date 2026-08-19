import 'dart:convert';
import 'dart:typed_data';

import '/app_session.dart';
import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/supervisor_job_page/supervisor_job_page_model.dart'
    show kNotAvailableReasons, kCompletionSignature, kCompletionNotAvailable;
import 'simple_document_pdf.dart';

/// Proof of Delivery document, generated ON DEMAND from `pod_records`.
///
/// Deliberately not stored anywhere (Arun, 18 Aug 2026): "the PDF is what
/// the customer asks for when there's a dispute three months later …
/// generated on demand from pod_records rather than stored — no bucket
/// needed, and it can never drift from the record."
///
/// That last point is the real argument. A stored PDF is a second copy
/// that can disagree with the row; a generated one is always a faithful
/// rendering of what the database actually holds.
///
/// The document must carry the WHOLE story on its face, because it is
/// what settles a damage dispute months later with nobody present who
/// remembers the job:
///   - the signature image, when there is one
///   - who received the goods, their phone, and their relationship to
///     the customer — a signature with no name attached is weak evidence
///   - packages delivered vs short, and any damage noted
///   - and when there is NO signature, the reason, stated plainly rather
///     than left as a silent absence
class PodPdf {
  /// Loads the POD row for [orderId] and renders it. Returns null when no
  /// `pod_records` row exists yet — the job hasn't been completed.
  static Future<Uint8List?> generateForOrder(String orderId) async {
    final rows = await OrgScope.read(SupaFlow.client
            .from('pod_records')
            .select())
        .eq('order_id', orderId)
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    final r = Map<String, dynamic>.from(rows.first as Map);

    // Branding, same source as every other document.
    Map<String, dynamic> profile = const {};
    try {
      final settings = await SettingsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('key', 'business_profile'),
      );
      if (settings.isNotEmpty && (settings.first.value ?? '').isNotEmpty) {
        final decoded = jsonDecode(settings.first.value!);
        if (decoded is Map) profile = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}

    // signature_data is a base64 PNG stored inline on the row — no
    // Storage bucket is involved, which is also why signature capture
    // works with no connectivity.
    Uint8List? signatureBytes;
    final sig = r['signature_data'] as String?;
    if (sig != null && sig.isNotEmpty) {
      try {
        signatureBytes = base64Decode(sig);
      } catch (_) {}
    }

    final method = r['completion_method'] as String?;
    final reasonKey = r['not_available_reason'] as String?;
    final deliveredAt = DateTime.tryParse('${r['delivered_at']}');
    final packagesDelivered = r['packages_delivered'];
    final packagesShort = r['packages_short'];
    final damageNoted = r['damage_noted'] == true;

    String fmt(DateTime? d) => d == null
        ? '—'
        : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year} '
            '${d.hour.toString().padLeft(2, '0')}:'
            '${d.minute.toString().padLeft(2, '0')}';

    String orNa(dynamic v) {
      final s = '${v ?? ''}'.trim();
      return s.isEmpty ? '—' : s;
    }

    // The narrative block. When nobody signed, this states it in words
    // rather than leaving an empty signature box to be interpreted.
    final notes = StringBuffer();
    if (method == kCompletionNotAvailable) {
      notes.writeln('COMPLETED WITHOUT CUSTOMER SIGNATURE');
      notes.writeln(
          'Reason: ${kNotAvailableReasons[reasonKey] ?? 'not recorded'}');
      final remarks = '${r['remarks'] ?? ''}'.trim();
      if (remarks.isNotEmpty) notes.writeln('Detail: $remarks');
      notes.writeln(
          'Recorded by ${orNa(r['captured_by'])} and pending owner review.');
    } else if (method == kCompletionSignature) {
      notes.writeln(
          'Signed at handover by ${orNa(r['received_by_name'])}'
          '${'${r['relationship'] ?? ''}'.trim().isEmpty ? '' : ' (${r['relationship']})'}.');
    }
    if (damageNoted) {
      notes.writeln('');
      notes.writeln('DAMAGE NOTED AT HANDOVER');
      notes.writeln(orNa(r['damage_description']));
    }

    return SimpleDocumentPdf.generate(
      docLabel: 'PROOF OF DELIVERY',
      docNo: orderId,
      orgName: AppSession.instance.currentOrgName ?? 'Nagarva',
      profile: profile,
      metaLeft: [
        MapEntry('Order', orderId),
        MapEntry('Delivered', fmt(deliveredAt)),
        MapEntry('Completed by', orNa(r['captured_by'])),
      ],
      // Phone and relationship only mean anything when somebody actually
      // received the goods. Printing them on an unsigned POD produced
      // "Relationship: self" opposite "Received by: —" (APC-1002, 19 Aug
      // 2026 emulator pass) — a contradiction on the face of the document.
      // The write path no longer stores that default, but rows written
      // before the fix still carry it, so this suppresses it at render
      // time too rather than trusting the data.
      metaRight: method == kCompletionSignature
          ? [
              MapEntry('Received by', orNa(r['received_by_name'])),
              MapEntry('Phone', orNa(r['received_by_phone'])),
              MapEntry('Relationship', orNa(r['relationship'])),
            ]
          : [
              MapEntry('Received by', orNa(r['received_by_name'])),
            ],
      tableHeaders: const ['Item', 'Detail'],
      tableRows: [
        ['Packages delivered', '${packagesDelivered ?? 0}'],
        ['Packages short', '${packagesShort ?? 0}'],
        ['Damage noted', damageNoted ? 'YES' : 'No'],
        [
          'Completion method',
          method == kCompletionSignature
              ? 'Customer signature'
              : method == kCompletionNotAvailable
                  ? 'No signature — ${kNotAvailableReasons[reasonKey] ?? 'reason not recorded'}'
                  : 'Legacy OTP confirmation',
        ],
      ],
      signatureBytes: signatureBytes,
      signatureLabel: signatureBytes != null
          ? 'Received by ${orNa(r['received_by_name'])}'
          : 'No customer signature captured',
      notesBlock: notes.isEmpty ? null : notes.toString().trim(),
      footerNote:
          'Generated from the delivery record on ${fmt(DateTime.now())}.',
    );
  }
}
