/// The document-numbering prefix a vendor's invoices, receipts and
/// quotations print under.
///
/// This is the vendor's own document identity, and it has to be unique
/// across tenants: before 2 Sep 2026 `seed_org_number_series()` handed
/// every org the identical calendar-year prefix at `last_number = 0`, so
/// every org's first invoice rendered as the same string. The counters
/// were isolated per org the whole time; the printed number was not.
///
/// Two halves, and the split is forced by RLS rather than chosen:
///
///  * **Format** is checked here, client-side, so a typo is caught while
///    the field still has focus. It mirrors the DB CHECK exactly — if the
///    two ever disagree the DB wins and the vendor sees a raw Postgres
///    error, so [validateDocPrefix] and `number_series_prefix_format`
///    must be edited together.
///  * **Uniqueness** cannot be checked here at all. `number_series` is
///    RLS-scoped per org, so a client literally cannot see another
///    tenant's prefixes — asking it would always return "free". It goes
///    through the `check_doc_prefix` RPC (SECURITY DEFINER), and is
///    enforced for real by a BEFORE INSERT/UPDATE trigger so a request
///    that skips the app cannot take a prefix either.
library;

/// Maximum prefix length.
///
/// Rule 46(b) caps a tax-invoice number at 16 characters. `padding` is 4,
/// so the prefix may use at most 12 — which is exactly `ABC/2026-27/`.
/// This is a statutory ceiling, not a round number: raising it produces
/// document numbers that are not compliant.
const int kDocPrefixMaxLength = 12;

/// Mirrors the `number_series_prefix_format` CHECK constraint.
final RegExp _kDocPrefixPattern = RegExp(r'^[A-Za-z0-9/-]{1,12}$');

/// Returns null when [raw] is a usable prefix, else the reason to show.
///
/// An empty prefix is NOT an error: leaving the field blank keeps the
/// per-org default that seeding derived from the org's slug, which is
/// already unique. Blank means "no opinion", not "invalid".
String? validateDocPrefix(String raw) {
  final prefix = raw.trim();
  if (prefix.isEmpty) return null;
  if (prefix.length > kDocPrefixMaxLength) {
    return 'Invoice prefix must be $kDocPrefixMaxLength characters or fewer '
        '(a tax invoice number is capped at 16, and 4 are the running '
        'number). "$prefix" is ${prefix.length}.';
  }
  if (!_kDocPrefixPattern.hasMatch(prefix)) {
    return 'Invoice prefix can use letters, numbers, / and - only.';
  }
  return null;
}

/// Interprets the `check_doc_prefix` RPC result.
///
/// The RPC returns NULL when the prefix is free and a sentence explaining
/// the clash when it is not. Returns null when available, else the reason.
///
/// A non-string, non-null body is treated as a REJECTION rather than as
/// availability. That direction is deliberate: this gate decides whether a
/// vendor may take a document identity, and failing open on an unexpected
/// shape would hand out a duplicate silently — the exact failure the whole
/// mechanism exists to stop.
String? docPrefixRejection(Object? rpcResult) {
  if (rpcResult == null) return null;
  if (rpcResult is String) {
    final msg = rpcResult.trim();
    return msg.isEmpty ? null : msg;
  }
  return 'Could not verify that this invoice prefix is free. '
      'Your other details were saved; the default prefix is still in use.';
}
