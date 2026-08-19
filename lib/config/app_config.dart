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
  defaultValue: 'https://link.nagarva.in',
);

/// Web origin Supabase Auth should redirect to after a confirmation or
/// password-reset email. Pass this explicitly on every client-side auth
/// call that sends an email (`signUp()`'s `emailRedirectTo`,
/// `resetPasswordForEmail()`'s `redirectTo`) rather than relying on the
/// Auth dashboard's Site URL default — see the 16 Aug 2026 redirect-issue
/// report for why that default can't be trusted blindly. Requires this
/// exact URL to be present in Supabase's Redirect URLs allow-list, or
/// GoTrue silently falls back to Site URL instead of rejecting the call.
///
/// 17 Aug 2026: changed from the Flutter web build (nagarva.netlify.app,
/// set 16 Aug 2026 when this session's own read of link.nagarva.in found
/// a 404 at root — that read was of a pre-deploy state) to link.nagarva.in
/// now that its relay page is confirmed live: renders "Email confirmed"
/// and forwards the full URL fragment to `nagarva://auth-callback`
/// (AndroidManifest.xml's intent-filter, handled by
/// backend/auth_deep_link.dart) — the actual trigger for this app's
/// native auto-login path. Not [kPublicBaseUrl] — that constant is for
/// customer-facing shareable links (survey/quote/track), a separate
/// concern that happens to be hosted on the same domain.
///
/// 17 Aug 2026 (later): moved from the domain root to `/auth` — link.
/// nagarva.in turned out to be serving the Flutter *web build* of this
/// repo (the `/survey`, `/sign`, `/track` public routes), and a
/// drag-drop deploy of just this relay page had silently replaced the
/// whole site, taking those three routes down. Restored as: Flutter web
/// build at root, this static relay page moved to `web/auth/index.html`
/// (copied verbatim, unchanged) so it coexists — see `web/_redirects`.
/// The Supabase Auth "Site URL" and Redirect URLs allow-list both need
/// this exact `/auth` path, not the bare domain, or GoTrue either
/// rejects the redirect or silently falls back to Site URL and a
/// confirmation link lands on the Flutter SPA instead of this page.
///
/// Keep supabase/functions/admin-reset-owner-password/index.ts's
/// RESET_REDIRECT_TO in sync — same value by convention, can't share the
/// literal across Dart/Deno.
const String kAuthRedirectUrl = 'https://link.nagarva.in/auth';

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

/// Canonical legal URLs, used by BOTH the signup agreement checkbox and
/// Settings → Help & About.
///
/// Moved here 18 Aug 2026 when Help & About was built — they were
/// top-level consts in `signup_page_widget.dart`, and duplicating them
/// into a second screen would have meant two places to update when a URL
/// changes. `kSignupTermsUrl`/`kSignupPrivacyUrl` still exist there as
/// aliases so the signup screen's own code reads unchanged.
///
/// Confirmed live 12 Aug 2026: bare `nagarva.in/terms` 301s to the `www`
/// host on Netlify. The redirect works, but Arun gave the `www` URLs as
/// canonical, so these point straight at them rather than taking the hop.
///
/// **Play Store requires the privacy policy be reachable IN-APP**, not
/// merely linked from the store listing — that requirement is why Help &
/// About exists at all, alongside Meta's WhatsApp Business review asking
/// for support contact details. Two external approvals depend on this
/// screen; don't remove either link.
const String kTermsUrl = 'https://www.nagarva.in/terms';
const String kPrivacyPolicyUrl = 'https://www.nagarva.in/privacy-policy';

/// App version shown in Help & About.
///
/// Deliberately NOT `package_info_plus` — that would be a new dependency,
/// and this project pins exact versions FlutterFlow-style with a pinned
/// SDK (see CLAUDE.md's environment rules), so adding one is never
/// casual. Instead this follows the same `--dart-define` pattern
/// [kPublicBaseUrl] above already uses:
///
///   flutter build apk --release --dart-define=NAGARVA_APP_VERSION=1.0.1+4
///
/// The default tracks `pubspec.yaml`'s `version:` field and must be
/// bumped with it — a release built without the define shows this
/// string, so a stale default is a wrong version number in front of a
/// vendor, not a crash.
const String kAppVersion = String.fromEnvironment(
  'NAGARVA_APP_VERSION',
  defaultValue: '1.0.0+1',
);

/// One-line positioning used on Help & About and anywhere else the
/// product introduces itself.
const String kNagarvaTagline =
    'Industry ERP for packers & movers — jobs, fleet, staff and GST '
    'billing in one place.';

/// Nagarva's own support line — the PLATFORM's number, not a tenant's.
///
/// **Currently empty on purpose.** Arun is setting up a dedicated
/// WhatsApp Business line (18 Aug 2026), deliberately separate from APC's
/// customer line: Nagarva is pan-India, so lapsed-trial contact arrives
/// at any hour and must not land on the mover's own business phone. Until
/// he hands the number over, every consumer below must degrade to plain
/// text with **no dead button** — a contact affordance that goes nowhere
/// is worse than none, especially for a vendor whose trial just ended.
///
/// Guard every use with [hasNagarvaSupportPhone] rather than testing the
/// string inline, so switching it on is one edit here and nothing else.
///
/// WHERE THIS IS (OR WILL BE) NEEDED — keep this list current, the whole
/// point is that wiring the number is one change, not a hunt:
///   1. `plan_page_widget.dart` — the activation CTA. Live text today,
///      becomes a "Chat with support" WhatsApp button. **Built and
///      waiting; see the comment at that call site.**
///   2. Settings → Help / About — this section does not exist yet
///      (grepped 18 Aug 2026: no About, Help or Support entry anywhere
///      in `settings_page_widget.dart`). It needs building, and the
///      support number is the reason to build it: support contact, app
///      version, and the privacy-policy link Phase 5 requires for the
///      Play Store and the Meta/WhatsApp API review.
///   3. The signup confirmation email — NOT in this repo. It's a Supabase
///      Auth email template, edited in the Dashboard under
///      Authentication → Email Templates, so it needs updating there by
///      hand rather than in code. Noted here because it's the easiest
///      one to forget precisely because it isn't a file.
///   4. The trial banner in `main.dart` (`_withTrialBanner`) currently
///      routes to PlanPage, which is correct — it should keep doing that
///      rather than opening WhatsApp directly, so there's one place a
///      vendor learns what their plan is and how to change it.
const String kNagarvaSupportPhone = '';

/// True once [kNagarvaSupportPhone] is set. Every support-contact
/// affordance in the app is gated on this.
bool get hasNagarvaSupportPhone => kNagarvaSupportPhone.trim().isNotEmpty;

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

// ---------------------------------------------------------------------------
// Which public pages are ACTUALLY HOSTED on kPublicBaseUrl
// ---------------------------------------------------------------------------
//
// The app can mint a token link for four customer-facing paths, but
// link.nagarva.in only serves some of them. A button that hands a
// customer a dead link is the same class of trust damage as the invented
// demo data was — the vendor looks incompetent in front of their own
// customer, and they cannot tell it was our fault.
//
// So these flags gate the SHARE AFFORDANCE, not the code behind it. The
// pages and token plumbing are built and correct; they are simply not
// hosted yet. Nobody should delete SurveyPage/QuotePage/SignPage/
// TrackPage on the strength of these being false.
//
// Flip to true the moment the corresponding page is live, and verify by
// opening a real token link in a browser first — not by reading the
// deploy log.
//
// Status, 19 Aug 2026:
//   survey  — hosted (hand-written static site; restored after the
//             drag-drop incident)
//   sign    — hosted (same site)
//   quote   — NEVER hosted by anything, at any point. No public_* RPC for
//             quotations exists either, so this needs a page AND an RPC.
//   track   — not deployed yet. This repo has a working TrackPage widget;
//             it has simply never been hosted anywhere.
const bool kSurveyLinkHosted = true;
const bool kSignLinkHosted = true;
const bool kQuoteLinkHosted = false;
const bool kTrackLinkHosted = false;
