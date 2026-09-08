/// Whether a tax invoice this org issues would satisfy Rule 46.
///
/// Rule 46 of the CGST Rules requires a tax invoice to carry the
/// supplier's NAME, ADDRESS and GSTIN. The first version of this check
/// looked at `address` alone, which meant it passed an invoice carrying a
/// **fabricated** GSTIN — the exact case live data contained: APC
/// Bengaluru holds `29AAAAA0000A1Z5`, the specimen number from GST
/// documentation.
///
/// Deliberately NOT checked: two orgs sharing a GSTIN. One registration
/// covers multiple places of business within a state, so APC Coimbatore
/// carrying its parent's number is lawful — warning on it would fire on
/// a correct setup, and a warning nobody believes is worse than no
/// warning. The error worth catching in that family is a GSTIN whose
/// state does not match the org's, which [checkInvoiceCompliance]
/// already reports once `state_code` is filled in.
///
/// **A missing field and a false one are different failures, and this
/// file keeps them apart.** An incomplete invoice is unfinished
/// paperwork: annoying, fixable, and obvious to everyone once seen. An
/// invoice bearing a GSTIN the vendor does not hold is a document
/// asserting a tax registration that is not theirs — it travels into the
/// customer's GSTR-2B, fails to reconcile against anything, and the
/// customer loses the input credit while the vendor has made a written
/// statement to the tax authority. Folding that into "your profile is
/// incomplete" would be the single most misleading thing this check could
/// do, so the two never share wording.
///
/// Everything here is a WARNING, never a block — see
/// `_generateInvoice`'s own comment for why refusing to issue is not this
/// app's call to make.
library;

import '/components/pdf_branding.dart';

/// The PAN segment of the specimen GSTIN used throughout GST
/// documentation and every "sample invoice" template on the internet.
///
/// It is the single most likely wrong-but-plausible value to end up in a
/// vendor's profile, because it is what they see when they look up what a
/// GSTIN is meant to look like. It passes [kGstinPattern] perfectly,
/// which is precisely why a format check alone is not enough.
const String kSpecimenPanSegment = 'AAAAA0000A';

/// Structural shape of a GSTIN: 2-digit state code, 10-char PAN, entity
/// digit, literal 'Z', checksum char.
///
/// Deliberately NOT a checksum validation. This catches typos and
/// nonsense; a full check-digit implementation would reject real numbers
/// on an implementation slip of ours, and being wrong in that direction —
/// telling a vendor their genuine GSTIN is invalid — is worse than
/// missing a rare bad one.
final RegExp kGstinPattern =
    RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$');

enum InvoiceComplianceKind {
  /// Rule 46 fields that are blank.
  incompleteProfile,

  /// Present, but not shaped like a GSTIN at all.
  gstinMalformed,

  /// Well-formed and famous: the documentation specimen.
  gstinSpecimen,

  /// The org's own state code disagrees with the one inside its GSTIN.
  stateCodeMismatch,
}

class InvoiceComplianceIssue {
  const InvoiceComplianceIssue({
    required this.kind,
    required this.title,
    required this.message,
    this.fields = const [],
  });

  final InvoiceComplianceKind kind;

  /// Dialog heading. Distinct per kind on purpose.
  final String title;
  final String message;

  /// Populated for [InvoiceComplianceKind.incompleteProfile] only.
  final List<String> fields;

  /// A false GSTIN is a different conversation from an unfinished
  /// profile, and the caller words the action button accordingly.
  bool get isFalseDocument =>
      kind == InvoiceComplianceKind.gstinMalformed ||
      kind == InvoiceComplianceKind.gstinSpecimen;
}

/// `nullif(trim(x), '')` semantics — a field of spaces is not a field.
String? _present(String? v) {
  final t = (v ?? '').trim();
  return t.isEmpty ? null : t;
}

/// Every Rule 46 problem with [org], most serious first.
///
/// Pure so it can be exercised directly; see
/// `test/invoice_compliance_test.dart`, which runs a fixture per branch
/// rather than reasoning about them.
List<InvoiceComplianceIssue> checkInvoiceCompliance(OrgProfile org) {
  final issues = <InvoiceComplianceIssue>[];
  final gstin = _present(org.gstin)?.toUpperCase();

  // ---- A false GSTIN outranks a blank one. ------------------------------
  if (gstin != null) {
    if (!kGstinPattern.hasMatch(gstin)) {
      issues.add(InvoiceComplianceIssue(
        kind: InvoiceComplianceKind.gstinMalformed,
        title: 'This GSTIN is not valid',
        message:
            '"$gstin" is not a valid GSTIN. A GSTIN is 15 characters: two '
            'state digits, a 10-character PAN, then three more.\n\n'
            'An invoice carrying a GSTIN that does not exist is worse than '
            'one carrying none — your customer cannot claim input credit '
            'on it, and the number is a statement to the tax authority.',
      ));
    } else if (gstin.substring(2, 12) == kSpecimenPanSegment) {
      issues.add(const InvoiceComplianceIssue(
        kind: InvoiceComplianceKind.gstinSpecimen,
        title: 'This is a specimen GSTIN, not yours',
        message:
            'This GSTIN contains the PAN "$kSpecimenPanSegment" — the '
            'example used in GST documentation and sample invoices, not a '
            'real registration.\n\n'
            'Issuing an invoice with it asserts a tax registration you do '
            'not hold. Replace it with your own GSTIN before invoicing.',
      ));
    }

    // ---- State code vs the state inside the GSTIN. ----------------------
    // Only when the GSTIN starts with two real digits; on a malformed
    // number the leading pair means nothing and comparing it would raise a
    // second, confusing complaint about the same field.
    final leading = RegExp(r'^[0-9]{2}').stringMatch(gstin);
    final declared = org.stateCode;
    if (leading != null && declared != null && declared != int.parse(leading)) {
      issues.add(InvoiceComplianceIssue(
        kind: InvoiceComplianceKind.stateCodeMismatch,
        title: 'State code does not match your GSTIN',
        message:
            'Your profile says state code $declared, but this GSTIN is '
            'registered in state $leading. One of the two is wrong.\n\n'
            'The state code decides whether an invoice is taxed CGST+SGST '
            'or IGST, so a mismatch changes what you charge.',
      ));
    }
  }

  // ---- Rule 46's required fields. ---------------------------------------
  final missing = <String>[
    if (_present(org.name) == null) 'business name',
    if (_present(org.address) == null) 'address',
    if (_present(org.city) == null) 'city',
    if (_present(org.state) == null) 'state',
    if (org.stateCode == null) 'state code',
    if (_present(org.pincode) == null) 'PIN code',
    if (gstin == null) 'GSTIN',
  ];

  if (missing.isNotEmpty) {
    issues.add(InvoiceComplianceIssue(
      kind: InvoiceComplianceKind.incompleteProfile,
      title: 'Invoice is missing required details',
      fields: missing,
      message:
          'A tax invoice must show your ${missing.join(', ')}. Without '
          '${missing.length == 1 ? 'it' : 'them'} your customer may not be '
          'able to claim input credit on this invoice.\n\n'
          'Add ${missing.length == 1 ? 'it' : 'them'} once in Settings → '
          'Business and every document from then on carries '
          '${missing.length == 1 ? 'it' : 'them'}.',
    ));
  }

  return issues;
}
