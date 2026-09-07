import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';

/// Keeps a copy of every document the vendor ISSUES.
///
/// Built 7 Sept 2026 for the customer document hub (option A: a token
/// link, not customer logins). Until now this app generated every PDF on
/// demand and stored none of them — `documents` has existed, purpose-
/// built, with nothing ever writing to it.
///
/// **Storing an issued document is more correct than regenerating it,
/// and that is the real argument — not the customer link.** An invoice is
/// immutable once issued. Regenerating one months later reads TODAY's
/// order row, so a corrected address, an added charge or a changed GST
/// rate would silently produce a different document from the one the
/// customer holds and signed. A stored copy cannot drift. The link is
/// what made the gap visible; it is not the only reason to close it.
///
/// **Failures never break document generation.** A vendor pressing
/// "Generate Invoice" wants an invoice; a storage outage must not stop
/// them handing one to a customer standing in front of them. Every call
/// here is best-effort and returns null on failure rather than throwing,
/// which is why the return value is worth checking but never required.
class IssuedDocuments {
  IssuedDocuments._();

  static const String bucket = 'order-documents';

  /// Stores [bytes] as this order's [docType] document.
  ///
  /// Returns the storage path, or null if anything failed.
  ///
  /// **Re-issuing REPLACES rather than accumulating.** Generating an
  /// invoice twice is routine — the number is cached and reused, so the
  /// second PDF is the same document, not a new one. Keeping both would
  /// show the customer two identical invoices and leave them guessing
  /// which is current.
  static Future<String?> storeForOrder({
    required String orderId,
    required String docType,
    required String fileName,
    required Uint8List bytes,
  }) =>
      _store(
          entityType: 'order',
          entityId: orderId,
          docType: docType,
          fileName: fileName,
          bytes: bytes);

  /// Stores a QUOTATION's PDF.
  ///
  /// Kept against the quotation rather than an order because at quote
  /// time there IS no order — the whole point of a quote is that the job
  /// has not been booked. `documents.entity_type` is generic, so this
  /// needs no schema change, and `public_get_order_documents` picks it up
  /// through the order's own `quotation_id` once the lead converts.
  ///
  /// Consequence worth knowing: the customer sees their quote on the
  /// tracking link only AFTER the order exists. A quote sent to someone
  /// who never books is stored but never surfaced, which is correct —
  /// there is no order to hang a link off.
  static Future<String?> storeForQuotation({
    required String quotationId,
    required String fileName,
    required Uint8List bytes,
  }) =>
      _store(
          entityType: 'quotation',
          entityId: quotationId,
          docType: 'quote',
          fileName: fileName,
          bytes: bytes);

  static Future<String?> _store({
    required String entityType,
    required String entityId,
    required String docType,
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      final orgId = OrgScope.stamp()['org_id'] as String?;
      if (orgId == null || orgId.isEmpty) return null;

      // Path: org / order / doctype.pdf
      //
      // Stable per (order, doc type) so a re-issue overwrites in place —
      // no orphaned file, no second row, and the customer's link keeps
      // working because the URL never changes.
      //
      // The bucket is public but nothing is listable, and an order id is
      // not guessable from outside, so a path cannot be walked to.
      final path = '$orgId/$entityId/$docType.pdf';

      await SupaFlow.client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              // Re-issue overwrites; see above.
              upsert: true,
            ),
          );

      // The row is what the customer's link reads — the file alone is
      // invisible to it. Written AFTER the upload so a failed upload
      // cannot leave a row pointing at nothing.
      final existing = await SupaFlow.client
          .from('documents')
          .select('id')
          .eq('entity_type', entityType)
          .eq('entity_id', entityId)
          .eq('doc_type', docType)
          .filter('deleted_at', 'is', null)
          .limit(1);

      final payload = <String, dynamic>{
        ...OrgScope.stamp(),
        'entity_type': entityType,
        'entity_id': entityId,
        'doc_type': docType,
        'file_name': fileName,
        'storage_path': path,
        'mime_type': 'application/pdf',
        'size_bytes': bytes.length,
        // Customer-facing by construction: these are the papers the
        // customer is entitled to. An internal attachment stored here
        // later must set this true, which is what the public reader
        // filters on.
        'is_sensitive': false,
      };

      if (existing is List && existing.isNotEmpty) {
        await SupaFlow.client
            .from('documents')
            .update(payload)
            .eq('id', (existing.first as Map)['id']);
      } else {
        await SupaFlow.client.from('documents').insert(payload);
      }
      return path;
    } catch (_) {
      // Deliberately silent to the caller. See the class doc: issuing the
      // document is the job, keeping a copy is the bonus.
      return null;
    }
  }
}
