import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '/backend/supabase/supabase.dart';

/// Files that must not be reachable by anyone holding a link (BUG-013,
/// 3 Nov 2026): the authorised signatory's signature used to sit in the
/// PUBLIC `org-logos` bucket. It now lives in the private `org-private`
/// bucket (20261103_private_signature_bucket.sql), readable only by
/// members of that company.
///
/// The stored value is a reference, not a URL: `org-private:<org_id>/…`.
/// Older rows still hold a public https URL; both are read here so the
/// change needs no data migration.
const kPrivateBucket = 'org-private';
const _kRefPrefix = '$kPrivateBucket:';

bool isPrivateRef(String? v) => v != null && v.startsWith(_kRefPrefix);

String privateRef(String path) => '$_kRefPrefix$path';

/// Bytes for a stored file value: a private reference (downloaded with the
/// signed-in user's rights) or a plain URL (fetched). Null on any failure.
Future<Uint8List?> fetchFileBytes(String? value) async {
  if (value == null || value.isEmpty) return null;
  try {
    if (isPrivateRef(value)) {
      return await SupaFlow.client.storage
          .from(kPrivateBucket)
          .download(value.substring(_kRefPrefix.length));
    }
    final res = await http.get(Uri.parse(value));
    if (res.statusCode == 200) return res.bodyBytes;
  } catch (_) {}
  return null;
}
