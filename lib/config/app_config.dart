/// App-wide configuration constants.
///
/// Created 28 Jul 2026 for live-test fix brief #2, Item 1 (blocker).
library;

/// Public web origin used to build customer-facing links (survey, quote,
/// signature, order tracking) that are shared over WhatsApp/SMS.
///
/// **Never derive this from `Uri.base`.** That was the original bug: on
/// Flutter *web* `Uri.base` is the page URL so `Uri.base.origin` works, but
/// inside an installed APK `Uri.base` is `file:///` and `.origin` throws
///
///     Bad state: Origin is only applicable schemes http and https: file:///
///
/// which is exactly what the "Could not create survey link" toast was
/// reporting on device. The link-building code had only ever run on web.
///
/// Overridable at build time without touching source, for staging builds:
///
///     flutter build apk --dart-define=NAGARVA_PUBLIC_BASE_URL=https://staging.nagarva.in
///
/// If per-tenant custom domains are ever added, read the org's configured
/// domain from settings and fall back to this constant.
const String kPublicBaseUrl = String.fromEnvironment(
  'NAGARVA_PUBLIC_BASE_URL',
  defaultValue: 'https://nagarva.in',
);

/// Builds a customer-facing shareable link.
///
/// [path] is a route path with a leading slash (e.g. `/survey`), matching
/// the public route prefixes registered in `lib/flutter_flow/nav/nav.dart`.
///
/// Use this rather than string-concatenating [kPublicBaseUrl] at each call
/// site, so trailing-slash handling and query encoding stay consistent.
String buildPublicLink(
  String path, {
  Map<String, String> params = const {},
}) {
  final base = kPublicBaseUrl.endsWith('/')
      ? kPublicBaseUrl.substring(0, kPublicBaseUrl.length - 1)
      : kPublicBaseUrl;
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  if (params.isEmpty) return '$base$normalizedPath';
  final query = params.entries
      .map((e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  return '$base$normalizedPath?$query';
}

/// Convenience wrapper for the token-keyed public links (survey, quote,
/// sign, track) — they all share the `?token=<token>` shape.
String buildTokenLink(String path, String token) =>
    buildPublicLink(path, params: {'token': token});

/// Builds a `wa.me` deep link that opens WhatsApp with [message]
/// pre-filled (fix brief #2, items 3 and 6 — "WhatsApp-first" sharing).
///
/// [phone] may be in any local format; non-digits are stripped and a bare
/// 10-digit Indian number gets a 91 country code, since that is what the
/// app's own phone fields hold. Pass null to open the WhatsApp share
/// sheet with no recipient chosen.
///
/// Note this is the plain consumer-app deep link, deliberately NOT the
/// AiSensy Business API — CLAUDE.md's Phase 4 rule is that AiSensy is
/// only ever called from a Supabase Edge Function so the API key never
/// ships in the APK. This just opens the user's own WhatsApp.
String buildWhatsAppLink({String? phone, required String message}) {
  final encoded = Uri.encodeComponent(message);
  final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return 'https://wa.me/?text=$encoded';
  final withCode = digits.length == 10 ? '91$digits' : digits;
  return 'https://wa.me/$withCode?text=$encoded';
}
