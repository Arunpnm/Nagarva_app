import '/app_session.dart';

/// The name the VENDOR trades under — never the platform's.
///
/// Arun, 8 Sept 2026: "nagarva is the software vendor using for their
/// business so we have to make sure once they have subscribed and
/// purchase the plan and using paid version then nagarva should not come
/// in any place only their (vendor) name in all places."
///
/// This exists because the rule kept being broken the same way. Fourteen
/// call sites wrote `AppSession.instance.currentOrgName ?? 'Nagarva'` —
/// each one individually reasonable ("we need *something* if the name is
/// missing"), and collectively a guarantee that a customer of Arun
/// Packers eventually reads the name of a company they have never dealt
/// with, on their own invoice, WhatsApp message or review request. They
/// cannot tell the document is genuine, and the vendor looks like they
/// are trading under someone else's name.
///
/// **The platform is never the fallback.** An empty slot reads as plain;
/// the wrong company reads as the wrong company. Which neutral form to
/// fall back to depends on where the name is going, hence two getters
/// rather than one — a blank is right on a letterhead and broken in the
/// middle of a sentence.
///
/// Note the fallback is close to unreachable in practice: a vendor is
/// signed in and their org name is loaded. It matters anyway, because the
/// one time it fires is the one time nobody is watching.
class VendorIdentity {
  VendorIdentity._();

  /// The vendor's trading name, or null when it genuinely is not known.
  ///
  /// Null rather than a placeholder, so a caller must decide what absence
  /// means for its own surface instead of inheriting someone else's
  /// guess.
  static String? get name {
    final n = AppSession.instance.currentOrgName?.trim();
    return (n == null || n.isEmpty) ? null : n;
  }

  /// For a document letterhead, a heading, a title — anywhere the name
  /// stands alone.
  ///
  /// Falls back to EMPTY. A document with no letterhead reads as plain
  /// stationery; a document headed with the wrong company is a document
  /// that says the goods were moved by someone else.
  static String get forDocument => name ?? '';

  /// For running text sent to a customer — "this is X", "thank you for
  /// choosing X".
  ///
  /// Falls back to "us", which is the one substitution that leaves every
  /// such sentence grammatical and true. A blank would produce "thank you
  /// for choosing !" and the platform's name would produce a lie.
  static String get forSentence => name ?? 'us';
}
