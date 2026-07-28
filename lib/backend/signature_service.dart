import 'dart:convert';
import 'dart:typed_data';

import '/backend/supabase/supabase.dart';
import '/backend/supabase/org_scope.dart';
import '/config/app_config.dart';

/// Signature-request helpers shared by the quote and invoice screens
/// (live-test fix brief #2, item 3).
///
/// Writes go direct to `document_signatures` (org-scoped, RLS-protected,
/// authenticated staff session). Only the *customer-facing* read/write
/// goes through the `sign-document` Edge Function, since that runs with
/// no session at all.
class SignatureRequest {
  const SignatureRequest({
    required this.id,
    required this.token,
    required this.status,
    this.customerName,
    this.signedAt,
    this.signatureData,
  });

  final String id;
  final String token;
  final String status; // pending | signed | declined
  final String? customerName;
  final DateTime? signedAt;

  /// base64 PNG, present once signed.
  final String? signatureData;

  bool get isSigned => status == 'signed';

  /// Decoded signature bytes for embedding in a PDF, or null if unsigned
  /// or the stored value isn't decodable.
  Uint8List? get signatureBytes {
    final raw = signatureData;
    if (raw == null || raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  /// Public link to hand to the customer. Built from [kPublicBaseUrl] —
  /// never from Uri.base, which is file:/// inside an APK (item 1).
  String get link => buildTokenLink('/sign', token);
}

class SignatureService {
  static const String _table = 'document_signatures';

  /// Existing request for a document, or null.
  static Future<SignatureRequest?> find({
    required String documentType, // 'quote' | 'invoice'
    required String documentId,
  }) async {
    final rows = await SupaFlow.client
        .from(_table)
        .select()
        .eq('document_type', documentType)
        .eq('document_id', documentId)
        .limit(1);
    if (rows.isEmpty) return null;
    return _fromRow(Map<String, dynamic>.from(rows.first));
  }

  /// Returns the existing request for this document, creating one if
  /// there isn't one yet.
  ///
  /// Deliberately reuses rather than minting a second token: the table has
  /// a unique index on (org_id, document_type, document_id) precisely so
  /// an old link can't stay signable after a new one is issued. Re-sending
  /// therefore re-sends the *same* link.
  static Future<SignatureRequest> getOrCreate({
    required String documentType,
    required String documentId,
    String? customerName,
  }) async {
    final existing = await find(
      documentType: documentType,
      documentId: documentId,
    );
    if (existing != null) return existing;

    final inserted = await SupaFlow.client
        .from(_table)
        .insert({
          ...OrgScope.stamp(),
          'document_type': documentType,
          'document_id': documentId,
          if (customerName != null && customerName.trim().isNotEmpty)
            'customer_name': customerName.trim(),
          // sign_token and status have DB defaults
          // (see 20260728_public_links_sign_and_track.sql).
        })
        .select()
        .limit(1)
        .single();
    return _fromRow(Map<String, dynamic>.from(inserted));
  }

  static SignatureRequest _fromRow(Map<String, dynamic> r) => SignatureRequest(
        id: r['id'] as String,
        token: (r['sign_token'] as String?) ?? '',
        status: (r['status'] as String?) ?? 'pending',
        customerName: r['customer_name'] as String?,
        signedAt: r['signed_at'] == null
            ? null
            : DateTime.tryParse(r['signed_at'] as String),
        signatureData: r['signature_data'] as String?,
      );
}
